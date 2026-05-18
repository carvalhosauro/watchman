ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(Watchman.Repo, :manual)

# Define mocks for provider behaviours
Mox.defmock(Watchman.Market.MockProvider, for: Watchman.Market.Provider)
Mox.defmock(Watchman.AI.MockProvider, for: Watchman.AI.Provider)
Mox.defmock(Watchman.Alerts.MockProvider, for: Watchman.Alerts.Provider)
