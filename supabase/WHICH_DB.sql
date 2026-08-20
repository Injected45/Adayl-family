-- ============================================================================
--  أيّ قاعدة أنا واقف عليها؟  —  للصق في SQL Editor.  للقراءة فقط.
--
--  PATCH_20260820b refused with «لا يوجد جدول صرف», and that refusal is either
--  true or the editor is pointed somewhere unexpected. This tells which.
--
--  ⚠ IT CANNOT ERROR ON A MISSING TABLE. to_regclass returns NULL rather than
--    raising, and the count goes through query_to_xml — the same device
--    WHICH_STATE.sql uses — so a project missing everything still answers
--    instead of dying on the first line.
-- ============================================================================
SELECT
  current_database()                            AS "القاعدة",
  current_user                                  AS "المستخدم",
  to_regclass('public.adeels')::text            AS "سجل العدايل",
  CASE WHEN to_regclass('public.adeels') IS NULL THEN '—'
       ELSE (xpath('/row/c/text()',
              query_to_xml('SELECT count(*) AS c FROM public.adeels',
                           false, true, '')))[1]::text
  END                                           AS "عدد العدايل",
  to_regclass('public.disbursements')::text     AS "جدول الصرف",
  to_regclass('public.chat_messages')::text     AS "جدول المحادثات",
  CASE WHEN to_regclass('public.disbursements') IS NULL THEN '—'
       ELSE (xpath('/row/c/text()',
              query_to_xml('SELECT count(*) AS c FROM public.disbursements',
                           false, true, '')))[1]::text
  END                                           AS "عدد السندات";
