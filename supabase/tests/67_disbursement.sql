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
  SELECT public.register_disbursement(10, 'جماعي', 'نقداً', NULL, 'عزاء')
$sql$, 'RUL00');
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.raises('spend', 'nor may the finance manager', $sql$
  SELECT public.register_disbursement(10, 'جماعي', 'نقداً', NULL, 'عزاء')
$sql$, 'RUL00');

SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.raises('spend', 'a zero disbursement is refused', $sql$
  SELECT public.register_disbursement(0, 'جماعي', 'نقداً', NULL, 'عزاء')
$sql$, 'RUL17');
SELECT probe.raises('spend', 'and a negative one', $sql$
  SELECT public.register_disbursement(-5, 'جماعي', 'نقداً', NULL, 'عزاء')
$sql$, 'RUL17');

-- ═════ THE TWO SHAPES ════════════════════════════════════════════════════════
-- A voucher is money to a NAMED man, or money on an OCCASION for everybody, and
-- BOTH carry a وجه — who was paid and what for are different questions.
--
-- What separates them is the payee, and one heading each:
--   مولود      is a family's, so it is لمشترك and never جماعي
--   فطور رمضان is one table for everybody, so it is جماعي and never one man's
SELECT probe.raises('spend', 'a voucher with no وجه is refused', $sql$
  SELECT public.register_disbursement(10, 'جماعي', 'نقداً')
$sql$, 'RUL17');
SELECT probe.raises('spend', 'صرف لمشترك without a member is refused', $sql$
  SELECT public.register_disbursement(10, 'لمشترك', 'نقداً', NULL, 'عزاء')
$sql$, 'RUL17');
SELECT probe.raises('spend', 'صرف جماعي may not name a member', $sql$
  SELECT public.register_disbursement(10, 'جماعي', 'نقداً', 1, 'عزاء')
$sql$, 'RUL17');
SELECT probe.raises('spend', '«فطور رمضان» cannot be paid to one man', $sql$
  SELECT public.register_disbursement(10, 'لمشترك', 'نقداً', 1, 'فطور رمضان')
$sql$, 'RUL17');
SELECT probe.raises('spend', 'and «مولود» cannot be collective', $sql$
  SELECT public.register_disbursement(10, 'جماعي', 'نقداً', NULL, 'مولود')
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
          'جماعي', 'نقداً', NULL, 'حالات طارئة') $sql$, 'RUL17');
SELECT probe.eq('spend', '...and the refusal left no voucher behind',
  $sql$ SELECT count(*)::text FROM public.disbursements $sql$, '0');

-- ═════ صرف جماعي — an occasion, and nobody's name on it ══════════════════════
SELECT probe.succeeds('spend', 'spending within the balance is accepted', $sql$
  SELECT public.register_disbursement(
    10, 'جماعي', 'نقداً', NULL, 'فطور رمضان',
    'INV-9', NULL, NULL, NULL, 'أمين الصندوق', 'إفطار الجمعية')
$sql$);
SELECT probe.eq('spend', 'the voucher is numbered EXP-000001',
  $sql$ SELECT voucher_no FROM public.disbursements ORDER BY id LIMIT 1 $sql$,
  'EXP-000001');
-- The association's own decision: nobody RECEIVES فطور رمضان the way a member
-- receives aid, so the column is empty rather than carrying an invented name.
SELECT probe.eq('spend', 'and it records no payee at all',
  $sql$ SELECT (payee_name IS NULL AND payee_adeel_id IS NULL)::text
          FROM public.disbursements WHERE voucher_no = 'EXP-000001' $sql$,
  'true');
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
         WHERE "category" = 'فطور رمضان' $sql$, '10.00');
-- Every heading appears, spent on or not: a report that omits a zero reads as
-- one that forgot it.
SELECT probe.eq('spend', 'all six أوجه are listed, including the empty',
  $sql$ SELECT count(*)::text FROM public.v_expense_by_category $sql$, '6');

