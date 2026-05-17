import Config

config :watchman, Watchman.Repo,
  database: "test/watchman_test.db",
  pool: Ecto.Adapters.SQL.Sandbox

config :logger, level: :warning
