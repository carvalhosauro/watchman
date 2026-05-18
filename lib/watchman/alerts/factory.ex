defmodule Watchman.Alerts.Factory do
  @moduledoc "Resolves configured alert provider modules."

  def providers do
    Application.get_env(:watchman, :alerts_provider_override) ||
      Watchman.Config.alerts_providers()
  end
end
