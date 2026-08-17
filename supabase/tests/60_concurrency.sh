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
# Fixture: an عديل owing exactly 100.00 in one receivable. Both sessions try to
# pay 60.00.
#
# ── WHAT THIS PROVES CHANGED WHEN THE WALLET ARRIVED ──────────────────────────
# It used to be one success and one RUL07: rule 7 capped a payment at the
# balance, so the second 60.00 was refused outright and "winners = 1" was the
# whole proof. That cap is gone deliberately — a man may now hand over more than
# he owes and the surplus becomes credit — so BOTH sessions now succeed, and an
# assertion of "winners = 1" would have failed forever while the code was right.
#
# The double-spend it was written to catch is untouched, and is now stated
# directly instead of through the refusal:
#
#     the 100.00 balance must be ALLOCATED EXACTLY ONCE.
#
# Two unserialised sessions each read a 100.00 balance and each allocate 60.00,
# and the receivable ends up 120.00 paid against a 100.00 charge — money invented
# from nothing, exactly as before. Serialised, the second session sees the 40.00
# that is left, allocates that, and puts 20.00 in the wallet. So: paid = 100.00,
# collected = 120.00, credit = 20.00 — and it is the FIRST of those three that
# is the guarantee.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
. "$HERE/_env.sh"

Q() { "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -t -A "$@"; }

TREASURER='00000000-0000-0000-0000-0000000000a3'
CLAIMS="{\"sub\":\"$TREASURER\",\"role\":\"authenticated\"}"

# ── Fixture ───────────────────────────────────────────────────────────────────
AID=$(Q <<SQL
INSERT INTO public.adeels (full_name, dob, registered_at)
VALUES ('عديل التزامن', '1980-01-01', current_date) RETURNING id;
SQL
)
Q -v ON_ERROR_STOP=1 <<SQL
INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name,
  total)
VALUES ($AID, '2027-01', '2027-01-31', 'عديل التزامن', 100.00);
SQL

race_session() {
  local delay="$1" out="$2"
  "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -t -A > "$out" 2>&1 <<SQL
BEGIN;
SELECT set_config('request.jwt.claims', '$CLAIMS', true);
-- Both sessions reach the locking SELECT inside the same window. The staggered
-- sleep is INSIDE the transaction but BEFORE the call, so both are open at once.
SELECT pg_sleep($delay);
SELECT 'RESULT=' || (public.register_payment($AID, 60.00, 'نقداً') ->> 'receiptNo');
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
# Neither session may die. A deadlock or a serialisation abort would also leave
# the ledger consistent, and would look like a pass on the allocation check while
# meaning the treasurer's phone showed an error — so it is asserted separately.
CRASHED="$(cat "$A" "$B" | grep -icE 'deadlock|could not serialize|server closed' || true)"

PAID=$(Q -c "SELECT paid::text FROM public.receivables WHERE adeel_id = $AID;")
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
 WHERE p.adeel_id = $AID AND c.status <> 'ملغي';
SQL
)
NPAY=$(Q -c "SELECT count(*)::text FROM public.payments WHERE adeel_id = $AID;")

echo "  session A: $(tr -d '\r' < "$A" | tail -2 | tr '\n' ' ')"
echo "  session B: $(tr -d '\r' < "$B" | tail -2 | tr '\n' ' ')"
echo "  winners=$WINNERS paid=$PAID collected=$COLLECTED payments=$NPAY"

# Record into the same results table the SQL probes use, so one report covers all.
Q -v ON_ERROR_STOP=1 <<SQL
SELECT probe.note('concurrency',
  'both simultaneous 60.00 payments were accepted, as the wallet allows',
  $WINNERS = 2, 'winners=$WINNERS (a=$OK_A b=$OK_B)');
SELECT probe.note('concurrency',
  'neither session died on a deadlock or a serialisation failure',
  $CRASHED = 0, 'crash lines=$CRASHED');
-- ★ THE GUARANTEE. Unserialised, both sessions read 100.00 owed and both
--   allocate 60.00, leaving 120.00 paid against a 100.00 charge. This is the
--   check that goes red the moment register_payment's FOR UPDATE is weakened.
SELECT probe.note('concurrency',
  'the 100.00 balance was allocated EXACTLY ONCE, not twice',
  '$PAID'::numeric = 100.00, 'paid=$PAID');
SELECT probe.note('concurrency',
  'paid never exceeded the 100.00 owed',
  '$PAID'::numeric <= 100.00, 'paid=$PAID');
SELECT probe.note('concurrency',
  'and the 20.00 the months could not absorb sits in the wallet, unallocated',
  '$COLLECTED'::numeric - '$PAID'::numeric = 20.00,
  'collected=$COLLECTED paid=$PAID');
SELECT probe.note('concurrency',
  'no orphan payment row from the losing session',
  $NPAY = $WINNERS, 'payments=$NPAY winners=$WINNERS');
SQL