-- ═════ صرف لمشترك — a named man, AND a وجه ═══════════════════════════════════
-- The name is taken from HIS OWN ROW, never from the client, so a voucher
-- cannot name one man while pointing at another.
SELECT probe.succeeds('spend', 'a member may be the payee', $sql$
  SELECT public.register_disbursement(5, 'لمشترك', 'نقداً', 1, 'مولود')
$sql$);
SELECT probe.eq('spend', '...and his name is snapshotted off the register',
  $sql$ SELECT (d.payee_name
              = (SELECT full_name FROM public.adeels WHERE id = 1))::text
          FROM public.disbursements d WHERE d.payee_adeel_id = 1 $sql$, 'true');
SELECT probe.raises('spend', 'an unknown member is refused', $sql$
  SELECT public.register_disbursement(5, 'لمشترك', 'نقداً', 999999, 'عزاء')
$sql$, 'RUL17');

-- ⚠ WHO was paid and WHAT FOR are different questions, and the register of
-- names cannot answer the second. This is the one that would be lost if a
-- member voucher carried no وجه.
SELECT probe.eq('spend', 'aid is filed under its own وجه, not merely a name',
  $sql$ SELECT "total" FROM public.v_expense_by_category
         WHERE "category" = 'مولود' $sql$, '5.00');
-- Every voucher of BOTH kinds carries one, so this single grouping covers the
-- whole outflow — nothing is left out and nothing is counted twice.
SELECT probe.eq('spend', '...so the report totals what the treasury paid out',
  $sql$ SELECT (sum("total"::numeric)::numeric(12,2)::text
              = (SELECT "disbursed" FROM public.v_cash_summary))::text
          FROM public.v_expense_by_category $sql$, 'true');

-- ═════ AID IS NOT A CREDIT AGAINST HIS SUBSCRIPTION ══════════════════════════
-- The association is خيرية. What it gives a man is not deducted from what he
-- owes it: he was just paid 5.00 for a birth, and he still owes every dinar of
-- every month he has not paid. Getting this wrong in either direction is the
-- expensive mistake — the association's charity cancelling its own dues, or a
-- man who received help being told he is in credit.
--
-- Asserted as an EQUALITY against the two tables the statement is allowed to
-- read, not as "the number did not move". The weaker form passes just as well
-- when the statement is broken in some other way, and it would not notice a
-- voucher that netted off two other figures on its way through.
SELECT probe.eq('spend', 'his statement is built from dues and receipts ALONE',
  $sql$ SELECT ((public.api_adeel_statement(1) ->> 'closingBalance')::numeric
              = (SELECT coalesce(sum(r.total), 0) FROM public.receivables r
                  WHERE r.adeel_id = 1 AND r.status <> 'ملغي')
              - (SELECT coalesce(sum(p.amount), 0) FROM public.payments p
                  WHERE p.adeel_id = 1 AND p.status <> 'ملغي'))::text $sql$,
  'true');
SELECT probe.eq('spend', '...and no voucher appears anywhere in it',
  $sql$ SELECT count(*)::text
          FROM jsonb_array_elements(
                 public.api_adeel_statement(1) -> 'movements') m
         WHERE m ->> 'reference' LIKE 'EXP-%' $sql$, '0');

-- ═════ SO IT IS ANSWERED SOMEWHERE ELSE ══════════════════════════════════════
-- «كم صُرف لفلان، وفي أي مناسبات» — the question the statement must never
-- answer, asked of the one function that exists to answer it.
SELECT probe.eq('spend', 'what he RECEIVED is answered by its own call',
  $sql$ SELECT public.api_adeel_aid(1) ->> 'total' $sql$, '5.00');
SELECT probe.eq('spend', '...and it names the occasion, not just the amount',
  $sql$ SELECT c ->> 'category'
          FROM jsonb_array_elements(public.api_adeel_aid(1) -> 'byCategory') c
         LIMIT 1 $sql$, 'مولود');
SELECT probe.eq('spend', '...with the voucher itself listed beneath it',
  $sql$ SELECT jsonb_array_length(public.api_adeel_aid(1) -> 'vouchers')::text
  $sql$, '1');
