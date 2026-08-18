-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-18 (c).  عهد المشتركين: مال في الصندوق
--  ليس مال الجمعية.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  WHAT THIS DOES
--    A member may pay a year ahead. The cash arrives, rule 8 records it in
--    cash_movements, and the treasury counts it — correctly, because it really
--    is there. What it is NOT is EARNED: until the month it covers is billed,
--    that sum is a liability owed back to him.
--
--    Until now it sat inside رصيد الجمعية and was spendable. The consequence,
--    reproduced exactly on a copy of this schema before the fix was written:
--
--        عهدة 60 taken in advance → one month closes, 20 earned
--        → رصيد الجمعية still reads 60
--        → a voucher for 60 is ACCEPTED
--        → the member's remaining 40 is gone, and no screen ever said so.
--
--    After this patch:
--
--      • v_cash_summary gains "heldForMembers" and its "balance" becomes
--        collected − disbursed − held. The figure under رصيد الجمعية is what
--        may actually be SPENT.
--      • register_disbursement refuses anything above that same number, and
--        its message names both figures — «في الصندوق 60.00 منها 40.00 عهد
--        للمشتركين» — because an admin who counted the notes is holding more
--        than the app will let him spend and would otherwise conclude the app
--        is wrong.
--      • cancel_payment subtracts عهد on its side too. The two guards are one
--        rule read from opposite ends, and a gap between them is exactly where
--        the fund would go negative with nothing having refused anything.
--      • api_association_finance subtracts it as well, so a member is never
--        shown his own deposit — or anyone else's — as association money.
--
--  ⚠ NO MONEY MOVES AND NO ROW IS TOUCHED. This patch adds one function,
--    replaces four bodies and one view. Every figure it changes was already
--    derivable from rows that exist: عهد is Σ payments − Σ allocations, which
--    is the same quantity v_adeels has published as "credit" all along. The
--    only thing that changes is which side of the line it is counted on.
--
--  ⚠ WHAT THE ASSOCIATION WILL SEE THE MOMENT THIS LANDS. If any member is
--    holding credit today, رصيد الجمعية DROPS by that total — immediately, with
--    no entry to explain it. That is the correction, not a fault: the old
--    figure counted money the association owes back. The new «عهد المشتركين»
--    line on the treasury screen is where the difference went, and the two
--    still add up to what is in the box.
--
--  ⚠ AND A DISBURSEMENT THAT WOULD HAVE BEEN ACCEPTED YESTERDAY MAY BE REFUSED
--    TODAY, for the same reason. The refusal names the arithmetic.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes. Safe to run twice.
--    Requires PATCH_20260817_device_lock.sql (نظام الصرف) — check with
--    supabase/WHICH_STATE.sql.
-- ============================================================================

BEGIN;

-- == 0. The prerequisites, stated rather than assumed =======================
DO $prereq$
BEGIN
  IF to_regclass('public.disbursements') IS NULL THEN
    RAISE EXCEPTION
      'PATCH_20260817_device_lock.sql has not been applied here: public.disbursements does not exist. Apply that first — see supabase/WHICH_STATE.sql.';
  END IF;
  -- CREATE OR REPLACE VIEW can only APPEND columns, so v_cash_summary must
  -- already carry the disbursement pair. Without this check the failure would
  -- arrive as a bare 42P16 about column counts.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'v_cash_summary'
       AND column_name = 'disbursed')
  THEN
    RAISE EXCEPTION
      'v_cash_summary here has no "disbursed" column, so this project predates نظام الصرف. Apply PATCH_20260817_device_lock.sql first — see supabase/WHICH_STATE.sql.';
  END IF;
END $prereq$;

