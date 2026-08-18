-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-18.  ماذا استلم المشترك من الجمعية.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  WHAT THIS DOES — two things, in one transaction
--
--    §1  A member may read HIS OWN vouchers. read_own_disbursements is scoped
--        on payee_adeel_id, so he sees what the association gave HIM and
--        nothing it gave anyone else — and a COLLECTIVE voucher, which is
--        attributed to nobody, matches no member at all.
--    §2  api_adeel_aid(bigint) — the page itself: a lifetime total, a breakdown
--        by occasion, a breakdown by year, and the vouchers beneath them.
--
--  ⚠ THE RULE THIS IS BUILT AROUND: الجمعية خيرية. Aid given to a man is NOT
--    deducted from what he owes. His statement stays a record of subscriptions
--    charged and subscriptions paid, and nothing else.
--
--    That is STRUCTURAL, not a matter of which screen shows what: a voucher
--    writes no receivable, no payment and no allocation, and
--    api_adeel_statement merges precisely those two tables. So aid cannot reach
--    the statement however this patch, or any screen, is written. What was
--    missing was not a safeguard — it was the ANSWER to "so where IS it
--    recorded", and §2 is that answer.
--
--  Nothing here is destructive. No DROP of any kind, no TRUNCATE, no DELETE,
--  no row touched, and no existing function's behaviour changed.
--  assert_signin_intact() runs before COMMIT.
--
--  ── WHY §1 WIDENS A POLICY THAT WAS DELIBERATELY NARROW ────────────────────
--  read_disbursements has always stopped at the staff boundary, and the comment
--  beside it said why: a row here records that a NAMED person received إعانة,
--  which in a family association is the most private fact the system holds. It
--  also said the missing piece was a decision for the association to take on
--  purpose. It has now been taken: a man may see his own.
--
--  The widening is a SEPARATE policy rather than a loosened clause on the
--  existing one, and that is not stylistic. Postgres ORs permissive policies,
--  so `payee_adeel_id = my_adeel_id()` adds exactly one row set and can be read
--  and reasoned about on its own — where editing read_disbursements would put
--  the staff rule and the member rule in one expression, and every future
--  change to either would have to be argued against both.
--
--  my_adeel_id() carries the one-device rule, so the wrong handset is refused
--  here by the same clause that empties the rest of his portal.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes. Safe to run twice.
--    Requires PATCH_20260817_device_lock.sql — check with WHICH_STATE.sql.
-- ============================================================================

BEGIN;

-- == 0. The prerequisite, stated rather than assumed ========================
-- This patch reads public.disbursements. On a project that never got the 17/08
-- patch the failure would otherwise be 42P01 half-way through, which is safe
-- (one transaction) but says nothing about what to do next.
DO $prereq$
BEGIN
  IF to_regclass('public.disbursements') IS NULL THEN
    RAISE EXCEPTION
      'PATCH_20260817_device_lock.sql has not been applied here: public.disbursements does not exist. Apply that first — see supabase/WHICH_STATE.sql.';
  END IF;
END $prereq$;

-- == 1. What the association gave HIM, and nothing it gave anybody else =====
-- Scoped on payee_adeel_id, so a COLLECTIVE voucher (payee_adeel_id IS NULL)
-- matches nobody — `NULL = my_adeel_id()` is NULL, never true. That is the
-- correct outcome and worth naming: فطور رمضان was spent on him as much as on
-- anyone, and it is still not a payment TO him. It appears in the totals he
-- already reads through api_association_finance() and nowhere else.
DO $ownpol$
BEGIN
  CREATE POLICY read_own_disbursements ON public.disbursements
    FOR SELECT TO authenticated USING (payee_adeel_id = public.my_adeel_id());
EXCEPTION WHEN duplicate_object THEN NULL;
END $ownpol$;

