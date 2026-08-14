#!/usr/bin/env bash
# local_pg.sh — provision and control the local test PostgreSQL.
#
#   bash supabase/tests/local_pg.sh start     download if needed, init, start
#   bash supabase/tests/local_pg.sh stop
#   bash supabase/tests/local_pg.sh status
#   bash supabase/tests/local_pg.sh reset     stop, delete the data dir, start
#
# WHY NOT `supabase start`
#   That needs Docker, and Docker Desktop's Linux engine will not start here —
#   WSL reports no installed distributions. Portable Postgres binaries need no
#   installer, no admin rights and no service, and the probe suite only needs a
#   real Postgres, not the whole Supabase stack. supabase/tests/00_local_shim.sql
#   supplies the parts of the platform the migrations depend on (the auth schema,
#   the anon/authenticated/service_role roles, and Supabase's own default
#   privileges).
#
# WHY NOT the session TEMP directory
#   That is where this started, and it meant the suite worked once, on one machine,
#   until Windows cleaned TEMP. PG_HOME in _env.sh is stable per user.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
. "$HERE/_env.sh"

# The version the schema was developed and verified against. The live Supabase
# project runs 17.6; nothing in these migrations depends on the difference, but the
# version is pinned so a future failure can be attributed rather than guessed at.
PG_VERSION="16.4-1"
PG_URL="https://get.enterprisedb.com/postgresql/postgresql-${PG_VERSION}-windows-x64-binaries.zip"

is_up() {
  [ -n "$PSQL" ] && "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres \
    -X -q -tAc "select 1" >/dev/null 2>&1
}

cmd_status() {
  if is_up; then
    local v
    v=$("$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d postgres -X -q -tAc \
        "select version();" | head -c 40)
    echo "up    $PGHOST:$PGPORT  $v"
    echo "      binaries: $PG_BIN"
    echo "      data:     $PG_DATA"
  else
    echo "down  $PGHOST:$PGPORT"
    [ -d "$PG_DATA" ] && echo "      data dir exists: $PG_DATA" \
                      || echo "      no data dir yet (start will create it)"
  fi
}

cmd_start() {
  if is_up; then echo "already up on $PGHOST:$PGPORT"; return 0; fi

  # ---- binaries ----
  if [ ! -x "$PG_BIN/postgres.exe" ]; then
    echo "provisioning PostgreSQL $PG_VERSION into $PG_HOME"
    mkdir -p "$PG_HOME"
    local zip="$PG_HOME/pgsql.zip"
    if [ ! -f "$zip" ]; then
      echo "  downloading (~340 MB zipped, ~1 GB extracted, once)..."
      curl -fL --retry 3 -o "$zip" "$PG_URL"
    fi
    echo "  extracting..."
    # PowerShell rather than unzip: unzip is not present in every Git-Bash install.
    powershell -NoProfile -Command \
      "Expand-Archive -Path '$(cygpath -w "$zip" 2>/dev/null || echo "$zip")' \
       -DestinationPath '$(cygpath -w "$PG_HOME" 2>/dev/null || echo "$PG_HOME")' -Force"
    rm -f "$zip"
    . "$HERE/_env.sh"
  fi

  # ---- data directory ----
  if [ ! -f "$PG_DATA/PG_VERSION" ]; then
    echo "initialising the cluster"
    mkdir -p "$PG_DATA"
    local pwfile="$PG_HOME/pw.txt"
    printf '%s' "$PGPASSWORD" > "$pwfile"
    # --locale=C keeps collation deterministic, so ORDER BY on Arabic text sorts
    # the same here as it does anywhere else the suite runs.
    "$PG_BIN/initdb.exe" -D "$PG_DATA" -U "$PGUSER" --pwfile="$pwfile" \
      -E UTF8 --locale=C >/dev/null
    rm -f "$pwfile"
  fi

  echo "starting on port $PGPORT"
  # listen_addresses is loopback-only on purpose: this is a scratch database with a
  # known password and it must not be reachable from the network.
  "$PG_BIN/pg_ctl.exe" -D "$PG_DATA" \
    -o "-p $PGPORT -c listen_addresses=127.0.0.1" -l "$PG_LOG" start >/dev/null

  local tries=0
  until is_up; do
    tries=$((tries + 1))
    if [ "$tries" -gt 30 ]; then
      echo "did not come up. Last lines of $PG_LOG:" >&2
      tail -15 "$PG_LOG" >&2
      return 1
    fi
    sleep 1
  done
  cmd_status
}

cmd_stop() {
  if [ ! -f "$PG_DATA/PG_VERSION" ]; then echo "nothing to stop"; return 0; fi
  "$PG_BIN/pg_ctl.exe" -D "$PG_DATA" -m fast stop >/dev/null 2>&1 || true
  echo "stopped"
}

cmd_reset() {
  cmd_stop
  # Deliberate and explicit: this is scratch data the probe suite recreates from
  # the migrations on every run. Nothing here is anyone's records.
  rm -rf "$PG_DATA"
  echo "data directory deleted"
  cmd_start
}

case "${1:-status}" in
  start)  cmd_start  ;;
  stop)   cmd_stop   ;;
  status) cmd_status ;;
  reset)  cmd_reset  ;;
  *) echo "usage: local_pg.sh {start|stop|status|reset}" >&2; exit 2 ;;
esac
