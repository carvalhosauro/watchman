defmodule Watchman.Alerts.Telegram do
  @moduledoc "Telegram Bot API alert provider."
  @behaviour Watchman.Alerts.Provider

  require Logger

  @base_url "https://api.telegram.org"

  @impl true
  def send_alert(ticker, recommendation, justification) do
    with {:ok, token} <- fetch_token(),
         {:ok, chat_id} <- fetch_chat_id() do
      message = "#{ticker} — #{recommendation}\n#{justification}"
      url = "#{@base_url}/bot#{token}/sendMessage"

      case Req.post(
             url,
             req_opts(json: %{chat_id: chat_id, text: message, parse_mode: "Markdown"})
           ) do
        {:ok, %Req.Response{status: 200}} ->
          :ok

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:telegram_api, status, body}}

        {:error, reason} ->
          {:error, {:telegram_request, reason}}
      end
    end
  end

  @impl true
  def test_connection do
    with {:ok, token} <- fetch_token(),
         {:ok, chat_id} <- fetch_chat_id(),
         :ok <- verify_token(token) do
      send_test_message(token, chat_id)
    end
  end

  defp verify_token(token) do
    url = "#{@base_url}/bot#{token}/getMe"

    case Req.get(url, req_opts([])) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:telegram_auth, status, body}}
      {:error, reason} -> {:error, {:telegram_request, reason}}
    end
  end

  defp send_test_message(token, chat_id) do
    url = "#{@base_url}/bot#{token}/sendMessage"
    body = %{chat_id: chat_id, text: "✓ Watchman alertas configurado!", parse_mode: "Markdown"}

    case Req.post(url, req_opts(json: body)) do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:telegram_api, status, body}}
      {:error, reason} -> {:error, {:telegram_request, reason}}
    end
  end

  defp fetch_token do
    try do
      {:ok, Watchman.Config.telegram_bot_token()}
    rescue
      e -> {:error, {:config, Exception.message(e)}}
    end
  end

  defp fetch_chat_id do
    try do
      {:ok, Watchman.Config.telegram_chat_id()}
    rescue
      e -> {:error, {:config, Exception.message(e)}}
    end
  end

  defp req_opts(opts) do
    case Application.get_env(:watchman, :telegram_req_plug) do
      nil -> opts
      plug -> Keyword.put(opts, :plug, plug)
    end
  end
end
