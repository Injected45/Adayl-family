-- 40_rls.sql — the hostile client.
--
-- Premise: the attacker holds the anon key, because it ships in the app binary
-- and the web bundle. They can issue any PostgREST call. Nothing below uses the
-- service_role key; that key never leaves a trusted context and testing with it
-- would prove nothing.
--
-- SET ROLE + request.jwt.claims is precisely what PostgREST does per request, so
-- these are the real conditions, not an approximation.
--
-- Two distinct denial shapes, and conflating them is how RLS bugs hide:
--   * NO PRIVILEGE  → SQLSTATE 42501, the statement errors.
--   * POLICY DENIES  → the statement SUCCEEDS and returns ZERO ROWS.
-- A read denied by policy is not an error, so a probe that only looks for errors
-- would report a wide-open table as locked down.

GRANT USAGE ON SCHEMA probe TO anon, authenticated;
GRANT ALL ON ALL TABLES     IN SCHEMA probe TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES  IN SCHEMA probe TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA probe TO anon, authenticated;

-- ═════ anon: signed out entirely ═════════════════════════════════════════════
SET ROLE anon;
SELECT probe.become(NULL, 'anon');

SELECT probe.raises('rls/anon', 'cannot read families',
  'SELECT * FROM public.families', '42501');
SELECT probe.raises('rls/anon', 'cannot read members (names, national IDs)',
  'SELECT * FROM public.members', '42501');
SELECT probe.raises('rls/anon', 'cannot read receivables',
  'SELECT * FROM public.receivables', '42501');
SELECT probe.raises('rls/anon', 'cannot read payments',
  'SELECT * FROM public.payments', '42501');
SELECT probe.raises('rls/anon', 'cannot read the treasury',
  'SELECT * FROM public.cash_movements', '42501');
SELECT probe.raises('rls/anon', 'cannot read the audit trail',
  'SELECT * FROM public.audit_log', '42501');
SELECT probe.raises('rls/anon', 'cannot read profiles',
  'SELECT * FROM public.profiles', '42501');
SELECT probe.raises('rls/anon', 'cannot read settings',
  'SELECT * FROM public.association_settings', '42501');
SELECT probe.raises('rls/anon', 'cannot read the families view',
  'SELECT * FROM public.v_families', '42501');
SELECT probe.raises('rls/anon', 'cannot register a payment',
  'SELECT public.register_payment(1, 10, ''نقداً'')', '42501');
SELECT probe.raises('rls/anon', 'cannot insert a family',
  'INSERT INTO public.families DEFAULT VALUES', '42501');
SELECT probe.raises('rls/anon', 'cannot insert a payment directly',
  'INSERT INTO public.payments (family_id, amount, method) VALUES (1,1,''نقداً'')', '42501');
RESET ROLE;

-- ═════ pending: signed in, never approved ════════════════════════════════════
-- The most dangerous case, because the JWT is genuine. Only the approval flag
-- separates this user from a viewer.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a5');

SELECT probe.eq('rls/pending', 'sees zero families',
  'SELECT count(*)::text FROM public.families', '0');
SELECT probe.eq('rls/pending', 'sees zero members',
  'SELECT count(*)::text FROM public.members', '0');
SELECT probe.eq('rls/pending', 'sees zero receivables',
  'SELECT count(*)::text FROM public.receivables', '0');
SELECT probe.eq('rls/pending', 'sees zero payments',
  'SELECT count(*)::text FROM public.payments', '0');
SELECT probe.eq('rls/pending', 'sees zero treasury rows',
  'SELECT count(*)::text FROM public.cash_movements', '0');
SELECT probe.eq('rls/pending', 'sees zero settings rows',
  'SELECT count(*)::text FROM public.association_settings', '0');
-- but CAN see their own profile, which is how the app renders "awaiting approval"
SELECT probe.eq('rls/pending', 'can read their OWN profile row',
  'SELECT status::text FROM public.profiles WHERE id = auth.uid()', 'pending');
SELECT probe.eq('rls/pending', 'cannot read anyone else''s profile',
  'SELECT count(*)::text FROM public.profiles WHERE id <> auth.uid()', '0');
SELECT probe.raises('rls/pending', 'cannot register a payment',
  'SELECT public.register_payment(1, 10, ''نقداً'')', 'RUL00');
SELECT probe.raises('rls/pending', 'cannot self-approve',
  $sql$ UPDATE public.profiles SET status = 'approved', role = 'admin'
         WHERE id = auth.uid() $sql$, '42501');

