defmodule Watchman.News.InfomoneyTest do
  use ExUnit.Case, async: true

  alias Watchman.Models.NewsItem
  alias Watchman.News.Infomoney

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  @valid_rss """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0">
    <channel>
      <title>Infomoney PETR4</title>
      <item>
        <title>Petrobras anuncia dividendo extraordinário de R$ 1,50</title>
        <link>https://www.infomoney.com.br/petr4-dividendo</link>
        <pubDate>Mon, 15 Apr 2026 14:30:00 -0300</pubDate>
      </item>
      <item>
        <title>Petrobras divulga resultado do trimestre com receita recorde</title>
        <link>https://www.infomoney.com.br/petr4-resultado</link>
        <pubDate>Fri, 12 Apr 2026 10:00:00 -0300</pubDate>
      </item>
      <item>
        <title>Petrobras comunica fato relevante sobre mudança de gestão</title>
        <link>https://www.infomoney.com.br/petr4-fato</link>
        <pubDate>Thu, 11 Apr 2026 09:00:00 -0300</pubDate>
      </item>
      <item>
        <title>Ações da Petrobras sobem 2% na bolsa hoje</title>
        <link>https://www.infomoney.com.br/petr4-alta</link>
        <pubDate>Wed, 10 Apr 2026 08:00:00 -0300</pubDate>
      </item>
    </channel>
  </rss>
  """

  @empty_channel_rss """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss version="2.0">
    <channel/>
  </rss>
  """

  @malformed_rss "this is not xml at all <<<"

  @rss_15_items (fn ->
                   items =
                     Enum.map_join(1..15, "\n", fn i ->
                       """
                       <item>
                         <title>Notícia #{i}</title>
                         <link>https://www.infomoney.com.br/item#{i}</link>
                         <pubDate>Mon, 01 Jan 2026 00:00:00 +0000</pubDate>
                       </item>
                       """
                     end)

                   """
                   <?xml version="1.0" encoding="UTF-8"?>
                   <rss version="2.0">
                     <channel>
                       #{items}
                     </channel>
                   </rss>
                   """
                 end).()

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp rss_with_title(title) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <item>
          <title>#{title}</title>
          <link>https://www.infomoney.com.br/article</link>
          <pubDate>Mon, 15 Apr 2026 14:30:00 -0300</pubDate>
        </item>
      </channel>
    </rss>
    """
  end

  defp rss_with_pub_date(pub_date) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <item>
          <title>Some title</title>
          <link>https://www.infomoney.com.br/article</link>
          <pubDate>#{pub_date}</pubDate>
        </item>
      </channel>
    </rss>
    """
  end

  defp first_item(rss) do
    {:ok, [item | _]} = Infomoney.parse_response(rss, "PETR4")
    item
  end

  # ---------------------------------------------------------------------------
  # parse_response/2 — core behaviour
  # ---------------------------------------------------------------------------

  describe "parse_response/2" do
    test "returns {:ok, items} with correct source for every item" do
      {:ok, items} = Infomoney.parse_response(@valid_rss, "PETR4")
      assert Enum.all?(items, fn %NewsItem{source: s} -> s == "infomoney" end)
    end

    test "returns correct title, url, and category for first item" do
      item = first_item(@valid_rss)

      assert item.title == "Petrobras anuncia dividendo extraordinário de R$ 1,50"
      assert item.url == "https://www.infomoney.com.br/petr4-dividendo"
      assert item.category == "dividend"
    end

    test "parses all four items in valid fixture" do
      {:ok, items} = Infomoney.parse_response(@valid_rss, "PETR4")
      assert length(items) == 4
    end

    test "caps results at 10 items when fixture has 15" do
      {:ok, items} = Infomoney.parse_response(@rss_15_items, "PETR4")
      assert length(items) == 10
    end

    test "returns {:ok, []} for empty channel" do
      assert {:ok, []} = Infomoney.parse_response(@empty_channel_rss, "PETR4")
    end

    test "returns {:error, _} for malformed RSS" do
      assert {:error, _} = Infomoney.parse_response(@malformed_rss, "PETR4")
    end

    test "all returned structs are NewsItem" do
      {:ok, items} = Infomoney.parse_response(@valid_rss, "PETR4")
      assert Enum.all?(items, fn item -> is_struct(item, NewsItem) end)
    end
  end

  # ---------------------------------------------------------------------------
  # parse_response/2 — category mapping
  # ---------------------------------------------------------------------------

  describe "parse_response/2 category mapping" do
    test "dividend for title containing 'dividendo'" do
      assert first_item(rss_with_title("Empresa paga dividendo trimestral")).category ==
               "dividend"
    end

    test "dividend for title containing 'jcp'" do
      assert first_item(rss_with_title("Empresa anuncia JCP de R$ 0,50")).category == "dividend"
    end

    test "dividend for title containing 'juros sobre capital'" do
      assert first_item(rss_with_title("Pagamento de juros sobre capital próprio aprovado")).category ==
               "dividend"
    end

    test "financial_result for title containing 'resultado'" do
      assert first_item(rss_with_title("Empresa divulga resultado do 1T26")).category ==
               "financial_result"
    end

    test "financial_result for title containing 'balanço'" do
      assert first_item(rss_with_title("Balanço anual supera expectativas")).category ==
               "financial_result"
    end

    test "financial_result for title containing 'lucro'" do
      assert first_item(rss_with_title("Lucro líquido cresce 30% no trimestre")).category ==
               "financial_result"
    end

    test "financial_result for title containing 'receita'" do
      assert first_item(rss_with_title("Receita líquida atinge R$ 10 bi")).category ==
               "financial_result"
    end

    test "financial_result for title containing 'trimestre'" do
      assert first_item(rss_with_title("Destaques do trimestre para investidores")).category ==
               "financial_result"
    end

    test "material_fact for title containing 'fato relevante'" do
      assert first_item(rss_with_title("Comunicado de fato relevante ao mercado")).category ==
               "material_fact"
    end

    test "material_fact for title containing 'material fact'" do
      assert first_item(rss_with_title("Material fact: board resignation")).category ==
               "material_fact"
    end

    test "other for title with no matching keywords" do
      assert first_item(rss_with_title("Petrobras anuncia nova parceria comercial")).category ==
               "other"
    end

    test "category matching is case-insensitive" do
      assert first_item(rss_with_title("DIVIDENDO EXTRAORDINÁRIO ANUNCIADO")).category ==
               "dividend"
    end
  end

  # ---------------------------------------------------------------------------
  # parse_response/2 — pubDate parsing
  # ---------------------------------------------------------------------------

  describe "parse_response/2 pubDate parsing" do
    test "parses RFC 822 pubDate with negative UTC offset to UTC DateTime" do
      # "Mon, 15 Apr 2026 14:30:00 -0300" → 14:30 + 3h = 17:30 UTC
      item = first_item(rss_with_pub_date("Mon, 15 Apr 2026 14:30:00 -0300"))
      assert item.published_at == ~U[2026-04-15 17:30:00Z]
    end

    test "parses RFC 822 pubDate with positive UTC offset to UTC DateTime" do
      # "Tue, 01 Jan 2026 12:00:00 +0200" → 12:00 - 2h = 10:00 UTC
      item = first_item(rss_with_pub_date("Tue, 01 Jan 2026 12:00:00 +0200"))
      assert item.published_at == ~U[2026-01-01 10:00:00Z]
    end

    test "parses RFC 822 pubDate with GMT timezone" do
      item = first_item(rss_with_pub_date("Wed, 10 Apr 2026 08:00:00 GMT"))
      assert item.published_at == ~U[2026-04-10 08:00:00Z]
    end

    test "parses RFC 822 pubDate with +0000 offset" do
      item = first_item(rss_with_pub_date("Mon, 01 Jan 2026 00:00:00 +0000"))
      assert item.published_at == ~U[2026-01-01 00:00:00Z]
    end

    test "returns nil for missing pubDate" do
      rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <title>No date</title>
            <link>https://www.infomoney.com.br/article</link>
          </item>
        </channel>
      </rss>
      """

      item = first_item(rss)
      assert is_nil(item.published_at)
    end
  end
end
