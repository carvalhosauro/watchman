defmodule Watchman.AI.Claude do
  @behaviour Watchman.AI.Provider

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"

  @impl true
  def analyze(asset, snapshot) do
    body = %{
      model: @model,
      max_tokens: 4096,
      system: system_prompt(),
      tools: [%{type: "web_search_20250305"}],
      messages: [%{role: "user", content: user_prompt(asset, snapshot)}]
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
      system: retro_system_prompt(),
      messages: [%{role: "user", content: prompt}]
    }

    case api_request(body) do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        text =
          resp_body["content"]
          |> Enum.find(&(&1["type"] == "text"))
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
      receive_timeout: 90_000
    )
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