-- The behavioural half of the security_invoker guarantee, and it MUST sit before
-- the RESET ROLE below. A view created without security_invoker runs with its
-- OWNER's rights and reads straight past RLS, so a pending user would see the
-- whole ledger through v_families while seeing nothing through the table itself.
-- Introspecting reloptions cannot demonstrate that; this can.
--
-- Placed after RESET ROLE in the first draft, these ran as postgres — the table
-- owner, who bypasses RLS — and reported the entire ledger as visible. That read
-- as a critical vulnerability and was purely the probe standing in the wrong
-- place. Worth the comment: an RLS test that is not demonstrably running as the
-- role it names is worse than no test.
SELECT probe.eq('rls/pending', 'is really running as authenticated, not as owner',
  'SELECT current_user', 'authenticated');
SELECT probe.eq('rls/pending', 'sees zero rows through the families VIEW too',
  'SELECT count(*)::text FROM public.v_families', '0');
SELECT probe.eq('rls/pending', 'sees zero rows through the receivables VIEW',
  'SELECT count(*)::text FROM public.v_receivables', '0');
SELECT probe.eq('rls/pending', 'sees zero rows through the members VIEW',
  'SELECT count(*)::text FROM public.v_members', '0');
SELECT probe.eq('rls/pending', 'the treasury summary reads zero, not the real total',
  -- '0.00', not '0'. Every money value is two decimal places now: the aggregate
  -- is cast to numeric(12,2) before text, so an empty bucket formats like every
  -- other amount on the same screen instead of standing out as a bare integer.
  $sql$ SELECT "total" FROM public.v_cash_summary $sql$, '0.00');
RESET ROLE;

-- ═════ suspended: was an admin, now revoked ══════════════════════════════════
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a6');
SELECT probe.eq('rls/suspended', 'an admin role with suspended status sees nothing',
  'SELECT count(*)::text FROM public.families', '0');
SELECT probe.raises('rls/suspended', 'and cannot use admin RPCs',
  $sql$ SELECT public.update_settings('{"currency":"HACKED"}'::jsonb) $sql$, 'RUL00');
RESET ROLE;

-- ═════ viewer: read-only, and it must really be read-only ════════════════════
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a4');
SELECT probe.eq('rls/viewer', 'is running as authenticated', 'SELECT current_user', 'authenticated');

SELECT probe.eq('rls/viewer', 'CAN read families',
  'SELECT count(*)::text FROM public.families', '2');
SELECT probe.eq('rls/viewer', 'CAN read the families view',
  'SELECT count(*)::text FROM public.v_families', '2');
SELECT probe.eq('rls/viewer', 'CAN read the treasury summary',
  'SELECT count(*)::text FROM public.v_cash_summary', '1');
-- audit is financeManager+, so a viewer sees an empty trail rather than an error
SELECT probe.eq('rls/viewer', 'sees an EMPTY audit trail',
  'SELECT count(*)::text FROM public.audit_log', '0');

SELECT probe.raises('rls/viewer', 'cannot register a payment',
  'SELECT public.register_payment(1, 10, ''نقداً'')', 'RUL00');
SELECT probe.raises('rls/viewer', 'cannot cancel a payment',
  'SELECT public.cancel_payment(1, ''x'')', 'RUL00');
SELECT probe.raises('rls/viewer', 'cannot generate receivables',
  'SELECT public.generate_period(''2026-05'')', 'RUL00');
SELECT probe.raises('rls/viewer', 'cannot save a family',
  'SELECT public.save_family(NULL, ''{"fullName":"x","nationalId":"9"}''::jsonb)', 'RUL00');
SELECT probe.raises('rls/viewer', 'cannot change settings',
  'SELECT public.update_settings(''{"currency":"X"}''::jsonb)', 'RUL00');
SELECT probe.raises('rls/viewer', 'cannot grant themselves a role',
  $sql$ SELECT public.set_user_access('00000000-0000-0000-0000-0000000000a4','admin','approved') $sql$,
  'RUL00');

-- Direct table writes: no privilege at all, so these never even reach a policy.
SELECT probe.raises('rls/viewer', 'cannot INSERT a family',
  'INSERT INTO public.families DEFAULT VALUES', '42501');
SELECT probe.raises('rls/viewer', 'cannot UPDATE a receivable balance',
  'UPDATE public.receivables SET paid = 0 WHERE id = 1', '42501');
SELECT probe.raises('rls/viewer', 'cannot DELETE a payment',
  'DELETE FROM public.payments WHERE id = 1', '42501');
