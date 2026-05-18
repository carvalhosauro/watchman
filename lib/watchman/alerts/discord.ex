defmodule Watchman.Alerts.Discord do
  @moduledoc "Discord webhook alert provider."
  @behaviour Watchman.Alerts.Provider

  require Logger

  @colors %{
    "vender" => 15_158_332,
    "investigar" => 16_776_960,
    "manter" => 3_066_993
  }

  @impl true
  def send_alert(ticker, recommendation, justification) do
    with {:ok, url} <- webhook_url() do
      color = Map.get(@colors, recommendation, 9_807_270)

      embed = %{
        title: "#{ticker} — #{recommendation}",
        description: justification,
        color: color
      }

      body = %{embeds: [embed]}

      case post(url, body) do
        {:ok, %Req.Response{status: status}} when status in [200, 204] ->
          :ok

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          {:error, {:discord_api, status, resp_body}}

        {:error, reason} ->
          {:error, {:discord_request, reason}}
      end
    end
  end

  @impl true
  def test_connection do
    with {:ok, url} <- webhook_url() do
      body = %{content: "✓ Watchman alertas configurado!"}

      case post(url, body) do
        {:ok, %Req.Response{status: status}} when status in [200, 204] ->
          :ok

        {:ok, %Req.Response{status: status, body: resp_body}} ->
          {:error, {:discord_api, status, resp_body}}

        {:error, reason} ->
          {:error, {:discord_request, reason}}
      end
    end
  end

  defp post(url, body) do
    opts = [json: body] ++ test_plug_opts()
    Req.post(url, opts)
  end

  defp test_plug_opts do
    case Application.get_env(:watchman, :discord_test_plug) do
      nil -> []
      plug -> [plug: plug]
    end
  end

  defp webhook_url do
    try do
      {:ok, Watchman.Config.discord_webhook_url()}
    rescue
      e -> {:error, {:config, Exception.message(e)}}
    end
  end
end
