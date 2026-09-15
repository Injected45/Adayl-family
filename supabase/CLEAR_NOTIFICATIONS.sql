-- ============================================================================
--  جمعية العدايل — مسحُ كلِّ الإشعارات الموجودة الآن.
--
--  ما الذي يفعله هذا الملف
--    يحذف كلَّ صفوف جدول الإشعارات: فتفرغ «الإشعارات» عند كلّ مشترك، ويفرغ
--    سجلُّ «كل ما أُرسل» عند الأدمن. وكلُّ إشعارٍ جديد بعده يصل كالمعتاد.
--
--  ⚠ لا يُمسّ غيرُ الإشعارات: لا إيصال، ولا سند، ولا استحقاق، ولا رقم ماليّ،
--    ولا مقترح، ولا صفحة من قانون الجمعية. وإن تغيّر رقمٌ ماليّ لأيّ سبب يُلغى
--    كلُّ شيء ولا يُحذف إشعارٌ واحد.
--
--  ⚠ يُحذف بـ DELETE ولا تُعاد الأرقامُ من 1، عن قصد. هاتفُ كلّ مشترك يحفظ رقمَ
--    آخر إشعارٍ رآه؛ لو بدأت الأرقامُ من جديد لاعتبر الهاتفُ الإشعاراتِ الجديدة
--    مقروءةً سلفًا، فلا يظهر لها تنبيهٌ ولا رقمٌ أحمر حتى تتجاوز الرقمَ القديم.
--
--  ⚠ الحذفُ نهائيّ ولا رجوع عنه.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة.
-- ============================================================================

BEGIN;

DO $before$
BEGIN
  IF to_regclass('public.notifications') IS NULL THEN
    RAISE EXCEPTION 'جدول الإشعارات غير موجود — لم يتغيّر شيء.';
  END IF;

  -- صورةُ ما قبل الحذف، محليّةٌ لهذه المعاملة فقط.
  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);
  PERFORM set_config('adayl.notices_before',
                     (SELECT count(*)::text FROM public.notifications),
                     true);
  PERFORM set_config('adayl.last_id_before',
                     (SELECT coalesce(max(id), 0)::text FROM public.notifications),
                     true);
END $before$;

DELETE FROM public.notifications;

DO $after$
BEGIN
  IF EXISTS (SELECT 1 FROM public.notifications) THEN
    RAISE EXCEPTION 'بقيت إشعارات بعد الحذف — أُلغي كلُّ شيء.';
  END IF;
  IF (SELECT row_to_json(s)::text FROM public.v_cash_summary s)
       IS DISTINCT FROM current_setting('adayl.fund_before', true) THEN
    RAISE EXCEPTION 'تغيّر رقمٌ ماليّ — أُلغي كلُّ شيء.';
  END IF;
END $after$;

-- == النتيجة: آخرُ جدولٍ يظهر في المحرّر ====================================
SELECT 'الإشعارات التي حُذفت' AS "البند",
       current_setting('adayl.notices_before', true) AS "القيمة"
UNION ALL SELECT 'الإشعارات الباقية',
       (SELECT count(*) FROM public.notifications)::text
UNION ALL SELECT 'الإشعار القادم يُرقَّم بعد آخر رقمٍ محذوف (الهواتف ستنبّه له)',
       (coalesce(pg_sequence_last_value(
                   pg_get_serial_sequence('public.notifications', 'id')), 0)
          >= current_setting('adayl.last_id_before', true)::bigint)::text
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       ((SELECT row_to_json(s)::text FROM public.v_cash_summary s)
          = current_setting('adayl.fund_before', true))::text;

COMMIT;
