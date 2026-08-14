-- ============================================================================
--  ADD_FAMILY_PORTAL.sql — bring an EXISTING project up to the family portal.
--
--  A fresh project needs nothing from this file: APPLY_TO_SUPABASE.sql already
--  contains all of it. This is the incremental path for a project that was
--  created before the portal existed, where CREATE TABLE would fail.
--
--  WHAT IT ADDS
--    profiles.family_id        the staff / head-of-family discriminator
--    family_access_codes       one code per family, admin-readable only
--    my_family_id()            the caller's own family, NULL for staff
--    my_role()                 now returns NULL for a head of family, which is
--                              what excludes him from every staff policy
--    7 family-scoped RLS policies + settings + the codes table
--    issue_family_code()       admin issues/regenerates a code
--    redeem_family_code()      a head of family binds his own account
--    api_me()                  now reports familyId / familyCode
--    v_users                   now reports familyCode
--    purge_all_data()          now clears heads of family with their families
--
--  HOW TO APPLY
--    Supabase dashboard → SQL Editor → New query → paste ALL of this → Run.
--    One transaction, ending in the lockdown assertion, so any mistake rolls
--    the whole thing back rather than leaving a function exposed.
--
--  Re-running is harmless: every statement is IF NOT EXISTS, CREATE OR REPLACE,
--  DROP-then-CREATE, or a grant.
--
--  AFTERWARDS, IN THE DASHBOARD
--    Authentication → Providers → Google must be ON. A head of family signs in
--    with Google and then types his code; without the provider there is no way
--    for him to sign in at all.
-- ============================================================================

BEGIN;

-- ── Schema ───────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS family_id bigint;

DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT fk_profiles_family
    FOREIGN KEY (family_id) REFERENCES public.families(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.profiles ADD CONSTRAINT ck_profiles_family_head
    CHECK (family_id IS NULL OR role = 'viewer');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS ix_profiles_family ON public.profiles (family_id);

CREATE TABLE IF NOT EXISTS public.family_access_codes (
  family_id   bigint      PRIMARY KEY REFERENCES public.families(id) ON DELETE CASCADE,
  code        text        NOT NULL,
  issued_at   timestamptz NOT NULL DEFAULT now(),
  issued_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  redeemed_at timestamptz,
  redeemed_by uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,

  CONSTRAINT uq_family_code UNIQUE (code),
  CONSTRAINT ck_family_code_len CHECK (char_length(code) BETWEEN 8 AND 64)
);
ALTER TABLE public.family_access_codes ENABLE ROW LEVEL SECURITY;

-- ── Role resolution: my_role() now excludes a head of family ─────────────
CREATE OR REPLACE FUNCTION public.my_role() RETURNS app_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.role
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.family_id IS NULL
$$;

CREATE OR REPLACE FUNCTION public.my_family_id() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.family_id
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
$$;

-- ── The self-change guard now permits redemption ─────────────────────────
CREATE OR REPLACE FUNCTION public.guard_profile_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  -- Redeeming an access code is the ONE self-change that has to be allowed:
  -- pending → approved, performed by the caller on his own row, inside
  -- redeem_family_code(). It is recognisable precisely because the row is
  -- ACQUIRING a family binding at the same moment, and it grants nothing — the
  -- role stays 'viewer', and my_role() returns NULL for anyone holding a
  -- family_id, so the account ends up with strictly less reach than before.
  --
  -- NULL → NOT NULL only. Moving between families is still refused below.
  v_redeeming boolean := OLD.family_id IS NULL
                     AND NEW.family_id IS NOT NULL
                     AND OLD.role = 'viewer'
                     AND NEW.role = 'viewer';
BEGIN
  -- Self-elevation. current_user is postgres/service_role during seeding and
  -- migrations, where this guard must not apply.
  IF auth.uid() IS NOT NULL AND NEW.id = auth.uid()
     AND NOT v_redeeming
     AND (NEW.role IS DISTINCT FROM OLD.role
          OR NEW.status IS DISTINCT FROM OLD.status) THEN
    RAISE EXCEPTION 'FORBIDDEN: cannot change your own role or status'
      USING ERRCODE = 'RUL00';
  END IF;

  -- family_id is only PARTLY exempt from the self-change rule above. Acquiring a
  -- binding is a self-change and is the whole point of redeem_family_code(), so
  -- NULL → a family has to be allowed. Changing one you already have must not
  -- be: that is a head of family moving himself into another household, or out
  -- of the family scope and back onto the staff ladder.
  --
  -- Scoped to `NEW.id = auth.uid()` deliberately. An ADMIN must still be able to
  -- correct a mis-binding — someone who redeemed the wrong code, or a household
  -- that changed hands — and forbidding it outright would leave no way to do so
  -- short of deleting the account and losing its sign-in history.
  IF auth.uid() IS NOT NULL AND NEW.id = auth.uid()
     AND OLD.family_id IS NOT NULL
     AND NEW.family_id IS DISTINCT FROM OLD.family_id THEN
    RAISE EXCEPTION 'FORBIDDEN: cannot change your own family binding'
      USING ERRCODE = 'RUL00';
  END IF;

  -- Last approved admin standing.
  IF (OLD.role = 'admin' AND OLD.status = 'approved')
     AND (NEW.role IS DISTINCT FROM 'admin' OR NEW.status IS DISTINCT FROM 'approved')
     AND (SELECT count(*) FROM public.profiles
           WHERE role = 'admin' AND status = 'approved' AND id <> OLD.id) = 0 THEN
    RAISE EXCEPTION 'FORBIDDEN: the last approved admin cannot be removed'
      USING ERRCODE = 'RUL00';
  END IF;

  RETURN NEW;
END $$;

-- ── Family-scoped read policies ──────────────────────────────────────────
-- Dropped first so re-running this file is safe; CREATE POLICY has no OR REPLACE.
DROP POLICY IF EXISTS read_own_family ON public.families;
DROP POLICY IF EXISTS read_own_members ON public.members;
DROP POLICY IF EXISTS read_own_receivables ON public.receivables;
DROP POLICY IF EXISTS read_own_receivable_lines ON public.receivable_lines;
DROP POLICY IF EXISTS read_own_payments ON public.payments;
DROP POLICY IF EXISTS read_own_allocations ON public.payment_allocations;
DROP POLICY IF EXISTS read_own_cash ON public.cash_movements;
DROP POLICY IF EXISTS read_settings_family ON public.association_settings;
DROP POLICY IF EXISTS read_family_codes ON public.family_access_codes;

-- ── The family portal: a head of family sees his OWN family, and nothing else ─
--
-- A second, narrower way in. Everything above answers "is the caller staff?"
-- through has_role(); everything here answers "which family is the caller the
-- head of?" through my_family_id(). The two are mutually exclusive by
-- construction, because my_role() returns NULL as soon as profiles.family_id is
-- set — so a head of family fails every policy above without any of them being
-- edited, and staff get NULL from my_family_id() so they never match a policy
-- below.
--
-- Postgres ORs multiple permissive policies on the same command, which is
-- exactly right here: a row is visible if the caller is staff OR it belongs to
-- the caller's family. Neither policy has to know the other exists.
--
-- READ ONLY, and that is the whole feature. There is no INSERT/UPDATE/DELETE
-- policy for a family head any more than there is for an admin — collection
-- stays with the treasurer, through register_payment(), which begins with
-- require_role('treasurer') and therefore refuses a head of family outright.
--
-- The two link tables are scoped through their parent rather than by a column of
-- their own: receivable_lines has no family_id, and payment_allocations has
-- none either. Scoping them by EXISTS against the parent means they cannot drift
-- out of step with the receivable or payment they belong to.

CREATE POLICY read_own_family ON public.families
  FOR SELECT TO authenticated USING (id = public.my_family_id());

CREATE POLICY read_own_members ON public.members
  FOR SELECT TO authenticated USING (family_id = public.my_family_id());

CREATE POLICY read_own_receivables ON public.receivables
  FOR SELECT TO authenticated USING (family_id = public.my_family_id());

CREATE POLICY read_own_receivable_lines ON public.receivable_lines
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.receivables r
             WHERE r.id = receivable_lines.receivable_id
               AND r.family_id = public.my_family_id()));

