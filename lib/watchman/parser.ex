defmodule Watchman.Parser do
  @moduledoc "Extracts structured analysis and news from AI responses."

  @doc "Extracts structured analysis and news items from Claude API response"
  def extract(%{content: content_blocks, tokens: tokens}) do
    news = extract_news(content_blocks)
    analysis = extract_analysis(content_blocks)
    {:ok, Map.put(analysis, :tokens_used, tokens), news}
  end

  defp extract_news(blocks) do
    blocks
    |> Enum.filter(&match?(%{"type" => "tool_result"}, &1))
    |> Enum.flat_map(fn block ->
      (block["content"] || [])
      |> Enum.filter(&match?(%{"type" => "web_search_results"}, &1))
      |> Enum.flat_map(&Map.get(&1, "results", []))
    end)
    |> Enum.uniq_by(&Map.get(&1, "url"))
    |> Enum.map(fn result ->
      %{
        title: result["title"],
        summary: result["snippet"] || result["content"],
        source: extract_domain(result["url"]),
        url: result["url"],
        published_at: parse_date(result["published_date"])
      }
    end)
  end

  defp extract_analysis(blocks) do
    text =
      blocks
      |> Enum.filter(&match?(%{"type" => "text"}, &1))
      |> List.last()
      |> case do
        %{"text" => text} -> text
        _ -> ""
      end

    # Strip markdown code fences if present
    json_str = Regex.replace(~r/```(?:json)?\n?|\n?```/, text, "") |> String.trim()

    case Jason.decode(json_str) do
      {:ok, map} ->
        %{
          cause: map["cause"],
          is_specific_problem: map["is_specific_problem"] || false,
          macro_context: map["macro_context"],
          recommendation: map["recommendation"] || "investigar",
          justification: map["justification"]
        }

      {:error, _} ->
        %{
          cause: nil,
          is_specific_problem: false,
          macro_context: nil,
          recommendation: "investigar",
          justification:
            "Falha ao processar resposta da IA. Resposta bruta: #{String.slice(text, 0..500)}"
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

  defp parse_date(nil), do: nil

  defp parse_date(date_str) when is_binary(date_str) do
    case DateTime.from_iso8601(date_str) do
      {:ok, dt, _} ->
        dt

      _ ->
        case Date.from_iso8601(date_str) do
          {:ok, d} -> DateTime.new!(d, ~T[00:00:00], "Etc/UTC")
          _ -> nil
        end
    end
  end
end
