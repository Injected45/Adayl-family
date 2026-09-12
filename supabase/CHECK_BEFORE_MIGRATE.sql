-- ============================================================================
--  قبل الترحيل: مَن في السجلّ الآن، وبأيّ كود؟
--
--  ⚠ هذا هو السؤالُ الوحيدُ الذي لا أستطيع الإجابةَ عنه من هنا، وهو الوحيدُ
--    الذي لا يجوز تخمينُه: ملفُّ الترحيل يضع مالَ كلّ رجلٍ على كودِه
--    (A-01 .. A-08)، فلو اختلف ترتيبُ سجلِّك عن ترتيب المنظومة، وقع مالُ
--    رجلٍ على آخر — ولن يشتكي شيء.
--
--  للقراءة فقط. لا يغيّر حرفًا.
-- ============================================================================
SELECT a.adeel_code                          AS "الكود",
       a.full_name                           AS "الاسم في التطبيق الآن",
       a.status                              AS "الحالة",
       coalesce(p.email, '—')                AS "الحساب المربوط"
  FROM public.adeels a
  LEFT JOIN public.profiles p ON p.adeel_id = a.id
 ORDER BY a.adeel_code;

-- وما فيه من أرقامٍ اليوم — كلُّه سيُمسح ويُستبدل بأرقام المنظومة
SELECT (SELECT count(*) FROM public.adeels)             AS "عدايل",
       (SELECT count(*) FROM public.receivables)        AS "استحقاقات",
       (SELECT count(*) FROM public.payments)           AS "إيصالات",
       (SELECT count(*) FROM public.disbursements)      AS "سندات",
       (SELECT count(*) FROM public.closed_periods)     AS "أشهر مغلقة",
       (SELECT count(*) FROM public.chat_messages)      AS "رسائل (لا تُمسّ)";
