defmodule Watchman.AI.Deepseek do
  @behaviour Watchman.AI.Provider

  @api_url "https://api.deepseek.com/chat/completions"
  @model "deepseek-chat"

  @impl true
  def analyze(asset, snapshot) do
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: system_prompt()},
        %{role: "user", content: user_prompt(asset, snapshot)}
      ],
      temperature: 0.7,
      max_tokens: 4096
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        tokens = get_in(resp, ["usage", "total_tokens"]) || 0
        text = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        analysis = parse_analysis(text, tokens)
        # DeepSeek has no web search — news is always empty
        {:ok, analysis, []}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:deepseek_api, status, body}}

      {:error, reason} ->
        {:error, {:deepseek_request, reason}}
    end
  end

  @impl true
  def generate_retro(prompt) do
    body = %{
      model: @model,
      messages: [
        %{role: "system", content: retro_system_prompt()},
        %{role: "user", content: prompt}
      ],
      temperature: 0.7,
      max_tokens: 4096
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp}} ->
        text = get_in(resp, ["choices", Access.at(0), "message", "content"]) || ""
        {:ok, text}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:deepseek_api, status, body}}

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

  defp system_prompt do
    """
    Você é um analista financeiro brasileiro especializado em ações e fundos imobiliários da B3.

    Sua tarefa é analisar a movimentação de um ativo e determinar se a variação é fundamentada ou especulativa.

    Com base no seu conhecimento, analise o contexto macroeconômico e as características do ativo.

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
