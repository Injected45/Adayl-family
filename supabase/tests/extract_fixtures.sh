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

# ON_ERROR_STOP on the SEEDING run below, not only on the captures. A statement
# that failed there used to print to stderr and carry on, so the fixtures were
# written from a half-seeded database — every capture succeeded, the script
# reported success, and the missing rows only surfaced as an expectation failure
# in supabase_contract_test.dart with nothing to point at.
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
# Money OUT is admin-only, so the vouchers below have to be written as one.
AD='00000000-0000-0000-0000-0000000000a1'
run -v ON_ERROR_STOP=1 > /dev/null <<SQL
SELECT set_config('request.jwt.claims', '{"sub":"$FM","role":"authenticated"}', false);
SELECT public.generate_period('2026-02');
SELECT public.generate_period('2026-03');
SELECT set_config('request.jwt.claims', '{"sub":"$TR","role":"authenticated"}', false);
-- Two periods at 20.00 each = 40.00 outstanding, so 30.00 fills February and
-- spills into March: the FIFO allocation array has more than one element.
SELECT public.register_payment(1, 30, 'نقداً', 'ref-1', 'أمين الصندوق', 'ملاحظة');
SELECT public.register_payment(2, 5, 'تحويل مصرفي', 'TRX-9');
SELECT set_config('request.jwt.claims', '{"sub":"$FM","role":"authenticated"}', false);
-- One cancelled payment, so the fixtures include a voided row.
SELECT public.cancel_payment(2, 'تصحيح إدخال');

-- ── Money OUT ────────────────────────────────────────────────────────────────
-- 30.00 was collected and 5.00 of it cancelled, so the treasury holds 30.00 and
-- these three vouchers fit inside it. Deliberately varied, because a fixture is
-- only worth the shapes it contains — and there are exactly two shapes:
--   • جماعي, cash, carrying reference/handedBy/note and NO payee at all
--   • لمشترك by TRANSFER, so payeeAdeelId and the three bank columns are
--     non-null in at least one row
--   • one CANCELLED, so the voided shape is captured exactly as with payments
SELECT set_config('request.jwt.claims', '{"sub":"$AD","role":"authenticated"}', false);
SELECT public.register_disbursement(
  12, 'جماعي', 'نقداً', NULL, 'فطور رمضان',
  'INV-3', NULL, NULL, NULL, 'أمين الصندوق', 'إفطار الجمعية');
SELECT public.register_disbursement(
  4, 'لمشترك', 'تحويل مصرفي', 1, 'مولود',
  'TRX-77', 'المصرف التجاري الوطني', 'علي المهدي', '0021547');
SELECT public.register_disbursement(3, 'جماعي', 'نقداً', NULL, 'عزاء');
SELECT public.cancel_disbursement(3, 'تصحيح إدخال');
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
capture adeel_detail.json      "SELECT public.api_adeel_detail(1);"
capture adeel_statement.json   "SELECT public.api_adeel_statement(1);"
# What the association GAVE him. Captured beside the statement on purpose: the
# two are read together and must never be confused, and the fixture is where a
# renamed key is caught before the app runs.
capture adeel_aid.json         "SELECT public.api_adeel_aid(1);"
capture receivables.json       "SELECT public.api_receivables(NULL);"
capture financial_report.json  "SELECT public.api_financial_report('2026-01-01','2030-12-31');"
capture closable_periods.json  "SELECT public.api_closable_periods();"

# Views arrive from PostgREST as a JSON array of row objects — json_agg over the
# view is that exact encoding.
capture adeels.json        "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_adeels ORDER BY \"id\") t;"
capture payments.json      "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_payments ORDER BY \"id\") t;"
capture cash_movements.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_cash_movements ORDER BY \"id\") t;"
capture cash_summary.json  "SELECT to_json(t) FROM (SELECT * FROM public.v_cash_summary) t;"
capture officials.json     "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_officials) t;"
capture settings_view.json "SELECT to_json(t) FROM (SELECT * FROM public.v_settings) t;"

# Money out. The two read surfaces the الصرف tab is built on, captured as the
# same viewer — read_disbursements is has_role('viewer'), so this is the shape a
# staff client actually receives. An عديل receives nothing here at all, which is
# asserted in 67_disbursement.sql rather than captured.
capture disbursements.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_disbursements ORDER BY \"id\") t;"
capture expense_by_category.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_expense_by_category) t;"
# The member-facing totals. SECURITY DEFINER and aggregates only — the one place
# an عديل learns what the association spent without seeing a single voucher.
capture association_finance.json "SELECT public.api_association_finance();"

# financeManager and admin see more than a viewer, so their endpoints are captured
# under the role that will actually call them.
capture audit.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_audit ORDER BY \"id\") t;" "$FM"
capture users.json "SELECT coalesce(json_agg(t), '[]') FROM (SELECT * FROM public.v_users ORDER BY \"email\") t;" "$ADMIN"

echo "fixtures written to app/test/fixtures/supabase/"
