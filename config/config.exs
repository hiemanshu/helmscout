import Config

config :helmscout, Helmscout.Repo,
  database: "data/helmscout.db",
  pool_size: 5,
  journal_mode: :wal,
  foreign_keys: :on,
  busy_timeout: 5000,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :helmscout, ecto_repos: [Helmscout.Repo]

# Where cloned repository working trees live while indexing.
config :helmscout, :cache_dir, "data/repos"

# Where progress logs are written.
config :helmscout, :log_dir, "log"

# Public base URL, used for the generated sitemap and absolute links.
config :helmscout, :base_url, "https://helmscout.dev"

# Built Vue app. In dev this is the Vite output; a release overrides it with the
# copy under priv/static/frontend.
config :helmscout, :frontend_dir, Path.expand("web/dist")

# Directories / files that should never be walked when indexing.
config :helmscout, :ignore_paths, [
  ".git/",
  "node_modules/",
  "vendor/",
  "archive/",
  ".archive/",
  "charts/",
  "CHANGELOG",
  "test/"
]

config :helmscout, HelmscoutWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HelmscoutWeb.ErrorHTML, json: HelmscoutWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Helmscout.PubSub,
  live_view: [signing_salt: "helmscout0000000"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
