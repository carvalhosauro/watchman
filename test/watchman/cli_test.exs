defmodule Watchman.CLITest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Watchman.Models.{Analysis, AnalysisOutcome, Asset, PriceSnapshot}
  alias Watchman.Repo

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  describe "assets command" do
    test "registers new asset with auto-detected type" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "XPTO3"])
        end)

      assert output =~ "+ XPTO3 (acao)"
      assert Repo.get_by(Asset, ticker: "XPTO3")
    end

    test "auto-detects FII type for ticker ending in 11" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "ZZZZ11"])
        end)

      assert output =~ "+ ZZZZ11 (fii)"
      asset = Repo.get_by(Asset, ticker: "ZZZZ11")
      assert asset.type == "fii"
    end

    test "handles explicit type override" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "ABCD11:acao"])
        end)

      assert output =~ "+ ABCD11 (acao)"
      asset = Repo.get_by(Asset, ticker: "ABCD11")
      assert asset.type == "acao"
    end

    test "skips already tracked asset" do
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "DUPL3", type: "acao"}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "DUPL3"])
        end)

      assert output =~ "~ DUPL3 (already tracked)"
    end

    test "upcases ticker input" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "lowcase3"])
        end)

      assert output =~ "+ LOWCASE3"
    end

    test "reactivates removed asset" do
      {:ok, asset} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "GONE3", type: "acao"}))
      Repo.update!(Asset.changeset(asset, %{active: false}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["assets", "GONE3"])
        end)

      assert output =~ "+ GONE3 (reactivated"
      assert Repo.get_by(Asset, ticker: "GONE3").active == true
    end
  end

  describe "list command" do
    test "shows tracked assets" do
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "LST13", type: "acao"}))
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "LST211", type: "fii"}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["list"])
        end)

      assert output =~ "LST13 (acao)"
      assert output =~ "LST211 (fii)"
    end

    test "shows message when no assets tracked" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["list"])
        end)

      assert output =~ "No assets tracked"
    end
  end

  describe "remove command" do
    test "deactivates asset" do
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "RMVX3", type: "acao"}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["remove", "RMVX3"])
        end)

      assert output =~ "- RMVX3"
      assert Repo.get_by(Asset, ticker: "RMVX3").active == false
    end

    test "reports not found" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["remove", "GHOST9"])
        end)

      assert output =~ "? GHOST9 (not found)"
    end
  end

  describe "usage" do
    test "shows usage on no args" do
      output =
        capture_io(fn ->
          Watchman.CLI.main([])
        end)

      assert output =~ "watchman - financial asset monitor"
      assert output =~ "wm setup"
    end
  end

  describe "show command" do
    test "reports no analyses when database is empty" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["show"])
        end)

      assert output =~ "No analyses found for today"
    end

    test "reports no analyses for specific ticker" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["show", "XPTO3"])
        end)

      assert output =~ "No analyses found for XPTO3"
    end

    test "shows analysis when data exists" do
      asset = Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "SHW13", type: "acao"}))

      snapshot =
        Repo.insert!(%PriceSnapshot{
          asset_id: asset.id,
          price: 42.0,
          variation_day: -1.5,
          fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      Repo.insert!(%Analysis{
        asset_id: asset.id,
        snapshot_id: snapshot.id,
        recommendation: "manter",
        cause: "test cause",
        justification: "test justification",
        analyzed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      output =
        capture_io(fn ->
          Watchman.CLI.main(["show", "SHW13"])
        end)

      assert output =~ "SHW13"
      assert output =~ "R$ 42.0"
      assert output =~ "manter"
      assert output =~ "test cause"
    end

    test "respects --last flag" do
      asset = Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "LSTF3", type: "acao"}))

      for i <- 1..3 do
        analysis_time =
          DateTime.utc_now()
          |> DateTime.add(-3 + i, :day)
          |> DateTime.truncate(:second)

        snapshot =
          Repo.insert!(%PriceSnapshot{
            asset_id: asset.id,
            price: 10.0 + i,
            fetched_at: analysis_time
          })

        Repo.insert!(%Analysis{
          asset_id: asset.id,
          snapshot_id: snapshot.id,
          recommendation: "manter",
          analyzed_at: analysis_time
        })
      end

      output =
        capture_io(fn ->
          Watchman.CLI.main(["show", "--last", "1"])
        end)

      # Should contain exactly one result
      assert length(String.split(output, "LSTF3")) == 2
    end
  end

  describe "retro command" do
    test "shows usage when called with no flags" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["retro"])
        end)

      assert output =~ "wm retro -w"
      assert output =~ "wm retro -m"
    end

    test "retro list shows message when no retrospectives exist" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["retro", "list"])
        end)

      assert output =~ "No retrospectives yet"
    end

    test "retro show with invalid ID" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["retro", "show", "abc"])
        end)

      assert output =~ "Invalid ID"
    end

    test "retro show with non-existent ID" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["retro", "show", "99999"])
        end)

      assert output =~ "not found"
    end

    test "retro list shows existing retrospectives" do
      Repo.insert!(%Watchman.Models.Retrospective{
        period_type: "weekly",
        start_date: ~D[2026-05-10],
        end_date: ~D[2026-05-17],
        content: "test retro",
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      output =
        capture_io(fn ->
          Watchman.CLI.main(["retro", "list"])
        end)

      assert output =~ "weekly"
      assert output =~ "2026-05-10"
    end
  end

  describe "completions command" do
    test "shows usage for invalid shell" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["completions", "fish"])
        end)

      assert output =~ "Usage: wm completions bash | zsh"
    end

    test "outputs bash completions" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["completions", "bash"])
        end)

      assert output =~ "_wm_completions"
    end

    test "outputs zsh completions" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["completions", "zsh"])
        end)

      assert output =~ "#compdef wm"
    end
  end

  describe "accuracy command" do
    test "shows empty-state message when no outcomes recorded" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["accuracy"])
        end)

      assert output =~ "No outcomes recorded yet"
      assert output =~ "business days"
    end

    test "shows Overall: with hit rate when outcomes exist" do
      {:ok, asset} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "ACCT3"}))
      insert_accuracy_outcome(asset.id, "hit", days_ago: 2)

      output =
        capture_io(fn ->
          Watchman.CLI.main(["accuracy"])
        end)

      assert output =~ "Overall:"
      assert output =~ "hit rate"
      assert output =~ "ACCT3"
    end

    test "--ticker filters output to that asset" do
      {:ok, asset_a} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "ACCA3"}))
      {:ok, asset_b} = Repo.insert(Asset.changeset(%Asset{}, %{ticker: "ACCB3"}))
      insert_accuracy_outcome(asset_a.id, "hit", days_ago: 2)
      insert_accuracy_outcome(asset_b.id, "miss", days_ago: 3)

      output =
        capture_io(fn ->
          Watchman.CLI.main(["accuracy", "--ticker", "ACCA3"])
        end)

      assert output =~ "ACCA3"
      refute output =~ "ACCB3"
    end

    test "--since with invalid date prints friendly error and does not crash" do
      output =
        capture_io(fn ->
          Watchman.CLI.main(["accuracy", "--since", "not-a-date"])
        end)

      assert output =~ "Invalid date"
      assert output =~ "YYYY-MM-DD"
    end
  end

  describe "hidden completion helpers" do
    test "_complete_tickers outputs tracked tickers" do
      Repo.insert!(Asset.changeset(%Asset{}, %{ticker: "COMP3", type: "acao"}))

      output =
        capture_io(fn ->
          Watchman.CLI.main(["_complete_tickers"])
        end)

      assert output =~ "COMP3"
    end

    test "_complete_retro_ids outputs IDs" do
      Repo.insert!(%Watchman.Models.Retrospective{
        period_type: "weekly",
        start_date: ~D[2026-05-01],
        end_date: ~D[2026-05-07],
        content: "test",
        generated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      output =
        capture_io(fn ->
          Watchman.CLI.main(["_complete_retro_ids"])
        end)

      assert output =~ ~r/\d+/
    end
  end

  # Inserts the minimal chain of records to produce one AnalysisOutcome row.
  # `days_ago:` controls the evaluated_at offset; analyzed_at is staggered
  # further back to avoid the analyses_asset_date unique index conflict.
  defp insert_accuracy_outcome(asset_id, outcome, opts) do
    eval_days = Keyword.fetch!(opts, :days_ago)
    analyzed_days = eval_days + 20

    {:ok, baseline} =
      Repo.insert(%PriceSnapshot{
        asset_id: asset_id,
        price: 100.0,
        fetched_at: ts_days_ago(analyzed_days + 5)
      })

    {:ok, analysis} =
      Repo.insert(
        Analysis.changeset(%Analysis{}, %{
          asset_id: asset_id,
          snapshot_id: baseline.id,
          recommendation: "manter",
          analyzed_at: ts_days_ago(analyzed_days)
        })
      )

    {:ok, observed} =
      Repo.insert(%PriceSnapshot{
        asset_id: asset_id,
        price: 105.0,
        fetched_at: ts_days_ago(eval_days + 1)
      })

    Repo.insert!(
      AnalysisOutcome.changeset(%AnalysisOutcome{}, %{
        analysis_id: analysis.id,
        observed_snapshot_id: observed.id,
        lookahead_days: 5,
        baseline_price: 100.0,
        observed_price: 105.0,
        variation_pct: 5.0,
        outcome: outcome,
        drop_threshold_pct: 3.0,
        evaluated_at: ts_days_ago(eval_days)
      })
    )
  end

  defp ts_days_ago(days) do
    DateTime.utc_now()
    |> DateTime.add(-days * 86_400, :second)
    |> DateTime.truncate(:second)
  end
end
