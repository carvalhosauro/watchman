defmodule Watchman.AI.Gemini do
  @moduledoc "Gemini (Google) AI provider with search grounding."

  @behaviour Watchman.AI.Provider

  alias Watchman.AI.Shared

  @model "gemini-2.5-flash"
  @base_url "https://generativelanguage.googleapis.com/v1beta"

  @impl true
  def analyze(asset, snapshot) do
    url = "#{@base_url}/models/#{@model}:generateContent"

    body = %{
      system_instruction: %{parts: [%{text: Shared.system_prompt(:search_grounding)}]},
      contents: [%{role: "user", parts: [%{text: Shared.user_prompt(asset, snapshot)}]}],
      tools: [%{google_search: %{}}],
      generationConfig: %{temperature: 0.7, maxOutputTokens: 4096}
    }

    case Req.post(url,
           json: body,
           params: [key: Watchman.Config.gemini_api_key()],
           receive_timeout: 90_000,
           retry: :transient,
           max_retries: 3
         ) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        tokens = get_in(resp, ["usageMetadata", "totalTokenCount"]) || 0
        text = extract_text(resp)
        news = extract_grounding_sources(resp)
        analysis = Shared.parse_analysis(text, tokens)
        {:ok, analysis, news}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:gemini_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:gemini_request, reason}}
    end
  end

  @impl true
  def analyze(asset, snapshot, signal, news) do
    url = "#{@base_url}/models/#{@model}:generateContent"
    recommendation = Shared.recommendation_from_signal(signal)

    body = %{
      system_instruction: %{
        parts: [%{text: Shared.system_prompt_with_signal(:search_grounding, signal)}]
      },
      contents: [
        %{
          role: "user",
          parts: [%{text: Shared.user_prompt_with_signal(asset, snapshot, signal, news)}]
        }
      ],
      tools: [%{google_search: %{}}],
      generationConfig: %{temperature: 0.7, maxOutputTokens: 600}
    }

    case Req.post(url,
           json: body,
           params: [key: Watchman.Config.gemini_api_key()],
           receive_timeout: 90_000,
           retry: :transient,
           max_retries: 3
         ) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        tokens = get_in(resp, ["usageMetadata", "totalTokenCount"]) || 0
        text = extract_text(resp)
        returned_news = extract_grounding_sources(resp)
        analysis = Shared.parse_analysis(text, tokens)
        {:ok, %{analysis | recommendation: recommendation}, returned_news}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:gemini_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:gemini_request, reason}}
    end
  end

  @impl true
  def generate_retro(prompt) do
    url = "#{@base_url}/models/#{@model}:generateContent"

    body = %{
      system_instruction: %{parts: [%{text: Shared.retro_system_prompt()}]},
      contents: [%{role: "user", parts: [%{text: prompt}]}],
      generationConfig: %{temperature: 0.7, maxOutputTokens: 4096}
    }

    case Req.post(url,
           json: body,
           params: [key: Watchman.Config.gemini_api_key()],
           receive_timeout: 90_000,
           retry: :transient,
           max_retries: 3
         ) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:ok, extract_text(resp)}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:gemini_api, status, resp_body}}

      {:error, reason} ->
        {:error, {:gemini_request, reason}}
    end
  end

  defp extract_text(resp) do
    get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) || ""
  end

  defp extract_grounding_sources(resp) do
    chunks =
      get_in(resp, ["candidates", Access.at(0), "groundingMetadata", "groundingChunks"]) || []

    chunks
    |> Enum.filter(&get_in(&1, ["web"]))
    |> Enum.uniq_by(&get_in(&1, ["web", "uri"]))
    |> Enum.map(fn chunk ->
      web = chunk["web"]

      %{
        title: web["title"],
        summary: nil,
        source: Shared.extract_domain(web["uri"]),
        url: web["uri"],
        published_at: nil
      }
    end)
  end
end
