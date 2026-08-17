-- ============================================================================
--  جمعية العدايل — PATCH: one عديل, one device.  2026-08-17.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  WHAT THIS DOES
--
--  An عديل's access code now opens the portal on ONE handset. The same account,
--  signed in with the same Google address on a second phone, sees nothing —
--  which is what the association asked for.
--
--  ⚠ IT IS NOT A MAC ADDRESS, AND NOTHING CAN BE.
--     Android has returned the constant 02:00:00:00:00:00 to every app since
--     API 23 and randomises the real one per network since Android 10; iOS
--     never exposed it. What the app sends is a SHA-256 of ANDROID_ID (or
--     identifierForVendor), which is the closest stable per-device value the
--     platform still gives out. It survives app updates and reinstalls and
--     changes on a factory reset.
--
--  HOW IT IS ENFORCED
--     `my_adeel_id()` — the function EVERY عديل-scoped RLS policy goes through
--     — compares profiles.device_id against the `x-device-id` request header
--     and returns NULL when they differ. Returning NULL is the mechanism: it
--     matches no row, so the wrong handset gets an empty portal. Putting the
--     check in the portal's read functions instead would leave a client talking
--     to PostgREST directly completely unaffected.
--
--     Be clear about the limit: a header is set by the client, and the anon key
--     is public. This stops SHARING — a second handset, a lent Google password
--     — and it is not proof against someone who forges the header. The code
--     remains the authorisation; the device is a constraint on convenience.
--
--  THE THREE STATES, AND WHY THE MIDDLE ONE REFUSES
--     device_id IS NULL   → REFUSED. "Released, not yet claimed."
--     device_id = header  → allowed.
--     device_id <> header → refused.
--
--     Reading NULL as a pass would turn one admin click into an unlock for
--     every device at once, which is the opposite of the feature.
--
--  RELEASING A LOST PHONE
--     `issue_adeel_code` clears device_id. The عديل stays BOUND — clearing
--     adeel_id too would drop him to a plain approved viewer, who reads the
--     WHOLE association, so the unlock would be a privilege escalation with a
--     time window. He is locked out until the handset holding the new code
--     opens the app, and `api_touch_login` claims it. A second handset calling
--     the same function cannot steal a claim that is already held.
--
--  EXISTING عدايل ARE NOT LOCKED OUT.
--     Anyone already bound has device_id NULL after this patch, so the FIRST
--     handset that opens the app claims it — which for a member already using
--     the app is the phone in his hand. No reissue, no retyping.
--
--  ⚠ THIS PATCH CONTAINS ONE DROP, AND IT IS DELIBERATE
--       DROP FUNCTION IF EXISTS public.redeem_adeel_code(text)
--     CREATE OR REPLACE cannot add a parameter, and leaving the one-argument
--     version beside the two-argument one makes every call ambiguous (42725).
--     Dropping a FUNCTION destroys no data and touches no row. Its EXECUTE
--     grant goes with it and is re-issued by the lockdown sweep in section 9.
--
--     Nothing else is dropped. No DROP SCHEMA, no DROP TABLE, no DROP TRIGGER,
--     no TRUNCATE, no DELETE, and nothing touching auth.users or profiles rows.
--     assert_signin_intact() runs before COMMIT.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes. Safe to run twice.
-- ============================================================================

BEGIN;

-- == 1. The column =========================================================
-- Nullable, and NULL is a refusal rather than a pass. See the header.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS device_id text;

-- == 2. Which device is asking =============================================
-- Declared before my_adeel_id() uses it: check_function_bodies is on, so a SQL
-- function calling one Postgres has not seen yet fails at CREATE time.
CREATE OR REPLACE FUNCTION public.request_device_id() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT nullif(
    btrim(coalesce(
      current_setting('request.headers', true)::json ->> 'x-device-id', '')),
    '')
$$;

-- == 3. my_adeel_id — where the rule actually bites ========================
CREATE OR REPLACE FUNCTION public.my_adeel_id() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.adeel_id
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.device_id IS NOT NULL
     AND p.device_id = public.request_device_id()
$$;

-- == 4. redeem_adeel_code — the moment the lock is established =============
-- The DROP is the only one in this file; see the header.
DROP FUNCTION IF EXISTS public.redeem_adeel_code(text);

