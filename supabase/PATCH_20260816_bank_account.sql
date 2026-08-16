-- ============================================================================
--  جمعية العدايل — PATCH: the association's bank account, 2026-08-16.
--
--  GENERATED FILE. Do not edit. The source of truth is supabase/migrations/.
--
--  WHAT IT ADDS
--    The association's own receiving account — رقم الحساب and اسم صاحب الحساب —
--    held ONCE in settings, and snapshotted onto every تحويل مصرفي.
--
--      association_settings.bank_account_no    where a transfer should be sent
--      association_settings.bank_account_name
--      payments.bank_account_no                where THIS transfer actually went
--      payments.bank_account_name
--
--    The pair on `payments` is a snapshot, not a join, for the same reason
--    receivables.adeel_name is: the association will change bank one day, and a
--    receipt reprinted afterwards must still name the account the money went to.
--
--    register_payment fills them FROM SETTINGS. The client never sends them —
--    the anon key ships inside the APK, so anything the client could send, a
--    hostile client could forge, and this is a field that says where the
--    association's money went.
--
--  ⚠ READ THIS IF YOU HAVE HIT THE SIGN-IN FAULT BEFORE
--    This patch is ADDITIVE ONLY. Verify it yourself before running:
--
--      * no DROP SCHEMA, no DROP TABLE, no DROP FUNCTION, no DROP TRIGGER
--      * no TRUNCATE and no DELETE
--      * no change to any function SIGNATURE, so no grant is dropped and the
--        lockdown allow-list is untouched
--      * nothing referencing auth.users, profiles, or trg_auth_user_created
--
--    RESET_AND_APPLY.sql is what took `trg_auth_user_created` with it and broke
--    first-time Google sign-in — DROP SCHEMA public CASCADE removes a trigger on
--    auth.users whose function lives in `public`. Nothing here drops anything.
--    The final query re-checks that the trigger is still in place.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes.
--
--  SAFE TO RUN TWICE
--    Yes. Columns are added IF NOT EXISTS, and CREATE OR REPLACE is idempotent.
-- ============================================================================

BEGIN;

-- == 1. Settings: where a transfer should be sent ============================
-- NOT NULL DEFAULT '' so every existing row gets a value and no read has to
-- handle NULL. Never format-checked: Libyan IBANs, plain account numbers and
-- whatever a given bank prints are all legitimate, and a CHECK would refuse the
-- association's real account the day they open one elsewhere.
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS bank_account_no   text NOT NULL DEFAULT '';
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS bank_account_name text NOT NULL DEFAULT '';

-- == 2. Payments: where THIS transfer actually went ==========================
-- Nullable, unlike the settings pair: NULL means cash, or a transfer taken
-- before any account was configured. Defaulting to '' would erase that
-- distinction on every historical row.
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_account_no   text;
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_account_name text;

-- == 3. register_payment — snapshots the account, signature UNCHANGED ========
-- Six parameters before and six after, so this is a plain CREATE OR REPLACE:
-- the existing EXECUTE grants survive, the lockdown allow-list still matches,
-- and nothing that calls it needs redeploying.
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

-- == 4. update_settings — writes the account, and audits the change ==========
-- The number is recorded in full, before and after. It is the one setting where
-- a single wrong digit sends the association's collections to a stranger, and
-- "someone changed the bank account" without saying what it was is not a trail
-- anyone can act on.
CREATE OR REPLACE FUNCTION public.update_settings(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_old     record;
  v_row     record;
  v_changes text[] := '{}';
BEGIN
  PERFORM public.require_role('admin');

  SELECT * INTO v_old FROM public.association_settings WHERE id = 1 FOR UPDATE;

  UPDATE public.association_settings SET
    association_name = coalesce(p_patch ->> 'associationName', association_name),
    currency         = coalesce(p_patch ->> 'currency', currency),
    member_fee       = coalesce((p_patch ->> 'memberFee')::numeric, member_fee),
    system_start     = coalesce((p_patch ->> 'systemStart')::date, system_start),
    treasurer_name        = coalesce(p_patch ->> 'treasurerName', treasurer_name),
    treasurer_phone       = coalesce(p_patch ->> 'treasurerPhone', treasurer_phone),
    finance_manager_name        = coalesce(p_patch ->> 'financeName', finance_manager_name),
    finance_manager_phone       = coalesce(p_patch ->> 'financePhone', finance_manager_phone),
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

-- == 5. The views ============================================================
-- CREATE OR REPLACE VIEW allows columns to be APPENDED but never reordered or
-- retyped, which is why both new columns sit at the end of each select list.
-- `security_invoker = on` is restated: without it the view would run as its
-- owner and read straight past RLS.
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

-- == 6. api_settings — the editable shape the settings screen reads ==========
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
    'treasurer', jsonb_build_object(
      'name', s.treasurer_name,
      'phone', s.treasurer_phone),
    'financeManager', jsonb_build_object(
      'name', s.finance_manager_name,
      'phone', s.finance_manager_phone))
  FROM public.association_settings s WHERE s.id = 1
$$;

-- == 7. The sign-in guard itself ============================================
-- New in the schema, so it has to be created here before it can be called
-- below — a project patched before today does not have it yet.
--
-- It is READ-ONLY and repairs nothing. If it finds sign-in already broken, this
-- patch refuses to commit and names the file that fixes it; applying a bank
-- account on top of a project nobody new can log into would just bury the
-- problem under a change that looks like progress.
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
-- SIGN-IN FIRST, and inside the transaction. If anything above had disturbed
-- handle_new_user() or trg_auth_user_created, this raises and the whole patch
-- rolls back — the project stays exactly as it was rather than committing a
-- state where nobody new can sign in. Nothing above should come near it; this
-- is what makes that a fact rather than an intention.
SELECT public.assert_signin_intact();

-- Nothing above changes a signature or creates a function, so no grant should
-- have moved. These assert it rather than assuming it — and the view check is
-- the one that matters here, because a replaced view that lost
-- security_invoker would quietly serve every payment row to every caller.
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed, and that sign-in is still wired.
SELECT 'settings hold a bank account' AS check,
       (SELECT count(*) = 2 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'association_settings'
           AND column_name IN ('bank_account_no', 'bank_account_name'))::text AS ok
UNION ALL SELECT 'payments snapshot a bank account',
       (SELECT count(*) = 2 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'payments'
           AND column_name IN ('bank_account_no', 'bank_account_name'))::text
UNION ALL SELECT 'register_payment still takes SIX parameters',
       (SELECT count(*) = 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'register_payment'
           AND p.pronargs = 6)::text
UNION ALL SELECT 'register_payment snapshots from settings',
       (pg_get_functiondef(
          'public.register_payment(bigint,numeric,pay_method,text,text,text)'::regprocedure)
        LIKE '%bank_account_no%')::text
UNION ALL SELECT 'v_payments exposes the snapshot',
       (SELECT count(*) = 2 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'v_payments'
           AND column_name IN ('bankAccountNo', 'bankAccountName'))::text
UNION ALL SELECT 'Google sign-in trigger is STILL in place',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)::text
UNION ALL SELECT 'staff profiles untouched',
       (EXISTS (SELECT 1 FROM public.profiles))::text;
