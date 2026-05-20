defmodule Watchman.Accuracy do
  @moduledoc """
  Stores realized outcomes for analyses post-lookahead and provides the
  classification and reporting API for accuracy tracking.

  ## classify_outcome/3

  Pure function implementing the recommendation-vs-variation rule. Given a
  recommendation string and the observed price variation, returns `:hit`,
  `:miss`, or `:neutral`. `investigar` analyses always produce `:neutral` —
  they receive an audit record but are excluded from the global hit-rate
  denominator by default.

  ## close_pending_outcomes/0

  Scans all analyses whose lookahead window has elapsed (using
  `Watchman.Calendar.add_business_days/2` for business-day math), finds the
  most recent price snapshot after the lookahead target date, computes the
  realized variation, classifies the outcome, and persists it.

  Idempotent: the `UNIQUE(analysis_id)` constraint on `analysis_outcomes`
  prevents duplicate rows. If an outcome row already exists (e.g. a previous
  run or a concurrent worker), the insert fails with a unique-constraint
  error and that analysis is counted as `:skipped` rather than raising.
  Analyses with a nil `snapshot_id` are excluded from processing entirely.

  ## report/1

  Reads stored `AnalysisOutcome` rows and aggregates them into a summary
  map containing hit/miss/neutral counts and hit-rate, broken down by ticker
  and overall.

  Supports the following keyword filters:

    * `:ticker` — restrict to a single asset ticker (case-insensitive).
    * `:since` — only outcomes evaluated on or after this `Date`.
    * `:lookahead_days` — only outcomes recorded with this lookahead window.
    * `:include_neutral` — when `true`, neutral outcomes count in the
      hit-rate denominator (default `false`).
    * `:provider` — **not yet tracked in v0.3.0**. Passing this key logs a
      warning and the filter is silently ignored. `by_provider` is always
      returned as `[]`.

  `hit_rate` is computed as `hits / (hits + misses)` (or
  `hits / (hits + misses + neutral)` when `:include_neutral` is `true`).
  Returns `0.0` when the denominator is zero.
  """

  require Logger

  import Ecto.Query

  alias Watchman.Calendar
  alias Watchman.Config
  alias Watchman.Models.{Analysis, AnalysisOutcome, Asset, PriceSnapshot}
  alias Watchman.Repo

  @spec classify_outcome(String.t(), float(), float()) :: :hit | :miss | :neutral
  def classify_outcome("manter", variation_pct, drop_threshold_pct) do
    if variation_pct >= -drop_threshold_pct, do: :hit, else: :miss
  end

  def classify_outcome("vender", variation_pct, drop_threshold_pct) do
    if variation_pct <= -drop_threshold_pct, do: :hit, else: :miss
  end

  def classify_outcome("investigar", _variation_pct, _drop_threshold_pct), do: :neutral

  @spec close_pending_outcomes() :: %{closed: non_neg_integer(), skipped: non_neg_integer()}
  def close_pending_outcomes do
    lookahead_days = Config.accuracy_lookahead_days()
    drop_threshold_pct = Config.accuracy_drop_threshold_pct()
    today = Date.utc_today()

    candidates =
      from(a in Analysis,
        where: not is_nil(a.snapshot_id),
        preload: [:snapshot]
      )
      |> Repo.all()

    Enum.reduce(candidates, %{closed: 0, skipped: 0}, fn analysis, acc ->
      case close_one(analysis, lookahead_days, drop_threshold_pct, today) do
        :closed -> Map.update!(acc, :closed, &(&1 + 1))
        :skipped -> Map.update!(acc, :skipped, &(&1 + 1))
      end
    end)
  end

  @type report_opt ::
          {:ticker, String.t() | nil}
          | {:provider, String.t() | nil}
          | {:lookahead_days, integer() | nil}
          | {:since, Date.t() | nil}
          | {:include_neutral, boolean()}

  @spec report([report_opt()]) :: %{
          by_ticker: [
            %{
              ticker: String.t(),
              hits: non_neg_integer(),
              misses: non_neg_integer(),
              neutral: non_neg_integer(),
              hit_rate: float()
            }
          ],
          by_provider: [],
          overall: %{
            hits: non_neg_integer(),
            misses: non_neg_integer(),
            neutral: non_neg_integer(),
            hit_rate: float()
          },
          window: %{from: Date.t() | nil, to: Date.t() | nil, lookahead_days: integer() | nil}
        }
  def report(opts \\ []) do
    ticker = opts[:ticker]
    provider = opts[:provider]
    since_date = opts[:since]
    lookahead = opts[:lookahead_days]
    include_neutral = Keyword.get(opts, :include_neutral, false)

    if provider do
      Logger.warning(
        "provider filter requested but provider column not yet tracked in analyses; ignored"
      )
    end

    rows = fetch_outcome_rows(ticker, since_date, lookahead)

    %{
      by_ticker: aggregate_by_ticker(rows, include_neutral),
      by_provider: [],
      overall: compute_stats(rows, include_neutral),
      window: build_window(rows, lookahead)
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp close_one(analysis, lookahead_days, drop_threshold_pct, today) do
    analyzed_date = DateTime.to_date(analysis.analyzed_at)
    target_date = Calendar.add_business_days(analyzed_date, lookahead_days)

    if Date.compare(target_date, today) in [:lt, :eq] do
      do_close(analysis, target_date, lookahead_days, drop_threshold_pct)
    else
      :skipped
    end
  end

  defp do_close(analysis, target_date, lookahead_days, drop_threshold_pct) do
    baseline_price = analysis.snapshot.price

    case find_observed_snapshot(analysis.asset_id, target_date) do
      nil ->
        :skipped

      observed ->
        variation_pct = (observed.price - baseline_price) / baseline_price * 100.0

        outcome_atom =
          classify_outcome(analysis.recommendation, variation_pct, drop_threshold_pct)

        outcome_str = Atom.to_string(outcome_atom)

        attrs = %{
          analysis_id: analysis.id,
          observed_snapshot_id: observed.id,
          lookahead_days: lookahead_days,
          baseline_price: baseline_price,
          observed_price: observed.price,
          variation_pct: variation_pct,
          outcome: outcome_str,
          drop_threshold_pct: drop_threshold_pct,
          evaluated_at: DateTime.truncate(DateTime.utc_now(), :second)
        }

        case Repo.insert(AnalysisOutcome.changeset(%AnalysisOutcome{}, attrs)) do
          {:ok, _} ->
            Logger.info("Closed outcome for analysis #{analysis.id}: #{outcome_str}")
            :closed

          {:error, _changeset} ->
            :skipped
        end
    end
  end

  defp find_observed_snapshot(asset_id, target_date) do
    start_of_day = DateTime.new!(target_date, ~T[00:00:00], "Etc/UTC")

    Repo.one(
      from(ps in PriceSnapshot,
        where: ps.asset_id == ^asset_id,
        where: ps.fetched_at >= ^start_of_day,
        order_by: [desc: ps.fetched_at],
        limit: 1
      )
    )
  end

  defp fetch_outcome_rows(ticker, since_date, lookahead) do
    from(o in AnalysisOutcome,
      as: :outcome,
      join: a in Analysis,
      as: :analysis,
      on: a.id == o.analysis_id,
      join: asset in Asset,
      as: :asset,
      on: asset.id == a.asset_id,
      select: %{ticker: asset.ticker, outcome: o.outcome, evaluated_at: o.evaluated_at}
    )
    |> filter_ticker(ticker)
    |> filter_since(since_date)
    |> filter_lookahead(lookahead)
    |> Repo.all()
  end

  defp filter_ticker(query, nil), do: query

  defp filter_ticker(query, ticker),
    do: where(query, [asset: a], a.ticker == ^String.upcase(ticker))

  defp filter_since(query, nil), do: query

  defp filter_since(query, since) do
    start_dt = DateTime.new!(since, ~T[00:00:00], "Etc/UTC")
    where(query, [outcome: o], o.evaluated_at >= ^start_dt)
  end

  defp filter_lookahead(query, nil), do: query

  defp filter_lookahead(query, n),
    do: where(query, [outcome: o], o.lookahead_days == ^n)

  defp aggregate_by_ticker(rows, include_neutral) do
    rows
    |> Enum.group_by(& &1.ticker)
    |> Enum.map(fn {ticker, t_rows} ->
      t_rows |> compute_stats(include_neutral) |> Map.put(:ticker, ticker)
    end)
    |> Enum.sort_by(fn r -> {-r.hit_rate, r.ticker} end)
  end

  defp build_window(rows, lookahead) do
    dates = Enum.map(rows, &DateTime.to_date(&1.evaluated_at))

    {from, to} =
      case dates do
        [] -> {nil, nil}
        _ -> {Enum.min_by(dates, &Date.to_erl/1), Enum.max_by(dates, &Date.to_erl/1)}
      end

    %{from: from, to: to, lookahead_days: lookahead}
  end

  defp compute_stats(rows, include_neutral) do
    hits = Enum.count(rows, &(&1.outcome == "hit"))
    misses = Enum.count(rows, &(&1.outcome == "miss"))
    neutral = Enum.count(rows, &(&1.outcome == "neutral"))
    denom = if include_neutral, do: hits + misses + neutral, else: hits + misses
    hit_rate = if denom == 0, do: 0.0, else: hits / denom
    %{hits: hits, misses: misses, neutral: neutral, hit_rate: hit_rate}
  end
end
