-- 45_adeel_portal.sql — an عديل sees his OWN row and his own money, nothing else.
--
-- Runs after 40_rls.sql (which proves the staff boundary) and before the money
-- files, because it neither creates nor destroys financial rows and puts the
-- fixture back exactly as it found it.
--
-- The whole feature rests on one clause: my_role() returns NULL once
-- profiles.adeel_id is set. That clause is doing two jobs, and both failure modes
-- are silent, which is why they are asserted rather than reasoned about:
--
--   1. it REMOVES the عديل from every staff policy without any of those policies
--      being edited. If my_role() ever stopped checking adeel_id he would quietly
--      gain association-wide read access and nothing on screen would look wrong.
--      The cross-عديل counts below catch that.
--   2. it keeps STAFF out of the عديل-scoped policies, because my_adeel_id() is
--      NULL for them. Asserted in the other direction at the end.
--
-- Several عدايل exist by the time this file runs, so "he sees one" is a real
-- assertion and not an accident of there being only one.

SET client_min_messages = warning;

-- ═════ Issuing a code ════════════════════════════════════════════════════════
SET ROLE authenticated;

SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.raises('portal', 'a finance manager cannot issue an access code',
  $sql$ SELECT public.issue_adeel_code(1) $sql$, 'RUL00');

SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.succeeds('portal', 'an admin issues a code for عديل 1',
  $sql$ SELECT public.issue_adeel_code(1) $sql$);
SELECT probe.raises('portal', 'issuing for an عديل that does not exist is refused',
  $sql$ SELECT public.issue_adeel_code(99999) $sql$, 'RUL14');

