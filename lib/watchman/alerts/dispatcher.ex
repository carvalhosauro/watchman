defmodule Watchman.Alerts.Dispatcher do
  @moduledoc "Dispatches alert notifications to configured providers."

  require Logger

  alias Watchman.Alerts.{Discord, Factory, Telegram}
  alias Watchman.Config

  @spec maybe_notify_signal(String.t(), Watchman.Analysis.Signal.t(), keyword()) :: :ok
  def maybe_notify_signal(ticker, %Watchman.Analysis.Signal{} = signal, _opts \\ []) do
    levels = Config.alerts_signal_levels()
    directions = Config.alerts_signal_directions()

    if Atom.to_string(signal.level) in levels and
         Atom.to_string(signal.direction) in directions do
      message = build_signal_message(ticker, signal)
      Factory.providers() |> Enum.each(&send_signal_to_provider(&1, ticker, message))
    end

    :ok
  end

  def maybe_notify(ticker, recommendation, justification) do
    triggers = Config.alerts_triggers()
    providers = Factory.providers()

    if recommendation in triggers and providers != [] do
      Enum.each(providers, &send_to_provider(&1, ticker, recommendation, justification))
    end

    :ok
  end

  defp send_to_provider(provider, ticker, recommendation, justification) do
    case provider.send_alert(ticker, recommendation, justification || "") do
      :ok ->
        Logger.info("Alert sent via #{inspect(provider)} for #{ticker}")

      {:error, reason} ->
        Logger.warning("Alert failed via #{inspect(provider)} for #{ticker}: #{inspect(reason)}")
    end
  end

  def test_all do
    providers = Factory.providers()

    if providers == [] do
      IO.puts("Nenhum provedor de alertas configurado. Execute: wm setup")
      :no_providers
    else
      results = Enum.map(providers, &test_provider/1)
      IO.puts("")
      results
    end
  end

  defp test_provider(provider) do
    name = provider_name(provider)

    case provider.test_connection() do
      :ok ->
        IO.puts("  ✓ #{name}")
        {name, :ok}

      {:error, reason} ->
        IO.puts("  ✗ #{name} — #{inspect(reason)}")
        {name, {:error, reason}}
    end
  end

  def status do
    providers = Factory.providers()
    triggers = Config.alerts_triggers()

    if providers == [] do
      IO.puts("Alertas: não configurado")
      IO.puts("Execute: wm setup")
    else
      names = Enum.map_join(providers, ", ", &provider_name/1)
      IO.puts("Provedores: #{names}")
      IO.puts("Gatilhos:   #{Enum.join(triggers, ", ")}")
    end
  end

  defp provider_name(Telegram), do: "Telegram"
  defp provider_name(Discord), do: "Discord"
  defp provider_name(module), do: inspect(module)

  defp build_signal_message(ticker, signal) do
    level = signal.level |> Atom.to_string() |> String.upcase()
    direction = signal.direction |> Atom.to_string() |> String.upcase()
    confidence = Float.round(signal.confidence * 100, 1)
    reasons = Enum.map_join(signal.reasons, "\n", &"• #{&1}")
    "[#{ticker}] #{level} #{direction} signal (confidence #{confidence}%). Reasons:\n#{reasons}"
  end

  defp send_signal_to_provider(provider, ticker, message) do
    case provider.send_alert(ticker, message, "") do
      :ok ->
        Logger.info("Signal alert sent via #{inspect(provider)} for #{ticker}")

      {:error, reason} ->
        Logger.warning(
          "Signal alert failed via #{inspect(provider)} for #{ticker}: #{inspect(reason)}"
        )
    end
  end
end
