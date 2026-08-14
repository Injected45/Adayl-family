#!/usr/bin/env bash
# _env.sh — where the local test Postgres lives. Sourced by every script here.
#
# The probe suite needs a real PostgreSQL. It cannot use the Supabase CLI's local
# stack because that needs Docker, and Docker's Linux engine will not start on
# this machine (WSL has no distributions). So it uses portable Postgres binaries
# instead: no installer, no admin rights, no service.
#
# Those binaries used to live in the session's TEMP scratchpad, which meant the
# whole suite worked exactly once, on one machine, until Windows cleaned TEMP. They
# now live in a stable per-user directory, and supabase/tests/local_pg.sh
# provisions it on demand.
#
# Override any of these from the environment if you already run Postgres somewhere.

# Stable, per-user, outside the repo. ~1 GB once extracted (EDB ships debug
# symbols and docs alongside the binaries), so it is deliberately not in the
# project tree.
: "${PG_HOME:=${LOCALAPPDATA:-$HOME}/family_app_localpg}"
: "${PG_BIN:=$PG_HOME/pgsql/bin}"
: "${PG_DATA:=$PG_HOME/data}"
: "${PG_LOG:=$PG_HOME/pg.log}"

: "${PGPORT:=55432}"
: "${PGHOST:=127.0.0.1}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:=famapp_local}"

# Pinned: psql otherwise takes its client encoding from the Windows console
# codepage, and a WIN1252 default rejects the Arabic in every migration with
# "character with byte sequence 0x81 has no equivalent in encoding UTF8".
export PGCLIENTENCODING=UTF8
export PGPASSWORD PGPORT PGHOST PGUSER

# Prefer the provisioned copy; fall back to psql on PATH for anyone who already
# has a local server.
if [ -x "$PG_BIN/psql.exe" ]; then
  PSQL="$PG_BIN/psql.exe"
elif [ -x "$PG_BIN/psql" ]; then
  PSQL="$PG_BIN/psql"
elif command -v psql >/dev/null 2>&1; then
  PSQL="psql"
else
  PSQL=""
fi
# Scratch space for the scripts' own working files (captured output, race logs).
# Was the session TEMP scratchpad, which vanished between runs.
: "${PG_WORK:=$PG_HOME/work}"
mkdir -p "$PG_WORK" 2>/dev/null || true

export PSQL PG_HOME PG_BIN PG_DATA PG_LOG PG_WORK

# Fails with an instruction rather than a connection error, because "could not
# connect to server" tells you nothing about what to do next.
require_pg() {
  if [ -z "$PSQL" ]; then
    echo "No psql found. Provision the local test database first:" >&2
    echo "    bash supabase/tests/local_pg.sh start" >&2
    return 1
  fi
  if ! "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
       -X -q -tAc "select 1" >/dev/null 2>&1; then
    echo "No PostgreSQL answering on $PGHOST:$PGPORT. Start it with:" >&2
    echo "    bash supabase/tests/local_pg.sh start" >&2
    return 1
  fi
}
