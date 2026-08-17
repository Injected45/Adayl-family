-- 20260811090100_profiles.sql
-- Replaces api/migrations/001_users.sql and 002_refresh_tokens.sql.
--
-- `users` is gone. Supabase Auth owns identity in auth.users, so this table
-- carries only what the association adds on top: role and approval state.
-- The primary key IS auth.users.id, which makes auth.uid() a direct key lookup
-- in every RLS policy and removes the id-mapping layer entirely.
--
-- `refresh_tokens` is gone with no replacement. GoTrue owns refresh rotation
-- and reuse detection. See docs/SUPABASE_MIGRATION_PLAN.md for what that costs:
-- the `replaced_by` chain that distinguished rotation from logout is not
-- something GoTrue exposes.
--
-- google_sub is not stored. It was the identity key precisely because it is
-- immutable while an email can be reassigned inside a Workspace domain; that
-- reasoning now lives in auth.identities, which GoTrue maintains.

-- adeel_id is the STAFF/عديل DISCRIMINATOR, and it is deliberately a nullable
-- column rather than a new app_role value.
--
--   NULL      → association staff. `role` means what it always meant.
--   NOT NULL  → an عديل who redeemed an access code to see his own subscription.
--               He is not on the staff ladder at all: my_role() returns NULL for
--               him, so every existing policy (all of which go through has_role)
--               denies him, and the عديل-scoped policies added in
--               20260811090500 are the only ones that let him see anything.
--
-- Why not `ALTER TYPE app_role ADD VALUE 'adeel'`: the new label cannot be USED
-- in the transaction that adds it, and this schema is applied as one transaction
-- (supabase/APPLY_TO_SUPABASE.sql). role_rank() would have to reference the
-- label immediately and the apply would fail. A column has no such rule, and it
-- also expresses the truth better — "which عديل" is data, not a rank.
--
-- ON DELETE CASCADE, not SET NULL: if the عديل is purged, his profile must not
-- silently fall back to being staff. Cascade removes the profile outright, and
-- auth.users keeps the identity so he can be re-issued a code.
CREATE TABLE public.profiles (
  id            uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         text        NOT NULL,
  display_name  text        NOT NULL DEFAULT '',
  picture_url   text,
  role          app_role    NOT NULL DEFAULT 'viewer',
  status        app_status  NOT NULL DEFAULT 'pending',
  adeel_id      bigint,
  -- ── The one device this عديل's portal opens on ───────────────────────────
  -- A hash of a per-device identifier, claimed when he redeems his code and
  -- compared on every request thereafter by my_adeel_id(). NULL means "not yet
  -- claimed", which is a REFUSAL, not a pass: see that function.
  --
  -- Staff never have one. Their reach is decided by `role`, and locking an
  -- admin to a handset would strand the association the first time a phone was
  -- replaced.
  --
  -- Not a MAC address, which is what was asked for and is no longer obtainable:
  -- Android has returned 02:00:00:00:00:00 to every app since API 23 and
  -- randomises it per network since 10, and iOS never exposed it at all. What
  -- the client sends is ANDROID_ID (or identifierForVendor), hashed — the
  -- closest stable thing the platform still gives out.
  device_id     text,
  approved_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at   timestamptz,
  last_login_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_profiles_email UNIQUE (email),
  -- An عديل on the portal is a viewer bound to one row. Any other combination
  -- would give someone both a staff rank and a portal scope, and my_role() would
  -- silently pick one — so it is refused outright instead.
  CONSTRAINT ck_profiles_adeel_portal
    CHECK (adeel_id IS NULL OR role = 'viewer')
);

CREATE INDEX ix_profiles_adeel ON public.profiles (adeel_id);

CREATE INDEX ix_profiles_status ON public.profiles (status, role);

