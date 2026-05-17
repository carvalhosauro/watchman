defmodule Watchman.Models.AnalysisTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.{Asset, Analysis}
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, asset} =
      Repo.insert(Asset.changeset(%Asset{}, %{ticker: "TEST1"}))

    %{asset: asset}
  end

  describe "changeset/2" do
    test "valid changeset with asset_id and recommendation", %{asset: asset} do
      changeset = Analysis.changeset(%Analysis{}, %{asset_id: asset.id, recommendation: "manter"})
      assert changeset.valid?
    end

    test "validates recommendation - manter is valid", %{asset: asset} do
      changeset = Analysis.changeset(%Analysis{}, %{asset_id: asset.id, recommendation: "manter"})
      assert changeset.valid?
    end

    test "validates recommendation - investigar is valid", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{asset_id: asset.id, recommendation: "investigar"})

      assert changeset.valid?
    end

    test "validates recommendation - vender is valid", %{asset: asset} do
      changeset = Analysis.changeset(%Analysis{}, %{asset_id: asset.id, recommendation: "vender"})
      assert changeset.valid?
    end

    test "rejects invalid recommendation", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{asset_id: asset.id, recommendation: "comprar"})

      refute changeset.valid?

      assert {:recommendation,
              {"is invalid", [validation: :inclusion, enum: ["manter", "investigar", "vender"]]}} in changeset.errors
    end

    test "requires recommendation", %{asset: asset} do
      changeset = Analysis.changeset(%Analysis{}, %{asset_id: asset.id})
      refute changeset.valid?
      assert {:recommendation, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "accepts nil cause", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter",
          cause: nil
        })

      assert changeset.valid?
    end

    test "accepts nil macro_context", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter",
          macro_context: nil
        })

      assert changeset.valid?
    end

    test "accepts nil justification", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter",
          justification: nil
        })

      assert changeset.valid?
    end

    test "accepts nil tokens_used and cost_usd", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter",
          tokens_used: nil,
          cost_usd: nil
        })

      assert changeset.valid?
    end
  end
end