-- == 1. عهد المشتركين, computed in ONE place ================================
-- ═════════════════════════════════════════════════════════════════════════════
-- عهد المشتركين — money the association HOLDS but has not EARNED.
--
-- A man may pay a year ahead. The cash is in the box, and rule 8 puts it in
-- cash_movements the moment it arrives, so the treasury's `total` counts it —
-- correctly, because it really did arrive. What it is NOT is the association's
-- money: until a month is billed and settle_from_credit allocates against it,
-- that sum is a liability owed back to him.
--
-- Left in the spendable balance it produced this, which is not a rounding
-- concern but the association spending a member's deposit: he pays 60 in
-- advance, one month closes so 20 is earned, and رصيد الجمعية still reads 60 —
-- so a voucher for 60 is accepted and his remaining 40 is gone. Nothing on any
-- screen said so, because nothing anywhere distinguished the two kinds of money.
--
-- ── One function rather than four copies of the SUM ──────────────────────────
-- The quantity is read in four places that must agree exactly: the treasury
-- view, the member portal's aggregates, and the two guards that decide whether
-- money may leave (register_disbursement) or be un-collected (cancel_payment).
-- Four hand-written copies of a money expression is four chances to fix three.
--
-- SECURITY INVOKER on purpose. Inside v_cash_summary — itself invoker — it sums
-- exactly what the caller may read, which is the same rule `total` beside it
-- already follows. Inside the SECURITY DEFINER guards it runs with their
-- privileges and sees everything, which is what a treasury check must do.
--
-- greatest(…, 0) is per PAYMENT and is a floor, not a correction: allocations
-- can never exceed their own payment (register_payment refuses a negative
-- remainder, settle_from_credit takes the least of the two). Should that ever
-- break, a negative would UNDERSTATE what is held and hand the difference to
-- the spendable balance — so the floor errs toward refusing a disbursement
-- rather than toward allowing one. v_adeels."credit" floors the same quantity
-- per MEMBER; with the invariant intact the two are identical.
--
-- p_exclude_payment exists for cancel_payment, which has to ask what will be
-- held AFTER the receipt it is about to void disappears.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.members_held(p_exclude_payment bigint DEFAULT NULL)
RETURNS numeric
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT coalesce(sum(greatest(p.amount - coalesce(al.allocated, 0), 0)), 0)
    FROM public.payments p
    LEFT JOIN LATERAL (
      SELECT sum(a.amount) AS allocated
        FROM public.payment_allocations a
       WHERE a.payment_id = p.id
    ) al ON true
   WHERE p.status <> 'ملغي'
     AND (p_exclude_payment IS NULL OR p.id <> p_exclude_payment);
$$;

