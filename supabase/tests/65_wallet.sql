-- 65_wallet.sql — prepayment, and the credit it leaves behind.
--
-- Runs LATE, in a file of its own, and both facts are deliberate. The group
-- needs an عديل who is not in the shared fixture — an overpayment settles every
-- open month for whoever receives it, so doing this to عديل 1 would quietly
-- rewrite the balances 30_rules asserts line by line — and a FIFTH عديل would
-- break 40_rls, which counts the register and expects four.
--
-- So it comes after every group that counts, and before 70_purge, which erases
-- the lot and asserts only that the tables end empty.

SET client_min_messages = warning;

-- ═════ THE WALLET ════════════════════════════════════════════════════════════
-- Prepayment. The association opened this deliberately: a member may hand over
-- a year at once, or round his payment up, and the surplus sits against his
-- name until the months it belongs to are raised. `register_payment` used to
-- refuse both — paying a man who owed nothing, and paying more than he owed —
-- and a treasurer holding cash he could not enter was the worse outcome.
--
-- There is NO wallet column. The surplus is the part of a payment the FIFO loop
-- could not allocate:
--
--     credit  =  Σ payments  −  Σ payment_allocations
--
-- so it is a view over rows that already exist and cannot drift from the money.
-- Spending it means WRITING the missing allocation, which is also what puts the
-- prepaid month in his statement beside the receipt that settled it.
--
-- On an عديل of its own, appended LAST: an overpayment settles every open month
-- for whoever receives it, so running this against the shared fixture would
-- quietly rewrite the balances every group above depends on.
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.succeeds('wallet', 'a fresh عديل for the wallet checks', $sql$
  SELECT public.save_adeel(NULL, '{"fullName":"مودع مقدماً"}'::jsonb)
$sql$);

SELECT probe.succeeds('wallet', 'one month is charged to him', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name, total)
  SELECT max(id), '2026-02', DATE '2026-02-28', 'مودع مقدماً', 20
    FROM public.adeels
$sql$);

SELECT probe.become('00000000-0000-0000-0000-0000000000a3');  -- treasurer
-- The refusal that is gone: 50 against a 20 debt.
SELECT probe.succeeds('wallet', 'paying MORE than is owed is accepted', $sql$
  SELECT public.register_payment(
    (SELECT max(id) FROM public.adeels), 50, 'نقداً', 'prepay')
$sql$);
SELECT probe.eq('wallet', 'the month it could cover is settled in full',
  $sql$ SELECT balance::text FROM public.receivables
         WHERE period = '2026-02'
           AND adeel_id = (SELECT max(id) FROM public.adeels) $sql$, '0.00');
SELECT probe.eq('wallet', 'and the surplus is credit — unallocated, not lost',
  $sql$ SELECT "credit" FROM public.v_adeels
         WHERE "id" = (SELECT max(id) FROM public.adeels) $sql$, '30.00');
-- The sign is the whole display rule: negative means the association is holding
-- his money, and the portal paints that green instead of red.
SELECT probe.eq('wallet', 'netBalance is NEGATIVE, which is what turns it green',
  $sql$ SELECT "netBalance" FROM public.v_adeels
         WHERE "id" = (SELECT max(id) FROM public.adeels) $sql$, '-30.00');

-- Owing NOTHING is no longer a reason to refuse money either.
SELECT probe.succeeds('wallet', 'a man who owes nothing may still pay in', $sql$
  SELECT public.register_payment(
    (SELECT max(id) FROM public.adeels), 10, 'نقداً', 'prepay-2')
$sql$);
SELECT probe.eq('wallet', '...and it all becomes credit',
  $sql$ SELECT "credit" FROM public.v_adeels
         WHERE "id" = (SELECT max(id) FROM public.adeels) $sql$, '40.00');

-- ── The drawdown ────────────────────────────────────────────────────────────
-- settle_from_credit is what generate_period calls the instant it raises a
-- receivable, so a member who paid ahead never sees the new month appear as a
-- debt he already covered — not even between two statements.
SELECT probe.succeeds('wallet', 'a NEW month is charged to him', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name, total)
  SELECT max(id), '2026-03', DATE '2026-03-31', 'مودع مقدماً', 20
    FROM public.adeels
$sql$);
SELECT probe.eq('wallet', 'before the drawdown the new month is unpaid',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE period = '2026-03'
           AND adeel_id = (SELECT max(id) FROM public.adeels) $sql$, '0.00');
SELECT probe.succeeds('wallet', 'the wallet is spent on it', $sql$
  SELECT public.settle_from_credit((SELECT max(id) FROM public.adeels))
$sql$);
SELECT probe.eq('wallet', 'the new month is paid from credit alone',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE period = '2026-03'
           AND adeel_id = (SELECT max(id) FROM public.adeels) $sql$, '20.00');
SELECT probe.eq('wallet', '...and the wallet is drawn down by exactly that',
  $sql$ SELECT "credit" FROM public.v_adeels
         WHERE "id" = (SELECT max(id) FROM public.adeels) $sql$, '20.00');
-- The allocation row is the LINK: which receipt paid which month, recorded
-- months after the receipt was written. Without it the statement would show a
-- charge with no settlement beside it.
SELECT probe.eq('wallet', 'the prepaid month names the receipt that paid it',
  $sql$ SELECT count(*)::text FROM public.payment_allocations a
          JOIN public.payments p ON p.id = a.payment_id
         WHERE p.reference = 'prepay' AND a.period = '2026-03' $sql$, '1');
-- Oldest receipt first, so a later cancellation takes back credit that is still
-- unspent rather than unpicking a month already settled from another receipt.
SELECT probe.eq('wallet', 'the OLDEST receipt is the one spent first',
  $sql$ SELECT coalesce(sum(a.amount), 0)::text
          FROM public.payment_allocations a
          JOIN public.payments p ON p.id = a.payment_id
         WHERE p.reference = 'prepay-2' $sql$, '0.00');

-- Running it again must do nothing: there is no open month left to settle, and
-- a second pass that spent the wallet twice would be a way to conjure money.
SELECT probe.eq('wallet', 'a second drawdown applies nothing',
  $sql$ SELECT public.settle_from_credit(
          (SELECT max(id) FROM public.adeels))::text $sql$, '0.00');

-- generate_period is the real caller. Asserted structurally because closing a
-- month here would bill the whole register and break rule 15b for every group.
SELECT probe.note('wallet', 'generate_period is what calls it in production',
  position('settle_from_credit' in
    pg_get_functiondef('public.generate_period(character)'::regprocedure)) > 0);

-- ── Cancelling a credited receipt ───────────────────────────────────────────
-- Rule 9 reverses the allocations; the credit that was never spent has to go
-- with them, or the association would still be showing money it handed back.
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.succeeds('wallet', 'the prepayment is cancelled', $sql$
  SELECT public.cancel_payment(
    (SELECT id FROM public.payments WHERE reference = 'prepay'), 'اختبار')
$sql$);
SELECT probe.eq('wallet', 'its months are owed again',
  $sql$ SELECT sum(balance)::text FROM public.receivables
         WHERE adeel_id = (SELECT max(id) FROM public.adeels)
           AND status <> 'ملغي' $sql$, '40.00');
SELECT probe.eq('wallet', '...and the credit it carried is gone with it',
  $sql$ SELECT "credit" FROM public.v_adeels
         WHERE "id" = (SELECT max(id) FROM public.adeels) $sql$, '10.00');
