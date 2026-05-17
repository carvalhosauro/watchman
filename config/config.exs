import Config

config :watchman,
  ecto_repos: [Watchman.Repo]

config :watchman, Watchman.Repo,
  database:
    Path.join([System.get_env("HOME") || "~", ".local", "share", "watchman", "watchman.db"])

import_config "#{config_env()}.exs"
