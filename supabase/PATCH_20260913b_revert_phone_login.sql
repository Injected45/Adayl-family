-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-13 (b).  التراجعُ عن الدخول برقم الهاتف.
--
--  ما الذي يفعله هذا الملف
--    قرّرت الجمعيةُ البقاءَ على الدخول بـ Google، لأنّ إرسال رموز واتساب يحتاج
--    حساب Twilio ورقمَ واتساب أعمالٍ توافق عليه Meta. هذا الملف يُرجع قاعدة
--    البيانات إلى ما كانت عليه قبل PATCH_20260913_phone_login.sql وملفّ
--    PHONE_LOGIN_ACCOUNTS.sql — وكلاهما شُغّل على المشروع الحيّ.
--
--  ⚠ الدخولُ بـ Google لم يتوقّف لحظةً قبل هذا الملف ولن يتوقّف بعده. التطبيقُ
--    المثبّت على الهواتف لم يعرف شيئًا عن الهاتف، والدوالُّ المضافة لم يستدعِها
--    أحد. هذا تنظيفٌ، لا إصلاحُ عطل.
--
--  ما يُرجَع:
--    ١. أرقامُ الهواتف التي أُلحقت بحسابات Google للأعضاء (هيثم وأيمن) تُمسح —
--       فقط حيث يطابق الرقمُ رقمَ عديله في السجلّ، ولحساباتٍ لها بريد.
--    ٢. guard_profile_change يعود بجسده الأصليّ حرفًا — منقولٌ من نسخةٍ لم
--       يمرّ بها ترقيعُ الهاتف قطّ، لا مكتوبٌ من الذاكرة.
--    ٣. api_phone_login تُحذف وتُرفع من قائمة السماح.
--    ٤. hook_before_user_created و normalize_ly_phone تُحذفان.
--
--  ⚠ وما لا يُرجَع، عن قصد: فهرسُ uq_profiles_email يبقى جزئيًّا
--    (WHERE email <> ''). كان الفهرسُ الكامل خللًا حقيقيًّا لا علاقة له
--    بالهاتف وحده: حسابٌ بلا بريد يُكتب بريدُه فارغًا، وثاني حسابٍ كذلك يصطدم
--    بالأوّل فلا يُنشأ له ملفّ. ولا يغيّر الفهرسُ الجزئيّ شيئًا لحساب Google —
--    بريدُه ليس فارغًا أبدًا، فيبقى فريدًا كما كان.
--
--  ⚠ قبل التشغيل: إن كنتَ فعّلتَ «Before User Created» في
--    Authentication → Hooks فأوقفه أوّلًا. الخطّافُ يُحذف هنا، وخطّافٌ مفعّلٌ
--    يشير إلى دالّةٍ غير موجودة يمنع إنشاء أيّ حسابٍ جديد. إن لم تفعّله —
--    وهو الأرجح، لأنّه كان خطوةً بعد إعداد Twilio — فلا شيء عليك.
--
--  للتشغيل: SQL Editor ← New query ← الصق ← Run. معاملةٌ واحدة، وتكرارُها آمن،
--  ويصلح على مشروعٍ لم يُشغَّل فيه ترقيعُ الهاتف أصلًا.
-- ============================================================================

BEGIN;

-- == 1. مسحُ الأرقام المُلحَقة بحسابات Google ================================
-- ⚠ قبل حذف normalize_ly_phone، لأنّ هذا الشرط يحتاجها. وداخل IF لأنّ ملفًّا
--   يُشغَّل على مشروعٍ لم يمرّ به ترقيعُ الهاتف لا يجد الدالّة أصلًا.
DO $phones$
DECLARE v_n int := 0;
BEGIN
  IF to_regprocedure('public.normalize_ly_phone(text)') IS NOT NULL THEN
    UPDATE auth.users u
       SET phone = NULL, phone_confirmed_at = NULL
      FROM public.profiles p
      JOIN public.adeels a ON a.id = p.adeel_id
     WHERE u.id = p.id
       AND coalesce(u.email, '') <> ''
       AND u.phone IS NOT NULL
       AND public.normalize_ly_phone(u.phone) = public.normalize_ly_phone(a.phone);
    GET DIAGNOSTICS v_n = ROW_COUNT;
  END IF;
  RAISE NOTICE 'مُسح الرقم من % حساب', v_n;
END $phones$;

-- == 2. الحارسُ بجسده الأصليّ ==============================================
CREATE OR REPLACE FUNCTION public.guard_profile_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  -- Redeeming an access code is the ONE self-change that has to be allowed:
  -- pending → approved, performed by the caller on his own row, inside
  -- redeem_adeel_code(). It is recognisable precisely because the row is
  -- ACQUIRING an عديل binding at the same moment, and it grants nothing — the
  -- role stays 'viewer', and my_role() returns NULL for anyone holding an
  -- adeel_id, so the account ends up with strictly less reach than before.
  --
  -- NULL → NOT NULL only. Rebinding to a different عديل is still refused below.
  v_redeeming boolean := OLD.adeel_id IS NULL
                     AND NEW.adeel_id IS NOT NULL
                     AND OLD.role = 'viewer'
                     AND NEW.role = 'viewer';
