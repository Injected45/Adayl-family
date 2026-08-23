-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-23 (b).  بابٌ واحدٌ للعديل: المفتاح.
--
--  ⚠ REPORTED FROM A REAL TEST, AND IT IS THE WORST KIND OF HOLE THERE IS:
--    «الغيت اشتراك ايمن وحاولت برمز مشترك جديد على تلفون ايمن … تم رفض الدخول
--     في البداية ولكن بعد الضغط على زر الدخول اكثر من مره قبل الكود ودخل —
--     فتح التطبيق باسم ايمن مع ان المفتاح انا استخرجته من حساب عبدالعزيز».
--
--  ── ما حدث بالضبط، ولا علاقة له بالرمز المكتوب ─────────────────────────────
--    Two separate things happened and they were read as one.
--
--    THE REFUSAL WAS CORRECT AND WAS NOT THE CODE BOX. guard_profile_change
--    already refuses «cannot change your own عديل binding», so عبدالعزيز's key
--    typed on an account already bound to ايمن was rejected by the database,
--    exactly as it should be. Nothing there is broken.
--
--    THE ENTRY CAME FROM api_touch_login, WHICH NEEDS NO CODE AT ALL:
--
--        device_id = CASE WHEN adeel_id IS NOT NULL AND device_id IS NULL
--                      THEN public.request_device_id() ELSE device_id END
--
--    and issue_adeel_code — which is what «إلغاء الاشتراك / مفتاح جديد» runs —
--    does exactly this:
--
--        UPDATE public.profiles SET device_id = NULL WHERE adeel_id = ...
--
--    so revoking a member's key leaves precisely the state api_touch_login
--    reads as «unclaimed, go ahead». The app calls api_touch_login on EVERY
--    sign-in and EVERY session restore (auth_repository.dart, two call sites).
--    So the old handset re-claimed itself on its next launch, my_adeel_id()
--    answered again, and the portal opened under ايمن — with no code involved.
--    Pressing the button repeatedly simply gave one of those launches its
--    chance. It was never brute force, and a longer code would not have helped.
--
--  ⚠ SO «المفتاح الجديد يبطل القديم ويغلق التطبيق فوراً» WAS NEVER TRUE. It
--    closed for one moment and the old phone let itself back in.
--
--  ── الداء: عمودٌ يحمل معنيين ───────────────────────────────────────────────
--    `device_id IS NULL` meant two different things and nothing asked which:
--        «لم يُطالَب به بعد — أوّلُ استردادٍ يأخذه»
--        «أُلغِي عمداً — لا يُؤخذ إلّا برمزٍ جديد»
--    This is the same disease as `approved` in PATCH_20260822d, where one
--    column meant both «هذا الشخص هو من يقول» and «هذا الشخص من الإدارة».
--
--  ── وثغرةٌ ثانيةٌ ظهرت عند أوّل تشغيل ──────────────────────────────────────
--    assert_two_doors_only REFUSED this patch and named three accounts:
--    approved, holding no عديل, and not admins. The guard was right. They came
--    from set_user_access, which the SHORT version of PATCH_20260822d — the one
--    that actually applied — never narrowed. So «اعتماد» in شاشة المستخدمين
--    still manufactured strangers, one button at a time.
--
--  ── الدواء ─────────────────────────────────────────────────────────────────
--    §0  the three are sent back to «pending» — the code box, where an عديل
--        belongs. They could read nothing today (PATCH_20260822d), so this
--        takes away nothing; it removes a shape that must not exist.
--    §0b set_user_access refuses to leave a profile approved, unbound and not
--        an admin — the same sentence assert_two_doors_only refuses, so the
--        function and the guard cannot drift apart.
--    §1 api_touch_login stops claiming devices — it records the login and
--       nothing else. The claim was REDUNDANT as well as dangerous:
--       redeem_adeel_code has always set device_id itself.
--    §2 redeem_adeel_code refuses a cross-binding in words instead of leaving
--       the trigger to say «FORBIDDEN», and EVICTS any other account still
--       holding the same عديل — «مفتاحٌ واحد، رجلٌ واحد، حسابٌ واحد».
--    §3 a UNIQUE index makes «عديلٌ بحسابين» impossible rather than merely
--       unobserved. WHO_IS_DUP.sql existed because it had happened.
--    §4 assert_login_lockdown() so none of the three can be undone quietly.
--
--  ⚠ ATHAR: EVERY MEMBER WHOSE device_id IS CURRENTLY NULL NOW NEEDS A NEW
--    KEY. That is the point — until now those accounts were one app launch
--    away from letting themselves in. The report after COMMIT names them.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

