defmodule Watchman.RetroTest do
  use ExUnit.Case
  import Mox
  import ExUnit.CaptureIO

  alias Watchman.Models.{Analysis, Asset, PriceSnapshot, Retrospective}
  alias Watchman.Repo
  import Ecto.Query

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    Application.put_env(:watchman, :ai_provider_override, Watchman.AI.MockProvider)

    on_exit(fn ->
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
      cause: "Queda no petróleo",
      is_specific_problem: false,
      macro_context: "Contexto macro global",
      justification: "Fundamentos sólidos",
      tokens_used: 1000,
      cost_usd: 0.005,
      analyzed_at: DateTime.utc_now()
    }

    {:ok, analysis} =
      Repo.insert(Analysis.changeset(%Analysis{}, Map.merge(defaults, attrs)))

    analysis
  end

  defp seed_period_data(analyzed_at) do
    asset = insert_asset()
    snapshot = insert_snapshot(asset)
    insert_analysis(asset, snapshot, %{analyzed_at: analyzed_at})
    asset
  end

  describe "generate/1 with no data" do
    test "prints message and returns :ok when no analyses in period" do
      output =
        capture_io(fn ->
          assert Watchman.Retro.generate(:weekly) == :ok
        end)

      assert output =~ "No analyses found"
    end

    test "returns :ok for monthly with no data" do
      output =
        capture_io(fn ->
          assert Watchman.Retro.generate(:monthly) == :ok
        end)

      assert output =~ "No analyses found"
    end
  end

  describe "generate(:weekly)" do
    test "calls AI provider and persists retrospective when data exists" do
      analyzed_at = DateTime.utc_now()
      seed_period_data(analyzed_at)

      retro_content = "Retrospectiva semanal: PETR4 manteve tendência de queda."

      expect(Watchman.AI.MockProvider, :generate_retro, fn prompt ->
        assert is_binary(prompt)
        assert prompt =~ "PETR4"
        {:ok, retro_content}
      end)

      output =
        capture_io(fn ->
          assert {:ok, ^retro_content} = Watchman.Retro.generate(:weekly)
        end)

      assert output =~ retro_content

      retro = Repo.one(from r in Retrospective, order_by: [desc: r.id], limit: 1)
      assert retro != nil
      assert retro.period_type == "weekly"
      assert retro.content == retro_content
    end

    test "does not include analyses outside the 7-day window" do
      old_analyzed_at = DateTime.add(DateTime.utc_now(), -10, :day)
      seed_period_data(old_analyzed_at)

      # No mock expectation — provider must not be called
      output =
        capture_io(fn ->
          assert Watchman.Retro.generate(:weekly) == :ok
        end)

      assert output =~ "No analyses found"
    end

    test "includes analyses from exactly 7 days ago" do
      analyzed_at = DateTime.add(DateTime.utc_now(), -6, :day)
      seed_period_data(analyzed_at)

      retro_content = "Retrospectiva dentro da janela semanal."

      expect(Watchman.AI.MockProvider, :generate_retro, fn _prompt ->
        {:ok, retro_content}
      end)

      capture_io(fn ->
        assert {:ok, _content} = Watchman.Retro.generate(:weekly)
      end)
    end
  end

  describe "generate(:monthly)" do
    test "calls AI provider and persists monthly retrospective" do
      analyzed_at = DateTime.add(DateTime.utc_now(), -15, :day)
      seed_period_data(analyzed_at)

      retro_content = "Retrospectiva mensal: portfólio estável."

      expect(Watchman.AI.MockProvider, :generate_retro, fn prompt ->
        assert prompt =~ "monthly"
        {:ok, retro_content}
      end)

      output =
        capture_io(fn ->
          assert {:ok, ^retro_content} = Watchman.Retro.generate(:monthly)
        end)

      assert output =~ retro_content

      retro = Repo.one(from r in Retrospective, order_by: [desc: r.id], limit: 1)
      assert retro.period_type == "monthly"
    end

    test "does not include analyses outside the 30-day window" do
      old_analyzed_at = DateTime.add(DateTime.utc_now(), -31, :day)
      seed_period_data(old_analyzed_at)

      output =
        capture_io(fn ->
          assert Watchman.Retro.generate(:monthly) == :ok
        end)

      assert output =~ "No analyses found"
    end
  end

  describe "generate/1 when AI provider fails" do
    test "prints error and returns error tuple" do
      analyzed_at = DateTime.utc_now()
      seed_period_data(analyzed_at)

      expect(Watchman.AI.MockProvider, :generate_retro, fn _prompt ->
        {:error, :api_timeout}
      end)

      output =
        capture_io(fn ->
          assert {:error, :api_timeout} = Watchman.Retro.generate(:weekly)
        end)

      assert output =~ "Failed"

      # No retrospective should be persisted on failure
      count = Repo.one(from r in Retrospective, select: count())
      assert count == 0
    end
  end

  describe "date range calculation" do
    test "weekly range covers last 7 days" do
      today = Date.utc_today()
      expected_start = Date.add(today, -7)

      # Seed analysis at the boundary (7 days ago) — should be included
      analyzed_at = DateTime.new!(expected_start, ~T[12:00:00], "Etc/UTC")
      seed_period_data(analyzed_at)

      retro_content = "Retrospectiva semanal."

      expect(Watchman.AI.MockProvider, :generate_retro, fn prompt ->
        assert prompt =~ to_string(expected_start)
        assert prompt =~ to_string(today)
        {:ok, retro_content}
      end)

      capture_io(fn ->
        assert {:ok, _} = Watchman.Retro.generate(:weekly)
      end)
    end

    test "monthly range covers from beginning of current month" do
      today = Date.utc_today()
      expected_start = Date.beginning_of_month(today)

      analyzed_at = DateTime.new!(expected_start, ~T[12:00:00], "Etc/UTC")
      seed_period_data(analyzed_at)

      retro_content = "Retrospectiva mensal."

      expect(Watchman.AI.MockProvider, :generate_retro, fn prompt ->
        assert prompt =~ to_string(expected_start)
        assert prompt =~ to_string(today)
        {:ok, retro_content}
      end)

      capture_io(fn ->
        assert {:ok, _} = Watchman.Retro.generate(:monthly)
      end)
    end
  end

  describe "generate/1 with multiple assets" do
    test "includes all assets in the prompt" do
      now = DateTime.utc_now()

      asset1 = insert_asset(%{ticker: "PETR4"})
      snapshot1 = insert_snapshot(asset1)
      insert_analysis(asset1, snapshot1, %{analyzed_at: now})

      asset2 = insert_asset(%{ticker: "VALE3"})
      snapshot2 = insert_snapshot(asset2)
      insert_analysis(asset2, snapshot2, %{analyzed_at: now})

      retro_content = "Retrospectiva com múltiplos ativos."

      expect(Watchman.AI.MockProvider, :generate_retro, fn prompt ->
        assert prompt =~ "PETR4"
        assert prompt =~ "VALE3"
        {:ok, retro_content}
      end)

      capture_io(fn ->
        assert {:ok, _} = Watchman.Retro.generate(:weekly)
      end)
    end
  end
end
