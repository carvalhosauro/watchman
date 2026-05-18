defmodule Watchman.Alerts.FactoryTest do
  use ExUnit.Case, async: false

  alias Watchman.Alerts.Factory

  describe "providers/0" do
    test "returns override when set" do
      Application.put_env(:watchman, :alerts_provider_override, [Watchman.Alerts.MockProvider])
      assert Factory.providers() == [Watchman.Alerts.MockProvider]
      Application.delete_env(:watchman, :alerts_provider_override)
    end

    test "resolves telegram from config" do
      Application.delete_env(:watchman, :alerts_provider_override)
      Application.put_env(:watchman, :toml_config, %{"alerts" => %{"provider" => "telegram"}})
      assert Factory.providers() == [Watchman.Alerts.Telegram]
    end

    test "resolves discord from config" do
      Application.delete_env(:watchman, :alerts_provider_override)
      Application.put_env(:watchman, :toml_config, %{"alerts" => %{"provider" => "discord"}})
      assert Factory.providers() == [Watchman.Alerts.Discord]
    end

    test "resolves both from config" do
      Application.delete_env(:watchman, :alerts_provider_override)
      Application.put_env(:watchman, :toml_config, %{"alerts" => %{"provider" => "both"}})
      assert Factory.providers() == [Watchman.Alerts.Telegram, Watchman.Alerts.Discord]
    end

    test "returns empty list when not configured" do
      Application.delete_env(:watchman, :alerts_provider_override)
      Application.put_env(:watchman, :toml_config, %{})
      assert Factory.providers() == []
    end
  end
end