-- ── §0. الغرباء الذين في الداخل الآن ───────────────────────────────────────
--
-- ⚠ THIS PATCH WAS REFUSED BY assert_two_doors_only ON THE FIRST RUN, naming
--   three accounts: ahmed.injax3@, fmhde77@, gaguuw661y@. The guard was right
--   and the patch was right — the DATABASE was carrying a state that should
--   not exist: approved, holding no عديل, and not an admin.
--
-- ⚠ THEY CAN READ NOTHING TODAY, and that is worth saying before anything is
--   changed: since PATCH_20260822d, my_role() ends «AND p.role = 'admin'», so
--   an approved viewer matches no staff policy anywhere, and my_adeel_id() is
--   NULL without a binding. This is not a live breach. It is the SHAPE of the
--   one that happened on 22/08, left standing — and «a permission that
--   silently grants nothing is worse than one that is refused» is this
--   project's own rule.
--
-- ⚠ WHERE THEY CAME FROM, because otherwise they come back: §0b. The 26 KB
--   version of PATCH_20260822d narrowed set_user_access and never applied —
--   the short version that DID apply carries §1..§5 and not that. So the
--   «اعتماد» button in شاشة المستخدمين still writes role=viewer,
--   status=approved onto an account with no عديل, which is a stranger inside,
--   made by the admin himself in the ordinary course of tidying a list.
--
--   Sending them back to `pending` costs them nothing they had, and puts them
--   where an عديل belongs: the code box. If any of the three is a real member,
--   issue him a key — that is the whole of the second door.
--
-- ⚠ `suspended` IS DELIBERATELY UNTOUCHED. A suspension must survive every
--   sweep, which is the correction PATCH_20260822d needed and got.
DO $strangers$
DECLARE v_who text; v_n int;
BEGIN
  SELECT string_agg(coalesce(nullif(email,''), id::text), ', '), count(*)
    INTO v_who, v_n
    FROM public.profiles
   WHERE status = 'approved' AND adeel_id IS NULL AND role <> 'admin';

  IF v_n > 0 THEN
    RAISE NOTICE 'أُعيد % حساباً إلى «بانتظار المفتاح»: %', v_n, v_who;
    UPDATE public.profiles
       SET status = 'pending'
     WHERE status = 'approved' AND adeel_id IS NULL AND role <> 'admin';
  END IF;
END $strangers$;


