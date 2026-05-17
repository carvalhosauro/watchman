defmodule Watchman.Models.Analysis do
  use Ecto.Schema
  import Ecto.Changeset

  schema "analyses" do
    field :cause, :string
    field :is_specific_problem, :boolean
    field :macro_context, :string
    field :recommendation, :string
    field :justification, :string
    field :tokens_used, :integer
    field :cost_usd, :float
    field :analyzed_at, :utc_datetime

    belongs_to :asset, Watchman.Models.Asset
    belongs_to :snapshot, Watchman.Models.PriceSnapshot, foreign_key: :snapshot_id
  end

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
      :analyzed_at
    ])
    |> validate_required([:recommendation])
    |> validate_inclusion(:recommendation, ~w(manter investigar vender))
    |> assoc_constraint(:asset)
    |> assoc_constraint(:snapshot)
  end
end
