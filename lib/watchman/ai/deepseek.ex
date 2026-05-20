defmodule Watchman.AI.Deepseek do
  @moduledoc "DeepSeek AI provider (OpenAI-compatible)."

  @behaviour Watchman.AI.Provider

  alias Watchman.AI.Shared

  @api_url "https://api.deepseek.com/chat/completions"
  @model "deepseek-chat"

  @impl true
  def analyze(asset, snapshot) do
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: Shared.system_prompt(:no_search)},
        %{role: "user", content: Shared.user_prompt(asset, snapshot, search: false)}
      ],
      temperature: 0.7,
      max_tokens: 4096
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        tokens = get_in(resp, ["usage", "total_tokens"]) || 0
        text = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        analysis = Shared.parse_analysis(text, tokens)
        # DeepSeek has no web search — news is always empty
        {:ok, analysis, []}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:deepseek_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:deepseek_request, reason}}
    end
  end

  @impl true
  def analyze(asset, snapshot, signal, news) do
    recommendation = Shared.recommendation_from_signal(signal)

    body = %{
      model: @model,
      messages: [
        %{role: "system", content: Shared.system_prompt_with_signal(:no_search, signal)},
        %{
          role: "user",
          content: Shared.user_prompt_with_signal(asset, snapshot, signal, news, search: false)
        }
      ],
      temperature: 0.7,
      max_tokens: 600
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        tokens = get_in(resp, ["usage", "total_tokens"]) || 0
        text = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        analysis = Shared.parse_analysis(text, tokens)
        # DeepSeek has no web search — news is always empty
        {:ok, %{analysis | recommendation: recommendation}, []}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:deepseek_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:deepseek_request, reason}}
    end
  end

  @impl true
  def generate_retro(prompt) do
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: Shared.retro_system_prompt()},
        %{role: "user", content: prompt}
      ],
      temperature: 0.7,
      max_tokens: 4096
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        text = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        {:ok, text}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:deepseek_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:deepseek_request, reason}}
    end
  end

  defp api_request(body) do
    Req.post(@api_url,
      json: body,
      headers: [
        {"authorization", "Bearer #{Watchman.Config.deepseek_api_key()}"},
        {"content-type", "application/json"}
      ],
      receive_timeout: 90_000,
      retry: :transient,
      max_retries: 3
    )
  end
end
