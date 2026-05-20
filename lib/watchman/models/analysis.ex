defmodule Watchman.Models.Analysis do
  @moduledoc """
  Ecto schema for the `analyses` table.

  Stores AI-generated analysis results for an asset at a given snapshot,
  including the deterministic signal classification introduced in v0.6.0.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Watchman.Analysis.Signal

  schema "analyses" do
    field :cause, :string
    field :is_specific_problem, :boolean
    field :macro_context, :string
    field :recommendation, :string
    field :justification, :string
    field :tokens_used, :integer
    field :cost_usd, :float
    field :analyzed_at, :utc_datetime

    # Signal classification columns (v0.6.0)
    field :signal_level, :string
    field :signal_direction, :string
    field :signal_reasons, :string
    field :signal_confidence, :float

    belongs_to :asset, Watchman.Models.Asset
    belongs_to :snapshot, Watchman.Models.PriceSnapshot, foreign_key: :snapshot_id
  end

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(analysis, attrs) do
    analysis
    |> cast(attrs, [
      :asset_id,
      :snapshot_id,
      :cause,
      :is_specific_problem,
      :macro_context,
      :recommendation,
      :justification,
      :tokens_used,
      :cost_usd,
      :analyzed_at,
      :signal_level,
      :signal_direction,
      :signal_reasons,
      :signal_confidence
    ])
    |> validate_required([:recommendation])
    |> validate_inclusion(:recommendation, ~w(manter investigar vender))
    |> validate_inclusion(:signal_level, Enum.map(Signal.levels(), &Atom.to_string/1))
    |> validate_inclusion(:signal_direction, Enum.map(Signal.directions(), &Atom.to_string/1))
    |> assoc_constraint(:asset)
    |> assoc_constraint(:snapshot)
  end
end
