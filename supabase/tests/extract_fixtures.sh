#!/usr/bin/env bash
# extract_fixtures.sh — captures the REAL wire JSON for every read endpoint.
#
# PostgREST builds its response body with json_agg inside Postgres, so what this
# script writes is byte-for-byte what the Flutter client will receive. Committing
# it as fixtures lets app/test/supabase_contract_test.dart parse the actual shape
# into the actual domain models — which verifies the whole view→model contract
# without needing PostgREST, a Supabase project, or a network.
#
# The one thing it cannot cover is the HTTP hop itself.
#
#   bash supabase/tests/extract_fixtures.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
. "$HERE/_env.sh"
require_pg || exit 1
OUT="$HERE/../../app/test/fixtures/supabase"
mkdir -p "$OUT"

# Rebuild and seed, then run enough real activity through the RPCs that the
# fixtures contain payments, allocations, cash movements and audit rows rather
# than empty arrays. An empty fixture proves nothing about parsing.
bash "$HERE/apply.sh" > /dev/null
run() { "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -v ON_ERROR_STOP=1 "$@"; }
run -f "$HERE/10_harness.sql" > /dev/null
run -f "$HERE/20_seed.sql"    > /dev/null

FM='00000000-0000-0000-0000-0000000000a2'
TR='00000000-0000-0000-0000-0000000000a3'
run > /dev/null <<SQL
SELECT set_config('request.jwt.claims', '{"sub":"$FM","role":"authenticated"}', false);
SELECT public.generate_period('2026-02');
SELECT public.generate_period('2026-03');
SELECT set_config('request.jwt.claims', '{"sub":"$TR","role":"authenticated"}', false);
-- Spans two periods, so the FIFO allocation array has more than one element.
SELECT public.register_payment(1, 50, 'نقداً', 'ref-1', 'أمين الصندوق', 'ملاحظة');
SELECT public.register_payment(2, 5, 'تحويل مصرفي', 'TRX-9');
SELECT set_config('request.jwt.claims', '{"sub":"$FM","role":"authenticated"}', false);
-- One cancelled payment, so the fixtures include a voided row.
SELECT public.cancel_payment(2, 'تصحيح إدخال');
SQL

# Every capture runs as an APPROVED VIEWER through the authenticated role, i.e.
# exactly as the app will. A fixture captured as postgres would bypass RLS and
# could contain rows the client will never actually receive.
VIEWER='00000000-0000-0000-0000-0000000000a4'
ADMIN='00000000-0000-0000-0000-0000000000a1'

capture() { # capture <file> <sql-returning-one-json-value> [role-uuid]
  local file="$1" sql="$2" who="${3:-$VIEWER}"
  "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -t -A \
    -v ON_ERROR_STOP=1 <<SQL > "$OUT/$file"
SET ROLE authenticated;
-- A DO block, not a bare SELECT: set_config() RETURNS its value, and with -t -A
-- that value lands in the fixture file as a stray first line, making the JSON
-- unparseable. DO emits nothing.
DO \$\$ BEGIN
  PERFORM set_config('request.jwt.claims',
    '{"sub":"$who","role":"authenticated"}', false);
END \$\$;
$sql
SQL
  printf '  %-28s %6s bytes\n' "$file" "$(wc -c < "$OUT/$file" | tr -d ' ')"
}

echo "capturing fixtures as an approved viewer:"
capture settings.json          "SELECT public.api_settings();"
capture me.json                "SELECT public.api_me();"
capture dashboard.json         "SELECT public.api_dashboard();"
capture alerts.json            "SELECT public.api_alerts();"
capture family_detail.json     "SELECT public.api_family_detail(1);"
capture family_statement.json  "SELECT public.api_family_statement(1);"
capture receivables.json       "SELECT public.api_receivables(NULL);"
capture financial_report.json  "SELECT public.api_financial_report('2026-01-01','2030-12-31');"

# Views arrive from PostgREST as a JSON array of row objects — json_agg over the
# view is that exact encoding.
capture families.json      "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_families ORDER BY \"id\") t;"
capture members.json       "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_members ORDER BY \"id\") t;"
capture payments.json      "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_payments ORDER BY \"id\") t;"
capture cash_movements.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_cash_movements ORDER BY \"id\") t;"
capture cash_summary.json  "SELECT to_json(t) FROM (SELECT * FROM public.v_cash_summary) t;"
capture officials.json     "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_officials) t;"
capture settings_view.json "SELECT to_json(t) FROM (SELECT * FROM public.v_settings) t;"

# financeManager and admin see more than a viewer, so their endpoints are captured
# under the role that will actually call them.
capture audit.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_audit ORDER BY \"id\") t;" "$FM"
capture users.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_users ORDER BY \"email\") t;" "$ADMIN"

echo "fixtures written to app/test/fixtures/supabase/"
