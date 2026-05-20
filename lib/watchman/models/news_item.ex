defmodule Watchman.Models.NewsItem do
  @moduledoc """
  Persisted news item attached to an asset.

  From v0.5.0 onwards, `source` is a whitelisted identifier of the
  adapter that produced the item (`"cvm"`, `"infomoney"`, `"b3"`,
  `"valor"`, `"money_times"`, `"investnews"`, `"suno"`,
  `"brazil_journal"`, or `"unknown"` for legacy rows) and `category`
  groups items by document type (`"material_fact"`,
  `"financial_result"`, `"dividend"`, `"other"`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @sources ~w(
    cvm
    infomoney
    b3
    valor
    money_times
    investnews
    suno
    brazil_journal
    unknown
  )

  @categories ~w(material_fact financial_result dividend other)

  @type t :: %__MODULE__{}

  schema "news_items" do
    field :title, :string
    field :summary, :string
    field :source, :string
    field :url, :string
    field :published_at, :utc_datetime
    field :fetched_at, :utc_datetime
    field :category, :string

    belongs_to :asset, Watchman.Models.Asset
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(news_item, attrs) do
    news_item
    |> cast(attrs, [
      :asset_id,
      :title,
      :summary,
      :source,
      :url,
      :published_at,
      :fetched_at,
      :category
    ])
    |> validate_required([:source, :category])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:category, @categories)
    |> assoc_constraint(:asset)
  end

  @spec sources() :: [String.t()]
  def sources, do: @sources

  @spec categories() :: [String.t()]
  def categories, do: @categories
end
