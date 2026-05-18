defmodule Watchman.Setup do
  @moduledoc "Interactive configuration wizard."

  @config_dir "~/.config/watchman"
  @config_path "~/.config/watchman/config.toml"

  def run do
    IO.puts("""

    ┌─────────────────────────────┐
    │     Watchman Setup          │
    └─────────────────────────────┘
    """)

    ai = choose_ai_provider()
    market = choose_market_provider()
    keys = collect_api_keys(ai, market)
    pipeline = configure_pipeline()
    {alerts, alert_keys} = configure_alerts()
    all_keys = Map.merge(keys, alert_keys)
    storage = choose_key_storage(all_keys)

    store_keys(all_keys, storage)
    write_config(ai, market, all_keys, pipeline, storage, alerts)

    IO.puts("""

    Config saved to #{Path.expand(@config_path)}
    #{if storage == :keyring, do: "API keys stored in system keyring", else: "API keys stored in config file (chmod 600)"}

    Next steps:
      wm assets MXRF11 PETR4 ITUB4
      wm run
    """)
  end

  defp choose_ai_provider do
    IO.puts("""
    AI Provider
      [1] Claude (Anthropic) — web search + structured analysis
      [2] Gemini (Google) — Google Search grounding
      [3] DeepSeek — knowledge-based, no web search, cheaper
    """)

    case prompt("Choose [1-3]", "1") do
      "1" -> "claude"
      "2" -> "gemini"
      "3" -> "deepseek"
      _ -> "claude"
    end
  end

  defp choose_market_provider do
    IO.puts("""

    Market Data Provider
      [1] Brapi (brapi.dev) — Brazilian market, free tier available
      [2] Yahoo Finance — international, no API key needed
    """)

    case prompt("Choose [1-2]", "1") do
      "1" -> "brapi"
      "2" -> "yfinance"
      _ -> "brapi"
    end
  end

  defp collect_api_keys(ai, market) do
    IO.puts("\n    API Keys (press Enter to skip)\n")

    keys = %{}

    keys =
      case ai do
        "claude" ->
          key = prompt_secret("  Anthropic API key")
          Map.put(keys, :anthropic_key, key)

        "gemini" ->
          key = prompt_secret("  Gemini API key")
          Map.put(keys, :gemini_key, key)

        "deepseek" ->
          key = prompt_secret("  DeepSeek API key")
          Map.put(keys, :deepseek_key, key)
      end

    keys =
      case market do
        "brapi" ->
          key = prompt_secret("  Brapi token")
          Map.put(keys, :brapi_token, key)

        "yfinance" ->
          keys
      end

    keys
  end

  defp configure_pipeline do
    IO.puts("\n    Pipeline Settings\n")

    concurrency = prompt("  Max concurrent analyses", "3")
    timeout = prompt("  Timeout per analysis (seconds)", "120")

    %{
      max_concurrency: parse_int(concurrency, 3),
      timeout_seconds: parse_int(timeout, 120)
    }
  end

  defp configure_alerts do
    IO.puts("""

    Alertas
      Receba notificacoes quando a analise recomendar acoes.
      [1] Nao configurar
      [2] Telegram
      [3] Discord
      [4] Ambos (Telegram + Discord)
    """)

    case prompt("Escolha [1-4]", "1") do
      "2" -> configure_telegram()
      "3" -> configure_discord()
      "4" -> configure_both()
      _ -> {%{}, %{}}
    end
  end

  defp configure_telegram do
    IO.puts("\n    Telegram Bot Setup\n")
    token = prompt_secret("  Bot token (@BotFather)")
    chat_id = prompt("Chat ID", "")

    triggers = choose_triggers()

    alerts = %{provider: "telegram", triggers: triggers, telegram_chat_id: chat_id}
    keys = %{telegram_bot_token: token}
    {alerts, keys}
  end

  defp configure_discord do
    IO.puts("\n    Discord Webhook Setup\n")
    url = prompt_secret("  Webhook URL")

    triggers = choose_triggers()

    alerts = %{provider: "discord", triggers: triggers}
    keys = %{discord_webhook_url: url}
    {alerts, keys}
  end

  defp configure_both do
    IO.puts("\n    Telegram Bot Setup\n")
    token = prompt_secret("  Bot token (@BotFather)")
    chat_id = prompt("Chat ID", "")

    IO.puts("\n    Discord Webhook Setup\n")
    url = prompt_secret("  Webhook URL")

    triggers = choose_triggers()

    alerts = %{provider: "both", triggers: triggers, telegram_chat_id: chat_id}
    keys = %{telegram_bot_token: token, discord_webhook_url: url}
    {alerts, keys}
  end

  defp choose_triggers do
    IO.puts("""

    Quais recomendacoes disparam alerta?
      [1] investigar + vender
      [2] Todas (manter, investigar, vender)
      [3] Apenas vender
    """)

    case prompt("Escolha [1-3]", "1") do
      "1" -> ["investigar", "vender"]
      "2" -> ["manter", "investigar", "vender"]
      "3" -> ["vender"]
      _ -> ["investigar", "vender"]
    end
  end

  defp choose_key_storage(keys) when map_size(keys) == 0, do: :config_file

  defp choose_key_storage(_keys) do
    if Watchman.Credentials.available?() do
      prompt_key_storage()
    else
      IO.puts("\n    System keyring not available. Using config file.\n")
      :config_file
    end
  end

  defp prompt_key_storage do
    IO.puts("""

    Key Storage
      [1] System keyring (recommended) — keys never stored as plaintext
      [2] Config file — encrypted with chmod 600
    """)

    case prompt("Choose [1-2]", "1") do
      "1" -> :keyring
      "2" -> :config_file
      _ -> :keyring
    end
  end

  defp store_keys(keys, :keyring) do
    Enum.each(keys, fn {key, value} -> store_key(key, value) end)
  end

  defp store_keys(_keys, :config_file), do: :ok

  defp store_key(_key, ""), do: :ok

  defp store_key(key, value) do
    case Watchman.Credentials.put(key, value) do
      :ok -> IO.puts("    Saved #{key} to keyring")
      {:error, reason} -> IO.puts("    Failed to save #{key}: #{inspect(reason)}")
    end
  end

  defp write_config(ai, market, keys, pipeline, storage, alerts) do
    dir = Path.expand(@config_dir)
    path = Path.expand(@config_path)

    File.mkdir_p!(dir)

    content = build_toml(ai, market, keys, pipeline, storage, alerts)
    File.write!(path, content)

    File.chmod!(path, 0o600)
  end

  defp build_toml(ai, market, keys, pipeline, storage, alerts) do
    api_section =
      case storage do
        :keyring ->
          """
          [api]
          # Keys stored in system keyring (managed by: wm setup)
          # To update keys, run: wm setup
          """

        :config_file ->
          anthropic_key = escape_toml_string(Map.get(keys, :anthropic_key, ""))
          gemini_key = escape_toml_string(Map.get(keys, :gemini_key, ""))
          deepseek_key = escape_toml_string(Map.get(keys, :deepseek_key, ""))
          brapi_token = escape_toml_string(Map.get(keys, :brapi_token, ""))

          """
          [api]
          # Keys stored here with chmod 600. Do NOT commit this file.
          anthropic_key = "#{anthropic_key}"
          gemini_key = "#{gemini_key}"
          deepseek_key = "#{deepseek_key}"
          brapi_token = "#{brapi_token}"
          """
      end

    alerts_section = build_alerts_toml(alerts, keys, storage)

    """
    # Watchman configuration
    # Generated by: wm setup

    #{api_section}
    [providers]
    ai = "#{ai}"
    market = "#{market}"

    [pipeline]
    max_concurrency = #{pipeline.max_concurrency}
    timeout_seconds = #{pipeline.timeout_seconds}
    #{alerts_section}\
    """
  end

  defp build_alerts_toml(%{provider: provider, triggers: triggers} = alerts, keys, storage) do
    triggers_str = Enum.map_join(triggers, ", ", &~s("#{&1}"))

    base = """

    [alerts]
    provider = "#{provider}"
    triggers = [#{triggers_str}]
    """

    telegram_section =
      if provider in ["telegram", "both"] do
        chat_id = Map.get(alerts, :telegram_chat_id, "")

        token_line =
          if storage == :config_file do
            token = escape_toml_string(Map.get(keys, :telegram_bot_token, ""))
            ~s(bot_token = "#{token}"\n)
          else
            "# bot_token stored in system keyring\n"
          end

        """

        [alerts.telegram]
        chat_id = "#{chat_id}"
        #{token_line}\
        """
      else
        ""
      end

    discord_section =
      if provider in ["discord", "both"] do
        if storage == :config_file do
          url = escape_toml_string(Map.get(keys, :discord_webhook_url, ""))

          """

          [alerts.discord]
          webhook_url = "#{url}"
          """
        else
          """

          [alerts.discord]
          # webhook_url stored in system keyring
          """
        end
      else
        ""
      end

    base <> telegram_section <> discord_section
  end

  defp build_alerts_toml(_alerts, _keys, _storage), do: ""

  # Helpers

  defp prompt(label, default) do
    result = IO.gets("  #{label} [#{default}]: ") |> String.trim()
    if result == "", do: default, else: result
  end

  defp prompt_secret(label) do
    IO.write("#{label}: ")

    case :io.get_password() do
      {:error, _} ->
        IO.gets("") |> String.trim()

      chars ->
        chars |> to_string() |> String.trim()
    end
  end

  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> default
    end
  end

  defp escape_toml_string(s),
    do: s |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
end
