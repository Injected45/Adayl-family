-- ============================================================================
--  ADD_PURGE_FINANCIAL_DATA.sql — install the Settings → "منطقة الخطر" purges on
--  a project that ALREADY has the schema.
--
--  TWO functions, one narrow and one wide:
--    purge_financial_data(text)  phrase 'مسح نهائي'       figures only
--    purge_all_data(text)        phrase 'مسح كل البيانات'  figures + directory
--
--  Re-run this whole file after either changes; it is idempotent.
--
--  A fresh project needs nothing from this file: APPLY_TO_SUPABASE.sql contains
--  the same function, because the source of truth is
--    supabase/migrations/20260811090600_rpc.sql          (the function)
--    supabase/migrations/20260811091200_function_lockdown.sql  (the allow-list)
--
--  This file is a transcription of those two hunks for an existing project,
--  where re-running the full bundle would fail on CREATE TABLE. If the function
--  body is ever changed, change it there first and re-transcribe here — the
--  probe suite tests the migrations, not this file.
--
--  HOW TO APPLY
--    Supabase dashboard → SQL Editor → New query → paste all of this → Run.
--    One transaction, and it ends with the lockdown assertion, so a mistake in
--    the allow-list rolls the whole thing back instead of leaving a function
--    exposed.
--
--  Re-running it is harmless: every statement is CREATE OR REPLACE or a grant.
-- ============================================================================

BEGIN;

-- ── The function ─────────────────────────────────────────────────────────────
-- See 20260811090600_rpc.sql for the full reasoning. In short: TRUNCATE rather
-- than DELETE, because TRUNCATE fires no BEFORE DELETE trigger and so never has
-- to disarm the rule-9 guards; RESTART IDENTITY so the next receipt is
-- PAY-000001; families / members / settings / profiles are untouched;
-- audit_log IS truncated and no entry is written afterwards, by choice.
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

  IF btrim(coalesce(p_confirm, '')) <> 'مسح نهائي' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

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

-- ── The wider purge: the directory too ───────────────────────────────────────
-- A SUPERSET of the above, not an alternative to it. receivables, payments,
-- cash_movements and members all reference families with ON DELETE RESTRICT, so
-- the families cannot go while a single receipt still points at one — the choice
-- was between taking the financial rows along or refusing whenever any exist,
-- and refusing would fail for exactly the admin who wants this.
--
-- Its confirmation phrase differs from purge_financial_data's ON PURPOSE: that
-- is what stops a mis-click meant for the figures from emptying the directory.
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

  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivable_lines,
           public.receivables,
           public.audit_log,
           public.members,
           public.families
    RESTART IDENTITY;

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

-- ── The allow-list, restated with the new entry ──────────────────────────────
-- assert_function_grants() reads this list and fails on ANY difference in either
-- direction, so the new function has to be named here or the COMMIT below never
-- happens. Keep it byte-identical to 20260811091200_function_lockdown.sql.
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',

    'register_payment(bigint,numeric,pay_method,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_family(bigint,jsonb,jsonb)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    'purge_financial_data(text)',
    'purge_all_data(text)',

    'period_label(text)',
    'member_json(bigint)',
    'api_family_detail(bigint)',
    'api_family_statement(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_settings()',
    'api_me()',
    'api_touch_login()'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- Supabase's default privileges grant EXECUTE on anything created in `public` to
-- anon BY NAME, so the revoke is not decoration — without it the purge would be
-- callable with nothing but the publishable key and no session at all.
REVOKE EXECUTE ON FUNCTION public.purge_financial_data(text)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.purge_financial_data(text)
  TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.purge_all_data(text)
  FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.purge_all_data(text)
  TO authenticated, service_role;

-- The standing guarantee: the set of client-callable functions is EXACTLY the
-- list above. Raises, and rolls everything back, on any drift.
SELECT public.assert_function_grants();

COMMIT;

-- Confirm what landed.
SELECT p.oid::regprocedure::text AS installed,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('purge_financial_data', 'purge_all_data')
 ORDER BY p.proname;