SELECT probe.raises('rls/viewer', 'cannot INSERT into the treasury',
  'INSERT INTO public.cash_movements (payment_id, family_id, amount, method, occurred_at)
   VALUES (1,1,1,''نقداً'',now())', '42501');
SELECT probe.raises('rls/viewer', 'cannot forge an audit entry',
  'INSERT INTO public.audit_log (event_type, detail, actor_name) VALUES (''x'',''y'',''z'')', '42501');
SELECT probe.raises('rls/viewer', 'cannot call the internal audit helper',
  'SELECT public.write_audit(''forged'',''forged'')', '42501');
SELECT probe.raises('rls/viewer', 'cannot promote themselves via profiles',
  $sql$ UPDATE public.profiles SET role = 'admin' WHERE id = auth.uid() $sql$, '42501');
RESET ROLE;

-- ═════ treasurer: may collect, may not reverse ═══════════════════════════════
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a3');
SELECT probe.eq('rls/treasurer', 'is running as authenticated', 'SELECT current_user', 'authenticated');
SELECT probe.succeeds('rls/treasurer', 'CAN register a payment',
  'SELECT public.register_payment(2, 5, ''نقداً'')');
SELECT probe.raises('rls/treasurer', 'cannot cancel a payment',
  'SELECT public.cancel_payment(2, ''x'')', 'RUL00');
SELECT probe.raises('rls/treasurer', 'cannot generate receivables',
  'SELECT public.generate_period(''2026-05'')', 'RUL00');
SELECT probe.raises('rls/treasurer', 'cannot change settings',
  'SELECT public.update_settings(''{"currency":"X"}''::jsonb)', 'RUL00');
SELECT probe.eq('rls/treasurer', 'sees an empty audit trail',
  'SELECT count(*)::text FROM public.audit_log', '0');
RESET ROLE;

-- ═════ financeManager: oversight, but not administration ═════════════════════
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');
SELECT probe.eq('rls/finance', 'is running as authenticated', 'SELECT current_user', 'authenticated');
SELECT probe.succeeds('rls/finance', 'CAN cancel a payment',
  'SELECT public.cancel_payment(2, ''تصحيح'')');
SELECT probe.succeeds('rls/finance', 'CAN generate receivables',
  'SELECT public.generate_period(''2026-05'')');
SELECT probe.succeeds('rls/finance', 'CAN save a family', $sql$
  SELECT public.save_family(NULL,
    '{"fullName":"أب جديد","nationalId":"1000000000200","dob":"1980-01-01"}'::jsonb,
    '[{"fullName":"ابن جديد","nationalId":"1000000000201","dob":"2006-01-01"}]'::jsonb)
$sql$);
SELECT probe.raises('rls/finance', 'cannot change settings',
  'SELECT public.update_settings(''{"currency":"X"}''::jsonb)', 'RUL00');
SELECT probe.raises('rls/finance', 'cannot grant roles',
  $sql$ SELECT public.set_user_access('00000000-0000-0000-0000-0000000000a4','admin','approved') $sql$,
  'RUL00');
SELECT probe.eq('rls/finance', 'CAN read the audit trail',
  'SELECT (count(*) > 0)::text FROM public.audit_log', 'true');
RESET ROLE;

-- ═════ admin ═════════════════════════════════════════════════════════════════
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');
SELECT probe.eq('rls/admin', 'is running as authenticated', 'SELECT current_user', 'authenticated');
SELECT probe.succeeds('rls/admin', 'CAN change settings',
  'SELECT public.update_settings(''{"currency":"د.ل"}''::jsonb)');
SELECT probe.succeeds('rls/admin', 'CAN approve another user',
  $sql$ SELECT public.set_user_access('00000000-0000-0000-0000-0000000000a5','viewer','approved') $sql$);
SELECT probe.eq('rls/admin', 'CAN list all profiles',
  'SELECT (count(*) = 6)::text FROM public.profiles', 'true');
-- Guards that bind even an admin.
SELECT probe.raises('rls/admin', 'cannot change their OWN role',
  $sql$ SELECT public.set_user_access('00000000-0000-0000-0000-0000000000a1','viewer','approved') $sql$,
  'RUL00');
SELECT probe.raises('rls/admin', 'cannot still write tables directly',
  'INSERT INTO public.families DEFAULT VALUES', '42501');
RESET ROLE;

-- ═════ The last-admin guard, exercised as postgres ═══════════════════════════
-- Demoting the only approved admin must fail even here, because this trigger is
-- the difference between a recoverable mistake and a permanently locked-out
-- association with no server-side console to fix it from.
SELECT probe.become(NULL, 'anon');
SELECT probe.succeeds('guards', 'demote the second admin first',
  $sql$ UPDATE public.profiles SET status = 'suspended' WHERE email = 'suspended@fam.test' $sql$);
SELECT probe.raises('guards', 'the last approved admin cannot be demoted',
  $sql$ UPDATE public.profiles SET role = 'viewer' WHERE email = 'admin@fam.test' $sql$,
  'RUL00');
SELECT probe.raises('guards', 'the last approved admin cannot be suspended',
  $sql$ UPDATE public.profiles SET status = 'suspended' WHERE email = 'admin@fam.test' $sql$,
  'RUL00');

-- ═════ The lockdown assertions must be able to FAIL ══════════════════════════
-- An assertion that has never been seen to fail is not evidence. Plant exactly
-- the mistake each one exists to catch, confirm it is caught, then remove it and
-- confirm the check goes quiet again.

SELECT probe.succeeds('lockdown', 'a clean schema passes the PUBLIC-execute check',
  'SELECT public.assert_no_public_execute()');

CREATE FUNCTION public._planted_leak() RETURNS int LANGUAGE sql AS 'SELECT 1';
SELECT probe.raises_like('lockdown',
  'a function left executable by PUBLIC is CAUGHT',
  'SELECT public.assert_no_public_execute()', 'P0001', '%_planted_leak%');
DROP FUNCTION public._planted_leak();
SELECT probe.succeeds('lockdown', 'and the check goes quiet once it is removed',
  'SELECT public.assert_no_public_execute()');

SELECT probe.succeeds('lockdown', 'a clean schema passes the security_invoker check',
  'SELECT public.assert_views_security_invoker()');

-- A view without security_invoker reads straight past RLS — the single most
-- likely way this schema could be opened up by accident.
CREATE VIEW public._planted_bypass AS SELECT id FROM public.families;
SELECT probe.raises_like('lockdown',
  'a view that would bypass RLS is CAUGHT',
  'SELECT public.assert_views_security_invoker()', 'P0001', '%_planted_bypass%');
DROP VIEW public._planted_bypass;
SELECT probe.succeeds('lockdown', 'and that check goes quiet too',
  'SELECT public.assert_views_security_invoker()');

-- ═════ The function allow-list must be exact, and must be able to FAIL ═══════
-- This is the guard that was missing. Supabase's default privileges grant EXECUTE
-- on every new function in `public` to anon and authenticated BY NAME, so a
-- lockdown that only revokes from PUBLIC does nothing at all — and write_audit
-- stayed callable by any signed-in user, who used it to forge an audit entry on
-- the live project during verification.

SELECT probe.succeeds('lockdown', 'a clean schema passes the grant check',
  'SELECT public.assert_function_grants()');

-- The exact hole that was exploited.
GRANT EXECUTE ON FUNCTION public.write_audit(text, text, text) TO authenticated;
SELECT probe.raises_like('lockdown',
  'write_audit granted to authenticated is CAUGHT',
  'SELECT public.assert_function_grants()', 'P0001', '%write_audit%');
REVOKE EXECUTE ON FUNCTION public.write_audit(text, text, text) FROM authenticated;
SELECT probe.succeeds('lockdown', 'and the check goes quiet once revoked',
  'SELECT public.assert_function_grants()');

-- anon counts too: the anon key is public, so a function anon can call is a
-- function the whole internet can call.
GRANT EXECUTE ON FUNCTION public.write_audit(text, text, text) TO anon;
SELECT probe.raises_like('lockdown',
  'write_audit granted to ANON is CAUGHT',
  'SELECT public.assert_function_grants()', 'P0001', '%write_audit%');
REVOKE EXECUTE ON FUNCTION public.write_audit(text, text, text) FROM anon;

-- A brand-new function is unreachable until it is allow-listed on purpose.
CREATE FUNCTION public._planted_rpc() RETURNS int LANGUAGE sql AS 'SELECT 1';
GRANT EXECUTE ON FUNCTION public._planted_rpc() TO authenticated;
SELECT probe.raises_like('lockdown',
  'a new un-allow-listed function is CAUGHT',
  'SELECT public.assert_function_grants()', 'P0001', '%_planted_rpc%');
DROP FUNCTION public._planted_rpc();

-- The other direction: an allow-listed function that is NOT granted would break a
-- screen at runtime. The migration should refuse instead.
REVOKE EXECUTE ON FUNCTION public.api_dashboard() FROM authenticated;
SELECT probe.raises_like('lockdown',
  'an allow-listed function left ungranted is CAUGHT',
  'SELECT public.assert_function_grants()', 'P0001', '%api_dashboard%');
GRANT EXECUTE ON FUNCTION public.api_dashboard() TO authenticated;
SELECT probe.succeeds('lockdown', 'restored',
  'SELECT public.assert_function_grants()');

-- And the real behavioural proof: a viewer cannot call write_audit.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a4');
SELECT probe.raises('lockdown', 'a viewer STILL cannot forge an audit entry',
  'SELECT public.write_audit(''forged'',''forged'')', '42501');
RESET ROLE;