CREATE POLICY read_own_payments ON public.payments
  FOR SELECT TO authenticated USING (family_id = public.my_family_id());

CREATE POLICY read_own_allocations ON public.payment_allocations
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.payments p
             WHERE p.id = payment_allocations.payment_id
               AND p.family_id = public.my_family_id()));

CREATE POLICY read_own_cash ON public.cash_movements
  FOR SELECT TO authenticated USING (family_id = public.my_family_id());

-- The association's name, currency and monthly fees. He is being billed by these
-- figures, so withholding them would make his own statement unreadable. The
-- officials' names and phones travel with them, which is intended — that is who
-- he pays.
CREATE POLICY read_settings_family ON public.association_settings
  FOR SELECT TO authenticated USING (public.my_family_id() IS NOT NULL);

-- Deliberately NOT extended to a family head: audit_log (it names other people's
-- transactions), profiles beyond his own row (read_own_profile already covers
-- that), and family_access_codes (below).

-- ── family_access_codes: admins only, and only through the RPCs ──────────────
-- No SELECT for anyone but an admin. A head of family must never be able to read
-- his own row, let alone anyone else's: the code is the credential, and the
-- table holds every family's in plaintext (see the table's header for why).
ALTER TABLE public.family_access_codes ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.family_access_codes TO authenticated;
CREATE POLICY read_family_codes ON public.family_access_codes
  FOR SELECT TO authenticated USING (public.has_role('admin'));

GRANT SELECT ON public.family_access_codes TO authenticated;

-- ── The two portal RPCs, and the wider purge it changed ──────────────────
CREATE OR REPLACE FUNCTION public.issue_family_code(p_family_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_alphabet CONSTANT text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_code text := '';
  v_code_fmt text;
  v_family record;
  i int;
BEGIN
  PERFORM public.require_role('admin');

  SELECT id, family_code INTO v_family FROM public.families WHERE id = p_family_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'FAMILY_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  FOR i IN 1..12 LOOP
    -- random() is not cryptographic. It does not need to be: the row is written
    -- under a UNIQUE constraint, the code is delivered out of band, and the
    -- worst case for a predicted code is read-only sight of one family's own
    -- figures. gen_random_bytes would drag in pgcrypto for that.
    v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
  END LOOP;

  -- Grouped for reading aloud. redeem_family_code strips the dashes back out,
  -- so what the admin sees and what the head of family types are the same thing.
  v_code_fmt := substr(v_code,1,4) || '-' || substr(v_code,5,4) || '-' || substr(v_code,9,4);

  INSERT INTO public.family_access_codes (family_id, code, issued_by)
  VALUES (p_family_id, v_code, auth.uid())
  ON CONFLICT (family_id) DO UPDATE SET
    code = excluded.code, issued_at = now(), issued_by = excluded.issued_by,
    -- Cleared: this is a NEW code, and it has not been redeemed.
    redeemed_at = NULL, redeemed_by = NULL;

  PERFORM public.write_audit('family.code.issue',
    format('إصدار رمز دخول للعائلة %s', v_family.family_code), v_family.family_code);

  RETURN jsonb_build_object(
    'familyId', p_family_id, 'familyCode', v_family.family_code, 'code', v_code_fmt);
END $$;

CREATE OR REPLACE FUNCTION public.redeem_family_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_norm   text;
  v_row    record;
  v_me     record;
  v_family record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً' USING ERRCODE = 'RUL14';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  IF v_me.role <> 'viewer' THEN
    RAISE EXCEPTION 'هذا الحساب حساب إداري ولا يمكن ربطه بعائلة'
      USING ERRCODE = 'RUL14';
  END IF;

  -- Typed by a person off a phone screen: dashes, spaces and lower case are all
  -- expected and none of them are part of the code.
  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));

  SELECT * INTO v_row FROM public.family_access_codes WHERE code = v_norm;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رمز الدخول غير صحيح' USING ERRCODE = 'RUL14';
  END IF;

  -- One code, one household. A second person redeeming the same code would get
  -- his own read-only view of the same family — which is a decision for the
  -- admin to make by reissuing, not something a forwarded WhatsApp message
  -- should be able to do.
  IF v_row.redeemed_at IS NOT NULL AND v_row.redeemed_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'هذا الرمز مستعمل بالفعل، اطلب رمزاً جديداً'
      USING ERRCODE = 'RUL14';
  END IF;

  UPDATE public.profiles
     SET family_id = v_row.family_id,
         status    = 'approved',
         role      = 'viewer'
   WHERE id = auth.uid();

  UPDATE public.family_access_codes
     SET redeemed_at = now(), redeemed_by = auth.uid()
   WHERE family_id = v_row.family_id;

  SELECT family_code INTO v_family FROM public.families WHERE id = v_row.family_id;

  PERFORM public.write_audit('family.code.redeem',
    format('ربط حساب %s بالعائلة %s', v_me.email, v_family.family_code),
    v_family.family_code);

  RETURN jsonb_build_object(
    'familyId', v_row.family_id, 'familyCode', v_family.family_code);
