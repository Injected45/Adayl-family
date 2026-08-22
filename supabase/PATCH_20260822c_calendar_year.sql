-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-22 (c).  «الجدوى» من يناير إلى ديسمبر.
--
--  WHAT CHANGES
--    api_member_value returns the twelve months of the CURRENT CALENDAR YEAR
--    instead of the last twelve rolling months. Nothing else moves: the same
--    keys, the same running totals, the same text.
--
--  ⚠ WHY, IN THE ASSOCIATION'S OWN WORDS: «اريدها من يناير الى ديسمبر». And
--    the rolling window had a real defect behind that preference — it ran
--    سبتمبر 2025 → أغسطس 2026, and the two ends of the axis read as two
--    ADJACENT months printed backwards beneath a heading that said twelve.
--
--    A calendar year needs no decoding: everybody knows where January is.
--
--  ⚠ AND THE EARLY-YEAR MONTHS ARE NOT AN EMPTY CHART. January to today is
--    what has happened; the rest of the year is what has not happened YET,
--    which is a different kind of zero and an honest one to show.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
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
                -- ── يناير إلى ديسمبر، لا آخر اثني عشر شهراً ──────────
                -- ⚠ A CALENDAR YEAR, at the association's request. The
                --   rolling window ran سبتمبر→أغسطس, and the two ends of
                --   it read as adjacent months in the wrong order under a
                --   heading that said twelve — «التناقض» was his word.
                --
                --   A calendar year needs no explaining: everybody
                --   already knows where January is and where December is,
                --   and the axis stops being something to decode.
                --
                -- ⚠ AND IT IS TRIPOLI'S YEAR. The whole app renders in
                --   Africa/Tripoli; a series bucketed in UTC would put a
                --   receipt taken at 23:30 on 31 December into the wrong
                --   year, on the one screen built to compare years.
                FROM generate_series(
                       date_trunc('year', now() AT TIME ZONE 'Africa/Tripoli'),
                       date_trunc('year', now() AT TIME ZONE 'Africa/Tripoli')
                         + interval '11 months',
                       interval '1 month') AS s(month)
            ) m
        ) t), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END $mv$;


-- ⚠ RUN, NOT MERELY CREATED. Two patches in a row were syntactically clean
--   and raised on their first call. This executes the months query itself —
--   the function's own guard refuses the SQL editor, which runs as `postgres`
--   with no auth.uid(), so the guard is what a smoke test through the
--   function would hit instead of the query.
DO $smoke$
DECLARE v jsonb;
BEGIN
  SELECT coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'period', to_char(t.month, 'YYYY-MM'),
             'paidTotal', t.paid_total::numeric(12,2)::text)
           ORDER BY t.month)
      FROM (
        SELECT m.month,
               sum(m.paid) OVER (ORDER BY m.month) AS paid_total
          FROM (
            SELECT s.month,
                   coalesce((SELECT sum(p.amount) FROM public.payments p
                              WHERE p.adeel_id = 1
                                AND p.status <> 'ملغي'
                                AND date_trunc('month',
                                      p.paid_at AT TIME ZONE 'Africa/Tripoli')
                                    = s.month), 0) AS paid
              FROM generate_series(
                     date_trunc('year', now() AT TIME ZONE 'Africa/Tripoli'),
                     date_trunc('year', now() AT TIME ZONE 'Africa/Tripoli')
                       + interval '11 months',
                     interval '1 month') AS s(month)
          ) m
      ) t), '[]'::jsonb) INTO v;

  IF jsonb_array_length(v) <> 12 THEN
    RAISE EXCEPTION 'السنة أعادت % شهراً بدل 12', jsonb_array_length(v);
  END IF;
  IF (v -> 0 ->> 'period') NOT LIKE '%-01' THEN
    RAISE EXCEPTION 'أول شهر ليس يناير: %', (v -> 0 ->> 'period');
  END IF;
  IF (v -> 11 ->> 'period') NOT LIKE '%-12' THEN
    RAISE EXCEPTION 'آخر شهر ليس ديسمبر: %', (v -> 11 ->> 'period');
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_api_functions_callable();

COMMIT;
