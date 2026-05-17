defmodule Watchman.Market.Yfinance do
  @behaviour Watchman.Market.Provider

  @base_url "https://query1.finance.yahoo.com/v8/finance/chart"

  @impl true
  def fetch(ticker) do
    # Brazilian tickers need .SA suffix for Yahoo Finance
    yahoo_ticker = "#{ticker}.SA"
    url = "#{@base_url}/#{yahoo_ticker}"

    case Req.get(url, params: [interval: "1d", range: "1mo"]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_yahoo_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:yfinance, status, body}}

      {:error, reason} ->
        {:error, {:yfinance_request, reason}}
    end
  end

  defp parse_yahoo_response(%{"chart" => %{"result" => [result | _]}}) do
    meta = result["meta"]
    price = meta["regularMarketPrice"]
    previous_close = meta["chartPreviousClose"] || meta["previousClose"]

    variation_day =
      if price && previous_close && previous_close != 0 do
        Float.round((price - previous_close) / previous_close * 100, 2)
      end

    {:ok, %{
      price: price,
      variation_day: variation_day,
      variation_week: nil,
      variation_month: nil
    }}
  end

  defp parse_yahoo_response(_), do: {:error, :invalid_yahoo_response}
end
