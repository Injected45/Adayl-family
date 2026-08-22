-- ============================================================================
--  جمعية العدايل — 2026-08-22.  المفتاح: عمرٌ، وجهازٌ لا يختاره صاحبه.
--
--  ⚠ NO LOCKDOWN SWEEP AND NO ALLOW-LIST IN THIS FILE, DELIBERATELY. Both
--    functions below are CREATE OR REPLACE at signatures that already exist,
--    so Postgres keeps their ACLs and there is nothing to re-grant. The 26 KB
--    file that rebuilt client_callable_functions() and swept every grant is
--    the one that rolled back on the live project, and the part that made it
--    big was the part that was never needed.
--
--  ── قفلان على المفتاح ─────────────────────────────────────────────────────
--    ١. يبطل بعد سبعة أيام، وإعادة الإصدار تُعيد ضبط المدّة.
--    ٢. الجهاز من ترويسة الطلب وحدها؛ لم يعد المتصل يسمّي جهازه بنفسه.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    It touches no existing key and locks nobody out.
-- ============================================================================

BEGIN;

-- ── ١. عمر المفتاح ──────────────────────────────────────────────────────
ALTER TABLE public.adeel_access_codes
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- A key already in the field gets the same clock, measured from when it was
-- issued — so one handed over today keeps six days rather than dying now.
UPDATE public.adeel_access_codes
   SET expires_at = issued_at + interval '7 days'
 WHERE expires_at IS NULL;

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

  -- ⚠ AND ISSUING RESETS THE CLOCK. Without expires_at in the UPDATE
  --   branch the ON CONFLICT path keeps the ORIGINAL expiry, so reissuing to
  --   a man whose first code had lapsed would hand him a key that was
  --   already dead — and the admin would watch him fail with a code issued
  --   one minute earlier.
  INSERT INTO public.adeel_access_codes
    (adeel_id, code, issued_by, expires_at)
  VALUES (p_adeel_id, v_code, auth.uid(), now() + interval '7 days')
  ON CONFLICT (adeel_id) DO UPDATE SET
    code = excluded.code, issued_at = now(), issued_by = excluded.issued_by,
    expires_at = excluded.expires_at,
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


-- ── ٢. ولا عدّاد للمحاولات، وهذا قرارٌ لا سهو ────────────────────────────
--
-- ⚠ IT WAS BUILT, MEASURED, AND REMOVED. A throttle that counts failed
--   redemptions CANNOT WORK inside this function: RAISE EXCEPTION aborts the
--   subtransaction and takes the INSERT that recorded the attempt down with
--   it. Seven wrong codes were tried against a working build of it and ONE
--   row survived — the successful one. PostgREST gives each RPC its own
--   transaction, so a failed redemption commits nothing, not even the fact
--   that it failed.
--
--   Making it work needs either an autonomous transaction (the dblink
--   extension) or a function that RETURNS failure instead of raising — and
--   that changes the contract every installed handset depends on.
--
-- ⚠ AND IT WOULD GUARD ALMOST NOTHING. Twelve characters from a thirty-letter
--   alphabet is 30^12 ≈ 5×10^17. What actually threatens an access code is a
--   slip of paper being forwarded, not a machine guessing it — and that is
--   what the seven-day expiry above answers.
--
--   Written down because a rate limit is the obvious thing to reach for here,
--   and whoever notices its absence should find the measurement rather than
--   repeat it.


-- ── ٣. الجهاز من الترويسة ───────────────────────────────────────────────
--
-- ⚠ THE ONE-ARGUMENT OVERLOAD MUST GO, AND THIS IS NOT TIDYING. The original
--   redeem_adeel_code(text) predates the device lock and establishes NO
--   binding at all. PATCH_20260817 dropped it — but a project where that
--   patch landed differently, or where the bundle was reapplied, carries
--   BOTH. PostgREST dispatches on the NAMED parameters it is given, so a
--   client sending only p_code would silently reach the unprotected one and
--   bind nobody to any handset, with nothing on screen to show for it.
--
--   Found on a rebuilt copy of this schema, where both were present.
--   Dropping it makes the wrong choice impossible rather than unlikely.
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

  -- ⚠ A KEY THAT WAS NEVER USED STOPS BEING A KEY. A slip of paper handed
  --   over months ago, or photographed into a WhatsApp group, worked forever:
  --   there was no clock on it at all. Seven days is long enough to reach a
  --   man in the جمعية and short enough that a lost code is a dead code,
  --   and reissuing costs the admin one tap.
  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'انتهت صلاحية هذا الرمز، اطلب رمزاً جديداً من الإدارة'
      USING ERRCODE = 'RUL14';
  END IF;

  -- One code, one man. A second person redeeming the same code would get his own
  -- read-only view of someone else's figures — which is a decision for the admin
  -- to make by reissuing, not something a forwarded WhatsApp message should be
  -- able to do.
  IF v_row.redeemed_at IS NOT NULL AND v_row.redeemed_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'هذا الرمز مستعمل بالفعل، اطلب رمزاً جديداً'
      USING ERRCODE = 'RUL14';
  END IF;

  -- ⚠ THE HEADER, AND ONLY THE HEADER — p_device_id IS NOW INERT.
  --
  --   Letting the CALLER name the handset he was claiming made
  --   «عديل واحد، جهاز واحد» a request rather than a rule: two phones
  --   send the same string, both hold the binding, and the register
  --   afterwards shows one device id with nothing in it to say two men are
  --   behind it.
  --
  --   The header is client-set too and can be forged — but forgery was never
  --   the threat. SHARING is, and a forwarded code plus a hand-typed device
  --   id was sharing with the lock left hanging open.
  --
  --   The argument stays so no installed handset breaks. Same treatment
  --   p_spent_at got the day a voucher could be dated tomorrow: keep the
  --   parameter, ignore the value, take the fact from the server.
  v_device := public.request_device_id();
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


-- ── ولا نصدّق ما لم نُشغّله ──────────────────────────────────────────────
--
-- ⚠ RUN, NOT MERELY CREATED. Two files in a row were syntactically perfect and
--   raised on their first real call. This reaches the expiry branch with a
--   real row and removes it again, so a broken body cannot reach the
--   association.
DO $smoke$
DECLARE
  v_adeel bigint;
  v_n     int;
BEGIN
  SELECT count(*) INTO v_n FROM public.adeel_access_codes
   WHERE expires_at IS NULL;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'بقي % مفتاحاً بلا تاريخ انتهاء', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ما زال هناك % نسخة من redeem_adeel_code', v_n;
  END IF;

  SELECT id INTO v_adeel FROM public.adeels ORDER BY id LIMIT 1;
  IF v_adeel IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.adeel_access_codes
                      WHERE adeel_id = v_adeel) THEN
    INSERT INTO public.adeel_access_codes (adeel_id, code, expires_at)
    VALUES (v_adeel, 'SMOKETESTCODE', now() - interval '1 day');

    SELECT count(*) INTO v_n FROM public.adeel_access_codes
     WHERE code = 'SMOKETESTCODE' AND expires_at < now();
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'تعذّر إنشاء مفتاح منتهٍ للاختبار';
    END IF;

    DELETE FROM public.adeel_access_codes WHERE code = 'SMOKETESTCODE';
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
