-- ============================================================================
--  جمعية العدايل — PATCH: officials chosen from the register, and the
--  association's bank account.  2026-08-16.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  ⚠ THIS FILE REPLACES PATCH_20260816_bank_account.sql.
--    It contains everything that one did, plus the officials change. Run THIS
--    one and ignore the other — a single cumulative patch is why there is no
--    "which order do I run them in" question to get wrong. Running it after the
--    bank one is harmless; running the bank one AFTER this would undo the
--    officials half, which is exactly the trap this consolidation removes.
--
--  WHAT IT CHANGES
--
--  1. THE TWO OFFICIALS ARE NOW عدايل, PICKED FROM THE REGISTER.
--     أمين الصندوق and المدير المالي are elected from the members, so each post
--     is an `adeels` row rather than a typed name:
--
--       association_settings.treasurer_adeel_id        → FK to adeels
--       association_settings.finance_manager_adeel_id  → FK to adeels
--       ck_settings_distinct_officials                 → one man, not both posts
--
--     The name and phone columns stay, as a SNAPSHOT of the chosen man's row.
--     They are not replaced by a join, deliberately: v_officials is read by an
--     عديل on the PORTAL, and RLS shows him only his own row in `adeels`, so a
--     join would blank the one screen that tells him who to pay. save_adeel
--     refreshes the snapshot whenever an عديل holding a post is renamed, so it
--     cannot drift.
--
--     v_officials is therefore UNCHANGED, and so is every consumer of it.
--
--  2. THE ASSOCIATION'S BANK ACCOUNT (from the superseded patch).
--       association_settings.bank_account_no / _name   → where to transfer
--       payments.bank_account_no / _name               → where THIS one went
--     register_payment snapshots the pair from settings. The client never sends
--     them: the anon key ships in the APK, so anything a client could send, a
--     hostile client could forge — and this says where the money went.
--
--  3. update_settings ALSO FIXES A SILENT SAVE BUG that predates all of this.
--     It reads the officials as FLAT keys (`p_patch ->> 'treasurerName'`) while
--     api_settings sends them NESTED, so the app posting the nested shape left
--     all four lookups NULL, coalesce kept the old row, and the two names never
--     saved while every other field did. The app now posts the flat shape; this
--     patch is what the flat shape talks to.
--
--  ⚠ ADDITIVE ONLY — verify before running
--       * no DROP SCHEMA / DROP TABLE / DROP FUNCTION / DROP TRIGGER
--       * no TRUNCATE, no DELETE
--       * no function SIGNATURE changes, so no grant is dropped and the
--         lockdown allow-list is untouched
--       * nothing referencing auth.users, profiles or trg_auth_user_created
--         except the read-only health check after COMMIT
--
--    RESET_AND_APPLY.sql is what broke first-time Google sign-in before —
--    DROP SCHEMA public CASCADE removes a trigger on auth.users whose function
--    lives in `public`. Nothing here drops anything, and assert_signin_intact()
--    below refuses to COMMIT if sign-in is not working.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes.
--
--  SAFE TO RUN TWICE. Columns and constraints are added conditionally and
--  CREATE OR REPLACE is idempotent.
-- ============================================================================

BEGIN;

-- == 1. Settings: the two posts, and the bank account ========================
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS treasurer_adeel_id       bigint;
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS finance_manager_adeel_id bigint;
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS bank_account_no   text NOT NULL DEFAULT '';
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS bank_account_name text NOT NULL DEFAULT '';

-- ON DELETE SET NULL, not RESTRICT: an عديل with no financial history can be
-- deleted, and holding a post must not turn that into a refusal nobody can
-- explain. The post falls vacant and the snapshotted name stays readable.
DO $fk$
BEGIN
  ALTER TABLE public.association_settings
    ADD CONSTRAINT fk_settings_treasurer
      FOREIGN KEY (treasurer_adeel_id) REFERENCES public.adeels(id)
      ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
END $fk$;

DO $fk2$
BEGIN
  ALTER TABLE public.association_settings
    ADD CONSTRAINT fk_settings_finance
      FOREIGN KEY (finance_manager_adeel_id) REFERENCES public.adeels(id)
      ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
END $fk2$;