END $$;

CREATE OR REPLACE FUNCTION public.purge_all_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv   bigint;
  v_lines  bigint;
  v_pay    bigint;
  v_alloc  bigint;
  v_cash   bigint;
  v_audit  bigint;
  v_fam    bigint;
  v_mem    bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- Distinct from purge_financial_data's phrase ON PURPOSE. See above.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح كل البيانات' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  SELECT count(*) INTO v_recv   FROM public.receivables;
  SELECT count(*) INTO v_lines  FROM public.receivable_lines;
  SELECT count(*) INTO v_pay    FROM public.payments;
  SELECT count(*) INTO v_alloc  FROM public.payment_allocations;
  SELECT count(*) INTO v_cash   FROM public.cash_movements;
  SELECT count(*) INTO v_audit  FROM public.audit_log;
  SELECT count(*) INTO v_fam    FROM public.families;
  SELECT count(*) INTO v_mem    FROM public.members;

  -- ── Why families and members are DELETEd while the six financial tables are
  -- TRUNCATEd ────────────────────────────────────────────────────────────────
  -- profiles.family_id references families, and TRUNCATE refuses whenever ANY
  -- table outside its list carries a foreign key into one being truncated —
  -- the constraint's existence is what it checks, not whether rows remain. So
  -- emptying profiles first does not help: it still dies with 0A000 "cannot
  -- truncate a table referenced in a foreign key constraint". Listing profiles
  -- would delete the association's own staff accounts, and CASCADE would do the
  -- same silently.
  --
  -- DELETE has no such rule, and neither families nor members carries a
  -- refuse_delete trigger — that guard is on the five financial tables, which
  -- keep their TRUNCATE. The identities are then restarted by hand, because
  -- that is the part RESTART IDENTITY was doing and the reason the next family
  -- must be F-0001.
  --
  -- Heads of family go first and go entirely: their family is being erased, so
  -- leaving the profile would leave a dangling scope. auth.users survives, so
  -- the same person can sign in again and redeem a fresh code later.
  DELETE FROM public.profiles WHERE family_id IS NOT NULL;

  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivable_lines,
           public.receivables,
           public.audit_log
    RESTART IDENTITY;

  DELETE FROM public.members;
  DELETE FROM public.families;

  ALTER TABLE public.members  ALTER COLUMN id RESTART WITH 1;
  ALTER TABLE public.families ALTER COLUMN id RESTART WITH 1;

  RETURN jsonb_build_object(
    'receivables',     v_recv,
    'receivableLines', v_lines,
    'payments',        v_pay,
    'allocations',     v_alloc,
    'cashMovements',   v_cash,
    'auditEntries',    v_audit,
    'families',        v_fam,
    'members',         v_mem);
END $$;

