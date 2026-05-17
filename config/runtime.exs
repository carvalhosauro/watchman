import Config

# DB path must be set here — Ecto reads it before Application.start
# TOML config not available yet at this stage, so only env var + default
db_path =
  System.get_env("WATCHMAN_DB_PATH") ||
    Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman", "watchman.db"])

config :watchman, Watchman.Repo, database: db_path

# API keys, providers, and pipeline settings are handled by Watchman.Config
# which reads from env vars and ~/.config/watchman/config.toml at startup