-- EXP-000001 was جماعي — spent on everybody, attributed to nobody. It must not
-- surface under any individual, or every collective iftar would be re-reported
-- as aid to each man in the register.
SELECT probe.eq('spend', 'a COLLECTIVE voucher is nobody''s aid',
  $sql$ SELECT (public.api_adeel_aid(1) -> 'vouchers' -> 0 ->> 'voucherNo')
  $sql$, 'EXP-000002');
-- A man who has been given nothing reads zero, not NULL and not an error: the
-- screen has one shape whether or not he has ever received anything.
SELECT probe.eq('spend', 'a member who received nothing reads a clean zero',
  $sql$ SELECT public.api_adeel_aid(2) ->> 'total' $sql$, '0.00');

-- ═════ THE RUNNING TOTAL — «صُرف له 100 ثم 500، فيصبح 600» ═══════════════════
-- The association asked for the aid page to read as a LEDGER: each voucher on
-- its own line with the total so far beside it. That column is a window
-- function in api_adeel_aid, not arithmetic in Dart — money crosses the wire as
-- text precisely so nothing on the client adds it, and a running total the app
-- accumulated itself would be the one figure on the screen computed in binary
-- floating point.
SELECT probe.succeeds('spend', 'a second voucher to the same man', $sql$
  SELECT public.register_disbursement(3, 'لمشترك', 'نقداً', 1, 'عزاء')
$sql$);
-- OLDEST FIRST, which is what makes the column mean anything: read newest-first
-- the total would accumulate backwards and the last line would show the FIRST
-- voucher's amount as though it were the sum of everything.
SELECT probe.eq('spend', 'the ledger opens on the oldest voucher',
  $sql$ SELECT public.api_adeel_aid(1) -> 'vouchers' -> 0 ->> 'runningTotal'
  $sql$, '5.00');
SELECT probe.eq('spend', '...and the next line carries the total so far',
  $sql$ SELECT public.api_adeel_aid(1) -> 'vouchers' -> 1 ->> 'runningTotal'
  $sql$, '8.00');

-- ⚠ A REVERSED VOUCHER IS LISTED AND MOVES NOTHING. Rule 9 keeps it on the page;
-- the FILTER inside the window keeps it out of the arithmetic. Dropping it with
-- a WHERE would have removed the line entirely, and leaving it in the sum would
-- have credited him with money that was taken back.
SELECT probe.succeeds('spend', 'the second voucher is reversed', $sql$
  SELECT public.cancel_disbursement(
    (SELECT max(id) FROM public.disbursements WHERE payee_adeel_id = 1),
    'خطأ إدخال')
$sql$);
SELECT probe.eq('spend', 'a reversed line STAYS in the ledger',
  $sql$ SELECT public.api_adeel_aid(1) -> 'vouchers' -> 1 ->> 'status' $sql$,
  'ملغي');
SELECT probe.eq('spend', '...and leaves the running total exactly where it was',
  $sql$ SELECT public.api_adeel_aid(1) -> 'vouchers' -> 1 ->> 'runningTotal'
  $sql$, '5.00');

-- ═════ The CONSTRAINT underneath, proved on its own ══════════════════════════
-- The four refusals above are the RPC's, and they exist to give an admin a
-- sentence he can act on. This is ck_disb_shape itself: the guarantee has to
-- hold for anything that reaches the TABLE, not only for what came through the
-- function — a future RPC, a patch, an import.
--
-- Placed after the successful vouchers deliberately. A failed INSERT still
-- consumes an identity value, so running these earlier renumbered EXP-000001
-- out of existence and broke two checks that had nothing to do with shapes.
SELECT probe.raises('spend', 'the TABLE itself refuses a MIXED row', $sql$
  INSERT INTO public.disbursements (amount, kind, category, payee_adeel_id,
                                    payee_name, method)
  VALUES (1, 'جماعي', 'عزاء', 1, 'فلان', 'نقداً')
$sql$, '23514');
SELECT probe.raises('spend', '...one with no payee where a payee is required',
  $sql$ INSERT INTO public.disbursements (amount, kind, category, method)
        VALUES (1, 'لمشترك', 'عزاء', 'نقداً') $sql$, '23514');