-- == 2. رصيد الجمعية, minus what is held ====================================
-- CREATE OR REPLACE rather than DROP: the existing columns keep their names,
-- types and order, and "heldForMembers" is APPENDED — which is the only
-- change Postgres permits on a view in place, and the reason nothing that
-- reads this view has to be dropped with it.
CREATE OR REPLACE VIEW public.v_cash_summary WITH (security_invoker = on) AS
SELECT
  coalesce(sum(amount), 0)::numeric(12,2)::text AS "total",
  coalesce(sum(amount) FILTER (WHERE method = 'نقداً'), 0)::numeric(12,2)::text        AS "cash",
  coalesce(sum(amount) FILTER (WHERE method = 'تحويل مصرفي'), 0)::numeric(12,2)::text AS "transfer",
  coalesce(sum(amount) FILTER (WHERE occurred_at::date = current_date), 0)::numeric(12,2)::text
    AS "today",
  coalesce(sum(amount) FILTER (WHERE date_trunc('month', occurred_at)
                                  = date_trunc('month', current_date)), 0)::numeric(12,2)::text
    AS "month",
  coalesce(sum(amount) FILTER (WHERE date_trunc('year', occurred_at)
                                  = date_trunc('year', current_date)), 0)::numeric(12,2)::text
    AS "year",
  -- ── What is still OWED, on the treasury screen ────────────────────────────
  -- The odd one out: every other figure here aggregates cash_movements, and
  -- this one reaches into receivables. It is here because the question a
  -- treasurer asks of this screen is "where does the association stand", and
  -- half that answer is money that has not arrived.
  --
  -- It replaced "تحصيل السنة", which on an association in its first year was
  -- the same number as "إجمالي المحصل" — two tiles, one figure, and no way to
  -- tell they were not disagreeing with each other.
  --
  -- Cancelled receivables excluded, matching every other debt figure in the
  -- schema. APPENDED at the end because CREATE OR REPLACE VIEW allows nothing
  -- else; anything added later goes below it.
  coalesce((SELECT sum(r.balance) FROM public.receivables r
             WHERE r.status <> 'ملغي'), 0)::numeric(12,2)::text
    AS "outstanding",
  -- ── Money OUT ─────────────────────────────────────────────────────────────
  -- Two tables rather than one signed ledger: see the note on the disbursements
  -- table. Nothing about the collection path had to change to make this work.
  coalesce((SELECT sum(x.amount) FROM public.disbursements x
             WHERE x.status <> 'ملغي'), 0)::numeric(12,2)::text
    AS "disbursed",
  -- ── رصيد الجمعية — and the third term that was missing ────────────────────
  -- `total` above is everything ever COLLECTED and keeps that meaning. It was
  -- also what the screen called "رصيد الجمعية", which was true only while money
  -- could not leave — the moment disbursement exists, collected-to-date and
  -- held-today are different numbers and calling the first one "the balance"
  -- makes the screen lie by exactly what has been spent.
  --
  -- ⚠ AND MINUS عهد المشتركين. A prepayment is real cash and rule 8 puts it
  --   here, so `total` counts it and should. What it is not is the
  --   association's: until the month it covers is billed, it is owed back. The
  --   figure under this heading is what may actually be SPENT, which is the
  --   only question anyone asks it — and register_disbursement enforces exactly
  --   this arithmetic, so the screen and the refusal cannot disagree.
  --
  --   The physical contents of the box is `total − disbursed`, and the two
  --   figures beside this one give it: subtract "المصروف" from "إجمالي المحصل".
  (coalesce(sum(amount), 0)
   - coalesce((SELECT sum(x.amount) FROM public.disbursements x
                WHERE x.status <> 'ملغي'), 0)
   - public.members_held())::numeric(12,2)::text
    AS "balance",
  -- What is held for members and not owned by the association. Appended rather
  -- than inserted because CREATE OR REPLACE VIEW allows nothing else; anything
  -- added later goes below it.
  public.members_held()::numeric(12,2)::text
    AS "heldForMembers"
FROM public.cash_movements
WHERE status <> 'ملغي';

