-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-16.  إصلاحُ زرّ «مسح كل الإشعارات»،
--  وإضافةُ إرسال رسالةٍ إلى مشتركٍ بعينه أو أكثر.
--
--  ما الذي يفعله هذا الملف — ثلاثةُ أشياء:
--
--    ١) يكشف سببَ الرمز 21000: يستدعي الدالّةَ القديمة بهويّة الأدمن نفسِها
--       التي يستدعيها بها التطبيق، ويلتقط الخطأ بنصِّه وموضعِه ويعرضه في جدول
--       النتيجة في آخر الملف. فإن نجحت هنا فقد مُسحت الإشعاراتُ فعلًا.
--
--    ٢) يُصلح الزرّ: نسخةٌ جديدة من clear_notifications() لا تسقط بخطأٍ مبهَم —
--       سؤالُ «هل هو أدمن؟» يُسأل مباشرةً بـ EXISTS، وكتابةُ سجلّ العمليات في
--       كتلةٍ خاصّة بها فلا تُسقط المسحَ إن تعثّرت، وأيُّ خطأٍ آخر يخرج إلى
--       الشاشة بجملةٍ عربيّة تسمّي موضعَه بدل رقمٍ بين قوسين.
--
--    ٣) يضيف send_notice(ids, title, body): رسالةٌ من الإدارة إلى مشتركٍ
--       واحد أو أكثر — للمطالبة بالسداد مثلًا — تصل هاتفَه وحده. وإرسالُ الكلّ
--       (send_broadcast) باقٍ كما هو، لم يُمسّ منه حرف.
--
--  ⚠ الرسالةُ الموجَّهة يقرؤها صاحبُها وحده: تُكتب بـ audience='member' مع رقمِه،
--    وسياسةُ القراءة القائمة تُعطي كلَّ مشتركٍ ما وُجّه له فقط. لا يراها مشتركٌ
--    آخر ولو نادى القاعدةَ من خارج التطبيق.
--
--  ⚠ لا يُمسّ أيُّ رقمٍ ماليّ ولا أيُّ دالّةٍ ماليّة — والصفُّ الأخيرُ يثبت ذلك.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.notifications') IS NULL
     OR to_regclass('public.adeels') IS NULL THEN
    RAISE EXCEPTION 'جدول الإشعارات أو العدايل غير موجود — لم يتغيّر شيء.';
  END IF;
  IF to_regprocedure('public.notify_insert(text,bigint,text,text,text,text)') IS NULL
     OR to_regprocedure('public.require_role(app_role)') IS NULL
     OR to_regprocedure('public.write_audit(text,text,text)') IS NULL
     OR to_regprocedure('public.client_callable_functions()') IS NULL THEN
    RAISE EXCEPTION 'هذا ليس مشروع الجمعية — لم يتغيّر شيء.';
  END IF;

  -- ⚠ صورةُ الأرقام قبل أيّ سطرٍ من هذا الملف، تُقارَن بها في آخره.
  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);
END $prereq$;

-- == 1. التشخيص: لماذا رفض الزرُّ بالرمز 21000 ==============================
-- ⚠ محرّرُ SQL يعمل بدور postgres، وauth.uid() فيه فارغة، فاستدعاءُ الدالّة
--   مباشرةً يُرفض بـ RUL00 ولا يخبرنا شيئًا. هنا نلبس هويّةَ الأدمن نفسَها:
--   نفسُ الدور (authenticated)، ونفسُ المُعرِّف — تمامًا كما يصل الطلبُ من
--   الهاتف. ثمّ نلتقط الخطأ بنصّه وموضعه.
DO $probe$
DECLARE
  v_uid   uuid;
  v_state text;
  v_msg   text;
  v_ctx   text;
  v_res   jsonb;
