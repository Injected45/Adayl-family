-- ============================================================================
--  WHY_NO_AID2.sql — الفحص الثاني: مَن هو المشترك، وهل يستطيع أن يقرأ أصلاً.
--
--  READ-ONLY. لا ينشئ شيئاً ولا يحذف شيئاً ولا يكتب صفاً.
--
--  ── ما استبعده الفحص الأوّل ─────────────────────────────────────────────────
--  الجدول موجود، والدالة موجودة، والسياسة موجودة وصحيحة، والامتياز موجود،
--  و my_adeel_id قابلة للتنفيذ، وكل السندات العشرة منسوبة إلى مشتركين بأعيانهم.
--  فالعطل ليس في شكل القاعدة.
--
--  ── ما بقي، وكلها تُفرغ الشاشة بالطريقة نفسها ───────────────────────────────
--    أ) الجهاز غير مُطالَب. my_adeel_id() تقرأ ترويسة x-device-id وتعيد NULL إن
--       لم تطابق، و NULL رفضٌ لا تجاوز — فلا سطر يمرّ من السياسة. والفحص الأوّل
--       قال إن عديلاً واحداً لم يطالب جهازاً بعد؛ هذا الملف يسمّيه.
--    ب) لا حساب بوابة له أصلاً — لم يُصدَر له رمز، أو أُصدر ولم يُستَرد.
--    ج) السندات باسم عديلٍ آخر يحمل اسماً مشابهاً. عشرة سندات منسوبة لا تعني
--       أنها منسوبة إلى الرجل الذي فتح الشاشة.
--    د) الدالة غير قابلة للتنفيذ من المشترك — عندها تظهر رسالة خطأ لا شاشة
--       فارغة، وهو فرقٌ يُفرّق بين عطلين مختلفين تماماً.
--
--  ⚠ والصفّ الأخير يشغّل api_adeel_aid فعلاً بصلاحيات المالك. المالك يتجاوز RLS،
--    فإن أعادت السندات هنا وأعطت فراغاً على الهاتف، فالسبب في السياسة أو في
--    الجهاز قطعاً — لا في الدالة ولا في البيانات. وهذا ما يفصل السببين اللذين
--    يبدوان واحداً من الشاشة.
-- ============================================================================

-- == 1. كل عديل: سنداته، وحسابه، وهل طالب جهازاً ============================
SELECT
  a.id                                   AS "المعرّف",
  a.adeel_code                           AS "الرمز",
  a.full_name                            AS "الاسم",
  count(d.id) FILTER (WHERE d.status <> 'ملغي')  AS "سندات سارية",
  coalesce(sum(d.amount) FILTER (WHERE d.status <> 'ملغي'), 0)::numeric(12,2)
                                         AS "مجموعها",
  CASE WHEN p.id IS NULL THEN 'لا حساب بوابة'
       WHEN p.device_id IS NULL THEN '⚠ حساب بلا جهاز مُطالَب'
       ELSE 'مربوط بجهاز' END            AS "حالة البوابة",
  coalesce(p.status::text, '—')          AS "حالة الحساب"
FROM public.adeels a
LEFT JOIN public.disbursements d ON d.payee_adeel_id = a.id
LEFT JOIN public.profiles p      ON p.adeel_id = a.id
GROUP BY a.id, a.adeel_code, a.full_name, p.id, p.device_id, p.status
ORDER BY a.id;

-- == 2. هل يستطيع المشترك تنفيذ الدالة أصلاً ================================
-- غيابه يعطي رسالة خطأ لا شاشة فارغة — وهذا ما يميّزه عمّا سبق.
SELECT 'تنفيذ api_adeel_aid من حساب مشترك' AS "الفحص",
       has_function_privilege('authenticated', 'public.api_adeel_aid(bigint)',
                              'EXECUTE')  AS "النتيجة"
UNION ALL SELECT 'وتنفيذ v_disbursements المقروء داخلها',
       has_table_privilege('authenticated', 'public.v_disbursements', 'SELECT')
UNION ALL SELECT 'وقراءة سجل العدايل، فالدالة تصل إليه لاسمه ورمزه',
       has_table_privilege('authenticated', 'public.adeels', 'SELECT');

-- == 3. الدالة نفسها، مُشغَّلة على كل من صُرف له ==============================
-- ⚠ بصلاحيات المالك، والمالك يتجاوز RLS. فما يظهر هنا هو ما تقوله البيانات
--   والدالة معاً؛ وما ينقص على الهاتف بعده يكون سببه السياسة أو الجهاز لا غير.
SELECT a.adeel_code                              AS "الرمز",
       a.full_name                               AS "الاسم",
       (public.api_adeel_aid(a.id) ->> 'total')  AS "الإجمالي كما تُرجعه الدالة",
       (public.api_adeel_aid(a.id) ->> 'count')  AS "عدد السندات",
       jsonb_array_length(
         coalesce(public.api_adeel_aid(a.id) -> 'ledger', '[]'::jsonb))
                                                 AS "أسطر السجل"
FROM public.adeels a
WHERE EXISTS (SELECT 1 FROM public.disbursements d WHERE d.payee_adeel_id = a.id)
ORDER BY a.id;