CREATE OR REPLACE FUNCTION public.redeem_adeel_code(
  p_code      text,
  p_device_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_norm   text;
  v_device text;
  v_row    record;
  v_me     record;
  v_adeel  record;
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

  -- The device this code is being spent on. The header is the fallback so a
  -- client that sets it globally does not have to pass it twice, but ONE of the
  -- two must arrive: an unlocked binding is not a weaker version of the
  -- feature, it is the absence of it, and it would be invisible afterwards.
  v_device := coalesce(nullif(btrim(coalesce(p_device_id, '')), ''),
                       public.request_device_id());
  IF v_device IS NULL THEN
    RAISE EXCEPTION 'تعذّر التعرّف على الجهاز، حدِّث التطبيق وأعد المحاولة'
      USING ERRCODE = 'RUL14';
  END IF;

  UPDATE public.profiles
     SET adeel_id  = v_row.adeel_id,
         status    = 'approved',
         role      = 'viewer',
         device_id = v_device
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

-- == 5. issue_adeel_code — reissuing releases the handset ==================
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

  -- ── Reissuing IS the way to release a lost phone ──────────────────────────
  -- Clearing device_id here is the only unlock the system has, and it was a
  -- deliberate choice over a second button: an عديل whose handset is stolen,
  -- wiped or replaced is otherwise locked out permanently, and the admin has to
  -- reissue his code in that situation anyway.
  --
  -- The binding itself (`adeel_id`) is deliberately LEFT ALONE. Clearing it too
  -- would drop him back to a plain approved viewer for as long as it took him
  -- to redeem again — and a viewer with no adeel_id reads the WHOLE
  -- association, because my_role() only returns NULL while an adeel_id is set.
  -- The unlock would have been a privilege escalation with a time window.
  --
  -- So he stays bound and stays locked out — my_adeel_id() refuses a NULL
  -- device_id — until the phone holding the new code opens the app and
  -- api_touch_login() claims it.
  UPDATE public.profiles
     SET device_id = NULL
   WHERE adeel_id = p_adeel_id
     AND device_id IS NOT NULL;

  PERFORM public.write_audit('adeel.code.issue',
    format('إصدار رمز دخول للعديل %s', v_adeel.adeel_code), v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', p_adeel_id, 'adeelCode', v_adeel.adeel_code, 'code', v_code_fmt);
END $$;

-- == 6. api_me and api_touch_login =========================================
-- api_me gains `deviceLocked`, which EXPLAINS the empty portal without being
-- what enforces it. api_touch_login claims an unclaimed device — the other half
-- of the release, and what keeps already-bound عدايل working after this patch.
CREATE OR REPLACE FUNCTION public.api_me() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', p.id::text,
    'email', p.email,
    'displayName', p.display_name,
    'pictureUrl', p.picture_url,
    'role', p.role::text,
    'status', p.status::text,
    'adeelId', p.adeel_id,
    'adeelCode', (SELECT a.adeel_code FROM public.adeels a WHERE a.id = p.adeel_id),
    -- ── Why the portal is empty, said out loud ──────────────────────────────
    -- my_adeel_id() enforces the one-device rule by returning NULL, so a عديل
    -- on the wrong handset gets a portal with no dues, no ledger and no
    -- explanation — which reads as a broken app, not as a rule.
    --
    -- This flag is the explanation, and it is deliberately NOT the enforcement:
    -- it is computed from the same three states my_adeel_id() decides on, but
    -- nothing depends on the client honouring it. Hiding the message would
    -- change what he is told, never what he can read.
    'deviceLocked', (p.adeel_id IS NOT NULL
                     AND p.device_id IS DISTINCT FROM public.request_device_id()))
  FROM public.profiles p WHERE p.id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.api_touch_login() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, auth AS $$
  UPDATE public.profiles
     SET last_login_at = now(),
         device_id = CASE
           WHEN adeel_id IS NOT NULL AND device_id IS NULL
             THEN public.request_device_id()
           ELSE device_id END
   WHERE id = auth.uid()
$$;

-- == 7. api_adeel_statement — the البيان column says WHAT, not which ref ====
-- A payment's particulars read `coalesce(nullif(p.reference,''), p.method)`, so
-- a transfer that carried a bank reference put a bare number in the statement —
-- "34871" beside 250.00, which tells a member nothing and reads like a second
-- amount. It now says the method: تحويل مصرفي or نقداً.
--
-- The reference is not lost. It stays on the payment row and on the collections
-- screen, where the treasurer reconciling against a bank statement is the
-- person who actually needs it.
CREATE OR REPLACE FUNCTION public.api_adeel_statement(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH movements AS (
    SELECT r.created_at AS at,
           r.period      AS reference,
           'استحقاق'::text AS kind,
           r.total       AS debit,
           NULL::numeric AS credit,
           public.period_label(r.period) AS note
      FROM public.receivables r
     WHERE r.adeel_id = p_adeel_id AND r.status <> 'ملغي'
    UNION ALL
    SELECT p.paid_at,
           p.receipt_no,
           'دفعة'::text,
           NULL::numeric,
           p.amount,
           -- ── The METHOD, in words. Not the transfer reference. ────────────
           -- This read `coalesce(nullif(p.reference,''), p.method::text)`, so a
           -- transfer that carried a reference put a bare number in the
           -- statement's البيان column — "34871" against 250.00, which tells a
           -- member nothing about what the line is and reads like a second
           -- amount next to the first.
           --
           -- The reference identifies the transfer to the BANK; it is not what
           -- the movement was. What it was is "تحويل مصرفي" or "نقداً", which is
           -- also the one thing on the line he can check against his own
           -- records. It stays on the payment row and on the collections
           -- screen, where a treasurer reconciling with a bank statement is the
           -- person who actually needs it.
           p.method::text
      FROM public.payments p
     WHERE p.adeel_id = p_adeel_id AND p.status <> 'ملغي'
  ), ordered AS (
    SELECT *,
           sum(coalesce(debit, 0) - coalesce(credit, 0))
             OVER (ORDER BY at, reference
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS balance
      FROM movements
  )
  SELECT jsonb_build_object(
    'movements', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'date', to_char(o.at AT TIME ZONE 'UTC', 'YYYY-MM-DD'),
                  'reference', o.reference,
                  'type', o.kind,
                  'debit', o.debit::text,
                  'credit', o.credit::text,
                  'balance', o.balance::text,
                  'note', o.note)
                ORDER BY o.at, o.reference)
         FROM ordered o),
      '[]'::jsonb),
    'closingBalance',
      coalesce((SELECT o.balance::text FROM ordered o
                 ORDER BY o.at DESC, o.reference DESC LIMIT 1), '0.00'))
