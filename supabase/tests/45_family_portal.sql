-- 45_family_portal.sql — a head of family sees his OWN family, and nothing else.
--
-- Runs after 40_rls.sql (which proves the staff boundary) and before the money
-- files, because it neither creates nor destroys financial rows and puts the
-- fixture back exactly as it found it.
--
-- The whole feature rests on one clause: my_role() returns NULL once
-- profiles.family_id is set. That clause is doing two jobs, and both failure
-- modes are silent, which is why they are asserted rather than reasoned about:
--
--   1. it REMOVES the head of family from every staff policy without any of
--      those eight policies being edited. If my_role() ever stopped checking
--      family_id he would quietly gain association-wide read access and nothing
--      on screen would look wrong. The cross-family counts below catch that.
--   2. it keeps STAFF out of the family-scoped policies, because my_family_id()
--      is NULL for them. Asserted in the other direction at the end.
--
-- Several families exist by the time this file runs, so "he sees one family" is
-- a real assertion and not an accident of there being only one.

SET client_min_messages = warning;

-- ═════ Issuing a code ════════════════════════════════════════════════════════
SET ROLE authenticated;

SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- finance manager
SELECT probe.raises('portal', 'a finance manager cannot issue an access code',
  $sql$ SELECT public.issue_family_code(1) $sql$, 'RUL00');

SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.succeeds('portal', 'an admin issues a code for family 1',
  $sql$ SELECT public.issue_family_code(1) $sql$);
SELECT probe.raises('portal', 'issuing for a family that does not exist is refused',
  $sql$ SELECT public.issue_family_code(99999) $sql$, 'RUL14');

RESET ROLE;
SELECT probe.eq('portal', 'the code is 12 characters of the unambiguous alphabet',
  $sql$ SELECT (code ~ '^[23456789ABCDEFGHJKMNPQRSTVWXYZ]{12}$')::text
          FROM public.family_access_codes WHERE family_id = 1 $sql$, 'true');

-- Regenerating must REVOKE the old code, not leave a second one working.
CREATE TEMP TABLE code1 AS
  SELECT code FROM public.family_access_codes WHERE family_id = 1;
SET ROLE authenticated;
SELECT probe.succeeds('portal', 'the admin regenerates the code',
  $sql$ SELECT public.issue_family_code(1) $sql$);
RESET ROLE;
SELECT probe.eq('portal', 'regenerating replaces the row rather than adding one',
  $sql$ SELECT count(*)::text FROM public.family_access_codes WHERE family_id = 1 $sql$,
  '1');
SELECT probe.eq('portal', 'the previous code no longer exists anywhere',
  $sql$ SELECT (NOT EXISTS (SELECT 1 FROM public.family_access_codes c
                              JOIN code1 ON code1.code = c.code))::text $sql$, 'true');

-- ═════ Redeeming ═════════════════════════════════════════════════════════════
-- Two accounts of this file's OWN, rather than the fixture's a4/a5. Earlier
-- files approve, suspend and re-approve those, so reusing them made this file's
-- result depend on what 30_rules and 40_rls happened to leave behind — which is
-- how "he is not on the staff ladder" first failed while the code was correct.
-- b1 and b2 are created here and deleted at the bottom.
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000b1', 'head@fam.test',  '{"full_name":"رب العائلة"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'other@fam.test', '{"full_name":"شخص آخر"}');

-- The code, readable. family_access_codes is admin-only by RLS, so a head of
-- family cannot select his own code out of it — which is correct, and which
-- means the test has to carry the plaintext forward from when postgres could
-- still read it. GRANT on the temp table because `authenticated` owns nothing.
CREATE TEMP TABLE thecode AS
  SELECT code FROM public.family_access_codes WHERE family_id = 1;
GRANT SELECT ON thecode TO authenticated;

-- What the staff side must still look like afterwards, measured now: earlier
-- files add families, so a literal would be a guess about their contents.
CREATE TEMP TABLE portal_before AS
  SELECT (SELECT count(*) FROM public.families) AS families;
GRANT SELECT ON portal_before TO authenticated;

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000b1');

SELECT probe.raises('portal', 'a wrong code is refused',
  $sql$ SELECT public.redeem_family_code('ZZZZZZZZZZZZ') $sql$, 'RUL14');
