import Config

if config_env() == :prod do
  # SQLite file. The pipeline (run on your runner) is the writer; the deployed
  # app only reads it.
  config :helmscout, Helmscout.Repo,
    database: System.get_env("DATABASE_PATH") || "/data/helmscout.db",
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    journal_mode: :wal,
    foreign_keys: :on,
    busy_timeout: 5000

  # Where the read-only copy is fetched from at boot, if set (e.g. a GitHub
  # release asset holding the gzipped database).
  if url = System.get_env("HELMSCOUT_DB_URL") do
    config :helmscout, :database_url, url
  end

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
