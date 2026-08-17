-- 20260811090500_rls.sql — the security boundary.
--
-- This file is what replaces `api/src/auth/middleware.ts` and every per-route
-- role guard. Read it as the answer to one question: "a hostile client holds the
-- anon key and can call anything — what stops it?"
--
-- The shape is deliberate and it is not the obvious one:
--
--   READS  go direct to tables and views, gated by RLS on role.
--   WRITES do not exist. anon and authenticated hold NO INSERT, UPDATE or
--          DELETE privilege on any table, and no table carries a write policy.
--          Every mutation goes through a SECURITY DEFINER function that checks
--          the caller's role and enforces the rule before touching a row.
--
-- Why withhold writes entirely rather than write careful per-table policies: a
-- policy can only judge the row in front of it. It cannot see that this INSERT
-- into payment_allocations is the third of five that must all land or none, nor
-- that receivables.paid must move by exactly the same amount. The nine
-- transactional endpoints were transactional for a reason, and a policy has no
-- way to express it. Funnelling writes through functions keeps the transaction
-- boundary that the API owned.

-- ── Baseline privileges ──────────────────────────────────────────────────────
-- Supabase grants ALL on new objects in public to anon and authenticated via
-- default privileges. Revoke first, then grant back only SELECT.
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon, authenticated;

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- ── RLS on, everywhere, with no exceptions ───────────────────────────────────
-- A table with RLS enabled and no matching policy denies. Enabling it on every
-- table means a table added later without a policy fails closed, not open.
ALTER TABLE public.profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.association_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.adeels               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receivables          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.closed_periods       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_movements       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.disbursements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log            ENABLE ROW LEVEL SECURITY;

-- ── SELECT: viewer and above ─────────────────────────────────────────────────
-- has_role() returns false for anon, for a suspended account, and for one still
-- pending admin approval, because my_role() returns NULL unless status =
-- 'approved'. "Sign in and you are in" becomes "sign in and wait to be let in",
-- which is the behaviour api/src/auth/middleware.ts had.

GRANT SELECT ON
  public.association_settings, public.adeels,
  public.receivables, public.closed_periods, public.payments,
  public.payment_allocations, public.cash_movements,
  public.disbursements
TO authenticated;

CREATE POLICY read_settings ON public.association_settings
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_adeels ON public.adeels
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_receivables ON public.receivables
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
-- Which months are closed is association-wide bookkeeping, not anybody's own
-- money, so it stops at the staff boundary: no عديل-scoped policy below.
CREATE POLICY read_closed_periods ON public.closed_periods
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_payments ON public.payments
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_allocations ON public.payment_allocations
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_cash ON public.cash_movements
  FOR SELECT TO authenticated USING (public.has_role('viewer'));

-- ── Disbursements: STAFF ONLY, and deliberately not extended to an عديل ──────
-- The association asked for "شفافية مطلقة" toward its members, and it has it:
-- api_association_finance() gives every member the treasury's TOTALS, including
-- what has been spent.
--
-- The vouchers themselves are a different thing. A row here says that a named
-- person received إعانة اجتماعية — which in a family association is the most
-- private fact the system holds, and it belongs to the recipient rather than to
-- the membership. Transparency about the collective purse is not the same as
-- publishing who needed help, and conflating them would be a decision nobody
-- asked for taken on the association's behalf.
--
-- There is deliberately no عديل-scoped policy either, not even "his own": a
-- member seeing a voucher made out to him is a reasonable feature, and it is a
-- decision for the association to take on purpose rather than one that arrives
-- as a side effect of this file.
CREATE POLICY read_disbursements ON public.disbursements
  FOR SELECT TO authenticated USING (public.has_role('viewer'));

-- ── audit_log: financeManager and above ──────────────────────────────────────
-- Endpoint 29 was financeManager-gated. A treasurer seeing who cancelled what
-- is an oversight function, not a collection function.
GRANT SELECT ON public.audit_log TO authenticated;
CREATE POLICY read_audit ON public.audit_log
  FOR SELECT TO authenticated USING (public.has_role('financeManager'));

