import Config

config :helmscout, Helmscout.Repo,
  database: "data/helmscout_test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 2

config :helmscout, HelmscoutWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: "test-only-secret-key-base-not-for-production-use-0000000000000000"

config :logger, level: :warning
