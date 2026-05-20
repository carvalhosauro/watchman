defmodule Watchman.News.B3Test do
  use ExUnit.Case, async: true

  alias Watchman.Models.NewsItem
  alias Watchman.News.B3

  @ticker "PETR4"

  @valid_body %{
    "ticker" => "PETR4",
    "corporateActions" => [
      %{
        "type" => "DIVIDEND",
        "description" => "Dividendo extraordinário",
        "approvedAt" => "2026-04-15",
        "exDate" => "2026-05-01",
        "url" => "https://b3.com.br/dividend"
      },
      %{
        "type" => "STOCK_SPLIT",
        "description" => "Desdobramento 1:2",
        "approvedAt" => "2026-03-01",
        "url" => "https://b3.com.br/split"
      },
      %{
        "type" => "SUBSCRIPTION",
        "description" => "Direito de subscrição",
        "approvedAt" => "2026-02-15",
        "url" => "https://b3.com.br/subscription"
      }
    ]
  }

  describe "parse_response/2 with decoded map" do
    test "returns {:ok, 3 items} for valid fixture" do
      assert {:ok, items} = B3.parse_response(@valid_body, @ticker)
      assert length(items) == 3
    end

    test "all items have source 'b3'" do
      assert {:ok, items} = B3.parse_response(@valid_body, @ticker)
      assert Enum.all?(items, &(&1.source == "b3"))
    end

    test "first item (DIVIDEND) has category 'dividend'" do
      assert {:ok, [item | _]} = B3.parse_response(@valid_body, @ticker)
      assert item.category == "dividend"
    end

    test "second item (STOCK_SPLIT) has category 'other'" do
      assert {:ok, [_, item | _]} = B3.parse_response(@valid_body, @ticker)
      assert item.category == "other"
    end

    test "third item (SUBSCRIPTION) has category 'other'" do
      assert {:ok, [_, _, item]} = B3.parse_response(@valid_body, @ticker)
      assert item.category == "other"
    end

    test "titles are taken from description field" do
      assert {:ok, items} = B3.parse_response(@valid_body, @ticker)
      titles = Enum.map(items, & &1.title)
      assert "Dividendo extraordinário" in titles
      assert "Desdobramento 1:2" in titles
      assert "Direito de subscrição" in titles
    end

    test "urls are taken from action url field" do
      assert {:ok, [item | _]} = B3.parse_response(@valid_body, @ticker)
      assert item.url == "https://b3.com.br/dividend"
    end

    test "published_at is parsed as start-of-day UTC" do
      assert {:ok, [item | _]} = B3.parse_response(@valid_body, @ticker)

      assert %DateTime{year: 2026, month: 4, day: 15, hour: 0, minute: 0, second: 0} =
               item.published_at
    end

    test "returns {:ok, []} for empty corporateActions" do
      body = %{"ticker" => @ticker, "corporateActions" => []}
      assert {:ok, []} = B3.parse_response(body, @ticker)
    end

    test "returns {:ok, []} for map without corporateActions key" do
      assert {:ok, []} = B3.parse_response(%{}, @ticker)
    end

    test "skips actions missing required fields" do
      body = %{
        "corporateActions" => [
          %{"type" => "DIVIDEND", "description" => "Valid", "approvedAt" => "2026-01-01"},
          %{"type" => "DIVIDEND"}
        ]
      }

      assert {:ok, [item]} = B3.parse_response(body, @ticker)
      assert item.title == "Valid"
    end
  end

  describe "parse_response/2 with raw JSON binary" do
    test "parses valid JSON binary and returns 3 items" do
      json = Jason.encode!(@valid_body)
      assert {:ok, items} = B3.parse_response(json, @ticker)
      assert length(items) == 3
    end

    test "returns {:ok, []} for empty corporateActions as binary" do
      json = Jason.encode!(%{"ticker" => @ticker, "corporateActions" => []})
      assert {:ok, []} = B3.parse_response(json, @ticker)
    end

    test "returns {:error, _} for malformed JSON" do
      assert {:error, _} = B3.parse_response("not json {{{", @ticker)
    end

    test "binary result matches map result" do
      json = Jason.encode!(@valid_body)
      assert {:ok, map_items} = B3.parse_response(@valid_body, @ticker)
      assert {:ok, bin_items} = B3.parse_response(json, @ticker)
      assert length(map_items) == length(bin_items)
    end
  end

  describe "category mapping" do
    test "DIVIDEND maps to 'dividend'" do
      assert {:ok, [%NewsItem{category: "dividend"}]} =
               B3.parse_response(action_body("DIVIDEND", "Test"), @ticker)
    end

    test "JCP maps to 'dividend'" do
      assert {:ok, [%NewsItem{category: "dividend"}]} =
               B3.parse_response(action_body("JCP", "Juros sobre capital próprio"), @ticker)
    end

    test "INTEREST_ON_CAPITAL maps to 'dividend'" do
      assert {:ok, [%NewsItem{category: "dividend"}]} =
               B3.parse_response(action_body("INTEREST_ON_CAPITAL", "Interest"), @ticker)
    end

    test "STOCK_SPLIT maps to 'other'" do
      assert {:ok, [%NewsItem{category: "other"}]} =
               B3.parse_response(action_body("STOCK_SPLIT", "Desdobramento"), @ticker)
    end

    test "REVERSE_SPLIT maps to 'other'" do
      assert {:ok, [%NewsItem{category: "other"}]} =
               B3.parse_response(action_body("REVERSE_SPLIT", "Agrupamento"), @ticker)
    end

    test "BONUS maps to 'other'" do
      assert {:ok, [%NewsItem{category: "other"}]} =
               B3.parse_response(action_body("BONUS", "Bonificação"), @ticker)
    end

    test "SUBSCRIPTION maps to 'other'" do
      assert {:ok, [%NewsItem{category: "other"}]} =
               B3.parse_response(action_body("SUBSCRIPTION", "Subscrição"), @ticker)
    end

    test "unknown type maps to 'other'" do
      assert {:ok, [%NewsItem{category: "other"}]} =
               B3.parse_response(action_body("UNKNOWN_TYPE", "Something"), @ticker)
    end
  end

  describe "url fallback" do
    test "uses fallback url when action has no url field" do
      body = %{
        "corporateActions" => [
          %{"type" => "DIVIDEND", "description" => "Div", "approvedAt" => "2026-01-01"}
        ]
      }

      assert {:ok, [item]} = B3.parse_response(body, @ticker)
      assert is_binary(item.url)
      assert String.starts_with?(item.url, "https://")
    end
  end

  # Helpers

  defp action_body(type, description) do
    %{
      "ticker" => @ticker,
      "corporateActions" => [
        %{
          "type" => type,
          "description" => description,
          "approvedAt" => "2026-01-01",
          "url" => "https://b3.com.br/action"
        }
      ]
    }
  end
end