-- The "no overlap" rule the association asked for, made structural.
DO $ck$
BEGIN
  ALTER TABLE public.association_settings
    ADD CONSTRAINT ck_settings_distinct_officials
      CHECK (treasurer_adeel_id IS NULL
          OR finance_manager_adeel_id IS NULL
          OR treasurer_adeel_id <> finance_manager_adeel_id);
EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL;
END $ck$;

-- == 2. Payments: where THIS transfer actually went ==========================
-- Nullable, unlike the settings pair: NULL means cash, or a transfer taken
-- before any account was configured. Defaulting to '' would erase that
-- distinction on every historical row.
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_account_no   text;
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_account_name text;

-- == 3. register_payment — snapshots the account, signature UNCHANGED ========
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
  v_acct_no     text;
  v_acct_name   text;
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

  -- The receiving account, snapshotted for a تحويل مصرفي and left NULL for
  -- cash. Read from settings HERE rather than accepted as a parameter: the
  -- account is the association's own, so the caller has no business naming it,
  -- and the anon key ships inside the APK — anything the client could send, a
  -- hostile client could forge. Taking it server-side also means no signature
  -- change, so nothing that calls register_payment has to be touched.
  IF p_method = 'تحويل مصرفي' THEN
    SELECT nullif(btrim(bank_account_no), ''),
           nullif(btrim(bank_account_name), '')
      INTO v_acct_no, v_acct_name
      FROM public.association_settings WHERE id = 1;
  END IF;

  INSERT INTO public.payments (adeel_id, amount, method, reference, receiver,
                               notes, created_by,
                               bank_account_no, bank_account_name)
  VALUES (p_adeel_id, p_amount, p_method, p_reference, p_receiver, p_notes,
          auth.uid(), v_acct_no, v_acct_name)
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