-- The وجه pairing too, not only the payee. A caller that skips the RPC must not
-- be able to file a birth as a collective expense or an iftar to one man.
SELECT probe.raises('spend', '...and «مولود» stored as جماعي', $sql$
  INSERT INTO public.disbursements (amount, kind, category, method)
  VALUES (1, 'جماعي', 'مولود', 'نقداً')
$sql$, '23514');
SELECT probe.raises('spend', '...and «فطور رمضان» stored against one man', $sql$
  INSERT INTO public.disbursements (amount, kind, category, payee_adeel_id,
                                    payee_name, method)
  VALUES (1, 'لمشترك', 'فطور رمضان', 1, 'فلان', 'نقداً')
$sql$, '23514');

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
         WHERE "category" = 'فطور رمضان' $sql$, '0.00');
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
    'جماعي', 'نقداً', NULL, 'حالات طارئة')
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
-- ── HIS OWN AID, AND NOBODY ELSE'S ──────────────────────────────────────────
-- The association decided a member may see what it has given HIM: how much,
-- and on which occasions. read_own_disbursements is scoped on payee_adeel_id,
-- so the widening stops exactly there.
--
-- The positive check comes FIRST and on purpose. Every negative check below
-- passes just as well against a policy that denies everything, and a portal
-- showing an empty page is indistinguishable from one correctly hiding other
-- people's rows. Prove he sees SOMETHING before proving what he does not.
SELECT probe.note('spend', 'an عديل sees the vouchers made out to him',
  (SELECT count(*) FROM public.disbursements) > 0);
SELECT probe.eq('spend', '...and NOTHING that is not his',
  $sql$ SELECT count(*)::text FROM public.disbursements
         WHERE payee_adeel_id IS DISTINCT FROM 1 $sql$, '0');
-- EXP-000001 was جماعي — spent on everybody, attributed to nobody, and still on
-- the table. `payee_adeel_id = my_adeel_id()` is NULL for it, never true, which
-- is what keeps a collective voucher out of every individual's page.
SELECT probe.eq('spend', '...not the collective voucher, which belongs to all',
  $sql$ SELECT count(*)::text FROM public.disbursements
         WHERE voucher_no = 'EXP-000001' $sql$, '0');

-- The same rule read through the function the screen actually calls. It is
-- SECURITY INVOKER, so nothing here is a second implementation of the policy —
-- which is the point: passing another man's id must return an empty answer, not
-- a refusal that would confirm he exists.
SELECT probe.note('spend', 'his aid page answers for him',
  (public.api_adeel_aid(1) ->> 'count')::int > 0);
SELECT probe.eq('spend', '...and tells him nothing about another member',
  $sql$ SELECT (public.api_adeel_aid(2) ->> 'total') $sql$, '0.00');
SELECT probe.eq('spend', '...not even that member''s name',
  $sql$ SELECT (public.api_adeel_aid(2) ->> 'adeelName' IS NULL)::text $sql$,
  'true');

-- ⚠ AND HIS STATEMENT IS STILL UNTOUCHED BY ANY OF IT. Now checked as HIM
-- rather than as an admin: the policy that lets him read his own vouchers must
-- not have leaked one into the ledger that says what he owes.
SELECT probe.eq('spend', 'seeing his aid did NOT put it in his statement',
  $sql$ SELECT count(*)::text
          FROM jsonb_array_elements(
                 public.api_adeel_statement(1) -> 'movements') m
         WHERE m ->> 'reference' LIKE 'EXP-%' $sql$, '0');

RESET ROLE;
-- Put the fixture back, exactly as 45_adeel_portal does: deleting the auth.users
-- row cascades to the profile and takes the binding with it, so 70_purge still
-- meets the register it expects.
SELECT probe.become(NULL);
DELETE FROM auth.users WHERE email = 'spend@fam.test';
