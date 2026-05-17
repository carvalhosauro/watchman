defmodule Watchman.Market.Provider do
  @type price_data :: %{
    price: float(),
    variation_day: float() | nil,
    variation_week: float() | nil,
    variation_month: float() | nil
  }

  @callback fetch(ticker :: String.t()) :: {:ok, price_data()} | {:error, term()}
end
