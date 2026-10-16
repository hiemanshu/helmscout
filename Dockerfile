# helmscout — API + MCP server (and, optionally, the SPA).
#
#   docker build -t helmscout .
#   docker run -p 4000:4000 \
#     -e SECRET_KEY_BASE=$(openssl rand -base64 48) \
#     -e DATABASE_PATH=/data/helmscout.db \
#     -e HELMSCOUT_DB_URL=https://github.com/<owner>/<repo>/releases/download/db/helmscout.db.gz \
#     helmscout
#
# The image is read-only by design: HELMSCOUT_DB_URL points at the database the
# pipeline publishes (raw or .gz; set HELMSCOUT_DB_TOKEN if the asset needs
# auth), and it is fetched once at boot. The SPA is deployed separately (static)
# but this image serves it too, so a single container works for local/dev use.

# --- frontend build -----------------------------------------------------------
FROM docker.io/library/node:22-bookworm-slim AS frontend
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY web/ ./
RUN npm run build

# --- elixir release -----------------------------------------------------------
FROM docker.io/library/elixir:1.20.4-otp-29 AS build
ENV MIX_ENV=prod LANG=C.UTF-8
RUN apt-get update -y && apt-get install -y --no-install-recommends git build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && mix local.hex --force && mix local.rebar --force
WORKDIR /app
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile
COPY config config
COPY priv priv
COPY lib lib
RUN mix compile && mix release

# --- runtime ------------------------------------------------------------------
FROM docker.io/library/elixir:1.20.4-otp-29-slim AS app
ENV MIX_ENV=prod LANG=C.UTF-8 PORT=4000 FRONTEND_DIR=/app/frontend \
    HOME=/app
RUN apt-get update -y && apt-get install -y --no-install-recommends \
      ca-certificates locales openssl && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
WORKDIR /app
COPY --from=build /app/_build/prod/rel/helmscout ./
COPY --from=frontend /web/dist /app/frontend
EXPOSE 4000
ENTRYPOINT ["/app/bin/helmscout"]
CMD ["start"]
