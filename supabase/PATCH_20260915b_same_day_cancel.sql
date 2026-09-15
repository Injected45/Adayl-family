-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-15 (b).  الإلغاءُ في يوم العملية فقط.
--
--  ما الذي يفعله هذا الملف
--    «إلغاء وعكس» في التحصيل و«إلغاء الصرف» في الصرف لا يُقبلان إلا في نفس
--    يوم تسجيل العملية بتوقيت ليبيا. بعد منتصف الليل تصير العمليةُ جزءًا ثابتًا
--    من الدفتر: لا تُلغى ولا تُعكس.
--
--  ⚠ الحارسُ في قاعدة البيانات، لا في الشاشة وحدها. دالّتا الإلغاء ترفضان أيَّ
--    عمليةٍ من يومٍ سابق — حتى لو ضُغط الزرُّ من نسخةٍ قديمة من التطبيق. وتاريخُ
--    العملية ختمٌ من ساعة الخادم، فلا يستطيع هاتفٌ أن يجعل عمليةً قديمة «اليوم».
--
--  ⚠ والقائمتان تُخبران التطبيق بعمودٍ جديد (cancellable) إن كانت العمليةُ
--    قابلةً للإلغاء، محسوبٍ بالشرط نفسه، فيظهر الزرُّ لعمليات اليوم وحدها.
--
--  ⚠ لا يتغيّر أيُّ رقم، ولا تُلغى أيُّ عملية. العمليات القديمة كلُّها تصير غيرَ
--    قابلةٍ للإلغاء من لحظة التشغيل.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.cancel_payment(bigint,text)') IS NULL
     OR to_regprocedure('public.cancel_disbursement(bigint,text)') IS NULL
     OR to_regclass('public.v_payments') IS NULL
     OR to_regclass('public.v_disbursements') IS NULL THEN
    RAISE EXCEPTION 'هذا ليس مشروع الجمعية بنظام الصرف — لم يتغيّر شيء.';
  END IF;
END $prereq$;

-- == 1. إلغاء الإيصال ======================================================
CREATE OR REPLACE FUNCTION public.cancel_payment(p_payment_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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

  -- ── ⚠ يُلغى في يومه فقط (PATCH_20260915b) ─────────────────────────────────
  -- «يمنع تغيير اي عملية عدت عليها … فقط في نفس اليوم». A receipt is
  -- reversible on the Tripoli calendar day it was recorded and on no other:
  -- once midnight passes it is part of the books. paid_at is stamped by the
  -- server's clock (pay_stamp_time), so no handset can move a receipt into
  -- «today» to reopen it.
  IF (v_pay.paid_at AT TIME ZONE 'Africa/Tripoli')::date
       <> (now() AT TIME ZONE 'Africa/Tripoli')::date THEN
    RAISE EXCEPTION 'لا يُلغى الإيصال % إلا في يوم تسجيله، وقد مضى يومه', v_pay.receipt_no
      USING ERRCODE = 'RUL09';
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
END $function$;

-- == 2. إلغاء الصرف ======================================================
CREATE OR REPLACE FUNCTION public.cancel_disbursement(p_id bigint, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE v_row record;
BEGIN
  PERFORM public.require_role('admin');

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED' USING ERRCODE = 'RUL17';
  END IF;

  SELECT * INTO v_row FROM public.disbursements WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DISBURSEMENT_NOT_FOUND' USING ERRCODE = 'RUL17';
  END IF;
  IF v_row.status = 'ملغي' THEN
    RAISE EXCEPTION 'DISBURSEMENT_ALREADY_CANCELLED' USING ERRCODE = 'RUL17';
  END IF;

  -- ── ⚠ يُلغى في يومه فقط (PATCH_20260915b) ─────────────────────────────────
  -- The same rule as cancel_payment, read from the other direction: a voucher
  -- is reversible on the Tripoli day it was recorded and never after.
  IF (v_row.spent_at AT TIME ZONE 'Africa/Tripoli')::date
       <> (now() AT TIME ZONE 'Africa/Tripoli')::date THEN
    RAISE EXCEPTION 'لا يُلغى السند % إلا في يوم تسجيله، وقد مضى يومه', v_row.voucher_no
      USING ERRCODE = 'RUL17';
  END IF;

  UPDATE public.disbursements
     SET status = 'ملغي', cancelled_at = now(),
         cancelled_by = auth.uid(), cancel_reason = p_reason
   WHERE id = p_id;

  PERFORM public.write_audit('disbursement.cancel',
    format('إلغاء %s: %s', v_row.voucher_no, p_reason), v_row.voucher_no);

  RETURN jsonb_build_object(
    'id', p_id, 'voucherNo', v_row.voucher_no,
    'status', 'ملغي', 'amount', v_row.amount::text, 'reason', p_reason);
END $function$;

-- == 3. قائمة التحصيل ====================================================
CREATE OR REPLACE VIEW public.v_payments WITH (security_invoker = on) AS
SELECT p.id,
    p.receipt_no AS "receiptNo",
    p.adeel_id AS "adeelId",
    a.full_name AS "adeelName",
    a.adeel_code AS "adeelCode",
    (p.amount)::text AS amount,
    (p.method)::text AS method,
    COALESCE(p.reference, ''::text) AS reference,
    COALESCE(p.receiver, ''::text) AS receiver,
    COALESCE(p.notes, ''::text) AS notes,
    (p.status)::text AS status,
    to_char((p.paid_at AT TIME ZONE 'UTC'::text), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'::text) AS "paidAt",
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('receivableId', al.receivable_id, 'period', al.period, 'amount', (al.amount)::text) ORDER BY al.sequence_no) AS jsonb_agg
           FROM payment_allocations al
          WHERE (al.payment_id = p.id)), '[]'::jsonb) AS allocations,
    COALESCE(p.bank_account_no, ''::text) AS "bankAccountNo",
    COALESCE(p.bank_account_name, ''::text) AS "bankAccountName",
    COALESCE(p.bank_name, ''::text) AS "bankName",
    -- ⚠ THE SERVER SAYS WHETHER THE BUTTON EXISTS (PATCH_20260915b). Today on
    --   the Tripoli calendar and not already reversed — the exact test the
    --   cancel function applies, so the screen can never offer what the
    --   function refuses. Computed from now(), never from a handset's clock.
    ((p.status <> 'ملغي'::pay_status)
      AND ((p.paid_at AT TIME ZONE 'Africa/Tripoli'::text))::date
          = ((now() AT TIME ZONE 'Africa/Tripoli'::text))::date) AS cancellable
   FROM (payments p
     JOIN adeels a ON ((a.id = p.adeel_id)));

