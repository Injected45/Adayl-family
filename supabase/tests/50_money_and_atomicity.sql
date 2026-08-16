-- 50_money_and_atomicity.sql — money survives the round trip, and a failed
-- collection leaves nothing behind.
--
-- ⚠ THIS FILE WAS A BYTE-FOR-BYTE COPY OF 45_adeel_portal.sql FROM THE FIRST
-- COMMIT UNTIL 2026-08-16. The suite ran the portal group twice and called the
-- second run "money precision + atomicity". EXPECTED_CHECKS was then set to the
-- total that broken suite produced (93+86+37+37+5+37 = 295), so the count guard
-- — the one mechanism designed to notice a check that does not exist — was
-- reverse-engineered from the duplication and validated it instead.
--
-- WHAT 30_rules.sql ALREADY PROVES, and is deliberately not repeated here:
-- rule 7's FIFO order and its refusals, rule 8's one-cash-movement, rule 9's
-- reversal and preservation, rule 11's ledger identity, rules 3/4/5/15. Those
-- are the money RULES and they are covered. What had no test anywhere is the
-- money REPRESENTATION and what happens when a collection dies halfway.
--
-- ── The invariant this file exists for ──────────────────────────────────────
-- "Money is text end to end." Postgres serialises `numeric` as a bare JSON
-- number and dart:convert decodes a bare JSON number to `double`. Putting a
-- treasury on binary floating point is the bug the casts prevent — every view
-- casts amounts to text, every RPC returns them as text, and every amount the
-- app sends is a String.
--
-- Nothing in SQL asserted any of that. app/test/supabase_contract_test.dart
-- parses captured wire JSON, so it only bites if someone re-runs
-- extract_fixtures.sh after the regression — which is the wrong order. A cast
-- dropped from a view would have shipped.
--
-- ── The fixture is this file's own ──────────────────────────────────────────
-- 30_rules and 40_rls close periods, cancel payments, suspend and reactivate
-- عدايل. Reusing what they leave behind is how 45_adeel_portal's "he is not on
-- the staff ladder" once failed while the code was correct. Two عدايل are
-- created here with periods (2027-04 … 2027-06) that no other file touches.
-- 70_purge erases everything at the end, so nothing is cleaned up.

SET client_min_messages = warning;

-- ═════════════════════════════════════════════════════════════════════════════
--  Fixture — as postgres, so RLS is bypassed and the arithmetic is exact.
-- ═════════════════════════════════════════════════════════════════════════════
-- عديل بلا سجل gets no receivable and no payment, ever. He is what proves an
-- EMPTY bucket serialises as '0.00' and not as the integer literal '0' that
-- coalesce(sum(x), 0) falls back to.
INSERT INTO public.adeels (full_name, dob, registered_at, status) VALUES
  ('عديل الدقة',   '1980-05-05', '2026-01-01', 'نشط'),
  ('عديل بلا سجل', '1990-06-06', '2026-01-01', 'نشط');

CREATE TEMP TABLE mfix AS
SELECT (SELECT id FROM public.adeels WHERE full_name = 'عديل الدقة'
          ORDER BY id DESC LIMIT 1) AS payer,
       (SELECT id FROM public.adeels WHERE full_name = 'عديل بلا سجل'
          ORDER BY id DESC LIMIT 1) AS empty_;

-- Granted HERE, not where it is first read. `authenticated` owns nothing, and
-- the probe statements below run under SET ROLE — a grant placed after the first
-- of them fails the whole group on "permission denied for table mfix".
GRANT SELECT ON mfix TO authenticated;

-- 60.00 owed, in three equal months, so FIFO has somewhere to spill to.
INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name, total)
SELECT m.payer, p.period, p.ends, 'عديل الدقة', 20.00
  FROM mfix m,
       (VALUES ('2027-04', DATE '2027-04-30'),
               ('2027-05', DATE '2027-05-31'),
               ('2027-06', DATE '2027-06-30')) AS p(period, ends);

-- ═════════════════════════════════════════════════════════════════════════════
--  WIRE — every amount leaves the database as a JSON string
--
--  jsonb_typeof is the assertion that matters. A numeric column reaches the app
--  as `"total": 20.00` and a cast one as `"total": "20.00"`; both look identical
--  in a psql result grid and only the first turns into a double.
-- ═════════════════════════════════════════════════════════════════════════════

