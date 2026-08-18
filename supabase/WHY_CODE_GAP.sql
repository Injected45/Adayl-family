-- ─────────────────────────────────────────────────────────────────────────────
-- لماذا يبدأ الترقيم من A-03؟  (وكذلك PAY- و EXP-)
--
-- للقراءة فقط. لا يعدّل صفًا ولا عدّادًا. الصقه في SQL Editor على المشروع الحيّ.
--
-- الرمز ليس ترقيمًا مستقلًا: adeel_code عمود GENERATED من id، و id عدّاد
-- (IDENTITY). فغياب A-01 يعني شيئًا واحدًا — لا يوجد صف يحمل id = 1 — وله
-- سببان لا ثالث لهما، ونتيجتاهما مختلفتان تمامًا:
--
--   (أ) عديلان سُجّلا ثم حُذفا.  ← فيه فَقْد فعلي، ويظهر في سجل التدقيق.
--   (ب) محاولتا تسجيل فشلتا.     ← لا شيء ضاع، ولا يظهر في سجل التدقيق.
--
-- والسبب (ب) ليس خللًا: عدّاد PostgreSQL لا يخضع للتراجع (non-transactional)
-- عمدًا. لو أعاد الرقم عند فشل الإدخال لَاضطُرّ كل تسجيل أن ينتظر الذي قبله
-- ليعرف رقمه، ولَتَعطّل تسجيلان متزامنان أحدهما على الآخر. الرقم المحروق هو
-- ثمن أن يعمل التسجيلان معًا — يُدفَع مرة واحدة وقت المحاولة الفاشلة.
--
-- ⚠ الفجوة لا تعني نقصًا في السجل. عدد المشتركين في الشاشة الرئيسية هو
--   العدد الحقيقي؛ الفجوة في الترقيم وحده. القسم 1 أدناه هو ما يثبت ذلك.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1) من على السجلّ الآن، وبأي أرقام ────────────────────────────────────────
--    العمود الأخير هو الحكم: كم عديلًا فعليًا مقابل أعلى رقم صدر.
SELECT '1) السجلّ' AS "القسم",
       a.id        AS "id",
       a.adeel_code AS "الرمز",
       a.full_name  AS "الاسم",
       a.status     AS "الحالة",
       a.created_at::date AS "أُضيف في"
  FROM public.adeels a
 ORDER BY a.id;

-- ── 2) الأرقام الغائبة بين 1 وأعلى رقم مستعمل ────────────────────────────────
--    كل رقم هنا رمزٌ لن يُستعمل أبدًا: العمود GENERATED من id، فلا سبيل لإعادة
--    استعماله إلا بتغيير id نفسه.
SELECT '2) أرقام محروقة' AS "القسم",
       g.missing_id                      AS "id مفقود",
       'A-' || CASE WHEN g.missing_id < 10 THEN '0' ELSE '' END
             || g.missing_id::text       AS "الرمز الذي كان سيحمله"
  FROM generate_series(
         1,
         coalesce((SELECT max(id) FROM public.adeels), 0)
       ) AS g(missing_id)
 WHERE NOT EXISTS (SELECT 1 FROM public.adeels a WHERE a.id = g.missing_id)
 ORDER BY g.missing_id;

-- ── 3) أين وصل العدّاد ───────────────────────────────────────────────────────
--    آخر رقم أصدره. إن كان أكبر من أعلى id موجود، فآخر ما صدر ذهب إلى محاولة
--    لم تُكمَل — أو إلى صفّ حُذف بعد ذلك.
SELECT '3) العدّاد' AS "القسم",
       s.sequencename AS "العدّاد",
       s.last_value   AS "آخر رقم أصدره"
  FROM pg_sequences s
 WHERE s.schemaname = 'public'
   AND s.sequencename IN ('adeels_id_seq', 'payments_id_seq', 'disbursements_id_seq')
 ORDER BY s.sequencename;

-- ── 4) الفصل بين السببين: هل حُذف أحد فعلًا؟ ─────────────────────────────────
--    delete_adeel تكتب «adeel.delete» في سجل التدقيق ومعها الرمز. فإن ظهر صفّ
--    هنا فالسبب (أ) — وهذا هو اسم من حُذف. وإن لم يظهر شيء فالسبب (ب).
--
--    ⚠ وقيدٌ على هذا الجواب: «مسح البيانات المالية» يمسح سجل التدقيق نفسه.
--       فخلوّ الجدول يعني «لا أثر لحذف» لا «لم يُحذف أحد قطعًا».
--    ولا يصمت حين لا يجد شيئًا: صفٌّ فارغ وعنوانٌ غائب يُقرأ كاستعلام لم يعمل،
--    وهو هنا نصف الجواب لا انعدامه.
SELECT '4) هل حُذف أحد' AS "القسم",
       to_char(l.occurred_at, 'YYYY-MM-DD HH24:MI') AS "متى",
       l.actor_name   AS "من",
       l.detail       AS "ماذا",
       l.ref          AS "الرمز"
  FROM public.audit_log l
 WHERE l.event_type = 'adeel.delete'
UNION ALL
SELECT '4) هل حُذف أحد', '—', '—', 'لا أثر لأي حذف في سجل التدقيق', '—'
 WHERE NOT EXISTS (
   SELECT 1 FROM public.audit_log WHERE event_type = 'adeel.delete')
 ORDER BY 2;

-- ── 5) الحكم في سطر واحد ─────────────────────────────────────────────────────
SELECT '5) الحكم' AS "القسم",
       CASE
         WHEN (SELECT count(*) FROM public.adeels) = 0
           THEN 'السجلّ فارغ.'
         WHEN NOT EXISTS (
                SELECT 1 FROM generate_series(1, (SELECT max(id) FROM public.adeels)) g(i)
                 WHERE NOT EXISTS (SELECT 1 FROM public.adeels a WHERE a.id = g.i))
           THEN 'لا فجوة أصلًا — الترقيم متصل من A-01.'
         WHEN EXISTS (SELECT 1 FROM public.audit_log WHERE event_type = 'adeel.delete')
           THEN 'الفجوة من حذف مسجَّل — انظر القسم 4، فيه اسم من حُذف ومتى.'
         ELSE
              'الفجوة من محاولات تسجيل لم تُكمَل. لم يُحذف أحد، ولا ينقص السجلّ '
           || 'أحدًا: عدد المشتركين ' || (SELECT count(*) FROM public.adeels)::text
           || ' وهو العدد الصحيح.'
       END AS "النتيجة";
