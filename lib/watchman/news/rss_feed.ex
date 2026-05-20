defmodule Watchman.News.RssFeed do
  @moduledoc """
  News adapter that fetches items from multiple RSS feeds and filters by ticker.

  Implements `Watchman.News.Provider`. Reads a config-provided list of RSS feed
  URLs, fetches each in turn, and tags items with the outlet name as source.
  Items are filtered by ticker presence in title or summary using
  `Watchman.News.TickerAliases.for/1`.

  Each feed is capped at 20 items (applied before ticker filtering) so the
  per-feed budget is predictable regardless of match volume.
  """

  @behaviour Watchman.News.Provider

  require Logger
  import SweetXml

  alias Watchman.Models.NewsItem
  alias Watchman.News.TickerAliases

  @default_feeds [
    %{name: "valor", url: "https://valor.globo.com/empresas/rss/"},
    %{name: "money_times", url: "https://www.moneytimes.com.br/feed/"},
    %{name: "investnews", url: "https://investnews.com.br/feed/"},
    %{name: "suno", url: "https://www.suno.com.br/noticias/feed/"},
    %{name: "brazil_journal", url: "https://braziljournal.com/feed/"}
  ]

  @months %{
    "Jan" => 1,
    "Feb" => 2,
    "Mar" => 3,
    "Apr" => 4,
    "May" => 5,
    "Jun" => 6,
    "Jul" => 7,
    "Aug" => 8,
    "Sep" => 9,
    "Oct" => 10,
    "Nov" => 11,
    "Dec" => 12
  }

  @doc """
  Returns the default list of RSS feeds (5 outlets).
  """
  @spec default_feeds() :: [%{name: String.t(), url: String.t()}]
  def default_feeds, do: @default_feeds

  @doc """
  Fetches news items for `ticker` from all configured RSS feeds.

  Accepts the following option:
  - `:feeds` — list of `%{name: String.t(), url: String.t()}` maps. Defaults
    to `default_feeds/0`.

  Single-feed failures are logged and skipped; the adapter always returns
  `{:ok, items}` where items may be empty. Items are sorted by `published_at`
  descending.
  """
  @impl Watchman.News.Provider
  @spec fetch(String.t(), keyword()) :: {:ok, [NewsItem.t()]} | {:error, term()}
  def fetch(ticker, opts \\ []) do
    feeds = Keyword.get(opts, :feeds, default_feeds())

    items =
      feeds
      |> Enum.flat_map(fn %{name: name, url: url} -> fetch_feed(url, name, ticker) end)
      |> Enum.sort_by(& &1.published_at, {:desc, DateTime})

    {:ok, items}
  end

  @doc """
  Parses an RSS feed `body` and returns items that mention `ticker`.

  The 20-item cap is applied before ticker filtering so the per-feed budget
  is respected regardless of how many items match. The `outlet_name` becomes
  the `source` field on every returned `NewsItem`.
  """
  @spec parse_response(binary(), String.t(), String.t()) ::
          {:ok, [NewsItem.t()]} | {:error, term()}
  def parse_response(body, ticker, outlet_name) do
    aliases = TickerAliases.for(ticker)

    items =
      body
      |> xpath(
        ~x"//item"l,
        title: ~x"./title/text()"s,
        link: ~x"./link/text()"s,
        pub_date: ~x"./pubDate/text()"s,
        description: ~x"./description/text()"s
      )
      |> Enum.take(20)
      |> Enum.filter(&matches_ticker?(&1, aliases))
      |> Enum.map(&build_news_item(&1, outlet_name))

    {:ok, items}
  rescue
    e -> {:error, e}
  catch
    _, reason -> {:error, reason}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_feed(url, name, ticker) do
    case Req.get(url, receive_timeout: 10_000, retry: :transient) do
      {:ok, %{status: 200, body: body}} ->
        case parse_response(body, ticker, name) do
          {:ok, items} ->
            items

          {:error, reason} ->
            Logger.warning("RssFeed: failed to parse feed #{name}: #{inspect(reason)}")
            []
        end

      {:ok, %{status: status}} ->
        Logger.warning("RssFeed: unexpected status #{status} for feed #{name}")
        []

      {:error, reason} ->
        Logger.warning("RssFeed: failed to fetch feed #{name}: #{inspect(reason)}")
        []
    end
  end

  defp matches_ticker?(%{title: title, description: desc}, aliases) do
    text = String.downcase(title <> " " <> desc)
    Enum.any?(aliases, &String.contains?(text, String.downcase(&1)))
  end

  defp build_news_item(%{title: title, link: url, pub_date: pub_date, description: desc}, outlet) do
    %NewsItem{
      title: title,
      url: url,
      summary: desc,
      source: outlet,
      category: categorize(title),
      published_at: parse_pub_date(pub_date),
      fetched_at: DateTime.utc_now()
    }
  end

  defp categorize(title) do
    lower = String.downcase(title)

    cond do
      String.contains?(lower, "dividendo") ->
        "dividend"

      String.contains?(lower, "resultado") or
        String.contains?(lower, "balanço") or
          String.contains?(lower, "lucro") ->
        "financial_result"

      String.contains?(lower, "fato relevante") ->
        "material_fact"

      true ->
        "other"
    end
  end

  defp parse_pub_date(""), do: DateTime.utc_now()

  defp parse_pub_date(str) do
    # RFC 822: optional "Mon, " day-of-week prefix, then "20 May 2026 10:30:00 +0000"
    stripped =
      case String.split(str, ", ", parts: 2) do
        [_dow, rest] -> String.trim(rest)
        _ -> String.trim(str)
      end

    case String.split(stripped) do
      [day_s, month_s, year_s, time_s | tz_parts] ->
        with {day, ""} <- Integer.parse(day_s),
             {:ok, month} <- Map.fetch(@months, month_s),
             {year, ""} <- Integer.parse(year_s),
             [h_s, m_s, s_s] <- String.split(time_s, ":"),
             {hour, ""} <- Integer.parse(h_s),
             {minute, ""} <- Integer.parse(m_s),
             {second, ""} <- Integer.parse(s_s),
             {:ok, naive} <- NaiveDateTime.new(year, month, day, hour, minute, second),
             {:ok, dt} <- DateTime.from_naive(naive, "Etc/UTC") do
          DateTime.add(dt, -tz_offset_seconds(List.first(tz_parts, "+0000")), :second)
        else
          _ -> DateTime.utc_now()
        end

      _ ->
        DateTime.utc_now()
    end
  end

  defp tz_offset_seconds("GMT"), do: 0
  defp tz_offset_seconds("UTC"), do: 0

  defp tz_offset_seconds(tz) when byte_size(tz) == 5 do
    sign = if String.starts_with?(tz, "-"), do: -1, else: 1
    {hours, ""} = Integer.parse(String.slice(tz, 1, 2))
    {minutes, ""} = Integer.parse(String.slice(tz, 3, 2))
    sign * (hours * 3600 + minutes * 60)
  end

  defp tz_offset_seconds(_), do: 0
end
