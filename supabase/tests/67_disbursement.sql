-- 67_disbursement.sql — money leaving the treasury.
--
-- The association could only take money IN until now: cash_kind carried the
-- single value 'تحصيل'. This group proves the other direction, and above all
-- the rule that makes it safe — **the association cannot pay out money it does
-- not hold**, which is rule 7 read backwards.
--
-- Runs after 65_wallet and before 70_purge, for the same reason that one does:
-- it spends the treasury, and every group that asserts a collected total would
-- read differently afterwards.

SET client_min_messages = warning;

-- ═════ Who may spend ═════════════════════════════════════════════════════════
-- ADMIN only, at the association's request. Taking money in belongs to the
-- treasurer; paying it out was put a rung above even the finance manager.
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');  -- treasurer
SELECT probe.raises('spend', 'a treasurer may NOT disburse', $sql$
  SELECT public.register_disbursement(10, 'مصاريف إدارية', 'مكتبة', 'نقداً')
$sql$, 'RUL00');
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.raises('spend', 'nor may the finance manager', $sql$
  SELECT public.register_disbursement(10, 'مصاريف إدارية', 'مكتبة', 'نقداً')
$sql$, 'RUL00');

SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.raises('spend', 'a zero disbursement is refused', $sql$
  SELECT public.register_disbursement(0, 'مصاريف إدارية', 'مكتبة', 'نقداً')
$sql$, 'RUL17');
SELECT probe.raises('spend', 'and a negative one', $sql$
  SELECT public.register_disbursement(-5, 'مصاريف إدارية', 'مكتبة', 'نقداً')
$sql$, 'RUL17');
SELECT probe.raises('spend', 'a nameless payee is refused', $sql$
  SELECT public.register_disbursement(10, 'مصاريف إدارية', '   ', 'نقداً')
$sql$, 'RUL17');

-- ═════ THE RULE: no overdraft ════════════════════════════════════════════════
-- A treasury that can go negative is one where the figure on the screen has
-- stopped describing anything, and the association would find out from a
-- bounced transfer rather than from the app.
SELECT probe.note('spend', 'the treasury holds something to spend',
  (SELECT "balance"::numeric FROM public.v_cash_summary) > 0);

SELECT probe.raises('spend', 'spending MORE than the treasury holds is refused',
  $sql$ SELECT public.register_disbursement(
          (SELECT "balance"::numeric + 1 FROM public.v_cash_summary),
          'مصاريف إدارية', 'مورد', 'نقداً') $sql$, 'RUL17');
SELECT probe.eq('spend', '...and the refusal left no voucher behind',
  $sql$ SELECT count(*)::text FROM public.disbursements $sql$, '0');

-- ═════ A voucher that IS within the balance ══════════════════════════════════
SELECT probe.succeeds('spend', 'spending within the balance is accepted', $sql$
  SELECT public.register_disbursement(
    10, 'مصاريف إدارية', 'مكتبة الوفاء', 'نقداً',
    NULL, 'INV-9', NULL, NULL, NULL, 'أمين الصندوق', 'قرطاسية')
$sql$);
SELECT probe.eq('spend', 'the voucher is numbered EXP-000001',
  $sql$ SELECT voucher_no FROM public.disbursements ORDER BY id LIMIT 1 $sql$,
  'EXP-000001');
SELECT probe.eq('spend', 'and the treasury balance drops by exactly that',
  $sql$ SELECT ("total"::numeric - "balance"::numeric)::text
          FROM public.v_cash_summary $sql$, '10.00');
-- `total` is everything ever COLLECTED and must NOT move. The two were the same
-- number only while money could not leave, and conflating them is what would
-- make the treasury screen overstate the fund by every voucher ever written.
SELECT probe.eq('spend', 'what was COLLECTED is unchanged by a disbursement',
  $sql$ SELECT ("disbursed" = '10.00' AND "total" <> "balance")::text
          FROM public.v_cash_summary $sql$, 'true');
SELECT probe.eq('spend', 'the heading carries the spend',
  $sql$ SELECT "total" FROM public.v_expense_by_category
         WHERE "category" = 'مصاريف إدارية' $sql$, '10.00');
-- Every heading appears, spent on or not: a report that omits a zero reads as
-- one that forgot it.
SELECT probe.eq('spend', 'all nine headings are listed, including the empty',
  $sql$ SELECT count(*)::text FROM public.v_expense_by_category $sql$, '9');

