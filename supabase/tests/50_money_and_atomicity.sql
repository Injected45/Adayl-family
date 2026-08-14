-- 50_money_and_atomicity.sql

-- ═════ Money precision on the wire ═══════════════════════════════════════════
-- PostgREST builds its response body with json_agg inside Postgres, so what
-- json_agg emits here IS the bytes the Flutter client receives. This is the check
-- that justifies every ::text cast in 20260811090700_views.sql.

SELECT probe.eq('money', 'a raw numeric column serialises as a bare JSON NUMBER',
  $sql$ SELECT (json_agg(t)::text ~ '"total":40\.00[,}\]]')::text
          FROM (SELECT total FROM public.receivables
                 WHERE family_id = 1 AND period = '2026-03') t $sql$, 'true');

SELECT probe.eq('money', '...which is exactly what must never reach Dart',
  $sql$ SELECT (json_agg(t)::text NOT LIKE '%"total":"%')::text
          FROM (SELECT total FROM public.receivables
                 WHERE family_id = 1 AND period = '2026-03') t $sql$, 'true');

SELECT probe.eq('money', 'the view serialises the same value as a QUOTED STRING',
  $sql$ SELECT (json_agg(t)::text LIKE '%"total":"40.00"%')::text
          FROM (SELECT "total" FROM public.v_receivables
                 WHERE "familyId" = 1 AND "period" = '2026-03') t $sql$, 'true');

-- Round-trip at the top of DECIMAL(12,2)'s range, where a double starts losing
-- integers. 12345678.91 survives as text; the point is that it survives EXACTLY,
-- to the last minor unit, not approximately.
-- Its own family: loading a ten-billion balance onto family 1 would distort the
-- FIFO and atomicity probes further down, which depend on its outstanding total.
SELECT probe.succeeds('money', 'store a large amount', $sql$
  WITH f AS (INSERT INTO public.families DEFAULT VALUES RETURNING id)
  INSERT INTO public.receivables (family_id, period, period_end, father_fee,
    son_fee, father_name, eligibility_age_snapshot, warning_months_snapshot, total)
  SELECT f.id, '2029-12', '2029-12-31', 20, 10, 'probe', 16, 3, 9999999999.91
    FROM f
$sql$);
SELECT probe.eq('money', 'it round-trips to the exact minor unit',
  $sql$ SELECT total::text FROM public.receivables WHERE period = '2029-12' $sql$,
  '9999999999.91');
SELECT probe.eq('money', 'and reaches the client as a string, not a float',
  $sql$ SELECT (json_agg(t)::text LIKE '%"total":"9999999999.91"%')::text
          FROM (SELECT "total" FROM public.v_receivables WHERE "period" = '2029-12') t $sql$,
  'true');
-- Why the cast matters, stated accurately. A single round-trip through float8
-- does NOT corrupt 9999999999.91 — it has 12 significant digits and float8 holds
-- ~15, so it prints back identically. The first draft of this probe asserted
-- otherwise and failed, correctly.
--
-- The hazard is ARITHMETIC, and it is what Dart would be doing to these values
-- once they arrive as doubles: accumulate a hundred instalments and the total no
-- longer matches the ledger.
SELECT probe.eq('money', 'a float8 round-trip alone does NOT lose this value',
  $sql$ SELECT (9999999999.91::numeric::float8::text = '9999999999.91')::text $sql$,
  'true');
SELECT probe.eq('money', 'but float8 ACCUMULATION drifts where numeric does not',
  $sql$ SELECT ((SELECT sum(0.07::float8)  FROM generate_series(1,100))::text
             <> (SELECT sum(0.07::numeric) FROM generate_series(1,100))::text)::text $sql$,
  'true');
SELECT probe.eq('money', 'numeric accumulation is exact to the minor unit',
  $sql$ SELECT (SELECT sum(0.07::numeric) FROM generate_series(1,100))::text $sql$,
  '7.00');

-- A third decimal must not survive into an allocation.
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');
SET ROLE authenticated;
SELECT probe.succeeds('money', 'a sub-cent payment is rounded, not stored raw',
  'SELECT public.register_payment(1, 10.004, ''نقداً'')');
RESET ROLE;
SELECT probe.eq('money', 'the stored payment is exactly 10.00',
  $sql$ SELECT amount::text FROM public.payments ORDER BY id DESC LIMIT 1 $sql$, '10.00');
SELECT probe.eq('money', 'no allocation carries more than 2 decimals',
  $sql$ SELECT count(*)::text FROM public.payment_allocations
         WHERE amount <> round(amount, 2) $sql$, '0');

-- ═════ Atomicity ═════════════════════════════════════════════════════════════
-- register_payment writes a payment, N allocations, N receivable updates and a
-- cash movement. If any part fails the whole call must vanish. Provoked by
-- letting the FIFO loop run and then failing on the final constraint.

CREATE OR REPLACE FUNCTION probe.snapshot() RETURNS text
LANGUAGE sql AS $$
  SELECT format('%s|%s|%s|%s|%s',
    (SELECT count(*) FROM public.payments),
    (SELECT count(*) FROM public.payment_allocations),
    (SELECT count(*) FROM public.cash_movements),
    (SELECT coalesce(sum(paid),0)::text FROM public.receivables),
    (SELECT coalesce(sum(amount),0)::text FROM public.cash_movements))
