-- 20260811090600_rpc.sql — every write in the system.
--
-- These functions are the direct replacement for the transactional endpoints.
-- Each is SECURITY DEFINER (so it can write tables the caller holds no privilege
-- on), each pins search_path (so a caller cannot redirect the elevated body at
-- their own schema), and each starts with require_role().
--
-- A function body is one transaction. That is the whole reason this file exists:
-- registering a payment inserts a payment, N allocations, N receivable updates
-- and a cash movement, and either all of it lands or none of it does. Split
-- across separate PostgREST calls from a phone, a dropped connection between
-- call three and call four leaves the treasury disagreeing with the ledger, and
-- no amount of client retry logic can repair it afterwards.
--
-- Money crosses the wire as TEXT. numeric serialises to an unquoted JSON number,
-- which dart:convert decodes to double — proven in supabase/tests/. Every amount
-- returned below is cast explicitly.

-- ── Audit helper ─────────────────────────────────────────────────────────────
-- actor_name is snapshotted so the trail survives a rename or a deleted account.
CREATE OR REPLACE FUNCTION public.write_audit(
  p_event_type text, p_detail text, p_ref text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_name text;
BEGIN
  SELECT coalesce(nullif(display_name, ''), email) INTO v_name
    FROM public.profiles WHERE id = auth.uid();
  INSERT INTO public.audit_log (event_type, detail, ref, actor_user_id, actor_name)
  VALUES (p_event_type, p_detail, p_ref, auth.uid(), coalesce(v_name, 'system'));
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- POST /payments.  THE critical transaction.
--
-- Rule 7: amount > 0, amount <= total outstanding, FIFO oldest period first.
-- Rule 8: exactly one cash movement per approved payment.
--
-- FIFO now runs over ONE عديل's own open periods rather than a household's. The
-- loop is otherwise unchanged, and so is every reason it is written this way.
--
-- The FOR UPDATE is not decoration. Two treasurers collecting from the same عديل
-- at the same moment both read a 100 balance and both allocate 60; without the
-- lock the second overwrites the first and 20 vanishes. The lock makes the loser
-- wait, re-read, and fail the outstanding check — which is the correct outcome.
-- ORDER BY inside the locking SELECT also fixes a consistent lock order, so two
-- payments touching overlapping receivables cannot deadlock.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.register_payment(
  p_adeel_id  bigint,
  p_amount    numeric,
  p_method    pay_method,
  p_reference text DEFAULT NULL,
  p_receiver  text DEFAULT NULL,
  p_notes     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  -- Unconstrained numeric, NOT numeric(12,2). Individual amounts are bounded by
  -- the column type, but their SUM is not: an عديل with enough open periods
  -- overflows a 12-digit accumulator and the call dies with 22003 instead of
  -- reporting the balance. Found by the probe suite, which pushed a large total
  -- through and got "numeric field overflow" where it expected a rule violation.
  v_outstanding numeric;
  v_remaining   numeric;
  v_payment_id  bigint;
  v_receipt     text;
  v_take        numeric(12,2);
  v_seq         smallint := 0;
  r             record;
  v_allocs      jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.require_role('treasurer');

  -- Round to minor units up front. A client can post 10.005; accepting it would
  -- put a third decimal into an allocation and the sums would stop tying out.
  p_amount := round(p_amount, 2);

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Rule 7: payment amount must be greater than zero'
      USING ERRCODE = 'RUL07';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.adeels WHERE id = p_adeel_id) THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL07';
  END IF;

  -- Lock every open receivable for this عديل, oldest first. Once locked, no
  -- other transaction can move them for the rest of this one, so the total below
  -- and the loop further down both read the same reality — which is the whole
  -- point. ORDER BY also fixes a consistent lock acquisition order.
  PERFORM 1
    FROM public.receivables r2
   WHERE r2.adeel_id = p_adeel_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0
   ORDER BY r2.period ASC, r2.id ASC
     FOR UPDATE;

  SELECT coalesce(sum(r2.balance), 0) INTO v_outstanding
    FROM public.receivables r2
   WHERE r2.adeel_id = p_adeel_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0;

  IF v_outstanding <= 0 THEN
    RAISE EXCEPTION 'Rule 7: العديل has no outstanding balance'
      USING ERRCODE = 'RUL07';
  END IF;

  IF p_amount > v_outstanding THEN
    RAISE EXCEPTION 'Rule 7: amount % exceeds outstanding balance %',
      p_amount, v_outstanding USING ERRCODE = 'RUL07';
  END IF;

  INSERT INTO public.payments (adeel_id, amount, method, reference, receiver,
                               notes, created_by)
  VALUES (p_adeel_id, p_amount, p_method, p_reference, p_receiver, p_notes,
          auth.uid())
  RETURNING id, receipt_no INTO v_payment_id, v_receipt;

  v_remaining := p_amount;

  FOR r IN SELECT r2.id, r2.period, r2.balance
             FROM public.receivables r2
            WHERE r2.adeel_id = p_adeel_id
              AND r2.status <> 'ملغي'
              AND r2.balance > 0
            ORDER BY r2.period ASC, r2.id ASC
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := least(v_remaining, r.balance);
    v_seq  := v_seq + 1;

    INSERT INTO public.payment_allocations
      (payment_id, receivable_id, period, amount, sequence_no)
    VALUES (v_payment_id, r.id, r.period, v_take, v_seq);

    -- ck_recv_paid (paid <= total) is the storage-engine backstop: if the maths
    -- above were ever wrong, this UPDATE fails and the whole call rolls back.
    UPDATE public.receivables SET paid = paid + v_take WHERE id = r.id;

    v_remaining := v_remaining - v_take;
    v_allocs := v_allocs || jsonb_build_object(
      'receivableId', r.id, 'period', r.period,
      'amount', v_take::text, 'sequenceNo', v_seq);
  END LOOP;

  IF v_remaining <> 0 THEN
    RAISE EXCEPTION 'INVARIANT: % left unallocated after FIFO', v_remaining
      USING ERRCODE = 'RUL07';
  END IF;

  -- Rule 8. uq_cash_payment makes a duplicate structurally impossible.
  INSERT INTO public.cash_movements
    (payment_id, adeel_id, amount, method, occurred_at)
  SELECT id, adeel_id, amount, method, paid_at
    FROM public.payments WHERE id = v_payment_id;

  PERFORM public.write_audit('payment.register',
    format('تحصيل %s من العديل %s', p_amount::text, p_adeel_id),
    v_receipt);

  RETURN jsonb_build_object(
    'paymentId', v_payment_id,
    'receiptNo', v_receipt,
    'adeelId',   p_adeel_id,
    'amount',    p_amount::text,
    'method',    p_method,
    'allocations', v_allocs);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- POST /payments/:id/cancel.  The second critical transaction.
-- Rule 9: reverse the money, preserve every row.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cancel_payment(
  p_payment_id bigint,
  p_reason     text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_pay record;
  r     record;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED' USING ERRCODE = 'RUL09';
  END IF;

  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND' USING ERRCODE = 'RUL09';
  END IF;
  IF v_pay.status = 'ملغي' THEN
    RAISE EXCEPTION 'PAYMENT_ALREADY_CANCELLED' USING ERRCODE = 'RUL09';
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

-- ═════════════════════════════════════════════════════════════════════════════
-- POST /receivables/generate.
-- Rules 3, 4, 5: total > 0 or skip, one live row per (عديل, period), snapshot.
--
-- Rule 1 used to live here too — "eligibility is age at PERIOD END" — and it is
-- gone. There is no age gate: every عديل whose status is 'نشط' is billed the one
-- monthly fee, and a موقوف or متوفى عديل is billed nothing whatever his age. The
-- period-end date is still computed and stored, because it is what a statement
-- prints and what auto_close walks.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.generate_period(p_period char(7))
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  s           record;
  a           record;
  v_end       date;
  v_recv_id   bigint;
  v_created   int := 0;
  v_skipped   int := 0;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'BAD_PERIOD: %', p_period USING ERRCODE = 'RUL04';
  END IF;

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_end := (to_date(p_period || '-01', 'YYYY-MM-DD')
            + interval '1 month - 1 day')::date;

  -- Rule 3: nothing to charge means no rows at all, not zero rows. A fee of zero
  -- is a valid configuration (the association pausing collection), and it must
  -- produce an empty period rather than a register full of 0.00 charges that
  -- ck_recv_total would refuse anyway.
  IF s.member_fee <= 0 THEN
    SELECT count(*) INTO v_skipped FROM public.adeels WHERE status = 'نشط';
    PERFORM public.write_audit('receivables.generate',
      format('إنشاء استحقاقات %s: لا رسم مقرر', p_period), p_period);
    RETURN jsonb_build_object('period', p_period, 'created', 0,
                              'skipped', v_skipped);
  END IF;

  FOR a IN SELECT id, full_name, status
             FROM public.adeels ORDER BY id LOOP
    -- Status overrides everything: a موقوف or متوفى عديل is not billable.
    IF a.status <> 'نشط' THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Rule 4 as idempotency: re-running the same period skips instead of
    -- raising a duplicate. The partial index is what makes this safe under
    -- concurrency, so two admins pressing the button together cannot double-bill.
    INSERT INTO public.receivables (
      adeel_id, period, period_end, adeel_name, total,
      created_by)
    VALUES (
      a.id, p_period, v_end, a.full_name, s.member_fee,
      auth.uid())
    ON CONFLICT (adeel_id, period) WHERE status <> 'ملغي' DO NOTHING
    RETURNING id INTO v_recv_id;

    IF v_recv_id IS NULL THEN
      v_skipped := v_skipped + 1;
    ELSE
      v_created := v_created + 1;
    END IF;
    v_recv_id := NULL;
  END LOOP;

  PERFORM public.write_audit('receivables.generate',
    format('إنشاء استحقاقات %s: %s سجل', p_period, v_created), p_period);

  RETURN jsonb_build_object('period', p_period, 'created', v_created,
                            'skipped', v_skipped);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- POST /receivables/auto-close.
-- Rule 6: backfill system_start → previous month. Idempotent via rule 4.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.auto_close_periods()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  s         record;
  v_cursor  date;
  v_last    date;
  v_period  char(7);
  v_created int := 0;
  v_periods jsonb := '[]'::jsonb;
  v_one     jsonb;
BEGIN
  PERFORM public.require_role('financeManager');

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_cursor := date_trunc('month', s.system_start)::date;
  -- PREVIOUS month, not this one — the current month is not closed until it ends.
  v_last   := (date_trunc('month', current_date) - interval '1 month')::date;

  WHILE v_cursor <= v_last LOOP
    v_period := to_char(v_cursor, 'YYYY-MM');
    v_one    := public.generate_period(v_period);
    v_created := v_created + (v_one ->> 'created')::int;
    v_periods := v_periods || v_one;
    v_cursor := (v_cursor + interval '1 month')::date;
  END LOOP;

  RETURN jsonb_build_object('created', v_created, 'periods', v_periods);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- POST /adeels, PUT /adeels/:id.  Replaces save_family().
-- What is left of rule 10: a date of birth cannot be in the future. The unique
-- national ID that was its other half is gone, so nothing here refuses a second
-- row for a person already on the register.
--
-- save_family() took a father object plus a sons array and had to delete the
-- absent sons BEFORE inserting the present ones, because reusing the national ID
-- of a son removed in the same call tripped the unique index otherwise. None of
-- that survives: one call now writes one row, and the ordering hazard it was
-- guarding against cannot arise. Removing an عديل is delete_adeel() below, which
-- is a separate, explicitly-confirmed act rather than a side effect of saving.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.save_adeel(
  p_adeel_id bigint,        -- NULL to create
  p_adeel    jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_id   bigint := p_adeel_id;
  v_code text;
BEGIN
  PERFORM public.require_role('financeManager');

  IF v_id IS NULL THEN
    INSERT INTO public.adeels (
      full_name, phone, subscription_no, dob, nationality,
      workplace, registered_at, status, notes, created_by, updated_by)
    VALUES (
      p_adeel ->> 'fullName',
      p_adeel ->> 'phone', p_adeel ->> 'subscriptionNo',
      nullif(p_adeel ->> 'dob', '')::date,
      coalesce(nullif(p_adeel ->> 'nationality', ''), 'ليبي'),
      p_adeel ->> 'workplace',
      coalesce(nullif(p_adeel ->> 'registeredAt', '')::date, current_date),
      coalesce(nullif(p_adeel ->> 'status', '')::member_status, 'نشط'),
      p_adeel ->> 'notes',
      auth.uid(), auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.adeels SET
      full_name       = p_adeel ->> 'fullName',
      phone           = p_adeel ->> 'phone',
      subscription_no = p_adeel ->> 'subscriptionNo',
      dob             = nullif(p_adeel ->> 'dob', '')::date,
      nationality     = coalesce(nullif(p_adeel ->> 'nationality', ''), 'ليبي'),
      workplace       = p_adeel ->> 'workplace',
      registered_at   = coalesce(nullif(p_adeel ->> 'registeredAt', '')::date,
                                 registered_at),
      status          = coalesce(nullif(p_adeel ->> 'status', '')::member_status,
                                 status),
      notes           = p_adeel ->> 'notes',
      updated_by      = auth.uid()
     WHERE id = v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL10';
    END IF;
  END IF;

  SELECT adeel_code INTO v_code FROM public.adeels WHERE id = v_id;

  PERFORM public.write_audit(
    CASE WHEN p_adeel_id IS NULL THEN 'adeel.create' ELSE 'adeel.update' END,
    format('%s %s', CASE WHEN p_adeel_id IS NULL THEN 'إضافة' ELSE 'تعديل' END,
           v_code), v_code);

  RETURN jsonb_build_object('adeelId', v_id, 'adeelCode', v_code);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- DELETE /adeels/:id.
--
-- The old model could remove a son simply by leaving him out of save_family's
-- array, and it refused when a receivable line referenced him. That capability
-- has to survive somewhere or a mistyped entry becomes permanent, so it is an
-- explicit call now — and it keeps the same guard, tightened to the whole
-- ledger: an عديل who has ever been billed or has ever paid cannot be erased,
-- because receivables and payments both reference him ON DELETE RESTRICT and
-- losing him would leave a receipt pointing at nobody.
--
-- The supported way to retire someone who HAS history is status 'موقوف' or
-- 'متوفى', which stops the billing without touching what he already owes.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.delete_adeel(p_adeel_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_code text;
BEGIN
  PERFORM public.require_role('financeManager');

  SELECT adeel_code INTO v_code FROM public.adeels WHERE id = p_adeel_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL10';
  END IF;

  IF EXISTS (SELECT 1 FROM public.receivables WHERE adeel_id = p_adeel_id)
     OR EXISTS (SELECT 1 FROM public.payments WHERE adeel_id = p_adeel_id) THEN
    RAISE EXCEPTION 'لا يمكن حذف عديل له سجل مالي، غيّر حالته إلى موقوف'
      USING ERRCODE = 'RUL10';
  END IF;

  -- Cascades to his profile binding and his access code, both of which point at
  -- him ON DELETE CASCADE. He can sign in again and redeem a fresh code if he is
  -- re-added later.
  DELETE FROM public.adeels WHERE id = p_adeel_id;

  PERFORM public.write_audit('adeel.delete', format('حذف %s', v_code), v_code);

  RETURN jsonb_build_object('adeelId', p_adeel_id, 'adeelCode', v_code);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- PUT /settings.  Rule 5's counterpart: changing these must not touch history,
-- which trg_recv_snapshot_immutable guarantees independently.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.update_settings(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_row record;
BEGIN
  PERFORM public.require_role('admin');

  UPDATE public.association_settings SET
    association_name = coalesce(p_patch ->> 'associationName', association_name),
    currency         = coalesce(p_patch ->> 'currency', currency),
    member_fee       = coalesce((p_patch ->> 'memberFee')::numeric, member_fee),
    system_start     = coalesce((p_patch ->> 'systemStart')::date, system_start),
    treasurer_name        = coalesce(p_patch ->> 'treasurerName', treasurer_name),
    treasurer_phone       = coalesce(p_patch ->> 'treasurerPhone', treasurer_phone),
    finance_manager_name        = coalesce(p_patch ->> 'financeName', finance_manager_name),
    finance_manager_phone       = coalesce(p_patch ->> 'financePhone', finance_manager_phone),
    updated_by = auth.uid()
  WHERE id = 1
  RETURNING * INTO v_row;

  PERFORM public.write_audit('settings.update', 'تحديث إعدادات الجمعية', 'settings');

  RETURN jsonb_build_object(
    'associationName', v_row.association_name, 'currency', v_row.currency,
    'memberFee', v_row.member_fee::text,
    'systemStart', v_row.system_start);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- PATCH /users/:id.  Self-elevation and last-admin are blocked by
-- trg_profiles_guard, so they hold even against the service_role key.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_user_access(
  p_user_id uuid, p_role app_role DEFAULT NULL, p_status app_status DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_row record;
BEGIN
  PERFORM public.require_role('admin');

  UPDATE public.profiles SET
    role   = coalesce(p_role, role),
    status = coalesce(p_status, status),
    approved_by = CASE WHEN p_status = 'approved' THEN auth.uid() ELSE approved_by END,
    approved_at = CASE WHEN p_status = 'approved' THEN now() ELSE approved_at END
  WHERE id = p_user_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'RUL00';
  END IF;

  PERFORM public.write_audit('user.access',
    format('%s → %s / %s', v_row.email, v_row.role, v_row.status),
    v_row.id::text);

  RETURN jsonb_build_object('id', v_row.id, 'email', v_row.email,
                            'role', v_row.role, 'status', v_row.status);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Purge — the ONE deliberate exception to rule 9, and the only way to erase
-- financial history. Settings → منطقة الخطر calls it.
--
-- WHY IT EXISTS: the association trials the app with practice figures before it
-- goes live. Cancelling every payment (rule 9's supported path) leaves the
-- practice rows on screen struck through forever, so there had to be a way to
-- actually start from zero.
--
-- WHY TRUNCATE AND NOT DELETE: the four financial tables carry BEFORE DELETE
-- triggers (refuse_delete) and audit_log carries refuse_audit_change. TRUNCATE
-- fires neither — only AFTER TRUNCATE statement triggers, and none are defined.
-- The alternative was ALTER TABLE … DISABLE TRIGGER around the DELETEs, which
-- takes the same ACCESS EXCLUSIVE lock but leaves a window in which the rule-9
-- guard is genuinely off. TRUNCATE never disarms anything, so a failure here
-- cannot leave the table unprotected. It also resets the identity sequences,
-- which is what makes the next receipt PAY-000001 instead of continuing the
-- practice run's numbering.
--
-- So rule 9 now reads: nothing can be hard-deleted except through this function
-- and delete_adeel(), both admin-gated, this one demanding a typed confirmation,
-- and both one transaction. `authenticated` holds no TRUNCATE privilege on any
-- table (see 20260811091200_function_lockdown.sql), so this really is the only
-- route to erasing the money.
--
-- WHAT SURVIVES: adeels, association_settings, profiles. The purge is financial
-- only — the register is what the association spent the most effort entering,
-- and rebuilding it is not what "clear the figures" means.
--
-- WHAT DOES NOT: audit_log is truncated too, and NO entry is written afterwards.
-- That is a deliberate choice by the association's admin, and it is worth being
-- explicit about the cost: rule 12 makes the trail append-only precisely so an
-- administrator cannot quietly rewrite history, and this function is a hole in
-- that. After it runs there is no record inside the database that it ran, or of
-- anything that preceded it. If that is ever regretted, the fix is one line —
-- move the audit_log truncate out and write a 'data.purge' entry at the end.
--
-- No ordering hazard in the TRUNCATE list: every FK pointing INTO these five
-- tables originates in one of the five, so Postgres does not demand CASCADE.
-- Adding a sixth table that references payments without listing it here would
-- fail loudly rather than silently skip.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.purge_financial_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv  bigint;
  v_pay   bigint;
  v_alloc bigint;
  v_cash  bigint;
  v_audit bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- The typed phrase. Not UX politeness: register_payment and save_adeel are
  -- reachable by anyone who can read the anon key out of the APK, and so is
  -- this. require_role stops a treasurer; the phrase stops an admin's own
  -- mis-click and a replayed request. It must match wire_values.dart exactly.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح نهائي' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  -- Counted before, because TRUNCATE reports no row count. These tables are
  -- small enough that five counts cost nothing next to the truncate itself.
  SELECT count(*) INTO v_recv  FROM public.receivables;
  SELECT count(*) INTO v_pay   FROM public.payments;
  SELECT count(*) INTO v_alloc FROM public.payment_allocations;
  SELECT count(*) INTO v_cash  FROM public.cash_movements;
  SELECT count(*) INTO v_audit FROM public.audit_log;

  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivables,
           public.audit_log
    RESTART IDENTITY;

  RETURN jsonb_build_object(
    'receivables',   v_recv,
    'payments',      v_pay,
    'allocations',   v_alloc,
    'cashMovements', v_cash,
    'auditEntries',  v_audit);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Purge, the wider one — the register as well as the money.
--
-- WHY IT CANNOT BE "ADEELS ONLY": receivables, payments and cash_movements all
-- carry `adeel_id … ON DELETE RESTRICT`. A purge that removed the register while
-- a single receipt still pointed at one would be refused by the storage engine,
-- so the choice is between erasing the financial rows alongside it or refusing
-- whenever any exist. Refusing would mean the button fails for exactly the
-- person who wants it — an admin clearing a trial run — and would leave him
-- pressing two buttons in an order nothing tells him about. So this is
-- deliberately a SUPERSET of purge_financial_data, and the screen says so rather
-- than surprising him after the fact.
--
-- The separate confirmation phrase is the point of having two functions at all.
-- Both are admin-only and both truncate; what stops a mis-click from erasing the
-- register when only the figures were meant is that 'مسح نهائي' does not satisfy
-- this function, and the app cannot send a phrase the admin did not type.
--
-- WHAT SURVIVES: association_settings and staff profiles. Wiping staff profiles
-- would strand the association outside its own app — the last-admin guard exists
-- precisely to make that unreachable — and settings are configuration, not data.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.purge_all_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv   bigint;
  v_pay    bigint;
  v_alloc  bigint;
  v_cash   bigint;
  v_audit  bigint;
  v_adeels bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- Distinct from purge_financial_data's phrase ON PURPOSE. See above.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح كل البيانات' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  SELECT count(*) INTO v_recv   FROM public.receivables;
  SELECT count(*) INTO v_pay    FROM public.payments;
  SELECT count(*) INTO v_alloc  FROM public.payment_allocations;
  SELECT count(*) INTO v_cash   FROM public.cash_movements;
  SELECT count(*) INTO v_audit  FROM public.audit_log;
  SELECT count(*) INTO v_adeels FROM public.adeels;

  -- ── Why adeels is DELETEd while the five financial tables are TRUNCATEd ────
  -- profiles.adeel_id references adeels, and TRUNCATE refuses whenever ANY table
  -- outside its list carries a foreign key into one being truncated — the
  -- constraint's existence is what it checks, not whether rows remain. So
  -- emptying profiles first does not help: it still dies with 0A000 "cannot
  -- truncate a table referenced in a foreign key constraint". Listing profiles
  -- would delete the association's own staff accounts, and CASCADE would do the
  -- same silently.
  --
  -- DELETE has no such rule, and adeels carries no refuse_delete trigger — that
  -- guard is on the financial tables, which keep their TRUNCATE. The identity is
  -- then restarted by hand, because that is the part RESTART IDENTITY was doing
  -- and the reason the next عديل must be A-0001.
  --
  -- ORDER MATTERS, and not for the reason it looks like. The truncate comes
  -- FIRST because receivables.created_by references profiles ON DELETE SET NULL,
  -- and that SET NULL is an UPDATE which trg_recv_snapshot_immutable rejects
  -- (created_by is a snapshot column). Deleting profiles while any receivable
  -- survives would therefore abort the whole purge with RUL05. Emptying the
  -- financial tables first leaves nothing for the cascade to touch.
  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivables,
           public.audit_log
    RESTART IDENTITY;

  -- Portal accounts go entirely: their عديل is being erased, so leaving the
  -- profile would leave a dangling scope and my_adeel_id() would answer with a
  -- dead id. auth.users survives, so the same person can sign in again and redeem
  -- a fresh code later.
  DELETE FROM public.profiles WHERE adeel_id IS NOT NULL;

  DELETE FROM public.adeels;

  ALTER TABLE public.adeels ALTER COLUMN id RESTART WITH 1;

  RETURN jsonb_build_object(
    'receivables',   v_recv,
    'payments',      v_pay,
    'allocations',   v_alloc,
    'cashMovements', v_cash,
    'auditEntries',  v_audit,
    'adeels',        v_adeels);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- The عديل portal — issuing and redeeming an access code.
--
-- Two functions, and the split between them is the security boundary: an admin
-- CREATES a code for an عديل, and the عديل REDEEMS it for himself. Nobody can do
-- both halves, and no client ever writes profiles.adeel_id directly —
-- `authenticated` holds no UPDATE on profiles at all.
-- ═════════════════════════════════════════════════════════════════════════════

-- POST /adeels/:id/access-code.  Generates, or regenerates.
--
-- Regenerating REVOKES the previous code (one row per عديل, overwritten) but
-- does NOT sign out someone who already redeemed it: the binding lives on
-- profiles.adeel_id from that moment on. So an admin can reissue freely when a
-- WhatsApp message is lost, without breaking anybody.
--
-- The alphabet omits 0/O/1/I/L/U — the pairs a person mis-reads off a phone
-- screen, and U so no random draw can spell something unfortunate. 30 letters,
-- 12 characters, ~59 bits: not guessable over HTTPS, and readable aloud.
CREATE OR REPLACE FUNCTION public.issue_adeel_code(p_adeel_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_alphabet CONSTANT text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_code text := '';
  v_code_fmt text;
  v_adeel record;
  i int;
BEGIN
  PERFORM public.require_role('admin');

  SELECT id, adeel_code INTO v_adeel FROM public.adeels WHERE id = p_adeel_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  FOR i IN 1..12 LOOP
    -- random() is not cryptographic. It does not need to be: the row is written
    -- under a UNIQUE constraint, the code is delivered out of band, and the
    -- worst case for a predicted code is read-only sight of one man's own
    -- figures. gen_random_bytes would drag in pgcrypto for that.
    v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
  END LOOP;

  -- Grouped for reading aloud. redeem_adeel_code strips the dashes back out, so
  -- what the admin sees and what the عديل types are the same thing.
  v_code_fmt := substr(v_code,1,4) || '-' || substr(v_code,5,4) || '-' || substr(v_code,9,4);

  INSERT INTO public.adeel_access_codes (adeel_id, code, issued_by)
  VALUES (p_adeel_id, v_code, auth.uid())
  ON CONFLICT (adeel_id) DO UPDATE SET
    code = excluded.code, issued_at = now(), issued_by = excluded.issued_by,
    -- Cleared: this is a NEW code, and it has not been redeemed.
    redeemed_at = NULL, redeemed_by = NULL;

  PERFORM public.write_audit('adeel.code.issue',
    format('إصدار رمز دخول للعديل %s', v_adeel.adeel_code), v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', p_adeel_id, 'adeelCode', v_adeel.adeel_code, 'code', v_code_fmt);
END $$;

-- POST /access-code/redeem.  Called by the عديل himself, once, right after he
-- signs in with Google.
--
-- Binds his profile to his row and approves him. From then on my_role() returns
-- NULL for him and my_adeel_id() returns his id, so the RLS policies in
-- 20260811090500 decide everything he can see — this function is never consulted
-- again.
--
-- It refuses anyone who is already staff. Without that check an admin who typed
-- a code would set his own adeel_id, my_role() would start returning NULL, and
-- he would lock himself out of the association's own app — possibly as the last
-- admin, which no other guard would catch because his role never changed.
CREATE OR REPLACE FUNCTION public.redeem_adeel_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_norm  text;
  v_row   record;
  v_me    record;
  v_adeel record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً' USING ERRCODE = 'RUL14';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  IF v_me.role <> 'viewer' THEN
    RAISE EXCEPTION 'هذا الحساب حساب إداري ولا يمكن ربطه بعديل'
      USING ERRCODE = 'RUL14';
  END IF;

  -- Typed by a person off a phone screen: dashes, spaces and lower case are all
  -- expected and none of them are part of the code.
  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));

  SELECT * INTO v_row FROM public.adeel_access_codes WHERE code = v_norm;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رمز الدخول غير صحيح' USING ERRCODE = 'RUL14';
  END IF;

  -- One code, one man. A second person redeeming the same code would get his own
  -- read-only view of someone else's figures — which is a decision for the admin
  -- to make by reissuing, not something a forwarded WhatsApp message should be
  -- able to do.
  IF v_row.redeemed_at IS NOT NULL AND v_row.redeemed_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'هذا الرمز مستعمل بالفعل، اطلب رمزاً جديداً'
      USING ERRCODE = 'RUL14';
  END IF;

  UPDATE public.profiles
     SET adeel_id = v_row.adeel_id,
         status   = 'approved',
         role     = 'viewer'
   WHERE id = auth.uid();

  UPDATE public.adeel_access_codes
     SET redeemed_at = now(), redeemed_by = auth.uid()
   WHERE adeel_id = v_row.adeel_id;

  SELECT adeel_code INTO v_adeel FROM public.adeels WHERE id = v_row.adeel_id;

  PERFORM public.write_audit('adeel.code.redeem',
    format('ربط حساب %s بالعديل %s', v_me.email, v_adeel.adeel_code),
    v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', v_row.adeel_id, 'adeelCode', v_adeel.adeel_code);
END $$;

-- ── Execution grants ─────────────────────────────────────────────────────────
-- Every function re-checks the role internally, so granting EXECUTE broadly to
-- authenticated is safe: a viewer calling register_payment gets RUL00, not a row.
GRANT EXECUTE ON FUNCTION
  public.register_payment(bigint, numeric, pay_method, text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_adeel(bigint, jsonb),
  public.delete_adeel(bigint),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status),
  public.purge_financial_data(text),
  public.purge_all_data(text),
  public.issue_adeel_code(bigint),
  public.redeem_adeel_code(text)
TO authenticated;

-- write_audit is NOT granted: it is an internal helper. Exposing it would let
-- any signed-in user forge trail entries under someone else's name.
