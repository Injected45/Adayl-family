-- ============================================================================
--  WHY_21000.sql — لماذا رفض «مسح كل البيانات» بالرمز 21000؟
--
--  READ-ONLY. لا يمسح ولا يعدّل شيئاً. الصق وشغّل وأرسل الجدول.
--
--  WHAT 21000 IS
--    cardinality_violation: a subquery used where ONE value was expected
--    returned MORE THAN ONE ROW. Nothing in purge_all_data's own body can do
--    that — it is six counts, a TRUNCATE and two DELETEs. So it came from
--    something the DELETE set off: a cascade, a SET NULL, or a trigger.
--
--  ⚠ AND THE REPO CANNOT ANSWER IT. Every trigger and every foreign key in
--    supabase/migrations was read before this file was written, and none of
--    them explains a 21000 on this path. That leaves one possibility worth
--    more than any amount of further reading: the live database holds
--    something the repo does not — an older function body, an extra trigger,
--    a constraint added by hand. This asks the database itself.
--
--  ⚠ ONE STATEMENT, because the Supabase editor renders only the LAST result
--    set. Everything below is a single UNION ALL.
-- ============================================================================

SELECT * FROM (
  -- ── 1. أيّ نسخة من الدالة مركّبة فعلاً ───────────────────────────────────
  -- ⚠ THE INSTALLED BODY, not the one in the file. PATCH_20260819 replaced
  --   purge_all_data to add chat_messages to the TRUNCATE; if this project is
  --   still holding the PATCH_20260817 body, it truncates one table fewer and
  --   the DELETE below meets rows the newer version would have cleared.
  SELECT 1 AS ord,
         'نسخة purge_all_data المركّبة' AS "الفحص",
         coalesce((
           SELECT CASE
                    WHEN p.prosrc LIKE '%chat_messages%'
                      THEN 'نسخة 19/08 — تُفرغ المحادثات أيضاً'
                    WHEN p.prosrc LIKE '%disbursements%'
                      THEN 'نسخة 17/08 — بلا المحادثات'
                    ELSE 'نسخة قديمة — بلا السندات ولا المحادثات'
                  END
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'purge_all_data'),
           'الدالة غير موجودة') AS "النتيجة"

  -- ── 2. كل زناد قد يشتعل عند الحذف ───────────────────────────────────────
  -- Whatever the repo says, this is what the database will actually run.
  UNION ALL SELECT 2, 'الزنادات القائمة على الجداول الباقية',
         coalesce((
           SELECT string_agg(c.relname || '.' || t.tgname, '، '
                             ORDER BY c.relname, t.tgname)
             FROM pg_trigger t
             JOIN pg_class c ON c.oid = t.tgrelid
             JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND NOT t.tgisinternal
              AND c.relname IN ('adeels', 'profiles', 'association_settings',
                                'adeel_access_codes', 'chat_messages')),
           'لا شيء')

  -- ── 3. كل مفتاح أجنبي يشير إلى العدايل، وماذا يفعل عند الحذف ────────────
  -- ⚠ RESTRICT or NO ACTION on a table the purge does NOT empty is the classic
  --   way this fails — though that raises 23503, not 21000. SET NULL is an
  --   UPDATE, and an UPDATE runs triggers.
  UNION ALL SELECT 3, 'ما يشير إلى adeels، وسلوكه عند الحذف',
         coalesce((
           SELECT string_agg(
                    src.relname || '.' || a.attname || ' → ' ||
                    CASE con.confdeltype WHEN 'a' THEN 'NO ACTION'
                                         WHEN 'r' THEN 'RESTRICT'
                                         WHEN 'c' THEN 'CASCADE'
                                         WHEN 'n' THEN 'SET NULL'
                                         WHEN 'd' THEN 'SET DEFAULT' END,
                    '، ' ORDER BY src.relname, a.attname)
             FROM pg_constraint con
             JOIN pg_class src ON src.oid = con.conrelid
             JOIN pg_class tgt ON tgt.oid = con.confrelid
             JOIN pg_attribute a ON a.attrelid = con.conrelid
                                AND a.attnum = con.conkey[1]
            WHERE con.contype = 'f' AND tgt.relname = 'adeels'),
           'لا شيء')

  UNION ALL SELECT 4, 'وما يشير إلى profiles',
         coalesce((
           SELECT string_agg(
                    src.relname || '.' || a.attname || ' → ' ||
                    CASE con.confdeltype WHEN 'a' THEN 'NO ACTION'
                                         WHEN 'r' THEN 'RESTRICT'
                                         WHEN 'c' THEN 'CASCADE'
                                         WHEN 'n' THEN 'SET NULL'
                                         WHEN 'd' THEN 'SET DEFAULT' END,
                    '، ' ORDER BY src.relname, a.attname)
             FROM pg_constraint con
             JOIN pg_class src ON src.oid = con.conrelid
             JOIN pg_class tgt ON tgt.oid = con.confrelid
             JOIN pg_attribute a ON a.attrelid = con.conrelid
                                AND a.attnum = con.conkey[1]
            WHERE con.contype = 'f' AND tgt.relname = 'profiles'),
           'لا شيء')

  -- ── 5. صفوف الإعدادات ───────────────────────────────────────────────────
  -- ⚠ THE SINGLETON IS THE BEST 21000 CANDIDATE IN THE WHOLE SCHEMA. Half the
  --   read functions say `(SELECT … FROM association_settings)` as a scalar
  --   subquery, and a scalar subquery over TWO rows is exactly a
  --   cardinality_violation. ck_settings_singleton is supposed to make that
  --   impossible — so if this says anything but 1, the constraint is missing
  --   here and that is the whole answer.
  UNION ALL SELECT 5, 'عدد صفوف association_settings (يجب أن يكون 1)',
         (SELECT count(*)::text FROM public.association_settings)
  UNION ALL SELECT 5.1, 'وقيد الصف الواحد قائم',
         CASE WHEN EXISTS (SELECT 1 FROM pg_constraint
                            WHERE conname = 'ck_settings_singleton')
                THEN 'نعم' ELSE 'مفقود — وهذا هو السبب' END

  -- ── 6. وباقي ما قد يتعدّد حيث يُنتظر واحد ────────────────────────────────
  UNION ALL SELECT 6, 'رموز دخول مكرّرة لعديل واحد',
         coalesce((
           SELECT string_agg(t, '، ') FROM (
             SELECT adeel_id::text || ' (' || count(*)::text || ')' AS t
               FROM public.adeel_access_codes
              GROUP BY adeel_id HAVING count(*) > 1) x),
           'لا شيء')
  UNION ALL SELECT 6.1, 'حسابات بوابة مكرّرة لعديل واحد',
         coalesce((
           SELECT string_agg(t, '، ') FROM (
             SELECT adeel_id::text || ' (' || count(*)::text || ')' AS t
               FROM public.profiles
              WHERE adeel_id IS NOT NULL
              GROUP BY adeel_id HAVING count(*) > 1) x),
           'لا شيء')
  UNION ALL SELECT 6.2, 'مديرون معتمدون',
         (SELECT count(*)::text FROM public.profiles
           WHERE role = 'admin' AND status = 'approved')
) t ORDER BY ord;
