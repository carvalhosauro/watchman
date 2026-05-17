defmodule Watchman.AI.FactoryTest do
  use ExUnit.Case

  describe "provider/0" do
    test "returns Claude by default" do
      Application.put_env(:watchman, :toml_config, %{})
      assert Watchman.AI.Factory.provider() == Watchman.AI.Claude
    end

    test "returns Gemini when configured" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"ai" => "gemini"}})
      assert Watchman.AI.Factory.provider() == Watchman.AI.Gemini
    end

    test "returns Deepseek when configured" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"ai" => "deepseek"}})
      assert Watchman.AI.Factory.provider() == Watchman.AI.Deepseek
    end

    test "returns Claude for unknown provider" do
      Application.put_env(:watchman, :toml_config, %{"providers" => %{"ai" => "unknown"}})
      assert Watchman.AI.Factory.provider() == Watchman.AI.Claude
    end
  end
end