-- ── §0b. ولا يُصنع غريبٌ بعد اليوم ─────────────────────────────────────────
--
-- ⚠ THE MISSING HALF OF PATCH_20260822d. That patch put «بابان لا ثالث لهما»
--   into my_role() — one clause, so every policy inherits it — and wiped the
--   accounts that were already inside. It did not close the FACTORY, and the
--   factory is one button on a screen the admin uses every week.
--
--   The refusal is written against the STATE THAT MUST NOT EXIST rather than
--   against the role being asked for, because the two are not the same
--   question: promoting somebody to admin is fine, suspending anybody is fine,
--   approving a man who holds an عديل is fine. What is never fine is a profile
--   that ends up approved, unbound and not an admin — which is precisely what
--   assert_two_doors_only refuses, so the function and the guard now say the
--   same sentence and cannot drift apart.
--
-- ⚠ AND IT REFUSES OUT LOUD. A button that silently did nothing would leave
--   the admin believing he had granted access, and the member waiting for it.
CREATE OR REPLACE FUNCTION public.set_user_access(
  p_user_id uuid, p_role app_role DEFAULT NULL, p_status app_status DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $setacc$
DECLARE
  v_row  record;
  v_cur  record;
BEGIN
  PERFORM public.require_role('admin');

  SELECT * INTO v_cur FROM public.profiles WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'RUL00';
  END IF;

  -- ⚠ THE STATE AFTER THE WRITE, not the arguments. p_role and p_status are
  --   each optional and each fall back to what the row already holds, so
  --   testing the arguments alone would miss «approve this account» sent with
  --   no role at all — which is exactly what the اعتماد button sends.
  IF coalesce(p_status, v_cur.status) = 'approved'
     AND v_cur.adeel_id IS NULL
     AND coalesce(p_role, v_cur.role) <> 'admin' THEN
    RAISE EXCEPTION
      'بابان لا ثالث لهما: إمّا أدمن، وإمّا عديلٌ يدخل بمفتاح. لا يُعتمد حسابٌ بلا عديل.'
      USING ERRCODE = 'RUL00';
  END IF;

  UPDATE public.profiles SET
    role   = coalesce(p_role, role),
    status = coalesce(p_status, status),
    approved_by = CASE WHEN p_status = 'approved' THEN auth.uid() ELSE approved_by END,
    approved_at = CASE WHEN p_status = 'approved' THEN now() ELSE approved_at END
  WHERE id = p_user_id
  RETURNING * INTO v_row;

  PERFORM public.write_audit('user.access',
    format('%s → %s / %s', v_row.email, v_row.role, v_row.status),
    v_row.id::text);

  RETURN jsonb_build_object('id', v_row.id, 'email', v_row.email,
                            'role', v_row.role, 'status', v_row.status);
END $setacc$;


-- ── §1. الدخول يُسجَّل، ولا يربط جهازاً ────────────────────────────────────
--
-- ⚠ THE CLAIM IS REMOVED, NOT NARROWED. Every narrowing keeps a path where a
--   handset binds itself without a code, and every such path is this bug
--   again. redeem_adeel_code sets device_id in its own body, so after this
--   there is exactly ONE way for a phone to become «the» phone: somebody typed
--   a live key into it.
CREATE OR REPLACE FUNCTION public.api_touch_login() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, auth AS $$
  UPDATE public.profiles
     SET last_login_at = now()
   WHERE id = auth.uid()
$$;


-- ── §2. الاسترداد: يرفض بالكلام، ويطرد من كان قبله ─────────────────────────
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

  -- ── ⚠ مفتاحٌ واحد، رجلٌ واحد، حسابٌ واحد ─────────────────────────────────
  --
  --   Redeeming TAKES OVER the عديل. Any other account still holding him is
  --   unbound in the same statement — its device released and its status put
  --   back to pending, so it is a stranger again until somebody issues it a
  --   key of its own.
  --
  -- ⚠ WITHOUT THIS, A PHONE CHANGE WITH A NEW GOOGLE ACCOUNT WOULD LEAVE TWO
  --   PROFILES ON ONE عديل — which is the state WHO_IS_DUP.sql was written to
  --   find, and which the UNIQUE index in §3 would refuse outright. So this is
  --   not tidying: it is what makes the index installable and phone changes
  --   possible at the same time.
  --
  -- ⚠ AND IT RUNS BEFORE MY OWN ROW IS WRITTEN, because the index is UNIQUE
  --   and the order is therefore not a style question.
  --
  -- ⚠ SAFE UNDER guard_profile_change: every refusal in that trigger is scoped
  --   to «NEW.id = auth.uid()», and these are other people's rows. The «last
  --   approved admin» clause cannot fire either — an admin never holds an
  --   adeel_id, because my_role() would stop answering for him.
  UPDATE public.profiles
     SET adeel_id = NULL, device_id = NULL, status = 'pending'
   WHERE adeel_id = v_row.adeel_id
     AND id <> auth.uid();

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

-- ── §3. عديلٌ واحد، حسابٌ واحد — بقيدٍ لا بعادة ────────────────────────────
--
-- ⚠ IT HAD ALREADY HAPPENED ONCE. WHO_IS_DUP.sql exists in this repository
--   because an عديل was found holding two portal profiles, and nothing in the
--   schema had refused it — every schema check ever written looks at shape,
--   and two rows of the right shape are two rows of the right shape.
--
-- ⚠ THE CLEANUP RUNS FIRST AND KEEPS THE MOST RECENTLY USED ACCOUNT. The
--   losers are unbound rather than deleted: an auth.users row survives either
--   way, and deleting a profile is what locked the association out of its own
--   app on 2026-08-20.
--
-- ⚠ AND UNBINDING IS SAFE ONLY BECAUSE OF PATCH_20260822d. Before it, a viewer
--   with no adeel_id read the WHOLE association — my_role() answered for any
--   approved profile — so this statement would have been a privilege
--   escalation. my_role() now ends «AND p.role = 'admin'», so an unbound
--   viewer reads nothing at all. status = 'pending' on top of it, so he is
--   sent to the code box rather than to an empty screen.
WITH ranked AS (
  SELECT id, adeel_id,
         row_number() OVER (PARTITION BY adeel_id
                            ORDER BY last_login_at DESC NULLS LAST, id) AS rn
    FROM public.profiles
   WHERE adeel_id IS NOT NULL)
UPDATE public.profiles p
   SET adeel_id = NULL, device_id = NULL, status = 'pending'
  FROM ranked r
 WHERE p.id = r.id AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS uq_profiles_adeel
  ON public.profiles (adeel_id) WHERE adeel_id IS NOT NULL;


-- ── §4. حارسٌ يسأل عن هذا الباب وحده ───────────────────────────────────────
--
-- ⚠ THE FOUR EXISTING GUARDS ALL PASSED ON THE DAY THIS HAPPENED, exactly as
--   they did on the day a member opened the association app. assert_signin,
--   assert_function_grants, assert_no_public_execute and
--   assert_views_security_invoker ask whether the PLUMBING is intact. None of
--   them asks «can a handset bind itself without a key», because that is a
--   sentence inside a function body, and a body of the right signature is a
--   body of the right signature.
--
-- ⚠ IT READS THE BODY, NOT THE NAME. A CREATE OR REPLACE that put the claim
--   back would leave every other check green.
CREATE OR REPLACE FUNCTION public.assert_login_lockdown()
RETURNS void LANGUAGE plpgsql AS $lock$
DECLARE
  v_src text;
  v_n   int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'api_touch_login';

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'LOGIN: api_touch_login مفقودة';
  END IF;

  IF v_src LIKE '%request_device_id%' THEN
    RAISE EXCEPTION
      'LOGIN: api_touch_login تربط جهازاً — هذه هي ثغرة 23/08 بعينها';
  END IF;

  -- ⚠ AND THE FACTORY, not only the strangers it made. Sweeping the accounts
  --   without closing set_user_access is what PATCH_20260822d did, and three
  --   more appeared within the day.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'set_user_access';
  IF v_src IS NULL OR v_src NOT LIKE '%بابان لا ثالث لهما%' THEN
    RAISE EXCEPTION
      'LOGIN: set_user_access ما زالت تعتمد حساباً بلا عديل — مصنع الغرباء مفتوح';
  END IF;

  SELECT count(*) INTO v_n FROM pg_indexes
   WHERE schemaname = 'public' AND indexname = 'uq_profiles_adeel';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'LOGIN: قيد «عديلٌ واحد، حسابٌ واحد» غير موجود';
  END IF;

  SELECT count(*) INTO v_n FROM (
    SELECT adeel_id FROM public.profiles
     WHERE adeel_id IS NOT NULL
     GROUP BY adeel_id HAVING count(*) > 1) q;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'LOGIN: % عديلاً يحمل أكثر من حساب', v_n;
  END IF;
END $lock$;

-- A guard is not a client endpoint — it is called from the tail of a patch and
-- from WHICH_STATE, both of which run as the owner.
REVOKE ALL ON FUNCTION public.assert_login_lockdown()
  FROM PUBLIC, anon, authenticated, service_role;


-- ── §5. ولا نصدّق ما لم نُشغّله ────────────────────────────────────────────
--
-- ⚠ TWO SOURCE CHECKS AND ONE REAL FAILING CASE, and the split is deliberate.
--
--   api_touch_login CANNOT be rehearsed here: its whole body is
--   «WHERE id = auth.uid()», and auth.uid() is NULL in the SQL Editor — which
--   runs as postgres, not as an admin. Calling it would update no row and pass
--   whatever the body said, which is the worst kind of test: one that reports
--   success for the broken code. So the claim is proved absent by READING the
--   body, the way FINAL_CHECK.sql reads a policy expression rather than a name.
--
--   The UNIQUE index CAN be rehearsed, and is: two accounts are pushed onto one
--   عديل and the database must refuse. It is undone by the exception handler's
--   own rollback, so no real binding is disturbed.
DO $smoke$
DECLARE
  v_src   text;
  v_a     uuid;
  v_b     uuid;
  v_adeel bigint;
  v_bit   boolean := false;
BEGIN
  -- (١) الباب المغلق: لا تربط جهازاً.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'api_touch_login';
  IF v_src IS NULL THEN
    RAISE EXCEPTION 'api_touch_login مفقودة';
  END IF;
  IF v_src LIKE '%device_id%' THEN
    RAISE EXCEPTION 'api_touch_login ما زالت تكتب device_id — الثغرة مفتوحة';
  END IF;

  -- (٢) والباب المفتوح: الاسترداد وحده يربط، ويطرد من كان قبله.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code';
  IF v_src NOT LIKE '%device_id = v_device%' THEN
    RAISE EXCEPTION 'redeem_adeel_code لم تعد تربط الجهاز — لا باب للعديل';
  END IF;
  IF v_src NOT LIKE '%AND id <> auth.uid()%' THEN
    RAISE EXCEPTION 'redeem_adeel_code لا تطرد الحساب السابق';
  END IF;
  IF v_src NOT LIKE '%مرتبط بعديلٍ آخر%' THEN
    RAISE EXCEPTION 'redeem_adeel_code لا ترفض الربط المتقاطع بالكلام';
  END IF;

  -- (٣) الحالة الفاشلة: عديلٌ بحسابين — يجب أن ترفضها القاعدة نفسها.
  SELECT p.id, p.adeel_id INTO v_a, v_adeel
    FROM public.profiles p WHERE p.adeel_id IS NOT NULL ORDER BY p.id LIMIT 1;
  -- ⚠ A VIEWER WITH NO BINDING, and the first draft did not say so — it took
  --   whatever row came first, which was the ADMIN, and the UPDATE was refused
  --   by ck_profiles_adeel_portal (an admin may hold no adeel_id) instead of by
  --   the index. A check_violation is not a unique_violation, so the handler
  --   below did not catch it and the whole patch rolled back. The constraint
  --   was right; the test picked the wrong man to test with.
  SELECT p.id INTO v_b
    FROM public.profiles p
   WHERE p.id <> v_a AND p.role = 'viewer' AND p.adeel_id IS NULL
   ORDER BY p.id LIMIT 1;

  IF v_a IS NOT NULL AND v_b IS NOT NULL THEN
    BEGIN
      UPDATE public.profiles SET adeel_id = v_adeel WHERE id = v_b;
      v_bit := true;              -- reached only if the index did NOT refuse
    EXCEPTION WHEN unique_violation THEN
      NULL;                       -- ✔ refused, and the savepoint is rolled back
    END;

    IF v_bit THEN
      RAISE EXCEPTION 'القاعدة قبلت عديلاً بحسابين — القيد لا يعمل';
    END IF;
  ELSE
    RAISE NOTICE 'تخطّي اختبار الازدواج: لا يوجد حسابٌ حرٌّ لتجربته عليه';
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();
SELECT public.assert_login_lockdown();

COMMIT;


-- ============================================================================
--  ومَن عليه أن يُصدر له مفتاحاً جديداً — اقرأ هذه القائمة
--
--  ⚠ EVERY ROW HERE IS AN ACCOUNT THAT WAS ONE APP LAUNCH FROM LETTING ITSELF
--    IN before this patch. After it, each needs a key typed into a handset.
-- ============================================================================
SELECT a.adeel_code                       AS "العديل",
       a.full_name                        AS "الاسم",
       coalesce(nullif(p.email, ''), '—') AS "الحساب",
       CASE WHEN p.device_id IS NULL THEN 'يحتاج مفتاحاً جديداً'
            ELSE 'مربوطٌ بجهاز' END       AS "الحالة",
       CASE WHEN c.code IS NULL THEN 'لا مفتاح'
            WHEN c.expires_at < now() THEN 'مفتاحه منتهٍ'
            WHEN c.redeemed_at IS NOT NULL THEN 'مفتاحه مُستعمل'
            ELSE 'مفتاحه صالح' END        AS "المفتاح"
  FROM public.profiles p
  JOIN public.adeels a ON a.id = p.adeel_id
  LEFT JOIN public.adeel_access_codes c ON c.adeel_id = p.adeel_id
 ORDER BY p.device_id IS NOT NULL, a.adeel_code;
