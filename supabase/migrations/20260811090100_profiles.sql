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

-- family_id is the STAFF/FAMILY-HEAD DISCRIMINATOR, and it is deliberately a
-- nullable column rather than a new app_role value.
--
--   NULL      → association staff. `role` means what it always meant.
--   NOT NULL  → a head of family who redeemed an access code. He is not on the
--               staff ladder at all: my_role() returns NULL for him, so every
--               existing policy (all of which go through has_role) denies him,
--               and the family-scoped policies added in 20260811090500 are the
--               only ones that let him see anything.
--
-- Why not `ALTER TYPE app_role ADD VALUE 'familyHead'`: the new label cannot be
-- USED in the transaction that adds it, and this schema is applied as one
-- transaction (supabase/APPLY_TO_SUPABASE.sql). role_rank() would have to
-- reference the label immediately and the apply would fail. A column has no such
-- rule, and it also expresses the truth better — "which family" is data, not a
-- rank.
--
-- ON DELETE CASCADE, not SET NULL: if the family is purged, the head's profile
-- must not silently fall back to being staff. Cascade removes his profile
-- outright, and auth.users keeps the identity so he can be re-issued a code.
CREATE TABLE public.profiles (
  id            uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         text        NOT NULL,
  display_name  text        NOT NULL DEFAULT '',
  picture_url   text,
  role          app_role    NOT NULL DEFAULT 'viewer',
  status        app_status  NOT NULL DEFAULT 'pending',
  family_id     bigint,
  approved_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at   timestamptz,
  last_login_at timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_profiles_email UNIQUE (email),
  -- A family head is a viewer with a family. Any other combination would give
  -- someone both a staff rank and a family scope, and my_role() would silently
  -- pick one — so it is refused outright instead.
  CONSTRAINT ck_profiles_family_head
    CHECK (family_id IS NULL OR role = 'viewer')
);

CREATE INDEX ix_profiles_family ON public.profiles (family_id);

CREATE INDEX ix_profiles_status ON public.profiles (status, role);

CREATE TRIGGER trg_profiles_touch
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- New accounts land as viewer/pending, exactly as 001_users.sql defaulted them,
-- so a Google sign-in grants no access until an admin approves it.
--
-- A trigger on auth.users, not a client insert: if the app created its own
-- profile row it could choose its own role, and the anon key is public.
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name, picture_url)
  VALUES (
    NEW.id,
    coalesce(NEW.email, ''),
    coalesce(NEW.raw_user_meta_data ->> 'full_name',
             NEW.raw_user_meta_data ->> 'name',
             split_part(coalesce(NEW.email, ''), '@', 1)),
    NEW.raw_user_meta_data ->> 'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Rule: nobody may promote themselves, and the last admin cannot be demoted or
-- locked out. Both were app-layer checks in api/src/users/routes.ts; with no
-- app layer they have to be here or they do not exist.
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

CREATE TRIGGER trg_profiles_guard
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_profile_change();

-- ── Role resolution ─────────────────────────────────────────────────────────
-- Deferred from 20260811090000 because these read the table above.

-- NULL for an unauthenticated caller, a suspended account, one still pending
-- approval, OR a head of family — so `>=` comparisons against it are NULL, never
-- true. Fail-closed by construction rather than by remembering to check.
--
-- `family_id IS NULL` is what keeps the family-head feature from needing a single
-- edit to any existing policy. Every staff policy in 20260811090500 reads
-- has_role(...), has_role reads my_role, and my_role refuses to answer for a
-- family head — so the eight policies that grant association-wide reads exclude
-- him automatically, and cannot be forgotten one at a time.
CREATE OR REPLACE FUNCTION public.my_role() RETURNS app_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.role
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.family_id IS NULL
$$;

-- The family a head of family may see, and NULL for everyone else — including
-- staff, so an admin cannot accidentally read through the family-scoped
-- policies as though he were a member of some family.
--
-- SECURITY DEFINER for the same reason my_role() is: a policy ON profiles that
-- selects FROM profiles re-enters its own policy and Postgres raises "infinite
-- recursion detected in policy".
CREATE OR REPLACE FUNCTION public.my_family_id() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.family_id
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
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
