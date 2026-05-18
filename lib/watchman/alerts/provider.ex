defmodule Watchman.Alerts.Provider do
  @moduledoc "Behaviour for alert notification providers."

  @callback send_alert(
              ticker :: String.t(),
              recommendation :: String.t(),
              justification :: String.t()
            ) :: :ok | {:error, term()}

  @callback test_connection() :: :ok | {:error, term()}
end