BEGIN
  -- Self-elevation. current_user is postgres/service_role during seeding and
  -- migrations, where this guard must not apply.
  IF auth.uid() IS NOT NULL AND NEW.id = auth.uid()
     AND NOT v_redeeming
     AND (NEW.role IS DISTINCT FROM OLD.role
          OR NEW.status IS DISTINCT FROM OLD.status) THEN
    RAISE EXCEPTION 'FORBIDDEN: cannot change your own role or status'
      USING ERRCODE = 'RUL00';
  END IF;

  -- adeel_id is only PARTLY exempt from the self-change rule above. Acquiring a
  -- binding is a self-change and is the whole point of redeem_adeel_code(), so
  -- NULL → an عديل has to be allowed. Changing one you already have must not be:
  -- that is someone moving himself onto another عديل's ledger, or out of the
  -- portal scope and back onto the staff ladder.
  --
  -- Scoped to `NEW.id = auth.uid()` deliberately. An ADMIN must still be able to
  -- correct a mis-binding — someone who redeemed the wrong code — and forbidding
  -- it outright would leave no way to do so short of deleting the account and
  -- losing its sign-in history.
  IF auth.uid() IS NOT NULL AND NEW.id = auth.uid()
     AND OLD.adeel_id IS NOT NULL
     AND NEW.adeel_id IS DISTINCT FROM OLD.adeel_id THEN
    RAISE EXCEPTION 'FORBIDDEN: cannot change your own عديل binding'
      USING ERRCODE = 'RUL00';
  END IF;

  -- Last approved admin standing.
  IF (OLD.role = 'admin' AND OLD.status = 'approved')
     AND (NEW.role IS DISTINCT FROM 'admin' OR NEW.status IS DISTINCT FROM 'approved')
     AND (SELECT count(*) FROM public.profiles
           WHERE role = 'admin' AND status = 'approved' AND id <> OLD.id) = 0 THEN
    RAISE EXCEPTION 'FORBIDDEN: the last approved admin cannot be removed'
      USING ERRCODE = 'RUL00';
  END IF;

  RETURN NEW;
END $function$;

-- == 3. api_phone_login خارج قائمة السماح ثمّ محذوفة =========================
DO $allow$
DECLARE
  v_old text[] := public.client_callable_functions();
  v_new text[];
BEGIN
  SELECT coalesce(array_agg(x ORDER BY ord), '{}'::text[]) INTO v_new
    FROM unnest(v_old) WITH ORDINALITY AS t(x, ord)
   WHERE replace(x, ' ', '') <> 'api_phone_login()';

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

DROP FUNCTION IF EXISTS public.api_phone_login();

-- == 4. الخطّاف ودالّةُ توحيد الرقم =========================================
DROP FUNCTION IF EXISTS public.hook_before_user_created(jsonb);
DROP FUNCTION IF EXISTS public.normalize_ly_phone(text);

-- == 5. الفحص: للقراءة فقط، وكلُّ صفٍّ يجب أن يقول true ====================
SELECT 'لا دوالَّ للدخول بالهاتف' AS "الفحص",
       to_regprocedure('public.api_phone_login()') IS NULL
   AND to_regprocedure('public.hook_before_user_created(jsonb)') IS NULL
   AND to_regprocedure('public.normalize_ly_phone(text)') IS NULL AS "النتيجة"
UNION ALL SELECT 'والحارسُ بجسده الأصليّ (بلا استثناء التحرير)',
       (SELECT prosrc NOT LIKE '%v_releasing%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'guard_profile_change')
UNION ALL SELECT 'وقائمةُ السماح بلا api_phone_login',
       NOT ('api_phone_login()' = ANY (
         SELECT replace(a, ' ', '') FROM unnest(public.client_callable_functions()) a))
-- ⚠ عبر query_to_xml وداخل CASE: العمودُ auth.users.phone موجودٌ في كلّ مشروع
--   Supabase، لكنّ فحصًا يُكتب مباشرةً عليه يموت بخطأ 42703 في أيّ بيئةٍ
--   تخلو منه — والفحصُ لا يجوز أن يكون هو ما يُسقط الملف.
UNION ALL SELECT 'ولا رقمَ هاتفٍ على حساب Google مربوطٍ بعديل',
       CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                              WHERE table_schema = 'auth' AND table_name = 'users'
                                AND column_name = 'phone')
            THEN true
            ELSE (xpath('/row/c/text()', query_to_xml(
                    'SELECT count(*) AS c FROM auth.users u
                       JOIN public.profiles p ON p.id = u.id
                      WHERE p.adeel_id IS NOT NULL
                        AND coalesce(u.email, '''') <> ''''
                        AND u.phone IS NOT NULL', false, true, '')))[1]::text::int = 0
       END
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 6. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
