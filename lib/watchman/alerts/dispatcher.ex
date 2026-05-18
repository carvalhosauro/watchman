defmodule Watchman.Alerts.Dispatcher do
  @moduledoc "Dispatches alert notifications to configured providers."

  require Logger

  def maybe_notify(ticker, recommendation, justification) do
    triggers = Watchman.Config.alerts_triggers()
    providers = Watchman.Alerts.Factory.providers()

    if recommendation in triggers and providers != [] do
      Enum.each(providers, fn provider ->
        case provider.send_alert(ticker, recommendation, justification || "") do
          :ok ->
            Logger.info("Alert sent via #{inspect(provider)} for #{ticker}")

          {:error, reason} ->
            Logger.warning(
              "Alert failed via #{inspect(provider)} for #{ticker}: #{inspect(reason)}"
            )
        end
      end)
    end

    :ok
  end

  def test_all do
    providers = Watchman.Alerts.Factory.providers()

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
    providers = Watchman.Alerts.Factory.providers()
    triggers = Watchman.Config.alerts_triggers()

    if providers == [] do
      IO.puts("Alertas: não configurado")
      IO.puts("Execute: wm setup")
    else
      names = Enum.map(providers, &provider_name/1) |> Enum.join(", ")
      IO.puts("Provedores: #{names}")
      IO.puts("Gatilhos:   #{Enum.join(triggers, ", ")}")
    end
  end

  defp provider_name(Watchman.Alerts.Telegram), do: "Telegram"
  defp provider_name(Watchman.Alerts.Discord), do: "Discord"
  defp provider_name(module), do: inspect(module)
end
