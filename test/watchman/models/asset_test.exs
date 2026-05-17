defmodule Watchman.Models.AssetTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.Asset
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "changeset/2" do
    test "valid changeset with ticker" do
      changeset = Asset.changeset(%Asset{}, %{ticker: "PETR4"})
      assert changeset.valid?
    end

    test "ticker gets upcased" do
      changeset = Asset.changeset(%Asset{}, %{ticker: "petr4"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :ticker) == "PETR4"
    end

    test "validates type inclusion - acao is valid" do
      changeset = Asset.changeset(%Asset{}, %{ticker: "PETR4", type: "acao"})
      assert changeset.valid?
    end

    test "validates type inclusion - fii is valid" do
      changeset = Asset.changeset(%Asset{}, %{ticker: "HGLG11", type: "fii"})
      assert changeset.valid?
    end

    test "rejects invalid type" do
      changeset = Asset.changeset(%Asset{}, %{ticker: "PETR4", type: "invalid"})
      refute changeset.valid?

      assert {:type, {"is invalid", [validation: :inclusion, enum: ["acao", "fii"]]}} in changeset.errors
    end

    test "unique ticker constraint" do
      {:ok, _} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "UNIQ1"}))
      {:error, changeset} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "UNIQ1"}))

      assert {:ticker,
              {"has already been taken",
               [constraint: :unique, constraint_name: "assets_ticker_index"]}} in changeset.errors
    end

    test "default active is true" do
      {:ok, asset} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "DFLT1"}))
      assert asset.active == true
    end
  end
end
