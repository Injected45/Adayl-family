-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (j).  مسح دخول كل المشتركين.
--
--  WHAT THIS ADDS
--    revoke_all_adeel_access(p_confirm) — admin-only, behind its own typed
--    phrase: it VOIDS every access code and unbinds every handset in one act.
--    After it, no عديل can open the app at all until the admin issues him a
--    NEW key.
--
--  ⚠ WHAT IT DOES NOT DO, AND MUST NOT. It does NOT clear
--    `profiles.adeel_id`. That looks like the tidy thing and it is a privilege
--    ESCALATION: `my_role()` returns NULL only while an adeel_id is set, so a
--    man stripped of his binding becomes a plain approved `viewer` — and a
--    viewer reads the WHOLE association. Unbinding is done by clearing the
--    DEVICE, which is what my_adeel_id() actually tests.
--
--  ⚠ AND IT DELETES THE CODES RATHER THAN REGENERATING THEM. A fresh code
--    would let anyone who still had the old paper slip in; an ABSENT code
--    cannot be redeemed at all. The admin then issues them one by one, which
--    is also the only moment he can hand each man his own key in person.
--
--  ── الدستور، وأين هو مكتوب فعلاً ────────────────────────────────────────────
--  «عندما أُصدر مفتاحاً جديداً لمشترك يبطل القديم ويغلق التطبيق فوراً ولن يفتح
--   من جديد إلا بالمفتاح الجديد».
--
--  That rule is ALREADY enforced by issue_adeel_code, and it is worth naming
--  where, because it is not in the app:
--
--    1. `ON CONFLICT (adeel_id) DO UPDATE SET code = excluded.code` — one row
--       per عديل, so a new code OVERWRITES the old one. The old key stops
--       existing; it is not merely disfavoured.
--    2. `UPDATE profiles SET device_id = NULL` — the handset that held it is
--       released in the same statement.
--    3. `my_adeel_id()` returns NULL unless `device_id` equals the
--       `x-device-id` request header. NULL is a REFUSAL, not a pass — so every
--       عديل-scoped policy hands the old phone nothing, immediately, with no
--       app update and no cooperation from the client.
--
--  The app's part is only to SAY so: api_me() reports `deviceLocked`, and the
--  router now sends a locked account to the code screen and nowhere else.
--
--  ⚠ AND A MEMBER CAN NEVER REACH THE ADMIN APP. Not by a screen check —
--    `my_role()` is NULL for anyone with an adeel_id, so every staff policy
--    refuses him at the database. The router pinning him to his own page is
--    presentation on top of a wall that already stands.
--    supabase/tests/45_adeel_portal.sql proves both directions.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ It does NOT revoke anything by itself — see the last section for the one
--      line that does, which is deliberately separate so this file can be
--      applied without emptying anything.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.adeel_access_codes') IS NULL THEN
    RAISE EXCEPTION
      'لا يوجد جدول رموز الدخول. طبّق PATCH_20260817 أولاً.';
  END IF;
END
$prereq$;


CREATE OR REPLACE FUNCTION public.revoke_all_adeel_access(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_codes   bigint;
  v_devices bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- ⚠ ITS OWN PHRASE, and deliberately not one of the purge phrases. The three
  --   are compared with `<>`, so an admin who typed the wrong one into the
  --   wrong box is refused rather than doing the wrong irreversible thing.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح دخول المشتركين' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  SELECT count(*) INTO v_codes   FROM public.adeel_access_codes;
  SELECT count(*) INTO v_devices FROM public.profiles
   WHERE adeel_id IS NOT NULL AND device_id IS NOT NULL;

  -- Every key void. An absent code cannot be redeemed; a regenerated one could
  -- be, by whoever still held the paper.
  DELETE FROM public.adeel_access_codes;

  -- Every handset released. This — not the code — is what my_adeel_id() tests,
  -- so this is the line that actually shuts the running apps.
  UPDATE public.profiles
     SET device_id = NULL
   WHERE adeel_id IS NOT NULL
     AND device_id IS NOT NULL;

  -- ⚠ adeel_id IS LEFT ALONE. See the header: clearing it would turn every
  --   member into a plain approved viewer, who reads the whole association.

  PERFORM public.write_audit('adeel.access.revoke_all',
    format('مسح دخول كل المشتركين: %s رمزاً و%s جهازاً', v_codes, v_devices),
    'adeels');

  RETURN jsonb_build_object('codes', v_codes, 'devices', v_devices);
END $$;


-- ── قائمة الدوال، ثم كنس الصلاحيات ─────────────────────────────────────────
--
-- ⚠ A FRESH FUNCTION HAS NO ACL TO KEEP, so Postgres gives it the built-in
--   default of EXECUTE TO PUBLIC and assert_no_public_execute() would roll this
--   patch back naming it. The sweep is lifted verbatim from
--   supabase/migrations/20260811091200_function_lockdown.sql — a hand-written
--   one using pg_get_function_identity_arguments() matches nothing but the
--   zero-argument functions, which cost one rolled-back patch already today.
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
    'revoke_all_adeel_access(text)',
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
    'api_ice_servers()',
    'may_join_thread(bigint)',
    'start_call(bigint)',
    'answer_call(bigint)',
    'end_call(bigint,boolean)',
    'send_signal(bigint,text,jsonb,uuid)',
    'join_call(bigint)',
    'heartbeat_call(bigint)',
    'leave_call(bigint)'
  ]::text[]
$$;

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


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