-- == 3. Rule 17: the association cannot spend what it holds for a member ====
CREATE OR REPLACE FUNCTION public.register_disbursement(
  p_amount            numeric,
  p_kind              disbursement_kind,
  p_method            pay_method,
  p_payee_adeel_id    bigint DEFAULT NULL,
  p_category          expense_category DEFAULT NULL,
  p_reference         text   DEFAULT NULL,
  p_bank_name         text   DEFAULT NULL,
  p_bank_account_name text   DEFAULT NULL,
  p_bank_account_no   text   DEFAULT NULL,
  p_handed_by         text   DEFAULT NULL,
  p_note              text   DEFAULT NULL,
  p_spent_at          date   DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  -- Unconstrained numeric for the same reason register_payment's is: the
  -- individual amounts are bounded by their column, their SUM is not, and an
  -- overflowing accumulator would report 22003 instead of a rule violation.
  v_collected numeric;
  v_spent     numeric;
  v_available numeric;
  v_held      numeric;
  v_payee     text;
  v_bank      text;
  v_acct_no   text;
  v_acct_name text;
  v_reference text;
  v_id        bigint;
  v_voucher   text;
BEGIN
  PERFORM public.require_role('admin');

  p_amount := round(p_amount, 2);
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'قيمة الصرف يجب أن تكون أكبر من صفر' USING ERRCODE = 'RUL17';
  END IF;

  -- The treasury mutex. See the note above.
  PERFORM 1 FROM public.association_settings WHERE id = 1 FOR UPDATE;

  SELECT coalesce(sum(amount), 0) INTO v_collected
    FROM public.cash_movements WHERE status <> 'ملغي';
  SELECT coalesce(sum(amount), 0) INTO v_spent
    FROM public.disbursements  WHERE status <> 'ملغي';
  -- ── AND WHAT IS HELD FOR MEMBERS IS NOT THE ASSOCIATION'S TO SPEND ─────────
  -- The third term is the whole of عهد: a prepayment is in cash_movements, so
  -- v_collected counts it, and until the month it covers is billed it is money
  -- owed back. Spending it is spending a member's deposit — see members_held().
  SELECT public.members_held() INTO v_held;
  v_available := v_collected - v_spent - v_held;

  -- ── The message has to name the عهد, or the refusal is unreadable ──────────
  -- The box physically holds v_collected − v_spent. An admin who counted it and
  -- is then refused a smaller figure will conclude the app is wrong, and he is
  -- the one person who can see the cash to check. So when any of it is عهد, the
  -- refusal says so and gives both numbers.
  IF p_amount > v_available THEN
    IF v_held > 0 THEN
      RAISE EXCEPTION
        'الصرف % يتجاوز القابل للصرف % — في الصندوق % منها % عهد للمشتركين',
        p_amount::text, v_available::text,
        (v_collected - v_spent)::text, v_held::text
        USING ERRCODE = 'RUL17';
    END IF;
    RAISE EXCEPTION 'الصرف % يتجاوز رصيد الصندوق %',
      p_amount::text, v_available::text USING ERRCODE = 'RUL17';
  END IF;
  -- ── The two shapes, refused here as well as CHECKed on the row ─────────────
  -- ck_disb_shape is the guarantee; this is the message. A constraint violation
  -- arrives as 23514 with a constraint name, which is true and unreadable — the
  -- admin needs to be told he picked a kind and then filled in the other one.
  -- Both kinds carry a وجه: WHO was paid and WHAT FOR are different questions,
  -- and a register of names cannot answer the second.
  IF p_category IS NULL THEN
    RAISE EXCEPTION 'اختر وجه الصرف' USING ERRCODE = 'RUL17';
  END IF;

  IF p_kind = 'لمشترك' THEN
    IF p_payee_adeel_id IS NULL THEN
      RAISE EXCEPTION 'اختر المشترك المستفيد' USING ERRCODE = 'RUL17';
    END IF;
    IF p_category = 'فطور رمضان' THEN
      RAISE EXCEPTION '«فطور رمضان» وجه صرف جماعي — لا يُصرف لمشترك بعينه'
        USING ERRCODE = 'RUL17';
    END IF;
    -- The name comes from HIS ROW, never from the client, so a voucher cannot
    -- name one man while pointing at another.
    SELECT full_name INTO v_payee FROM public.adeels WHERE id = p_payee_adeel_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'المستفيد المختار ليس في سجل العدايل' USING ERRCODE = 'RUL17';
    END IF;
  ELSE
    IF p_payee_adeel_id IS NOT NULL THEN
      RAISE EXCEPTION 'الصرف الجماعي لا يُنسب إلى مشترك' USING ERRCODE = 'RUL17';
    END IF;
    IF p_category = 'مولود' THEN
      RAISE EXCEPTION '«مولود» وجه صرف لمشترك — لا يكون جماعياً'
        USING ERRCODE = 'RUL17';
    END IF;
    -- No payee at all, by the association's own decision: nobody receives
    -- فطور رمضان the way a member receives aid, and a name invented to fill the
    -- column would be a fact the books assert without knowing it.
    v_payee := NULL;
  END IF;

  -- Kept only for a transfer: a cash payout has no receiving account, and
  -- letting the columns carry anything for it would put bank details beside
  -- نقداً on the voucher.
  --
  -- `reference` goes with them, and that is the difference from a COLLECTION.
  -- There it is a receipt-book number a treasurer writes for cash as readily as
  -- for a transfer; here the field is «رقم مرجع التحويل», a number the BANK
  -- issues, so on a cash payout there is nothing it could truthfully hold. The
  -- screen hides it for cash — this is what makes that a rule rather than a
  -- layout choice.
  IF p_method = 'تحويل مصرفي' THEN
    v_bank      := nullif(btrim(coalesce(p_bank_name, '')), '');
    v_acct_name := nullif(btrim(coalesce(p_bank_account_name, '')), '');
    v_acct_no   := nullif(btrim(coalesce(p_bank_account_no, '')), '');
    v_reference := nullif(btrim(coalesce(p_reference, '')), '');
  END IF;

  INSERT INTO public.disbursements (
    amount, kind, category, payee_adeel_id, payee_name, method, reference,
    bank_name, bank_account_no, bank_account_name, handed_by, note,
    spent_at, created_by)
  VALUES (
    p_amount, p_kind, p_category, p_payee_adeel_id, v_payee, p_method,
    v_reference,
    v_bank, v_acct_no, v_acct_name,
    nullif(btrim(coalesce(p_handed_by, '')), ''),
    nullif(btrim(coalesce(p_note, '')), ''),
    -- A back-dated voucher keeps the time of day it was entered, so two
    -- vouchers on the same past date still order deterministically.
    coalesce(p_spent_at + (now()::time), now()),
    auth.uid())
  RETURNING id, voucher_no INTO v_id, v_voucher;

  PERFORM public.write_audit('disbursement.register',
    format('صرف %s — %s', p_amount::text,
           coalesce('إلى ' || v_payee, p_category::text)),
    v_voucher);

  RETURN jsonb_build_object(
    'id', v_id, 'voucherNo', v_voucher,
    'amount', p_amount::text, 'kind', p_kind::text,
    'category', p_category::text,
    'payeeName', v_payee,
    -- What the treasury stands at AFTER this voucher. The screen states it back
    -- so an admin who has just emptied the fund learns it now rather than on
    -- the next attempt.
    'balanceAfter', (v_available - p_amount)::text);
END $$;

-- == 4. Rule 9, the same rule read backwards ===============================
CREATE OR REPLACE FUNCTION public.cancel_payment(
  p_payment_id bigint,
  p_reason     text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_pay       record;
  r           record;
  v_collected numeric;
  v_spent     numeric;
  v_held      numeric;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED' USING ERRCODE = 'RUL09';
  END IF;

  -- ── The treasury mutex, taken FIRST ────────────────────────────────────────
  -- Same row register_disbursement locks, and before the payment row rather
  -- than after, so the two money-moving paths queue in ONE order. No cycle can
  -- form: register_disbursement takes this row and nothing else, and
  -- register_payment takes receivables and nothing else.
  PERFORM 1 FROM public.association_settings WHERE id = 1 FOR UPDATE;

  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND' USING ERRCODE = 'RUL09';
  END IF;
  IF v_pay.status = 'ملغي' THEN
    RAISE EXCEPTION 'PAYMENT_ALREADY_CANCELLED' USING ERRCODE = 'RUL09';
  END IF;

  -- ── AND THE FUND CANNOT BE LEFT HOLDING LESS THAN NOTHING ──────────────────
  -- register_disbursement refuses to pay out money the association does not
  -- hold. Read only from that side the guarantee is half of one: collect 100,
  -- spend 100, then cancel the receipt that funded it and the treasury stands at
  -- −100 with nothing having refused anything. Every عديل reads that figure
  -- through api_association_finance() under the heading رصيد الجمعية.
  --
  -- The arithmetic is not what is wrong — if the receipt was entered by mistake
  -- and the money genuinely left, the fund really IS short. What is wrong is
  -- that it happens SILENTLY, and that every disbursement afterwards is then
  -- refused for a reason nobody was ever told. So the voucher is reversed first
  -- and this cancellation goes through second; the message says which.
  --
  -- This payment's own cash movement is excluded rather than subtracted: it is
  -- about to become 'ملغي', and rule 8 guarantees exactly one live row per live
  -- payment, so excluding it IS the post-cancellation total.
  SELECT coalesce(sum(amount), 0) INTO v_collected
    FROM public.cash_movements
   WHERE status <> 'ملغي' AND payment_id <> p_payment_id;
  SELECT coalesce(sum(amount), 0) INTO v_spent
    FROM public.disbursements WHERE status <> 'ملغي';

  -- The same subtraction register_disbursement makes, and it has to be here too:
  -- what is left after this cancellation is only spendable money if the عهد
  -- still standing is taken out of it. Excluding THIS payment is the same trick
  -- as the line above — it is about to be 'ملغي', so its own unallocated part
  -- stops being held at the same instant its cash movement stops counting.
  SELECT public.members_held(p_payment_id) INTO v_held;

  IF v_collected - v_held < v_spent THEN
    RAISE EXCEPTION
      'إلغاء الإيصال % يترك الصندوق سالباً — ألغِ سندات صرف بقيمة % أولاً',
      v_pay.receipt_no, (v_spent - (v_collected - v_held))::text
      USING ERRCODE = 'RUL09';
  END IF;

  -- Same lock order as register_payment: period then id.
  FOR r IN
    SELECT a.receivable_id, a.amount, rc.period
      FROM public.payment_allocations a
      JOIN public.receivables rc ON rc.id = a.receivable_id
     WHERE a.payment_id = p_payment_id
     ORDER BY rc.period ASC, rc.id ASC
       FOR UPDATE OF rc
  LOOP
    -- ck_recv_paid (paid >= 0) catches a double reversal.
    UPDATE public.receivables SET paid = paid - r.amount
     WHERE id = r.receivable_id;
  END LOOP;

  UPDATE public.payments
     SET status = 'ملغي', cancelled_at = now(),
         cancelled_by = auth.uid(), cancel_reason = p_reason
   WHERE id = p_payment_id;

  -- Voided, never deleted — the cash screen renders it struck through.
  UPDATE public.cash_movements SET status = 'ملغي' WHERE payment_id = p_payment_id;

  PERFORM public.write_audit('payment.cancel',
    format('إلغاء %s: %s', v_pay.receipt_no, p_reason), v_pay.receipt_no);

  RETURN jsonb_build_object(
    'paymentId', p_payment_id, 'receiptNo', v_pay.receipt_no,
    'status', 'ملغي', 'amount', v_pay.amount::text, 'reason', p_reason);
END $$;

-- == 5. What the member is told ============================================
CREATE OR REPLACE FUNCTION public.api_association_finance() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_out jsonb;
BEGIN
  IF public.my_role() IS NULL AND public.my_adeel_id() IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  SELECT jsonb_build_object(
    'collected', coalesce(sum(c.amount), 0)::numeric(12,2)::text,
    'cash',      coalesce(sum(c.amount) FILTER (WHERE c.method = 'نقداً'),
                          0)::numeric(12,2)::text,
    'transfer',  coalesce(sum(c.amount) FILTER (WHERE c.method = 'تحويل مصرفي'),
                          0)::numeric(12,2)::text)
    INTO v_out
    FROM public.cash_movements c
   WHERE c.status <> 'ملغي';

  RETURN v_out
    || jsonb_build_object(
         -- ── Spent, and what is left ─────────────────────────────────────────
         -- The member's transparency is not honest without the outgoing side:
         -- showing him only what came in, under a heading that says "the
         -- association's balance", would overstate the fund by everything it
         -- has ever paid out. The TOTAL spent is his to see; who received it is
         -- not — see the note on read_disbursements.
         'disbursed', (SELECT coalesce(sum(x.amount), 0)::numeric(12,2)::text
                         FROM public.disbursements x WHERE x.status <> 'ملغي'),
         -- ⚠ MINUS what is held for members, exactly as v_cash_summary does.
         -- The member reads this under the heading رصيد الجمعية; if it counted
         -- عهد, his own deposit would be shown to him as association money —
         -- and to every other member as well. See members_held().
         'heldForMembers', public.members_held()::numeric(12,2)::text,
         'balance', (
           (SELECT coalesce(sum(c2.amount), 0) FROM public.cash_movements c2
             WHERE c2.status <> 'ملغي')
           - (SELECT coalesce(sum(x.amount), 0) FROM public.disbursements x
               WHERE x.status <> 'ملغي')
           - public.members_held())::numeric(12,2)::text,
         'issued', (SELECT coalesce(sum(r.total), 0)::numeric(12,2)::text
                      FROM public.receivables r WHERE r.status <> 'ملغي'),
         'outstanding', (SELECT coalesce(sum(r.balance), 0)::numeric(12,2)::text
                           FROM public.receivables r WHERE r.status <> 'ملغي'),
         -- Counts, not money, and deliberately only the two a member can already
         -- infer from the register he is part of. No breakdown by person.
         'members', (SELECT count(*) FROM public.adeels),
         'activeMembers', (SELECT count(*) FROM public.adeels
                            WHERE status = 'نشط'));
END $$;

-- == 6. The allow-list, and the lockdown sweep =============================
-- members_held is created FRESH here, so it has no ACL to keep: Postgres
-- materialises EXECUTE to PUBLIC and Supabase layers anon on top. The sweep
-- below recomputes every grant from the list, which is what takes it back.
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    -- Role helpers. The RLS policies call these, so they must be executable by
    -- the caller whose policy is being evaluated. They leak nothing beyond that
    -- caller's own role.
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    -- Answers only for the caller's own عديل binding, and the عديل-scoped
    -- policies call it, so the caller whose policy is being evaluated must hold
    -- EXECUTE — otherwise every one of those policies ERRORS instead of denying,
    -- and the failure surfaces as "permission denied for function my_adeel_id"
    -- on screens that have nothing to do with the portal.
    'my_adeel_id()',
    -- Echoes the caller's own x-device-id header back. api_me() is SECURITY
    -- INVOKER and calls it, so the caller must hold EXECUTE or every launch
    -- fails with "permission denied for function request_device_id".
    'request_device_id()',
    -- عهد المشتركين. v_cash_summary is SECURITY INVOKER and calls it, so staff
    -- reading the treasury screen must hold EXECUTE or the whole view errors.
    -- It returns ONE aggregate and no row, no name and no receipt — and the
    -- figure it returns is already on that screen beside it.
    'members_held(bigint)',

    -- Writes. Each require_role()-gated, each one transaction.
    'register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_adeel(bigint,jsonb)',
    -- The only hard delete outside the purges, and it refuses any عديل who has
    -- ever been billed or has ever paid. Retiring someone with history is a
    -- status change, not a deletion.
    'delete_adeel(bigint)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    -- The two destructive ones. admin-only, and each refuses without its OWN
    -- typed phrase, so the phrase that clears the figures cannot clear the
    -- register. They are on the list because Settings calls them directly; the
    -- reason that is safe is the same reason the others are — the gate is inside
    -- the body, not in who can reach it.
    'purge_financial_data(text)',
    'purge_all_data(text)',

    -- The عديل portal. issue_ is admin-gated; redeem_ deliberately is NOT — it
    -- is the one write a signed-in stranger may call, because until he redeems a
    -- code he has no role and no binding, and the code itself is the
    -- authorisation. It refuses anyone who is already staff.
    'issue_adeel_code(bigint)',
    'redeem_adeel_code(text,text)',

    -- Money OUT. Both admin-gated inside their bodies; register_disbursement
    -- also refuses to spend past the treasury balance, which is rule 7 read
    -- backwards and the reason the fund cannot be overdrawn from a phone.
    'register_disbursement(numeric,disbursement_kind,pay_method,bigint,expense_category,text,text,text,text,text,text,date)',
    'cancel_disbursement(bigint,text)',

    -- Reads. STABLE and SECURITY INVOKER, so RLS still decides what they return.
    'period_label(text)',
    'adeel_json(bigint)',
    'api_adeel_detail(bigint)',
    'api_adeel_statement(bigint)',
    -- What the association GAVE him, beside what he owes it. SECURITY INVOKER,
    -- so staff read any man's and an عديل reads only his own — through
    -- read_own_disbursements, which is scoped on payee_adeel_id.
    'api_adeel_aid(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_closable_periods()',
    'api_settings()',
    'api_me()',
    'api_touch_login()',
    -- Aggregates only, and SECURITY DEFINER on purpose: an عديل's RLS on
    -- cash_movements is `adeel_id = my_adeel_id()`, so a SECURITY INVOKER
    -- version would show him HIS OWN four figures under headings that say
    -- "the association's" — a wrong answer he has no way to doubt. It returns
    -- no name, no receipt and no row, takes no argument, and writes nothing.
    'api_association_finance()'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- == 4. Re-run the lockdown sweep ===========================================
-- Byte-for-byte the loop from 20260811091200_function_lockdown.sql, which runs
-- LAST on a full apply. A patch gets no such pass, and api_adeel_aid is created
-- FRESH here — so Postgres materialises the built-in default ACL (EXECUTE to
-- PUBLIC) and Supabase's ALTER DEFAULT PRIVILEGES layers `anon` on top.
-- assert_no_public_execute() would then roll this patch back with a message
-- naming the function rather than the missing REVOKE, which reads like a defect
-- in the file.
DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.full_sig);
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;


-- == 7. Confirmation ========================================================
-- Read-only. Every row must say true. These run INSIDE the transaction, so a
-- false here is a patch to abandon rather than an outcome to accept — but
-- nothing below can fail on its own: they assert what the statements above
-- have already done.
SELECT 'عهد المشتركين تُحسب في مكان واحد' AS "الفحص",
       (to_regprocedure('public.members_held(bigint)') IS NOT NULL) AS "النتيجة"
UNION ALL SELECT 'وهي على قائمة الأذونات',
       ('members_held(bigint)' = ANY (public.client_callable_functions()))
UNION ALL SELECT 'ولا تُنفَّذ من PUBLIC ولا من anon',
       NOT has_function_privilege('anon', 'public.members_held(bigint)', 'EXECUTE')
UNION ALL SELECT 'الخزينة تعرض عهد المشتركين',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='v_cash_summary'
                  AND column_name='heldForMembers')