RESET ROLE;
SELECT probe.eq('portal', 'the code is 12 characters of the unambiguous alphabet',
  $sql$ SELECT (code ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{12}$')::text
          FROM public.adeel_access_codes WHERE adeel_id = 1 $sql$, 'true');

-- Regenerating must REVOKE the old code, not leave a second one working.
CREATE TEMP TABLE code1 AS
  SELECT code FROM public.adeel_access_codes WHERE adeel_id = 1;
SET ROLE authenticated;
SELECT probe.succeeds('portal', 'the admin regenerates the code',
  $sql$ SELECT public.issue_adeel_code(1) $sql$);
RESET ROLE;
SELECT probe.eq('portal', 'regenerating replaces the row rather than adding one',
  $sql$ SELECT count(*)::text FROM public.adeel_access_codes WHERE adeel_id = 1 $sql$,
  '1');
SELECT probe.eq('portal', 'the previous code no longer exists anywhere',
  $sql$ SELECT (NOT EXISTS (SELECT 1 FROM public.adeel_access_codes c
                              JOIN code1 ON code1.code = c.code))::text $sql$, 'true');

-- ═════ Redeeming ═════════════════════════════════════════════════════════════
-- Two accounts of this file's OWN, rather than the fixture's a4/a5. Earlier files
-- approve, suspend and re-approve those, so reusing them made this file's result
-- depend on what 30_rules and 40_rls happened to leave behind — which is how "he
-- is not on the staff ladder" first failed while the code was correct. b1 and b2
-- are created here and deleted at the bottom.
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'adeel@fam.test', '{"full_name":"العديل نفسه"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'other@fam.test', '{"full_name":"شخص آخر"}');

-- The code, readable. adeel_access_codes is admin-only by RLS, so an عديل cannot
-- select his own code out of it — which is correct, and which means the test has
-- to carry the plaintext forward from when postgres could still read it. GRANT on
-- the temp table because `authenticated` owns nothing.
CREATE TEMP TABLE thecode AS
  SELECT code FROM public.adeel_access_codes WHERE adeel_id = 1;
GRANT SELECT ON thecode TO authenticated;

-- What the staff side must still look like afterwards, measured now: earlier
-- files add عدايل, so a literal would be a guess about their contents.
CREATE TEMP TABLE portal_before AS
  SELECT (SELECT count(*) FROM public.adeels) AS adeels;
GRANT SELECT ON portal_before TO authenticated;

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000b1');

SELECT probe.raises('portal', 'a wrong code is refused',
  $sql$ SELECT public.redeem_adeel_code('ZZZZZZZZZZZZ') $sql$, 'RUL14');
SELECT probe.raises('portal', 'an empty code is refused',
  $sql$ SELECT public.redeem_adeel_code('') $sql$, 'RUL14');

RESET ROLE;
SELECT probe.eq('portal', 'a refused redemption bound nobody',
  $sql$ SELECT count(*)::text FROM public.profiles WHERE adeel_id IS NOT NULL $sql$,
  '0');

-- Typed off a phone screen: dashes, spaces and lower case are all expected, and
-- none of them are part of the code.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000b1');
SELECT probe.succeeds('portal', 'the real code is redeemed, dashed and lower-case', $sql$
  SELECT public.redeem_adeel_code(
    lower(substr((SELECT code FROM thecode), 1, 4)
      || '-' || substr((SELECT code FROM thecode), 5, 4)
      || ' '  || substr((SELECT code FROM thecode), 9, 4)))
$sql$);
RESET ROLE;

SELECT probe.eq('portal', 'he is bound to عديل 1, approved, still a viewer',
  $sql$ SELECT adeel_id::text || '/' || status::text || '/' || role::text
          FROM public.profiles WHERE email = 'adeel@fam.test' $sql$,
  '1/approved/viewer');

-- An admin who typed a code would set his own adeel_id, my_role() would start
-- returning NULL, and he would lock himself out of the association's own app —
-- possibly as the last admin, which no other guard would catch, because his role
-- never changed.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');
SELECT probe.raises('portal', 'an admin cannot redeem a code and lock himself out',
  $sql$ SELECT public.redeem_adeel_code(
          (SELECT code FROM thecode)) $sql$,
  'RUL14');

-- A forwarded WhatsApp message must not enrol a second account. b2 is an ordinary
-- viewer, so the admin check above does not fire and the already-redeemed check
-- is genuinely what refuses him.
SELECT probe.become('00000000-0000-0000-0000-0000000000b2');
SELECT probe.raises('portal', 'a redeemed code cannot be redeemed by someone else',
  $sql$ SELECT public.redeem_adeel_code(
          (SELECT code FROM thecode)) $sql$,
  'RUL14');

-- ═════ What he can actually SEE ══════════════════════════════════════════════
SELECT probe.become('00000000-0000-0000-0000-0000000000b1');  -- the عديل

SELECT probe.eq('portal', 'he is not on the staff ladder at all',
  $sql$ SELECT (public.my_role() IS NULL)::text $sql$, 'true');
SELECT probe.eq('portal', 'has_role(viewer) is false for him',
  $sql$ SELECT public.has_role('viewer')::text $sql$, 'false');
SELECT probe.eq('portal', 'my_adeel_id() returns his own id',
  $sql$ SELECT public.my_adeel_id()::text $sql$, '1');

SELECT probe.eq('portal', 'he sees exactly one عديل, and it is himself',
  $sql$ SELECT count(*)::text || '/' || coalesce(min(id)::text, '-')
          FROM public.adeels $sql$, '1/1');
SELECT probe.eq('portal', 'no receivable of another عديل reaches him',
  $sql$ SELECT (count(*) FILTER (WHERE adeel_id <> 1))::text
          FROM public.receivables $sql$, '0');
SELECT probe.eq('portal', 'no payment of another عديل reaches him',
  $sql$ SELECT (count(*) FILTER (WHERE adeel_id <> 1))::text
          FROM public.payments $sql$, '0');
SELECT probe.eq('portal', 'no cash movement of another عديل reaches him',
  $sql$ SELECT (count(*) FILTER (WHERE adeel_id <> 1))::text
          FROM public.cash_movements $sql$, '0');

-- payment_allocations carries no adeel_id of its own and is scoped through its
-- parent — the join most likely to be written wrong, and the one a column-shaped
-- policy could not express at all.
SELECT probe.eq('portal', 'allocations follow their payment',
  $sql$ SELECT count(*)::text FROM public.payment_allocations a
         WHERE NOT EXISTS (SELECT 1 FROM public.payments p
                            WHERE p.id = a.payment_id AND p.adeel_id = 1) $sql$,
  '0');

-- He is billed BY these figures, so withholding them would make his own statement
-- unreadable.
SELECT probe.eq('portal', 'he can read the association settings',
  $sql$ SELECT count(*)::text FROM public.association_settings $sql$, '1');
-- And these are none of his business.
SELECT probe.eq('portal', 'the audit trail is closed to him',
  $sql$ SELECT count(*)::text FROM public.audit_log $sql$, '0');
SELECT probe.eq('portal', 'access codes are closed to him, including his own',
  $sql$ SELECT count(*)::text FROM public.adeel_access_codes $sql$, '0');
SELECT probe.eq('portal', 'he sees only his own profile row',
  $sql$ SELECT count(*)::text FROM public.profiles $sql$, '1');

-- The nested reads the portal screen calls. SECURITY INVOKER, so RLS decides: his
-- own row answers, another عديل returns nothing at all.
SELECT probe.eq('portal', 'api_adeel_detail answers for himself',
  $sql$ SELECT public.api_adeel_detail(1) -> 'adeel' ->> 'adeelCode' $sql$,
  'A-0001');
SELECT probe.eq('portal', 'api_adeel_detail is null for another عديل',
  $sql$ SELECT coalesce((public.api_adeel_detail(2))::text, 'null') $sql$, 'null');
SELECT probe.eq('portal', 'his statement has his own movements',
  $sql$ SELECT (jsonb_array_length(
          public.api_adeel_statement(1) -> 'movements') > 0)::text $sql$, 'true');
SELECT probe.eq('portal', 'another عديل''s statement is empty for him',
  $sql$ SELECT jsonb_array_length(
          public.api_adeel_statement(2) -> 'movements')::text $sql$, '0');

-- READ ONLY is the whole feature. Collection stays with the treasurer, and the
-- refusals come from require_role() inside each RPC, not from hiding a button.
SELECT probe.raises('portal', 'he cannot register a payment',
  $sql$ SELECT public.register_payment(1, 1.00, 'نقداً') $sql$, 'RUL00');
SELECT probe.raises('portal', 'he cannot edit his own record',
  $sql$ SELECT public.save_adeel(1, '{"fullName":"x"}'::jsonb) $sql$,
  'RUL00');
SELECT probe.raises('portal', 'he cannot delete himself off the register',
  $sql$ SELECT public.delete_adeel(1) $sql$, 'RUL00');
SELECT probe.raises('portal', 'he cannot issue a code for another عديل',
  $sql$ SELECT public.issue_adeel_code(2) $sql$, 'RUL00');

-- He may not rebind himself to someone else's ledger either. The guard is scoped
-- to self-change, so an admin can still correct a mis-binding.
-- 42501, not RUL00: `authenticated` holds no UPDATE on profiles at all, so he is
-- stopped by privilege before the trigger is even reached. The trigger is the
-- backstop for anything holding a SQL console; this is the front door.
SELECT probe.raises('portal', 'he cannot even attempt to rebind himself',
  $sql$ UPDATE public.profiles SET adeel_id = 2 WHERE id = auth.uid() $sql$, '42501');

-- ═════ A suspended account cannot redeem its way back in ════════════════════
--
-- guard_profile_change refuses every self-change of `status` except one: the
-- pending → approved that redeem_adeel_code performs on the caller's own row,
-- recognised by the row acquiring an عديل binding at the same moment. Nothing
-- distinguished suspended → approved from it, so an account an admin had
-- suspended could restore itself to `approved` by redeeming any unredeemed
-- code — coming back with read access to one عديل's dues, receipts and
-- statement. Its role never changed, so no other guard had anything to notice.
--
-- Both directions are asserted, because "refused" on its own would also be the
-- answer if the code were simply wrong.
RESET ROLE;
SELECT probe.become(NULL);

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000b3', 'stopped@fam.test',
   '{"full_name":"حساب موقوف"}');