-- ── Reads that now report the family ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.api_me() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', p.id::text,
    'email', p.email,
    'displayName', p.display_name,
    'pictureUrl', p.picture_url,
    'role', p.role::text,
    'status', p.status::text,
    'familyId', p.family_id,
    'familyCode', (SELECT f.family_code FROM public.families f WHERE f.id = p.family_id))
  FROM public.profiles p WHERE p.id = auth.uid()
$$;

CREATE OR REPLACE VIEW public.v_users WITH (security_invoker = on) AS
SELECT
  p.id::text            AS "id",
  p.email               AS "email",
  p.display_name        AS "displayName",
  p.role::text          AS "role",
  p.status::text        AS "status",
  to_char(p.last_login_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                        AS "lastLoginAt",
  approver.display_name AS "approvedByName",
  -- NULL for staff. Non-NULL marks a head of family, who stores `viewer` in
  -- `role` and would otherwise be indistinguishable on the users screen from a
  -- real viewer — while actually seeing far less, and something different.
  fam.family_code       AS "familyCode"
FROM public.profiles p
LEFT JOIN public.profiles approver ON approver.id = p.approved_by
LEFT JOIN public.families fam ON fam.id = p.family_id;

-- ── The allow-list, restated ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    -- Role helpers. The RLS policies call these, so they must be executable by
    -- the caller whose policy is being evaluated. They leak nothing beyond that
    -- caller's own role.
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    -- Answers only for the caller's own family binding, and the family-scoped
    -- policies call it, so the caller whose policy is being evaluated must hold
    -- EXECUTE — otherwise every one of those policies ERRORS instead of denying,
    -- and the failure surfaces as "permission denied for function my_family_id"
    -- on screens that have nothing to do with the family portal.
    'my_family_id()',

    -- Writes. Eleven functions, each require_role()-gated, each one transaction.
    'register_payment(bigint,numeric,pay_method,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_family(bigint,jsonb,jsonb)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    -- The two destructive ones. admin-only, and each refuses without its OWN
    -- typed phrase, so the phrase that clears the figures cannot clear the
    -- directory. They are on the list because Settings calls them directly; the
    -- reason that is safe is the same reason the other seven are — the gate is
    -- inside the body, not in who can reach it.
    'purge_financial_data(text)',
    'purge_all_data(text)',

    -- The family portal. issue_ is admin-gated; redeem_ deliberately is NOT —
    -- it is the one write a signed-in stranger may call, because until he
    -- redeems a code he has no role and no family, and the code itself is the
    -- authorisation. It refuses anyone who is already staff.
    'issue_family_code(bigint)',
    'redeem_family_code(text)',

    -- Reads. STABLE and SECURITY INVOKER, so RLS still decides what they return.
    'period_label(text)',
    'member_json(bigint)',
    'api_family_detail(bigint)',
    'api_family_statement(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_settings()',
    'api_me()',
    'api_touch_login()'
  ]::text[]
$$;

DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    -- regprocedure, NOT pg_get_function_identity_arguments(): the latter includes
    -- PARAMETER NAMES ("p_period character"), while regprocedure renders the
    -- type-only form the allow-list is written in ("generate_period(character)").
    -- Comparing against identity arguments silently matched nothing except the
    -- zero-argument functions, so fourteen were left ungranted.
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       -- Extension functions are not ours. A project with pgcrypto or uuid-ossp
       -- in `public` would otherwise lose gen_random_uuid() and friends.
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    -- PUBLIC *and* the named roles. Supabase's default privileges grant to the
    -- names, so a PUBLIC-only revoke is a no-op on a real project.
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.full_sig);

    -- Normalise: strip spaces, and drop a leading `public.` in case the role's
    -- search_path does not include public and regprocedure qualifies the name.
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      -- service_role too: it is a trusted server-side context, and the phase-4
      -- legacy import needs the write functions.
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;

SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed.
SELECT p.oid::regprocedure::text AS installed,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS app_can_call,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_can_call
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
   AND p.proname IN ('issue_family_code','redeem_family_code','my_family_id')
 ORDER BY p.proname;