$$;

-- == 8. The lockdown allow-list, restated for the new signature ============
-- An EXACT set. It has to name redeem_adeel_code(text,text) and the new
-- request_device_id(), or assert_function_grants() fails in both directions and
-- the whole patch rolls back.
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
    -- Echoes the caller's own x-device-id header back. api_me() is SECURITY
    -- INVOKER and calls it, so the caller must hold EXECUTE or every launch
    -- fails with "permission denied for function request_device_id".
    'request_device_id()',

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
    'redeem_adeel_code(text,text)',

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

-- == 9. Re-run the lockdown sweep ==========================================
-- Byte-for-byte the loop from 20260811091200_function_lockdown.sql, which runs
-- LAST on a full apply. A patch gets no such sweep for free, and every function
-- it creates FRESH — request_device_id here, redeem_adeel_code after the DROP —
-- comes out with the built-in default ACL, which is EXECUTE to PUBLIC. That is
-- the error that made an earlier patch roll back on every attempt.
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

-- == The standing guarantees, re-proven ====================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed.
SELECT 'profiles carries the device binding' AS check,
       (EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'profiles'
                   AND column_name = 'device_id'))::text AS ok
UNION ALL SELECT 'my_adeel_id refuses a device that does not match',
       (pg_get_functiondef('public.my_adeel_id()'::regprocedure)
          LIKE '%request_device_id%')::text
UNION ALL SELECT 'redeem_adeel_code now takes the handset too',
       (SELECT count(*) = 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code'
           AND p.pronargs = 2)::text
UNION ALL SELECT 'reissuing a code releases the handset',
       (pg_get_functiondef('public.issue_adeel_code(bigint)'::regprocedure)
          LIKE '%device_id = NULL%')::text
UNION ALL SELECT 'api_me explains the lock',
       (pg_get_functiondef('public.api_me()'::regprocedure)
          LIKE '%deviceLocked%')::text
UNION ALL SELECT 'a first launch claims an unclaimed handset',
       (pg_get_functiondef('public.api_touch_login()'::regprocedure)
          LIKE '%request_device_id%')::text
UNION ALL SELECT 'redeem_adeel_code is NOT callable by the anon key',
       (SELECT count(*) = 0 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace,
          LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code'
           AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR a.grantee = 'anon'::regrole))::text
-- Informational, not a pass/fail: right after the patch every bound عديل reads
-- "N / 0", and each one becomes claimed the next time he opens the app. A
-- boolean here would flip to false the moment the feature started working.
UNION ALL SELECT 'عدايل bound / of those, handset already claimed',
       ((SELECT count(*) FROM public.profiles WHERE adeel_id IS NOT NULL)::text
        || ' / ' ||
        (SELECT count(*) FROM public.profiles
          WHERE adeel_id IS NOT NULL AND device_id IS NOT NULL)::text)
UNION ALL SELECT 'Google sign-in trigger is STILL in place',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)::text
UNION ALL SELECT 'staff profiles untouched',
       (EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin'))::text;
