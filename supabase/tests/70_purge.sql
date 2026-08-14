-- 70_purge.sql — the two purges, the deliberate exceptions to rule 9.
--
--   purge_financial_data  the figures only; the directory survives
--   purge_all_data        the directory too, and therefore the figures with it
--
-- Both are exercised here, narrow first, because the wide one's starting state
-- is whatever the narrow one leaves behind — which is the state a real admin is
-- in when he decides clearing the figures was not enough.
--
-- RUNS LAST, AND HAS TO. It erases every payment, receivable, cash movement and
-- audit row the four preceding files created, so anything scheduled after it
-- would be asserting against an empty database. probe.sh calls it after
-- 60_concurrency.sh for that reason.
--
-- What is proved here is narrower than "the function works":
--
--   * it refuses everyone below admin, so a treasurer who reads the publishable
--     key out of the APK and calls the RPC by hand gets RUL00, not a wiped
--     ledger;
--   * it refuses an admin who did not type the phrase, and a refusal leaves the
--     data untouched — a half-purge would be worse than either outcome;
--   * it erases exactly six tables and NOTHING else. The before/after counts on
--     families, members and profiles are the checks that matter most: a stray
--     CASCADE in the TRUNCATE list would take the whole directory with it and
--     the function would still report success;
--   * the rule-9 and rule-12 guards are still armed afterwards. TRUNCATE was
--     chosen over DISABLE TRIGGER + DELETE precisely so no path can leave them
--     off, and this is the assertion that pins that choice;
--   * the identities restarted, so the association's first real receipt is
--     PAY-000001 rather than a continuation of the trial run's numbering. That
--     is the whole reason a purge was wanted instead of cancelling every payment.

SET client_min_messages = warning;

-- Everything the purge must NOT touch, measured before it runs. Comparing
-- against literals would only prove the counts are what this file guessed;
-- comparing against the before-state proves the purge left them alone whatever
-- the preceding four files did to them.
CREATE TEMP TABLE purge_before AS
  SELECT (SELECT count(*) FROM public.families) AS families,
         (SELECT count(*) FROM public.members)  AS members,
         (SELECT count(*) FROM public.profiles) AS profiles,
         (SELECT count(*) FROM public.payments) AS payments;

SELECT probe.eq('purge', 'the suite left financial data behind to erase',
  $sql$ SELECT ((SELECT count(*) FROM public.payments)    > 0
            AND (SELECT count(*) FROM public.receivables) > 0
            AND (SELECT count(*) FROM public.audit_log)   > 0)::text $sql$,
  'true');

-- ═════ The role gate ═════════════════════════════════════════════════════════
-- Called the way a real client calls it: the `authenticated` SQL role plus a JWT
-- claim, which is the pair PostgREST sets up per request.
SET ROLE authenticated;

SELECT probe.become('00000000-0000-0000-0000-0000000000a3');  -- treasurer
SELECT probe.raises('purge', 'a treasurer cannot purge',
  $sql$ SELECT public.purge_financial_data('مسح نهائي') $sql$, 'RUL00');

-- The finance manager too. He is the role that legitimately performs every
-- other destructive-looking write (generate, cancel), so he is the one a
-- `>= financeManager` check would wrongly let through.
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.raises('purge', 'a finance manager cannot purge either',
  $sql$ SELECT public.purge_financial_data('مسح نهائي') $sql$, 'RUL00');

-- ═════ The typed phrase ══════════════════════════════════════════════════════
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin

SELECT probe.raises('purge', 'the wrong confirmation phrase is refused',
  $sql$ SELECT public.purge_financial_data('نعم') $sql$, 'RUL13');
SELECT probe.raises('purge', 'an empty confirmation is refused',
  $sql$ SELECT public.purge_financial_data('') $sql$, 'RUL13');

RESET ROLE;
SELECT probe.eq('purge', 'a refused purge erased nothing',
  $sql$ SELECT ((SELECT count(*) FROM public.payments)
              = (SELECT payments FROM purge_before))::text $sql$, 'true');

-- ═════ The purge itself ══════════════════════════════════════════════════════
SET ROLE authenticated;
SELECT probe.succeeds('purge', 'an admin with the phrase purges',
  $sql$ SELECT public.purge_financial_data('مسح نهائي') $sql$);
RESET ROLE;

SELECT probe.eq('purge', 'receivables are gone',
  $sql$ SELECT count(*)::text FROM public.receivables $sql$, '0');
SELECT probe.eq('purge', 'receivable lines are gone',
  $sql$ SELECT count(*)::text FROM public.receivable_lines $sql$, '0');
SELECT probe.eq('purge', 'payments are gone',
  $sql$ SELECT count(*)::text FROM public.payments $sql$, '0');
