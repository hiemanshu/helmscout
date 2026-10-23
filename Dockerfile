# syntax=docker/dockerfile:1

# helmscout — SPA + JSON API + MCP server + a read-only SQLite snapshot.
#
# The database is passed as a named build context and baked into the image:
#
#   mkdir -p db-bake
#   sqlite3 data/helmscout.db "VACUUM INTO 'db-bake/helmscout.db'"
#   docker build --build-context db=db-bake -t helmscout .
#   docker run -p 4000:4000 -e SECRET_KEY_BASE=$(openssl rand -base64 48) helmscout
#
# It is opened read-only at runtime: no volumes, no downloads, no writable state.

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
    DATABASE_PATH=/app/data/helmscout.db HOME=/app
RUN apt-get update -y && apt-get install -y --no-install-recommends \
      ca-certificates locales openssl && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
WORKDIR /app
COPY --from=build /app/_build/prod/rel/helmscout ./
COPY --from=frontend /web/dist /app/frontend
COPY --from=db helmscout.db /app/data/helmscout.db
RUN chmod 0444 /app/data/helmscout.db
EXPOSE 4000
ENTRYPOINT ["/app/bin/helmscout"]
CMD ["start"]
