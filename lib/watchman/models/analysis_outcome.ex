defmodule Watchman.Models.AnalysisOutcome do
  @moduledoc """
  Stores the realized outcome of an `Analysis` once its lookahead window has
  elapsed.

  Each row is the deterministic verdict on a past analysis: did the price move
  the way the recommendation implied, given a configurable drop threshold and
  lookahead window. Outcomes are persisted (not recomputed at query time) so
  `wm accuracy` is a pure read of stored data.

  Constraints (see `docs/track-1-accuracy.md`):

    * `analysis_id` is unique — one outcome per analysis. The future closer
      step relies on this for idempotency.
    * `outcome` is constrained to `"hit" | "miss" | "neutral"`.
    * `lookahead_days` must be a positive integer.
    * `drop_threshold_pct` must be non-negative.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @outcomes ~w(hit miss neutral)

  @type t :: %__MODULE__{}

  schema "analysis_outcomes" do
    field :lookahead_days, :integer
    field :baseline_price, :float
    field :observed_price, :float
    field :variation_pct, :float
    field :outcome, :string
    field :drop_threshold_pct, :float
    field :evaluated_at, :utc_datetime

    belongs_to :analysis, Watchman.Models.Analysis

    belongs_to :observed_snapshot,
               Watchman.Models.PriceSnapshot,
               foreign_key: :observed_snapshot_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(outcome, attrs) do
    outcome
    |> cast(attrs, [
      :analysis_id,
      :observed_snapshot_id,
      :lookahead_days,
      :baseline_price,
      :observed_price,
      :variation_pct,
      :outcome,
      :drop_threshold_pct,
      :evaluated_at
    ])
    |> validate_required([
      :analysis_id,
      :observed_snapshot_id,
      :lookahead_days,
      :baseline_price,
      :observed_price,
      :variation_pct,
      :outcome,
      :drop_threshold_pct,
      :evaluated_at
    ])
    |> validate_inclusion(:outcome, @outcomes)
    |> validate_number(:lookahead_days, greater_than: 0)
    |> validate_number(:drop_threshold_pct, greater_than_or_equal_to: 0.0)
    |> assoc_constraint(:analysis)
    |> assoc_constraint(:observed_snapshot)
    |> unique_constraint(:analysis_id)
  end
end