SELECT probe.eq('purge', 'allocations are gone',
  $sql$ SELECT count(*)::text FROM public.payment_allocations $sql$, '0');
SELECT probe.eq('purge', 'cash movements are gone',
  $sql$ SELECT count(*)::text FROM public.cash_movements $sql$, '0');
-- Deliberate, and the reason rule 12 is weaker than it was: the association's
-- admin asked for a purge that leaves no trace, so no entry is written after the
-- truncate either. See the header of purge_financial_data().
SELECT probe.eq('purge', 'the audit trail is gone, and nothing records the purge',
  $sql$ SELECT count(*)::text FROM public.audit_log $sql$, '0');

-- ═════ And nothing else ══════════════════════════════════════════════════════
SELECT probe.eq('purge', 'every family survived',
  $sql$ SELECT ((SELECT count(*) FROM public.families)
              = (SELECT families FROM purge_before))::text $sql$, 'true');
SELECT probe.eq('purge', 'every member survived',
  $sql$ SELECT ((SELECT count(*) FROM public.members)
              = (SELECT members FROM purge_before))::text $sql$, 'true');
SELECT probe.eq('purge', 'every user account survived',
  $sql$ SELECT ((SELECT count(*) FROM public.profiles)
              = (SELECT profiles FROM purge_before))::text $sql$, 'true');
SELECT probe.eq('purge', 'the association settings survived',
  $sql$ SELECT count(*)::text FROM public.association_settings $sql$, '1');

-- ═════ The database still works, and starts from one ═════════════════════════
-- Inserted as postgres rather than raised through generate_period(): the four
-- preceding files suspend and reinstate members, so which families are billable
-- by now is not something this file should have to know.
SELECT probe.succeeds('purge', 'the financial tables accept new rows again', $sql$
  INSERT INTO public.receivables (family_id, period, period_end, father_fee,
                                  son_fee, father_name, eligibility_age_snapshot,
                                  warning_months_snapshot, total)
  VALUES (1, '2027-01', '2027-01-31', 20.00, 0.00, 'الأب الأول', 16, 3, 20.00)
$sql$);
SELECT probe.eq('purge', 'RESTART IDENTITY: the first receivable is id 1',
  $sql$ SELECT min(id)::text FROM public.receivables $sql$, '1');

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');  -- treasurer
SELECT probe.succeeds('purge', 'collection works again after a purge',
  $sql$ SELECT public.register_payment(1, 20.00, 'نقداً') $sql$);
RESET ROLE;
SELECT probe.eq('purge', 'RESTART IDENTITY: the first receipt is PAY-000001',
  $sql$ SELECT receipt_no FROM public.payments ORDER BY id LIMIT 1 $sql$,
  'PAY-000001');

-- ═════ The guards are still armed ════════════════════════════════════════════
-- TRUNCATE fires no BEFORE DELETE trigger, so it never had to disarm these. If
-- the implementation is ever switched to DISABLE TRIGGER + DELETE, an exception
-- between the disable and the re-enable would leave the financial tables
-- deletable by anything with a SQL console, and these two checks are what would
-- catch it.
SELECT probe.raises('purge', 'the rule 9 delete guard is still armed',
  'DELETE FROM public.receivables WHERE id = 1', 'RUL09');
SELECT probe.raises('purge', 'the rule 12 audit guard is still armed',
  'DELETE FROM public.audit_log WHERE id = 1', 'RUL12');

-- The function is the ONLY route to a truncate: the privilege itself is withheld
-- from both client roles, so a hostile client cannot skip the role check and the
-- phrase by issuing the TRUNCATE directly.
SELECT probe.eq('purge', 'no client role can TRUNCATE the financial tables itself',
  $sql$ SELECT bool_or(has_table_privilege(r, t, 'TRUNCATE'))::text
          FROM unnest(ARRAY['anon','authenticated']) r,
               unnest(ARRAY['public.receivables','public.receivable_lines',
                            'public.payments','public.payment_allocations',
                            'public.cash_movements','public.audit_log']) t $sql$,
  'false');

-- Supabase's default privileges grant EXECUTE in `public` to anon BY NAME, so
-- this is the check that the lockdown's revoke actually reached the new
-- function. Without it the purge would be callable with the publishable key and
-- no session at all — which is exactly how write_audit was once exposed.
SELECT probe.eq('purge', 'anon cannot reach the purge function at all',
  $sql$ SELECT has_function_privilege('anon',
          'public.purge_financial_data(text)', 'EXECUTE')::text $sql$, 'false');