-- ⚠ Restated: a view that is ever dropped and recreated comes back with no
--   grants, and every reader gets «permission denied» on a blank list.
REVOKE ALL ON public.v_payments FROM PUBLIC, anon;
GRANT SELECT ON public.v_payments TO authenticated;

-- == 4. قائمة الصرف ======================================================
CREATE OR REPLACE VIEW public.v_disbursements WITH (security_invoker = on) AS
SELECT d.id,
    d.voucher_no AS "voucherNo",
    (d.amount)::text AS amount,
    (d.kind)::text AS kind,
    (d.category)::text AS category,
    d.payee_adeel_id AS "payeeAdeelId",
    COALESCE(d.payee_name, ''::text) AS "payeeName",
    COALESCE(a.adeel_code, ''::text) AS "payeeCode",
    (d.method)::text AS method,
    COALESCE(d.reference, ''::text) AS reference,
    COALESCE(d.bank_name, ''::text) AS "bankName",
    COALESCE(d.bank_account_no, ''::text) AS "bankAccountNo",
    COALESCE(d.bank_account_name, ''::text) AS "bankAccountName",
    COALESCE(d.handed_by, ''::text) AS "handedBy",
    COALESCE(d.note, ''::text) AS note,
    (d.status)::text AS status,
    to_char((d.spent_at AT TIME ZONE 'UTC'::text), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'::text) AS "spentAt",
    -- ⚠ THE SERVER SAYS WHETHER THE BUTTON EXISTS (PATCH_20260915b). Today on
    --   the Tripoli calendar and not already reversed — the exact test the
    --   cancel function applies, so the screen can never offer what the
    --   function refuses. Computed from now(), never from a handset's clock.
    ((d.status <> 'ملغي'::pay_status)
      AND ((d.spent_at AT TIME ZONE 'Africa/Tripoli'::text))::date
          = ((now() AT TIME ZONE 'Africa/Tripoli'::text))::date) AS cancellable
   FROM (disbursements d
     LEFT JOIN adeels a ON ((a.id = d.payee_adeel_id)));

-- ⚠ Restated: a view that is ever dropped and recreated comes back with no
--   grants, and every reader gets «permission denied» on a blank list.
REVOKE ALL ON public.v_disbursements FROM PUBLIC, anon;
GRANT SELECT ON public.v_disbursements TO authenticated;

-- == 5. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 6. النتيجة: آخرُ جدولٍ يظهر في المحرّر، وكلُّ صفٍّ يجب أن يقول true ======
SELECT 'إلغاءُ الإيصال يرفض ما ليس من اليوم' AS "الفحص",
       (SELECT prosrc LIKE '%إلا في يوم تسجيله%'
          FROM pg_proc WHERE oid = 'public.cancel_payment(bigint,text)'::regprocedure)::text AS "النتيجة"
UNION ALL SELECT 'وإلغاءُ الصرف كذلك',
       (SELECT prosrc LIKE '%إلا في يوم تسجيله%'
          FROM pg_proc WHERE oid = 'public.cancel_disbursement(bigint,text)'::regprocedure)::text
UNION ALL SELECT 'وقائمةُ التحصيل تُخبر التطبيق',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'v_payments'
                  AND column_name = 'cancellable')::text
UNION ALL SELECT 'وقائمةُ الصرف تُخبر التطبيق',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'v_disbursements'
                  AND column_name = 'cancellable')::text
UNION ALL SELECT 'إيصالاتٌ قابلةٌ للإلغاء الآن (من اليوم فقط)',
       (SELECT count(*) FROM public.v_payments WHERE cancellable)::text
UNION ALL SELECT 'سنداتٌ قابلةٌ للإلغاء الآن (من اليوم فقط)',
       (SELECT count(*) FROM public.v_disbursements WHERE cancellable)::text
UNION ALL SELECT 'رصيدُ الجمعية (لم يتغيّر)',
       (SELECT balance FROM public.v_cash_summary);

COMMIT;
