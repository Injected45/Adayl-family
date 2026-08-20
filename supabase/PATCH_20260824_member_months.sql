-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-24.  حركة المشترك على اثني عشر شهراً.
--
--  WHAT THIS ADDS
--    One key on api_member_value: `months`, an array of twelve — the calendar
--    month, what he PAID in it, and what he RECEIVED in it. It is what the
--    chart at the foot of «الجدوى» is drawn from.
--
--  ⚠ THE SERVER SUMS; THE CLIENT ONLY DRAWS. Money is text end to end in this
--    project because Postgres numerics reach dart:convert as doubles. A chart
--    is the most tempting place to break that — «I only need it as a number to
--    scale a bar» — so the monthly totals are computed here and the client
--    receives twelve already-final figures.
--
--  ⚠ AND THE SPINE IS GENERATED. Twelve months always come back, including the
--    empty ones. Grouping the rows instead would return only the months he
--    paid in, and a chart of those has no time axis: three months of silence
--    would look exactly like three payments in a row.
--
--  ⚠ NOTHING ELSE CHANGES. CREATE OR REPLACE on a function that already
--    exists, so its ACL is kept and no lockdown sweep is needed. No row is
--    written, no policy is touched, and the eight keys it already returned
--    come back byte for byte.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.api_member_value(bigint)') IS NULL THEN
    RAISE EXCEPTION
      'لا توجد دالة الجدوى. طبّق supabase/PATCH_20260820b_aid_transparency.sql أولاً.';
  END IF;
END $prereq$;

-- ⚠ THE BODY IS THE INSTALLED ONE, LIFTED WHOLE, with one key appended. A
--   patch that retyped the rest would silently revert the scoping in its first
--   statement — the clause that stops one member asking about another.
CREATE OR REPLACE FUNCTION public.api_member_value(p_adeel_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $mv$
DECLARE
  v_me   bigint := public.my_adeel_id();
  v_role app_role := public.my_role();
  v_out  jsonb;
BEGIN
  IF v_role IS NULL AND v_me IS DISTINCT FROM p_adeel_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;
  IF v_role IS NULL AND v_me IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  SELECT jsonb_build_object(
    -- ── HIS SIDE ────────────────────────────────────────────────────────
    -- What he has actually PAID, not what he was billed: the question is
    -- what left his hand.
    'paid', (SELECT coalesce(sum(p.amount), 0)::numeric(12,2)::text
               FROM public.payments p
              WHERE p.adeel_id = p_adeel_id AND p.status <> 'ملغي'),
    'received', (SELECT coalesce(sum(d.amount), 0)::numeric(12,2)::text
                   FROM public.disbursements d
                  WHERE d.payee_adeel_id = p_adeel_id
                    AND d.status <> 'ملغي'),

    -- ── THE FUND ────────────────────────────────────────────────────────
    'collected', (SELECT coalesce(sum(c.amount), 0)::numeric(12,2)::text
                    FROM public.cash_movements c WHERE c.status <> 'ملغي'),
    -- Everything given to NAMED members. Collective spending (فطور رمضان) is
    -- excluded on purpose: this figure answers «how much of the fund comes
    -- back to a man», and a shared meal comes back to everyone at once.
    'toMembers', (SELECT coalesce(sum(d.amount), 0)::numeric(12,2)::text
                    FROM public.disbursements d
                   WHERE d.payee_adeel_id IS NOT NULL
                     AND d.status <> 'ملغي'),

    -- ── THE STATISTICS THAT ANSWER «ما الجدوى» ──────────────────────────
    -- How many men the fund has actually stood behind, out of how many pay
    -- into it. One ratio, no prose.
    'helped', (SELECT count(DISTINCT d.payee_adeel_id)
                 FROM public.disbursements d
                WHERE d.payee_adeel_id IS NOT NULL AND d.status <> 'ملغي'),
    'members', (SELECT count(*) FROM public.adeels),
    -- ⚠ THE INSURANCE FIGURE, and the most useful number on the screen: the
    --   largest single voucher the association has ever written to one man.
    --   «هذا ما تقف خلفه الجمعية إن نزلت بك نازلة» is what a member is
    --   actually buying, and no average says it.
    'largest', (SELECT coalesce(max(d.amount), 0)::numeric(12,2)::text
                  FROM public.disbursements d
                 WHERE d.payee_adeel_id IS NOT NULL AND d.status <> 'ملغي'),

    -- ── حركته على اثني عشر شهراً ─────────────────────────────────────
    -- What he paid and what he was given, month by month, for the chart at
    -- the foot of «الجدوى».
    --
    -- ⚠ THE SPINE IS GENERATED, NOT DERIVED FROM THE ROWS. Grouping the
    --   payments alone would return only the months he happened to pay in,
    --   and a chart drawn from that has no time axis — it has a list of
    --   events evenly spaced, so three months of silence look identical to
    --   three consecutive payments. generate_series gives every month a
    --   column, and an empty one is the fact worth seeing.
    --
    -- ⚠ AND EVERY FIGURE IS SUMMED HERE, IN TEXT. The client draws bars from
    --   these and never adds them: money is text end to end in this app, and
    --   a Dart loop totalling a year of receipts would put the association’s
    --   figures on binary floating point.
    'months', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'period',   to_char(m.month, 'YYYY-MM'),
               'paid',     m.paid::numeric(12,2)::text,
               'received', m.received::numeric(12,2)::text)
             ORDER BY m.month)
        FROM (
          SELECT s.month,
                 coalesce((SELECT sum(p.amount) FROM public.payments p
                            WHERE p.adeel_id = p_adeel_id
                              AND p.status <> 'ملغي'
                              AND date_trunc('month',
                                    p.paid_at AT TIME ZONE 'Africa/Tripoli')
                                  = s.month), 0) AS paid,
                 coalesce((SELECT sum(d.amount) FROM public.disbursements d
                            WHERE d.payee_adeel_id = p_adeel_id
                              AND d.status <> 'ملغي'
                              AND date_trunc('month',
                                    d.spent_at AT TIME ZONE 'Africa/Tripoli')
                                  = s.month), 0) AS received
            -- ⚠ BUCKETED BY TRIPOLI’S MONTH, not by UTC’s. A receipt taken
            --   at 23:30 on the last night of a month is stamped in UTC two
            --   hours earlier — still that month there, but the NEXT month
            --   has already begun in Libya. The whole app renders in
            --   Africa/Tripoli; a chart bucketed differently would disagree
            --   with the statement printed above it.
            FROM generate_series(
                   date_trunc('month', now() AT TIME ZONE 'Africa/Tripoli')
                     - interval '11 months',
                   date_trunc('month', now() AT TIME ZONE 'Africa/Tripoli'),
                   interval '1 month') AS s(month)
        ) m), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END $mv$;

-- == Confirmation ===========================================================
-- Read-only. Every row must say true.
SELECT 'الجدوى تُعيد سلسلة الأشهر' AS "الفحص",
       coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%generate_series%'
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'api_member_value'),
                false) AS "النتيجة"
-- ⚠ AND IT IS STILL SCOPED. The first statement of the body refuses a member
--   asking about anyone but himself; a lift that lost it would hand every
--   man every other man's figures, and the function is SECURITY DEFINER so
--   no policy would catch it.
UNION ALL SELECT 'وما زالت مقصورة على صاحبها',
       coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%FORBIDDEN%'
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'api_member_value'),
                false)
UNION ALL SELECT 'وما زالت SECURITY DEFINER',
       coalesce((SELECT p.prosecdef
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'api_member_value'),
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
