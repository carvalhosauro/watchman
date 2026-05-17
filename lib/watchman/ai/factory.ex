defmodule Watchman.AI.Factory do
  def provider do
    Application.get_env(:watchman, :ai_provider_override) ||
      Watchman.Config.ai_provider()
  end
end
