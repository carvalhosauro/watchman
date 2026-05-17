defmodule Watchman.Market.Factory do
  def provider do
    Application.get_env(:watchman, :market_provider_override) ||
      Watchman.Config.market_provider()
  end
end