BEGIN
  IF to_regprocedure('public.clear_notifications()') IS NULL THEN
    PERFORM set_config('adayl.probe',
      'الدالّة لم تكن موجودة أصلًا — ملفُّ 15/09 (e) لم يُشغَّل', false);
    RETURN;
  END IF;

  SELECT p.id INTO v_uid
    FROM public.profiles p
   WHERE p.role = 'admin' AND p.status = 'approved'
   ORDER BY p.created_at
   LIMIT 1;

  IF v_uid IS NULL THEN
    PERFORM set_config('adayl.probe', 'لا يوجد حسابُ أدمن معتمَد', false);
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  BEGIN
    SET LOCAL ROLE authenticated;
    SELECT public.clear_notifications() INTO v_res;
    EXECUTE 'RESET ROLE';
    PERFORM set_config('adayl.probe',
      'لم يظهر خطأ — نجح المسحُ الآن: ' || coalesce(v_res::text, ''), false);
  EXCEPTION WHEN OTHERS THEN
    -- ⚠ الالتقاطُ يُلغي ما جرى داخل هذه الكتلة وحدها، ولا يُسقط الملفّ.
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE,
                            v_msg   = MESSAGE_TEXT,
                            v_ctx   = PG_EXCEPTION_CONTEXT;
    PERFORM set_config('adayl.probe',
      'الرمز ' || v_state || ' — ' || coalesce(v_msg, '') || ' — عند: ' ||
      split_part(coalesce(v_ctx, 'لا موضع'), E'\n', 1), false);
  END;

  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
END $probe$;

-- == 2. الزرُّ: نسخةٌ لا تسقط بخطأٍ مبهَم ======================================
-- ⚠ سؤالُ «هل هو أدمن؟» يُسأل هنا مباشرةً بـ EXISTS بنفس شرط my_role() حرفًا
--   (معتمَد، بلا ربطٍ بعديل، ودورُه admin). السببُ: EXISTS جوابُه نعم أو لا
--   مهما كان عددُ الصفوف، فلا يمكن أن يرفع 21000 مهما كانت حالُ الجدول.
-- ⚠ وكتابةُ سجلّ العمليات في كتلةٍ خاصّة: المسحُ هو المطلوب، وتعثُّرُ سطرِ
--   السجلّ لا يجوز أن يُلغيه — ويُذكر في الجواب إن تعثّر.
-- ⚠ وأيُّ خطأٍ آخر يخرج بجملةٍ عربيّة تسمّي رمزَه وموضعَه، برمز RUL18 لأنّ
--   التطبيق يعرض نصَّ أخطاء RUL كما هو. «[21000]» وحدَه لا يقول شيئًا لأحد.
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
    -- ⚠ حذفٌ لا يعيد الترقيم من 1: هاتفُ كلّ مشترك يحفظ رقمَ آخر إشعارٍ رآه،
    --   ولو بدأ الترقيمُ من جديد لاعتبر الإشعاراتِ الجديدة مقروءةً سلفًا.
    DELETE FROM public.notifications;
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

