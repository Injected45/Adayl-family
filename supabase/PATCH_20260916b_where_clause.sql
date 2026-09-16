-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-16 (b).  «DELETE requires a WHERE clause».
--
--  ما الذي حدث — والجوابُ جاء من الهاتف لا من الملفات:
--
--    زرُّ «مسح كل الإشعارات» كان يردّ بالرمز 21000. وبعد أن صارت الدالّةُ
--    تسمّي خطأها بالعربيّة (ملفّ 16/09) ظهر السببُ على الشاشة كاملًا:
--
--        تعذّر مسحُ الإشعارات (الرمز 21000): DELETE requires a WHERE clause
--        — عند: SQL statement "DELETE FROM public.notifications"
--
--    في مشروع سوبابيز حارسٌ (safeupdate) مفروضٌ على حساب التطبيق يرفض أيَّ
--    حذفٍ أو تعديلٍ بلا شرط WHERE — حمايةً من أمرٍ يمسح جدولًا كلَّه بالخطأ.
--    الحارسُ يعمل على جلسة التطبيق وحدها، ولا وجود له في محرّر SQL (فهو يعمل
--    بدور postgres) ولا في نسخة الاختبار المحليّة. ولهذا نجح الأمرُ في كلّ
--    فحصٍ جرى عليه، وفشل على الهاتف وحدَه.
--
--  ما الذي يفعله هذا الملف — شرطٌ في موضعين، لا أكثر:
--
--    ١) clear_notifications()      ← DELETE … WHERE id > 0
--    ٢) revoke_all_adeel_access()  ← DELETE … WHERE adeel_id > 0
--
--  ⚠ الثانيةُ لم تُجرَّب بعد وكانت ستفشل بنفس الرمز: «مسح دخول المشتركين» في
--    شاشة المستخدمين. وجدتُها بفحص كلِّ دالّةٍ يناديها التطبيق، لا بالتخمين،
--    وهما الاثنتان الوحيدتان في القاعدة كلِّها.
--
--  ⚠ الشرطُ «> 0» لا «IS NOT NULL»: عمودٌ معرَّفٌ بأنّه لا يقبل الفراغ قد يحذف
--    المخطِّطُ شرطَ «ليس فارغًا» لأنّه صحيحٌ دائمًا، فيعود الأمرُ بلا شرطٍ في
--    الخطّة ويرفضه الحارسُ من جديد. و«> 0» يبقى في الخطّة، وقد تحقّقتُ من ذلك
--    بـ EXPLAIN. والمعنى واحد: كلُّ الصفوف، فالأرقام تبدأ من 1.
--
--  ⚠ لا يتغيّر أيُّ رقمٍ ماليّ ولا أيُّ دالّةٍ ماليّة، ولا سلوكَ أيِّ دالّةٍ سوى
--    أنّها صارت تعمل: الشرطُ يشمل كلَّ الصفوف تمامًا كما كان الأمرُ بلا شرط.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.notifications') IS NULL
     OR to_regclass('public.adeel_access_codes') IS NULL THEN
    RAISE EXCEPTION 'جدولٌ مطلوبٌ غير موجود — لم يتغيّر شيء.';
  END IF;
  IF to_regprocedure('public.clear_notifications()') IS NULL
     OR to_regprocedure('public.revoke_all_adeel_access(text)') IS NULL THEN
    RAISE EXCEPTION 'شغّل ملفَّ 16/09 الأوّل قبل هذا — لم يتغيّر شيء.';
  END IF;

  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);
END $prereq$;

-- == 1. مسح كل الإشعارات ====================================================
-- ⚠ هي نسخةُ ملفّ 16/09 حرفًا، ولم يتغيّر فيها إلا سطرُ الحذف. والغلافُ الذي
--   يسمّي الخطأ بالعربيّة باقٍ: هو الذي كشف هذا السبب، وهو الذي سيكشف التالي.
CREATE OR REPLACE FUNCTION public.clear_notifications()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $cn$
DECLARE
  v_deleted bigint := 0;
  v_audit   text   := 'ok';
  v_state   text;
  v_msg     text;
  v_ctx     text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.id = auth.uid()
                    AND p.status = 'approved'
                    AND p.adeel_id IS NULL
                    AND p.role = 'admin') THEN
    RAISE EXCEPTION 'هذا الأمر للإدارة وحدها' USING ERRCODE = 'RUL00';
  END IF;

  BEGIN
    -- ⚠ WHERE id > 0 — كلُّ الصفوف، والشرطُ مكتوبٌ لأنّ حارسَ سوبابيز يرفض
    --   الحذفَ بلا شرط. وحذفٌ لا يعيد الترقيم من 1: هاتفُ كلّ مشترك يحفظ رقمَ
    --   آخر إشعارٍ رآه، ولو بدأ الترقيمُ من جديد لاعتبر الجديدَ مقروءًا سلفًا.
    DELETE FROM public.notifications WHERE id > 0;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE,
                            v_msg   = MESSAGE_TEXT,
                            v_ctx   = PG_EXCEPTION_CONTEXT;
    RAISE EXCEPTION 'تعذّر مسحُ الإشعارات (الرمز %): % — عند: %',
      v_state, coalesce(v_msg, ''),
      split_part(coalesce(v_ctx, 'لا موضع'), E'\n', 1)
      USING ERRCODE = 'RUL18';
  END;

  BEGIN
    PERFORM public.write_audit(
      'notifications.clear',
      format('مسح كل الإشعارات (%s إشعار)', v_deleted));
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
    v_audit := v_state || ' ' || coalesce(v_msg, '');
  END;

  RETURN jsonb_build_object('deleted', v_deleted, 'audit', v_audit);
