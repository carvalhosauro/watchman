defmodule Watchman.News.TickerAliases do
  @moduledoc """
  Lookup table mapping a B3 ticker code to a list of search aliases
  (ticker code + company-name variants) used by `Watchman.News.RssFeed`
  to filter broad-market RSS items down to per-ticker mentions.

  The table starts minimal — the most-traded B3 tickers — and grows
  as users register assets. Unknown tickers fall back to the bare
  ticker code as the only alias.

  Aliases are matched case-insensitively against title + summary by
  the caller (`RssFeed`); this module only owns the table.
  """

  @aliases %{
    "PETR4" => ["PETR4", "Petrobras"],
    "PETR3" => ["PETR3", "Petrobras"],
    "VALE3" => ["VALE3", "Vale"],
    "ITUB4" => ["ITUB4", "Itaú", "Itau Unibanco", "Itau"],
    "BBDC4" => ["BBDC4", "Bradesco"],
    "BBAS3" => ["BBAS3", "Banco do Brasil"],
    "ABEV3" => ["ABEV3", "Ambev"],
    "B3SA3" => ["B3SA3", "B3 ", "Bolsa do Brasil"],
    "WEGE3" => ["WEGE3", "WEG", "Weg Equipamentos"],
    "SUZB3" => ["SUZB3", "Suzano"],
    "MGLU3" => ["MGLU3", "Magazine Luiza", "Magalu"],
    "BPAC11" => ["BPAC11", "BTG Pactual"],
    "RENT3" => ["RENT3", "Localiza"],
    "RADL3" => ["RADL3", "Raia Drogasil", "RaiaDrogasil"],
    "JBSS3" => ["JBSS3", "JBS"],
    "MXRF11" => ["MXRF11", "Maxi Renda"],
    "HGLG11" => ["HGLG11", "HG Logística", "CSHG Logística"],
    "KNRI11" => ["KNRI11", "Kinea Renda Imobiliária"]
  }

  @doc """
  Returns the list of search aliases for `ticker`. Always returns at
  least `[ticker]` so callers do not need to handle nil.
  """
  @spec for(String.t()) :: [String.t()]
  def for(ticker) when is_binary(ticker) do
    upper = String.upcase(ticker)
    Map.get(@aliases, upper, [upper])
  end

  @doc """
  All tickers currently registered in the alias table.
  """
  @spec known_tickers() :: [String.t()]
  def known_tickers, do: Map.keys(@aliases)
end
