defmodule Watchman.PipelineTest do
  use ExUnit.Case
  import Mox
  import Ecto.Query
  import ExUnit.CaptureIO

  alias Watchman.Models.{Analysis, Asset, PriceSnapshot}
  alias Watchman.Repo

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    Application.put_env(:watchman, :market_provider_override, Watchman.Market.MockProvider)
    Application.put_env(:watchman, :ai_provider_override, Watchman.AI.MockProvider)

    on_exit(fn ->
      Application.delete_env(:watchman, :market_provider_override)
      Application.delete_env(:watchman, :ai_provider_override)
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

  defp insert_analysis(asset, snapshot, attrs \\ %{}) do
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

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot ->
        {:ok, mock_analysis_result(), []}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "PETR4"
      assert output =~ "manter"

      asset_id = asset.id
      assert Repo.exists?(from a in Analysis, where: a.asset_id == ^asset_id)
    end

    test "run/0 returns :ok and prints summary" do
      _asset = insert_asset()

      expect(Watchman.Market.MockProvider, :fetch, fn "PETR4" ->
        {:ok, mock_price_data()}
      end)

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot ->
        {:ok, mock_analysis_result(), []}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "PETR4"
      assert output =~ "Summary"
      assert output =~ "Analyzed"
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

    test "handles AI provider error gracefully" do
      _asset = insert_asset()

      expect(Watchman.Market.MockProvider, :fetch, fn "PETR4" ->
        {:ok, mock_price_data()}
      end)

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot ->
        {:error, :api_error}
      end)

      output =
        capture_io(fn ->
          Watchman.Pipeline.run()
        end)

      assert output =~ "PETR4"
      assert output =~ "Failed"
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

      expect(Watchman.AI.MockProvider, :analyze, fn _asset, _snapshot ->
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

  describe "run/0 with multiple assets" do
    test "analyzes all active assets and prints summary" do
      _petr4 = insert_asset(%{ticker: "PETR4"})
      _vale3 = insert_asset(%{ticker: "VALE3"})

      expect(Watchman.Market.MockProvider, :fetch, 2, fn ticker ->
        {:ok, Map.put(mock_price_data(), :ticker, ticker)}
      end)

      expect(Watchman.AI.MockProvider, :analyze, 2, fn _asset, _snapshot ->
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
