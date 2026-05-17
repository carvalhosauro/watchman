defmodule Watchman.Models.PriceSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "price_snapshots" do
    field :price, :float
    field :variation_day, :float
    field :variation_week, :float
    field :variation_month, :float
    field :fetched_at, :utc_datetime

    belongs_to :asset, Watchman.Models.Asset
  end

  def changeset(price_snapshot, attrs) do
    price_snapshot
    |> cast(attrs, [:asset_id, :price, :variation_day, :variation_week, :variation_month, :fetched_at])
    |> validate_required([:price])
    |> assoc_constraint(:asset)
  end
end
