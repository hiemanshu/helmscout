#!/bin/sh
set -e

# Run pending migrations before booting the server.
if [ -n "${DATABASE_PATH:-}" ]; then
  echo "running migrations against ${DATABASE_PATH}"
  /app/bin/helmscout eval "Helmscout.Release.migrate()"
fi

exec /app/bin/helmscout "$@"
