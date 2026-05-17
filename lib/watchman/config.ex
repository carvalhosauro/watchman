defmodule Watchman.Config do
  @moduledoc "Configuration reader for env vars, keyring, and TOML."

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
    toml_get(["pipeline", "max_concurrency"]) || 10
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
