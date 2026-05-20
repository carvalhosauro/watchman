defmodule Watchman.News.Infomoney do
  @moduledoc """
  News adapter for Infomoney per-ticker RSS feeds.

  Fetches news for a given B3 ticker from the Infomoney RSS endpoint:
  `https://www.infomoney.com.br/mercados/[ticker-lowercase]/feed/`

  Implements `Watchman.News.Provider`.
  """

  @behaviour Watchman.News.Provider

  import SweetXml, only: [xpath: 3, sigil_x: 2]

  alias Watchman.Models.NewsItem

  @base_url "https://www.infomoney.com.br/mercados"
  @max_items 10
  @req_timeout 10_000

  @months %{
    "Jan" => "01",
    "Feb" => "02",
    "Mar" => "03",
    "Apr" => "04",
    "May" => "05",
    "Jun" => "06",
    "Jul" => "07",
    "Aug" => "08",
    "Sep" => "09",
    "Oct" => "10",
    "Nov" => "11",
    "Dec" => "12"
  }

  @impl true
  @spec fetch(String.t(), keyword()) :: {:ok, [NewsItem.t()]} | {:error, term()}
  def fetch(ticker, _opts \\ []) do
    url = "#{@base_url}/#{String.downcase(ticker)}/feed/"

    case Req.get(url, receive_timeout: @req_timeout, retry: :transient) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_response(body, ticker)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:infomoney_http, status, body}}

      {:error, reason} ->
        {:error, {:infomoney_request, reason}}
    end
  end

  @spec parse_response(binary(), String.t()) :: {:ok, [NewsItem.t()]} | {:error, term()}
  def parse_response(body, _ticker) do
    items =
      xpath(
        body,
        ~x"//item"l,
        title: ~x"./title/text()"s,
        url: ~x"./link/text()"s,
        pub_date: ~x"./pubDate/text()"s
      )

    news_items =
      items
      |> Enum.take(@max_items)
      |> Enum.map(&build_news_item/1)

    {:ok, news_items}
  rescue
    e -> {:error, {:parse_error, e}}
  catch
    _kind, reason -> {:error, {:parse_error, reason}}
  end

  defp build_news_item(item) do
    title = item[:title]

    %NewsItem{
      source: "infomoney",
      category: categorize(title),
      title: title,
      url: item[:url],
      published_at: parse_pub_date(item[:pub_date])
    }
  end

  defp categorize(title) do
    lower = String.downcase(title)

    cond do
      String.contains?(lower, ["dividendo", "jcp", "juros sobre capital"]) ->
        "dividend"

      String.contains?(lower, ["resultado", "balanço", "lucro", "receita", "trimestre"]) ->
        "financial_result"

      String.contains?(lower, ["fato relevante", "material fact"]) ->
        "material_fact"

      true ->
        "other"
    end
  end

  defp parse_pub_date(""), do: nil

  defp parse_pub_date(pub_date) do
    case do_parse_rfc822(pub_date) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp do_parse_rfc822(pub_date) do
    regex =
      ~r/(?:\w+,\s+)?(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}:\d{2}:\d{2})\s+([+-]\d{4}|UTC|GMT)/

    with [_, day, month_str, year, time, tz] <- Regex.run(regex, pub_date),
         month = Map.get(@months, month_str, "01"),
         day_padded = String.pad_leading(day, 2, "0"),
         iso = "#{year}-#{month}-#{day_padded}T#{time}#{format_tz_offset(tz)}",
         {:ok, dt, _offset} <- DateTime.from_iso8601(iso) do
      {:ok, DateTime.truncate(dt, :second)}
    else
      _ -> {:error, :invalid_date}
    end
  end

  defp format_tz_offset("UTC"), do: "Z"
  defp format_tz_offset("GMT"), do: "Z"

  defp format_tz_offset(<<sign::binary-size(1), hours::binary-size(2), minutes::binary-size(2)>>) do
    "#{sign}#{hours}:#{minutes}"
  end

  defp format_tz_offset(offset), do: offset
end