-- ── profiles ─────────────────────────────────────────────────────────────────
-- Own row always readable, otherwise admin only — a pending user must be able
-- to load /auth/me and see that they are pending, which is how the app renders
-- the waiting-for-approval screen. That read must NOT go through has_role(),
-- since has_role() is false for exactly those users.
GRANT SELECT ON public.profiles TO authenticated;
CREATE POLICY read_own_profile ON public.profiles
  FOR SELECT TO authenticated USING (id = auth.uid());
CREATE POLICY read_all_profiles ON public.profiles
  FOR SELECT TO authenticated USING (public.has_role('admin'));

-- ── The عديل portal: he sees his OWN row and his own money, nothing else ─────
--
-- A second, narrower way in. Everything above answers "is the caller staff?"
-- through has_role(); everything here answers "which عديل is the caller?"
-- through my_adeel_id(). The two are mutually exclusive by construction, because
-- my_role() returns NULL as soon as profiles.adeel_id is set — so an عديل fails
-- every policy above without any of them being edited, and staff get NULL from
-- my_adeel_id() so they never match a policy below.
--
-- Postgres ORs multiple permissive policies on the same command, which is
-- exactly right here: a row is visible if the caller is staff OR it is the
-- caller's own. Neither policy has to know the other exists.
--
-- READ ONLY, and that is the whole feature. There is no INSERT/UPDATE/DELETE
-- policy for an عديل any more than there is for an admin — collection stays with
-- the treasurer, through register_payment(), which begins with
-- require_role('treasurer') and therefore refuses him outright.
--
-- payment_allocations is scoped through its parent rather than by a column of
-- its own: it has no adeel_id. Scoping it by EXISTS against the payment means it
-- cannot drift out of step with the payment it belongs to.

CREATE POLICY read_own_adeel ON public.adeels
  FOR SELECT TO authenticated USING (id = public.my_adeel_id());

CREATE POLICY read_own_receivables ON public.receivables
  FOR SELECT TO authenticated USING (adeel_id = public.my_adeel_id());

CREATE POLICY read_own_payments ON public.payments
  FOR SELECT TO authenticated USING (adeel_id = public.my_adeel_id());

CREATE POLICY read_own_allocations ON public.payment_allocations
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.payments p
             WHERE p.id = payment_allocations.payment_id
               AND p.adeel_id = public.my_adeel_id()));

CREATE POLICY read_own_cash ON public.cash_movements
  FOR SELECT TO authenticated USING (adeel_id = public.my_adeel_id());

-- The association's name, currency and monthly fee. He is being billed by these
-- figures, so withholding them would make his own statement unreadable. The
-- officials' names and phones travel with them, which is intended — that is who
-- he pays.
CREATE POLICY read_settings_adeel ON public.association_settings
  FOR SELECT TO authenticated USING (public.my_adeel_id() IS NOT NULL);

-- Deliberately NOT extended to an عديل: audit_log (it names other people's
-- transactions), profiles beyond his own row (read_own_profile already covers
-- that), and adeel_access_codes (below).

-- ── adeel_access_codes: admins only, and only through the RPCs ───────────────
-- No SELECT for anyone but an admin. An عديل must never be able to read his own
-- row, let alone anyone else's: the code is the credential, and the table holds
-- every code in plaintext (see the table's header for why).
ALTER TABLE public.adeel_access_codes ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.adeel_access_codes TO authenticated;
CREATE POLICY read_adeel_codes ON public.adeel_access_codes
  FOR SELECT TO authenticated USING (public.has_role('admin'));

-- Deliberately absent: any INSERT, UPDATE or DELETE policy on any table.
-- If you are about to add one, the write belongs in an RPC instead.

-- ── Function execution ───────────────────────────────────────────────────────
-- Handled in 20260811090800_lockdown.sql, not here, and NOT with
-- ALTER DEFAULT PRIVILEGES.
--
-- The obvious approach is to set a default-privilege rule now so that every
-- function created by later migrations comes out locked. It does not work:
-- issued as the superuser that owns these objects,
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- is a silent no-op on PostgreSQL 16.4 — nothing lands in pg_default_acl and the
-- next function created still carries PUBLIC=EXECUTE. Verified directly; see the
-- header of the lockdown migration. Supabase runs migrations as that same kind of
-- role, so this is not a local artefact.
--
-- The privileges the read policies above depend on are granted there too, so that
-- one file holds the complete answer to "what can a client call?".
