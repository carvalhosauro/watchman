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
  """

  require Logger

  import Ecto.Query

  alias Watchman.Calendar
  alias Watchman.Config
  alias Watchman.Models.{Analysis, AnalysisOutcome, PriceSnapshot}
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
end
