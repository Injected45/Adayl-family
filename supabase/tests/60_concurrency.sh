#!/usr/bin/env bash
# 60_concurrency.sh — two treasurers, one balance.
#
# This is the risk the original plan called "the single biggest": in the
# prototype the FIFO allocation is safe because JavaScript is single-threaded and
# there is one user. With two treasurers on two phones, an unserialised
# allocation double-spends a balance. Losing the Node tier does not change the
# problem — it moves it entirely inside register_payment's FOR UPDATE.
#
# It cannot be tested from one connection: a single session never contends with
# itself. Two psql processes, deliberately overlapped.
#
# Fixture: a family owing exactly 100.00 in one receivable. Both sessions try to
# pay 60.00. Correct outcome is one success and one RUL07 — never two successes,
# because 120 collected against 100 owed is money invented from nothing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
. "$HERE/_env.sh"

Q() { "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -t -A "$@"; }

TREASURER='00000000-0000-0000-0000-0000000000a3'
CLAIMS="{\"sub\":\"$TREASURER\",\"role\":\"authenticated\"}"

# ── Fixture ───────────────────────────────────────────────────────────────────
FID=$(Q <<SQL
INSERT INTO public.families DEFAULT VALUES RETURNING id;
SQL
)
Q -v ON_ERROR_STOP=1 <<SQL
INSERT INTO public.members (family_id, kind, full_name, national_id, dob, registered_at)
VALUES ($FID, 'father', 'أب التزامن', '1000000009000', '1980-01-01', current_date);
INSERT INTO public.receivables (family_id, period, period_end, father_fee, son_fee,
  father_name, eligibility_age_snapshot, warning_months_snapshot, total)
VALUES ($FID, '2027-01', '2027-01-31', 100, 0, 'أب التزامن', 16, 3, 100.00);
SQL

race_session() {
  local delay="$1" out="$2"
  "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -t -A > "$out" 2>&1 <<SQL
BEGIN;
SELECT set_config('request.jwt.claims', '$CLAIMS', true);
-- Both sessions reach the locking SELECT inside the same window. The staggered
-- sleep is INSIDE the transaction but BEFORE the call, so both are open at once.
SELECT pg_sleep($delay);
SELECT 'RESULT=' || (public.register_payment($FID, 60.00, 'نقداً') ->> 'receiptNo');
COMMIT;
SQL
}

A="$PG_WORK/race_a.txt"; B="$PG_WORK/race_b.txt"
race_session 0.05 "$A" &
PA=$!
race_session 0.05 "$B" &
PB=$!
wait $PA; wait $PB

OK_A=$(grep -c 'RESULT=PAY-' "$A" || true)
OK_B=$(grep -c 'RESULT=PAY-' "$B" || true)
WINNERS=$(( OK_A + OK_B ))
LOSER_MSG="$(cat "$A" "$B" | grep -i 'Rule 7' | head -1 || true)"

PAID=$(Q -c "SELECT paid::text FROM public.receivables WHERE family_id = $FID;")
# c.amount, qualified. Both cash_movements and payments have an `amount` column,
# so the bare name was ambiguous — the query errored, COLLECTED came back empty,
# and the two notes below it never ran. The suite still reported 169 checks,
# because it counted what was recorded rather than what was expected. That is why
# probe.report() now takes an expected total.
# Fed on STDIN, not as a -c argument. This shell mangles non-ASCII in argv, so
# 'ملغي' arrived as '????' and Postgres rejected it as an invalid pay_status. The
# heredoc form is byte-exact. (The ambiguity fix above unmasked this: the query
# used to fail at parse time, before it ever reached the enum comparison.)
COLLECTED=$(Q <<SQL
SELECT coalesce(sum(c.amount),0)::text FROM public.cash_movements c
  JOIN public.payments p ON p.id = c.payment_id
 WHERE p.family_id = $FID AND c.status <> 'ملغي';
SQL
)
NPAY=$(Q -c "SELECT count(*)::text FROM public.payments WHERE family_id = $FID;")

echo "  session A: $(tr -d '\r' < "$A" | tail -2 | tr '\n' ' ')"
echo "  session B: $(tr -d '\r' < "$B" | tail -2 | tr '\n' ' ')"
echo "  winners=$WINNERS paid=$PAID collected=$COLLECTED payments=$NPAY"

# Record into the same results table the SQL probes use, so one report covers all.
Q -v ON_ERROR_STOP=1 <<SQL
SELECT probe.note('concurrency',
  'exactly one of two simultaneous 60.00 payments succeeded',
  $WINNERS = 1, 'winners=$WINNERS (a=$OK_A b=$OK_B)');
SELECT probe.note('concurrency',
  'the loser was refused by rule 7, not by a deadlock or a crash',
  $(if [ -n "$LOSER_MSG" ]; then echo true; else echo false; fi),
  '$(printf '%s' "$LOSER_MSG" | tr -d "'" | cut -c1-100)');
SELECT probe.note('concurrency',
  'paid never exceeded the 100.00 owed',
  '$PAID'::numeric <= 100.00, 'paid=$PAID');
SELECT probe.note('concurrency',
  'the treasury collected exactly what was allocated',
  '$COLLECTED'::numeric = '$PAID'::numeric, 'collected=$COLLECTED paid=$PAID');
SELECT probe.note('concurrency',
  'no orphan payment row from the losing session',
  $NPAY = $WINNERS, 'payments=$NPAY winners=$WINNERS');
SQL
