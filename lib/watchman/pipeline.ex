defmodule Watchman.Pipeline do
  @moduledoc """
  Parallel asset analysis orchestrator. Track 4 (v0.6.0) wires the
  deterministic classifier into the per-asset loop and demotes the AI
  provider to optional narrative enrichment.

  For each active asset, the pipeline:

    1. Closes any pending accuracy outcomes (Track 1).
    2. Fetches the latest price (Track 0 — `Market.Provider`).
    3. Persists the new `PriceSnapshot`.
    4. Fetches news from every configured `News.Provider` adapter (Track 3).
    5. Loads the last #{50} price snapshots from the DB.
    6. Computes `%Indicators{}` over `[new_snapshot | history]` (Track 2).
    7. Classifies a deterministic `%Signal{}` (Track 4) via
       `Watchman.Analysis.Classifier.classify/2`.
    8. Calls the configured AI provider with `analyze/4`, passing the
       signal + news as enrichment context. The AI's job is to narrate,
       not to re-classify. On AI failure the pipeline falls back to
       `Watchman.Analysis.SignalFormatter` and records 0 tokens.
    9. Persists the analysis row with both the legacy
       `recommendation` / `justification` fields and the four new
       `signal_*` columns.
   10. Persists merged news (Track 3 adapters + any AI-fetched items),
       deduplicated by URL.
   11. Dispatches alerts via the existing recommendation-based path AND
       the new signal-based path (Track 4 alerts extension).

  Track 5 (v0.7.0) will move this orchestration out of the CLI into a
  GenServer scheduler. The internal shape of `analyze_asset/1` does not
  change — only the invocation site moves.
  """

  require Logger
  import Ecto.Query

  alias Watchman.AI.Shared, as: AIShared
  alias Watchman.Alerts.Dispatcher
  alias Watchman.Analysis.{Classifier, Indicators, SignalFormatter, Technical}
  alias Watchman.Market.{Brapi, BrapiUsage, Yfinance}
  alias Watchman.Models.{Analysis, Asset, NewsItem, PriceSnapshot}
  alias Watchman.Repo

  @history_window 50

  def run do
    close_pending_outcomes()
    maybe_warn_brapi_usage()
    assets = Repo.all(from a in Asset, where: a.active == true)

    if assets == [] do
      IO.puts("No tracked assets. Use: wm assets TICKER1 TICKER2")
      :ok
    else
      Logger.info("Starting analysis for #{length(assets)} assets")
      IO.puts("Analyzing #{length(assets)} assets...\n")

      results =
        assets
        |> Task.async_stream(&analyze_asset/1,
          max_concurrency: Watchman.Config.max_concurrency(),
          timeout: Watchman.Config.task_timeout(),
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> result
          {:exit, :timeout} -> {:error, "unknown", "timeout"}
          {:exit, reason} -> {:error, "unknown", inspect(reason)}
        end)

      print_summary(results)
    end
  end

  defp analyze_asset(asset) do
    today = Date.utc_today()

    if already_analyzed_today?(asset.id, today) do
      IO.puts("  ~ #{asset.ticker} (already analyzed today)")
      {:skip, asset.ticker}
    else
      do_analyze(asset)
    end
  end

  defp already_analyzed_today?(asset_id, date) do
    start_of_day = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_of_day = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    Repo.exists?(
      from a in Analysis,
        where: a.asset_id == ^asset_id,
        where: a.analyzed_at >= ^start_of_day,
        where: a.analyzed_at <= ^end_of_day
    )
  end

  defp do_analyze(asset) do
    with {:ok, price_data} <- fetch_price(asset),
         {:ok, snapshot} <- persist_snapshot(asset, price_data),
         news_items <- fetch_news(asset),
         history <- load_history(asset.id, snapshot.id),
         indicators <- compute_indicators([snapshot | history], asset),
         signal <- Classifier.classify(indicators, news_items),
         {:ok, analysis_data, ai_news} <- call_ai(asset, snapshot, signal, news_items),
         {:ok, _analysis} <- persist_analysis(asset, snapshot, signal, analysis_data),
         :ok <- persist_news(asset, merge_news(news_items, ai_news)) do
      log_success(asset, signal, analysis_data)
      dispatch_alerts(asset, signal, analysis_data)
      {:ok, asset.ticker, analysis_data.recommendation}
    else
      {:error, step, reason} ->
        report_failure(asset, step, reason)

      {:error, reason} ->
        report_failure(asset, :unknown, reason)
    end
  end

  defp fetch_price(asset) do
    provider = Watchman.Market.Factory.provider()

    case provider.fetch(asset.ticker) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        Logger.warning(
          "#{asset.ticker}: primary provider failed (#{inspect(reason)}), trying fallback"
        )

        try_fallback(provider, asset.ticker)
    end
  end

  defp try_fallback(Brapi, ticker), do: Yfinance.fetch(ticker)
  defp try_fallback(Yfinance, ticker), do: Brapi.fetch(ticker)
  defp try_fallback(_, _ticker), do: {:error, "all market providers failed"}

  # ---------------------------------------------------------------------------
  # Track 3: news fetch
  # ---------------------------------------------------------------------------

  defp fetch_news(asset) do
    Watchman.News.Factory.providers()
    |> Enum.flat_map(&fetch_from_provider(&1, asset))
    |> Enum.uniq_by(& &1.url)
  end

  defp fetch_from_provider(provider, asset) do
    case provider.fetch(asset.ticker, []) do
      {:ok, items} when is_list(items) ->
        items

      {:error, reason} ->
        Logger.warning(
          "News provider #{inspect(provider)} failed for #{asset.ticker}: #{inspect(reason)}"
        )

        []
    end
  end

  # ---------------------------------------------------------------------------
  # Track 2: history load + indicators
  # ---------------------------------------------------------------------------

  defp load_history(asset_id, exclude_snapshot_id) do
    from(ps in PriceSnapshot,
      where: ps.asset_id == ^asset_id,
      where: ps.id != ^exclude_snapshot_id,
      order_by: [desc: ps.fetched_at],
      limit: ^@history_window
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  defp compute_indicators(snapshots, asset) do
    case Technical.indicators(snapshots) do
      {:ok, indicators} ->
        indicators

      {:error, :insufficient_data} ->
        Logger.info(
          "#{asset.ticker}: insufficient history (#{length(snapshots)} snapshots); using neutral fallback"
        )

        fallback_indicators()
    end
  end

  defp fallback_indicators do
    %Indicators{
      sma7: 0.0,
      sma21: 0.0,
      sma50: 0.0,
      ema21: 0.0,
      rsi14: 50.0,
      zscore21: 0.0,
      streak: %{direction: :up, days: 0},
      drawdown_from_peak: 0.0
    }
  end

  # ---------------------------------------------------------------------------
  # AI enrichment (optional — falls back to SignalFormatter on failure)
  # ---------------------------------------------------------------------------

  defp call_ai(asset, snapshot, signal, news_items) do
    case Watchman.AI.Factory.provider().analyze(asset, snapshot, signal, news_items) do
      {:ok, attrs, items} ->
        {:ok, attrs, items}

      {:error, reason} ->
        Logger.warning(
          "#{asset.ticker}: AI failed (#{inspect(reason)}); using SignalFormatter fallback"
        )

        {:ok, ai_less_attrs(signal), []}
    end
  end

  defp ai_less_attrs(signal) do
    %{
      cause: nil,
      is_specific_problem: false,
      macro_context: nil,
      recommendation: AIShared.recommendation_from_signal(signal),
      justification: SignalFormatter.format(signal),
      tokens_used: 0
    }
  end

  # ---------------------------------------------------------------------------
  # Persistence
  # ---------------------------------------------------------------------------

  defp persist_snapshot(asset, price_data) do
    attrs = %{
      asset_id: asset.id,
      price: price_data.price,
      variation_day: price_data.variation_day,
      variation_week: price_data.variation_week,
      variation_month: price_data.variation_month,
      fetched_at: DateTime.utc_now()
    }

    case Repo.insert(PriceSnapshot.changeset(%PriceSnapshot{}, attrs)) do
      {:ok, snapshot} -> {:ok, snapshot}
      {:error, changeset} -> {:error, :persist_snapshot, inspect(changeset.errors)}
    end
  end

  defp persist_analysis(asset, snapshot, signal, analysis_data) do
    cost = (analysis_data.tokens_used || 0) * cost_per_mtok() / 1_000_000

    attrs = %{
      asset_id: asset.id,
      snapshot_id: snapshot.id,
      cause: analysis_data.cause,
      is_specific_problem: analysis_data.is_specific_problem,
      macro_context: analysis_data.macro_context,
      recommendation: analysis_data.recommendation,
      justification: analysis_data.justification,
      tokens_used: analysis_data.tokens_used,
      cost_usd: cost,
      analyzed_at: DateTime.utc_now(),
      signal_level: Atom.to_string(signal.level),
      signal_direction: Atom.to_string(signal.direction),
      signal_reasons: Jason.encode!(signal.reasons),
      signal_confidence: signal.confidence
    }

    case Repo.insert(Analysis.changeset(%Analysis{}, attrs)) do
      {:ok, analysis} -> {:ok, analysis}
      {:error, changeset} -> {:error, :persist_analysis, inspect(changeset.errors)}
    end
  end

  defp cost_per_mtok do
    case Watchman.AI.Factory.provider() do
      Watchman.AI.Claude -> 5.0
      Watchman.AI.Gemini -> 0.30
      Watchman.AI.Deepseek -> 1.10
      _ -> 5.0
    end
  end

  defp merge_news(track3_items, ai_items) do
    (track3_items ++ Enum.map(ai_items, &normalize_news_item/1))
    |> Enum.uniq_by(& &1.url)
  end

  defp normalize_news_item(%NewsItem{} = item), do: item
  defp normalize_news_item(%{} = map), do: struct(NewsItem, map)

  defp persist_news(asset, news_items) do
    now = DateTime.utc_now()
    valid_sources = NewsItem.sources()

    Enum.each(news_items, fn item ->
      attrs = build_news_attrs(item, asset.id, valid_sources, now)

      case Repo.insert(NewsItem.changeset(%NewsItem{}, attrs)) do
        {:ok, _} ->
          :ok

        {:error, changeset} ->
          Logger.warning(
            "Failed to persist news for #{asset.ticker}: #{inspect(changeset.errors)}"
          )
      end
    end)

    :ok
  end

  defp build_news_attrs(item, asset_id, valid_sources, now) do
    normalized_source =
      if Map.get(item, :source) in valid_sources, do: item.source, else: "unknown"

    %{
      asset_id: asset_id,
      title: Map.get(item, :title),
      summary: Map.get(item, :summary),
      source: normalized_source,
      category: Map.get(item, :category) || "other",
      url: Map.get(item, :url),
      published_at: Map.get(item, :published_at),
      fetched_at: now
    }
  end

  # ---------------------------------------------------------------------------
  # Outcome closer (Track 1) + brapi usage warning
  # ---------------------------------------------------------------------------

  defp close_pending_outcomes do
    case Watchman.Accuracy.close_pending_outcomes() do
      %{closed: 0} = stats ->
        Logger.debug("Accuracy: no outcomes to close (#{inspect(stats)})")
        stats

      %{closed: n} = stats ->
        Logger.info("Accuracy: closed #{n} outcomes")
        IO.puts("Closed #{n} past outcome(s)")
        stats
    end
  end

  defp maybe_warn_brapi_usage do
    if Watchman.Market.Factory.provider() == Brapi do
      case BrapiUsage.check_limit() do
        {:exceeded, count, limit} ->
          Logger.warning(
            "Brapi free tier: #{count}/#{limit} requests used this month — limit exceeded!"
          )

        {:warning, count, limit} ->
          Logger.warning("Brapi free tier: #{count}/#{limit} requests used this month")

        {:ok, _, _} ->
          :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Logging + alerts
  # ---------------------------------------------------------------------------

  defp log_success(asset, signal, analysis_data) do
    Logger.info(
      "#{asset.ticker}: #{signal.level} #{signal.direction} (#{analysis_data.tokens_used || 0} tokens)"
    )

    IO.puts("  ✓ #{asset.ticker} — #{signal.level} #{signal.direction}")
  end

  defp dispatch_alerts(asset, signal, analysis_data) do
    Dispatcher.maybe_notify(
      asset.ticker,
      analysis_data.recommendation,
      analysis_data.justification
    )

    Dispatcher.maybe_notify_signal(asset.ticker, signal)
  end

  defp report_failure(asset, step, reason) do
    Logger.error("#{asset.ticker}: failed at #{step} — #{inspect(reason)}")
    IO.puts("  ✗ #{asset.ticker} — failed at #{step}: #{inspect(reason)}")
    {:error, asset.ticker, "#{step}: #{inspect(reason)}"}
  end

  defp print_summary(results) do
    {ok, skip, fail} =
      Enum.reduce(results, {[], [], []}, fn
        {:ok, ticker, _rec}, {o, s, f} -> {[ticker | o], s, f}
        {:skip, ticker}, {o, s, f} -> {o, [ticker | s], f}
        {:error, ticker, _reason}, {o, s, f} -> {o, s, [ticker | f]}
      end)

    IO.puts("\n--- Summary ---")
    if ok != [], do: IO.puts("Analyzed: #{Enum.join(Enum.reverse(ok), ", ")}")
    if skip != [], do: IO.puts("Skipped:  #{Enum.join(Enum.reverse(skip), ", ")}")
    if fail != [], do: IO.puts("Failed:   #{Enum.join(Enum.reverse(fail), ", ")}")
  end
end
