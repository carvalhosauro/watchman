defmodule Watchman.Models.PriceSnapshotTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.{Asset, PriceSnapshot}
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, asset} =
      Repo.insert(Asset.changeset(%Asset{}, %{ticker: "TEST1"}))

    %{asset: asset}
  end

  describe "changeset/2" do
    test "valid changeset with price and asset_id", %{asset: asset} do
      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, %{price: 29.50, asset_id: asset.id})
      assert changeset.valid?
    end

    test "requires price", %{asset: asset} do
      changeset = PriceSnapshot.changeset(%PriceSnapshot{}, %{asset_id: asset.id})
      refute changeset.valid?
      assert {:price, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "accepts nil variation_day", %{asset: asset} do
      changeset =
        PriceSnapshot.changeset(%PriceSnapshot{}, %{
          price: 10.0,
          asset_id: asset.id,
          variation_day: nil
        })

      assert changeset.valid?
    end

    test "accepts nil variation_week", %{asset: asset} do
      changeset =
        PriceSnapshot.changeset(%PriceSnapshot{}, %{
          price: 10.0,
          asset_id: asset.id,
          variation_week: nil
        })

      assert changeset.valid?
    end

    test "accepts nil variation_month", %{asset: asset} do
      changeset =
        PriceSnapshot.changeset(%PriceSnapshot{}, %{
          price: 10.0,
          asset_id: asset.id,
          variation_month: nil
        })

      assert changeset.valid?
    end
  end
end