$$;

CREATE OR REPLACE FUNCTION probe.atomicity_check() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE before_ text; after_ text; v_fid bigint; v_ok boolean;
BEGIN
  before_ := probe.snapshot();

  -- Over-pay by one minor unit. The outstanding check rejects it, but only after
  -- the payment row and the temp table already exist inside the call.
  SELECT id INTO v_fid FROM public.families ORDER BY id LIMIT 1;
  BEGIN
    PERFORM public.register_payment(
      v_fid,
      (SELECT coalesce(sum(balance),0) + 0.01 FROM public.receivables
        WHERE family_id = v_fid AND status <> 'ملغي'),
      'نقداً');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := (SQLSTATE = 'RUL07');
  END;

  after_ := probe.snapshot();
  PERFORM probe.note('atomicity', 'an over-payment is rejected', v_ok);
  PERFORM probe.note('atomicity',
    'a rejected payment leaves NOTHING behind (payments/allocs/cash/paid/total)',
    before_ = after_, format('before=%s after=%s', before_, after_));
END $$;

SELECT probe.become('00000000-0000-0000-0000-0000000000a3');
SET ROLE authenticated;
SELECT probe.atomicity_check();
RESET ROLE;

-- Mid-loop failure. The over-payment above is rejected BEFORE any allocation is
-- written, so on its own it does not prove the interesting case. This one fails
-- at the cash-movement insert — after the payment row, all the allocations and
-- all the receivable updates have already landed.
CREATE OR REPLACE FUNCTION probe._explode() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'simulated late failure' USING ERRCODE = 'RUL99';
END $$;

CREATE OR REPLACE FUNCTION probe.atomicity_midloop() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE before_ text; after_ text; v_ok boolean; v_fid bigint; v_amt numeric;
BEGIN
  SELECT r.family_id, sum(r.balance) INTO v_fid, v_amt
    FROM public.receivables r
   WHERE r.status <> 'ملغي' AND r.balance > 0
   GROUP BY r.family_id
   HAVING count(*) >= 2
   ORDER BY r.family_id
   LIMIT 1;

  IF v_fid IS NULL THEN
    PERFORM probe.note('atomicity', 'fixture has a family with 2+ open periods',
      false, 'no such family — the probe would prove nothing');
    RETURN;
  END IF;
  PERFORM probe.note('atomicity', 'fixture has a family with 2+ open periods', true);

  before_ := probe.snapshot();
  BEGIN
    PERFORM public.register_payment(v_fid, v_amt, 'نقداً');
    v_ok := false;
  EXCEPTION WHEN OTHERS THEN
    v_ok := (SQLSTATE = 'RUL99');
  END;
  after_ := probe.snapshot();

  PERFORM probe.note('atomicity',
    'a failure AFTER the allocations aborts the whole call', v_ok);
  PERFORM probe.note('atomicity',
    'the allocations and receivable balances rolled back with it',
    before_ = after_, format('before=%s after=%s', before_, after_));
END $$;

SELECT probe.become('00000000-0000-0000-0000-0000000000a3');
CREATE TRIGGER _late BEFORE INSERT ON public.cash_movements
  FOR EACH ROW EXECUTE FUNCTION probe._explode();
SELECT probe.atomicity_midloop();
DROP TRIGGER _late ON public.cash_movements;

-- And prove the trigger was really the thing failing, not a silent no-op: the
-- same payment must now succeed with it gone.
SELECT probe.succeeds('atomicity',
  'with the injected failure removed, the same payment succeeds',
  $sql$ SELECT public.register_payment(
          (SELECT r.family_id FROM public.receivables r
            WHERE r.status <> 'ملغي' AND r.balance > 0
            GROUP BY r.family_id HAVING count(*) >= 2
            ORDER BY r.family_id LIMIT 1),
          1, 'نقداً') $sql$);

-- ═════ Known residual exposure, pinned deliberately ══════════════════════════
-- The views cast money to text, but `authenticated` also holds SELECT on the base
-- tables — it has to, because security_invoker means the view reads them AS the
-- caller. So a client that queries `receivables` instead of `v_receivables` still
-- receives numeric, i.e. a float in Dart.
--
-- This is not closed by the schema. It is closed by the Flutter layer only ever
-- reading v_*, which has to be enforced there (a lint, like the existing
-- tool/rtl_lint.dart). Asserted here so the exposure is visible and cannot drift
-- into a surprise later. See docs/SUPABASE_MIGRATION_PLAN.md, residual risk R1.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a4');
SELECT probe.eq('residual', 'reading the BASE table still yields a bare JSON number',
  $sql$ SELECT (json_agg(t)::text LIKE '%"total":40.00%')::text
          FROM (SELECT total FROM public.receivables
                 WHERE family_id = 1 AND period = '2026-03') t $sql$, 'true');
SELECT probe.eq('residual', 'the view remains the only money-safe path',
  $sql$ SELECT (json_agg(t)::text LIKE '%"total":"40.00"%')::text
          FROM (SELECT "total" FROM public.v_receivables
                 WHERE "familyId" = 1 AND "period" = '2026-03') t $sql$, 'true');
RESET ROLE;
