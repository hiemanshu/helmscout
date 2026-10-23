import Config

if config_env() == :prod do
  # The SQLite snapshot is baked into the image at build time (a named build
  # context, see the Dockerfile) and opened read-only. There is no download step
  # and no writable storage requirement.
  config :helmscout, Helmscout.Repo,
    database: System.get_env("DATABASE_PATH") || "/app/data/helmscout.db",
    mode: :readonly,
    journal_mode: :delete,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    foreign_keys: :on,
    busy_timeout: 5000

  config :helmscout, :cache_dir, System.get_env("CACHE_DIR") || "/data/repos"

  config :helmscout,
         :frontend_dir,
         System.get_env("FRONTEND_DIR") ||
           Path.join(:code.priv_dir(:helmscout), "static/frontend")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE environment variable is missing"

  port = String.to_integer(System.get_env("PORT") || "4000")

  config :helmscout, HelmscoutWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true
end