-- The structural form, and the most durable check in this file: it holds for a
-- view added next year by someone who never read this comment. information_schema
-- reports the view's OWN column types, so a forgotten ::text shows up as numeric
-- here whether or not any test happens to select that column.
SELECT probe.eq('wire', 'no v_* view exposes a bare numeric column to the client',
  $sql$ SELECT coalesce(string_agg(table_name || '.' || column_name, ', '
                                   ORDER BY table_name, column_name), 'none')
          FROM information_schema.columns
         WHERE table_schema = 'public'
           AND table_name LIKE 'v\_%'
           AND data_type IN ('numeric', 'double precision', 'real') $sql$,
  'none');

SELECT probe.eq('wire', 'v_receivables.total is a string, not a number',
  $sql$ SELECT jsonb_typeof(to_jsonb(v) -> 'total') FROM public.v_receivables v
         WHERE v."adeelId" = (SELECT payer FROM mfix) LIMIT 1 $sql$, 'string');

SELECT probe.eq('wire', 'v_adeels.debt is a string',
  $sql$ SELECT jsonb_typeof(to_jsonb(v) -> 'debt') FROM public.v_adeels v
         WHERE v."id" = (SELECT payer FROM mfix) $sql$, 'string');

SELECT probe.eq('wire', 'v_cash_summary.total is a string',
  $sql$ SELECT jsonb_typeof(to_jsonb(v) -> 'total') FROM public.v_cash_summary v $sql$,
  'string');

SELECT probe.eq('wire', 'api_dashboard reports debt as a string',
  $sql$ SELECT jsonb_typeof(public.api_dashboard() -> 'stats' -> 'debt') $sql$,
  'string');

SELECT probe.eq('wire', 'api_dashboard reports collected as a string',
  $sql$ SELECT jsonb_typeof(public.api_dashboard() -> 'stats' -> 'collected') $sql$,
  'string');

SELECT probe.eq('wire', 'api_financial_report reports collected as a string',
  $sql$ SELECT jsonb_typeof(
          public.api_financial_report('2026-01-01', '2027-12-31') -> 'collected') $sql$,
  'string');

SELECT probe.eq('wire', 'api_receivables summarises issued as a string',
  $sql$ SELECT jsonb_typeof(public.api_receivables(NULL) -> 'summary' -> 'issued') $sql$,
  'string');

SELECT probe.eq('wire', 'api_adeel_detail reports the KPI debt as a string',
  $sql$ SELECT jsonb_typeof(
          public.api_adeel_detail((SELECT payer FROM mfix)) -> 'kpis' -> 'debt') $sql$,
  'string');

SELECT probe.eq('wire', 'api_adeel_statement closes with a string balance',
  $sql$ SELECT jsonb_typeof(
          public.api_adeel_statement((SELECT payer FROM mfix)) -> 'closingBalance') $sql$,
  'string');

SELECT probe.eq('wire', 'the statement debits are strings too',
  $sql$ SELECT jsonb_typeof(
          public.api_adeel_statement((SELECT payer FROM mfix))
            -> 'movements' -> 0 -> 'debit') $sql$,
  'string');

-- ═════════════════════════════════════════════════════════════════════════════
--  FORMAT — two decimals, always, including an empty bucket
--
--  `coalesce(sum(x), 0)` falls back to an INTEGER literal, so a bucket with no
--  rows serialises as "0" while every other amount on the same screen is "0.00".
--  The contract test caught that once on the treasury's transfer total; the fix
--  was ::numeric(12,2) before ::text, and nothing asserted it afterwards.
-- ═════════════════════════════════════════════════════════════════════════════

SELECT probe.eq('format', 'an عديل with no ledger at all reports 0.00, not 0',
  $sql$ SELECT v."debt" || '/' || v."paid" || '/' || v."issued"
          FROM public.v_adeels v WHERE v."id" = (SELECT empty_ FROM mfix) $sql$,
  '0.00/0.00/0.00');

-- Compared against the CURRENT fee rather than a literal: 30_rules sets the fee
-- to zero and back to prove rule 3, so a literal here would assert what that
-- file happened to leave behind rather than the formatting this check is about.
SELECT probe.eq('format', 'monthlyExpected is the live fee, at two decimals',
  $sql$ SELECT (v."monthlyExpected" ~ '^[0-9]+\.[0-9]{2}$'
            AND v."monthlyExpected" = s.member_fee::text)::text
          FROM public.v_adeels v, public.association_settings s
         WHERE v."id" = (SELECT empty_ FROM mfix) AND s.id = 1 $sql$, 'true');