-- == 2. The page =============================================================
-- The counterpart of api_adeel_statement, and deliberately a SEPARATE call
-- rather than another key inside it. The statement answers "what does he owe
-- and what has he paid"; this answers "what has he received". Merging them
-- would put the two figures in one column and invite exactly the subtraction
-- that must never happen.
--
-- SECURITY INVOKER, so RLS decides: staff read any man's, and an عديل reads his
-- own through the policy above. An عديل passing somebody else's id gets a zero
-- total, empty lists and a NULL name — the same answer the register gives him
-- for a row that is not his, rather than a refusal that would confirm the id
-- exists.
--
-- ── Why the breakdowns are non-zero only, unlike v_expense_by_category ──────
-- That view lists every heading including the untouched ones, because
-- association-wide "nothing was spent on فرح this year" is itself an answer.
-- For ONE man it is not: he is not missing an answer because he was never given
-- anything for a wedding, and five zero rows would bury the two that matter.
--
-- CANCELLED vouchers are excluded from every total but LISTED, struck through,
-- exactly as a cancelled receipt is. Rule 9 requires them visible, never hidden.
CREATE OR REPLACE FUNCTION public.api_adeel_aid(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH live AS (
    SELECT d.* FROM public.disbursements d
     WHERE d.payee_adeel_id = p_adeel_id AND d.status <> 'ملغي'
  )
  SELECT jsonb_build_object(
    'adeelId',   p_adeel_id,
    'adeelCode', (SELECT a.adeel_code FROM public.adeels a WHERE a.id = p_adeel_id),
    'adeelName', (SELECT a.full_name  FROM public.adeels a WHERE a.id = p_adeel_id),
    'total', (SELECT coalesce(sum(l.amount), 0)::numeric(12,2)::text FROM live l),
    'count', (SELECT count(*) FROM live l),
    'firstAt', (SELECT to_char(min(l.spent_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD')
                  FROM live l),
    'lastAt',  (SELECT to_char(max(l.spent_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD')
                  FROM live l),
    'byCategory', coalesce(
      (SELECT jsonb_agg(c ORDER BY (c ->> 'total')::numeric DESC)
         FROM (SELECT jsonb_build_object(
                        'category', l.category::text,
                        'total', sum(l.amount)::numeric(12,2)::text,
                        'count', count(*)) AS c
                 FROM live l GROUP BY l.category) cats),
      '[]'::jsonb),
    'byYear', coalesce(
      (SELECT jsonb_agg(y ORDER BY (y ->> 'year') DESC)
         FROM (SELECT jsonb_build_object(
                        'year', to_char(l.spent_at AT TIME ZONE 'UTC', 'YYYY'),
                        'total', sum(l.amount)::numeric(12,2)::text,
                        'count', count(*)) AS y
                 FROM live l
                GROUP BY to_char(l.spent_at AT TIME ZONE 'UTC', 'YYYY')) years),
      '[]'::jsonb),
    -- ── THE LEDGER, with a RUNNING TOTAL, oldest first ────────────────────
    -- «صُرف له 100 مولود، ثم بعد أشهر 500 فرح» must read 100 then 600. The
    -- accumulation is a WINDOW FUNCTION here for the same reason the statement's
    -- running balance is one: money crosses the wire as text precisely so
    -- nothing adds it in Dart, and a column the client accumulated itself would
    -- be the one figure on the screen computed in binary floating point.
    --
    -- ASCENDING, and that is what makes the column mean anything: read
    -- newest-first the total accumulates backwards and the last line shows the
    -- FIRST voucher's amount as though it were the sum of everything.
    --
    -- ⚠ FILTER, not a WHERE. A reversed voucher must still be LISTED — rule 9:
    --   history is not an embarrassment — and must not move the balance.
    --   Excluding it with WHERE would drop the line; FILTER keeps it and leaves
    --   its running total identical to the line above, which is exactly what a
    --   ledger shows for an entry that was reversed. coalesce because a FILTERed
    --   window sum over a frame with no live row is NULL, not zero.
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
            WHERE d.payee_adeel_id = p_adeel_id
         ) r
         JOIN public.v_disbursements v ON v."id" = r.id),
      '[]'::jsonb))
$$;

-- == 3. The allow-list, restated with the new read ==========================
-- An EXACT set: assert_function_grants() fails in BOTH directions, so a
-- function granted but unlisted and one listed but ungranted each roll the
-- patch back.
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    'my_adeel_id()',
    'request_device_id()',

    'register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_adeel(bigint,jsonb)',
    'delete_adeel(bigint)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    'purge_financial_data(text)',
    'purge_all_data(text)',

    'issue_adeel_code(bigint)',
    'redeem_adeel_code(text,text)',

    'register_disbursement(numeric,disbursement_kind,pay_method,bigint,expense_category,text,text,text,text,text,text,date)',
    'cancel_disbursement(bigint,text)',

    'period_label(text)',
    'adeel_json(bigint)',
    'api_adeel_detail(bigint)',
    'api_adeel_statement(bigint)',
    -- What the association GAVE him, beside what he owes it. SECURITY INVOKER,
    -- so staff read any man's and an عديل reads only his own — through
    -- read_own_disbursements, which is scoped on payee_adeel_id.
    'api_adeel_aid(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_closable_periods()',
    'api_settings()',
    'api_me()',
    'api_touch_login()',
    'api_association_finance()'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- == 4. Re-run the lockdown sweep ===========================================
-- Byte-for-byte the loop from 20260811091200_function_lockdown.sql, which runs
-- LAST on a full apply. A patch gets no such pass, and api_adeel_aid is created
-- FRESH here — so Postgres materialises the built-in default ACL (EXECUTE to
-- PUBLIC) and Supabase's ALTER DEFAULT PRIVILEGES layers `anon` on top.
-- assert_no_public_execute() would then roll this patch back with a message
-- naming the function rather than the missing REVOKE, which reads like a defect
-- in the file.
DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.full_sig);
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;

-- == The standing guarantees, re-proven ====================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed.
SELECT 'a member may read his OWN vouchers' AS check,
       (SELECT count(*) = 1 FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'disbursements'
           AND policyname = 'read_own_disbursements')::text AS ok
UNION ALL SELECT '...scoped on payee_adeel_id, so a collective voucher is nobody''s',
       (SELECT count(*) = 1 FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'disbursements'
           AND policyname = 'read_own_disbursements'
           AND qual LIKE '%payee_adeel_id%')::text
UNION ALL SELECT '...and the staff policy is untouched beside it',
       (SELECT count(*) = 1 FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'disbursements'
           AND policyname = 'read_disbursements')::text
UNION ALL SELECT 'the aid page exists',
       (SELECT count(*) = 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'api_adeel_aid')::text
UNION ALL SELECT '...and it is SECURITY INVOKER, so RLS still decides',
       (SELECT NOT p.prosecdef FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'api_adeel_aid')::text
UNION ALL SELECT '...and the client may call it',
       (SELECT has_function_privilege('authenticated', p.oid, 'EXECUTE')
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'api_adeel_aid')::text
UNION ALL SELECT '...and anon may NOT',
       (SELECT count(*) = 0 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace,
          LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         WHERE n.nspname = 'public' AND p.proname = 'api_adeel_aid'
           AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR a.grantee = 'anon'::regrole))::text
-- ⚠ The rule the whole patch is built around, checked on the live data rather
-- than asserted in prose: api_adeel_statement reads receivables and payments
-- and nothing else, so no voucher can appear in anybody's statement.
UNION ALL SELECT 'aid is NOT in any statement — الجمعية خيرية',
       (pg_get_functiondef('public.api_adeel_statement(bigint)'::regprocedure)
          NOT LIKE '%disbursement%')::text
-- Informational: how much aid the association has recorded so far, and to how
-- many named members. Right after this patch on a project that has issued no
-- member voucher yet, this reads "0.00 / 0".
UNION ALL SELECT 'aid paid to named members so far / how many men',
       (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text || ' / ' ||
               count(DISTINCT payee_adeel_id)::text
          FROM public.disbursements
         WHERE status <> 'ملغي' AND payee_adeel_id IS NOT NULL)
UNION ALL SELECT 'Google sign-in trigger is STILL in place',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)::text
UNION ALL SELECT 'staff profiles untouched',
       (EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin'))::text;
