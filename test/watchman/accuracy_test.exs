defmodule Watchman.AccuracyTest do
  # async: false because close_pending_outcomes/0 reads Date.utc_today() and
  # relies on wall-clock time; running serially avoids any fixture
  # interference with other time-sensitive test modules.
  use ExUnit.Case, async: false

  alias Watchman.Accuracy
  alias Watchman.Models.{Analysis, AnalysisOutcome, Asset, PriceSnapshot}
  alias Watchman.Repo

  # ---------------------------------------------------------------------------
  # Pure classifier tests (no DB)
  # ---------------------------------------------------------------------------

  describe "classify_outcome/3" do
    test "manter with positive variation is a hit" do
      assert Accuracy.classify_outcome("manter", 1.0, 3.0) == :hit
    end

    test "manter at -2.9 with threshold 3.0 is a hit (boundary inclusive)" do
      assert Accuracy.classify_outcome("manter", -2.9, 3.0) == :hit
    end

    test "manter at exactly -3.0 with threshold 3.0 is a hit (at threshold)" do
      assert Accuracy.classify_outcome("manter", -3.0, 3.0) == :hit
    end

    test "manter at -3.1 with threshold 3.0 is a miss" do
      assert Accuracy.classify_outcome("manter", -3.1, 3.0) == :miss
    end

    test "vender at -3.0 with threshold 3.0 is a hit" do
      assert Accuracy.classify_outcome("vender", -3.0, 3.0) == :hit
    end

    test "vender at -10.0 with threshold 3.0 is a hit" do
      assert Accuracy.classify_outcome("vender", -10.0, 3.0) == :hit
    end

    test "vender at -2.0 with threshold 3.0 is a miss" do
      assert Accuracy.classify_outcome("vender", -2.0, 3.0) == :miss
    end

    test "vender at +1.0 with threshold 3.0 is a miss" do
      assert Accuracy.classify_outcome("vender", 1.0, 3.0) == :miss
    end

    test "investigar is always neutral" do
      assert Accuracy.classify_outcome("investigar", 0.0, 3.0) == :neutral
    end

    test "investigar with extreme positive variation is neutral" do
      assert Accuracy.classify_outcome("investigar", 99.9, 3.0) == :neutral
    end

    test "investigar with extreme negative variation is neutral" do
      assert Accuracy.classify_outcome("investigar", -99.9, 3.0) == :neutral
    end

    test "unknown recommendation raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Accuracy.classify_outcome("comprar", 1.0, 3.0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # close_pending_outcomes/0 — sandbox-backed tests
  # ---------------------------------------------------------------------------

  describe "close_pending_outcomes/0" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

      {:ok, asset} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "CLTA3"}))
      {:ok, asset2} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "CLTB3"}))

      # Baseline snapshot — old, used as analysis.snapshot_id (price reference)
      {:ok, baseline} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 100.0,
            fetched_at: dt_days_ago(60)
          })
        )

      {:ok, baseline2} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset2.id,
            price: 100.0,
            fetched_at: dt_days_ago(60)
          })
        )

      # Recent observed snapshot for asset (10 days ago — after any 5-bday
      # lookahead target for an analysis from 30 days ago)
      {:ok, recent} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 95.0,
            fetched_at: dt_days_ago(10)
          })
        )

      # asset2 intentionally has NO recent snapshot (only baseline from 60 days ago)

      %{
        asset: asset,
        asset2: asset2,
        baseline: baseline,
        baseline2: baseline2,
        recent: recent
      }
    end

    test "analysis whose lookahead has not yet elapsed is skipped", %{
      asset: asset,
      baseline: baseline
    } do
      {:ok, _analysis} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: baseline.id,
            recommendation: "manter",
            analyzed_at: dt_days_ago(1)
          })
        )

      result = Accuracy.close_pending_outcomes()

      assert result.closed == 0
      assert result.skipped >= 1
      assert Repo.aggregate(AnalysisOutcome, :count) == 0
    end

    test "analysis whose lookahead has elapsed and observed snapshot exists is closed", %{
      asset: asset,
      baseline: baseline
    } do
      {:ok, analysis} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: baseline.id,
            recommendation: "vender",
            analyzed_at: dt_days_ago(30)
          })
        )

      result = Accuracy.close_pending_outcomes()

      assert result.closed == 1
      assert result.skipped == 0

      outcome = Repo.get_by!(AnalysisOutcome, analysis_id: analysis.id)
      assert outcome.outcome == "hit"
      assert outcome.baseline_price == 100.0
      assert outcome.observed_price == 95.0
      assert_in_delta outcome.variation_pct, -5.0, 0.001
      assert outcome.lookahead_days == 5
    end

    test "analysis whose lookahead elapsed but no snapshot after target is skipped", %{
      asset2: asset2,
      baseline2: baseline2
    } do
      {:ok, _analysis} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset2.id,
            snapshot_id: baseline2.id,
            recommendation: "manter",
            analyzed_at: dt_days_ago(30)
          })
        )

      result = Accuracy.close_pending_outcomes()

      assert result.closed == 0
      assert result.skipped >= 1
      assert Repo.aggregate(AnalysisOutcome, :count) == 0
    end

    test "re-running after success is idempotent — second run counts as skipped", %{
      asset: asset,
      baseline: baseline
    } do
      {:ok, _analysis} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: baseline.id,
            recommendation: "manter",
            analyzed_at: dt_days_ago(30)
          })
        )

      first = Accuracy.close_pending_outcomes()
      assert first.closed == 1
      assert first.skipped == 0
      assert Repo.aggregate(AnalysisOutcome, :count) == 1

      second = Accuracy.close_pending_outcomes()
      assert second.closed == 0
      assert second.skipped == 1
      # No new rows inserted
      assert Repo.aggregate(AnalysisOutcome, :count) == 1
    end

    test "analysis with nil snapshot_id is excluded from processing", %{asset: asset} do
      {:ok, _analysis} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: nil,
            recommendation: "manter",
            analyzed_at: dt_days_ago(30)
          })
        )

      result = Accuracy.close_pending_outcomes()

      assert result.closed == 0
      assert Repo.aggregate(AnalysisOutcome, :count) == 0
    end

    test "mixed batch: 1 closable, 1 too early, 1 already closed returns %{closed: 1, skipped: 2}",
         %{asset: asset} do
      # Each analysis needs a distinct snapshot to satisfy the
      # analyses_asset_id_snapshot_id_index unique constraint.
      {:ok, snap_a} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 100.0,
            fetched_at: dt_days_ago(61)
          })
        )

      {:ok, snap_b} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 100.0,
            fetched_at: dt_days_ago(62)
          })
        )

      {:ok, snap_c} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 100.0,
            fetched_at: dt_days_ago(63)
          })
        )

      # Closable: 30 days ago, observed snapshot available (recent snap for asset)
      {:ok, _closable} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: snap_a.id,
            recommendation: "vender",
            analyzed_at: dt_days_ago(30)
          })
        )

      # Too early: 1 day ago, lookahead window not elapsed
      {:ok, _too_early} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: snap_b.id,
            recommendation: "manter",
            analyzed_at: dt_days_ago(1)
          })
        )

      # Already closed: 31 days ago (different calendar date from closable's 30
      # days ago, avoiding the analyses_asset_date unique index) — the
      # pre-existing outcome row forces a unique-constraint skip on this run.
      {:ok, already_closed} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: snap_c.id,
            recommendation: "manter",
            analyzed_at: dt_days_ago(31)
          })
        )

      {:ok, recent_for_closed} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 102.0,
            fetched_at: dt_days_ago(8)
          })
        )

      Repo.insert!(
        AnalysisOutcome.changeset(%AnalysisOutcome{}, %{
          analysis_id: already_closed.id,
          observed_snapshot_id: recent_for_closed.id,
          lookahead_days: 5,
          baseline_price: 100.0,
          observed_price: 102.0,
          variation_pct: 2.0,
          outcome: "hit",
          drop_threshold_pct: 3.0,
          evaluated_at: dt_days_ago(0)
        })
      )

      result = Accuracy.close_pending_outcomes()

      assert result == %{closed: 1, skipped: 2}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp dt_days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 86_400, :second)
    |> DateTime.truncate(:second)
  end
end