SELECT probe.eq('format', 'every treasury bucket carries exactly two decimals',
  $sql$ SELECT (v."total"    ~ '^-?[0-9]+\.[0-9]{2}$'
            AND v."cash"     ~ '^-?[0-9]+\.[0-9]{2}$'
            AND v."transfer" ~ '^-?[0-9]+\.[0-9]{2}$'
            AND v."today"    ~ '^-?[0-9]+\.[0-9]{2}$'
            AND v."month"    ~ '^-?[0-9]+\.[0-9]{2}$'
            AND v."year"     ~ '^-?[0-9]+\.[0-9]{2}$')::text
          FROM public.v_cash_summary v $sql$, 'true');

SELECT probe.eq('format', 'every dashboard money stat carries two decimals',
  $sql$ SELECT bool_and(public.api_dashboard() -> 'stats' ->> k
                          ~ '^-?[0-9]+\.[0-9]{2}$')::text
          FROM unnest(ARRAY['debt','collected','cash','transfer']) k $sql$,
  'true');

SELECT probe.eq('format', 'a receivable renders total, paid and balance alike',
  $sql$ SELECT bool_and(r."total"   ~ '^-?[0-9]+\.[0-9]{2}$'
                    AND r."paid"    ~ '^-?[0-9]+\.[0-9]{2}$'
                    AND r."balance" ~ '^-?[0-9]+\.[0-9]{2}$')::text
          FROM public.v_receivables r
         WHERE r."adeelId" = (SELECT payer FROM mfix) $sql$, 'true');

-- ═════════════════════════════════════════════════════════════════════════════
--  ROUNDING — the client can post a third decimal, and must not be able to
--  put one into the ledger.
--
--  register_payment rounds to minor units UP FRONT, before the zero check and
--  before the outstanding check. A third decimal reaching an allocation is not a
--  display problem: the allocations stop summing to the payment, and rule 11's
--  identity drifts by fractions nobody can see.
-- ═════════════════════════════════════════════════════════════════════════════
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');  -- treasurer

SELECT probe.raises('round', 'a third-decimal payment that rounds to zero is refused',
  $sql$ SELECT public.register_payment((SELECT payer FROM mfix), 0.004, 'نقداً') $sql$,
  'RUL07');

SELECT probe.succeeds('round', 'a third-decimal payment above zero is accepted',
  $sql$ SELECT public.register_payment((SELECT payer FROM mfix), 10.006, 'نقداً') $sql$);

RESET ROLE;

SELECT probe.eq('round', '...and 10.006 was stored as exactly 10.01',
  $sql$ SELECT amount::text FROM public.payments
         WHERE adeel_id = (SELECT payer FROM mfix) ORDER BY id DESC LIMIT 1 $sql$,
  '10.01');

SELECT probe.eq('round', 'the allocation carries the rounded amount, not the raw one',
  $sql$ SELECT a.amount::text FROM public.payment_allocations a
          JOIN public.payments p ON p.id = a.payment_id
         WHERE p.adeel_id = (SELECT payer FROM mfix)
         ORDER BY a.id DESC LIMIT 1 $sql$, '10.01');

SELECT probe.eq('round', 'the oldest period absorbed it and shows 9.99 left',
  $sql$ SELECT balance::text FROM public.receivables
         WHERE adeel_id = (SELECT payer FROM mfix) AND period = '2027-04' $sql$,
  '9.99');

-- Ledger-wide, not just this fixture: numeric(12,2) rounds on storage, so a
-- third decimal can only survive if some column somewhere is wider.
SELECT probe.eq('round', 'no allocation anywhere carries more than two decimals',
  $sql$ SELECT count(*)::text FROM public.payment_allocations
         WHERE scale(amount) > 2 $sql$, '0');

SELECT probe.eq('round', 'no payment anywhere carries more than two decimals',
  $sql$ SELECT count(*)::text FROM public.payments WHERE scale(amount) > 2 $sql$, '0');

-- ═════════════════════════════════════════════════════════════════════════════
--  EXACTNESS — rule 7 bites at the cent, not near it
-- ═════════════════════════════════════════════════════════════════════════════

