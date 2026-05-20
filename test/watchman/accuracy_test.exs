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

    test "unknown recommendation logs warning and returns :neutral" do
      import ExUnit.CaptureLog

      log =
        capture_log(fn -> assert Accuracy.classify_outcome("comprar", 1.0, 3.0) == :neutral end)

      assert log =~ "unknown recommendation"
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

    test "skips analysis when baseline_price is 0.0 without crashing", %{asset2: asset2} do
      {:ok, zero_baseline} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset2.id,
            price: 0.0,
            fetched_at: dt_days_ago(60)
          })
        )

      # Provide an observed snapshot AFTER the lookahead target so the closer
      # gets past find_observed_snapshot and hits the baseline guard.
      {:ok, _observed} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset2.id,
            price: 10.0,
            fetched_at: dt_days_ago(10)
          })
        )

      {:ok, _analysis} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset2.id,
            snapshot_id: zero_baseline.id,
            recommendation: "manter",
            analyzed_at: dt_days_ago(30)
          })
        )

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          result = Accuracy.close_pending_outcomes()
          assert result.closed == 0
          assert result.skipped >= 1
        end)

      assert log =~ "zero baseline_price"
      assert Repo.aggregate(AnalysisOutcome, :count) == 0
    end

    test "re-running after success is idempotent — second run is a no-op", %{
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

      # F1 (LEFT JOIN analysis_outcomes IS NULL) filters out already-closed
      # analyses BEFORE the reduce, so the second run finds no candidates at
      # all — both counters stay at zero and no new rows are inserted.
      second = Accuracy.close_pending_outcomes()
      assert second.closed == 0
      assert second.skipped == 0
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

    test "mixed batch: 1 closable, 1 too early, 1 already closed returns %{closed: 1, skipped: 1}",
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

      # already_closed is excluded from candidates by F1's LEFT JOIN filter,
      # so it does not appear in the skipped count. closable closes, too_early
      # is skipped for lookahead-not-elapsed.
      assert result == %{closed: 1, skipped: 1}
    end

    test "honors :lookahead_days opt instead of Config default", %{asset: asset} do
      # Analysis 3 days ago with a future observed snapshot. Default lookahead
      # is 5 (too early); injecting 1 should close it.
      {:ok, baseline} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 100.0,
            fetched_at: dt_days_ago(3)
          })
        )

      {:ok, _observed} =
        Repo.insert(
          PriceSnapshot.changeset(%PriceSnapshot{}, %{
            asset_id: asset.id,
            price: 95.0,
            fetched_at: dt_days_ago(0)
          })
        )

      {:ok, _analysis} =
        Repo.insert(
          Analysis.changeset(%Analysis{}, %{
            asset_id: asset.id,
            snapshot_id: baseline.id,
            recommendation: "vender",
            analyzed_at: dt_days_ago(3)
          })
        )

      assert Accuracy.close_pending_outcomes().closed == 0
      assert Accuracy.close_pending_outcomes(lookahead_days: 1).closed == 1
    end
  end

  # ---------------------------------------------------------------------------
  # report/1 — sandbox-backed tests
  # ---------------------------------------------------------------------------

  describe "report/1" do
    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

      {:ok, a1} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "RPTA3"}))
      {:ok, a2} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "RPTB3"}))

      %{a1: a1, a2: a2}
    end

    test "empty database returns all-zero counts and empty lists" do
      result = Accuracy.report()

      assert result == %{
               by_ticker: [],
               by_provider: [],
               overall: %{hits: 0, misses: 0, neutral: 0, hit_rate: 0.0},
               window: %{from: nil, to: nil, lookahead_days: nil}
             }
    end

    test "single hit outcome has overall hit_rate 1.0", %{a1: a1} do
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)

      result = Accuracy.report()

      assert result.overall.hits == 1
      assert result.overall.misses == 0
      assert result.overall.neutral == 0
      assert result.overall.hit_rate == 1.0
    end

    test "mixed batch: counts are correct and neutral excluded from hit_rate by default", %{
      a1: a1,
      a2: a2
    } do
      # a1 (RPTA3): 2 hits, 1 miss
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 31, evaluated_at_days_ago: 3)
      insert_report_outcome(a1.id, "miss", analyzed_at_days_ago: 32, evaluated_at_days_ago: 4)

      # a2 (RPTB3): 1 hit, 1 miss, 1 neutral
      insert_report_outcome(a2.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)
      insert_report_outcome(a2.id, "miss", analyzed_at_days_ago: 31, evaluated_at_days_ago: 3)
      insert_report_outcome(a2.id, "neutral", analyzed_at_days_ago: 32, evaluated_at_days_ago: 4)

      result = Accuracy.report()

      assert result.overall.hits == 3
      assert result.overall.misses == 2
      assert result.overall.neutral == 1
      # 3 / (3 + 2) = 0.6, neutral excluded
      assert_in_delta result.overall.hit_rate, 0.6, 0.001

      # by_ticker sorted by hit_rate desc
      tickers = Enum.map(result.by_ticker, & &1.ticker)
      assert tickers == ["RPTA3", "RPTB3"]

      rpta = Enum.find(result.by_ticker, &(&1.ticker == "RPTA3"))
      assert rpta.hits == 2
      assert rpta.misses == 1
      assert_in_delta rpta.hit_rate, 2 / 3, 0.001

      window = result.window
      assert window.from != nil
      assert window.to != nil
      assert Date.compare(window.from, window.to) in [:lt, :eq]
    end

    test ":include_neutral true counts neutral in denominator", %{a1: a1, a2: a2} do
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 31, evaluated_at_days_ago: 3)
      insert_report_outcome(a1.id, "miss", analyzed_at_days_ago: 32, evaluated_at_days_ago: 4)
      insert_report_outcome(a2.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)
      insert_report_outcome(a2.id, "miss", analyzed_at_days_ago: 31, evaluated_at_days_ago: 3)
      insert_report_outcome(a2.id, "neutral", analyzed_at_days_ago: 32, evaluated_at_days_ago: 4)

      result = Accuracy.report(include_neutral: true)

      # 3 / (3 + 2 + 1) = 0.5
      assert_in_delta result.overall.hit_rate, 0.5, 0.001
    end

    test ":ticker filter restricts to one asset (case-insensitive)", %{a1: a1, a2: a2} do
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)
      insert_report_outcome(a1.id, "miss", analyzed_at_days_ago: 31, evaluated_at_days_ago: 3)
      insert_report_outcome(a2.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)

      # lowercase input — report/1 must upcase before filtering
      result = Accuracy.report(ticker: "rpta3")

      assert result.overall.hits == 1
      assert result.overall.misses == 1
      assert length(result.by_ticker) == 1
      assert hd(result.by_ticker).ticker == "RPTA3"
    end

    test ":since filter restricts by evaluated_at date", %{a1: a1} do
      # evaluated 10 days ago — older than the :since boundary
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 10)
      # evaluated 1 day ago — within range
      insert_report_outcome(a1.id, "miss", analyzed_at_days_ago: 31, evaluated_at_days_ago: 1)

      result = Accuracy.report(since: Date.utc_today() |> Date.add(-5))

      assert result.overall.hits == 0
      assert result.overall.misses == 1
    end

    test ":lookahead_days filter restricts to matching window", %{a1: a1} do
      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)
      # different lookahead_days — must not appear with filter: 5
      insert_report_outcome(a1.id, "miss",
        analyzed_at_days_ago: 31,
        evaluated_at_days_ago: 3,
        lookahead_days: 10
      )

      result = Accuracy.report(lookahead_days: 5)

      assert result.overall.hits == 1
      assert result.overall.misses == 0
    end

    test ":provider filter logs a warning and always returns by_provider: []", %{a1: a1} do
      import ExUnit.CaptureLog

      insert_report_outcome(a1.id, "hit", analyzed_at_days_ago: 30, evaluated_at_days_ago: 2)

      result = Accuracy.report(provider: "clearsal")
      log = capture_log(fn -> Accuracy.report(provider: "clearsal") end)

      assert result.by_provider == []
      assert log =~ "provider filter requested"
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Inserts the chain of records needed to produce one AnalysisOutcome row:
  # a baseline PriceSnapshot, an Analysis referencing it, an observed
  # PriceSnapshot, and the AnalysisOutcome itself. `analyzed_at_days_ago`
  # controls which calendar day the analysis falls on (must be unique per
  # asset_id due to the analyses_asset_date index); `evaluated_at_days_ago`
  # controls the outcome timestamp.
  defp insert_report_outcome(asset_id, outcome, opts) do
    analyzed_days = Keyword.fetch!(opts, :analyzed_at_days_ago)
    eval_days = Keyword.fetch!(opts, :evaluated_at_days_ago)
    lookahead = Keyword.get(opts, :lookahead_days, 5)

    {:ok, baseline} =
      Repo.insert(
        PriceSnapshot.changeset(%PriceSnapshot{}, %{
          asset_id: asset_id,
          price: 100.0,
          fetched_at: dt_days_ago(analyzed_days + 5)
        })
      )

    {:ok, analysis} =
      Repo.insert(
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset_id,
          snapshot_id: baseline.id,
          recommendation: "manter",
          analyzed_at: dt_days_ago(analyzed_days)
        })
      )

    {:ok, observed} =
      Repo.insert(
        PriceSnapshot.changeset(%PriceSnapshot{}, %{
          asset_id: asset_id,
          price: 105.0,
          fetched_at: dt_days_ago(eval_days + 1)
        })
      )

    Repo.insert!(
      AnalysisOutcome.changeset(%AnalysisOutcome{}, %{
        analysis_id: analysis.id,
        observed_snapshot_id: observed.id,
        lookahead_days: lookahead,
        baseline_price: 100.0,
        observed_price: 105.0,
        variation_pct: 5.0,
        outcome: outcome,
        drop_threshold_pct: 3.0,
        evaluated_at: dt_days_ago(eval_days)
      })
    )
  end

  defp dt_days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 86_400, :second)
    |> DateTime.truncate(:second)
  end
end
