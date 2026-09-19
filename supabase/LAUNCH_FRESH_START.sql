-- ============================================================================
--  جمعية العدايل — بدايةٌ نظيفة قبل الإطلاق: مسحُ أثر التجربة.
--
--  ما الذي يُمسح
--      • كلُّ رسائل المحادثات — المجلس، ومحادثاتُ المشتركين مع الإدارة،
--        والمحادثاتُ الثنائية بينهم.
--      • كلُّ الإشعارات.
--      • المقترحاتُ التي لم يُبتّ فيها بعد.
--      • المكالماتُ القديمة وإشاراتُها.
--      • عدّادُ محاولات إدخال المفتاح (يبدأ كلُّ مشترك بخمس محاولاتٍ كاملة).
--
--  ⚠ ما لا يُمسّ، ولا سطرًا واحدًا منه:
--      • المال كلُّه — المشتركون، والاستحقاقات، والإيصالات، وتوزيعُها، وحركةُ
--        الصندوق، وسنداتُ الصرف، والأشهرُ المقفلة. الصفُّ الأخير يُثبت ذلك
--        بمقارنة رصيد الجمعية قبل وبعد.
--      • سجلُّ العمليات — القاعدةُ نفسُها ترفض حذفه (قاعدة ١٢)، وهو تاريخُ
--        مَن فعل ماذا.
--      • صفحاتُ قانون الجمعية — عقدُ الجمعية لا أثرُ تجربة.
--      • المقترحاتُ المقبولة — وُعد المشتركون أنّها تُحفظ للأبد، والقاعدةُ
--        ترفض حذفها حتى من هذا المحرّر. إن كان فيها مقترحُ تجربةٍ قبلتَه
--        بالخطأ فأخبرني، فله ملفٌّ خاصّ يُقال فيه صراحةً ما يُنقَض.
--
--  ⚠ حذفٌ لا يعيد الترقيم من ١. هاتفُ كلّ مشترك يحفظ رقمَ آخر رسالةٍ وآخر
--    إشعارٍ رآه؛ ولو بدأ الترقيمُ من جديد لاعتبر الجديدَ مقروءًا سلفًا، فلا
--    يصل جرسٌ ولا رقمٌ أحمر — وهذا أسوأ من بقاء رسائل التجربة.
--
--  ⚠ المقاطعُ الصوتية التي رُفعت مع الرسائل تبقى في المخزن ولا تُسمع: سياسةُ
--    القراءة تسأل رسالتَها أولًا، والرسالةُ لم تعد موجودة.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة،
--  وتكرارُها آمن (المرّة الثانية لا تجد ما تمسح).
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.chat_messages') IS NULL
     OR to_regclass('public.notifications') IS NULL THEN
    RAISE EXCEPTION 'هذا ليس مشروع الجمعية — لم يتغيّر شيء.';
  END IF;

  -- صورةُ الأرقام قبل أيّ سطر، تُقارَن بها في آخره.
  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);

  -- ما كان موجودًا قبل المسح، ليُعرض في النتيجة.
  PERFORM set_config('adayl.before', json_build_object(
    'رسائل',    (SELECT count(*) FROM public.chat_messages),
    'إشعارات',  (SELECT count(*) FROM public.notifications),
    'مقترحات',  CASE WHEN to_regclass('public.proposals') IS NULL THEN 0
                     ELSE (SELECT count(*) FROM public.proposals
                            WHERE status = 'pending') END
  )::text, false);
END $prereq$;

-- == 1. المحادثات =========================================================
-- ⚠ WHERE id > 0 — كلُّ الصفوف، والشرطُ مكتوبٌ لأنّ شرطًا يمكن للمخطِّط أن
--   يُسقطه (مثل IS NOT NULL على عمودٍ لا يقبل الفراغ) يعود كأنّه لا شرط.
DELETE FROM public.chat_messages WHERE id > 0;

-- == 2. الإشعارات =========================================================
DELETE FROM public.notifications WHERE id > 0;

-- == 3. المقترحاتُ المعلَّقة وحدَها ==========================================
DO $prop$
BEGIN
  IF to_regclass('public.proposals') IS NOT NULL THEN
    DELETE FROM public.proposals WHERE status = 'pending';
  END IF;
END $prop$;

-- == 4. المكالماتُ القديمة وعدّادُ المحاولات ==================================
-- ⚠ الأبناءُ قبل الآباء: الإشاراتُ والمقاعد قبل المكالمة نفسِها.
DO $calls$
BEGIN
  IF to_regclass('public.call_signals') IS NOT NULL THEN
    DELETE FROM public.call_signals WHERE id > 0;
  END IF;
  IF to_regclass('public.call_participants') IS NOT NULL THEN
    DELETE FROM public.call_participants WHERE id > 0;
  END IF;
  IF to_regclass('public.calls') IS NOT NULL THEN
    DELETE FROM public.calls WHERE id > 0;
  END IF;
  -- خمسُ محاولاتٍ في الساعة لإدخال المفتاح: يبدأ الجميعُ الإطلاقَ بعدّادٍ صفر.
  IF to_regclass('public.code_attempts') IS NOT NULL THEN
    DELETE FROM public.code_attempts WHERE id > 0;
  END IF;
END $calls$;

-- == 5. السجلّ ============================================================
DO $audit$
DECLARE v_before json := current_setting('adayl.before', true)::json;
BEGIN
  PERFORM public.write_audit('launch.fresh_start',
    format('بداية نظيفة قبل الإطلاق: %s رسالة و%s إشعارًا و%s مقترحًا معلَّقًا',
           v_before ->> 'رسائل', v_before ->> 'إشعارات', v_before ->> 'مقترحات'),
    'launch');
END $audit$;

-- == 6. الحرّاس ===========================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 7. النتيجة: آخرُ جدولٍ يظهر في المحرّر ==================================
SELECT 'ما كان قبل المسح' AS "الفحص",
       coalesce(current_setting('adayl.before', true), '—') AS "النتيجة"
UNION ALL SELECT 'الرسائلُ الآن',
       (SELECT count(*)::text FROM public.chat_messages)
UNION ALL SELECT 'الإشعاراتُ الآن',
       (SELECT count(*)::text FROM public.notifications)
UNION ALL SELECT 'المقترحاتُ المعلَّقة الآن',
       CASE WHEN to_regclass('public.proposals') IS NULL THEN '—'
            ELSE (SELECT count(*)::text FROM public.proposals
                   WHERE status = 'pending') END
UNION ALL SELECT 'المقترحاتُ المقبولة (محفوظةٌ عمدًا)',
       CASE WHEN to_regclass('public.proposals') IS NULL THEN '—'
            ELSE (SELECT count(*)::text FROM public.proposals
                   WHERE status = 'accepted') END
UNION ALL SELECT 'صفحاتُ قانون الجمعية (لم تُمسّ)',
       CASE WHEN to_regclass('public.bylaw_pages') IS NULL THEN '—'
            ELSE (SELECT count(*)::text FROM public.bylaw_pages) END
UNION ALL SELECT 'المشتركون (لم يُمسّوا)',
       (SELECT count(*)::text FROM public.adeels)
UNION ALL SELECT 'الإيصالات (لم تُمسّ)',
       (SELECT count(*)::text FROM public.payments)
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       ((SELECT row_to_json(s)::text FROM public.v_cash_summary s)
          = current_setting('adayl.fund_before', true))::text
UNION ALL SELECT 'رصيدُ الجمعية',
       (SELECT balance FROM public.v_cash_summary);

COMMIT;
