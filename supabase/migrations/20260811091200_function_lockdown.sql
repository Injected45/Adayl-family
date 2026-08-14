-- 20260811091200_function_lockdown.sql — runs LAST. The real function lockdown.
--
-- ═══════════════════════════════════════════════════════════════════════════
--  WHY THIS FILE EXISTS, AND WHY THE EARLIER ONES WERE NOT ENOUGH
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 20260811090800_lockdown.sql revoked EXECUTE from PUBLIC and asserted that no
-- function in `public` was PUBLIC-executable. That assertion passed on the live
-- project. And `write_audit` was still callable by any signed-in user, who could
-- forge audit-trail entries under their own name. A forged row was actually
-- written during verification.
--
-- The reason: a real Supabase project ships with
--
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public
--       GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
--
-- so every function created in `public` comes out with EXECUTE granted to `anon`
-- and `authenticated` **BY NAME**. Nothing is granted to PUBLIC, which is exactly
-- why the PUBLIC-only check reported success. Revoking from PUBLIC on a Supabase
-- project changes nothing at all.
--
-- This was invisible locally because supabase/tests/00_local_shim.sql did not
-- reproduce those default privileges. It does now, and the probe suite fails
-- without this file.
--
-- ═══════════════════════════════════════════════════════════════════════════
--
-- The rule enforced here: the set of functions callable by a client is EXACTLY
-- the allow-list below. Not "at least" — exactly. A function added later is
-- unreachable until someone adds it here on purpose, and a function removed from
-- the list but still granted fails the assertion.

-- ── The allow-list ───────────────────────────────────────────────────────────
-- Everything a signed-in client may call, and nothing else. Each write function
-- checks the caller's role internally with require_role(), so granting them all
-- to `authenticated` is safe: a viewer calling register_payment gets RUL00.
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    -- Role helpers. The RLS policies call these, so they must be executable by
    -- the caller whose policy is being evaluated. They leak nothing beyond that
    -- caller's own role.
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    -- Answers only for the caller's own family binding, and the family-scoped
    -- policies call it, so the caller whose policy is being evaluated must hold
    -- EXECUTE — otherwise every one of those policies ERRORS instead of denying,
    -- and the failure surfaces as "permission denied for function my_family_id"
    -- on screens that have nothing to do with the family portal.
    'my_family_id()',

    -- Writes. Eleven functions, each require_role()-gated, each one transaction.
    'register_payment(bigint,numeric,pay_method,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_family(bigint,jsonb,jsonb)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    -- The two destructive ones. admin-only, and each refuses without its OWN
    -- typed phrase, so the phrase that clears the figures cannot clear the
    -- directory. They are on the list because Settings calls them directly; the
    -- reason that is safe is the same reason the other seven are — the gate is
    -- inside the body, not in who can reach it.
    'purge_financial_data(text)',
    'purge_all_data(text)',

    -- The family portal. issue_ is admin-gated; redeem_ deliberately is NOT —
    -- it is the one write a signed-in stranger may call, because until he
    -- redeems a code he has no role and no family, and the code itself is the
    -- authorisation. It refuses anyone who is already staff.
    'issue_family_code(bigint)',
    'redeem_family_code(text)',

    -- Reads. STABLE and SECURITY INVOKER, so RLS still decides what they return.
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

-- Deliberately ABSENT, and each for a reason:
--
--   write_audit          — no internal role check. Exposing it lets any signed-in
--                          user forge trail entries under someone else's name, in
--                          a system whose rule 12 exists to make the trail
--                          trustworthy. This is the function that was actually
--                          exploited during verification.
--   require_role         — pointless alone, and returns nothing useful.
--   handle_new_user      — a trigger on auth.users. Calling it directly would let
--                          a client insert profile rows.
--   touch_updated_at     — trigger body.
--   guard_*, derive_*, refuse_*  — trigger bodies. Postgres checks EXECUTE at
--                          CREATE TRIGGER time, not when a trigger fires, so
--                          withholding it costs nothing.
--   assert_*             — migration-time guards.
--   client_callable_functions — this list itself.

-- ── Revoke from every client role, then grant back the list ──────────────────
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
    -- Comparing against identity arguments silently matched nothing except the
    -- zero-argument functions, so fourteen were left ungranted.
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

    -- Normalise: strip spaces, and drop a leading `public.` in case the role's
    -- search_path does not include public and regprocedure qualifies the name.
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      -- service_role too: it is a trusted server-side context, and the phase-4
      -- legacy import needs the write functions.
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;

-- ── The standing guarantee ───────────────────────────────────────────────────
-- Exact-set, not a floor. Exposed as a function so the probe suite can call it
-- and can plant a violation to prove it fails.
CREATE OR REPLACE FUNCTION public.assert_function_grants() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_extra   text;
  v_missing text;
BEGIN
  -- Anything callable by a client that is not on the list.
  SELECT string_agg(sig, ', ' ORDER BY sig) INTO v_extra
    FROM (
      SELECT replace(replace(p.oid::regprocedure::text, 'public.', ''), ' ', '')
               AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND NOT EXISTS (SELECT 1 FROM pg_depend d
                          WHERE d.objid = p.oid
                            AND d.classid = 'pg_proc'::regclass
                            AND d.deptype = 'e')
         AND (
           p.proacl IS NULL   -- built-in default includes PUBLIC
           OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                       WHERE a.privilege_type = 'EXECUTE'
                         AND (a.grantee = 0
                              OR a.grantee = 'anon'::regrole
                              OR a.grantee = 'authenticated'::regrole))
         )
    ) callable
   WHERE sig <> ALL (SELECT replace(a, ' ', '')
                       FROM unnest(public.client_callable_functions()) a);

  IF v_extra IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these functions are callable by anon/authenticated but are not '
      'on the allow-list in 20260811091200_function_lockdown.sql: %', v_extra;
  END IF;

  -- And anything on the list that is NOT callable — a typo in a signature would
  -- otherwise silently break a screen at runtime instead of failing the migration.
  SELECT string_agg(a, ', ') INTO v_missing
    FROM unnest(public.client_callable_functions()) a
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND replace(replace(p.oid::regprocedure::text, 'public.', ''), ' ', '')
            = replace(a, ' ', '')
        AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
   );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these allow-listed functions are missing or not granted — check '
      'the signatures: %', v_missing;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_function_grants() FROM PUBLIC, anon,
  authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.client_callable_functions() FROM PUBLIC, anon,
  authenticated, service_role;

SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

-- ── Tables and sequences, same reasoning ─────────────────────────────────────
-- Supabase's default privileges also GRANT ALL ON TABLES to anon and
-- authenticated. 20260811090500_rls.sql revokes that and grants back only SELECT,
-- and every table is created before it runs — but re-stating it here means the
-- last migration is the complete picture rather than something spread over three
-- files.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA public FROM authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

DO $tables$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s:%s', table_name, privilege_type), ', ')
    INTO v_bad
    FROM information_schema.role_table_grants
   WHERE table_schema = 'public'
     AND grantee IN ('anon', 'authenticated')
     AND (grantee = 'anon'
          OR privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'LOCKDOWN: unexpected table privileges: %', v_bad;
  END IF;
END $tables$;
