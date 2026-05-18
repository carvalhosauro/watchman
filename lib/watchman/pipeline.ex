defmodule Watchman.Pipeline do
  @moduledoc "Parallel asset analysis orchestrator."

  require Logger

  alias Watchman.Market.{Brapi, BrapiUsage}
  alias Watchman.Models.{Analysis, Asset, NewsItem, PriceSnapshot}
  alias Watchman.Repo
  import Ecto.Query

  def run do
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

    # Idempotent: skip if already analyzed today
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
         {:ok, analysis_data, news_items} <- call_ai(asset, snapshot),
         {:ok, _analysis} <- persist_analysis(asset, snapshot, analysis_data),
         :ok <- persist_news(asset, news_items) do
      Logger.info(
        "#{asset.ticker}: #{analysis_data.recommendation} (#{analysis_data.tokens_used || 0} tokens)"
      )

      Watchman.Alerts.Dispatcher.maybe_notify(
        asset.ticker,
        analysis_data.recommendation,
        analysis_data.justification
      )

      IO.puts("  ✓ #{asset.ticker} — #{analysis_data.recommendation}")
      {:ok, asset.ticker, analysis_data.recommendation}
    else
      {:error, step, reason} ->
        Logger.error("#{asset.ticker}: failed at #{step} — #{inspect(reason)}")
        IO.puts("  ✗ #{asset.ticker} — failed at #{step}: #{inspect(reason)}")
        {:error, asset.ticker, "#{step}: #{inspect(reason)}"}

      {:error, reason} ->
        Logger.error("#{asset.ticker}: #{inspect(reason)}")
        IO.puts("  ✗ #{asset.ticker} — #{inspect(reason)}")
        {:error, asset.ticker, inspect(reason)}
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

  alias Watchman.Market.{Brapi, Yfinance}

  defp try_fallback(Brapi, ticker), do: Yfinance.fetch(ticker)
  defp try_fallback(Yfinance, ticker), do: Brapi.fetch(ticker)
  defp try_fallback(_, _ticker), do: {:error, "all market providers failed"}

  defp call_ai(asset, snapshot) do
    Watchman.AI.Factory.provider().analyze(asset, snapshot)
  end

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

  defp persist_analysis(asset, snapshot, analysis_data) do
    # Compute cost based on active provider's blended rate
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
      analyzed_at: DateTime.utc_now()
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
      Watchman.AI.DeepSeek -> 1.10
      _ -> 5.0
    end
  end

  defp persist_news(asset, news_items) do
    now = DateTime.utc_now()

    Enum.each(news_items, fn item ->
      attrs = %{
        asset_id: asset.id,
        title: item.title,
        summary: item.summary,
        source: item.source,
        url: item.url,
        published_at: item.published_at,
        fetched_at: now
      }

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
