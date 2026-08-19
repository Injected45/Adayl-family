-- ============================================================================
--  WHY_18C.sql — لماذا يقول WHICH_STATE إن «عهد المشتركين» غير مطبَّق بينما
--  الدردشة مطبَّقة؟
--
--  READ-ONLY. لا ينشئ شيئاً ولا يحذف شيئاً ولا يكتب صفاً. آمن على المشروع الحيّ.
--
--  ── الحالة التي يفسّرها ─────────────────────────────────────────────────────
--  PATCH_20260818c ينشئ شيئين في معاملة واحدة: الدالة members_held(bigint)
--  والعمود v_cash_summary."heldForMembers". ومعاملة واحدة تعني أن الاثنين ينزلان
--  معاً أو لا ينزل أيّهما.
--
--  و PATCH_20260819 (الدردشة) يبدأ بحارس يرفض العمل ما لم توجد members_held.
--
--  فالقراءة «الدردشة مطبَّقة + heldForMembers غائب» تناقض الاثنين معاً، ولها
--  تفسيران لا ثالث لهما:
--
--    (أ) الدالة موجودة والعمود غائب — أي أن شيئاً أعاد بناء v_cash_summary بعد
--        18c فأسقط العمود الملحق. عندها 18c نزل فعلاً ثم نُقض نصفه.
--
--    (ب) الدالة غائبة أيضاً — أي أن 18c لم ينزل قط، والدردشة نزلت من نسخة
--        أقدم من الملف لا حارس فيها.
--
--  الفرق بينهما ليس أكاديمياً: في (أ) لا يكفي إعادة تشغيل 18c وحده إن كان الذي
--  أسقط العمود سيعاد تشغيله، وفي (ب) إعادة تشغيل 18c هي كل المطلوب.
--
--  السطر الأخير يقول أيّهما.
-- ============================================================================

WITH probe AS (
  SELECT
    to_regprocedure('public.members_held(bigint)') IS NOT NULL      AS fn_exists,
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='v_cash_summary'
               AND column_name='heldForMembers')                     AS col_exists,
    to_regclass('public.chat_messages')  IS NOT NULL                 AS chat_exists,
    to_regclass('public.v_cash_summary') IS NOT NULL                 AS summary_exists,
    -- الدوال الثلاث التي يستبدل 18c أجسادها. وجود الدالة لا يثبت شيئاً — كلها
    -- كانت موجودة قبله بالاسم نفسه — فالفحص على جسدها: هل تستدعي members_held؟
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public'
        AND p.proname IN ('register_disbursement','cancel_payment','api_association_finance')
        AND pg_get_functiondef(p.oid) LIKE '%members_held%')         AS bodies_patched
)
SELECT * FROM (
  SELECT 1 AS ord, 'الدالة members_held(bigint)' AS item,
         CASE WHEN fn_exists THEN 'موجودة' ELSE 'غائبة' END AS answer FROM probe
  UNION ALL SELECT 2, 'العمود v_cash_summary."heldForMembers"',
         CASE WHEN NOT summary_exists THEN 'لا يوجد عرض v_cash_summary أصلاً'
              WHEN col_exists THEN 'موجود' ELSE 'غائب' END FROM probe
  UNION ALL SELECT 3, 'أجساد الدوال الثلاث تستدعي members_held',
         bodies_patched::text || ' من 3' FROM probe
  UNION ALL SELECT 4, 'جدول الدردشة chat_messages',
         CASE WHEN chat_exists THEN 'موجود' ELSE 'غائب' END FROM probe
  -- أعمدة v_cash_summary بترتيبها، لأن CREATE OR REPLACE VIEW لا يُلحق إلا في
  -- الآخر: فموضع heldForMembers — أو غيابه — يقول أي نسخة من العرض هي القائمة.
  UNION ALL SELECT 5, 'أعمدة v_cash_summary بالترتيب',
         coalesce((SELECT string_agg(column_name, ' | ' ORDER BY ordinal_position)
                     FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='v_cash_summary'),
                  'لا يوجد')
  UNION ALL SELECT 9, '‹‹ التشخيص ››',
         CASE
           WHEN fn_exists AND col_exists
             THEN '18c مطبَّق بالكامل — أعد تشغيل WHICH_STATE، فقد قرأتَ نتيجة قديمة.'
           WHEN fn_exists AND NOT col_exists
             THEN 'الحالة (أ): الدالة نزلت والعمود سقط — شيء أعاد بناء v_cash_summary بعد 18c. أرسل هذا الجدول كاملاً قبل تشغيل أي ملف.'
           WHEN NOT fn_exists AND chat_exists
             THEN 'الحالة (ب): 18c لم ينزل قط، والدردشة نزلت بلا حارسها. أرسل هذا الجدول كاملاً قبل تشغيل أي ملف.'
           WHEN NOT fn_exists
             THEN 'لا الدالة ولا الدردشة — طبّق 18c ثم 19 بالترتيب.'
           ELSE 'حالة غير متوقعة — أرسل الجدول كاملاً.'
         END FROM probe
) t ORDER BY ord;