-- ═════════════════════════════════════════════════════════════════════════════
-- purge_all_data — the wider purge, which takes the directory too.
--
-- Runs after the narrow one on purpose: the state it starts from is the one the
-- narrow purge leaves behind (a fresh receivable, one receipt, the directory
-- untouched), which is exactly the state an admin is in when he decides the
-- figures were not enough and the families have to go as well.
--
-- The check that carries the design is 'the financial phrase does NOT satisfy
-- it'. Two admin-only truncating functions are only safely distinct if the
-- phrase for one is refused by the other; without that, having two is theatre.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE TEMP TABLE purge_all_before AS
  SELECT (SELECT count(*) FROM public.families) AS families,
         (SELECT count(*) FROM public.members)  AS members,
         (SELECT count(*) FROM public.profiles WHERE family_id IS NULL) AS staff;

SELECT probe.eq('purge_all', 'the directory is still standing before the wider purge',
  $sql$ SELECT ((SELECT count(*) FROM public.families) > 0
            AND (SELECT count(*) FROM public.members)  > 0)::text $sql$, 'true');

SET ROLE authenticated;

SELECT probe.become('00000000-0000-0000-0000-0000000000a3');  -- treasurer
SELECT probe.raises('purge_all', 'a treasurer cannot purge the directory',
  $sql$ SELECT public.purge_all_data('مسح كل البيانات') $sql$, 'RUL00');

SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin

-- THE check. An admin who meant to clear the figures, and typed the phrase he
-- knows, must not empty the directory instead.
SELECT probe.raises('purge_all', 'the financial phrase does NOT satisfy the wider purge',
  $sql$ SELECT public.purge_all_data('مسح نهائي') $sql$, 'RUL13');
-- And the reverse, so neither phrase is a superset of the other.
SELECT probe.raises('purge_all', 'the wider phrase does NOT satisfy the financial purge',
  $sql$ SELECT public.purge_financial_data('مسح كل البيانات') $sql$, 'RUL13');

RESET ROLE;
SELECT probe.eq('purge_all', 'the refused attempts left the directory alone',
  $sql$ SELECT ((SELECT count(*) FROM public.families)
              = (SELECT families FROM purge_all_before))::text $sql$, 'true');

SET ROLE authenticated;
SELECT probe.succeeds('purge_all', 'an admin with the wider phrase purges everything',
  $sql$ SELECT public.purge_all_data('مسح كل البيانات') $sql$);
RESET ROLE;

SELECT probe.eq('purge_all', 'families are gone',
  $sql$ SELECT count(*)::text FROM public.families $sql$, '0');
SELECT probe.eq('purge_all', 'members are gone',
  $sql$ SELECT count(*)::text FROM public.members $sql$, '0');
SELECT probe.eq('purge_all', 'the financial tables went with them',
  $sql$ SELECT ((SELECT count(*) FROM public.receivables)
              + (SELECT count(*) FROM public.receivable_lines)
              + (SELECT count(*) FROM public.payments)
              + (SELECT count(*) FROM public.payment_allocations)
              + (SELECT count(*) FROM public.cash_movements)
              + (SELECT count(*) FROM public.audit_log))::text $sql$, '0');

-- What must NOT go. Wiping profiles would strand the association outside its own
-- app, and settings are configuration rather than data.
SELECT probe.eq('purge_all', 'the association settings survived',
  $sql$ SELECT count(*)::text FROM public.association_settings $sql$, '1');
-- STAFF accounts specifically. A head of family is deliberately NOT among the
-- survivors: his family is being erased, so leaving his profile would leave a
-- scope pointing at nothing, and my_family_id() would answer with a dead id.
-- His auth.users identity survives, so the same person can redeem a fresh code
-- once the directory is rebuilt.
SELECT probe.eq('purge_all', 'every STAFF account survived',
  $sql$ SELECT ((SELECT count(*) FROM public.profiles WHERE family_id IS NULL)
              = (SELECT staff FROM purge_all_before))::text $sql$, 'true');
SELECT probe.eq('purge_all', 'and no family-head profile is left pointing at nothing',
  $sql$ SELECT count(*)::text FROM public.profiles
         WHERE family_id IS NOT NULL $sql$, '0');

-- RESTART IDENTITY reaches families too, so the association's first real family
-- is F-0001 rather than a continuation of the trial run's codes.
SELECT probe.succeeds('purge_all', 'a family can be created again after the purge',
  $sql$ INSERT INTO public.families DEFAULT VALUES $sql$);
SELECT probe.eq('purge_all', 'RESTART IDENTITY: the first family is F-0001',
  $sql$ SELECT family_code FROM public.families ORDER BY id LIMIT 1 $sql$, 'F-0001');

SELECT probe.eq('purge_all', 'anon cannot reach the wider purge either',
  $sql$ SELECT has_function_privilege('anon',
          'public.purge_all_data(text)', 'EXECUTE')::text $sql$, 'false');
