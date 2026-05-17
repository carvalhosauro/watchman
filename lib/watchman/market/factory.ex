defmodule Watchman.Market.Factory do
  def provider do
    Watchman.Config.market_provider()
  end
end