UNION ALL SELECT 'ورصيد الجمعية = المحصل − المصروف − العهد',
       (SELECT "balance"::numeric
             = "total"::numeric - "disbursed"::numeric - "heldForMembers"::numeric
          FROM public.v_cash_summary)
-- The two independent expressions for one quantity: the treasury aggregate and
-- the register's per-member wallet. A disagreement is a member reading one
-- figure and the treasurer another, with no third number to say which is wrong.
UNION ALL SELECT 'والعهد تساوي مجموع أرصدة المشتركين',
       (SELECT (SELECT "heldForMembers"::numeric FROM public.v_cash_summary)
             = (SELECT coalesce(sum("credit"::numeric), 0) FROM public.v_adeels))
UNION ALL SELECT 'ولا شيء منها سالب',
       (SELECT "heldForMembers"::numeric >= 0 AND "balance"::numeric >= 0
          FROM public.v_cash_summary)
-- Rule 17 and rule 9 must read the same rule. Both bodies are checked by their
-- text, because the alternative — actually spending money to prove it — is not
-- something a patch may do to a live treasury.
UNION ALL SELECT 'قاعدة الصرف تطرح العهد',
       (SELECT pg_get_functiondef(p.oid) LIKE '%members_held()%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='register_disbursement')
UNION ALL SELECT 'وقاعدة إلغاء الإيصال تطرحها أيضاً',
       (SELECT pg_get_functiondef(p.oid) LIKE '%members_held(p_payment_id)%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='cancel_payment')
-- ⚠ CHECKED BY ITS TEXT, not by calling it. api_association_finance refuses a
-- caller with no role and no عديل binding — which is exactly what the SQL
-- Editor is: it runs as `postgres` with no JWT, so my_role() is NULL and the
-- function raises FORBIDDEN. Invoking it here would abort the patch on a
-- project where nothing is wrong. 75_held.sql calls it for real, as a member.
UNION ALL SELECT 'وبوابة المشترك تقرأ الرقم نفسه',
       (SELECT pg_get_functiondef(p.oid) LIKE '%heldForMembers%'
           AND pg_get_functiondef(p.oid) LIKE '%members_held()%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='api_association_finance')
-- ⚠ AND NO MONEY MOVED. The patch touches no row; these are the totals it must
--   have left exactly as it found them. `total` is every collection ever
--   recorded and cannot change here, and the register's own debt figure is
--   computed from receivables which this patch never mentions.
UNION ALL SELECT 'ولم يتغيّر إجمالي المحصل ولا المستحقات',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
           AND "outstanding"::numeric = (SELECT coalesce(sum(balance), 0)
                                           FROM public.receivables
                                          WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 8. The four guards =====================================================
-- assert_function_grants() is the one that matters most here: it asserts the
-- allow-list is EXACT, so members_held being reachable and members_held being
-- LISTED are checked against each other rather than each on its own.
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
