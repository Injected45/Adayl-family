-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-14 (b).  إغلاقُ منطقة الخطر، وقفلُ الدخول.
--
--  ما الذي يفعله هذا الملف
--
--  ١. منطقةُ الخطر تُغلق من قاعدة البيانات، لا من الشاشة وحدها.
--     «مسح البيانات المالية» و«مسح كل البيانات» تُرفعان من قائمة الدوالّ التي
--     يستطيع التطبيق استدعاءها. الشاشةُ الجديدة لا تُظهرهما، وحتى هاتفُ أدمن
--     عليه نسخةٌ قديمة من التطبيق يُرفض طلبُه ولا يُحذف شيء. الدالّتان تبقيان
--     في القاعدة ولا يصل إليهما إلا محرّرُ SQL.
--
--  ٢. المشتركُ يُربط بجهازه وبدخوله معًا.
--     • من سجّل خروجه — بزرّ الخروج، أو بمسح بيانات التطبيق، أو بإعادة تثبيته —
--       لا يدخل إلا بمفتاحٍ جديد من الأدمن.
--     • ومن غيّر جهازه لا يدخل إلا بمفتاحٍ جديد من الأدمن (وهذا كان قائمًا).
--     • والمفتاحُ يُستعمل مرّةً واحدة: المفتاحُ القديم لا يُعيد صاحبَه.
--
--  ⚠ كيف يُعرف «الدخول»: كلُّ دخولٍ بـ Google يُنشئ جلسةً لها رقم، ويحمل التطبيقُ
--    هذا الرقم في كلّ طلب، ويبقى الرقمُ نفسُه طوال بقاء المشترك داخل التطبيق —
--    لا يتغيّر بتجديد الاتصال التلقائيّ. الخروجُ ثمّ الدخولُ يُنشئ رقمًا جديدًا،
--    فلا يطابق الرقمَ المحفوظ، فيُطلب المفتاح.
--
--  ⚠ لا يُطرد أحدٌ الآن. المشتركون الداخلون حاليًّا يبقون داخلين كما هم، لأنّ
--    دخولهم سابقٌ لهذا الملف. القاعدةُ تسري على كلّ دخولٍ جديد من لحظة التشغيل.
--
--  ⚠ لا يتغيّر أيُّ رقمٍ ماليّ، ولا الأدمن: دخولُ الأدمن لا يمرّ بهذا القفل.
--
--  للتشغيل: SQL Editor ← New query ← الصق ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.redeem_adeel_code(text,text)') IS NULL
     OR to_regprocedure('public.unbind_adeel(bigint)') IS NULL THEN
    RAISE EXCEPTION 'ترقيعاتُ الدخول السابقة غير مطبّقة — هذا الملف لا يناسب هذه القاعدة.';
  END IF;
  IF to_regclass('auth.sessions') IS NULL THEN
    RAISE EXCEPTION 'جدول auth.sessions غير موجود — هذا ليس مشروع Supabase.';
  END IF;
  -- ⚠ يُقرأ الآن، بالدور الذي سيملك الدوالّ: إن لم يكن مقروءًا فالأفضل أن
  --   يفشل الملف هنا من أن تفشل كلُّ طلبات المشتركين بعده.
  PERFORM 1 FROM auth.sessions LIMIT 1;
END $prereq$;

-- == 1. العمودان ============================================================
-- الجلسةُ التي فُتح بها المفتاح.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS session_id text;

-- لحظةُ بدء القاعدة. تُكتب مرّةً واحدة ولا تتحرّك بإعادة تشغيل الملف — لو
-- تحرّكت لصار كلُّ دخولٍ بين التشغيلين دخولًا قديمًا يُعفى من المفتاح.
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS member_session_since timestamptz;

UPDATE public.association_settings
   SET member_session_since = now()
 WHERE member_session_since IS NULL;

-- == 2. رقمُ الجلسة من الطلب ================================================
-- ⚠ من الـ JWT الذي وقّعه الخادم، لا من ترويسةٍ يكتبها التطبيق. رقمُ الجهاز
--   ترويسةٌ يمكن تقليدها؛ رقمُ الجلسة لا.
CREATE OR REPLACE FUNCTION public.request_session_id()
RETURNS text
LANGUAGE sql
STABLE
AS $rs$
  SELECT nullif(btrim(coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id',
    '')), '')
