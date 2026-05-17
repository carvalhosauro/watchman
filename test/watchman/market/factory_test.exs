defmodule Watchman.Market.FactoryTest do
  use ExUnit.Case

  describe "provider/0" do
    test "returns Brapi by default" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Watchman.Market.Factory.provider() == Watchman.Market.Brapi
    end

    test "returns Yfinance when configured" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"market" => "yfinance"}})
      assert Watchman.Market.Factory.provider() == Watchman.Market.Yfinance
    end

    test "returns Brapi for unknown provider" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"market" => "unknown"}})
      assert Watchman.Market.Factory.provider() == Watchman.Market.Brapi
    end
  end
end
