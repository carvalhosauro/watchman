defmodule Watchman.Market.Factory do
  @moduledoc "Resolves configured market data provider module."

  def provider do
    Application.get_env(:watchman, :market_provider_override) ||
      Watchman.Config.market_provider()
  end
end
