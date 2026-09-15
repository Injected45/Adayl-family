-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-15 (e).  زرُّ «مسح كل الإشعارات» للأدمن.
--
--  ما الذي يفعله هذا الملف
--    يضيف دالّةً واحدة، clear_notifications()، يستدعيها زرٌّ أحمر في تبويب
--    الإشعارات عند الأدمن. تحذف كلَّ الإشعارات، فتفرغ عند الأدمن وعند كلّ
--    مشترك، وتُسجِّل في سجلّ العمليات مَن مسحها ومتى وكم كانت.
--
--  ⚠ للأدمن وحده، والقاعدةُ هي التي تقرّر ذلك لا الشاشة: الدالّةُ تبدأ بـ
--    require_role('admin')، فالمشترك يُرفض ولو استدعاها من خارج التطبيق.
--
--  ⚠ «بدون أي تعطيل»: الحذفُ بـ DELETE ولا تُعاد أرقامُ الإشعارات من 1. هاتفُ
--    كلّ مشترك يحفظ رقمَ آخر إشعارٍ رآه، ولو بدأ الترقيمُ من جديد لاعتبر
--    الإشعاراتِ الجديدة مقروءةً سلفًا فلا يصل تنبيهٌ ولا رقمٌ أحمر. والإشعاراتُ
--    القادمة تصل كالمعتاد.
--
--  ⚠ لا يُمسّ غيرُ الإشعارات: لا رقمٌ ماليّ، ولا إيصال، ولا سند، ولا مقترح.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.notifications') IS NULL THEN
    RAISE EXCEPTION 'جدول الإشعارات غير موجود — شغّل ملف الإشعارات أولًا. لم يتغيّر شيء.';
  END IF;
  IF to_regprocedure('public.require_role(app_role)') IS NULL
     OR to_regprocedure('public.write_audit(text,text,text)') IS NULL
     OR to_regprocedure('public.client_callable_functions()') IS NULL THEN
    RAISE EXCEPTION 'هذا ليس مشروع الجمعية — لم يتغيّر شيء.';
  END IF;

  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);
END $prereq$;

-- == 1. الدالّة ==============================================================
CREATE OR REPLACE FUNCTION public.clear_notifications()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $cn$
DECLARE
  v_deleted bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- ⚠ حذفٌ لا يعيد الترقيم — انظر رأسَ الملف.
  DELETE FROM public.notifications;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  PERFORM public.write_audit(
    'notifications.clear',
    format('مسح كل الإشعارات (%s إشعار)', v_deleted));

  RETURN jsonb_build_object('deleted', v_deleted);
END $cn$;

-- == 2. قائمةُ السماح ========================================================
DO $allow$
DECLARE
  v_old text[] := public.client_callable_functions();
  v_new text[];
BEGIN
  IF 'clear_notifications()' = ANY (SELECT replace(a, ' ', '') FROM unnest(v_old) a) THEN
    v_new := v_old;
  ELSE
    v_new := v_old || 'clear_notifications()'::text;
  END IF;

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

-- == 3. المسحة، بعد آخر CREATE في هذا الملف ================================
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

-- == 4. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 5. النتيجة: آخرُ جدولٍ يظهر في المحرّر، وكلُّ صفٍّ يجب أن يقول true ======
SELECT 'زرُّ مسح الإشعارات متاحٌ للتطبيق' AS "الفحص",
       has_function_privilege('authenticated', 'public.clear_notifications()',
                              'EXECUTE')::text AS "النتيجة"
UNION ALL SELECT 'ولا يصل إليه غيرُ المسجَّل',
       (NOT has_function_privilege('anon', 'public.clear_notifications()',
                                   'EXECUTE'))::text
UNION ALL SELECT 'ويحذف ولا يعيد الترقيم من 1',
       (SELECT prosrc LIKE '%DELETE FROM public.notifications%'
               AND prosrc NOT ILIKE '%TRUNCATE%'
          FROM pg_proc
         WHERE oid = 'public.clear_notifications()'::regprocedure)::text
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       ((SELECT row_to_json(s)::text FROM public.v_cash_summary s)
          = current_setting('adayl.fund_before', true))::text;

COMMIT;