-- == 4. update_settings — the officials, the account, and the audit ==========
CREATE OR REPLACE FUNCTION public.update_settings(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_old     record;
  v_row     record;
  v_changes text[] := '{}';
  v_t_id    bigint;
  v_f_id    bigint;
  v_t       record;
  v_f       record;
BEGIN
  PERFORM public.require_role('admin');

  SELECT * INTO v_old FROM public.association_settings WHERE id = 1 FOR UPDATE;

  -- ── Who holds each post ───────────────────────────────────────────────────
  -- Both officials are عدايل, chosen from the register rather than typed. The
  -- id is what is being set; the name and phone are copied from his row below,
  -- so the association can never end up with three spellings of one man across
  -- a year of settings edits.
  --
  -- `p_patch ? key` distinguishes "not mentioned" from "explicitly cleared".
  -- Using ->> alone would make a null indistinguishable from an omission, and
  -- vacating a post would become impossible.
  v_t_id := CASE WHEN p_patch ? 'treasurerAdeelId'
                 THEN nullif(p_patch ->> 'treasurerAdeelId', '')::bigint
                 ELSE v_old.treasurer_adeel_id END;
  v_f_id := CASE WHEN p_patch ? 'financeAdeelId'
                 THEN nullif(p_patch ->> 'financeAdeelId', '')::bigint
                 ELSE v_old.finance_manager_adeel_id END;

  -- The overlap the association asked to make impossible. ck_settings_distinct_
  -- officials enforces it in the storage engine too; this exists so the admin
  -- gets a sentence he can act on instead of a constraint name.
  IF v_t_id IS NOT NULL AND v_t_id = v_f_id THEN
    RAISE EXCEPTION 'لا يمكن أن يكون أمين الصندوق والمدير المالي عديلاً واحداً'
      USING ERRCODE = 'RUL16';
  END IF;

  -- The FK would refuse an unknown id anyway; catching it here names WHICH post
  -- was wrong, which the constraint cannot.
  IF v_t_id IS NOT NULL THEN
    SELECT full_name, phone INTO v_t FROM public.adeels WHERE id = v_t_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'أمين الصندوق المختار ليس في سجل العدايل'
        USING ERRCODE = 'RUL16';
    END IF;
  END IF;
  IF v_f_id IS NOT NULL THEN
    SELECT full_name, phone INTO v_f FROM public.adeels WHERE id = v_f_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'المدير المالي المختار ليس في سجل العدايل'
        USING ERRCODE = 'RUL16';
    END IF;
  END IF;

  UPDATE public.association_settings SET
    association_name = coalesce(p_patch ->> 'associationName', association_name),
    currency         = coalesce(p_patch ->> 'currency', currency),
    member_fee       = coalesce((p_patch ->> 'memberFee')::numeric, member_fee),
    system_start     = coalesce((p_patch ->> 'systemStart')::date, system_start),
    -- The post, then the snapshot of whoever holds it. When an عديل is chosen
    -- his row IS the name and phone; the free-text keys are still honoured when
    -- no عديل is set, so a project that has not picked anyone yet keeps working
    -- exactly as before.
    treasurer_adeel_id    = v_t_id,
    treasurer_name        = CASE WHEN v_t_id IS NOT NULL THEN v_t.full_name
                                 ELSE coalesce(p_patch ->> 'treasurerName',
                                               treasurer_name) END,
    treasurer_phone       = CASE WHEN v_t_id IS NOT NULL
                                 THEN coalesce(v_t.phone, '')
                                 ELSE coalesce(p_patch ->> 'treasurerPhone',
                                               treasurer_phone) END,
    finance_manager_adeel_id = v_f_id,
    finance_manager_name  = CASE WHEN v_f_id IS NOT NULL THEN v_f.full_name
                                 ELSE coalesce(p_patch ->> 'financeName',
                                               finance_manager_name) END,
    finance_manager_phone = CASE WHEN v_f_id IS NOT NULL
                                 THEN coalesce(v_f.phone, '')
                                 ELSE coalesce(p_patch ->> 'financePhone',
                                               finance_manager_phone) END,
    bank_account_no             = coalesce(p_patch ->> 'bankAccountNo', bank_account_no),
    bank_account_name           = coalesce(p_patch ->> 'bankAccountName', bank_account_name),
    updated_by = auth.uid()
  WHERE id = 1
  RETURNING * INTO v_row;

  -- The two financially load-bearing fields first, then the rest. IS DISTINCT
  -- FROM so a field the patch omitted (coalesce kept it) records nothing.
  IF v_row.member_fee IS DISTINCT FROM v_old.member_fee THEN
    v_changes := v_changes || format('الاشتراك الشهري من %s إلى %s',
                                     v_old.member_fee::text, v_row.member_fee::text);
  END IF;
  IF v_row.system_start IS DISTINCT FROM v_old.system_start THEN
    v_changes := v_changes || format('بداية النظام من %s إلى %s',
                                     to_char(v_old.system_start, 'YYYY-MM-DD'),
                                     to_char(v_row.system_start, 'YYYY-MM-DD'));
  END IF;
  IF v_row.currency IS DISTINCT FROM v_old.currency THEN
    v_changes := v_changes || format('العملة من %s إلى %s',
                                     v_old.currency, v_row.currency);
  END IF;
  IF v_row.association_name IS DISTINCT FROM v_old.association_name THEN
    v_changes := v_changes || format('اسم الجمعية من %s إلى %s',
                                     v_old.association_name, v_row.association_name);
  END IF;
  -- The account number is recorded in full, both before and after. It is the
  -- one setting where a single wrong digit sends the association's collections
  -- to a stranger, and "someone changed the bank account" without saying what
  -- it was is not a trail anyone can act on.
  IF v_row.bank_account_no IS DISTINCT FROM v_old.bank_account_no THEN
    v_changes := v_changes || format('رقم الحساب المصرفي من %s إلى %s',
                                     coalesce(nullif(v_old.bank_account_no, ''), '—'),
                                     coalesce(nullif(v_row.bank_account_no, ''), '—'));
  END IF;
  IF v_row.bank_account_name IS DISTINCT FROM v_old.bank_account_name THEN
    v_changes := v_changes || format('اسم صاحب الحساب من %s إلى %s',
                                     coalesce(nullif(v_old.bank_account_name, ''), '—'),
                                     coalesce(nullif(v_row.bank_account_name, ''), '—'));
  END IF;
  IF v_row.treasurer_name  IS DISTINCT FROM v_old.treasurer_name
  OR v_row.treasurer_phone IS DISTINCT FROM v_old.treasurer_phone THEN
    v_changes := v_changes || 'بيانات أمين الصندوق';
  END IF;
  IF v_row.finance_manager_name  IS DISTINCT FROM v_old.finance_manager_name
  OR v_row.finance_manager_phone IS DISTINCT FROM v_old.finance_manager_phone THEN
    v_changes := v_changes || 'بيانات المدير المالي';
  END IF;

  -- A no-op save still writes an entry. "An admin opened settings and saved
  -- without changing anything" is itself worth being able to see, and a silent
  -- write would make the trail's gaps ambiguous.
  PERFORM public.write_audit('settings.update',
    CASE WHEN cardinality(v_changes) = 0
         THEN 'تحديث إعدادات الجمعية: لا تغيير'
         ELSE 'تحديث إعدادات الجمعية: ' || array_to_string(v_changes, '، ')
    END,
    'settings');

  RETURN jsonb_build_object(
    'associationName', v_row.association_name, 'currency', v_row.currency,
    'memberFee', v_row.member_fee::text,
    'systemStart', v_row.system_start);
END $$;

-- == 5. save_adeel — keeps the officials' snapshot from going stale ==========
-- Renaming an عديل who holds a post rewrites the copy of his name in settings.
-- Without this the officials screen would keep showing the old spelling with
-- nothing to indicate it was out of date.
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
      full_name, phone, dob, registered_at, status, notes,
      created_by, updated_by)
    VALUES (
      p_adeel ->> 'fullName',
      p_adeel ->> 'phone',
      nullif(p_adeel ->> 'dob', '')::date,
      coalesce(nullif(p_adeel ->> 'registeredAt', '')::date, current_date),
      coalesce(nullif(p_adeel ->> 'status', '')::member_status, 'نشط'),
      p_adeel ->> 'notes',
      auth.uid(), auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.adeels SET
      full_name     = p_adeel ->> 'fullName',
      phone         = p_adeel ->> 'phone',
      dob           = nullif(p_adeel ->> 'dob', '')::date,
      registered_at = coalesce(nullif(p_adeel ->> 'registeredAt', '')::date,
                               registered_at),
      status        = coalesce(nullif(p_adeel ->> 'status', '')::member_status,
                               status),
      notes         = p_adeel ->> 'notes',
      updated_by    = auth.uid()
     WHERE id = v_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL10';
    END IF;
  END IF;

  SELECT adeel_code INTO v_code FROM public.adeels WHERE id = v_id;

  -- ── Keep the officials' snapshot honest ───────────────────────────────────
  -- association_settings stores each official's name and phone alongside his
  -- id, so that v_officials stays readable for an عديل on the portal whom RLS
  -- would otherwise show nothing but his own row. A snapshot that is only
  -- written when SETTINGS are saved goes stale the moment the man is renamed on
  -- the register — and the officials screen would keep showing the old spelling
  -- with nothing to indicate it was out of date.
  --
  -- Scoped by the WHERE, so this is a no-op for the overwhelming majority of
  -- saves: it touches the row only when the عديل just edited actually holds a
  -- post.
  UPDATE public.association_settings s SET
    treasurer_name  = CASE WHEN s.treasurer_adeel_id = v_id
                           THEN (SELECT full_name FROM public.adeels WHERE id = v_id)
                           ELSE s.treasurer_name END,
    treasurer_phone = CASE WHEN s.treasurer_adeel_id = v_id
                           THEN coalesce((SELECT phone FROM public.adeels WHERE id = v_id), '')
                           ELSE s.treasurer_phone END,
    finance_manager_name  = CASE WHEN s.finance_manager_adeel_id = v_id
                           THEN (SELECT full_name FROM public.adeels WHERE id = v_id)
                           ELSE s.finance_manager_name END,
    finance_manager_phone = CASE WHEN s.finance_manager_adeel_id = v_id
                           THEN coalesce((SELECT phone FROM public.adeels WHERE id = v_id), '')
                           ELSE s.finance_manager_phone END
   WHERE s.id = 1
     AND (s.treasurer_adeel_id = v_id OR s.finance_manager_adeel_id = v_id);

  PERFORM public.write_audit(
    CASE WHEN p_adeel_id IS NULL THEN 'adeel.create' ELSE 'adeel.update' END,
    format('%s %s', CASE WHEN p_adeel_id IS NULL THEN 'إضافة' ELSE 'تعديل' END,
           v_code), v_code);

  RETURN jsonb_build_object('adeelId', v_id, 'adeelCode', v_code);
END $$;

-- == 6. The views ============================================================
-- v_officials is NOT touched: it reads the snapshot columns, which is what
-- keeps it readable for an عديل on the portal. Only v_settings and v_payments
-- gain columns, and CREATE OR REPLACE VIEW allows columns to be APPENDED and
-- nothing else — which is why both sit at the end of their select lists.
CREATE OR REPLACE VIEW public.v_settings WITH (security_invoker = on) AS
SELECT
  association_name        AS "associationName",
  currency                AS "currency",
  member_fee::text        AS "memberFee",
  to_char(system_start, 'YYYY-MM-DD') AS "systemStart",
  auto_close_previous_months          AS "autoClosePreviousMonths",
  -- Where a transfer should be sent. Deliberately on the WIDELY readable view
  -- rather than the admin-only settings shape: an عديل on the portal reads this
  -- view too, and he is the one being asked to transfer.
  bank_account_no                     AS "bankAccountNo",
  bank_account_name                   AS "bankAccountName"
FROM public.association_settings;

CREATE OR REPLACE VIEW public.v_payments WITH (security_invoker = on) AS
SELECT
  p.id                       AS "id",
  p.receipt_no               AS "receiptNo",
  p.adeel_id                 AS "adeelId",
  a.full_name                AS "adeelName",
  a.adeel_code               AS "adeelCode",
  p.amount::text             AS "amount",
  p.method::text             AS "method",
  coalesce(p.reference, '')  AS "reference",
  coalesce(p.receiver, '')   AS "receiver",
  coalesce(p.notes, '')      AS "notes",
  p.status::text             AS "status",
  to_char(p.paid_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "paidAt",
  coalesce(
    (SELECT jsonb_agg(
              jsonb_build_object(
                'receivableId', al.receivable_id,
                'period', al.period,
                'amount', al.amount::text)
              ORDER BY al.sequence_no)
       FROM public.payment_allocations al
      WHERE al.payment_id = p.id),
    '[]'::jsonb
  )                          AS "allocations",
  -- ── APPENDED, and it has to stay that way ─────────────────────────────────
  -- CREATE OR REPLACE VIEW can add columns to the END of the list and nothing
  -- else: inserting these two after `notes`, where they read more naturally,
  -- makes Postgres try to rename the existing `status` column and refuse with
  -- 42P16. A fresh apply would not notice — the view is created, not replaced —
  -- so it would fail only on the live project, which is the worst place to find
  -- out. Anything added later goes below these, for the same reason.
  --
  -- The snapshot on the payment row, NOT a join to current settings: a receipt
  -- reprinted after the association changes bank must still name the account
  -- the money actually went to. Empty string for cash.
  coalesce(p.bank_account_no, '')   AS "bankAccountNo",
  coalesce(p.bank_account_name, '') AS "bankAccountName"
FROM public.payments p
JOIN public.adeels a ON a.id = p.adeel_id;

-- == 7. api_settings — now carries which عديل holds each post ================
CREATE OR REPLACE FUNCTION public.api_settings() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'associationName', s.association_name,
    'currency', s.currency,
    'memberFee', s.member_fee::text,
    'systemStart', to_char(s.system_start, 'YYYY-MM-DD'),
    'autoClosePreviousMonths', s.auto_close_previous_months,
    'bankAccountNo', s.bank_account_no,
    'bankAccountName', s.bank_account_name,
    -- adeelId is what the settings screen preselects in its dropdown; the name
    -- and phone travel with it so the screen can render the current holder
    -- without a second read. NULL means the post is vacant, or was filled by a
    -- typed name before the two posts were tied to the register.
    'treasurer', jsonb_build_object(
      'adeelId', s.treasurer_adeel_id,
      'name', s.treasurer_name,
      'phone', s.treasurer_phone),
    'financeManager', jsonb_build_object(
      'adeelId', s.finance_manager_adeel_id,
      'name', s.finance_manager_name,
      'phone', s.finance_manager_phone))
  FROM public.association_settings s WHERE s.id = 1
$$;

-- == 8. The sign-in guard ====================================================
-- New in the schema, so it is created here before being called below.
-- Read-only: it repairs nothing and names the file that does.
CREATE OR REPLACE FUNCTION public.assert_signin_intact() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_fn      bool;
  v_trigger bool;
  v_enabled bool;
  v_orphans bigint;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'handle_new_user')
    INTO v_fn;

  -- tgisinternal excludes the constraint triggers Postgres creates for foreign
  -- keys, which would otherwise make a missing trigger look present.
  SELECT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)
    INTO v_trigger;

  -- 'D' is DISABLED. A disabled trigger exists, reports present in every naive
  -- check, and does nothing at all — the same broken sign-in wearing a
  -- convincing disguise.
  SELECT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal
                    AND tgenabled <> 'D')
    INTO v_enabled;

  IF NOT v_fn THEN
    RAISE EXCEPTION
      'SIGN-IN: public.handle_new_user() is missing. Any new account would fail '
      'to be created and nobody new could sign in. Nothing has been committed.'
      USING ERRCODE = 'RUL01';
  END IF;

  IF NOT v_trigger THEN
    RAISE EXCEPTION
      'SIGN-IN: trigger trg_auth_user_created on auth.users is missing — this is '
      'what DROP SCHEMA public CASCADE removes. First-time sign-in would fail '
      'with "Database error saving new user". Nothing has been committed.'
      USING ERRCODE = 'RUL01';
  END IF;

  IF NOT v_enabled THEN
    RAISE EXCEPTION
      'SIGN-IN: trigger trg_auth_user_created exists but is DISABLED, so it '
      'creates no profile. Nothing has been committed.' USING ERRCODE = 'RUL01';
  END IF;

  -- Not fatal: an account with no profile can still authenticate, and the app
  -- says so plainly. Worth a warning because it means somebody signed in while
  -- the trigger was gone, and the backfill in 20260811090100 clears it.
  SELECT count(*) INTO v_orphans
    FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);

  IF v_orphans > 0 THEN
    RAISE WARNING
      'SIGN-IN: % account(s) exist with no profiles row. They can authenticate '
      'but the app will show "this account has no row in the database". Re-run '
      'the bundle, or supabase/PATCH_20260816_restore_signin_trigger.sql, to '
      'backfill them.', v_orphans;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_signin_intact()
  FROM PUBLIC, anon, authenticated, service_role;