$rs$;

-- == 3. هل هذا الدخولُ هو المفتوحُ بالمفتاح؟ ===================================
-- ⚠ حالتان فقط تُقبلان:
--   • الجلسةُ المحفوظة هي جلسةُ هذا الطلب؛
--   • أو لم تُحفظ جلسةٌ بعد، وجلسةُ هذا الطلب أقدمُ من بدء القاعدة — أي
--     مشتركٌ كان داخلًا يوم شُغّل هذا الملف، فلا يُطرد.
--   كلُّ دخولٍ أُنشئ بعد التشغيل ولم يُفتح بمفتاح يُرفض.
CREATE OR REPLACE FUNCTION public.my_session_ok()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $mso$
  SELECT EXISTS (
    SELECT 1
      FROM public.profiles p
     WHERE p.id = auth.uid()
       AND public.request_session_id() IS NOT NULL
       AND (
             p.session_id = public.request_session_id()
          OR (p.session_id IS NULL
              AND EXISTS (
                    SELECT 1
                      FROM auth.sessions s
                     WHERE s.user_id = p.id
                       AND s.id::text = public.request_session_id()
                       AND s.created_at < (SELECT a.member_session_since
                                             FROM public.association_settings a
                                            LIMIT 1)))
       )
  )
$mso$;

-- == 3b. my_adeel_id: الجهازُ والدخولُ معًا ===================================
-- ⚠ كلُّ سياسةٍ تخصّ المشترك تمرّ من هنا — المستحقّات، الإيصالات، الكشف،
--   المحادثات، المكالمات، الإشعارات — فشرطٌ واحدٌ هنا يُغلقها كلَّها معًا.
CREATE OR REPLACE FUNCTION public.my_adeel_id()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT p.adeel_id
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.device_id IS NOT NULL
     AND p.device_id = public.request_device_id()
     AND public.my_session_ok()
$function$;

