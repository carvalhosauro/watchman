defmodule Watchman.PipelineTest do
  use ExUnit.Case
  import Mox
  import Ecto.Query
  import ExUnit.CaptureIO

  alias Watchman.Models.{Analysis, AnalysisOutcome, Asset, PriceSnapshot}
  alias Watchman.Repo

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    Application.put_env(:watchman, :market_provider_override, Watchman.Market.MockProvider)
    Application.put_env(:watchman, :ai_provider_override, Watchman.AI.MockProvider)
    Application.put_env(:watchman, :news_providers_override, [Watchman.News.MockProvider])

    # Default: every test gets the "no news from any provider" stub. Individual
    # tests that need news fixtures override via expect/3.
    stub(Watchman.News.MockProvider, :fetch, fn _ticker, _opts -> {:ok, []} end)

    on_exit(fn ->
      Application.delete_env(:watchman, :market_provider_override)
      Application.delete_env(:watchman, :ai_provider_override)
      Application.delete_env(:watchman, :news_providers_override)
    end)

    :ok
  end

  defp insert_asset(attrs \\ %{}) do
    defaults = %{ticker: "PETR4", name: "Petrobras", type: "acao", active: true}

    {:ok, asset} =
      Repo.insert(Asset.changeset(%Asset{}, Map.merge(defaults, attrs)))

    asset
  end

  defp insert_snapshot(asset, attrs \\ %{}) do
    defaults = %{
      asset_id: asset.id,
      price: 35.50,
      variation_day: -1.2,
      variation_week: 2.0,
      variation_month: -3.5,
      fetched_at: DateTime.utc_now()
    }

    {:ok, snapshot} =
      Repo.insert(PriceSnapshot.changeset(%PriceSnapshot{}, Map.merge(defaults, attrs)))

    snapshot
  end

  defp insert_analysis(asset, snapshot, attrs) do
    defaults = %{
      asset_id: asset.id,
      snapshot_id: snapshot.id,
      recommendation: "manter",
      analyzed_at: DateTime.utc_now()
    }

    {:ok, analysis} =
      Repo.insert(Analysis.changeset(%Analysis{}, Map.merge(defaults, attrs)))

    analysis
  end

  defp mock_price_data do
    %{
      price: 35.50,
      variation_day: -1.2,
      variation_week: 2.0,
      variation_month: -3.5
    }
  end

  defp mock_analysis_result do
    %{
      cause: "Queda no preço do petróleo",
      is_specific_problem: false,
      macro_context: "Tensão geopolítica global",
      recommendation: "manter",
      justification: "Fundamentos sólidos a longo prazo",
      tokens_used: 1500
    }
  end

  describe "run/0 with no assets" do
    test "prints message and returns :ok when no active assets" do
      output =
        capture_io(fn ->
          assert Watchman.Pipeline.run() == :ok
        end)

      assert output =~ "No tracked assets"
    end
  end

  describe "run/0 with active assets" do
    test "analyzes asset successfully and persists to DB" do
      asset = insert_asset()

      expect(Watchman.Market.MockProvider, :fetch, fn "PETR4" ->
        {:ok, mock_price_data()}
      end)

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot, _signal, _news ->
        {:ok, mock_analysis_result(), []}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "PETR4"
      # Track 4: status line shows Signal level + direction, not the
      # AI-derived recommendation. recommendation is persisted to the DB.
      assert output =~ "PETR4 — noise neutral"

      asset_id = asset.id
      assert Repo.exists?(from a in Analysis, where: a.asset_id == ^asset_id)
      analysis = Repo.one(from a in Analysis, where: a.asset_id == ^asset_id)
      assert analysis.recommendation == "manter"
    end

    test "run/0 returns :ok and prints summary" do
      _asset = insert_asset()

      expect(Watchman.Market.MockProvider, :fetch, fn "PETR4" ->
        {:ok, mock_price_data()}
      end)

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot, _signal, _news ->
        {:ok, mock_analysis_result(), []}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "PETR4"
      assert output =~ "Summary"
      assert output =~ "Analyzed"
      # Track 4: per-asset status line shows the deterministic Signal level +
      # direction, not the AI-derived recommendation atom.
      assert output =~ "PETR4 — noise neutral"
    end

    test "skips asset already analyzed today" do
      asset = insert_asset()
      snapshot = insert_snapshot(asset)
      insert_analysis(asset, snapshot, %{analyzed_at: DateTime.utc_now()})

      # No mock expectations set — if pipeline calls providers it will fail verify_on_exit!
      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "already analyzed today"
      assert output =~ "PETR4"
    end

    test "handles market provider error and returns error tuple" do
      _asset = insert_asset()

      expect(Watchman.Market.MockProvider, :fetch, fn "PETR4" ->
        {:error, :timeout}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "PETR4"
      assert output =~ "Failed"
    end

    test "handles AI provider error gracefully via SignalFormatter fallback" do
      asset = insert_asset()

      expect(Watchman.Market.MockProvider, :fetch, fn "PETR4" ->
        {:ok, mock_price_data()}
      end)

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot, _signal, _news ->
        {:error, :api_error}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      # Track 4: AI failure no longer fails the pipeline. The fallback uses
      # SignalFormatter to populate justification with zero tokens spent and
      # the recommendation derived deterministically from the Signal.
      assert output =~ "PETR4 — noise neutral"
      assert output =~ "Analyzed"

      asset_id = asset.id
      analysis = Repo.one(from a in Analysis, where: a.asset_id == ^asset_id)
      assert analysis.tokens_used == 0
      assert analysis.recommendation == "manter"
      assert analysis.signal_level == "noise"
    end

    test "only processes active assets" do
      _inactive = insert_asset(%{ticker: "VALE3", active: false})

      output =
        capture_io(fn ->
          assert Watchman.Pipeline.run() == :ok
        end)

      assert output =~ "No tracked assets"
    end

    test "persists news items when returned by AI provider" do
      asset = insert_asset()

      news = [
        %{
          title: "Petrobras anuncia dividendos",
          summary: "Dividendos acima do esperado",
          source: "InfoMoney",
          url: "https://example.com/news",
          published_at: DateTime.utc_now()
        }
      ]

      expect(Watchman.Market.MockProvider, :fetch, fn "PETR4" ->
        {:ok, mock_price_data()}
      end)

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot, _signal, _news ->
        {:ok, mock_analysis_result(), news}
      end)

      capture_io(fn ->
        Watchman.Pipeline.run()
      end)

      import Ecto.Query

      count =
        Repo.one(
          from n in Watchman.Models.NewsItem, where: n.asset_id == ^asset.id, select: count()
        )

      assert count == 1
    end
  end

  describe "run/0 closer integration" do
    test "close_pending_outcomes runs and records an AnalysisOutcome" do
      # Inactive asset — pipeline skips main analysis loop, no mock expectations needed
      asset = insert_asset(%{ticker: "CLOSE4", active: false})

      thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 3600, :second)

      baseline_snapshot =
        insert_snapshot(asset, %{fetched_at: thirty_days_ago, price: 30.00})

      analysis =
        insert_analysis(asset, baseline_snapshot, %{
          analyzed_at: thirty_days_ago,
          recommendation: "manter"
        })

      # Observed snapshot dated after the 5-business-day target (~23 days ago)
      observed_at = DateTime.utc_now() |> DateTime.add(-20 * 24 * 3600, :second)
      insert_snapshot(asset, %{fetched_at: observed_at, price: 31.00})

      capture_io(fn -> Watchman.Pipeline.run() end)

      analysis_id = analysis.id
      assert Repo.exists?(from ao in AnalysisOutcome, where: ao.analysis_id == ^analysis_id)
    end
  end

  describe "run/0 with multiple assets" do
    test "analyzes all active assets and prints summary" do
      _petr4 = insert_asset(%{ticker: "PETR4"})
      _vale3 = insert_asset(%{ticker: "VALE3"})

      expect(Watchman.Market.MockProvider, :fetch, 2, fn ticker ->
        {:ok, Map.put(mock_price_data(), :ticker, ticker)}
      end)

      expect(Watchman.AI.MockProvider, :analyze, 2, fn _asset, _snapshot, _signal, _news ->
        {:ok, mock_analysis_result(), []}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "Summary"
      assert output =~ "Analyzed"
    end
  end
end
