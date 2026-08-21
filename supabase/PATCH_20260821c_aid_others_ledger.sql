-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (c).  «أسلاف للغير» يصير دفتراً.
--
--  WHAT CHANGES
--    api_aid_others returns its vouchers OLDEST FIRST, each carrying the
--    running total to that point — the same shape api_adeel_aid has returned
--    since 18/08, so the two screens can share one ledger widget instead of
--    each keeping a copy that drifts.
--
--  ⚠ THE ORDER REVERSES, and that is the substance rather than a detail. It
--    was newest-first, which is a FEED: a list of recent events, where a
--    running total would count downwards and mean nothing. A ledger runs the
--    other way — oldest at the top, each line adding to the one above — and
--    that is the only order in which «الإجمالي» is a number rather than a
--    decoration.
--
--  ⚠ AND THE SERVER SUMS. Money is text end to end in this project because a
--    Postgres numeric reaches dart:convert as a double; a screen that added
--    its own column would be the one place that rule is broken, and the
--    hardest place to notice it.
--
--  ⚠ CANCELLED VOUCHERS KEEP THEIR LINE. The window frame covers every row
--    and the SUM excludes reversals with FILTER — so a reversed line is
--    listed, struck through, and leaves the balance where it was. A WHERE
--    would delete it from the record, which rule 9 forbids.
--
--  ⚠ NOTHING ELSE MOVES. CREATE OR REPLACE on a function that already exists,
--    so its ACL is kept and no lockdown sweep is needed. No row is written,
--    no policy is touched, and `total`, `count` and `byCategory` come back
--    byte for byte.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.api_aid_others(bigint)') IS NULL THEN
    RAISE EXCEPTION
      'لا توجد دالة أسلاف للغير. طبّق supabase/PATCH_20260820b_aid_transparency.sql أولاً.';
  END IF;
END $prereq$;

-- ⚠ THE BODY IS THE INSTALLED ONE, LIFTED WHOLE, with only the vouchers key
--   rewritten. A patch that retyped the rest would risk losing the
--   `payee_adeel_id IS NULL` filter — the clause that stops one member
--   reading what another was given, by name.
CREATE OR REPLACE FUNCTION public.api_aid_others(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
  -- ⚠ COLLECTIVE ONLY — `payee_adeel_id IS NULL`. That is the same clause the
  --   policy above uses, restated here so the function is honest on its own:
  --   a reader who somehow held a wider policy would still get only these.
  --
  -- ⚠ AND CANCELLED VOUCHERS ARE EXCLUDED. A man's own ledger keeps his
  --   reversals listed and struck through, because rule 9 says his history is
  --   not an embarrassment. A reversal on a communal expense is an
  --   administrative correction and belongs in the audit trail, not on a
  --   screen a member reads to see where the fund went.
  WITH live AS (
    SELECT d.* FROM public.disbursements d
     WHERE d.payee_adeel_id IS NULL
       AND d.status <> 'ملغي'
  )
  SELECT jsonb_build_object(
    'total', (SELECT coalesce(sum(l.amount), 0)::numeric(12,2)::text FROM live l),
    'count', (SELECT count(*) FROM live l),
    -- ── BY OCCASION, largest first ────────────────────────────────────────
    -- «على ماذا أُنفق» is the question this screen is opened with — a member
    -- wants to know where the fund went, and a communal expense has no man to
    -- group under. The وجه is the only grouping it HAS, and it is exactly the
    -- one the association chose an enum for so that عزاء and مصاريف عزاء
    -- could not become two answers to one question.
    --
    -- Only the headings actually spent on, unlike v_expense_by_category which
    -- lists the empty ones too: «صُرف صفر على فرح» is an answer a treasurer
    -- wants and a member does not.
    'byCategory', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'category', g.cat,
               'total',    g.amt::numeric(12,2)::text,
               'count',    g.n)
             ORDER BY g.amt DESC, g.cat)
        FROM (SELECT l.category::text AS cat,
                     sum(l.amount)    AS amt,
                     count(*)         AS n
                FROM live l
               GROUP BY l.category) g), '[]'::jsonb),
    -- ── THE SAME LEDGER «أسلافي» KEEPS, for the same reasons ─────────────
    -- OLDEST FIRST, each line carrying the total so far. «400 فطور رمضان,
    -- then months later 100 عزاء» reads 400 then 500 — which is what a
    -- ledger is, and what «كم أنفقت الجمعية على الجميع» actually asks.
    --
    -- ⚠ THE WINDOW IS THE POINT, not a convenience. Money is text end to end
    --   in this app precisely so nothing accumulates it in Dart; a screen
    --   that added twelve vouchers to draw a column would put the
    --   association’s spending on binary floating point.
    --
    -- ⚠ AND THE FRAME IS COMPUTED OVER EVERY ROW, cancelled ones included,
    --   while the SUM excludes them with FILTER. That is not the same as a
    --   WHERE: WHERE would drop the reversed line from the list, and rule 9
    --   says a reversal is part of the record. FILTER keeps the line and
    --   leaves its running total identical to the one above it — which is
    --   exactly what a ledger shows for an entry that was reversed.
    --
    --   coalesce because a FILTERed window over a frame holding no live row
    --   is NULL, not zero.
    'vouchers', coalesce(
      (SELECT jsonb_agg(
                to_jsonb(v) || jsonb_build_object(
                  'runningTotal', coalesce(r.run, 0)::numeric(12,2)::text)
                ORDER BY r.ord)
         FROM (
           SELECT d.id,
                  row_number() OVER (ORDER BY d.spent_at, d.id) AS ord,
                  sum(d.amount) FILTER (WHERE d.status <> 'ملغي')
                    OVER (ORDER BY d.spent_at, d.id
                          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                    AS run
             FROM public.disbursements d
            -- ⚠ THE COLLECTIVE ROWS, and the clause is `payee_adeel_id IS
            --   NULL` rather than `kind = جماعي`. The two are equivalent only
            --   because ck_disb_shape makes them so, and this guards against
            --   a NAME being read — so it is written against the column that
            --   holds the name.
            WHERE d.payee_adeel_id IS NULL
         ) r
         JOIN public.v_disbursements v ON v."id" = r.id),
      '[]'::jsonb)
  )
$fn$;

-- == Confirmation ===========================================================
-- Read-only. Every row must say true.
SELECT 'الدفتر يحمل الإجمالي المتراكم' AS "الفحص",
       coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%runningTotal%'
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'api_aid_others'),
                false) AS "النتيجة"
-- ⚠ AND IT IS STILL COLLECTIVE-ONLY. The lift could not have dropped this
--   without opening every member's aid to every other member, by name — and
--   the policy alone would not stop it, because the function is what the
--   portal calls.
UNION ALL SELECT 'وما زال جماعياً فقط',
       coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%payee_adeel_id IS NULL%'
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'api_aid_others'),
                false)
-- ⚠ AND A REVERSED VOUCHER IS STILL LISTED. FILTER keeps the line and leaves
--   the balance; WHERE would erase it from the record.
UNION ALL SELECT 'والملغى يبقى مسطوراً',
       coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%FILTER (WHERE%'
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'api_aid_others'),
                false)
UNION ALL SELECT 'ولم يتغيّر أي رقم مالي',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == The four guards ========================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
