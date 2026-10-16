import Config

config :helmscout, HelmscoutWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-not-for-production-use-0000000000000000",
  # Pipeline tasks (`mix helmscout.*`) boot this endpoint; don't let them grab
  # :4000. `mix phx.server` overrides this and serves endpoints regardless.
  server: false,
  watchers: []

config :logger, level: :info
