defmodule Watchman.AI.Shared do
  @moduledoc "Shared prompts and utilities for all AI providers."

  alias Watchman.Analysis.Signal

  @doc """
  Returns the system prompt for the given search capability variant.

  - `:web_search_tool` — Claude (uses web_search tool)
  - `:search_grounding` — Gemini (uses built-in search grounding)
  - `:no_search` — DeepSeek (no web access, uses knowledge only)
  """
  @spec system_prompt(:web_search_tool | :search_grounding | :no_search) :: String.t()
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

  @doc """
  Returns the system prompt for signal-enrichment calls (`analyze/4`).

  The signal block is injected at the very top so the model sees it first.
  The model is instructed to explain and enrich the signal in Portuguese —
  never to re-classify the asset or contradict the rule-engine decision.

  The `~300 token` cap on `justification` is enforced via the prompt rules;
  `max_tokens` / `maxOutputTokens` must be set to ≤ 600 in each adapter.
  """
  @spec system_prompt_with_signal(:web_search_tool | :search_grounding | :no_search, Signal.t()) ::
          String.t()
  def system_prompt_with_signal(variant, signal) do
    search_instruction = search_instruction(variant)
    signal_str = format_signal(signal)

    """
    #{signal_str}

    Você é um analista financeiro brasileiro especializado em ações e fundos imobiliários da B3.

    O motor de regras já classificou este ativo com o sinal acima. Sua tarefa é EXPLICAR e
    ENRIQUECER o sinal em português — não reclassifique o ativo nem contradiga o sinal.

    #{search_instruction}

    Responda APENAS com um objeto JSON válido (sem markdown, sem texto adicional) com esta estrutura:

    {
      "cause": "explicação breve do que causou a movimentação",
      "is_specific_problem": true/false,
      "macro_context": "contexto macroeconômico relevante, se houver",
      "recommendation": "manter" | "investigar" | "vender",
      "justification": "narrativa de 2-3 frases em português explicando o sinal"
    }

    Regras:
    - "manter": variação normal, sem preocupação
    - "investigar": sinais que merecem atenção, mas sem ação imediata
    - "vender": problema grave identificado que justifica reavaliação da posição
    - is_specific_problem: true se o problema é específico da empresa, false se é macro/setorial
    - Limite: justification deve ter no máximo 3 frases curtas (~300 tokens total)
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
  @spec user_prompt(map(), map(), keyword()) :: String.t()
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

  @doc """
  Returns the user prompt for signal-enrichment calls (`analyze/4`).

  Includes asset/snapshot data plus up to 5 pre-fetched news items, then
  directs the model to explain the already-computed signal rather than
  re-derive a classification.

  Options:
  - `search: true` (default) — asks to search for additional context
  - `search: false` — uses knowledge only (for providers without web access)
  """
  @spec user_prompt_with_signal(map(), map(), Signal.t(), list(), keyword()) :: String.t()
  def user_prompt_with_signal(asset, snapshot, _signal, news, opts \\ []) do
    search = Keyword.get(opts, :search, true)

    final_line =
      if search do
        "Busque contexto adicional e explique em português o que está causando este sinal."
      else
        "Com base no seu conhecimento do mercado brasileiro, explique em português o que está causando este sinal."
      end

    news_section = format_news_items(news)

    """
    Ativo: #{asset.ticker} (#{asset.name || "sem nome"}, tipo: #{asset.type || "desconhecido"})

    Dados atuais:
    - Preço: R$ #{snapshot.price}
    - Variação dia: #{format_var(snapshot.variation_day)}
    - Variação semana: #{format_var(snapshot.variation_week)}
    - Variação mês: #{format_var(snapshot.variation_month)}
    - Data: #{Date.utc_today()}
    #{news_section}
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

  @doc """
  Formats a `%Signal{}` as a two-line header for injection into system prompts.

  Example output:

      Signal: HIGH BEARISH (confidence 0.78).
      Reasons: Price 2.3σ below 21-day average; 3 consecutive down days.
  """
  @spec format_signal(Signal.t()) :: String.t()
  def format_signal(%Signal{
        level: level,
        direction: direction,
        confidence: confidence,
        reasons: reasons
      }) do
    level_str = level |> Atom.to_string() |> String.upcase()
    dir_str = direction |> Atom.to_string() |> String.upcase()
    conf_str = :erlang.float_to_binary(confidence, decimals: 2)
    reasons_str = Enum.join(reasons, "; ")

    "Signal: #{level_str} #{dir_str} (confidence #{conf_str}).\nReasons: #{reasons_str}"
  end

  @doc """
  Maps a `%Signal{}` to a recommendation string based on level and direction.

  The mapping convention is:

  | level            | direction  | recommendation |
  |------------------|------------|----------------|
  | `:noise`         | any        | `"manter"`     |
  | `:high`          | `:bullish` | `"investigar"` |
  | `:medium`, `:low`| `:bullish` | `"manter"`     |
  | `:high`, `:medium`| `:bearish`| `"vender"`     |
  | `:low`           | `:bearish` | `"investigar"` |
  | any (non-noise)  | `:neutral` | `"investigar"` |

  Used by each adapter's `analyze/4` to override the model's own
  `recommendation` field with a deterministic, rule-engine-derived value.
  """
  @spec recommendation_from_signal(Signal.t()) :: String.t()
  def recommendation_from_signal(%Signal{level: :noise}), do: "manter"
  def recommendation_from_signal(%Signal{direction: :bullish, level: :high}), do: "investigar"
  def recommendation_from_signal(%Signal{direction: :bullish}), do: "manter"
  def recommendation_from_signal(%Signal{direction: :bearish, level: :low}), do: "investigar"
  def recommendation_from_signal(%Signal{direction: :bearish}), do: "vender"
  def recommendation_from_signal(%Signal{direction: :neutral}), do: "investigar"

  @doc """
  Formats up to 5 news items as a bulleted list for inclusion in prompts.

  Accepts `%Watchman.Models.NewsItem{}` structs or plain maps with the
  same fields (`title`, `summary`, `published_at`). Returns an empty
  string when the list is empty so callers can embed the result directly
  without conditionals.
  """
  @spec format_news_items(list()) :: String.t()
  def format_news_items([]), do: ""

  def format_news_items(news) do
    items =
      news
      |> Enum.take(5)
      |> Enum.map_join("\n", fn item ->
        date =
          if item.published_at,
            do: " (#{DateTime.to_date(item.published_at)})",
            else: ""

        "- #{item.title || "Sem título"}#{date}: #{item.summary || "Sem resumo"}"
      end)

    "\nNotícias recentes:\n#{items}\n"
  end

  @doc ~S(Formats a variation value. nil → "N/A", val → "val%")
  @spec format_var(number() | nil) :: String.t()
  def format_var(nil), do: "N/A"
  def format_var(val), do: "#{val}%"

  @doc """
  Parses a JSON analysis response from an AI provider.

  Strips markdown fences, decodes JSON, and builds a structured analysis map.
  Returns a fallback map on decode failure.
  """
  @spec parse_analysis(String.t(), integer()) :: Watchman.AI.Provider.analysis_result()
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
  @spec extract_domain(String.t() | nil) :: String.t() | nil
  def extract_domain(nil), do: nil

  def extract_domain(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> url
    end
  end
end
