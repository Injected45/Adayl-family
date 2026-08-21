-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (f).  «الجدوى» يصير خطّين تراكميّين.
--
--  WHAT CHANGES
--    api_member_value adds `paidTotal` and `receivedTotal` to each month —
--    the running total to that point, in text, from a window function.
--
--  ⚠ WHY THE SERVER AND NOT THE CHART. The association rejected the old
--    graphic in the right words: «الخطان يعبّران عن إجمالي قيمة وفي الأسفل
--    أشهر … اجعل الأسلاف كرسم بياني لا كمؤشر عمودي متجمد». The fix is two
--    CUMULATIVE lines, where a month of aid becomes a step that persists
--    instead of a lone spike, and the vertical gap between the lines IS the
--    answer «الجدوى» exists to give.
--
--    That needs a running total per month. Computing it in Dart was written,
--    and `test/member_months_chart_test.dart` refused it by reading the
--    source — correctly: money is text end to end in this project precisely
--    so nothing accumulates it on binary floating point. `api_adeel_aid`
--    already returns its ledger column the same way, so this is the existing
--    rule applied rather than a new one.
--
--  ⚠ NOTHING ELSE MOVES. CREATE OR REPLACE on a function that already
--    exists, so its ACL is kept and no lockdown sweep is needed. No row is
--    written, no policy is touched, and every field the screen already reads
--    comes back byte for byte — the two new keys are additions.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.api_member_value(bigint)') IS NULL THEN
    RAISE EXCEPTION
      'الدالة api_member_value غير موجودة. طبّق supabase/PATCH_20260820b_aid_transparency.sql أولاً.';
  END IF;
END
$prereq$;


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
               'period',        to_char(m.month, 'YYYY-MM'),
               'paid',          m.paid::numeric(12,2)::text,
               'received',      m.received::numeric(12,2)::text,
               -- ── التراكم، من الخادم لا من التطبيق ──────────────────
               -- ⚠ THE CHART NEEDS RUNNING TOTALS AND MUST NOT COMPUTE
               --   THEM. «الجدوى» draws two cumulative lines and reads
               --   the answer off the GAP between them, which means a
               --   running total per month — and a Dart loop adding a
               --   year of receipts is the app doing arithmetic on
               --   money, which is the one thing the text-money rule
               --   forbids. test/member_months_chart_test.dart enforces
               --   it by reading the source, and it caught exactly this.
               --
               -- ⚠ SAME SHAPE api_adeel_aid ALREADY USES for its ledger
               --   column: a window function over the ordered months, so
               --   there is one way this project accumulates money and it
               --   is in Postgres.
               'paidTotal',
               (sum(m.paid) OVER (ORDER BY m.month))::numeric(12,2)::text,
               'receivedTotal',
               (sum(m.received) OVER (ORDER BY m.month))::numeric(12,2)::text)
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


-- ── الحُرّاس ────────────────────────────────────────────────────────────────
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
