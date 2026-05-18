defmodule Watchman.Parser do
  @moduledoc "Extracts structured analysis and news from AI responses."

  alias Watchman.AI.Shared

  @doc "Extracts structured analysis and news items from Claude API response"
  def extract(%{content: content_blocks, tokens: tokens}) do
    news = extract_news(content_blocks)
    analysis = extract_analysis(content_blocks, tokens)
    {:ok, analysis, news}
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
        source: Shared.extract_domain(result["url"]),
        url: result["url"],
        published_at: parse_date(result["published_date"])
      }
    end)
  end

  defp extract_analysis(blocks, tokens) do
    text =
      blocks
      |> Enum.filter(&match?(%{"type" => "text"}, &1))
      |> List.last()
      |> case do
        %{"text" => text} -> text
        _ -> ""
      end

    Shared.parse_analysis(text, tokens)
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