-- == 4. redeem_adeel_code: مفتاحٌ واحدٌ لدخولٍ واحد ==========================
CREATE OR REPLACE FUNCTION public.redeem_adeel_code(p_code text, p_device_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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

  -- ── ⚠ حسابٌ مربوطٌ بعديل لا يُربط بعديلٍ آخر، ويُقال له لماذا ───────────
  --
  --   THIS WAS ALREADY REFUSED and that is worth stating plainly: the UPDATE
  --   at the end of this function trips guard_profile_change, which raises
  --   «FORBIDDEN: cannot change your own عديل binding». The rule was never
  --   missing. What was missing was SAYING SO — the association typed
  --   عبدالعزيز's key into a handset bound to ايمن, saw a bare refusal, pressed
  --   again, and was let in by a different door entirely (see §1). A refusal
  --   nobody can read is a refusal nobody trusts, and it sent an hour of
  --   testing looking at the wrong thing.
  --
  -- ⚠ AND IT MUST NOT REFUSE HIS OWN KEY. Re-redeeming the SAME عديل is the
  --   ordinary case — a new phone, a reissued code — so the test is «a
  --   DIFFERENT عديل», never «already bound».
  IF v_me.adeel_id IS NOT NULL AND v_me.adeel_id IS DISTINCT FROM
     (SELECT adeel_id FROM public.adeel_access_codes
       WHERE code = upper(regexp_replace(coalesce(p_code,''),'[^0-9A-Za-z]','','g'))) THEN
    RAISE EXCEPTION 'هذا الحساب مرتبط بعديلٍ آخر. لفكّ الارتباط راجع إدارة الجمعية'
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
  -- ⚠ مفتاحٌ استُعمل مرّةً لا يُستعمل ثانيةً — ولا لصاحبه (PATCH_20260914b).
  --   The old rule let the SAME account redeem its own used key again for as
  --   long as the key lived, so a member who signed out could walk back in
  --   within seven days with the slip he already had. The association's rule
  --   is «لا يفتح إلا بمفتاح جديد يستلمه من الأدمن».
  --
  -- ⚠ ONE EXCEPTION, AND IT CHANGES NOTHING: the same account, on the same
  --   handset, in the same login, already bound to this عديل. That is a retry
  --   of a redemption that succeeded while the reply was lost on a slow
  --   connection — answering it «مستعمل» would tell a man who is already in
  --   that he is locked out.
  IF v_row.redeemed_at IS NOT NULL THEN
    IF v_row.redeemed_by = auth.uid()
       AND v_me.adeel_id = v_row.adeel_id
       AND v_me.device_id IS NOT DISTINCT FROM public.request_device_id()
       AND v_me.session_id IS NOT DISTINCT FROM public.request_session_id() THEN
      RETURN jsonb_build_object(
        'adeelId', v_row.adeel_id,
        'adeelCode', (SELECT adeel_code FROM public.adeels WHERE id = v_row.adeel_id));
    END IF;
    RAISE EXCEPTION 'هذا المفتاح استُعمل من قبل، اطلب مفتاحاً جديداً من الإدارة'
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

  -- ⚠ والدخولُ نفسُه يُربط مع الجهاز. GoTrue puts the login's id in every
  --   access token as `session_id`, and keeps it across silent refreshes; only
  --   a NEW sign-in makes a new one. Binding it here is what makes «سجّل خروجاً
  --   فلا يفتح إلا بمفتاح جديد» true whichever way the old login ended —
  --   the sign-out button, clearing the app's data, or reinstalling it.
  IF public.request_session_id() IS NULL THEN
    RAISE EXCEPTION 'تعذّر التعرّف على جلسة الدخول، سجّل الدخول من جديد'
      USING ERRCODE = 'RUL14';
  END IF;

  -- الحسابُ الذي فعّل هذا العديل أوّلَ مرّة هو صاحبُه، ولا يُنزع منه.
  IF EXISTS (SELECT 1 FROM public.profiles
              WHERE adeel_id = v_row.adeel_id AND id <> auth.uid()) THEN
    RAISE EXCEPTION
      'هذا العديل مرتبط ببريدٍ آخر. لا يُفتح إلا بنفس البريد، أو تفكّ الإدارة الارتباط'
      USING ERRCODE = 'RUL14';
  END IF;

  UPDATE public.profiles
     SET adeel_id  = v_row.adeel_id,
         status    = 'approved',
         role      = 'viewer',
         device_id = v_device,
         session_id = public.request_session_id()
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
END $function$;

-- == 5. issue_adeel_code: المفتاحُ الجديد يُغلق الجهاز والدخول معاً ==========
CREATE OR REPLACE FUNCTION public.issue_adeel_code(p_adeel_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
  -- ⚠ AND THE LOGIN WITH IT (PATCH_20260914b). The next redemption binds a
  --   device and a session together; clearing only one would leave the other
  --   holding a value from a key that no longer exists.
  UPDATE public.profiles
     SET device_id = NULL,
         session_id = NULL
   WHERE adeel_id = p_adeel_id
     AND (device_id IS NOT NULL OR session_id IS NOT NULL);

  PERFORM public.write_audit('adeel.code.issue',
    format('إصدار رمز دخول للعديل %s', v_adeel.adeel_code), v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', p_adeel_id, 'adeelCode', v_adeel.adeel_code, 'code', v_code_fmt);
END $function$;

-- == 6. unbind_adeel ==========================================================
CREATE OR REPLACE FUNCTION public.unbind_adeel(p_adeel_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_adeel record;
  v_who   text;
  v_n     int;
BEGIN
  PERFORM public.require_role('admin');

  SELECT id, adeel_code, full_name INTO v_adeel
    FROM public.adeels WHERE id = p_adeel_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  SELECT string_agg(coalesce(nullif(email,''), id::text), ', '), count(*)
    INTO v_who, v_n
    FROM public.profiles WHERE adeel_id = p_adeel_id;

  UPDATE public.profiles
     SET adeel_id = NULL, device_id = NULL, session_id = NULL, status = 'pending'
   WHERE adeel_id = p_adeel_id;

  DELETE FROM public.adeel_access_codes WHERE adeel_id = p_adeel_id;

  PERFORM public.write_audit('adeel.unbind',
    format('فكّ ارتباط العديل %s عن %s', v_adeel.adeel_code,
           coalesce(v_who, 'لا حساب')),
    v_adeel.adeel_code);

  RETURN jsonb_build_object('adeelId', p_adeel_id,
                            'adeelCode', v_adeel.adeel_code,
                            'unbound', coalesce(v_n, 0));
END $function$;

-- == 7. api_me: علامةُ القفل =================================================
CREATE OR REPLACE FUNCTION public.api_me()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
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
    -- ⚠ SINCE 14/09 IT ALSO MEANS «a login the admin never keyed». Same
    --   destination either way — the code box — and computed from exactly what
    --   my_adeel_id() decides on, so the sentence and the refusal agree.
    'deviceLocked', (p.adeel_id IS NOT NULL
                     AND (p.device_id IS DISTINCT FROM public.request_device_id()
                          OR NOT public.my_session_ok())))
  FROM public.profiles p WHERE p.id = auth.uid()
$function$;

-- == 8. قائمةُ السماح: تُرفع دالّتا المسح، وتُضاف دالّةُ الجلسة ================
-- ⚠ تُقرأ القائمةُ حيّةً ويُعدَّل فيها ثلاثةُ مُدخلات فقط.
DO $allow$
DECLARE
  v_old text[] := public.client_callable_functions();
  v_new text[];
BEGIN
  SELECT coalesce(array_agg(x ORDER BY ord), '{}'::text[]) INTO v_new
    FROM unnest(v_old) WITH ORDINALITY AS t(x, ord)
   WHERE replace(x, ' ', '') NOT IN ('purge_financial_data(text)',
                                     'purge_all_data(text)');

  IF NOT ('my_session_ok()' = ANY (SELECT replace(a, ' ', '') FROM unnest(v_new) a)) THEN
    v_new := v_new || 'my_session_ok()'::text;
  END IF;

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

-- == 9. المسحة، بعد آخر CREATE في هذا الملف ================================
-- ⚠ هي التي تسحب EXECUTE من دالّتي المسح فعلًا، وتمنح my_session_ok لأنّ
--   api_me — وهي بصلاحيّة المستدعي — تستدعيها.
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

-- == 10. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 11. النتيجة: آخرُ جدولٍ يظهر في المحرّر، وكلُّ صفٍّ يجب أن يقول true ======
SELECT 'التطبيقُ لا يستطيع «مسح البيانات المالية»' AS "الفحص",
       NOT has_function_privilege('authenticated',
             'public.purge_financial_data(text)', 'EXECUTE') AS "النتيجة"
UNION ALL SELECT 'ولا «مسح كل البيانات»',
       NOT has_function_privilege('authenticated',
             'public.purge_all_data(text)', 'EXECUTE')
UNION ALL SELECT 'والمفتاحُ يربط الجهازَ والدخولَ معًا',
       (SELECT prosrc LIKE '%session_id = public.request_session_id()%'
          FROM pg_proc WHERE oid = 'public.redeem_adeel_code(text,text)'::regprocedure)
UNION ALL SELECT 'والمفتاحُ المستعملُ لا يُستعمل ثانيةً',
       (SELECT prosrc LIKE '%استُعمل من قبل%'
          FROM pg_proc WHERE oid = 'public.redeem_adeel_code(text,text)'::regprocedure)
UNION ALL SELECT 'وكلُّ سياسات المشترك تشترط الدخولَ المفتوح بالمفتاح',
       (SELECT prosrc LIKE '%my_session_ok()%'
          FROM pg_proc WHERE oid = 'public.my_adeel_id()'::regprocedure)
UNION ALL SELECT 'ولحظةُ بدء القاعدة مسجّلة (المشتركون الداخلون الآن لا يُطردون)',
       (SELECT member_session_since IS NOT NULL FROM public.association_settings LIMIT 1)
UNION ALL SELECT 'والأدمن ما زال يدخل (حسابٌ معتمد واحد على الأقلّ)',
       EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin' AND status = 'approved');

COMMIT;