CREATE TRIGGER trg_profiles_touch
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- New accounts land as viewer/pending, exactly as 001_users.sql defaulted them,
-- so a Google sign-in grants no access until an admin approves it.
--
-- A trigger on auth.users, not a client insert: if the app created its own
-- profile row it could choose its own role, and the anon key is public.
-- ═════════════════════════════════════════════════════════════════════════════
--  SIGNING IN MUST NEVER BREAK. Everything in this block exists for that.
--
--  This trigger is the single most fragile thing in the schema, and the reason
--  is structural: it lives on `auth.users` — GoTrue's table — but its function
--  lives in `public`. `DROP SCHEMA public CASCADE`, which RESET_AND_APPLY.sql
--  runs, therefore takes the trigger with the schema. If it does not come back,
--  the INSERT that CREATES an account raises, GoTrue answers "Database error
--  saving new user", and no new person can sign in again, by Google or by the
--  dev email/password login. It has happened on the live project.
--
--  That failure is also the worst kind to diagnose, because it is asymmetric:
--  anyone already in `auth.users` inserts nothing and signs in perfectly. So it
--  reads as "it works for me", and whoever tests it is usually already in.
--
--  Three separate guarantees now stand between that and the association:
--    1. the trigger is recreated IDEMPOTENTLY here, so any re-apply restores it
--       rather than failing on "already exists";
--    2. the function CANNOT RAISE, so no error inside it can ever block an
--       account being created;
--    3. assert_signin_intact() refuses to let any apply or patch COMMIT with
--       this broken — see 20260811091200_function_lockdown.sql.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  -- Bare ON CONFLICT DO NOTHING, not ON CONFLICT (id). The id is not the only
  -- unique thing on this table: uq_profiles_email would raise for a second
  -- account carrying an email already present — a reused address, or a phone
  -- signup where coalesce(email,'') collapses to the same empty string twice.
  -- Naming the id constraint leaves those cases raising, and a raise here is an
  -- account that cannot be created.
  INSERT INTO public.profiles (id, email, display_name, picture_url)
  VALUES (
    NEW.id,
    coalesce(NEW.email, ''),
    coalesce(NEW.raw_user_meta_data ->> 'full_name',
             NEW.raw_user_meta_data ->> 'name',
             split_part(coalesce(NEW.email, ''), '@', 1)),
    NEW.raw_user_meta_data ->> 'avatar_url'
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- DELIBERATELY SWALLOWED, and this is the one place in the schema where that
  -- is the right call. Weigh the two failures against each other:
  --
  --   raise   → GoTrue cannot create the account. The person can NEVER sign in,
  --             there is no message that says why, and no amount of retrying or
  --             reinstalling helps. Unrecoverable from the app.
  --   swallow → the account exists with no profiles row. The app already has a
  --             specific screen for exactly this (errorProfileMissing), an
  --             admin sees it, and the backfill below or the next apply repairs
  --             it in one statement. Recoverable, visible, and harmless — the
  --             row grants nothing, since a profile is viewer/pending anyway.
  --
  -- A convenience row must never be able to hold authentication hostage.
  RETURN NEW;
END $$;

-- CREATE OR REPLACE TRIGGER (PostgreSQL 14+, and Supabase is well past it),
-- deliberately in place of DROP-then-CREATE.
--
-- Both are idempotent, so re-running is a repair either way. The difference is
-- that the DROP form leaves a window — however short — in which auth.users has
-- NO trigger, and if the statement after it failed, the transaction would roll
-- back but a reader of this file would still be looking at a DROP against the
-- table sign-in depends on. There is now no statement anywhere in this schema,
-- or in any patch generated from it, that removes anything from `auth`.
CREATE OR REPLACE TRIGGER trg_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── Backfill: nobody who already has an account is left without a profile ────
-- The trigger fires on INSERT into auth.users and nothing else. So after a
-- reset — which empties `public` but leaves `auth.users` standing — every
-- existing member has an account and NO profile, and signing in does not create
-- one, because signing in inserts nothing. They would each be stuck on
-- "this account has no row in the database" with no way out from the app.
--
-- On a genuinely fresh project auth.users is empty and this does nothing.
--
-- Everyone lands viewer/pending, exactly as the trigger would have made them.
-- NO access is granted here: the first admin is still a deliberate manual step
-- (supabase/bootstrap_first_admin.sql).
INSERT INTO public.profiles (id, email, display_name, picture_url)
SELECT u.id,
       coalesce(u.email, ''),
       coalesce(u.raw_user_meta_data ->> 'full_name',
                u.raw_user_meta_data ->> 'name',
                split_part(coalesce(u.email, ''), '@', 1)),
       u.raw_user_meta_data ->> 'avatar_url'
  FROM auth.users u
 WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
ON CONFLICT DO NOTHING;

-- Rule: nobody may promote themselves, and the last admin cannot be demoted or
-- locked out. Both were app-layer checks in api/src/users/routes.ts; with no
-- app layer they have to be here or they do not exist.
CREATE OR REPLACE FUNCTION public.guard_profile_change() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  -- Redeeming an access code is the ONE self-change that has to be allowed:
  -- pending → approved, performed by the caller on his own row, inside
  -- redeem_adeel_code(). It is recognisable precisely because the row is
  -- ACQUIRING an عديل binding at the same moment, and it grants nothing — the
  -- role stays 'viewer', and my_role() returns NULL for anyone holding an
  -- adeel_id, so the account ends up with strictly less reach than before.
  --
  -- NULL → NOT NULL only. Rebinding to a different عديل is still refused below.
  v_redeeming boolean := OLD.adeel_id IS NULL
                     AND NEW.adeel_id IS NOT NULL
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

  -- adeel_id is only PARTLY exempt from the self-change rule above. Acquiring a
  -- binding is a self-change and is the whole point of redeem_adeel_code(), so
  -- NULL → an عديل has to be allowed. Changing one you already have must not be:
  -- that is someone moving himself onto another عديل's ledger, or out of the
  -- portal scope and back onto the staff ladder.
  --
  -- Scoped to `NEW.id = auth.uid()` deliberately. An ADMIN must still be able to
  -- correct a mis-binding — someone who redeemed the wrong code — and forbidding
  -- it outright would leave no way to do so short of deleting the account and
  -- losing its sign-in history.
  IF auth.uid() IS NOT NULL AND NEW.id = auth.uid()
     AND OLD.adeel_id IS NOT NULL
     AND NEW.adeel_id IS DISTINCT FROM OLD.adeel_id THEN
    RAISE EXCEPTION 'FORBIDDEN: cannot change your own عديل binding'
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

CREATE TRIGGER trg_profiles_guard
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_change();

-- ── Role resolution ─────────────────────────────────────────────────────────
-- Deferred from 20260811090000 because these read the table above.

-- NULL for an unauthenticated caller, a suspended account, one still pending
-- approval, OR an عديل on the portal — so `>=` comparisons against it are NULL,
-- never true. Fail-closed by construction rather than by remembering to check.
--
-- `adeel_id IS NULL` is what keeps the portal feature from needing a single edit
-- to any existing policy. Every staff policy in 20260811090500 reads
-- has_role(...), has_role reads my_role, and my_role refuses to answer for an
-- عديل — so the policies that grant association-wide reads exclude him
-- automatically, and cannot be forgotten one at a time.
CREATE OR REPLACE FUNCTION public.my_role() RETURNS app_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.role
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.adeel_id IS NULL
$$;

-- The عديل a portal user may see, and NULL for everyone else — including staff,
-- so an admin cannot accidentally read through the عديل-scoped policies as
-- though he were one.
--
-- SECURITY DEFINER for the same reason my_role() is: a policy ON profiles that
-- selects FROM profiles re-enters its own policy and Postgres raises "infinite
-- recursion detected in policy".
-- ── ONE عديل, ONE DEVICE ────────────────────────────────────────────────────
-- Every عديل-scoped RLS policy goes through this function, so the device check
-- belongs here and nowhere else: put it in the portal's read functions instead
-- and a client talking to PostgREST directly would walk straight past it.
-- Returning NULL is the whole enforcement — a NULL adeel_id matches no row, so
-- the wrong device sees an empty portal rather than a refused one.
--
-- `request.headers` is what PostgREST publishes for the current request, so
-- `x-device-id` is whatever the app put in its header. That makes this a lock
-- against SHARING — the member opening his account on a second handset, or
-- handing his Google password to a cousin — and NOT against a determined
-- attacker with the anon key, who can put any string in a header he likes. It
-- is worth saying plainly: the code is the authorisation, the device is a
-- constraint on convenience, and no header can ever be more than that.
--
-- Three states, and the middle one is the one to get right:
--
--   device_id IS NULL      → REFUSE. "Not yet claimed", which is what an
--                            account looks like the instant an admin reissues
--                            a code to release a lost phone. Treating it as a
--                            pass would make reissuing an unlock for EVERY
--                            device at once, which is the opposite of the
--                            feature. api_touch_login() claims it on the next
--                            launch from the phone that actually has the code.
--   device_id = header     → allow.
--   device_id <> header    → refuse.
--
-- Staff are unaffected: they have no adeel_id, so this returns NULL for them
-- exactly as it always did, and my_role() — which they DO go through — never
-- looks at device_id.
-- The header, isolated so there is one definition of "which device is asking".
--
-- Declared BEFORE my_adeel_id() on purpose: `check_function_bodies` is on, so a
-- SQL function that calls one Postgres has not seen yet fails at CREATE time
-- and takes the apply with it.
--
-- `true` on current_setting means "NULL if unset" rather than an error. The
-- setting does not exist at all outside a PostgREST request — in psql, in the
-- probe suite, during a migration — and throwing there would be a function that
-- only works in production.
CREATE OR REPLACE FUNCTION public.request_device_id() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT nullif(
    btrim(coalesce(
      current_setting('request.headers', true)::json ->> 'x-device-id', '')),
    '')
$$;

CREATE OR REPLACE FUNCTION public.my_adeel_id() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.adeel_id
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.device_id IS NOT NULL
     AND p.device_id = public.request_device_id()
$$;

CREATE OR REPLACE FUNCTION public.has_role(minimum app_role) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT coalesce(public.role_rank(public.my_role()) >= public.role_rank(minimum), false)
$$;

-- Raise rather than return false, so an RPC body cannot forget to branch.
CREATE OR REPLACE FUNCTION public.require_role(minimum app_role) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  IF NOT public.has_role(minimum) THEN
    RAISE EXCEPTION 'FORBIDDEN: requires % or higher', minimum
      USING ERRCODE = 'RUL00';
  END IF;
END $$;