UPDATE public.profiles SET role = 'viewer', status = 'suspended'
 WHERE email = 'stopped@fam.test';

-- A fresh, unredeemed code to aim at. Re-issuing does NOT unbind b1 — his
-- binding lives on profiles.adeel_id from the moment he redeemed — so nothing
-- asserted above changes.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');   -- admin
SELECT probe.succeeds('portal', 'the admin issues a fresh, unredeemed code',
  $sql$ SELECT public.issue_adeel_code(1) $sql$);

-- Carried in a temp table: adeel_access_codes is admin-only by RLS, so reading
-- the code inside the attempt below would return NULL and the redemption would
-- be refused for being empty rather than for the account being suspended —
-- and both refusals raise RUL14.
RESET ROLE;
CREATE TEMP TABLE freshcode AS
  SELECT code FROM public.adeel_access_codes WHERE adeel_id = 1;
GRANT SELECT ON freshcode TO authenticated;

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000b3');
SELECT probe.raises('portal', 'a SUSPENDED account cannot redeem a code',
  $sql$ SELECT public.redeem_adeel_code((SELECT code FROM freshcode)) $sql$,
  'RUL14');

RESET ROLE;
SELECT probe.become(NULL);
SELECT probe.eq('portal', '...and it was left unbound and still suspended',
  $sql$ SELECT coalesce(adeel_id::text, '-') || '/' || status::text
          FROM public.profiles WHERE email = 'stopped@fam.test' $sql$,
  '-/suspended');

