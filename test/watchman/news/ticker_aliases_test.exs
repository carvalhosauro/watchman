defmodule Watchman.News.TickerAliasesTest do
  use ExUnit.Case, async: true

  alias Watchman.News.TickerAliases

  describe "for/1" do
    test "returns curated aliases for a registered ticker" do
      assert TickerAliases.for("PETR4") == ["PETR4", "Petrobras"]
    end

    test "upcases the input before lookup" do
      assert TickerAliases.for("petr4") == ["PETR4", "Petrobras"]
    end

    test "falls back to [ticker] for unknown tickers (no crash)" do
      assert TickerAliases.for("ZZZZ99") == ["ZZZZ99"]
    end

    test "unknown ticker fallback is upcased" do
      assert TickerAliases.for("xxx") == ["XXX"]
    end
  end

  describe "known_tickers/0" do
    test "returns a non-empty list of strings" do
      tickers = TickerAliases.known_tickers()
      assert is_list(tickers)
      assert tickers != []
      assert Enum.all?(tickers, &is_binary/1)
    end

    test "every known ticker has at least 2 aliases (code + company name)" do
      for ticker <- TickerAliases.known_tickers() do
        aliases = TickerAliases.for(ticker)
        assert match?([_, _ | _], aliases), "#{ticker} should have ticker + company name"
        assert ticker in aliases
      end
    end
  end
end
