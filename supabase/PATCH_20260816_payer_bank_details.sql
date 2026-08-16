-- ============================================================================
--  جمعية العدايل — PATCH: the payer's bank details.  2026-08-16.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  Cumulative on purpose: it re-applies everything the earlier patches did as
--  well as what is new. Every statement is idempotent, so running it is correct
--  whatever you have run before — which matters, because the save_adeel fix
--  below landed AFTER PATCH_20260816_officials_and_bank.sql was applied.
--
--  WHAT IS NEW
--
--  1. THE THREE BANK FIELDS ARE THE PAYER'S ACCOUNT, NOT THE ASSOCIATION'S.
--     An عديل may transfer from more than one account and more than one bank,
--     so which he used is a fact about THAT collection and cannot be a setting.
--     register_payment now ACCEPTS them instead of copying them from settings:
--
--       p_bank_name, p_bank_account_name, p_bank_account_no
--
--     Kept only for a تحويل مصرفي; a cash collection has no sending account and
--     the three columns stay NULL for it. Blanks are normalised to NULL, so
--     "not given" and "given empty" are the same thing on the row.
--
--     Letting the client name them is safe HERE, unlike the association's own
--     account: these describe the SENDER, which only the treasurer taking the
--     receipt knows, and getting one wrong misfiles a receipt rather than
--     misdirecting money. The app makes retyping cheap by offering what this
--     same عديل used before — read from v_payments, which RLS already scopes.
--
--     association_settings keeps its own bank_* columns. They answer a
--     different question — where a member should SEND a transfer — and are
--     untouched here.
--
--  2. save_adeel NO LONGER ERASES WHAT IT WAS NOT TOLD ABOUT.
--     `notes = p_adeel ->> 'notes'` was unconditional, and the عديل form has no
--     notes field, so the key was never sent, ->> returned NULL, and EVERY edit
--     silently wiped the note. The save succeeded, so nothing reported it.
--     `phone` and `dob` had the same shape. An absent key now means "leave it
--     alone"; a key sent EMPTY still clears the field.
--
--  3. THE PATCH NOW REVOKES WHAT IT CREATES. (This is the fix for the error
--     that made every earlier run of this file roll back:
--
--       LOCKDOWN: these public functions are executable by PUBLIC
--       (i.e. by anyone holding the anon key): register_payment(...)
--
--     CREATE OR REPLACE keeps a function's existing ACL; a FRESH create has no
--     ACL to keep, so Postgres materialises the built-in default — EXECUTE to
--     PUBLIC — and Supabase's ALTER DEFAULT PRIVILEGES adds anon on top. The
--     DROP in section 3 turns the CREATE after it into a fresh create, so the
--     nine-argument register_payment came out callable by anyone holding the
--     anon key. assert_no_public_execute() caught it and refused the whole
--     transaction, every single time — which is the guard working, not failing.
--
--     A full apply never hit this because the lockdown migration runs LAST and
--     sweeps the whole schema. Section 11 now re-runs that same sweep here, so
--     this cannot recur for the next function a patch adds.
--
--  ⚠ THIS PATCH CONTAINS ONE DROP, AND IT IS DELIBERATE
--       DROP FUNCTION IF EXISTS public.register_payment(6 args)
--
--     CREATE OR REPLACE cannot change a signature, and leaving the old
--     six-argument function beside the new nine-argument one makes every call
--     ambiguous (42725, "function is not unique"). Dropping a FUNCTION destroys
--     no data and touches no row; what it does drop is the EXECUTE grant, which
--     is re-issued below, and it forces the lockdown allow-list to be restated —
--     both are asserted before COMMIT.
--
--     Nothing else is dropped. No DROP SCHEMA, no DROP TABLE, no DROP TRIGGER,
--     no TRUNCATE, no DELETE, and nothing touching auth.users or profiles.
--     assert_signin_intact() still runs before COMMIT.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes. Safe to run twice.
-- ============================================================================

BEGIN;

-- == 1. Settings: the two posts, and the bank account ========================
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS treasurer_adeel_id       bigint;
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS finance_manager_adeel_id bigint;
-- Three parts, because a transfer needs all three to be actionable: an account
-- number alone does not say WHICH bank to walk into, and a Libyan account
-- number is only unique within its own bank.
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS bank_name         text NOT NULL DEFAULT '';
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

-- == 2. Payments: the account the money came FROM ======================
-- The payer's, not the association's. Nullable: NULL means cash, or a transfer
-- recorded before these columns existed. Defaulting to '' would erase that
-- distinction on every historical row.
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_name         text;
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_account_no   text;
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_account_name text;

-- == 3. register_payment — the signature GAINS the payer's three fields =====
-- The only DROP in this file. It removes a FUNCTION, not data: no row is
-- touched. The old six-argument version has to go because CREATE OR REPLACE
-- cannot change a signature, and leaving both would make every call ambiguous
-- with 42725. The grant it takes with it is re-issued immediately after.
DROP FUNCTION IF EXISTS
  public.register_payment(bigint, numeric, pay_method, text, text, text);

CREATE OR REPLACE FUNCTION public.register_payment(
  p_adeel_id  bigint,
  p_amount    numeric,
  p_method    pay_method,
  p_reference text DEFAULT NULL,
  p_receiver  text DEFAULT NULL,
  p_notes     text DEFAULT NULL,
  p_bank_name         text DEFAULT NULL,
  p_bank_account_name text DEFAULT NULL,
  p_bank_account_no   text DEFAULT NULL
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
  v_bank        text;
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

  -- Kept ONLY for a transfer. A cash collection has no sending account, so
  -- letting the three columns carry anything for it would put data on the row
  -- that cannot be true — and the treasury screen would start showing bank
  -- details beside نقداً. Blanks are normalised to NULL so "not given" and
  -- "given as an empty box" are the same thing on the row.
  IF p_method = 'تحويل مصرفي' THEN
    v_bank      := nullif(btrim(coalesce(p_bank_name, '')), '');
    v_acct_name := nullif(btrim(coalesce(p_bank_account_name, '')), '');
    v_acct_no   := nullif(btrim(coalesce(p_bank_account_no, '')), '');
  END IF;

  INSERT INTO public.payments (adeel_id, amount, method, reference, receiver,
                               notes, created_by,
                               bank_name, bank_account_no, bank_account_name)
  VALUES (p_adeel_id, p_amount, p_method, p_reference, p_receiver, p_notes,
          auth.uid(), v_bank, v_acct_no, v_acct_name)
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

-- REVOKE FIRST, and this is the line whose absence made every run of this patch
-- roll back with
--
--   LOCKDOWN: these public functions are executable by PUBLIC
--   (i.e. by anyone holding the anon key): register_payment(...)
--
-- A function created by CREATE OR REPLACE keeps the ACL it already had. One
-- created FRESH does not have an ACL to keep, so Postgres materialises the
-- built-in default — which grants EXECUTE to PUBLIC — and then layers Supabase's
-- ALTER DEFAULT PRIVILEGES grants to anon/authenticated/service_role on top.
-- The DROP above makes the CREATE below a fresh create, so the new nine-argument
-- register_payment came out callable by ANYONE HOLDING THE ANON KEY, signed in
-- or not. assert_no_public_execute() saw that and refused the whole transaction.
--
-- The full apply never hit this because 20260811091200_function_lockdown.sql
-- runs LAST and sweeps every function in the schema. A patch has no such sweep,
-- so it has to revoke what it creates — see section 11, which re-runs that sweep
-- so the next function added by a patch cannot repeat this.
REVOKE EXECUTE ON FUNCTION
  public.register_payment(bigint, numeric, pay_method, text, text, text,
                          text, text, text)
FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  public.register_payment(bigint, numeric, pay_method, text, text, text,
                          text, text, text)
TO authenticated, service_role;

-- == 4. The lockdown allow-list — restated for the new signature =========
-- It is an EXACT set, so it has to name the new signature.
-- Leave it naming the old one and assert_function_grants() fails in both
-- directions at once — the new function callable but unlisted, the listed one
-- missing — and the whole patch rolls back.
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
    'redeem_adeel_code(text)',

    -- Reads. STABLE and SECURITY INVOKER, so RLS still decides what they return.
    'period_label(text)',
    'adeel_json(bigint)',
    'api_adeel_detail(bigint)',
    'api_adeel_statement(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_closable_periods()',
    'api_settings()',
    'api_me()',
    'api_touch_login()'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- == 5. update_settings — the officials, the account, and the audit ==========
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
    -- nullif BEFORE the cast, and the officials below have always had it while
    -- these two did not. An EMPTY string is not a number and not a date, so
    -- `''::numeric` raises 22P02 — a code with no Arabic text, which the app can
    -- only render as "something went wrong". The whole save fails, including
    -- the two officials the admin was actually trying to set, and nothing on
    -- screen connects the failure to a field he may not even have touched.
    --
    -- An empty box now means "leave it alone", which is the only reading that
    -- makes sense: the fee is NOT NULL, so blank cannot be a value.
    member_fee       = coalesce(nullif(p_patch ->> 'memberFee', '')::numeric,
                                member_fee),
    system_start     = coalesce(nullif(p_patch ->> 'systemStart', '')::date,
                                system_start),
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
    bank_name                   = coalesce(p_patch ->> 'bankName', bank_name),
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
  IF v_row.bank_name IS DISTINCT FROM v_old.bank_name THEN
    v_changes := v_changes || format('المصرف من %s إلى %s',
                                     coalesce(nullif(v_old.bank_name, ''), '—'),
                                     coalesce(nullif(v_row.bank_name, ''), '—'));
  END IF;
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

-- == 6. save_adeel — keeps the officials' snapshot from going stale ==========
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
    -- ── An ABSENT key means "leave it alone", never "set it to NULL" ────────
    -- `notes` used to be assigned unconditionally: `notes = p_adeel ->> 'notes'`.
    -- The عديل form does not have a notes field and so never sends the key, so
    -- ->> returned NULL and EVERY edit of an عديل silently erased his notes.
    -- Nothing reported it — the save succeeded, and the loss was only visible
    -- to whoever had written the note. `phone` and `dob` had the same shape and
    -- would do the same to any caller that omits them.
    --
    -- `p_adeel ? key` is the distinction the old code could not make: it tells
    -- a key that was sent as empty (clear the field) from one that was not sent
    -- at all (do not touch it). update_settings already resolves the officials
    -- this way, and for the same reason.
    --
    -- full_name stays unconditional on purpose: it is NOT NULL, so omitting it
    -- raises instead of quietly blanking the register entry — which is the
    -- correct outcome for the one field an عديل cannot exist without.
    UPDATE public.adeels SET
      full_name     = p_adeel ->> 'fullName',
      phone         = CASE WHEN p_adeel ? 'phone'
                           THEN p_adeel ->> 'phone' ELSE phone END,
      dob           = CASE WHEN p_adeel ? 'dob'
                           THEN nullif(p_adeel ->> 'dob', '')::date ELSE dob END,
      registered_at = coalesce(nullif(p_adeel ->> 'registeredAt', '')::date,
                               registered_at),
      status        = coalesce(nullif(p_adeel ->> 'status', '')::member_status,
                               status),
      notes         = CASE WHEN p_adeel ? 'notes'
                           THEN p_adeel ->> 'notes' ELSE notes END,
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

-- == 7. redeem_adeel_code — a SUSPENDED account cannot redeem its way back in =
-- Folded in from the superseded PATCH_20260816_financial_hardening.sql, so that
-- this file is the whole story and there is no second patch whose older
-- update_settings could overwrite the officials half of this one.
--
-- guard_profile_change refuses every self-change of `status` except one: the
-- pending → approved that redeeming performs on the caller's own row. Nothing
-- distinguished suspended → approved from it, so an account an admin had
-- suspended could restore itself by redeeming any unredeemed access code — and
-- come back with read access to one عديل's dues, receipts and statement. Its
-- role never changed, so no other guard had anything to notice.
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

  -- A SUSPENDED account cannot redeem its way back in.
  --
  -- This is the one status that has to be checked here, and it is easy to miss
  -- because the check that matters is not in this function — it is in
  -- guard_profile_change. That trigger normally refuses any self-change of
  -- `status`, and it makes ONE exception (`v_redeeming`) for the update below,
  -- which sets status = 'approved' on the caller's own row. The exception exists
  -- for pending → approved, which is the whole redemption flow.
  --
  -- Nothing distinguished suspended → approved from it. So an admin could
  -- suspend an account and that account could restore itself to `approved` by
  -- redeeming any unredeemed access code — coming back with read access to one
  -- عديل's dues, receipts and statement. The role never changed, so no other
  -- guard had anything to notice.
  --
  -- `pending` must still pass: a new Google account is created viewer/pending by
  -- handle_new_user, and redeeming is exactly how an عديل turns that into access
  -- without an admin approving him as staff. Only `suspended` is refused.
  IF v_me.status = 'suspended' THEN
    RAISE EXCEPTION 'هذا الحساب موقوف، راجع إدارة الجمعية'
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

-- == 8. The views ============================================================
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
  bank_account_name                   AS "bankAccountName",
  bank_name                           AS "bankName"
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
  -- The PAYER'S account, as he gave it for THIS transfer — recorded on the row
  -- because a member may transfer from more than one account and more than one
  -- bank. Empty string for cash, which has no sending account.
  coalesce(p.bank_account_no, '')   AS "bankAccountNo",
  coalesce(p.bank_account_name, '') AS "bankAccountName",
  coalesce(p.bank_name, '')         AS "bankName"
FROM public.payments p
JOIN public.adeels a ON a.id = p.adeel_id;

-- == 9. api_settings — now carries which عديل holds each post ================
CREATE OR REPLACE FUNCTION public.api_settings() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'associationName', s.association_name,
    'currency', s.currency,
    'memberFee', s.member_fee::text,
    'systemStart', to_char(s.system_start, 'YYYY-MM-DD'),
    'autoClosePreviousMonths', s.auto_close_previous_months,
    'bankName', s.bank_name,
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

-- == 10. The sign-in guard ====================================================
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
      'the bundle, or supabase/PATCH_20260816_signin_hardening.sql, to '
      'backfill them.', v_orphans;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_signin_intact()
  FROM PUBLIC, anon, authenticated, service_role;

-- == 11. Re-run the lockdown sweep ===========================================
-- Byte-for-byte the loop from 20260811091200_function_lockdown.sql, which runs
-- LAST on a full apply and is the reason a fresh project never had this problem.
--
-- A patch does not get that sweep for free. Every function it creates fresh —
-- register_payment above, assert_signin_intact in section 10 — comes out with
-- the built-in default ACL, and the built-in default for a function is EXECUTE
-- to PUBLIC. Naming each one in a REVOKE works only for as long as nobody
-- forgets, and forgetting is silent: the function is created, the patch reads
-- correctly, and the only thing that objects is an assertion 600 lines further
-- down whose message names a symptom rather than the missing line.
--
-- Running the sweep instead makes the guarantee structural. It revokes from
-- every function in `public` and grants back EXACTLY the allow-list restated in
-- section 4, so the schema's grants are recomputed from that list rather than
-- accumulated. Nothing here depends on the next patch remembering.
--
-- It is placed after every CREATE in this file, deliberately: the sweep can only
-- normalise functions that already exist when it runs.
DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    -- regprocedure, NOT pg_get_function_identity_arguments(): the latter includes
    -- PARAMETER NAMES ("p_period character"), while regprocedure renders the
    -- type-only form the allow-list is written in ("generate_period(character)").
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       -- Extension functions are not ours. A project with pgcrypto or uuid-ossp
       -- in `public` would otherwise lose gen_random_uuid() and friends.
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    -- PUBLIC *and* the named roles. Supabase's default privileges grant to the
    -- names, so a PUBLIC-only revoke is a no-op on a real project.
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
UNION ALL SELECT 'settings and payments hold all three bank fields',
       (SELECT count(*) = 6 FROM information_schema.columns
         WHERE table_schema = 'public'
           AND column_name IN ('bank_name','bank_account_no','bank_account_name')
           AND table_name IN ('association_settings','payments'))::text
UNION ALL SELECT 'register_payment now takes NINE parameters',
       (SELECT count(*) = 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'register_payment'
           AND p.pronargs = 9)::text
-- The one this patch used to fail on. `= 0` means no PUBLIC (grantee 0) EXECUTE
-- entry survives on the new signature: holding the anon key is not enough to
-- call it, and require_role('treasurer') inside it is not the only thing
-- standing between a stranger and the treasury.
UNION ALL SELECT 'register_payment is NOT callable by the anon key',
       (SELECT count(*) = 0 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace,
          LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         WHERE n.nspname = 'public' AND p.proname = 'register_payment'
           AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR a.grantee = 'anon'::regrole))::text
UNION ALL SELECT 'v_officials was left alone (portal still sees the names)',
       (SELECT count(*) = 3 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'v_officials')::text
UNION ALL SELECT 'Google sign-in trigger is STILL in place',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)::text
UNION ALL SELECT 'staff profiles untouched',
       (EXISTS (SELECT 1 FROM public.profiles))::text;