-- == 3. رسالةٌ إلى مشتركٍ بعينه أو أكثر =======================================
-- ⚠ صفٌّ لكلّ مشترك، لا صفٌّ واحدٌ بقائمة: سياسةُ القراءة القائمة تسأل
--   adeel_id = my_adeel_id()، فالصفُّ المنفصل هو ما يجعل الرسالةَ خاصّةً به
--   ولا تحتاج سياسةً جديدة ولا تعديلَ سياسة.
-- ⚠ ومن نوع 'broadcast' كرسالة الإدارة للجميع: النوعُ يقول «من الإدارة، لا من
--   حركةٍ ماليّة»، والجمهورُ (audience) هو ما يقول لمن.
CREATE OR REPLACE FUNCTION public.send_notice(
  p_adeel_ids bigint[], p_title text, p_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $sn$
DECLARE
  v_title text := nullif(btrim(coalesce(p_title, '')), '');
  v_body  text := btrim(coalesce(p_body, ''));
  v_ids   bigint[];
  v_found int;
  v_sent  int := 0;
  r       record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.id = auth.uid()
                    AND p.status = 'approved'
                    AND p.adeel_id IS NULL
                    AND p.role = 'admin') THEN
    RAISE EXCEPTION 'هذا الأمر للإدارة وحدها' USING ERRCODE = 'RUL00';
  END IF;

  SELECT array_agg(DISTINCT x) INTO v_ids
    FROM unnest(coalesce(p_adeel_ids, '{}'::bigint[])) x
   WHERE x IS NOT NULL;

  IF v_ids IS NULL THEN
    RAISE EXCEPTION 'حدِّد مشتركًا واحدًا على الأقل' USING ERRCODE = 'RUL18';
  END IF;
  IF cardinality(v_ids) > 200 THEN
    RAISE EXCEPTION 'لا تُرسل لأكثر من 200 مشترك في المرة الواحدة'
      USING ERRCODE = 'RUL18';
  END IF;
  IF v_body = '' THEN
    RAISE EXCEPTION 'اكتب نصَّ الرسالة قبل الإرسال' USING ERRCODE = 'RUL18';
  END IF;
  IF length(v_body) > 1000 THEN
    RAISE EXCEPTION 'الرسالة أطول من 1000 حرف' USING ERRCODE = 'RUL18';
  END IF;
  IF v_title IS NOT NULL AND length(v_title) > 120 THEN
    RAISE EXCEPTION 'العنوان أطول من 120 حرفًا' USING ERRCODE = 'RUL18';
  END IF;

  SELECT count(*) INTO v_found FROM public.adeels a WHERE a.id = ANY (v_ids);
  IF v_found <> cardinality(v_ids) THEN
    RAISE EXCEPTION 'بعض المشتركين المحدَّدين غير موجودين' USING ERRCODE = 'RUL18';
  END IF;

  FOR r IN SELECT a.id FROM public.adeels a WHERE a.id = ANY (v_ids) ORDER BY a.id
  LOOP
    PERFORM public.notify_insert('member', r.id, 'broadcast',
                                 coalesce(v_title, 'رسالة من الإدارة'),
                                 v_body, NULL);
    v_sent := v_sent + 1;
  END LOOP;

  PERFORM public.write_audit('notifications.send',
    format('رسالة من الإدارة إلى %s مشترك', v_sent),
    array_to_string(v_ids, ','));

  RETURN jsonb_build_object('sent', v_sent);
END $sn$;

-- == 4. قائمةُ السماح ========================================================
DO $allow$
DECLARE
  v_old text[] := public.client_callable_functions();
  v_new text[] := v_old;
  v_add text[] := ARRAY['clear_notifications()', 'send_notice(bigint[],text,text)'];
  v_one text;
BEGIN
  FOREACH v_one IN ARRAY v_add LOOP
    IF NOT (v_one = ANY (SELECT replace(a, ' ', '') FROM unnest(v_new) a)) THEN
      v_new := v_new || v_one;
    END IF;
  END LOOP;

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

-- == 5. المسحة، بعد آخر CREATE في هذا الملف ================================
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

-- == 6. التأكيد: الزرُّ الجديد بهويّة الأدمن نفسِها ============================
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

-- == 7. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 8. النتيجة: آخرُ جدولٍ يظهر في المحرّر ==================================
SELECT 'ما كان يمنع الزرَّ (التشخيص)' AS "الفحص",
       coalesce(current_setting('adayl.probe', true), 'لم يُفحص') AS "النتيجة"
UNION ALL SELECT 'والزرُّ يعمل الآن',
       coalesce(current_setting('adayl.verify', true), 'لم يُفحص')
UNION ALL SELECT 'الإشعاراتُ الباقية الآن',
       (SELECT count(*)::text FROM public.notifications)
UNION ALL SELECT 'إرسالٌ لمشتركٍ بعينه متاحٌ للتطبيق',
       has_function_privilege('authenticated',
         'public.send_notice(bigint[],text,text)', 'EXECUTE')::text
UNION ALL SELECT 'ولا يصل إليه غيرُ المسجَّل',
       (NOT has_function_privilege('anon',
         'public.send_notice(bigint[],text,text)', 'EXECUTE'))::text
UNION ALL SELECT 'وإرسالُ الكلّ باقٍ كما هو',
       has_function_privilege('authenticated',
         'public.send_broadcast(text,text)', 'EXECUTE')::text
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       ((SELECT row_to_json(s)::text FROM public.v_cash_summary s)
          = current_setting('adayl.fund_before', true))::text;

COMMIT;
