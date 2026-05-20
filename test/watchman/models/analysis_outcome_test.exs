defmodule Watchman.Models.AnalysisOutcomeTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.{Analysis, AnalysisOutcome, Asset, PriceSnapshot}
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    {:ok, asset} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "OUT1"}))

    {:ok, baseline_snapshot} =
      Repo.insert(
        PriceSnapshot.changeset(%PriceSnapshot{}, %{
          asset_id: asset.id,
          price: 100.0,
          fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
      )

    {:ok, observed_snapshot} =
      Repo.insert(
        PriceSnapshot.changeset(%PriceSnapshot{}, %{
          asset_id: asset.id,
          price: 95.0,
          fetched_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
      )

    {:ok, analysis} =
      Repo.insert(
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset.id,
          snapshot_id: baseline_snapshot.id,
          recommendation: "vender",
          analyzed_at: DateTime.truncate(DateTime.utc_now(), :second)
        })
      )

    %{
      analysis: analysis,
      observed_snapshot: observed_snapshot,
      base_attrs: %{
        analysis_id: analysis.id,
        observed_snapshot_id: observed_snapshot.id,
        lookahead_days: 5,
        baseline_price: 100.0,
        observed_price: 95.0,
        variation_pct: -5.0,
        outcome: "hit",
        drop_threshold_pct: 3.0,
        evaluated_at: DateTime.truncate(DateTime.utc_now(), :second)
      }
    }
  end

  describe "changeset/2" do
    test "valid changeset with all required fields", %{base_attrs: attrs} do
      changeset = AnalysisOutcome.changeset(%AnalysisOutcome{}, attrs)
      assert changeset.valid?
    end

    test "requires analysis_id", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :analysis_id))

      refute changeset.valid?
      assert {:analysis_id, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires observed_snapshot_id", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(
          %AnalysisOutcome{},
          Map.delete(attrs, :observed_snapshot_id)
        )

      refute changeset.valid?

      assert {:observed_snapshot_id, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires lookahead_days", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :lookahead_days))

      refute changeset.valid?
      assert {:lookahead_days, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires baseline_price", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :baseline_price))

      refute changeset.valid?
      assert {:baseline_price, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires observed_price", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :observed_price))

      refute changeset.valid?
      assert {:observed_price, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires variation_pct", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :variation_pct))

      refute changeset.valid?
      assert {:variation_pct, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires outcome", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :outcome))

      refute changeset.valid?
      assert {:outcome, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires drop_threshold_pct", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :drop_threshold_pct))

      refute changeset.valid?

      assert {:drop_threshold_pct, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "requires evaluated_at", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, Map.delete(attrs, :evaluated_at))

      refute changeset.valid?
      assert {:evaluated_at, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "accepts outcome \"hit\"", %{base_attrs: attrs} do
      changeset = AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | outcome: "hit"})
      assert changeset.valid?
    end

    test "accepts outcome \"miss\"", %{base_attrs: attrs} do
      changeset = AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | outcome: "miss"})
      assert changeset.valid?
    end

    test "accepts outcome \"neutral\"", %{base_attrs: attrs} do
      changeset = AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | outcome: "neutral"})
      assert changeset.valid?
    end

    test "rejects unknown outcome", %{base_attrs: attrs} do
      changeset = AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | outcome: "maybe"})
      refute changeset.valid?

      assert {:outcome,
              {"is invalid", [validation: :inclusion, enum: ["hit", "miss", "neutral"]]}} in changeset.errors
    end

    test "rejects lookahead_days = 0", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | lookahead_days: 0})

      refute changeset.valid?

      assert {:lookahead_days,
              {"must be greater than %{number}",
               [validation: :number, kind: :greater_than, number: 0]}} in changeset.errors
    end

    test "rejects negative lookahead_days", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | lookahead_days: -3})

      refute changeset.valid?
    end

    test "rejects negative drop_threshold_pct", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | drop_threshold_pct: -1.0})

      refute changeset.valid?

      assert {:drop_threshold_pct,
              {"must be greater than or equal to %{number}",
               [
                 validation: :number,
                 kind: :greater_than_or_equal_to,
                 number: 0.0
               ]}} in changeset.errors
    end

    test "accepts drop_threshold_pct = 0.0", %{base_attrs: attrs} do
      changeset =
        AnalysisOutcome.changeset(%AnalysisOutcome{}, %{attrs | drop_threshold_pct: 0.0})

      assert changeset.valid?
    end
  end

  describe "Repo.insert/1" do
    test "persists a valid outcome", %{base_attrs: attrs} do
      assert {:ok, outcome} =
               Repo.insert(AnalysisOutcome.changeset(%AnalysisOutcome{}, attrs))

      assert outcome.id
      assert outcome.outcome == "hit"
      assert outcome.inserted_at
    end

    test "enforces unique analysis_id", %{base_attrs: attrs} do
      assert {:ok, _} =
               Repo.insert(AnalysisOutcome.changeset(%AnalysisOutcome{}, attrs))

      assert {:error, changeset} =
               Repo.insert(AnalysisOutcome.changeset(%AnalysisOutcome{}, attrs))

      assert {:analysis_id, {"has already been taken", _}} =
               List.keyfind(changeset.errors, :analysis_id, 0)
    end
  end
end