SELECT probe.raises('portal', 'an empty code is refused',
  $sql$ SELECT public.redeem_family_code('') $sql$, 'RUL14');

RESET ROLE;
SELECT probe.eq('portal', 'a refused redemption bound nobody',
  $sql$ SELECT count(*)::text FROM public.profiles WHERE family_id IS NOT NULL $sql$,
  '0');

-- Typed off a phone screen: dashes, spaces and lower case are all expected, and
-- none of them are part of the code.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000b1');
SELECT probe.succeeds('portal', 'the real code is redeemed, dashed and lower-case', $sql$
  SELECT public.redeem_family_code(
    lower(substr((SELECT code FROM thecode), 1, 4)
      || '-' || substr((SELECT code FROM thecode), 5, 4)
      || ' '  || substr((SELECT code FROM thecode), 9, 4)))
$sql$);
RESET ROLE;

SELECT probe.eq('portal', 'he is bound to family 1, approved, still a viewer',
  $sql$ SELECT family_id::text || '/' || status::text || '/' || role::text
          FROM public.profiles WHERE email = 'head@fam.test' $sql$,
  '1/approved/viewer');

-- An admin who typed a code would set his own family_id, my_role() would start
-- returning NULL, and he would lock himself out of the association's own app —
-- possibly as the last admin, which no other guard would catch, because his
-- role never changed.
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');
SELECT probe.raises('portal', 'an admin cannot redeem a code and lock himself out',
  $sql$ SELECT public.redeem_family_code(
          (SELECT code FROM thecode)) $sql$,
  'RUL14');

-- A forwarded WhatsApp message must not enrol a second household. b2 is an
-- ordinary viewer, so the admin check above does not fire and the
-- already-redeemed check is genuinely what refuses him.
SELECT probe.become('00000000-0000-0000-0000-0000000000b2');
SELECT probe.raises('portal', 'a redeemed code cannot be redeemed by someone else',
  $sql$ SELECT public.redeem_family_code(
          (SELECT code FROM thecode)) $sql$,
  'RUL14');

-- ═════ What he can actually SEE ══════════════════════════════════════════════
SELECT probe.become('00000000-0000-0000-0000-0000000000b1');  -- the head of family

SELECT probe.eq('portal', 'he is not on the staff ladder at all',
  $sql$ SELECT (public.my_role() IS NULL)::text $sql$, 'true');
SELECT probe.eq('portal', 'has_role(viewer) is false for him',
  $sql$ SELECT public.has_role('viewer')::text $sql$, 'false');
SELECT probe.eq('portal', 'my_family_id() returns his family',
  $sql$ SELECT public.my_family_id()::text $sql$, '1');

SELECT probe.eq('portal', 'he sees exactly one family, and it is his',
  $sql$ SELECT count(*)::text || '/' || coalesce(min(id)::text, '-')
          FROM public.families $sql$, '1/1');
SELECT probe.eq('portal', 'no member of another family reaches him',
  $sql$ SELECT (count(*) FILTER (WHERE family_id <> 1))::text
          FROM public.members $sql$, '0');
SELECT probe.eq('portal', 'no receivable of another family reaches him',
  $sql$ SELECT (count(*) FILTER (WHERE family_id <> 1))::text
          FROM public.receivables $sql$, '0');
SELECT probe.eq('portal', 'no payment of another family reaches him',
  $sql$ SELECT (count(*) FILTER (WHERE family_id <> 1))::text
          FROM public.payments $sql$, '0');
SELECT probe.eq('portal', 'no cash movement of another family reaches him',
  $sql$ SELECT (count(*) FILTER (WHERE family_id <> 1))::text
          FROM public.cash_movements $sql$, '0');

-- The two link tables carry no family_id of their own and are scoped through
-- their parent — the join most likely to be written wrong, and the one a
-- column-shaped policy could not express at all.
SELECT probe.eq('portal', 'receivable lines follow their receivable',
  $sql$ SELECT count(*)::text FROM public.receivable_lines l
         WHERE NOT EXISTS (SELECT 1 FROM public.receivables r
                            WHERE r.id = l.receivable_id AND r.family_id = 1) $sql$,
  '0');
SELECT probe.eq('portal', 'allocations follow their payment',
  $sql$ SELECT count(*)::text FROM public.payment_allocations a
         WHERE NOT EXISTS (SELECT 1 FROM public.payments p
                            WHERE p.id = a.payment_id AND p.family_id = 1) $sql$,
  '0');

