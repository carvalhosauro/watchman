defmodule Watchman.ParserTest do
  use ExUnit.Case

  alias Watchman.Parser

  describe "extract/1" do
    test "parses valid JSON analysis from text block" do
      input = %{
        content: [
          %{
            "type" => "text",
            "text" =>
              ~s({"cause": "oil prices up", "is_specific_problem": false, "macro_context": "global oil", "recommendation": "manter", "justification": "stable"})
          }
        ],
        tokens: 500
      }

      assert {:ok, analysis, []} = Parser.extract(input)
      assert analysis.cause == "oil prices up"
      assert analysis.is_specific_problem == false
      assert analysis.recommendation == "manter"
      assert analysis.justification == "stable"
      assert analysis.tokens_used == 500
    end

    test "strips markdown code fences from JSON" do
      input = %{
        content: [
          %{
            "type" => "text",
            "text" =>
              "```json\n{\"cause\": \"test\", \"is_specific_problem\": true, \"macro_context\": null, \"recommendation\": \"investigar\", \"justification\": \"reason\"}\n```"
          }
        ],
        tokens: 100
      }

      assert {:ok, analysis, []} = Parser.extract(input)
      assert analysis.cause == "test"
      assert analysis.recommendation == "investigar"
    end

    test "fallback on invalid JSON" do
      input = %{
        content: [
          %{"type" => "text", "text" => "This is not JSON at all"}
        ],
        tokens: 50
      }

      assert {:ok, analysis, []} = Parser.extract(input)
      assert analysis.recommendation == "investigar"
      assert analysis.justification =~ "Falha ao processar"
    end

    test "extracts news from web_search_results" do
      input = %{
        content: [
          %{
            "type" => "tool_result",
            "content" => [
              %{
                "type" => "web_search_results",
                "results" => [
                  %{
                    "title" => "News 1",
                    "url" => "https://example.com/1",
                    "snippet" => "Summary 1",
                    "published_date" => "2026-05-17"
                  },
                  %{
                    "title" => "News 2",
                    "url" => "https://other.com/2",
                    "snippet" => "Summary 2",
                    "published_date" => nil
                  }
                ]
              }
            ]
          },
          %{
            "type" => "text",
            "text" =>
              ~s({"cause": "test", "is_specific_problem": false, "macro_context": null, "recommendation": "manter", "justification": "ok"})
          }
        ],
        tokens: 1000
      }

      assert {:ok, _analysis, news} = Parser.extract(input)
      assert length(news) == 2
      assert hd(news).title == "News 1"
      assert hd(news).source == "example.com"
    end

    test "deduplicates news by URL" do
      input = %{
        content: [
          %{
            "type" => "tool_result",
            "content" => [
              %{
                "type" => "web_search_results",
                "results" => [
                  %{"title" => "News 1", "url" => "https://example.com/1", "snippet" => "A"},
                  %{"title" => "News 1 dup", "url" => "https://example.com/1", "snippet" => "B"}
                ]
              }
            ]
          },
          %{
            "type" => "text",
            "text" =>
              ~s({"cause": "x", "is_specific_problem": false, "macro_context": null, "recommendation": "manter", "justification": "y"})
          }
        ],
        tokens: 200
      }

      assert {:ok, _, news} = Parser.extract(input)
      assert length(news) == 1
    end

    test "handles empty content blocks" do
      input = %{content: [], tokens: 0}
      assert {:ok, analysis, []} = Parser.extract(input)
      assert analysis.recommendation == "investigar"
    end
  end
end