-- == The standing guarantees, re-proven ======================================
-- SIGN-IN FIRST, inside the transaction. If anything above had disturbed
-- handle_new_user() or trg_auth_user_created, this raises and the whole patch
-- rolls back — the project stays as it was rather than committing a state
-- nobody new can log into.
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed, and that sign-in is still wired.
SELECT 'officials are tied to the register' AS check,
       (SELECT count(*) = 2 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'association_settings'
           AND column_name IN ('treasurer_adeel_id','finance_manager_adeel_id'))::text AS ok
UNION ALL SELECT 'one man cannot hold both posts',
       (EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conname = 'ck_settings_distinct_officials'))::text
UNION ALL SELECT 'update_settings saves the officials (the silent-save fix)',
       (pg_get_functiondef('public.update_settings(jsonb)'::regprocedure)
          LIKE '%treasurer_adeel_id%')::text
UNION ALL SELECT 'renaming an official refreshes the snapshot',
       (pg_get_functiondef('public.save_adeel(bigint,jsonb)'::regprocedure)
          LIKE '%treasurer_adeel_id%')::text
UNION ALL SELECT 'settings and payments hold a bank account',
       (SELECT count(*) = 4 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND column_name IN ('bank_account_no','bank_account_name')
           AND table_name IN ('association_settings','payments'))::text
UNION ALL SELECT 'register_payment still takes SIX parameters',
       (SELECT count(*) = 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'register_payment'
           AND p.pronargs = 6)::text
UNION ALL SELECT 'v_officials was left alone (portal still sees the names)',
       (SELECT count(*) = 3 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'v_officials')::text
UNION ALL SELECT 'Google sign-in trigger is STILL in place',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)::text
UNION ALL SELECT 'staff profiles untouched',
       (EXISTS (SELECT 1 FROM public.profiles))::text;
