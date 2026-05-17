defmodule Watchman.Retro do
  alias Watchman.Repo
  alias Watchman.Models.{Asset, Analysis, PriceSnapshot, NewsItem, Retrospective}
  import Ecto.Query

  def generate(period_type) when period_type in [:weekly, :monthly] do
    {start_date, end_date} = date_range(period_type)

    IO.puts("Generating #{period_type} retrospective (#{start_date} to #{end_date})...\n")

    data = fetch_period_data(start_date, end_date)

    if data == [] do
      IO.puts("No analyses found for this period.")
      :ok
    else
      prompt = build_prompt(data, period_type, start_date, end_date)

      case Watchman.AI.Factory.provider().generate_retro(prompt) do
        {:ok, content} ->
          persist_retro(period_type, start_date, end_date, content)
          IO.puts(content)
          {:ok, content}

        {:error, reason} ->
          IO.puts("Failed to generate retrospective: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp date_range(:weekly) do
    today = Date.utc_today()
    start_date = Date.add(today, -7)
    {start_date, today}
  end

  defp date_range(:monthly) do
    today = Date.utc_today()
    start_date = Date.add(today, -30)
    {start_date, today}
  end

  defp fetch_period_data(start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    Repo.all(
      from a in Analysis,
        join: asset in Asset, on: a.asset_id == asset.id,
        join: s in PriceSnapshot, on: a.snapshot_id == s.id,
        left_join: n in NewsItem, on: n.asset_id == asset.id and n.fetched_at >= ^start_dt and n.fetched_at <= ^end_dt,
        where: a.analyzed_at >= ^start_dt and a.analyzed_at <= ^end_dt,
        select: %{
          ticker: asset.ticker,
          asset_type: asset.type,
          price: s.price,
          variation_day: s.variation_day,
          cause: a.cause,
          is_specific_problem: a.is_specific_problem,
          macro_context: a.macro_context,
          recommendation: a.recommendation,
          justification: a.justification,
          analyzed_at: a.analyzed_at,
          news_title: n.title,
          news_source: n.source
        },
        order_by: [asc: asset.ticker, asc: a.analyzed_at]
    )
  end

  defp build_prompt(data, period_type, start_date, end_date) do
    grouped = Enum.group_by(data, & &1.ticker)

    assets_text =
      grouped
      |> Enum.map(fn {ticker, entries} ->
        analyses_text =
          entries
          |> Enum.uniq_by(& &1.analyzed_at)
          |> Enum.map(fn e ->
            """
            - Data: #{e.analyzed_at}
              Preço: R$ #{e.price}, Variação dia: #{e.variation_day || "N/A"}%
              Causa: #{e.cause || "não identificada"}
              Problema específico: #{e.is_specific_problem}
              Contexto macro: #{e.macro_context || "N/A"}
              Recomendação: #{e.recommendation}
              Justificativa: #{e.justification}
            """
          end)
          |> Enum.join("\n")

        news_text =
          entries
          |> Enum.filter(& &1.news_title)
          |> Enum.uniq_by(& &1.news_title)
          |> Enum.map(fn e -> "  - #{e.news_title} (#{e.news_source})" end)
          |> Enum.join("\n")

        """
        ## #{ticker} (#{List.first(entries).asset_type || "tipo desconhecido"})

        Análises:
        #{analyses_text}
        #{if news_text != "", do: "Notícias:\n#{news_text}", else: ""}
        """
      end)
      |> Enum.join("\n---\n")

    """
    Gere uma retrospectiva #{period_type} para o período de #{start_date} a #{end_date}.

    Dados coletados:

    #{assets_text}

    Analise:
    1. Tendências observadas em cada ativo
    2. Recomendações que se mantiveram ou mudaram
    3. Alertas que merecem atenção continuada
    4. Visão geral do período para a carteira
    """
  end

  defp persist_retro(period_type, start_date, end_date, content) do
    attrs = %{
      period_type: to_string(period_type),
      start_date: start_date,
      end_date: end_date,
      content: content,
      generated_at: DateTime.utc_now()
    }

    Repo.insert!(Retrospective.changeset(%Retrospective{}, attrs))
  end
end
