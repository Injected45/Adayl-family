-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-22 (b).  إصلاح «الجدوى»: 42803.
--
--  ⚠ WHAT WAS WRONG. PATCH_20260821f put the running totals INSIDE the
--    jsonb_agg that builds each month:
--
--        jsonb_agg(jsonb_build_object(…, sum(m.paid) OVER (ORDER BY m.month)))
--
--    A window function cannot be nested inside an aggregate. Postgres
--    evaluates windows AFTER aggregation, so the reference is not resolvable
--    and it raises 42803 — «column must appear in the GROUP BY clause or be
--    used in an aggregate function», which names neither the window nor the
--    aggregate and reads like a completely different mistake.
--
--    The whole of «الجدوى» answered that error, on every screen that opened
--    it, from the moment 21f was applied.
--
--  ⚠ THE FIX IS THE ORDERING: the window runs in its own subquery FIRST, and
--    the aggregate wraps the rows it produced. Same arithmetic, same numbers,
--    and the running total is still the SERVER's — which is the rule 21f
--    existed to keep. Nothing moves to Dart.
--
--  ⚠ AND THIS IS WHY THE STATIC CHECKS DID NOT CATCH IT. There is no
--    PostgreSQL on the machine these patches are written on, so they are
--    verified by reading: every table, view, function and column in this file
--    resolves, and all of them did. A window nested in an aggregate is
--    perfectly well-formed by every name it uses — only EXECUTION rejects it.
--    A reference check is worth what it is worth, and this is its edge.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    No lockdown sweep: CREATE OR REPLACE on a function that already exists,
--    so its grants are kept.
-- ============================================================================

BEGIN;

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
               'period',        to_char(t.month, 'YYYY-MM'),
               'paid',          t.paid::numeric(12,2)::text,
               'received',      t.received::numeric(12,2)::text,
               'paidTotal',     t.paid_total::numeric(12,2)::text,
               'receivedTotal', t.received_total::numeric(12,2)::text)
             ORDER BY t.month)
        FROM (
          SELECT m.month, m.paid, m.received,
                 sum(m.paid)     OVER (ORDER BY m.month) AS paid_total,
                 sum(m.received) OVER (ORDER BY m.month) AS received_total
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
                FROM generate_series(
                       date_trunc('month', now() AT TIME ZONE 'Africa/Tripoli')
                         - interval '11 months',
                       date_trunc('month', now() AT TIME ZONE 'Africa/Tripoli'),
                       interval '1 month') AS s(month)
            ) m
        ) t), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END $mv$;


-- ⚠ AND IT IS RUN, not merely created: a syntax-clean function that raises on
--   its first call is what got us here. This asks it for عديل 1 and throws the
--   answer away — if the shape is still wrong, THIS transaction rolls back
--   rather than the man's screen breaking later.
DO $smoke$
DECLARE v jsonb;
BEGIN
  SELECT public.api_member_value(a.id) INTO v
    FROM public.adeels a ORDER BY a.id LIMIT 1;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_api_functions_callable();

COMMIT;
