defmodule Watchman.Models.NewsItemTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.{Asset, NewsItem}
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, asset} =
      Repo.insert(Asset.changeset(%Asset{}, %{ticker: "TEST1"}))

    base_attrs = %{
      asset_id: asset.id,
      source: "cvm",
      category: "material_fact"
    }

    %{asset: asset, base_attrs: base_attrs}
  end

  describe "changeset/2" do
    test "valid with source + category", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, attrs)
      assert changeset.valid?
    end

    test "title is optional", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, Map.put(attrs, :title, nil))
      assert changeset.valid?
    end

    test "summary is optional", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, Map.put(attrs, :summary, nil))
      assert changeset.valid?
    end

    test "url is optional", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, Map.put(attrs, :url, nil))
      assert changeset.valid?
    end

    test "published_at is optional", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, Map.put(attrs, :published_at, nil))
      assert changeset.valid?
    end

    test "fetched_at is optional", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, Map.put(attrs, :fetched_at, nil))
      assert changeset.valid?
    end

    test "valid with all fields", %{base_attrs: attrs} do
      full =
        Map.merge(attrs, %{
          title: "Some news",
          summary: "A brief summary",
          url: "https://example.com/news",
          published_at: ~U[2026-01-01 10:00:00Z],
          fetched_at: ~U[2026-01-01 11:00:00Z]
        })

      changeset = NewsItem.changeset(%NewsItem{}, full)
      assert changeset.valid?
    end

    test "source is required", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, Map.delete(attrs, :source))
      refute changeset.valid?
      assert {:source, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "category is required", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, Map.delete(attrs, :category))
      refute changeset.valid?
      assert {:category, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "rejects unknown source", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, %{attrs | source: "yahoo"})
      refute changeset.valid?

      assert {:source, {"is invalid", [validation: :inclusion, enum: _]}} =
               List.keyfind(changeset.errors, :source, 0)
    end

    test "rejects unknown category", %{base_attrs: attrs} do
      changeset = NewsItem.changeset(%NewsItem{}, %{attrs | category: "earnings"})
      refute changeset.valid?

      assert {:category, {"is invalid", [validation: :inclusion, enum: _]}} =
               List.keyfind(changeset.errors, :category, 0)
    end

    test "accepts each whitelisted source", %{base_attrs: attrs} do
      for source <- NewsItem.sources() do
        changeset = NewsItem.changeset(%NewsItem{}, %{attrs | source: source})
        assert changeset.valid?, "#{source} should be valid"
      end
    end

    test "accepts each whitelisted category", %{base_attrs: attrs} do
      for category <- NewsItem.categories() do
        changeset = NewsItem.changeset(%NewsItem{}, %{attrs | category: category})
        assert changeset.valid?, "#{category} should be valid"
      end
    end
  end
end
