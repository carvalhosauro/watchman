defmodule Watchman.Models.NewsItemTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.{Asset, NewsItem}
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, asset} =
      Repo.insert(Asset.changeset(%Asset{}, %{ticker: "TEST1"}))

    %{asset: asset}
  end

  describe "changeset/2" do
    test "valid changeset with asset_id", %{asset: asset} do
      changeset = NewsItem.changeset(%NewsItem{}, %{asset_id: asset.id})
      assert changeset.valid?
    end

    test "title is optional", %{asset: asset} do
      changeset = NewsItem.changeset(%NewsItem{}, %{asset_id: asset.id, title: nil})
      assert changeset.valid?
    end

    test "summary is optional", %{asset: asset} do
      changeset = NewsItem.changeset(%NewsItem{}, %{asset_id: asset.id, summary: nil})
      assert changeset.valid?
    end

    test "source is optional", %{asset: asset} do
      changeset = NewsItem.changeset(%NewsItem{}, %{asset_id: asset.id, source: nil})
      assert changeset.valid?
    end

    test "url is optional", %{asset: asset} do
      changeset = NewsItem.changeset(%NewsItem{}, %{asset_id: asset.id, url: nil})
      assert changeset.valid?
    end

    test "published_at is optional", %{asset: asset} do
      changeset = NewsItem.changeset(%NewsItem{}, %{asset_id: asset.id, published_at: nil})
      assert changeset.valid?
    end

    test "fetched_at is optional", %{asset: asset} do
      changeset = NewsItem.changeset(%NewsItem{}, %{asset_id: asset.id, fetched_at: nil})
      assert changeset.valid?
    end

    test "valid with all fields", %{asset: asset} do
      attrs = %{
        asset_id: asset.id,
        title: "Some news",
        summary: "A brief summary",
        source: "InfoMoney",
        url: "https://example.com/news",
        published_at: ~U[2026-01-01 10:00:00Z],
        fetched_at: ~U[2026-01-01 11:00:00Z]
      }

      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end
  end
end
