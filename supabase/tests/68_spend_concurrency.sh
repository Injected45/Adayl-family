#!/usr/bin/env bash
# 68_spend_concurrency.sh — two admins, one treasury.
#
# register_disbursement calls the settings row its "treasury mutex" and the
# commit that introduced it calls that lock THE RULE THAT MAKES IT SAFE. Nothing
# ever raced it. Every other money rule in this suite has a failing case, and a
# lock is the one kind of guarantee a single connection CANNOT test: a session
# never contends with itself, so the FOR UPDATE is a no-op in every check that
# already exists and would go on passing if it were deleted.
#
# The race: both sessions try to disburse the WHOLE balance at the same moment.
# Unserialised, both read the same available figure, both pass the overdraft
# check, and the association pays out twice what it holds — the fund ends the day
# short by exactly one voucher. Serialised, the second session re-reads a
# treasury the first has already emptied and is refused by RUL17.
#
# Runs AFTER 67_disbursement, which asserts exact treasury figures, and before
# the purge that erases the lot. It spends the fund down to zero and leaves the
# winning voucher standing; nothing after it reads a balance.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
. "$HERE/_env.sh"

Q() { "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -t -A "$@"; }

ADMIN='00000000-0000-0000-0000-0000000000a1'
CLAIMS="{\"sub\":\"$ADMIN\",\"role\":\"authenticated\"}"

# What the fund actually holds right now. Read rather than assumed: earlier
# groups collect and cancel, and a literal here would be a guess about what they
# happened to leave behind.
BAL=$(Q <<SQL
SELECT "balance" FROM public.v_cash_summary;
SQL
)
VOUCHERS_BEFORE=$(Q -c "SELECT count(*)::text FROM public.disbursements;")

race_session() {
  local out="$1"
  "$PSQL" -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d famtest -X -q -t -A > "$out" 2>&1 <<SQL
BEGIN;
SELECT set_config('request.jwt.claims', '$CLAIMS', true);
-- Both transactions are open and past their claim before either calls the
-- function, so they meet at the lock rather than one after the other.
SELECT pg_sleep(0.05);
SELECT 'RESULT=' || (public.register_disbursement(
         $BAL, 'مصاريف إدارية', 'مورد التزامن', 'نقداً') ->> 'voucherNo');
COMMIT;
SQL
}

A="$PG_WORK/spend_a.txt"; B="$PG_WORK/spend_b.txt"
race_session "$A" &
PA=$!
race_session "$B" &
PB=$!
wait $PA; wait $PB

OK_A=$(grep -c 'RESULT=EXP-' "$A" || true)
OK_B=$(grep -c 'RESULT=EXP-' "$B" || true)
WINNERS=$(( OK_A + OK_B ))
# The loser must be refused by the treasury rule specifically. A deadlock or a
# crash would also leave one winner, and would satisfy a bare "winners = 1" while
# meaning the admin's phone showed something unexplained.
REFUSED=$(cat "$A" "$B" | grep -c 'RUL17\|يتجاوز رصيد الصندوق' || true)
CRASHED=$(cat "$A" "$B" | grep -icE 'deadlock|could not serialize|server closed' || true)

BAL_AFTER=$(Q <<SQL
SELECT "balance" FROM public.v_cash_summary;
SQL
)
VOUCHERS_AFTER=$(Q -c "SELECT count(*)::text FROM public.disbursements;")
WROTE=$(( VOUCHERS_AFTER - VOUCHERS_BEFORE ))

echo "  session A: $(tr -d '\r' < "$A" | tail -2 | tr '\n' ' ')"
echo "  session B: $(tr -d '\r' < "$B" | tail -2 | tr '\n' ' ')"
echo "  balance=$BAL -> $BAL_AFTER  winners=$WINNERS vouchers+=$WROTE"

Q -v ON_ERROR_STOP=1 <<SQL
SELECT probe.note('spend_race',
  'the treasury had a balance to race for',
  '$BAL'::numeric > 0, 'balance=$BAL');
-- ★ THE GUARANTEE. Without the FOR UPDATE on the settings row both of these
--   succeed and the association has paid out twice what it held.
SELECT probe.note('spend_race',
  'exactly ONE of two simultaneous full-balance vouchers succeeded',
  $WINNERS = 1, 'winners=$WINNERS (a=$OK_A b=$OK_B)');
SELECT probe.note('spend_race',
  'the loser was refused by the treasury rule, not by a deadlock',
  $REFUSED >= 1 AND $CRASHED = 0, 'refused=$REFUSED crashed=$CRASHED');
SELECT probe.note('spend_race',
  'the fund never went below zero',
  '$BAL_AFTER'::numeric >= 0, 'balance after=$BAL_AFTER');
SELECT probe.note('spend_race',
  'and the refused session left NO voucher row behind',
  $WROTE = 1, 'vouchers written=$WROTE');
SQL
