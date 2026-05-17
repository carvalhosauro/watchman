defmodule Watchman.Models.NewsItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "news_items" do
    field :title, :string
    field :summary, :string
    field :source, :string
    field :url, :string
    field :published_at, :utc_datetime
    field :fetched_at, :utc_datetime

    belongs_to :asset, Watchman.Models.Asset
  end

  def changeset(news_item, attrs) do
    news_item
    |> cast(attrs, [:asset_id, :title, :summary, :source, :url, :published_at, :fetched_at])
    |> assoc_constraint(:asset)
  end
end