-- ═════ A payee from the register ═════════════════════════════════════════════
-- The name is taken from HIS OWN ROW, never from the client, so a voucher
-- cannot name one man while pointing at another.
SELECT probe.succeeds('spend', 'a member may be the payee', $sql$
  SELECT public.register_disbursement(
    5, 'إعانة اجتماعية', 'اسم سيُتجاهل', 'نقداً', 1)
$sql$);
SELECT probe.eq('spend', '...and the register overrides whatever was typed',
  $sql$ SELECT (d.payee_name
              = (SELECT full_name FROM public.adeels WHERE id = 1))::text
          FROM public.disbursements d WHERE d.payee_adeel_id = 1 $sql$, 'true');
SELECT probe.raises('spend', 'an unknown member is refused', $sql$
  SELECT public.register_disbursement(5, 'إعانة اجتماعية', 'x', 'نقداً', 999999)
$sql$, 'RUL17');

-- ⚠ THE ONE THAT MATTERS MOST. Aid paid to a member is NOT a payment against
-- his subscription: it never touches receivables, payments or his wallet. If it
-- ever did, the association's charity would be cancelling its own dues.
SELECT probe.eq('spend', 'aid to a member does NOT reduce what he owes',
  $sql$ SELECT count(*)::text FROM public.payments
         WHERE adeel_id = 1 AND amount = 5 $sql$, '0');

-- ═════ Rule 9, outgoing ══════════════════════════════════════════════════════
SELECT probe.raises('spend', 'cancelling without a reason is refused', $sql$
  SELECT public.cancel_disbursement(
    (SELECT min(id) FROM public.disbursements), '  ')
$sql$, 'RUL17');
SELECT probe.succeeds('spend', 'a voucher is cancelled with a reason', $sql$
  SELECT public.cancel_disbursement(
    (SELECT min(id) FROM public.disbursements), 'خطأ إدخال')
$sql$);
SELECT probe.eq('spend', '...the money returns to the treasury',
  $sql$ SELECT ("total"::numeric - "balance"::numeric)::text
          FROM public.v_cash_summary $sql$, '5.00');
SELECT probe.eq('spend', '...the voucher STAYS, struck through',
  $sql$ SELECT status::text FROM public.disbursements
         WHERE id = (SELECT min(id) FROM public.disbursements) $sql$, 'ملغي');
SELECT probe.eq('spend', '...and its heading no longer counts it',
  $sql$ SELECT "total" FROM public.v_expense_by_category
         WHERE "category" = 'مصاريف إدارية' $sql$, '0.00');
SELECT probe.raises('spend', 'cancelling it twice is refused', $sql$
  SELECT public.cancel_disbursement(
    (SELECT min(id) FROM public.disbursements), 'مرة أخرى')
$sql$, 'RUL17');

-- A voucher can never be DELETED, only reversed. One that could be removed is a
-- treasury that can be quietly rebalanced.
SELECT probe.raises('spend', 'a voucher cannot be deleted', $sql$
  DELETE FROM public.disbursements
   WHERE id = (SELECT min(id) FROM public.disbursements)
$sql$, 'RUL09');

-- ═════ THE RULE FROM THE OTHER SIDE ══════════════════════════════════════════
-- register_disbursement refuses to pay out money the association does not hold.
-- On its own that is half a guarantee, because the money can be taken away
-- AFTER it is spent: cancelling the receipt that funded a voucher used to drive
-- the fund straight through zero, silently, and every عديل then read the
-- negative figure as رصيد الجمعية. cancel_payment now refuses instead and names
-- the voucher to reverse first.
--
-- Built here rather than in 50_money because it is only reachable once money can
-- LEAVE — before disbursement existed there was nothing for a cancellation to
-- overdraw.
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');  -- treasurer
SELECT probe.succeeds('spend', 'a receipt is collected to fund a voucher', $sql$
  SELECT public.register_payment(1, 30.00, 'نقداً')
$sql$);

SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.succeeds('spend', '...and the whole fund is spent', $sql$
  SELECT public.register_disbursement(
    (SELECT "balance"::numeric FROM public.v_cash_summary),
    'إيجار وخدمات', 'مالك المقر', 'نقداً')
$sql$);
SELECT probe.eq('spend', '...leaving the treasury at exactly zero',
  $sql$ SELECT "balance" FROM public.v_cash_summary $sql$, '0.00');

SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.raises('spend',
  'cancelling the receipt whose money is SPENT is refused', $sql$
  SELECT public.cancel_payment(
    (SELECT id FROM public.payments WHERE amount = 30.00 AND status <> 'ملغي'
      ORDER BY id DESC LIMIT 1), 'محاولة سحب المال المصروف')
$sql$, 'RUL09');
SELECT probe.eq('spend', '...and the fund is still standing at zero, not below',
  $sql$ SELECT ("balance"::numeric >= 0)::text
          FROM public.v_cash_summary $sql$, 'true');

