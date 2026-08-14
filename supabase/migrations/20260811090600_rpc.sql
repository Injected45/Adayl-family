-- 20260811090600_rpc.sql — every write in the system.
--
-- These functions are the direct replacement for the nine transactional
-- endpoints. Each is SECURITY DEFINER (so it can write tables the caller holds
-- no privilege on), each pins search_path (so a caller cannot redirect the
-- elevated body at their own schema), and each starts with require_role().
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
-- Endpoint 22 — POST /payments.  THE critical transaction.
--
-- Rule 7: amount > 0, amount <= total outstanding, FIFO oldest period first.
-- Rule 8: exactly one cash movement per approved payment.
--
-- The FOR UPDATE is not decoration. Two treasurers collecting from the same
-- family at the same moment both read a 100 balance and both allocate 60; without
-- the lock the second overwrites the first and 20 vanishes. The lock makes the
-- loser wait, re-read, and fail the outstanding check — which is the correct
-- outcome. ORDER BY inside the locking SELECT also fixes a consistent lock
-- order, so two payments touching overlapping receivables cannot deadlock.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.register_payment(
  p_family_id bigint,
  p_amount    numeric,
  p_method    pay_method,
  p_reference text DEFAULT NULL,
  p_receiver  text DEFAULT NULL,
  p_notes     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  -- Unconstrained numeric, NOT numeric(12,2). Individual amounts are bounded by
  -- the column type, but their SUM is not: a family with enough open periods
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

  IF NOT EXISTS (SELECT 1 FROM public.families WHERE id = p_family_id) THEN
    RAISE EXCEPTION 'FAMILY_NOT_FOUND' USING ERRCODE = 'RUL07';
  END IF;

  -- Lock every open receivable for this family, oldest first. Once locked, no
  -- other transaction can move them for the rest of this one, so the total below
  -- and the loop further down both read the same reality — which is the whole
  -- point. ORDER BY also fixes a consistent lock acquisition order.
  PERFORM 1
    FROM public.receivables r2
   WHERE r2.family_id = p_family_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0
   ORDER BY r2.period ASC, r2.id ASC
     FOR UPDATE;

  SELECT coalesce(sum(r2.balance), 0) INTO v_outstanding
    FROM public.receivables r2
   WHERE r2.family_id = p_family_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0;

  IF v_outstanding <= 0 THEN
    RAISE EXCEPTION 'Rule 7: family has no outstanding balance'
      USING ERRCODE = 'RUL07';
  END IF;

  IF p_amount > v_outstanding THEN
    RAISE EXCEPTION 'Rule 7: amount % exceeds outstanding balance %',
      p_amount, v_outstanding USING ERRCODE = 'RUL07';
  END IF;

  INSERT INTO public.payments (family_id, amount, method, reference, receiver,
                               notes, created_by)
  VALUES (p_family_id, p_amount, p_method, p_reference, p_receiver, p_notes,
          auth.uid())
  RETURNING id, receipt_no INTO v_payment_id, v_receipt;

  v_remaining := p_amount;

  FOR r IN SELECT r2.id, r2.period, r2.balance
             FROM public.receivables r2
            WHERE r2.family_id = p_family_id
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
    (payment_id, family_id, amount, method, occurred_at)
  SELECT id, family_id, amount, method, paid_at
    FROM public.payments WHERE id = v_payment_id;

  PERFORM public.write_audit('payment.register',
    format('تحصيل %s من العائلة %s', p_amount::text, p_family_id),
    v_receipt);

  RETURN jsonb_build_object(
    'paymentId', v_payment_id,
    'receiptNo', v_receipt,
    'familyId',  p_family_id,
    'amount',    p_amount::text,
    'method',    p_method,
    'allocations', v_allocs);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 23 — POST /payments/:id/cancel.  The second critical transaction.
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
-- Endpoint 18 — POST /receivables/generate.
-- Rules 1, 3, 4, 5: eligibility at period end, total > 0 or skip, one live row
-- per (family, period), snapshot the settings.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.generate_period(p_period char(7))
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  s           record;
  f           record;
  v_end       date;
  v_total     numeric(12,2);
  v_father    record;
  v_recv_id   bigint;
  v_created   int := 0;
  v_skipped   int := 0;
  v_sons      int;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'BAD_PERIOD: %', p_period USING ERRCODE = 'RUL04';
  END IF;

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_end := (to_date(p_period || '-01', 'YYYY-MM-DD')
            + interval '1 month - 1 day')::date;

  FOR f IN SELECT id FROM public.families ORDER BY id LOOP
    SELECT * INTO v_father FROM public.members
      WHERE family_id = f.id AND kind = 'father';

    -- No father row means no one to bill and no name to snapshot.
    IF NOT FOUND THEN v_skipped := v_skipped + 1; CONTINUE; END IF;

    -- Rule 1: eligibility is age at PERIOD END, and member status overrides age
    -- — a موقوف or متوفى son is not billable however old he is.
    SELECT count(*) INTO v_sons FROM public.members m
     WHERE m.family_id = f.id AND m.kind = 'son' AND m.status = 'نشط'
       AND m.dob IS NOT NULL
       AND extract(year FROM age(v_end, m.dob)) >= s.eligibility_age;

    v_total := (CASE WHEN v_father.status = 'نشط' THEN s.father_fee ELSE 0 END)
             + s.son_fee * v_sons;

    -- Rule 3: nothing to charge means no row at all, not a zero row.
    IF v_total <= 0 THEN v_skipped := v_skipped + 1; CONTINUE; END IF;

    -- Rule 4 as idempotency: re-running the same period skips instead of
    -- raising a duplicate. The partial index is what makes this safe under
    -- concurrency, so two admins pressing the button together cannot double-bill.
    INSERT INTO public.receivables (
      family_id, period, period_end, father_fee, son_fee, father_member_id,
      father_name, eligibility_age_snapshot, warning_months_snapshot, total,
      created_by)
    VALUES (
      f.id, p_period, v_end, s.father_fee, s.son_fee, v_father.id,
      v_father.full_name, s.eligibility_age, s.warning_months, v_total,
      auth.uid())
    ON CONFLICT (family_id, period) WHERE status <> 'ملغي' DO NOTHING
    RETURNING id INTO v_recv_id;

    IF v_recv_id IS NULL THEN v_skipped := v_skipped + 1; CONTINUE; END IF;

    -- Snapshot who was billed. SUM(fee_amount) = total is the invariant the
    -- reconciler checks.
    IF v_father.status = 'نشط' THEN
      INSERT INTO public.receivable_lines
        (receivable_id, member_id, member_kind, member_name,
         member_national_id, fee_amount)
      VALUES (v_recv_id, v_father.id, 'father', v_father.full_name,
              v_father.national_id, s.father_fee);
    END IF;

    INSERT INTO public.receivable_lines
      (receivable_id, member_id, member_kind, member_name,
       member_national_id, fee_amount)
    SELECT v_recv_id, m.id, 'son', m.full_name, m.national_id, s.son_fee
      FROM public.members m
     WHERE m.family_id = f.id AND m.kind = 'son' AND m.status = 'نشط'
       AND m.dob IS NOT NULL
       AND extract(year FROM age(v_end, m.dob)) >= s.eligibility_age;

    v_created := v_created + 1;
    v_recv_id := NULL;
  END LOOP;

  PERFORM public.write_audit('receivables.generate',
    format('إنشاء استحقاقات %s: %s سجل', p_period, v_created), p_period);

  RETURN jsonb_build_object('period', p_period, 'created', v_created,
                            'skipped', v_skipped);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 19 — POST /receivables/auto-close.
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
  -- PREVIOUS month, not this one. index.html labels the button with
  -- previousPeriod() (line 452) — the current month is not closed until it ends.
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
-- Endpoints 11 and 13 — POST /families, PUT /families/:id.
-- Rule 10: national_id unique across ALL members, DOB not future.
--
-- Sons arrive as a jsonb array. A son absent from the array is removed, and the
-- removal must be applied BEFORE the inserts, otherwise re-using the national ID
-- of a son you just removed trips uq_members_national_id — a bug this project
-- already hit once against MySQL.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.save_family(
  p_family_id bigint,      -- NULL to create
  p_father    jsonb,
  p_sons      jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_family_id bigint := p_family_id;
  v_code      text;
  v_keep      bigint[];
  son         jsonb;
  v_son_id    bigint;
BEGIN
  PERFORM public.require_role('financeManager');

  IF v_family_id IS NULL THEN
    INSERT INTO public.families (created_by, updated_by)
    VALUES (auth.uid(), auth.uid())
    RETURNING id INTO v_family_id;
  ELSE
    UPDATE public.families SET updated_by = auth.uid() WHERE id = v_family_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'FAMILY_NOT_FOUND' USING ERRCODE = 'RUL10';
    END IF;
  END IF;

  -- Father: upsert on the one-father partial index.
  INSERT INTO public.members (
    family_id, kind, full_name, national_id, phone, subscription_no, dob,
    nationality, workplace, registered_at, status)
  VALUES (
    v_family_id, 'father',
    p_father ->> 'fullName', p_father ->> 'nationalId',
    p_father ->> 'phone', p_father ->> 'subscriptionNo',
    nullif(p_father ->> 'dob', '')::date,
    coalesce(nullif(p_father ->> 'nationality', ''), 'ليبي'),
    p_father ->> 'workplace',
    coalesce(nullif(p_father ->> 'registeredAt', '')::date, current_date),
    coalesce(nullif(p_father ->> 'status', '')::member_status, 'نشط'))
  ON CONFLICT (family_id) WHERE kind = 'father' DO UPDATE SET
    full_name = excluded.full_name, national_id = excluded.national_id,
    phone = excluded.phone, subscription_no = excluded.subscription_no,
    dob = excluded.dob, nationality = excluded.nationality,
    workplace = excluded.workplace, status = excluded.status;

  -- Remove first, then insert. Order is the whole point.
  SELECT coalesce(array_agg((s ->> 'id')::bigint), '{}'::bigint[]) INTO v_keep
    FROM jsonb_array_elements(p_sons) s WHERE s ->> 'id' IS NOT NULL;

  DELETE FROM public.members
   WHERE family_id = v_family_id AND kind = 'son'
     AND NOT (id = ANY (v_keep))
     -- A son who has been billed cannot vanish: the receivable line references
     -- him. FK is ON DELETE SET NULL, which would silently orphan the line, so
     -- refuse instead and let the caller mark him موقوف.
     AND NOT EXISTS (SELECT 1 FROM public.receivable_lines l WHERE l.member_id = members.id);

  FOR son IN SELECT * FROM jsonb_array_elements(p_sons) LOOP
    v_son_id := nullif(son ->> 'id', '')::bigint;
    IF v_son_id IS NULL THEN
      INSERT INTO public.members (
        family_id, kind, full_name, national_id, phone, dob, nationality,
        workplace, registered_at, status)
      VALUES (
        v_family_id, 'son', son ->> 'fullName', son ->> 'nationalId',
        son ->> 'phone', nullif(son ->> 'dob', '')::date,
        coalesce(nullif(son ->> 'nationality', ''), 'ليبي'),
        son ->> 'workplace',
        coalesce(nullif(son ->> 'registeredAt', '')::date, current_date),
        coalesce(nullif(son ->> 'status', '')::member_status, 'نشط'));
    ELSE
      UPDATE public.members SET
        full_name = son ->> 'fullName', national_id = son ->> 'nationalId',
        phone = son ->> 'phone', dob = nullif(son ->> 'dob', '')::date,
        nationality = coalesce(nullif(son ->> 'nationality', ''), 'ليبي'),
        workplace = son ->> 'workplace',
        status = coalesce(nullif(son ->> 'status', '')::member_status, 'نشط')
       WHERE id = v_son_id AND family_id = v_family_id AND kind = 'son';
    END IF;
  END LOOP;

  SELECT family_code INTO v_code FROM public.families WHERE id = v_family_id;

  PERFORM public.write_audit(
    CASE WHEN p_family_id IS NULL THEN 'family.create' ELSE 'family.update' END,
    format('%s %s', CASE WHEN p_family_id IS NULL THEN 'إضافة' ELSE 'تعديل' END,
           v_code), v_code);

  RETURN jsonb_build_object('familyId', v_family_id, 'familyCode', v_code);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 8 — PUT /settings.  Rule 5's counterpart: changing these must not
-- touch history, which trg_recv_snapshot_immutable guarantees independently.
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
    father_fee       = coalesce((p_patch ->> 'fatherFee')::numeric, father_fee),
    son_fee          = coalesce((p_patch ->> 'sonFee')::numeric, son_fee),
    eligibility_age  = coalesce((p_patch ->> 'eligibilityAge')::smallint, eligibility_age),
    warning_months   = coalesce((p_patch ->> 'warningMonths')::smallint, warning_months),
    system_start     = coalesce((p_patch ->> 'systemStart')::date, system_start),
    treasurer_name        = coalesce(p_patch ->> 'treasurerName', treasurer_name),
    treasurer_national_id = coalesce(p_patch ->> 'treasurerNationalId', treasurer_national_id),
    treasurer_phone       = coalesce(p_patch ->> 'treasurerPhone', treasurer_phone),
    finance_manager_name        = coalesce(p_patch ->> 'financeName', finance_manager_name),
    finance_manager_national_id = coalesce(p_patch ->> 'financeNationalId', finance_manager_national_id),
    finance_manager_phone       = coalesce(p_patch ->> 'financePhone', finance_manager_phone),
    updated_by = auth.uid()
  WHERE id = 1
  RETURNING * INTO v_row;

  PERFORM public.write_audit('settings.update', 'تحديث إعدادات الجمعية', 'settings');

  RETURN jsonb_build_object(
    'associationName', v_row.association_name, 'currency', v_row.currency,
    'fatherFee', v_row.father_fee::text, 'sonFee', v_row.son_fee::text,
    'eligibilityAge', v_row.eligibility_age, 'warningMonths', v_row.warning_months,
    'systemStart', v_row.system_start);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 6 — PATCH /users/:id.  Self-elevation and last-admin are blocked by
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
-- WHY TRUNCATE AND NOT DELETE: the five financial tables carry BEFORE DELETE
-- triggers (refuse_delete) and audit_log carries refuse_audit_change. TRUNCATE
-- fires neither — only AFTER TRUNCATE statement triggers, and none are defined.
-- The alternative was ALTER TABLE … DISABLE TRIGGER around the DELETEs, which
-- takes the same ACCESS EXCLUSIVE lock but leaves a window in which the rule-9
-- guard is genuinely off. TRUNCATE never disarms anything, so a failure here
-- cannot leave the table unprotected. It also resets the identity sequences,
-- which is what makes the next receipt PAY-000001 instead of continuing the
-- practice run's numbering.
--
-- So rule 9 now reads: nothing can be hard-deleted except through this function,
-- which is admin-only, demands a typed confirmation, and is one transaction.
-- `authenticated` holds no TRUNCATE privilege on any table (see
-- 20260811091200_function_lockdown.sql), so this really is the only route.
--
-- WHAT SURVIVES: families, members, association_settings, profiles. The purge is
-- financial only — the directory is what the association spent the most effort
-- entering, and rebuilding it is not what "clear the figures" means.
--
-- WHAT DOES NOT: audit_log is truncated too, and NO entry is written afterwards.
-- That is a deliberate choice by the association's admin, and it is worth being
-- explicit about the cost: rule 12 makes the trail append-only precisely so an
-- administrator cannot quietly rewrite history, and this function is a hole in
-- that. After it runs there is no record inside the database that it ran, or of
-- anything that preceded it. If that is ever regretted, the fix is one line —
-- move the audit_log truncate out and write a 'data.purge' entry at the end.
--
-- No ordering hazard in the TRUNCATE list: every FK pointing INTO these six
-- tables originates in one of the six, so Postgres does not demand CASCADE.
-- Adding a seventh table that references payments without listing it here would
-- fail loudly rather than silently skip.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.purge_financial_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv  bigint;
  v_lines bigint;
  v_pay   bigint;
  v_alloc bigint;
  v_cash  bigint;
  v_audit bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- The typed phrase. Not UX politeness: register_payment and save_family are
  -- reachable by anyone who can read the anon key out of the APK, and so is
  -- this. require_role stops a treasurer; the phrase stops an admin's own
  -- mis-click and a replayed request. It must match wire_values.dart exactly.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح نهائي' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  -- Counted before, because TRUNCATE reports no row count. These tables are
  -- small enough that six counts cost nothing next to the truncate itself.
  SELECT count(*) INTO v_recv  FROM public.receivables;
  SELECT count(*) INTO v_lines FROM public.receivable_lines;
  SELECT count(*) INTO v_pay   FROM public.payments;
  SELECT count(*) INTO v_alloc FROM public.payment_allocations;
  SELECT count(*) INTO v_cash  FROM public.cash_movements;
  SELECT count(*) INTO v_audit FROM public.audit_log;

  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivable_lines,
           public.receivables,
           public.audit_log
    RESTART IDENTITY;

  RETURN jsonb_build_object(
    'receivables',     v_recv,
    'receivableLines', v_lines,
    'payments',        v_pay,
    'allocations',     v_alloc,
    'cashMovements',   v_cash,
    'auditEntries',    v_audit);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Purge, the wider one — the directory as well as the money.
--
-- WHY IT CANNOT BE "FAMILIES ONLY": receivables, payments and cash_movements all
-- carry `family_id … ON DELETE RESTRICT`, and members does too. A purge that
-- removed families while a single receipt still pointed at one would be refused
-- by the storage engine, so the choice is between erasing the financial rows
-- alongside them or refusing whenever any exist. Refusing would mean the button
-- fails for exactly the person who wants it — an admin clearing a trial run —
-- and would leave him pressing two buttons in an order nothing tells him about.
-- So this is deliberately a SUPERSET of purge_financial_data, and the screen
-- says so rather than surprising him after the fact.
--
-- The separate confirmation phrase is the point of having two functions at all.
-- Both are admin-only and both truncate; what stops a mis-click from erasing the
-- directory when only the figures were meant is that 'مسح نهائي' does not
-- satisfy this function, and the app cannot send a phrase the admin did not type.
--
-- WHAT SURVIVES: association_settings and profiles. Wiping profiles would strand
-- the association outside its own app — the last-admin guard exists precisely to
-- make that unreachable — and settings are configuration, not data.
--
-- Order and CASCADE: every FK pointing INTO these eight originates in one of the
-- eight (members → families, receivable_lines → members, receivables →
-- father_member_id, and the four financial links), so Postgres does not demand
-- CASCADE. A ninth table referencing families and left off this list would fail
-- loudly instead of being silently skipped.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.purge_all_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv   bigint;
  v_lines  bigint;
  v_pay    bigint;
  v_alloc  bigint;
  v_cash   bigint;
  v_audit  bigint;
  v_fam    bigint;
  v_mem    bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- Distinct from purge_financial_data's phrase ON PURPOSE. See above.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح كل البيانات' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  SELECT count(*) INTO v_recv   FROM public.receivables;
  SELECT count(*) INTO v_lines  FROM public.receivable_lines;
  SELECT count(*) INTO v_pay    FROM public.payments;
  SELECT count(*) INTO v_alloc  FROM public.payment_allocations;
  SELECT count(*) INTO v_cash   FROM public.cash_movements;
  SELECT count(*) INTO v_audit  FROM public.audit_log;
  SELECT count(*) INTO v_fam    FROM public.families;
  SELECT count(*) INTO v_mem    FROM public.members;

  -- ── Why families and members are DELETEd while the six financial tables are
  -- TRUNCATEd ────────────────────────────────────────────────────────────────
  -- profiles.family_id references families, and TRUNCATE refuses whenever ANY
  -- table outside its list carries a foreign key into one being truncated —
  -- the constraint's existence is what it checks, not whether rows remain. So
  -- emptying profiles first does not help: it still dies with 0A000 "cannot
  -- truncate a table referenced in a foreign key constraint". Listing profiles
  -- would delete the association's own staff accounts, and CASCADE would do the
  -- same silently.
  --
  -- DELETE has no such rule, and neither families nor members carries a
  -- refuse_delete trigger — that guard is on the five financial tables, which
  -- keep their TRUNCATE. The identities are then restarted by hand, because
  -- that is the part RESTART IDENTITY was doing and the reason the next family
  -- must be F-0001.
  --
  -- Heads of family go first and go entirely: their family is being erased, so
  -- leaving the profile would leave a dangling scope. auth.users survives, so
  -- the same person can sign in again and redeem a fresh code later.
  DELETE FROM public.profiles WHERE family_id IS NOT NULL;

  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivable_lines,
           public.receivables,
           public.audit_log
    RESTART IDENTITY;

  DELETE FROM public.members;
  DELETE FROM public.families;

  ALTER TABLE public.members  ALTER COLUMN id RESTART WITH 1;
  ALTER TABLE public.families ALTER COLUMN id RESTART WITH 1;

  RETURN jsonb_build_object(
    'receivables',     v_recv,
    'receivableLines', v_lines,
    'payments',        v_pay,
    'allocations',     v_alloc,
    'cashMovements',   v_cash,
    'auditEntries',    v_audit,
    'families',        v_fam,
    'members',         v_mem);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- The family portal — issuing and redeeming an access code.
--
-- Two functions, and the split between them is the security boundary: an admin
-- CREATES a code for a family, and the head of family REDEEMS it for himself.
-- Nobody can do both halves, and no client ever writes profiles.family_id
-- directly — `authenticated` holds no UPDATE on profiles at all.
-- ═════════════════════════════════════════════════════════════════════════════

-- Endpoint: POST /families/:id/access-code.  Generates, or regenerates.
--
-- Regenerating REVOKES the previous code (one row per family, overwritten) but
-- does NOT sign out a head of family who already redeemed it: the binding lives
-- on profiles.family_id from that moment on. So an admin can reissue freely when
-- a WhatsApp message is lost, without breaking anybody.
--
-- The alphabet omits 0/O/1/I/L/U — the pairs a person mis-reads off a phone
-- screen, and U so no random draw can spell something unfortunate. 27 letters,
-- 12 characters, ~57 bits: not guessable over HTTPS, and readable aloud.
CREATE OR REPLACE FUNCTION public.issue_family_code(p_family_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_alphabet CONSTANT text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_code text := '';
  v_code_fmt text;
  v_family record;
  i int;
BEGIN
  PERFORM public.require_role('admin');

  SELECT id, family_code INTO v_family FROM public.families WHERE id = p_family_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAMILY_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  FOR i IN 1..12 LOOP
    -- random() is not cryptographic. It does not need to be: the row is written
    -- under a UNIQUE constraint, the code is delivered out of band, and the
    -- worst case for a predicted code is read-only sight of one family's own
    -- figures. gen_random_bytes would drag in pgcrypto for that.
    v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
  END LOOP;

  -- Grouped for reading aloud. redeem_family_code strips the dashes back out,
  -- so what the admin sees and what the head of family types are the same thing.
  v_code_fmt := substr(v_code,1,4) || '-' || substr(v_code,5,4) || '-' || substr(v_code,9,4);

  INSERT INTO public.family_access_codes (family_id, code, issued_by)
  VALUES (p_family_id, v_code, auth.uid())
  ON CONFLICT (family_id) DO UPDATE SET
    code = excluded.code, issued_at = now(), issued_by = excluded.issued_by,
    -- Cleared: this is a NEW code, and it has not been redeemed.
    redeemed_at = NULL, redeemed_by = NULL;

  PERFORM public.write_audit('family.code.issue',
    format('إصدار رمز دخول للعائلة %s', v_family.family_code), v_family.family_code);

  RETURN jsonb_build_object(
    'familyId', p_family_id, 'familyCode', v_family.family_code, 'code', v_code_fmt);
END $$;

-- Endpoint: POST /access-code/redeem.  Called by the head of family himself,
-- once, right after he signs in with Google.
--
-- Binds his profile to the family and approves him. From then on my_role()
-- returns NULL for him and my_family_id() returns the family, so the RLS
-- policies in 20260811090500 decide everything he can see — this function is
-- never consulted again.
--
-- It refuses anyone who is already staff. Without that check an admin who typed
-- a code would set his own family_id, my_role() would start returning NULL, and
-- he would lock himself out of the association's own app — possibly as the last
-- admin, which no other guard would catch because his role never changed.
CREATE OR REPLACE FUNCTION public.redeem_family_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_norm   text;
  v_row    record;
  v_me     record;
  v_family record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً' USING ERRCODE = 'RUL14';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  IF v_me.role <> 'viewer' THEN
    RAISE EXCEPTION 'هذا الحساب حساب إداري ولا يمكن ربطه بعائلة'
      USING ERRCODE = 'RUL14';
  END IF;

  -- Typed by a person off a phone screen: dashes, spaces and lower case are all
  -- expected and none of them are part of the code.
  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));

  SELECT * INTO v_row FROM public.family_access_codes WHERE code = v_norm;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رمز الدخول غير صحيح' USING ERRCODE = 'RUL14';
  END IF;

  -- One code, one household. A second person redeeming the same code would get
  -- his own read-only view of the same family — which is a decision for the
  -- admin to make by reissuing, not something a forwarded WhatsApp message
  -- should be able to do.
  IF v_row.redeemed_at IS NOT NULL AND v_row.redeemed_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'هذا الرمز مستعمل بالفعل، اطلب رمزاً جديداً'
      USING ERRCODE = 'RUL14';
  END IF;

  UPDATE public.profiles
     SET family_id = v_row.family_id,
         status    = 'approved',
         role      = 'viewer'
   WHERE id = auth.uid();

  UPDATE public.family_access_codes
     SET redeemed_at = now(), redeemed_by = auth.uid()
   WHERE family_id = v_row.family_id;

  SELECT family_code INTO v_family FROM public.families WHERE id = v_row.family_id;

  PERFORM public.write_audit('family.code.redeem',
    format('ربط حساب %s بالعائلة %s', v_me.email, v_family.family_code),
    v_family.family_code);

  RETURN jsonb_build_object(
    'familyId', v_row.family_id, 'familyCode', v_family.family_code);
END $$;

-- ── Execution grants ─────────────────────────────────────────────────────────
-- Every function re-checks the role internally, so granting EXECUTE broadly to
-- authenticated is safe: a viewer calling register_payment gets RUL00, not a row.
GRANT EXECUTE ON FUNCTION
  public.register_payment(bigint, numeric, pay_method, text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_family(bigint, jsonb, jsonb),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status),
  public.purge_financial_data(text),
  public.purge_all_data(text),
  public.issue_family_code(bigint),
  public.redeem_family_code(text)
TO authenticated;

-- write_audit is NOT granted: it is an internal helper. Exposing it would let
-- any signed-in user forge trail entries under someone else's name.
