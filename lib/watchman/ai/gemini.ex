defmodule Watchman.AI.Gemini do
  @behaviour Watchman.AI.Provider

  @model "gemini-2.5-flash"
  @base_url "https://generativelanguage.googleapis.com/v1beta"

  @impl true
  def analyze(asset, snapshot) do
    url = "#{@base_url}/models/#{@model}:generateContent"

    body = %{
      system_instruction: %{parts: [%{text: system_prompt()}]},
      contents: [%{role: "user", parts: [%{text: user_prompt(asset, snapshot)}]}],
      tools: [%{google_search: %{}}],
      generationConfig: %{temperature: 0.7, maxOutputTokens: 4096}
    }

    case Req.post(url, json: body, params: [key: Watchman.Config.gemini_api_key()], receive_timeout: 90_000, retry: :transient, max_retries: 3) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        tokens = get_in(resp, ["usageMetadata", "totalTokenCount"]) || 0
        text = extract_text(resp)
        news = extract_grounding_sources(resp)
        analysis = parse_analysis(text, tokens)
        {:ok, analysis, news}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:gemini_api, status, body}}

      {:error, reason} ->
        {:error, {:gemini_request, reason}}
    end
  end

  @impl true
  def generate_retro(prompt) do
    url = "#{@base_url}/models/#{@model}:generateContent"

    body = %{
      system_instruction: %{parts: [%{text: retro_system_prompt()}]},
      contents: [%{role: "user", parts: [%{text: prompt}]}],
      generationConfig: %{temperature: 0.7, maxOutputTokens: 4096}
    }

    case Req.post(url, json: body, params: [key: Watchman.Config.gemini_api_key()], receive_timeout: 90_000, retry: :transient, max_retries: 3) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:ok, extract_text(resp)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:gemini_api, status, body}}

      {:error, reason} ->
        {:error, {:gemini_request, reason}}
    end
  end

  defp extract_text(resp) do
    get_in(resp, ["candidates", Access.at(0), "content", "parts", Access.at(0), "text"]) || ""
  end

  defp extract_grounding_sources(resp) do
    chunks = get_in(resp, ["candidates", Access.at(0), "groundingMetadata", "groundingChunks"]) || []

    chunks
    |> Enum.filter(&get_in(&1, ["web"]))
    |> Enum.uniq_by(&get_in(&1, ["web", "uri"]))
    |> Enum.map(fn chunk ->
      web = chunk["web"]
      %{
        title: web["title"],
        summary: nil,
        source: extract_domain(web["uri"]),
        url: web["uri"],
        published_at: nil
      }
    end)
  end

  defp parse_analysis(text, tokens) do
    json_str = Regex.replace(~r/```(?:json)?\n?|\n?```/, text, "") |> String.trim()

    case Jason.decode(json_str) do
      {:ok, map} ->
        %{
          cause: map["cause"],
          is_specific_problem: map["is_specific_problem"] || false,
          macro_context: map["macro_context"],
          recommendation: map["recommendation"] || "investigar",
          justification: map["justification"],
          tokens_used: tokens
        }

      {:error, _} ->
        %{
          cause: nil,
          is_specific_problem: false,
          macro_context: nil,
          recommendation: "investigar",
          justification: "Falha ao processar resposta da IA. Resposta bruta: #{String.slice(text, 0..500)}",
          tokens_used: tokens
        }
    end
  end

  defp extract_domain(nil), do: nil
  defp extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> url
    end
  end

  defp system_prompt do
    """
    Você é um analista financeiro brasileiro especializado em ações e fundos imobiliários da B3.

    Sua tarefa é analisar a movimentação de um ativo e determinar se a variação é fundamentada ou especulativa.

    Use a ferramenta web_search para buscar notícias recentes, relatórios e opiniões de analistas sobre o ativo.

    Responda APENAS com um objeto JSON válido (sem markdown, sem texto adicional) com esta estrutura:

    {
      "cause": "explicação breve do que causou a movimentação",
      "is_specific_problem": true/false,
      "macro_context": "contexto macroeconômico relevante, se houver",
      "recommendation": "manter" | "investigar" | "vender",
      "justification": "justificativa de 2-3 frases para a recomendação"
    }

    Regras:
    - "manter": variação normal, sem preocupação
    - "investigar": sinais que merecem atenção, mas sem ação imediata
    - "vender": problema grave identificado que justifica reavaliação da posição
    - is_specific_problem: true se o problema é específico da empresa, false se é macro/setorial
    """
  end

  defp user_prompt(asset, snapshot) do
    """
    Analise o ativo #{asset.ticker} (#{asset.name || "sem nome"}, tipo: #{asset.type || "desconhecido"}).

    Dados atuais:
    - Preço: R$ #{snapshot.price}
    - Variação dia: #{format_var(snapshot.variation_day)}
    - Variação semana: #{format_var(snapshot.variation_week)}
    - Variação mês: #{format_var(snapshot.variation_month)}
    - Data: #{Date.utc_today()}

    Busque notícias recentes e determine: esta movimentação é fundamentada ou é ruído de mercado?
    """
  end

  defp retro_system_prompt do
    """
    Você é um analista financeiro brasileiro. Analise os dados históricos fornecidos e gere uma retrospectiva.

    Identifique:
    - Tendências nos ativos monitorados
    - Alertas que se confirmaram ou não
    - Padrões recorrentes
    - Mudanças de recomendação ao longo do período

    Responda em português, de forma clara e objetiva.
    """
  end

  defp format_var(nil), do: "N/A"
  defp format_var(val), do: "#{val}%"
end
