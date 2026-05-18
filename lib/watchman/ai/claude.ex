defmodule Watchman.AI.Claude do
  @moduledoc "Claude (Anthropic) AI provider with web search."

  @behaviour Watchman.AI.Provider

  alias Watchman.AI.Shared

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"

  @impl true
  def analyze(asset, snapshot) do
    body = %{
      model: @model,
      max_tokens: 4096,
      system: Shared.system_prompt(:web_search_tool),
      tools: [%{type: "web_search_20250305"}],
      messages: [%{role: "user", content: Shared.user_prompt(asset, snapshot)}]
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        tokens =
          get_in(resp_body, ["usage", "input_tokens"]) +
            get_in(resp_body, ["usage", "output_tokens"])

        Watchman.Parser.extract(%{content: resp_body["content"], tokens: tokens})

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:claude_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:claude_request, reason}}
    end
  end

  @impl true
  def generate_retro(prompt) do
    body = %{
      model: @model,
      max_tokens: 4096,
      system: Shared.retro_system_prompt(),
      messages: [%{role: "user", content: prompt}]
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        text =
          resp_body["content"]
          |> Enum.filter(&(&1["type"] == "text"))
          |> List.last()
          |> case do
            %{"text" => text} -> {:ok, text}
            _ -> {:error, :no_text_in_response}
          end

        text

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:claude_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:claude_request, reason}}
    end
  end

  defp api_request(body) do
    Req.post(@api_url,
      json: body,
      headers: [
        {"x-api-key", Watchman.Config.anthropic_api_key()},
        {"anthropic-version", "2025-03-05"},
        {"content-type", "application/json"}
      ],
      receive_timeout: 90_000,
      retry: :transient,
      max_retries: 3
    )
  end
end