-- The passing case. `pending` must still redeem — a new Google account is
-- created viewer/pending, and redeeming is exactly how an عديل turns that into
-- access without an admin approving him as staff.
UPDATE public.profiles SET status = 'pending' WHERE email = 'stopped@fam.test';

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000b3');
SELECT probe.succeeds('portal', 'the same code works once the suspension is lifted',
  $sql$ SELECT public.redeem_adeel_code((SELECT code FROM freshcode)) $sql$);

RESET ROLE;
SELECT probe.become(NULL);
SELECT probe.eq('portal', 'redeeming still approves a PENDING account',
  $sql$ SELECT status::text FROM public.profiles
         WHERE email = 'stopped@fam.test' $sql$, 'approved');

-- Back under the client role. The section below was written inside the SET ROLE
-- that the block above interrupted, and as postgres its two checks would read
-- past RLS and pass while proving nothing.
SET ROLE authenticated;

-- ═════ And staff are not عدايل ═══════════════════════════════════════════════
-- The other direction. If my_adeel_id() ever answered for staff, the عديل-scoped
-- policies would start matching for them too — harmless today, but it would mean
-- the two paths are no longer disjoint.
SELECT probe.become('00000000-0000-0000-0000-0000000000a4');  -- viewer
SELECT probe.eq('portal', 'a staff viewer has no عديل scope',
  $sql$ SELECT (public.my_adeel_id() IS NULL)::text $sql$, 'true');
SELECT probe.eq('portal', 'and still sees the whole register, as before',
  $sql$ SELECT ((SELECT count(*) FROM public.adeels)
              = (SELECT adeels FROM portal_before))::text $sql$, 'true');

RESET ROLE;

-- Put the fixture back. probe.become(NULL) first: the guard above keys on
-- auth.uid(), and the claim from the last impersonation would otherwise make this
-- cleanup look like the عديل unbinding himself.
SELECT probe.become(NULL);
DELETE FROM public.adeel_access_codes;
-- Deleting the auth.users rows cascades to their profiles, which is what takes
-- the binding with them. Nothing else in the suite knows these two ever existed.
DELETE FROM auth.users
 WHERE email IN ('adeel@fam.test', 'other@fam.test', 'stopped@fam.test');
DROP TABLE code1;
DROP TABLE thecode;
DROP TABLE freshcode;
DROP TABLE portal_before;
