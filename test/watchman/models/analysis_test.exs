defmodule Watchman.Models.AnalysisTest do
  use ExUnit.Case, async: true

  alias Watchman.Analysis.Signal
  alias Watchman.Models.{Analysis, Asset}
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

  describe "signal columns" do
    test "valid changeset with all 4 signal fields set", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter",
          signal_level: "high",
          signal_direction: "bullish",
          signal_reasons: Jason.encode!(["RSI oversold", "volume spike"]),
          signal_confidence: 0.85
        })

      assert changeset.valid?
    end

    test "changeset without signal fields is valid (DB defaults apply on insert)", %{asset: asset} do
      # Pure changeset with no signal fields is valid — inclusion validators
      # only fire when a value is present. The migration's column defaults
      # (noise / neutral / [] / 0.0) are applied by the DB on insert.
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter"
        })

      assert changeset.valid?
    end

    test "DB defaults applied on insert when signal fields omitted", %{asset: asset} do
      {:ok, record} =
        %Analysis{}
        |> Analysis.changeset(%{asset_id: asset.id, recommendation: "manter"})
        |> Repo.insert()

      # The inserted struct returns nil for fields not in the changeset;
      # the DB fills them with column defaults. Fetch back to verify.
      fetched = Repo.get!(Analysis, record.id)
      assert fetched.signal_level == "noise"
      assert fetched.signal_direction == "neutral"
      assert fetched.signal_reasons == "[]"
      assert fetched.signal_confidence == 0.0
    end

    test "rejects invalid signal_level", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter",
          signal_level: "extreme"
        })

      refute changeset.valid?

      valid_levels = Enum.map(Signal.levels(), &Atom.to_string/1)

      assert {:signal_level, {"is invalid", [validation: :inclusion, enum: valid_levels]}} in changeset.errors
    end

    test "rejects invalid signal_direction", %{asset: asset} do
      changeset =
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          recommendation: "manter",
          signal_direction: "sideways"
        })

      refute changeset.valid?

      valid_directions = Enum.map(Signal.directions(), &Atom.to_string/1)

      assert {:signal_direction, {"is invalid", [validation: :inclusion, enum: valid_directions]}} in changeset.errors
    end

    test "round-trip: signal_reasons JSON string stored and fetched unchanged", %{asset: asset} do
      reasons_json = Jason.encode!(["MACD crossover", "news sentiment positive"])

      {:ok, record} =
        %Analysis{}
        |> Analysis.changeset(%{
          asset_id: asset.id,
          recommendation: "investigar",
          signal_level: "medium",
          signal_direction: "bullish",
          signal_reasons: reasons_json,
          signal_confidence: 0.6
        })
        |> Repo.insert()

      fetched = Repo.get!(Analysis, record.id)
      assert fetched.signal_reasons == reasons_json
    end

    test "signal_confidence accepts boundary floats 0.0 and 1.0", %{asset: asset} do
      for confidence <- [0.0, 1.0] do
        changeset =
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            recommendation: "manter",
            signal_level: "low",
            signal_direction: "neutral",
            signal_reasons: "[]",
            signal_confidence: confidence
          })

        assert changeset.valid?, "Expected valid changeset for confidence=#{confidence}"
      end
    end

    test "all Signal.levels/0 values are valid signal_level", %{asset: asset} do
      for level <- Signal.levels() do
        changeset =
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            recommendation: "manter",
            signal_level: Atom.to_string(level)
          })

        assert changeset.valid?, "Expected valid changeset for level=#{level}"
      end
    end

    test "all Signal.directions/0 values are valid signal_direction", %{asset: asset} do
      for direction <- Signal.directions() do
        changeset =
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            recommendation: "manter",
            signal_direction: Atom.to_string(direction)
          })

        assert changeset.valid?, "Expected valid changeset for direction=#{direction}"
      end
    end
  end
end
