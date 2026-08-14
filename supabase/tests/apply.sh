#!/usr/bin/env bash
# Rebuilds the local probe database from scratch: shim, then every migration in
# order. ON_ERROR_STOP is not optional — psql otherwise reports success after a
# failed statement, which would make the probe suite prove nothing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
. "$HERE/_env.sh"
require_pg || exit 1

run() { "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -X -q -v ON_ERROR_STOP=1 "$@"; }

run -d postgres -c "DROP DATABASE IF EXISTS famtest;" -c "CREATE DATABASE famtest;"
run -d famtest -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
run -d famtest -f "$HERE/00_local_shim.sql"

for f in "$HERE/../migrations"/*.sql; do
  echo "-- applying $(basename "$f")"
  run -d famtest -f "$f"
done

echo "schema applied cleanly"
