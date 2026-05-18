defmodule Watchman.AI.Shared do
  @moduledoc "Shared prompts and utilities for all AI providers."

  @doc """
  Returns the system prompt for the given search capability variant.

  - `:web_search_tool` — Claude (uses web_search tool)
  - `:search_grounding` — Gemini (uses built-in search grounding)
  - `:no_search` — DeepSeek (no web access, uses knowledge only)
  """
  def system_prompt(variant) do
    search_instruction = search_instruction(variant)

    """
    Você é um analista financeiro brasileiro especializado em ações e fundos imobiliários da B3.

    Sua tarefa é analisar a movimentação de um ativo e determinar se a variação é fundamentada ou especulativa.

    #{search_instruction}

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

  defp search_instruction(:web_search_tool),
    do:
      "Use a ferramenta web_search para buscar notícias recentes, relatórios e opiniões de analistas sobre o ativo."

  defp search_instruction(:search_grounding),
    do:
      "Use sua capacidade de busca para encontrar notícias recentes, relatórios e opiniões de analistas sobre o ativo."

  defp search_instruction(:no_search),
    do:
      "Com base no seu conhecimento, analise o contexto macroeconômico e as características do ativo."

  @doc """
  Returns the user prompt for an asset analysis.

  Options:
  - `search: true` (default) — asks to search for recent news
  - `search: false` — uses knowledge only (for providers without web access)
  """
  def user_prompt(asset, snapshot, opts \\ []) do
    search = Keyword.get(opts, :search, true)

    final_line =
      if search do
        "Busque notícias recentes e determine: esta movimentação é fundamentada ou é ruído de mercado?"
      else
        "Com base no seu conhecimento sobre o mercado brasileiro, determine: esta movimentação é fundamentada ou é ruído de mercado?"
      end

    """
    Analise o ativo #{asset.ticker} (#{asset.name || "sem nome"}, tipo: #{asset.type || "desconhecido"}).

    Dados atuais:
    - Preço: R$ #{snapshot.price}
    - Variação dia: #{format_var(snapshot.variation_day)}
    - Variação semana: #{format_var(snapshot.variation_week)}
    - Variação mês: #{format_var(snapshot.variation_month)}
    - Data: #{Date.utc_today()}

    #{final_line}
    """
  end

  @doc "Returns the system prompt for retrospective generation."
  def retro_system_prompt do
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

  @doc ~S(Formats a variation value. nil → "N/A", val → "val%")
  def format_var(nil), do: "N/A"
  def format_var(val), do: "#{val}%"

  @doc """
  Parses a JSON analysis response from an AI provider.

  Strips markdown fences, decodes JSON, and builds a structured analysis map.
  Returns a fallback map on decode failure.
  """
  def parse_analysis(text, tokens) do
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
          justification:
            "Falha ao processar resposta da IA. Resposta bruta: #{String.slice(text, 0..500)}",
          tokens_used: tokens
        }
    end
  end

  @doc "Extracts the domain host from a URL. Returns nil for nil input, falls back to the raw URL."
  def extract_domain(nil), do: nil

  def extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> url
    end
  end
end