-- He is billed BY these figures, so withholding them would make his own
-- statement unreadable.
SELECT probe.eq('portal', 'he can read the association settings',
  $sql$ SELECT count(*)::text FROM public.association_settings $sql$, '1');
-- And these are none of his business.
SELECT probe.eq('portal', 'the audit trail is closed to him',
  $sql$ SELECT count(*)::text FROM public.audit_log $sql$, '0');
SELECT probe.eq('portal', 'access codes are closed to him, including his own',
  $sql$ SELECT count(*)::text FROM public.family_access_codes $sql$, '0');
SELECT probe.eq('portal', 'he sees only his own profile row',
  $sql$ SELECT count(*)::text FROM public.profiles $sql$, '1');

-- The nested reads the portal screen calls. SECURITY INVOKER, so RLS decides:
-- his own family answers, another family returns nothing at all.
SELECT probe.eq('portal', 'api_family_detail answers for his own family',
  $sql$ SELECT public.api_family_detail(1) -> 'family' ->> 'familyCode' $sql$,
  'F-0001');
SELECT probe.eq('portal', 'api_family_detail is null for another family',
  $sql$ SELECT coalesce((public.api_family_detail(2))::text, 'null') $sql$, 'null');
SELECT probe.eq('portal', 'his statement has his own movements',
  $sql$ SELECT (jsonb_array_length(
          public.api_family_statement(1) -> 'movements') > 0)::text $sql$, 'true');
SELECT probe.eq('portal', 'another family statement is empty for him',
  $sql$ SELECT jsonb_array_length(
          public.api_family_statement(2) -> 'movements')::text $sql$, '0');

-- READ ONLY is the whole feature. Collection stays with the treasurer, and the
-- refusals come from require_role() inside each RPC, not from hiding a button.
SELECT probe.raises('portal', 'he cannot register a payment',
  $sql$ SELECT public.register_payment(1, 1.00, 'نقداً') $sql$, 'RUL00');
SELECT probe.raises('portal', 'he cannot edit his own family',
  $sql$ SELECT public.save_family(1, '{"fullName":"x","nationalId":"y"}'::jsonb) $sql$,
  'RUL00');
SELECT probe.raises('portal', 'he cannot issue a code for another family',
  $sql$ SELECT public.issue_family_code(2) $sql$, 'RUL00');

-- He may not move himself into another household either. The guard is scoped to
-- self-change, so an admin can still correct a mis-binding.
-- 42501, not RUL00: `authenticated` holds no UPDATE on profiles at all, so he is
-- stopped by privilege before the trigger is even reached. The trigger is the
-- backstop for anything holding a SQL console; this is the front door.
SELECT probe.raises('portal', 'he cannot even attempt to rebind himself',
  $sql$ UPDATE public.profiles SET family_id = 2 WHERE id = auth.uid() $sql$, '42501');

-- ═════ And staff are not heads of family ═════════════════════════════════════
-- The other direction. If my_family_id() ever answered for staff, the
-- family-scoped policies would start matching for them too — harmless today,
-- but it would mean the two paths are no longer disjoint.
SELECT probe.become('00000000-0000-0000-0000-0000000000a4');  -- viewer
SELECT probe.eq('portal', 'a staff viewer has no family scope',
  $sql$ SELECT (public.my_family_id() IS NULL)::text $sql$, 'true');
SELECT probe.eq('portal', 'and still sees every family, as before',
  $sql$ SELECT ((SELECT count(*) FROM public.families)
              = (SELECT families FROM portal_before))::text $sql$, 'true');

RESET ROLE;

-- Put the fixture back. probe.become(NULL) first: the guard above keys on
-- auth.uid(), and the claim from the last impersonation would otherwise make
-- this cleanup look like the head of family unbinding himself.
SELECT probe.become(NULL);
DELETE FROM public.family_access_codes;
-- Deleting the auth.users rows cascades to their profiles, which is what takes
-- the family binding with them. Nothing else in the suite knows these two ever
-- existed.
DELETE FROM auth.users WHERE email IN ('head@fam.test', 'other@fam.test');
DROP TABLE code1;
DROP TABLE thecode;
DROP TABLE portal_before;