END $cn$;

-- == 2. مسح دخول كل المشتركين ===============================================
-- ⚠ الجسمُ منقولٌ حرفًا من الدالّة الحيّة (PATCH_20260821j)، لم يتغيّر فيه إلا
--   شرطُ الحذف. لم تكن قد جُرِّبت بعد، وكانت ستردّ بالرمز 21000 نفسِه.
CREATE OR REPLACE FUNCTION public.revoke_all_adeel_access(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $ra$
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
  -- ⚠ WHERE adeel_id > 0 — every row, and the qualifier is written because the
  --   project's safeupdate guard refuses an unqualified DELETE on the app's
  --   own session. Nothing else about this line changed.
  DELETE FROM public.adeel_access_codes WHERE adeel_id > 0;

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
END $ra$;

-- == 3. التأكيد: الزرّ بهويّة الأدمن نفسِها ====================================
-- ⚠ الحارسُ لا وجود له هنا (المحرّر يعمل بدور postgres)، فهذا يثبت أنّ الدالّة
--   تعمل ويمسح ما تبقّى من الإشعارات فعلًا — والشرطُ نفسُه يُفحص في §5 بقراءة
--   نصِّ الدالّة، وهو ما يهمّ الهاتف.
DO $verify$
DECLARE
  v_uid uuid;
  v_res jsonb;
BEGIN
  SELECT p.id INTO v_uid
    FROM public.profiles p
   WHERE p.role = 'admin' AND p.status = 'approved'
   ORDER BY p.created_at
   LIMIT 1;

  IF v_uid IS NULL THEN
    PERFORM set_config('adayl.verify', 'لا يوجد حسابُ أدمن معتمَد', false);
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  BEGIN
    SET LOCAL ROLE authenticated;
    SELECT public.clear_notifications() INTO v_res;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('adayl.verify', 'نعم — ' || coalesce(v_res::text, ''), false);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('adayl.verify',
      'لا — الرمز ' || SQLSTATE || ' — ' || SQLERRM, false);
  END;

  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
END $verify$;

-- == 4. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 5. النتيجة: آخرُ جدولٍ يظهر في المحرّر ==================================
-- ⚠ الصفُّ الأول يمسح كلَّ دالّةٍ يناديها التطبيق بحثًا عن حذفٍ أو تعديلٍ بلا
--   شرط — لا عن الاثنتين المعروفتين فقط. التعليقاتُ تُنزع أولًا، لأنّ فاصلةً
--   منقوطة داخل تعليقٍ تقطع الأمرَ فتجعله يبدو بلا شرط.
WITH callable AS (
  SELECT p.oid::regprocedure::text AS fn,
         regexp_replace(p.prosrc, '--[^\n]*', '', 'g') AS src
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND replace(ltrim(replace(p.oid::regprocedure::text, 'public.', ''), ' '), ' ', '')
         = ANY (SELECT replace(a, ' ', '') FROM unnest(public.client_callable_functions()) a)
), unqualified AS (
  SELECT fn, (regexp_matches(src, '(DELETE\s+FROM\s+[^;]*;)', 'gi'))[1] AS s FROM callable
  UNION ALL
  SELECT fn, (regexp_matches(src, '(UPDATE\s+[a-zA-Z_."]+\s+SET\s+[^;]*;)', 'gi'))[1] FROM callable
)
SELECT 'لا دالّةَ يناديها التطبيق فيها حذفٌ أو تعديلٌ بلا شرط' AS "الفحص",
       coalesce((SELECT string_agg(DISTINCT fn, '، ') FROM unqualified WHERE s !~* 'where'),
                'صحيح') AS "النتيجة"
UNION ALL SELECT 'وزرُّ مسح الإشعارات يعمل',
       coalesce(current_setting('adayl.verify', true), 'لم يُفحص')
UNION ALL SELECT 'الإشعاراتُ الباقية الآن',
       (SELECT count(*)::text FROM public.notifications)
UNION ALL SELECT 'و«مسح دخول المشتركين» صار بشرطٍ أيضًا',
       coalesce((SELECT prosrc LIKE '%adeel_access_codes WHERE adeel_id > 0%'
                   FROM pg_proc
                  WHERE oid = 'public.revoke_all_adeel_access(text)'::regprocedure),
                false)::text
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       ((SELECT row_to_json(s)::text FROM public.v_cash_summary s)
          = current_setting('adayl.fund_before', true))::text;

COMMIT;
