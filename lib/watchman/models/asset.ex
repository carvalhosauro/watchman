defmodule Watchman.Models.Asset do
  use Ecto.Schema
  import Ecto.Changeset

  schema "assets" do
    field :ticker, :string
    field :name, :string
    field :type, :string  # "acao" or "fii"
    field :active, :boolean, default: true

    has_many :price_snapshots, Watchman.Models.PriceSnapshot
    has_many :news_items, Watchman.Models.NewsItem
    has_many :analyses, Watchman.Models.Analysis

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [:ticker, :name, :type, :active])
    |> validate_required([:ticker])
    |> validate_inclusion(:type, ~w(acao fii))
    |> unique_constraint(:ticker)
    |> update_change(:ticker, &String.upcase/1)
  end
end
