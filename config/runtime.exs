import Config

# DB path — skip for test env (test.exs handles it)
if config_env() != :test do
  db_path =
    System.get_env("WATCHMAN_DB_PATH") ||
      Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman", "watchman.db"])

  config :watchman, Watchman.Repo, database: db_path
end

# API keys, providers, and pipeline settings are handled by Watchman.Config
# which reads from env vars and ~/.config/watchman/config.toml at startup
