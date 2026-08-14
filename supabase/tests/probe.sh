#!/usr/bin/env bash
# probe.sh — the whole suite. Exits non-zero if any check fails.
#
#   bash supabase/tests/probe.sh
#
# Rebuilds the database from the migrations every run, so a passing result always
# reflects what is committed in supabase/migrations/ and never leftover state.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
. "$HERE/_env.sh"
require_pg || exit 1
export SP

# How many checks the suite must record. A mismatch fails, so a check whose SQL
# errors before recording anything cannot hide.
EXPECTED_CHECKS=257

run() {
  "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -v ON_ERROR_STOP=1 "$@"
}

echo "=== rebuilding schema ==="
# Abort if the schema does not build. Without this the suite runs against
# whatever partially-applied state was left behind and reports PASS — which it
# did once, silently hiding a mutation test whose migration had failed.
if ! bash "$HERE/apply.sh" > "$PG_WORK/apply.out" 2>&1; then
  tail -20 "$PG_WORK/apply.out"
  echo "PROBE SUITE: FAIL (schema did not apply)"
  exit 1
fi
tail -1 "$PG_WORK/apply.out"

echo "=== harness + fixture ==="
run -f "$HERE/10_harness.sql"
run -f "$HERE/20_seed.sql"

# One session per file so SET ROLE / RESET ROLE cannot leak between groups, and
# so a file that leaves the connection in a strange state cannot mask later
# failures as passes.
echo "=== business rules ==="
run -f "$HERE/30_rules.sql"          2>&1 | grep -vE '^(INSERT|UPDATE|DELETE|SELECT|SET) ' || true

echo "=== hostile client / RLS ==="
run -f "$HERE/40_rls.sql"            2>&1 | grep -vE '^(GRANT|SET|RESET) ' || true

echo "=== family portal / per-family RLS ==="
run -f "$HERE/45_family_portal.sql"   2>&1 | grep -vE "^(INSERT|UPDATE|DELETE|SELECT|SET|RESET|CREATE|DROP) " || true

echo "=== money precision + atomicity ==="
run -f "$HERE/50_money_and_atomicity.sql" 2>&1 | grep -vE '^(CREATE|SET|RESET|DROP) ' || true

echo "=== concurrency (two sessions) ==="
bash "$HERE/60_concurrency.sh"

# LAST, and it has to be: the purge erases everything the four files above built,
# so any group scheduled after it would assert against an empty database.
echo "=== purge (destructive — erases the fixture) ==="
run -f "$HERE/70_purge.sql"          2>&1 | grep -vE '^(INSERT|DELETE|SELECT|SET|RESET|CREATE) ' || true

echo
echo "=== report ==="
# RAISE INFO goes to stderr; fold it in so the report is readable in one stream.
run -c "SELECT probe.report($EXPECTED_CHECKS);" 2>&1 | sed -e 's/^INFO:  //' -e '/^SELECT/d'
RC=${PIPESTATUS[0]}

echo
if [ "$RC" -eq 0 ]; then echo "PROBE SUITE: PASS"; else echo "PROBE SUITE: FAIL"; fi
exit "$RC"
