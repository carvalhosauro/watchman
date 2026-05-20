defmodule Watchman.AI.SharedTest do
  use ExUnit.Case, async: true

  alias Watchman.AI.Shared
  alias Watchman.Analysis.Signal

  # ---------------------------------------------------------------------------
  # format_signal/1
  # ---------------------------------------------------------------------------

  describe "format_signal/1" do
    test "formats level, direction, confidence and reasons" do
      signal = %Signal{
        level: :high,
        direction: :bearish,
        confidence: 0.78,
        reasons: ["Price 2.3σ below 21-day average", "3 consecutive down days"]
      }

      result = Shared.format_signal(signal)

      assert result =~ "Signal: HIGH BEARISH"
      assert result =~ "confidence 0.78"
      assert result =~ "Price 2.3σ below 21-day average; 3 consecutive down days"
    end

    test "upcases level and direction" do
      signal = %Signal{level: :medium, direction: :bullish, confidence: 0.60, reasons: []}
      result = Shared.format_signal(signal)

      assert result =~ "MEDIUM"
      assert result =~ "BULLISH"
      refute result =~ "medium"
      refute result =~ "bullish"
    end

    test "renders empty reasons list without trailing semicolon" do
      signal = %Signal{level: :noise, direction: :neutral, confidence: 0.10, reasons: []}
      result = Shared.format_signal(signal)

      assert result =~ "Reasons:"
      refute result =~ ";"
    end
  end

  # ---------------------------------------------------------------------------
  # system_prompt_with_signal/2
  # ---------------------------------------------------------------------------

  describe "system_prompt_with_signal/2" do
    test "signal block appears before analyst intro" do
      signal = %Signal{level: :high, direction: :bearish, confidence: 0.78, reasons: ["Reason A"]}
      prompt = Shared.system_prompt_with_signal(:no_search, signal)

      signal_pos = :binary.match(prompt, "Signal:") |> elem(0)
      analyst_pos = :binary.match(prompt, "Você é um analista") |> elem(0)

      assert signal_pos < analyst_pos
    end

    test "includes anti-reclassification instruction" do
      signal = %Signal{level: :medium, direction: :bullish, confidence: 0.60, reasons: []}
      prompt = Shared.system_prompt_with_signal(:no_search, signal)

      assert prompt =~ "não reclassifique"
    end

    test "includes token-cap instruction" do
      signal = %Signal{level: :low, direction: :neutral, confidence: 0.40, reasons: []}
      prompt = Shared.system_prompt_with_signal(:no_search, signal)

      assert prompt =~ "300 tokens"
    end

    test "includes web_search instruction for :web_search_tool variant" do
      signal = %Signal{level: :low, direction: :neutral, confidence: 0.40, reasons: []}
      prompt = Shared.system_prompt_with_signal(:web_search_tool, signal)

      assert prompt =~ "web_search"
    end

    test "includes knowledge-only instruction for :no_search variant" do
      signal = %Signal{level: :noise, direction: :neutral, confidence: 0.10, reasons: []}
      prompt = Shared.system_prompt_with_signal(:no_search, signal)

      assert prompt =~ "conhecimento"
    end

    test "includes grounding instruction for :search_grounding variant" do
      signal = %Signal{level: :medium, direction: :bullish, confidence: 0.55, reasons: []}
      prompt = Shared.system_prompt_with_signal(:search_grounding, signal)

      assert prompt =~ "busca"
    end
  end

  # ---------------------------------------------------------------------------
  # recommendation_from_signal/1
  # ---------------------------------------------------------------------------

  describe "recommendation_from_signal/1" do
    test "noise level always returns manter regardless of direction" do
      for direction <- [:bullish, :bearish, :neutral] do
        signal = %Signal{level: :noise, direction: direction, confidence: 0.10, reasons: []}

        assert Shared.recommendation_from_signal(signal) == "manter",
               "expected manter for noise/#{direction}"
      end
    end

    test "bullish high returns investigar" do
      signal = %Signal{level: :high, direction: :bullish, confidence: 0.90, reasons: []}
      assert Shared.recommendation_from_signal(signal) == "investigar"
    end

    test "bullish medium returns manter" do
      signal = %Signal{level: :medium, direction: :bullish, confidence: 0.60, reasons: []}
      assert Shared.recommendation_from_signal(signal) == "manter"
    end

    test "bullish low returns manter" do
      signal = %Signal{level: :low, direction: :bullish, confidence: 0.35, reasons: []}
      assert Shared.recommendation_from_signal(signal) == "manter"
    end

    test "bearish high returns vender" do
      signal = %Signal{level: :high, direction: :bearish, confidence: 0.90, reasons: []}
      assert Shared.recommendation_from_signal(signal) == "vender"
    end

    test "bearish medium returns vender" do
      signal = %Signal{level: :medium, direction: :bearish, confidence: 0.65, reasons: []}
      assert Shared.recommendation_from_signal(signal) == "vender"
    end

    test "bearish low returns investigar" do
      signal = %Signal{level: :low, direction: :bearish, confidence: 0.30, reasons: []}
      assert Shared.recommendation_from_signal(signal) == "investigar"
    end

    test "neutral returns investigar for all non-noise levels" do
      for level <- [:high, :medium, :low] do
        signal = %Signal{level: level, direction: :neutral, confidence: 0.50, reasons: []}

        assert Shared.recommendation_from_signal(signal) == "investigar",
               "expected investigar for #{level}/neutral"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # format_news_items/1
  # ---------------------------------------------------------------------------

  describe "format_news_items/1" do
    test "returns empty string for empty list" do
      assert Shared.format_news_items([]) == ""
    end

    test "includes title and summary of each item" do
      news = [
        %{title: "PETR4 cai 3%", summary: "Queda relacionada ao petróleo", published_at: nil},
        %{title: "Resultado trimestral", summary: "Lucro abaixo do esperado", published_at: nil}
      ]

      result = Shared.format_news_items(news)

      assert result =~ "PETR4 cai 3%"
      assert result =~ "Queda relacionada ao petróleo"
      assert result =~ "Resultado trimestral"
      assert result =~ "Lucro abaixo do esperado"
    end

    test "limits output to first 5 items" do
      news =
        for i <- 1..10 do
          %{title: "Notícia #{i}", summary: "Resumo #{i}", published_at: nil}
        end

      result = Shared.format_news_items(news)

      assert result =~ "Notícia 5"
      refute result =~ "Notícia 6"
    end

    test "handles nil title gracefully" do
      news = [%{title: nil, summary: "Resumo", published_at: nil}]
      result = Shared.format_news_items(news)

      assert result =~ "Sem título"
    end

    test "handles nil summary gracefully" do
      news = [%{title: "Título", summary: nil, published_at: nil}]
      result = Shared.format_news_items(news)

      assert result =~ "Sem resumo"
    end

    test "includes formatted date when published_at is present" do
      {:ok, dt, _} = DateTime.from_iso8601("2025-05-01T10:00:00Z")
      news = [%{title: "Notícia", summary: "Resumo", published_at: dt}]
      result = Shared.format_news_items(news)

      assert result =~ "2025-05-01"
    end

    test "omits date when published_at is nil" do
      news = [%{title: "Notícia", summary: "Resumo", published_at: nil}]
      result = Shared.format_news_items(news)

      refute result =~ "20"
    end

    test "wraps items under Notícias recentes header" do
      news = [%{title: "A", summary: "B", published_at: nil}]
      result = Shared.format_news_items(news)

      assert result =~ "Notícias recentes"
    end
  end

  # ---------------------------------------------------------------------------
  # user_prompt_with_signal/4
  # ---------------------------------------------------------------------------

  describe "user_prompt_with_signal/4" do
    setup do
      asset = %{ticker: "PETR4", name: "Petrobras", type: "acao"}

      snapshot = %{
        price: 35.50,
        variation_day: -3.2,
        variation_week: -5.1,
        variation_month: -8.0
      }

      signal = %Signal{
        level: :high,
        direction: :bearish,
        confidence: 0.82,
        reasons: ["Volume spike"]
      }

      {:ok, asset: asset, snapshot: snapshot, signal: signal}
    end

    test "includes ticker", %{asset: asset, snapshot: snapshot, signal: signal} do
      result = Shared.user_prompt_with_signal(asset, snapshot, signal, [])
      assert result =~ "PETR4"
    end

    test "includes asset name", %{asset: asset, snapshot: snapshot, signal: signal} do
      result = Shared.user_prompt_with_signal(asset, snapshot, signal, [])
      assert result =~ "Petrobras"
    end

    test "includes price variation data", %{asset: asset, snapshot: snapshot, signal: signal} do
      result = Shared.user_prompt_with_signal(asset, snapshot, signal, [])
      assert result =~ "35.5"
      assert result =~ "-3.2%"
      assert result =~ "-5.1%"
    end

    test "includes news section when news present", %{
      asset: asset,
      snapshot: snapshot,
      signal: signal
    } do
      news = [%{title: "Notícia A", summary: "Resumo A", published_at: nil}]
      result = Shared.user_prompt_with_signal(asset, snapshot, signal, news)

      assert result =~ "Notícias recentes"
      assert result =~ "Notícia A"
    end

    test "omits news section when news empty", %{asset: asset, snapshot: snapshot, signal: signal} do
      result = Shared.user_prompt_with_signal(asset, snapshot, signal, [])
      refute result =~ "Notícias recentes"
    end

    test "uses search=false instruction when opted out", %{
      asset: asset,
      snapshot: snapshot,
      signal: signal
    } do
      result = Shared.user_prompt_with_signal(asset, snapshot, signal, [], search: false)
      assert result =~ "conhecimento"
    end
  end
end