SELECT probe.eq('exact', 'he now owes exactly 49.99',
  $sql$ SELECT coalesce(sum(balance), 0)::text FROM public.receivables
         WHERE adeel_id = (SELECT payer FROM mfix) AND status <> 'ملغي' $sql$,
  '49.99');

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');

SELECT probe.raises('exact', 'one cent over the balance is refused',
  $sql$ SELECT public.register_payment((SELECT payer FROM mfix), 50.00, 'نقداً') $sql$,
  'RUL07');

SELECT probe.succeeds('exact', 'the balance to the cent is accepted',
  $sql$ SELECT public.register_payment((SELECT payer FROM mfix), 49.99,
                                       'تحويل مصرفي') $sql$);

SELECT probe.raises('exact', 'and nothing more can be collected from him',
  $sql$ SELECT public.register_payment((SELECT payer FROM mfix), 0.01, 'نقداً') $sql$,
  'RUL07');

RESET ROLE;

SELECT probe.eq('exact', 'all three months settled to exactly zero',
  $sql$ SELECT coalesce(sum(balance), 0)::text || '/' || count(*)::text
          FROM public.receivables
         WHERE adeel_id = (SELECT payer FROM mfix)
           AND status = 'مسدد بالكامل' $sql$, '0.00/3');

-- ═════════════════════════════════════════════════════════════════════════════
--  ATOMICITY — a collection that dies at its LAST step leaves nothing standing
--
--  register_payment writes a payment, N allocations, N receivable updates and
--  THEN the cash movement. The trigger below makes that final insert fail, so
--  the failure lands after every other write has already happened — which is the
--  only ordering that can distinguish "one transaction" from "four statements".
--
--  WHAT IS AND IS NOT BEING PROVEN. Postgres rolls a failed statement back on
--  its own, and probe.raises() wraps the call in a subtransaction besides, so
--  the rollback itself is not this file's discovery. What IS load-bearing is
--  that the error PROPAGATES: if register_payment ever grew an
--  `EXCEPTION WHEN OTHERS` around the cash movement — the obvious way to make a
--  retry "more robust" — the call would return a receipt, the payment and its
--  allocations would commit, and the treasury would silently be short by exactly
--  that amount. Rule 8's uq_cash_payment cannot catch that: the row is missing,
--  not duplicated. Under that regression the raises() below reports SUCCEEDED
--  and the three counts after it all move.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TEMP TABLE mbefore AS
SELECT (SELECT count(*) FROM public.payments)            AS pays,
       (SELECT count(*) FROM public.payment_allocations) AS allocs,
       (SELECT count(*) FROM public.cash_movements)      AS cash,
       (SELECT coalesce(sum(paid), 0) FROM public.receivables
         WHERE adeel_id = (SELECT payer FROM mfix))      AS paid;
GRANT SELECT ON mbefore TO authenticated;
GRANT SELECT ON mfix    TO authenticated;

CREATE OR REPLACE FUNCTION probe.boom() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'INJECTED: the treasury write failed' USING ERRCODE = 'RUL99';
END $$;

CREATE TRIGGER trg_probe_boom AFTER INSERT ON public.cash_movements
  FOR EACH ROW EXECUTE FUNCTION probe.boom();

-- Free a balance to collect against, so the call reaches the cash movement
-- rather than being refused by rule 7 before it gets there.
UPDATE public.receivables SET paid = paid - 5.00
 WHERE adeel_id = (SELECT payer FROM mfix) AND period = '2027-06';

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');

SELECT probe.raises('atomic',
  'a failure at the treasury write is not swallowed by register_payment',
  $sql$ SELECT public.register_payment((SELECT payer FROM mfix), 5.00, 'نقداً') $sql$,
  'RUL99');

RESET ROLE;

-- Armed for exactly one call. Dropped immediately so a failure below cannot
-- leave it in place for 60_concurrency, which would fail every payment it makes
-- and look like a locking bug.
DROP TRIGGER trg_probe_boom ON public.cash_movements;

SELECT probe.eq('atomic', 'the failed collection left no payment row',
  $sql$ SELECT (count(*) = (SELECT pays FROM mbefore))::text
          FROM public.payments $sql$, 'true');

SELECT probe.eq('atomic', '...no allocation row',
  $sql$ SELECT (count(*) = (SELECT allocs FROM mbefore))::text
          FROM public.payment_allocations $sql$, 'true');

