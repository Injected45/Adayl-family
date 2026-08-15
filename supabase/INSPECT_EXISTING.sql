-- INSPECT_EXISTING.sql — what is actually in this project, before touching it.
--
-- ═══════════════════════════════════════════════════════════════════════════
--  READ-ONLY. It creates nothing, changes nothing, drops nothing. Safe on a
--  live project with real records in it.
-- ═══════════════════════════════════════════════════════════════════════════
--
-- WHY IT EXISTS
--
-- VERIFY_INSTALL.sql answers "is the current schema correctly installed". This
-- answers the question that has to come first: "is there anything here worth
-- keeping". A project holding the old family/member schema and a project holding
-- that schema plus three years of receipts look identical from the app, and the
-- difference decides whether RESET_AND_APPLY.sql is a convenience or a disaster.
--
-- It assumes NO particular schema. It reads whatever tables exist, so it works on
-- the old family/member shape, on the new عديل shape, and on an empty project —
-- and it never names a table in a way that could fail to parse when that table is
-- absent. Every count is reached through the `tabs` CTE, which only contains
-- tables that are actually there.
--
-- ONE result set, deliberately: the Supabase SQL editor shows the last statement
-- only, so three separate SELECTs would display the third and silently discard
-- the two that mattered.
--
--   Supabase dashboard → SQL Editor → New query → paste → Run → send the table back.

WITH
-- Exact counts, not pg_class.reltuples. An estimate reads "0" for any table that
-- was never ANALYZEd, and "0" here is the number that licenses a reset.
tabs AS (
  SELECT t.table_name AS name,
         (xpath('/row/c/text()',
                query_to_xml(format('SELECT count(*) AS c FROM public.%I', t.table_name),
                             false, true, ''))
         )[1]::text::bigint AS n
    FROM information_schema.tables t
   WHERE t.table_schema = 'public'
     AND t.table_type   = 'BASE TABLE'
),
-- The tables where losing a row means losing money or its history. Named as a
-- list matched against `tabs`, so the ones this schema does not have simply do
-- not contribute rather than raising "relation does not exist".
money AS (
  SELECT coalesce(sum(n), 0) AS n
    FROM tabs
   WHERE name IN ('receivables', 'receivable_lines', 'payments',
                  'payment_allocations', 'cash_movements', 'audit_log')
)
SELECT * FROM (
  -- ── Which schema is live ──────────────────────────────────────────────────
  SELECT 1 AS s, 'المخطط' AS "البند",
         CASE
           WHEN EXISTS (SELECT 1 FROM tabs WHERE name = 'adeels')
             THEN 'الجديد — عديل'
           WHEN EXISTS (SELECT 1 FROM tabs WHERE name IN ('families', 'members'))
             THEN 'القديم — عائلات وأعضاء'
           WHEN EXISTS (SELECT 1 FROM tabs)
             THEN 'جداول موجودة لكنها ليست مخطط هذا التطبيق'
           ELSE 'لا شيء — مشروع فارغ'
         END AS "التفصيل"

  -- ── The one line that decides whether a reset is allowed ──────────────────
  UNION ALL
  SELECT 2, 'سجلات مالية',
         (SELECT n FROM money)::text || ' صف — ' ||
         CASE WHEN (SELECT n FROM money) > 0
              THEN '⚠ لا تُعِد البناء قبل نسخة احتياطية'
              ELSE 'إعادة البناء لا تُتلف مالاً' END

  -- ── Every table, biggest first ────────────────────────────────────────────
  UNION ALL
  SELECT 3, 'جدول: ' || name, n::text || ' صف' FROM tabs

  -- ── Who can sign in. Sourced FROM tabs, so this row is absent rather than
  --    an error when there is no profiles table at all. These accounts survive
  --    a reset in auth.users but lose their role and approval with profiles,
  --    which makes this the list to restore from afterwards.
  UNION ALL
  SELECT 4, 'الحسابات',
         coalesce((xpath('/row/c/text()', query_to_xml(
           'SELECT string_agg(email || '' ('' || role || ''/'' || status || '')'',
                              '', '' ORDER BY email) AS c FROM public.profiles',
           false, true, '')))[1]::text, 'لا حسابات')
    FROM tabs WHERE name = 'profiles'
) r
ORDER BY s, "البند";