-- Reverse the voucher and the SAME cancellation goes through. This is the half
-- that proves the guard is a rule and not a wall: the money is put back before
-- it is taken back, which is the order the books require.
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.succeeds('spend', 'reversing the voucher releases the money', $sql$
  SELECT public.cancel_disbursement(
    (SELECT max(id) FROM public.disbursements), 'إلغاء لاختبار الترتيب')
$sql$);
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.succeeds('spend', '...and NOW the receipt cancels cleanly', $sql$
  SELECT public.cancel_payment(
    (SELECT id FROM public.payments WHERE amount = 30.00 AND status <> 'ملغي'
      ORDER BY id DESC LIMIT 1), 'إلغاء بعد رد السند')
$sql$);
SELECT probe.eq('spend', '...with the fund back where it started',
  $sql$ SELECT ("balance"::numeric >= 0)::text
          FROM public.v_cash_summary $sql$, 'true');

-- ═════ What a member is told ═════════════════════════════════════════════════
-- Aggregates only. He sees the TOTAL spent — without it his "transparency"
-- would overstate the fund by every voucher — and never who received it.
SELECT probe.eq('spend', 'the member-facing figures include what went out',
  $sql$ SELECT (public.api_association_finance() ? 'disbursed')::text $sql$,
  'true');
SELECT probe.eq('spend', '...and its balance is collections minus spending',
  $sql$ SELECT ((public.api_association_finance() ->> 'balance')::numeric
              = (public.api_association_finance() ->> 'collected')::numeric
              - (public.api_association_finance() ->> 'disbursed')::numeric)::text
  $sql$, 'true');
-- ═════ And what he is NOT told ═══════════════════════════════════════════════
-- This check needs two things the rest of the file does not, and it silently had
-- NEITHER — so it counted every voucher in the table and reported that an عديل
-- sees them all, which is exactly what it was written to forbid:
--
--   1. `SET ROLE authenticated`. Everything above is either an RPC or an
--      owner-side read, and an RPC gates itself on the JWT claim that
--      probe.become() sets — so this file never needed a database role and never
--      took one. RLS is the one thing that does not work that way: the table
--      OWNER bypasses every policy. The check was reading straight past
--      read_disbursements. (The file must stay owner-side elsewhere: the rule-9
--      check DELETEs, and `authenticated` holds no DELETE grant, so as a client
--      it would be refused by 42501 before ever reaching the trigger it exists
--      to prove.)
--
--   2. A LIVE عديل. 45_adeel_portal creates b1 and DELETES it at its bottom, so
--      becoming b1 here impersonates a user with no profile at all — a stranger,
--      not a member. That is the right answer for the wrong reason, and it would
--      go on being right if `adeel_id` stopped excluding anybody.
--
-- So this group binds its own, and proves he is a WORKING portal user BEFORE
-- proving what he cannot see. Without that order an empty count means nothing —
-- a broken account sees nothing either.
SELECT probe.become(NULL);
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000b7', 'spend@fam.test',
   '{"full_name":"عديل الصرف"}');
UPDATE public.profiles
   SET adeel_id = 1, status = 'approved',
       device_id = 'dev-00000000-0000-0000-0000-0000000000b7'
 WHERE id = '00000000-0000-0000-0000-0000000000b7';

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000b7');

SELECT probe.eq('spend', 'the portal user is live — scoped to his own عديل',
  $sql$ SELECT (public.my_adeel_id() = 1)::text $sql$, 'true');
SELECT probe.eq('spend', '...and holds no staff role, which is what excludes him',
  $sql$ SELECT (public.my_role() IS NULL)::text $sql$, 'true');
SELECT probe.eq('spend', 'an عديل sees NO voucher rows at all',
  $sql$ SELECT count(*)::text FROM public.disbursements $sql$, '0');
-- He IS adeel 1, and EXP-000002 was paid to adeel 1 above. A voucher says that a
-- named man received إعانة اجتماعية; that it is his own name does not make the
-- row his to read, and the association never asked for it to be.
SELECT probe.eq('spend', '...not even the one made out to him',
  $sql$ SELECT count(*)::text FROM public.disbursements
         WHERE payee_adeel_id = 1 $sql$, '0');

RESET ROLE;
-- Put the fixture back, exactly as 45_adeel_portal does: deleting the auth.users
-- row cascades to the profile and takes the binding with it, so 70_purge still
-- meets the register it expects.
SELECT probe.become(NULL);
DELETE FROM auth.users WHERE email = 'spend@fam.test';
