defmodule Watchman.Config do
  @moduledoc "Configuration loading and access."

  @config_path "~/.config/watchman/config.toml"

  def load do
    path = Path.expand(@config_path)

    toml =
      if File.exists?(path) do
        case Toml.decode_file(path) do
          {:ok, data} ->
            data

          {:error, reason} ->
            IO.puts("Warning: failed to parse #{path}: #{inspect(reason)}")
            %{}
        end
      else
        %{}
      end

    Application.put_env(:watchman, :toml_config, toml)
  end

  # API keys — priority: env var > keyring > TOML

  def anthropic_api_key do
    get_key(
      "ANTHROPIC_API_KEY",
      "anthropic_key",
      ["api", "anthropic_key"],
      "ANTHROPIC_API_KEY not set. Run: wm setup"
    )
  end

  def gemini_api_key do
    get_key(
      "GEMINI_API_KEY",
      "gemini_key",
      ["api", "gemini_key"],
      "GEMINI_API_KEY not set. Run: wm setup"
    )
  end

  def deepseek_api_key do
    get_key(
      "DEEPSEEK_API_KEY",
      "deepseek_key",
      ["api", "deepseek_key"],
      "DEEPSEEK_API_KEY not set. Run: wm setup"
    )
  end

  def brapi_token do
    get_key(
      "BRAPI_TOKEN",
      "brapi_token",
      ["api", "brapi_token"],
      "BRAPI_TOKEN not set. Run: wm setup"
    )
  end

  # Providers

  @provider_map %{
    "claude" => Watchman.AI.Claude,
    "gemini" => Watchman.AI.Gemini,
    "deepseek" => Watchman.AI.Deepseek
  }

  @market_map %{
    "brapi" => Watchman.Market.Brapi,
    "yfinance" => Watchman.Market.Yfinance
  }

  def ai_provider do
    case toml_get(["providers", "ai"]) do
      name when is_binary(name) -> Map.get(@provider_map, name, Watchman.AI.Claude)
      _ -> Watchman.AI.Claude
    end
  end

  def market_provider do
    case toml_get(["providers", "market"]) do
      name when is_binary(name) -> Map.get(@market_map, name, Watchman.Market.Brapi)
      _ -> Watchman.Market.Brapi
    end
  end

  # Pipeline settings

  def max_concurrency do
    toml_get(["pipeline", "max_concurrency"]) || 3
  end

  def task_timeout do
    seconds = toml_get(["pipeline", "timeout_seconds"]) || 120
    seconds * 1_000
  end

  # Storage

  def db_path do
    System.get_env("WATCHMAN_DB_PATH") ||
      toml_get(["storage", "db_path"]) ||
      Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman", "watchman.db"])
  end

  # Alerts

  @alerts_map %{
    "telegram" => [Watchman.Alerts.Telegram],
    "discord" => [Watchman.Alerts.Discord],
    "both" => [Watchman.Alerts.Telegram, Watchman.Alerts.Discord]
  }

  def alerts_providers do
    case toml_get(["alerts", "provider"]) do
      name when is_binary(name) -> Map.get(@alerts_map, name, [])
      _ -> []
    end
  end

  def alerts_triggers do
    case toml_get(["alerts", "triggers"]) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  def telegram_bot_token do
    get_key(
      "TELEGRAM_BOT_TOKEN",
      "telegram_bot_token",
      ["alerts", "telegram", "bot_token"],
      "TELEGRAM_BOT_TOKEN not set. Run: wm setup"
    )
  end

  def telegram_chat_id do
    System.get_env("TELEGRAM_CHAT_ID") ||
      toml_get(["alerts", "telegram", "chat_id"]) ||
      raise "Telegram chat_id not configured. Run: wm setup"
  end

  def discord_webhook_url do
    get_key(
      "DISCORD_WEBHOOK_URL",
      "discord_webhook_url",
      ["alerts", "discord", "webhook_url"],
      "DISCORD_WEBHOOK_URL not set. Run: wm setup"
    )
  end

  # Helpers

  defp get_key(env_var, keyring_key, toml_path, error_msg) do
    System.get_env(env_var) ||
      Watchman.Credentials.get(keyring_key) ||
      toml_get(toml_path) ||
      raise error_msg
  end

  defp toml_get(path) do
    config = Application.get_env(:watchman, :toml_config, %{})
    get_in(config, path)
  end
end
