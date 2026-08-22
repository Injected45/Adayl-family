-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (k).  إعادة ما سقط من قائمة السماح.
--
--  ⚠ WHAT BROKE, AND HOW. «الجدوى» started answering 42501 —
--    insufficient_privilege — because `api_member_value(bigint)` was no
--    longer granted to `authenticated`. So was `api_aid_others(bigint)`,
--    which is «أسلاف للغير».
--
--    Neither was deleted. Both fell OFF the allow-list: PATCH_20260821d
--    rewrote client_callable_functions() by hand from the ORIGINAL migration,
--    which predates the patches that ADDED those two — and d, e and j then
--    carried the truncated list forward. The lockdown sweep does exactly what
--    it is told: anything not on the list is revoked.
--
--  ⚠ AND THE FOUR GUARDS COULD NOT SEE IT, which is the part worth fixing.
--    assert_function_grants() asserts the list is EXACT in both directions:
--    everything listed is granted, and nothing granted is unlisted. A
--    function REMOVED from the list is revoked — so both directions pass, and
--    a capability vanishes in silence. The guard protects the list; nothing
--    protected the list from getting shorter.
--
--    §2 adds the guard that would have caught it on the first run:
--    **every public.api_* function must be callable.** They exist for exactly
--    one purpose — to be called by the client — so one that exists and is not
--    granted is a broken screen with no error until somebody taps it.
--
--  ⚠ AND THE LIST BELOW IS THE UNION OF EVERY VERSION EVER SHIPPED, computed
--    from the files rather than retyped, minus the two signatures that were
--    genuinely REPLACED (redeem_adeel_code gained a device argument,
--    send_signal gained a recipient). Leaving a dropped signature on the list
--    fails assert_function_grants in the other direction.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

-- ── §1. القائمة الكاملة ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    'my_adeel_id()',
    'request_device_id()',
    'members_held(bigint)',
    'register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_adeel(bigint,jsonb)',
    'delete_adeel(bigint)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    'purge_financial_data(text)',
    'purge_all_data(text)',
    'issue_adeel_code(bigint)',
    'redeem_adeel_code(text,text)',
    'register_disbursement(numeric,disbursement_kind,pay_method,bigint,expense_category,text,text,text,text,text,text,date)',
    'cancel_disbursement(bigint,text)',
    'in_association()',
    'send_chat_message(text,bigint)',
    'delete_chat_message(bigint)',
    'period_label(text)',
    'adeel_json(bigint)',
    'api_adeel_detail(bigint)',
    'api_adeel_statement(bigint)',
    'api_adeel_aid(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_closable_periods()',
    'api_settings()',
    'api_me()',
    'api_touch_login()',
    'api_association_finance()',
    'api_aid_others(bigint)',
    'api_member_value(bigint)',
    'api_ice_servers()',
    'may_join_thread(bigint)',
    'start_call(bigint)',
    'answer_call(bigint)',
    'end_call(bigint,boolean)',
    'send_signal(bigint,text,jsonb,uuid)',
    'join_call(bigint)',
    'heartbeat_call(bigint)',
    'leave_call(bigint)',
    'revoke_all_adeel_access(text)'
  ]::text[]
$$;


-- ── §2. الحارس الذي كان ناقصاً ──────────────────────────────────────────
--
-- ⚠ EVERY api_* FUNCTION MUST BE CALLABLE. That is what the prefix MEANS in
--   this schema: these are the reads and the aggregates the client asks for
--   by name. One that exists and is not granted is not a security posture, it
--   is a screen that answers 42501 the moment somebody opens it — and no
--   existing guard could tell, because a function missing from the allow-list
--   is revoked, and "revoked and unlisted" is a state assert_function_grants
--   considers correct.
--
-- ⚠ IT NAMES WHAT IS MISSING, not that something is. A patch rolled back with
--   «api_member_value(bigint)» in the message is one line from fixed.
CREATE OR REPLACE FUNCTION public.assert_api_functions_callable()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(sig, ', ' ORDER BY sig) INTO v_missing
    FROM (
      SELECT p.oid::regprocedure::text AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND p.proname LIKE 'api\_%'
         AND NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
    ) q;

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these api_* functions exist but the app cannot call them: %',
      v_missing;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.assert_api_functions_callable() FROM PUBLIC, anon, authenticated;


-- ── §3. كنس الصلاحيات ───────────────────────────────────────────────────
-- Lifted verbatim from 20260811091200_function_lockdown.sql.
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


-- ── §4. الحُرّاس، والجديد معهم ──────────────────────────────────────────
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_api_functions_callable();

COMMIT;
