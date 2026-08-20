-- ============================================================================
--  WHY_NO_AID3.sql — الفحص الثالث، والمصحَّح.
--
--  READ-ONLY.
--
--  ⚠ الفحص الثاني سأل عن مفتاح اسمه 'ledger' والدالة تسمّيه 'vouchers'، فأعاد
--    صفراً كان خطأً في السؤال لا في الجواب. المفتاح هنا هو الذي يقرأه التطبيق
--    فعلاً — راجع AdeelAid.fromJson.
--
--  جدولان لا غير:
--    1. هل تُرجع الدالة أسطر السجل فعلاً (بصلاحيات المالك، فتتجاوز RLS).
--    2. مَن ربط جهازه ومَن لم يربط — وهذا ما بقي إن كان الجدول الأوّل سليماً،
--       لأن my_adeel_id() تعيد NULL لجهاز غير مُطالَب، و NULL رفضٌ لا تجاوز.
-- ============================================================================

-- == 1. ما تُرجعه الدالة، بالمفتاح الصحيح ===================================
SELECT a.adeel_code                               AS "الرمز",
       a.full_name                                AS "الاسم",
       (public.api_adeel_aid(a.id) ->> 'total')   AS "الإجمالي",
       (public.api_adeel_aid(a.id) ->> 'count')   AS "عدد السندات",
       jsonb_array_length(
         coalesce(public.api_adeel_aid(a.id) -> 'vouchers', '[]'::jsonb))
                                                  AS "أسطر السجل"
FROM public.adeels a
WHERE EXISTS (SELECT 1 FROM public.disbursements d WHERE d.payee_adeel_id = a.id)
ORDER BY a.id;

-- == 2. مَن يستطيع أن يقرأها من هاتفه =======================================
-- «حساب بلا جهاز مُطالَب» يعني شاشة فارغة في كل موضع يمرّ على my_adeel_id —
-- وليس شاشة الصرف وحدها.
SELECT
  a.adeel_code                           AS "الرمز",
  a.full_name                            AS "الاسم",
  CASE WHEN p.id IS NULL THEN 'لا حساب بوابة'
       WHEN p.device_id IS NULL THEN '⚠ حساب بلا جهاز مُطالَب'
       ELSE 'مربوط بجهاز' END            AS "حالة البوابة",
  coalesce(p.status::text, '—')          AS "حالة الحساب",
  -- ⚠ الرمز في جدول منفصل، لا عمود في profiles. عمود بذلك الاسم كان
  --   تخميني، والتخمين هو ما كسر الاستعلام.
  CASE WHEN c.adeel_id IS NULL THEN 'لم يُصدر له رمز'
       WHEN c.redeemed_at IS NULL THEN '⚠ رمز صدر ولم يُستَرد'
       ELSE 'رمز مُستَرد' END           AS "الرمز الخاص"
FROM public.adeels a
LEFT JOIN public.profiles p ON p.adeel_id = a.id
-- مفتاح الجدول هو adeel_id نفسه، فصفٌّ واحد لكل عديل ولا عمود id فيه.
LEFT JOIN public.adeel_access_codes c ON c.adeel_id = a.id
ORDER BY a.id;