SELECT probe.eq('atomic', '...and no cash movement',
  $sql$ SELECT (count(*) = (SELECT cash FROM mbefore))::text
          FROM public.cash_movements $sql$, 'true');

-- The receivable update happens BEFORE the cash movement, so this is the one
-- that would still be standing if the writes were separate calls.
SELECT probe.eq('atomic', 'the receivable it had already credited was rolled back',
  $sql$ SELECT (coalesce(sum(paid), 0) = (SELECT paid FROM mbefore) - 5.00)::text
          FROM public.receivables WHERE adeel_id = (SELECT payer FROM mfix) $sql$,
  'true');

-- Put the 5.00 back so the ledger identity below is measured against an
-- untampered fixture.
UPDATE public.receivables SET paid = paid + 5.00
 WHERE adeel_id = (SELECT payer FROM mfix) AND period = '2027-06';

-- ═════════════════════════════════════════════════════════════════════════════
--  REVERSAL — cancellation restores the balance to the cent, and the treasury
--  with it
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TEMP TABLE mcash AS
SELECT "total"::numeric AS before_ FROM public.v_cash_summary;

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager

SELECT probe.succeeds('reversal', 'the 49.99 transfer is cancelled', $sql$
  SELECT public.cancel_payment(
    (SELECT id FROM public.payments
      WHERE adeel_id = (SELECT payer FROM mfix) AND amount = 49.99
        AND status <> 'ملغي' ORDER BY id DESC LIMIT 1),
    'اختبار الدقة')
$sql$);

RESET ROLE;

SELECT probe.eq('reversal', 'the balance came back to exactly 49.99',
  $sql$ SELECT coalesce(sum(balance), 0)::text FROM public.receivables
         WHERE adeel_id = (SELECT payer FROM mfix) AND status <> 'ملغي' $sql$,
  '49.99');

SELECT probe.eq('reversal', 'the 10.01 already collected was NOT reversed with it',
  $sql$ SELECT coalesce(sum(paid), 0)::text FROM public.receivables
         WHERE adeel_id = (SELECT payer FROM mfix) $sql$, '10.01');

SELECT probe.eq('reversal', 'the treasury dropped by exactly the cancelled amount',
  $sql$ SELECT (("total"::numeric) = (SELECT before_ FROM mcash) - 49.99)::text
          FROM public.v_cash_summary $sql$, 'true');

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');

SELECT probe.succeeds('reversal', 'the freed balance is collectable again',
  $sql$ SELECT public.register_payment((SELECT payer FROM mfix), 49.99, 'نقداً') $sql$);

RESET ROLE;

-- ═════════════════════════════════════════════════════════════════════════════
--  IDENTITY — the two ties that must hold over the WHOLE ledger, not one عديل
--
--  30_rules asserts issued - collected = outstanding in aggregate, and that
--  every allocation points at a live receivable. Neither of those catches a
--  per-row drift that nets out: an allocation credited to the wrong receivable
--  leaves both sums correct. These are the row-level forms.
-- ═════════════════════════════════════════════════════════════════════════════

SELECT probe.eq('identity',
  'every approved payment equals the sum of its own allocations',
  $sql$ SELECT count(*)::text FROM public.payments p
         WHERE p.status <> 'ملغي'
           AND p.amount <> (SELECT coalesce(sum(a.amount), 0)
                              FROM public.payment_allocations a
                             WHERE a.payment_id = p.id) $sql$, '0');

SELECT probe.eq('identity',
  'every receivable paid equals what live payments allocated to it',
  $sql$ SELECT count(*)::text FROM public.receivables r
         WHERE r.paid <> (SELECT coalesce(sum(a.amount), 0)
                            FROM public.payment_allocations a
                            JOIN public.payments p ON p.id = a.payment_id
                           WHERE a.receivable_id = r.id
                             AND p.status <> 'ملغي') $sql$, '0');

SELECT probe.eq('identity', 'no receivable is over-collected or negatively paid',
  $sql$ SELECT count(*)::text FROM public.receivables
         WHERE paid < 0 OR paid > total $sql$, '0');

SELECT probe.eq('identity',
  'every approved payment has exactly one live cash movement (rule 8)',
  $sql$ SELECT count(*)::text FROM public.payments p
         WHERE p.status <> 'ملغي'
           AND (SELECT count(*) FROM public.cash_movements c
                 WHERE c.payment_id = p.id AND c.status <> 'ملغي') <> 1 $sql$,
  '0');
