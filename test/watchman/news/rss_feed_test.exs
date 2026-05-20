defmodule Watchman.News.RssFeedTest do
  use ExUnit.Case, async: true

  alias Watchman.News.RssFeed

  # ---------------------------------------------------------------------------
  # Fixture helpers
  # ---------------------------------------------------------------------------

  defp rss_item(title, description, opts \\ []) do
    link = Keyword.get(opts, :link, "https://example.com/article")
    pub_date = Keyword.get(opts, :pub_date, "Mon, 20 May 2026 10:30:00 +0000")

    """
    <item>
      <title>#{title}</title>
      <link>#{link}</link>
      <pubDate>#{pub_date}</pubDate>
      <description>#{description}</description>
    </item>
    """
  end

  defp wrap_items(items_xml) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Test Feed</title>
        #{items_xml}
      </channel>
    </rss>
    """
  end

  # ---------------------------------------------------------------------------
  # parse_response/3
  # ---------------------------------------------------------------------------

  describe "parse_response/3" do
    test "returns only items that mention the ticker" do
      xml =
        wrap_items(
          rss_item("Petrobras anuncia investimento", "Petrobras expande operações") <>
            rss_item("Vale reporta recordes", "Resultado trimestral da Vale")
        )

      assert {:ok, items} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert length(items) == 1
      assert hd(items).title == "Petrobras anuncia investimento"
    end

    test "ticker filter is case-insensitive (lowercase alias in description matches)" do
      xml =
        wrap_items(rss_item("Ação sobe após notícia", "analistas recomendam petrobras hoje"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "suno")
      assert item.title == "Ação sobe após notícia"
    end

    test "ticker alias in title triggers match" do
      xml = wrap_items(rss_item("PETR4 valoriza no pregão", "Petróleo em alta"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "investnews")
      assert item.title == "PETR4 valoriza no pregão"
    end

    test "outlet name becomes the source field on returned items" do
      xml = wrap_items(rss_item("Petrobras em alta", "Compra de PETR4 recomendada"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "money_times")
      assert item.source == "money_times"
    end

    test "caps at 20 items even when all 25 items match the ticker" do
      items_xml =
        1..25
        |> Enum.map_join("", fn i ->
          rss_item("Petrobras notícia #{i}", "PETR4 análise #{i}")
        end)

      assert {:ok, items} = RssFeed.parse_response(wrap_items(items_xml), "PETR4", "valor")
      assert length(items) == 20
    end

    test "20-item cap is applied before filtering (first 20 of 25 evaluated)" do
      # Items 1..20 match PETR4; items 21..25 match VALE3 only.
      # After Enum.take(20), only PETR4 items remain, so all 20 are kept.
      petr4_items =
        1..20
        |> Enum.map_join("", fn i ->
          rss_item("Petrobras item #{i}", "PETR4 update")
        end)

      vale_items =
        1..5
        |> Enum.map_join("", fn i ->
          rss_item("Vale item #{i}", "VALE3 update")
        end)

      assert {:ok, items} =
               RssFeed.parse_response(wrap_items(petr4_items <> vale_items), "PETR4", "valor")

      assert length(items) == 20
    end

    test "category is 'dividend' when title contains 'dividendo'" do
      xml = wrap_items(rss_item("Petrobras anuncia dividendo extraordinário", "PETR4 dividendo"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert item.category == "dividend"
    end

    test "category is 'financial_result' when title contains 'resultado'" do
      xml = wrap_items(rss_item("Resultado trimestral da Petrobras supera expectativas", "PETR4"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert item.category == "financial_result"
    end

    test "category is 'financial_result' when title contains 'lucro'" do
      xml = wrap_items(rss_item("Lucro da Petrobras bate recorde", "PETR4 balanço"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert item.category == "financial_result"
    end

    test "category is 'financial_result' when title contains 'balanço'" do
      xml = wrap_items(rss_item("Balanço da Petrobras é divulgado amanhã", "PETR4"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert item.category == "financial_result"
    end

    test "category is 'material_fact' when title contains 'fato relevante'" do
      xml = wrap_items(rss_item("Fato relevante da Petrobras divulgado", "PETR4"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert item.category == "material_fact"
    end

    test "category is 'other' for generic titles" do
      xml = wrap_items(rss_item("Petrobras inicia exploração offshore", "PETR4 notícia"))

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert item.category == "other"
    end

    test "empty channel returns {:ok, []}" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel/>
      </rss>
      """

      assert {:ok, []} = RssFeed.parse_response(xml, "PETR4", "valor")
    end

    test "malformed XML returns {:error, _}" do
      assert {:error, _} = RssFeed.parse_response("<not valid xml<<<", "PETR4", "valor")
    end

    test "pubDate is parsed to a UTC DateTime" do
      xml =
        wrap_items(
          rss_item("Petrobras alta", "PETR4", pub_date: "Mon, 20 May 2026 10:30:00 +0000")
        )

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert %DateTime{} = item.published_at
      assert item.published_at.year == 2026
      assert item.published_at.month == 5
      assert item.published_at.day == 20
    end

    test "non-zero timezone offset is applied correctly" do
      # +0300 means UTC-3h, so 10:30:00 +0300 → 07:30:00 UTC
      xml =
        wrap_items(
          rss_item("Petrobras alta", "PETR4", pub_date: "Mon, 20 May 2026 10:30:00 +0300")
        )

      assert {:ok, [item]} = RssFeed.parse_response(xml, "PETR4", "valor")
      assert item.published_at.hour == 7
      assert item.published_at.minute == 30
    end
  end

  # ---------------------------------------------------------------------------
  # default_feeds/0
  # ---------------------------------------------------------------------------

  describe "default_feeds/0" do
    test "returns exactly 5 entries" do
      assert length(RssFeed.default_feeds()) == 5
    end

    test "contains all documented feed names" do
      names = Enum.map(RssFeed.default_feeds(), & &1.name)

      assert "valor" in names
      assert "money_times" in names
      assert "investnews" in names
      assert "suno" in names
      assert "brazil_journal" in names
    end

    test "contains all documented feed URLs" do
      urls = Enum.map(RssFeed.default_feeds(), & &1.url)

      assert "https://valor.globo.com/empresas/rss/" in urls
      assert "https://www.moneytimes.com.br/feed/" in urls
      assert "https://investnews.com.br/feed/" in urls
      assert "https://www.suno.com.br/noticias/feed/" in urls
      assert "https://braziljournal.com/feed/" in urls
    end

    test "each entry has both :name and :url string fields" do
      for feed <- RssFeed.default_feeds() do
        assert is_binary(feed.name), "name should be a string: #{inspect(feed)}"
        assert is_binary(feed.url), "url should be a string: #{inspect(feed)}"
      end
    end
  end
end
