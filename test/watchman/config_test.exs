defmodule Watchman.ConfigTest do
  use ExUnit.Case

  alias Watchman.Config

  describe "ai_provider/0" do
    test "defaults to Claude when no config" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Config.ai_provider() == Watchman.AI.Claude
    end

    test "resolves from TOML config" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"ai" => "gemini"}})
      assert Config.ai_provider() == Watchman.AI.Gemini
    end

    test "resolves deepseek" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"ai" => "deepseek"}})
      assert Config.ai_provider() == Watchman.AI.Deepseek
    end

    test "falls back to Claude for unknown provider" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"ai" => "unknown"}})
      assert Config.ai_provider() == Watchman.AI.Claude
    end
  end

  describe "market_provider/0" do
    test "defaults to Brapi" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Config.market_provider() == Watchman.Market.Brapi
    end

    test "resolves yfinance" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"market" => "yfinance"}})
      assert Config.market_provider() == Watchman.Market.Yfinance
    end
  end

  describe "max_concurrency/0" do
    test "defaults to 3" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Config.max_concurrency() == 3
    end

    test "reads from TOML" do
      Application.put_env(:watchman, :toml_config, %{"pipeline" => %{"max_concurrency" => 5}})
      assert Config.max_concurrency() == 5
    end
  end

  describe "task_timeout/0" do
    test "defaults to 120 seconds in ms" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Config.task_timeout() == 120_000
    end

    test "reads from TOML and converts to ms" do
      Application.put_env(:watchman, :toml_config, %{"pipeline" => %{"timeout_seconds" => 60}})
      assert Config.task_timeout() == 60_000
    end
  end

  describe "accuracy_lookahead_days/0" do
    test "defaults to 5 when no TOML" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Config.accuracy_lookahead_days() == 5
    end

    test "reads from TOML" do
      Application.put_env(:watchman, :toml_config, %{"accuracy" => %{"lookahead_days" => 10}})
      assert Config.accuracy_lookahead_days() == 10
    end
  end

  describe "accuracy_drop_threshold_pct/0" do
    test "defaults to 3.0 when no TOML" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Config.accuracy_drop_threshold_pct() == 3.0
    end

    test "reads float from TOML" do
      Application.put_env(:watchman, :toml_config, %{"accuracy" => %{"drop_threshold_pct" => 2.5}})

      assert Config.accuracy_drop_threshold_pct() == 2.5
    end

    test "coerces integer to float" do
      Application.put_env(:watchman, :toml_config, %{"accuracy" => %{"drop_threshold_pct" => 4}})
      assert Config.accuracy_drop_threshold_pct() == 4.0
    end
  end
end
