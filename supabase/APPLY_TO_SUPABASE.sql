-- ============================================================================
--  Family App — complete schema for a fresh Supabase project.
--
--  GENERATED FILE. Do not edit. Regenerate with:
--      bash supabase/tests/bundle.sh
--  The source of truth is supabase/migrations/*.sql.
--
--  HOW TO APPLY
--    Supabase dashboard → SQL Editor → New query → paste all of this → Run.
--    It is one transaction: if anything fails, nothing is applied.
--
--  WHAT IT ASSUMES
--    A fresh project. It expects the `auth` schema, `auth.users`, and the
--    anon / authenticated / service_role roles to already exist — Supabase
--    provides all of them.
--
--  AFTER APPLYING
--    1. Authentication → Providers → Google: on, with your client ID + secret.
--    2. Authentication → URL Configuration → Redirect URLs:
--         com.family.app://login-callback
--    3. Sign in to the app once (you will see "awaiting approval").
--    4. Run supabase/bootstrap_first_admin.sql with your address.
-- ============================================================================

BEGIN;


-- ==========================================================================
-- 20260811090000_enums_and_helpers.sql
-- ==========================================================================

-- 20260811090000_enums_and_helpers.sql
--
-- Postgres port of api/migrations/*.sql. Read docs/SUPABASE_MIGRATION_PLAN.md
-- §"Translation decisions" for why each MySQL construct became what it became.
--
-- THE GOVERNING CONSTRAINT: there is no server any more. The anon key ships
-- inside the app binary and the web bundle, so a hostile client can issue any
-- PostgREST call it likes. Every business rule therefore lives here, in the
-- database. Nothing in Dart is trusted.

-- ── Enumerated types ─────────────────────────────────────────────────────────
-- MySQL inline ENUM(...) becomes a named type. The Arabic labels are the wire
-- values the Flutter app already sends (app/lib/core/domain/wire_values.dart);
-- changing them would break the client and the index.html parity oracle.

CREATE TYPE app_role       AS ENUM ('viewer','treasurer','financeManager','admin');
CREATE TYPE app_status     AS ENUM ('pending','approved','suspended');
CREATE TYPE member_kind    AS ENUM ('father','son');
CREATE TYPE member_status  AS ENUM ('نشط','موقوف','متوفى');
CREATE TYPE recv_status    AS ENUM ('غير مسدد','مسدد جزئياً','مسدد بالكامل','ملغي');
CREATE TYPE pay_method     AS ENUM ('نقداً','تحويل مصرفي');
CREATE TYPE pay_status     AS ENUM ('معتمد','ملغي');
CREATE TYPE cash_kind      AS ENUM ('تحصيل');

-- ── updated_at ───────────────────────────────────────────────────────────────
-- Postgres has no `ON UPDATE CURRENT_TIMESTAMP`, so it needs a trigger.

CREATE OR REPLACE FUNCTION public.touch_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- ── Role resolution ──────────────────────────────────────────────────────────
-- SECURITY DEFINER is not a convenience here, it is required: a policy ON
-- profiles that SELECTs FROM profiles re-enters its own policy and Postgres
-- raises "infinite recursion detected in policy". A definer-rights function
-- reads the row with RLS bypassed, which breaks the cycle.
--
-- `SET search_path` on every definer function is mandatory. Without it a caller
-- can prepend a schema they control and have the elevated body call their own
-- table instead of ours.

CREATE OR REPLACE FUNCTION public.role_rank(r app_role) RETURNS int
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE r
           WHEN 'admin'          THEN 4
           WHEN 'financeManager' THEN 3
           WHEN 'treasurer'      THEN 2
           WHEN 'viewer'         THEN 1
         END
$$;

-- my_role() / has_role() / require_role() cannot live here: a LANGUAGE sql body
-- is parsed and validated at CREATE time, and they read public.profiles, which
-- the next migration creates. They are defined at the end of
-- 20260811090100_profiles.sql instead.


-- ==========================================================================
-- 20260811090100_profiles.sql
-- ==========================================================================

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


-- ==========================================================================
-- 20260811090200_settings_families_members.sql
-- ==========================================================================

-- 20260811090200_settings_families_members.sql
-- Ports api/migrations/003, 004, 005.

-- ─────────────────────────────────────────────────────────────────────────────
-- association_settings — the singleton. Drives every FUTURE calculation and
-- never alters history: a receivable snapshots these values at creation.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.association_settings (
  id                          smallint      NOT NULL DEFAULT 1,
  association_name            text          NOT NULL DEFAULT 'مشروع جمعية العدايل',
  currency                    text          NOT NULL DEFAULT 'د.ل',
  father_fee                  numeric(12,2) NOT NULL DEFAULT 20.00,
  son_fee                     numeric(12,2) NOT NULL DEFAULT 10.00,
  eligibility_age             smallint      NOT NULL DEFAULT 16,
  warning_months              smallint      NOT NULL DEFAULT 3,
  system_start                date          NOT NULL,
  auto_close_previous_months  boolean       NOT NULL DEFAULT true,

  treasurer_name              text          NOT NULL DEFAULT '',
  treasurer_national_id       text          NOT NULL DEFAULT '',
  treasurer_phone             text          NOT NULL DEFAULT '',

  finance_manager_name        text          NOT NULL DEFAULT '',
  finance_manager_national_id text          NOT NULL DEFAULT '',
  finance_manager_phone       text          NOT NULL DEFAULT '',

  updated_by                  uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at                  timestamptz   NOT NULL DEFAULT now(),

  PRIMARY KEY (id),
  CONSTRAINT ck_settings_singleton CHECK (id = 1),
  CONSTRAINT ck_settings_fees      CHECK (father_fee >= 0 AND son_fee >= 0),
  -- MySQL's TINYINT UNSIGNED bounded these; Postgres smallint is signed, so the
  -- bound has to be stated. A negative eligibility age would make every son
  -- billable from birth.
  CONSTRAINT ck_settings_age       CHECK (eligibility_age BETWEEN 0 AND 255),
  CONSTRAINT ck_settings_warning   CHECK (warning_months  BETWEEN 0 AND 255)
);

CREATE TRIGGER trg_settings_touch
  BEFORE UPDATE ON public.association_settings
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Defaults match defaultSettings in index.html; system_start is 1 January of
-- the current year, as `new Date().getFullYear()+"-01-01"` produced.
INSERT INTO public.association_settings (id, system_start)
VALUES (1, make_date(extract(year FROM current_date)::int, 1, 1))
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- families
--
-- family_code is a GENERATED column here. MySQL forbade generated columns that
-- reference AUTO_INCREMENT, which forced the API to INSERT then UPDATE inside
-- the creating transaction. Postgres computes it from the identity value in the
-- same row, so the code cannot collide and no second statement exists to fail
-- between. (index.html used `F-${families.length+1}`, which collides outright
-- when two users create a family in the same moment.)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.families (
  id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  family_code text        GENERATED ALWAYS AS ('F-' || lpad(id::text, 4, '0')) STORED,
  legacy_id   text,
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,

  CONSTRAINT uq_families_code   UNIQUE (family_code),
  CONSTRAINT uq_families_legacy UNIQUE (legacy_id)
);

CREATE TRIGGER trg_families_touch
  BEFORE UPDATE ON public.families
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- members — fathers and sons in one table.
--
-- Flattening father{} + sons[] behind a `kind` discriminator turns business
-- rule 10 (national ID unique across ALL members) into one unique index,
-- replacing the prototype's O(n) nationalExists() scan.
--
-- "Exactly one father per family" is a PARTIAL unique index here. MySQL needed
-- a generated `father_slot` column that produced NULL for sons, exploiting the
-- fact that NULL repeats freely in a unique index. Postgres indexes a WHERE
-- clause directly, so the helper column is unnecessary.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.members (
  id              bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  family_id       bigint        NOT NULL REFERENCES public.families(id) ON DELETE RESTRICT,
  kind            member_kind   NOT NULL,
  full_name       text          NOT NULL,
  national_id     text          NOT NULL,
  phone           text,
  subscription_no text,
  dob             date,
  nationality     text          NOT NULL DEFAULT 'ليبي',
  workplace       text,
  registered_at   date          NOT NULL,
  status          member_status NOT NULL DEFAULT 'نشط',
  notes           text,
  legacy_id       text,
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now(),

  CONSTRAINT uq_members_national_id UNIQUE (national_id),
  CONSTRAINT uq_members_legacy      UNIQUE (legacy_id),
  CONSTRAINT ck_members_name        CHECK (btrim(full_name) <> ''),
  CONSTRAINT ck_members_national_id CHECK (btrim(national_id) <> '')
);

CREATE UNIQUE INDEX uq_members_one_father
  ON public.members (family_id) WHERE kind = 'father';

CREATE INDEX ix_members_family ON public.members (family_id, kind);
CREATE INDEX ix_members_dob    ON public.members (dob);
CREATE INDEX ix_members_name   ON public.members (full_name);
CREATE INDEX ix_members_status ON public.members (status);

CREATE TRIGGER trg_members_touch
  BEFORE UPDATE ON public.members
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- Rule 10, second half: date of birth cannot be in the future. A trigger, not a
-- CHECK, because CURRENT_DATE is not immutable and Postgres rejects it in a
-- CHECK constraint for the same reason MySQL did.
--
-- ⚠ CARRIED-FORWARD DECISION D2 / CONFLICT C1 (docs/MIGRATION_PLAN.md §11.2):
-- this covers fathers AND sons, which is stricter than index.html (saveFamily
-- line 309 validates sons only and never checks the father's dob). The stricter
-- reading was chosen so no bad row can enter the database. To match the
-- prototype exactly, add `AND NEW.kind = 'son'`. Still flagged, still not
-- silently settled.
CREATE OR REPLACE FUNCTION public.guard_member_dob() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.dob IS NOT NULL AND NEW.dob > current_date THEN
    RAISE EXCEPTION 'تاريخ الميلاد لا يمكن أن يكون مستقبلياً'
      USING ERRCODE = 'RUL10';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_members_dob
  BEFORE INSERT OR UPDATE ON public.members
  FOR EACH ROW EXECUTE FUNCTION public.guard_member_dob();

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles.family_id → families.id
--
-- Declared here rather than on the column, because profiles is created one
-- migration earlier than families and a REFERENCES clause cannot point forward.
-- See the header of profiles for why the family-head discriminator is a column
-- rather than a new app_role value.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD CONSTRAINT fk_profiles_family
  FOREIGN KEY (family_id) REFERENCES public.families(id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- family_access_codes — one code per family, the thing a head of family types
-- once to bind his Google account to his own family and nothing else.
--
-- PRIMARY KEY (family_id): one live code per family. Re-issuing overwrites,
-- which is what "regenerate" means and also what revokes the old code — there is
-- no second row for the previous one to keep working from.
--
-- Re-issuing does NOT sign anybody out. The binding lives on profiles.family_id
-- once redeemed; the code is only the thing that creates that binding. So an
-- admin can regenerate freely without breaking a head of family who is already in.
--
-- THE CODE IS STORED IN PLAINTEXT, deliberately, and it is worth being explicit
-- about the trade:
--   * only an admin can read this table (RLS, 20260811090500), and only through
--     an admin-gated function; anon and every other role get nothing;
--   * the admin has to be able to re-read a code to resend it over WhatsApp. A
--     hash would force "regenerate" every time the message is lost, which for a
--     non-technical treasurer is a footgun, not a safeguard;
--   * the code reaches the family head over WhatsApp anyway, so it already
--     exists in plaintext somewhere far less protected than this table.
-- What a hash WOULD buy is protection of old codes in a leaked backup. Against
-- that: the codes grant read-only access to one family's own figures, and
-- rotating every code is one button per family.
--
-- `code` is 12 characters from an unambiguous 32-letter alphabet ≈ 60 bits.
-- Guessing one over HTTPS is not a threat worth rate-limiting for; guessing it
-- offline buys the attacker one family's balance.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.family_access_codes (
  family_id   bigint      PRIMARY KEY REFERENCES public.families(id) ON DELETE CASCADE,
  code        text        NOT NULL,
  issued_at   timestamptz NOT NULL DEFAULT now(),
  issued_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  redeemed_at timestamptz,
  redeemed_by uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,

  CONSTRAINT uq_family_code UNIQUE (code),
  CONSTRAINT ck_family_code_len CHECK (char_length(code) BETWEEN 8 AND 64)
);


-- ==========================================================================
-- 20260811090300_receivables.sql
-- ==========================================================================

-- 20260811090300_receivables.sql — the immutable financial core.
-- Ports api/migrations/006 and 007.
--
-- Three business rules are made structurally impossible to violate rather than
-- merely checked in code:
--
--   Rule 4  one live receivable per (family, period)
--           → uq_recv_active_period, a PARTIAL unique index. MySQL needed a
--             generated `active_period` column that produced NULL for cancelled
--             rows; Postgres indexes `WHERE status <> 'ملغي'` directly.
--             Cancelling frees the slot while the row survives forever.
--
--   Rule 5  receivables are immutable snapshots
--           → trg_recv_snapshot_immutable rejects any UPDATE touching a
--             snapshot column, so editing association_settings CANNOT alter a
--             historical receivable regardless of application correctness.
--
--   Rule 7  a payment can never exceed what is owed
--           → ck_recv_paid. Even if an allocation bug slips past the balance
--             check, the storage engine refuses the write.
--
-- `balance` is generated, not maintained, so it cannot drift from total - paid.

CREATE TABLE public.receivables (
  id                       bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  family_id                bigint        NOT NULL REFERENCES public.families(id) ON DELETE RESTRICT,
  period                   char(7)       NOT NULL,
  period_end               date          NOT NULL,

  -- ── IMMUTABLE SNAPSHOT ────────────────────────────────────────────────────
  father_fee               numeric(12,2) NOT NULL,
  son_fee                  numeric(12,2) NOT NULL,
  father_member_id         bigint        REFERENCES public.members(id) ON DELETE SET NULL,
  father_name              text          NOT NULL,
  eligibility_age_snapshot smallint      NOT NULL,
  warning_months_snapshot  smallint      NOT NULL,
  total                    numeric(12,2) NOT NULL,
  -- ──────────────────────────────────────────────────────────────────────────

  paid                     numeric(12,2) NOT NULL DEFAULT 0.00,
  balance                  numeric(12,2) GENERATED ALWAYS AS (total - paid) STORED,
  status                   recv_status   NOT NULL DEFAULT 'غير مسدد',

  created_at               timestamptz   NOT NULL DEFAULT now(),
  created_by               uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancelled_at             timestamptz,
  cancelled_by             uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancel_reason            text,
  legacy_id                text,

  CONSTRAINT uq_recv_legacy UNIQUE (legacy_id),
  CONSTRAINT ck_recv_total  CHECK (total > 0),
  CONSTRAINT ck_recv_paid   CHECK (paid >= 0 AND paid <= total),
  CONSTRAINT ck_recv_period CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT ck_recv_fees   CHECK (father_fee >= 0 AND son_fee >= 0),
  CONSTRAINT ck_recv_cancel CHECK (status <> 'ملغي' OR cancelled_at IS NOT NULL)
);

-- Rule 4.
CREATE UNIQUE INDEX uq_recv_active_period
  ON public.receivables (family_id, period) WHERE status <> 'ملغي';

CREATE INDEX ix_recv_period      ON public.receivables (period, status);
CREATE INDEX ix_recv_family_open ON public.receivables (family_id, status, period);
CREATE INDEX ix_recv_created     ON public.receivables (created_at);

-- Rule 5. The only columns an UPDATE may legitimately touch are paid, status,
-- and the three cancellation columns. IS DISTINCT FROM is the NULL-safe
-- comparison — it replaces MySQL's `<=>` and catches a change to or from NULL.
CREATE OR REPLACE FUNCTION public.guard_recv_snapshot() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF  NEW.family_id                IS DISTINCT FROM OLD.family_id
   OR NEW.period                   IS DISTINCT FROM OLD.period
   OR NEW.period_end               IS DISTINCT FROM OLD.period_end
   OR NEW.father_fee               IS DISTINCT FROM OLD.father_fee
   OR NEW.son_fee                  IS DISTINCT FROM OLD.son_fee
   OR NEW.father_member_id         IS DISTINCT FROM OLD.father_member_id
   OR NEW.father_name              IS DISTINCT FROM OLD.father_name
   OR NEW.eligibility_age_snapshot IS DISTINCT FROM OLD.eligibility_age_snapshot
   OR NEW.warning_months_snapshot  IS DISTINCT FROM OLD.warning_months_snapshot
   OR NEW.total                    IS DISTINCT FROM OLD.total
   OR NEW.created_at               IS DISTINCT FROM OLD.created_at
   OR NEW.created_by               IS DISTINCT FROM OLD.created_by
   OR NEW.legacy_id                IS DISTINCT FROM OLD.legacy_id
  THEN
    RAISE EXCEPTION 'Rule 5: receivable snapshot columns are immutable'
      USING ERRCODE = 'RUL05';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_recv_snapshot_immutable
  BEFORE UPDATE ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.guard_recv_snapshot();

-- Keeps `status` in agreement with the money instead of trusting the caller to
-- pass the right label. index.html derived it (receivableStatus); deriving it in
-- a trigger means a hostile client cannot mark an unpaid charge as settled.
CREATE OR REPLACE FUNCTION public.derive_recv_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'ملغي' THEN
    RETURN NEW;                              -- cancellation is explicit
  END IF;
  NEW.status := CASE
    WHEN NEW.paid <= 0        THEN 'غير مسدد'::recv_status
    WHEN NEW.paid >= NEW.total THEN 'مسدد بالكامل'::recv_status
    ELSE 'مسدد جزئياً'::recv_status
  END;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_recv_status
  BEFORE INSERT OR UPDATE ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.derive_recv_status();

-- ─────────────────────────────────────────────────────────────────────────────
-- receivable_lines — which members were actually billed, snapshotted.
--
-- Replaces the prototype's parallel eligibleSonIds[] / eligibleSonNames[]
-- arrays with real rows. Name and national ID are duplicated rather than
-- joined, so a receipt printed years later still shows the details as they
-- stood when the charge was raised.
--
-- Invariant asserted by generate_period() and the reconciler:
--   SUM(receivable_lines.fee_amount) = receivables.total
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.receivable_lines (
  id                 bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receivable_id      bigint        NOT NULL REFERENCES public.receivables(id) ON DELETE RESTRICT,
  -- SET NULL, not RESTRICT: losing the member link must never destroy financial
  -- history, and the snapshot columns keep the line readable without it.
  member_id          bigint        REFERENCES public.members(id) ON DELETE SET NULL,
  member_kind        member_kind   NOT NULL,
  member_name        text          NOT NULL,
  member_national_id text          NOT NULL,
  fee_amount         numeric(12,2) NOT NULL,

  CONSTRAINT uq_line_recv_member UNIQUE (receivable_id, member_id),
  CONSTRAINT ck_line_fee CHECK (fee_amount >= 0)
);

CREATE INDEX ix_line_member ON public.receivable_lines (member_id);


-- ==========================================================================
-- 20260811090400_payments_cash_audit.sql
-- ==========================================================================

-- 20260811090400_payments_cash_audit.sql
-- Ports api/migrations/008, 009, 010, 011, 012.

-- ─────────────────────────────────────────────────────────────────────────────
-- payments
--
-- receipt_no is GENERATED from the identity value, for the same reason
-- families.family_code is: MySQL forbade it and needed a follow-up UPDATE
-- inside the transaction, Postgres does not.
--
-- `reference` stays optional even for bank transfers because index.html leaves
-- it optional (PaymentModal line 620). Requiring it would be a new rule.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.payments (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receipt_no    text          GENERATED ALWAYS AS ('PAY-' || lpad(id::text, 6, '0')) STORED,
  family_id     bigint        NOT NULL REFERENCES public.families(id) ON DELETE RESTRICT,
  amount        numeric(12,2) NOT NULL,
  method        pay_method    NOT NULL,
  reference     text,
  receiver      text,
  notes         text,
  status        pay_status    NOT NULL DEFAULT 'معتمد',
  paid_at       timestamptz   NOT NULL DEFAULT now(),
  created_by    uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancelled_at  timestamptz,
  cancelled_by  uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancel_reason text,
  legacy_id     text,

  CONSTRAINT uq_pay_receipt UNIQUE (receipt_no),
  CONSTRAINT uq_pay_legacy  UNIQUE (legacy_id),
  CONSTRAINT ck_pay_amount  CHECK (amount > 0),
  CONSTRAINT ck_pay_cancel  CHECK (status <> 'ملغي' OR cancelled_at IS NOT NULL)
);

CREATE INDEX ix_pay_family ON public.payments (family_id, paid_at);
CREATE INDEX ix_pay_time   ON public.payments (paid_at);
CREATE INDEX ix_pay_status ON public.payments (status, paid_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- payment_allocations — the FIFO split of one payment across receivables.
--
-- Rows are never deleted, not even on cancellation (rule 9): reversal adjusts
-- receivables.paid and marks the payment 'ملغي' while this record of what was
-- applied where survives. sequence_no records the order the FIFO loop actually
-- applied them, which makes a disputed allocation reconstructable.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.payment_allocations (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id    bigint        NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
  receivable_id bigint        NOT NULL REFERENCES public.receivables(id) ON DELETE RESTRICT,
  period        char(7)       NOT NULL,
  amount        numeric(12,2) NOT NULL,
  sequence_no   smallint      NOT NULL,

  CONSTRAINT uq_alloc_pay_recv UNIQUE (payment_id, receivable_id),
  CONSTRAINT ck_alloc_amount   CHECK (amount > 0)
);

CREATE INDEX ix_alloc_recv ON public.payment_allocations (receivable_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- cash_movements — the treasury mirror of every approved payment.
--
-- uq_cash_payment turns business rule 8 into a schema guarantee: a payment can
-- have exactly one cash movement, so a retried request cannot double-count the
-- treasury. That matters more here than it did behind the API, because a mobile
-- client on a flaky connection retries far more often than a server did.
--
-- movement_type carries only 'تحصيل' because that is the sole value index.html
-- produces (line 353) — the association has no way to record money going OUT.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.cash_movements (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id    bigint        NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
  family_id     bigint        NOT NULL REFERENCES public.families(id) ON DELETE RESTRICT,
  amount        numeric(12,2) NOT NULL,
  method        pay_method    NOT NULL,
  movement_type cash_kind     NOT NULL DEFAULT 'تحصيل',
  status        pay_status    NOT NULL DEFAULT 'معتمد',
  occurred_at   timestamptz   NOT NULL,
  legacy_id     text,

  CONSTRAINT uq_cash_payment UNIQUE (payment_id),
  CONSTRAINT uq_cash_legacy  UNIQUE (legacy_id),
  CONSTRAINT ck_cash_amount  CHECK (amount > 0)
);

CREATE INDEX ix_cash_time   ON public.cash_movements (occurred_at);
CREATE INDEX ix_cash_method ON public.cash_movements (method, status, occurred_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- audit_log — append-only regulatory trail (rule 12).
--
-- timestamptz is microsecond-resolution, which covers what MySQL needed
-- DATETIME(3) for: several entries are written inside one operation and rendered
-- newest-first, so second precision made the display order unstable.
--
-- actor_name is snapshotted alongside actor_id so the trail stays readable after
-- a user is renamed or deleted.
--
-- ip_address has no source any more. PostgREST does not expose the client IP to
-- SQL, so this column will be NULL for every row the app writes. Left in place
-- rather than dropped so imported legacy rows keep theirs — see
-- docs/SUPABASE_MIGRATION_PLAN.md, "what cannot be preserved".
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.audit_log (
  id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_type    text        NOT NULL,
  detail        text        NOT NULL,
  ref           text,
  actor_user_id uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  actor_name    text        NOT NULL,
  ip_address    text,
  occurred_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX ix_audit_time ON public.audit_log (occurred_at);
CREATE INDEX ix_audit_type ON public.audit_log (event_type, occurred_at);
CREATE INDEX ix_audit_ref  ON public.audit_log (ref);

-- ─────────────────────────────────────────────────────────────────────────────
-- Rule 9 / rule 12: nothing financial is ever hard-deleted, and the audit trail
-- cannot be rewritten.
--
-- index.html never deletes a payment; it marks it 'ملغي', reverses the
-- allocations and keeps the row (cancelPayment line 361). These triggers make
-- that structural rather than conventional.
--
-- Defence in depth is different now. Previously the app's database user could be
-- granted no DELETE privilege, and the triggers guarded against someone with a
-- SQL console. There is no app database user any more — the client IS the
-- caller, so RLS withholds DELETE and these triggers are the backstop that also
-- binds anything holding the service_role key.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refuse_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Rule 9: % rows cannot be deleted, only cancelled', TG_TABLE_NAME
    USING ERRCODE = 'RUL09';
END $$;

CREATE TRIGGER trg_recv_no_delete       BEFORE DELETE ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_recv_lines_no_delete BEFORE DELETE ON public.receivable_lines
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_pay_no_delete        BEFORE DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_alloc_no_delete      BEFORE DELETE ON public.payment_allocations
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_cash_no_delete       BEFORE DELETE ON public.cash_movements
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();

CREATE OR REPLACE FUNCTION public.refuse_audit_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only: rows cannot be modified or deleted'
    USING ERRCODE = 'RUL12';
END $$;

CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION public.refuse_audit_change();
CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION public.refuse_audit_change();


-- ==========================================================================
-- 20260811090500_rls.sql
-- ==========================================================================

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
ALTER TABLE public.families             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.members              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receivables          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.receivable_lines     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_movements       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log            ENABLE ROW LEVEL SECURITY;

-- ── SELECT: viewer and above ─────────────────────────────────────────────────
-- has_role() returns false for anon, for a suspended account, and for one still
-- pending admin approval, because my_role() returns NULL unless status =
-- 'approved'. The prototype's "sign in and you are in" becomes "sign in and wait
-- to be let in", which is the behaviour api/src/auth/middleware.ts had.

GRANT SELECT ON
  public.association_settings, public.families, public.members,
  public.receivables, public.receivable_lines, public.payments,
  public.payment_allocations, public.cash_movements
TO authenticated;

CREATE POLICY read_settings ON public.association_settings
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_families ON public.families
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_members ON public.members
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_receivables ON public.receivables
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_receivable_lines ON public.receivable_lines
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_payments ON public.payments
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_allocations ON public.payment_allocations
  FOR SELECT TO authenticated USING (public.has_role('viewer'));
CREATE POLICY read_cash ON public.cash_movements
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


-- ==========================================================================
-- 20260811090600_rpc.sql
-- ==========================================================================

-- 20260811090600_rpc.sql — every write in the system.
--
-- These functions are the direct replacement for the nine transactional
-- endpoints. Each is SECURITY DEFINER (so it can write tables the caller holds
-- no privilege on), each pins search_path (so a caller cannot redirect the
-- elevated body at their own schema), and each starts with require_role().
--
-- A function body is one transaction. That is the whole reason this file exists:
-- registering a payment inserts a payment, N allocations, N receivable updates
-- and a cash movement, and either all of it lands or none of it does. Split
-- across separate PostgREST calls from a phone, a dropped connection between
-- call three and call four leaves the treasury disagreeing with the ledger, and
-- no amount of client retry logic can repair it afterwards.
--
-- Money crosses the wire as TEXT. numeric serialises to an unquoted JSON number,
-- which dart:convert decodes to double — proven in supabase/tests/. Every amount
-- returned below is cast explicitly.

-- ── Audit helper ─────────────────────────────────────────────────────────────
-- actor_name is snapshotted so the trail survives a rename or a deleted account.
CREATE OR REPLACE FUNCTION public.write_audit(
  p_event_type text, p_detail text, p_ref text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_name text;
BEGIN
  SELECT coalesce(nullif(display_name, ''), email) INTO v_name
    FROM public.profiles WHERE id = auth.uid();
  INSERT INTO public.audit_log (event_type, detail, ref, actor_user_id, actor_name)
  VALUES (p_event_type, p_detail, p_ref, auth.uid(), coalesce(v_name, 'system'));
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 22 — POST /payments.  THE critical transaction.
--
-- Rule 7: amount > 0, amount <= total outstanding, FIFO oldest period first.
-- Rule 8: exactly one cash movement per approved payment.
--
-- The FOR UPDATE is not decoration. Two treasurers collecting from the same
-- family at the same moment both read a 100 balance and both allocate 60; without
-- the lock the second overwrites the first and 20 vanishes. The lock makes the
-- loser wait, re-read, and fail the outstanding check — which is the correct
-- outcome. ORDER BY inside the locking SELECT also fixes a consistent lock
-- order, so two payments touching overlapping receivables cannot deadlock.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.register_payment(
  p_family_id bigint,
  p_amount    numeric,
  p_method    pay_method,
  p_reference text DEFAULT NULL,
  p_receiver  text DEFAULT NULL,
  p_notes     text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  -- Unconstrained numeric, NOT numeric(12,2). Individual amounts are bounded by
  -- the column type, but their SUM is not: a family with enough open periods
  -- overflows a 12-digit accumulator and the call dies with 22003 instead of
  -- reporting the balance. Found by the probe suite, which pushed a large total
  -- through and got "numeric field overflow" where it expected a rule violation.
  v_outstanding numeric;
  v_remaining   numeric;
  v_payment_id  bigint;
  v_receipt     text;
  v_take        numeric(12,2);
  v_seq         smallint := 0;
  r             record;
  v_allocs      jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.require_role('treasurer');

  -- Round to minor units up front. A client can post 10.005; accepting it would
  -- put a third decimal into an allocation and the sums would stop tying out.
  p_amount := round(p_amount, 2);

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Rule 7: payment amount must be greater than zero'
      USING ERRCODE = 'RUL07';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.families WHERE id = p_family_id) THEN
    RAISE EXCEPTION 'FAMILY_NOT_FOUND' USING ERRCODE = 'RUL07';
  END IF;

  -- Lock every open receivable for this family, oldest first. Once locked, no
  -- other transaction can move them for the rest of this one, so the total below
  -- and the loop further down both read the same reality — which is the whole
  -- point. ORDER BY also fixes a consistent lock acquisition order.
  PERFORM 1
    FROM public.receivables r2
   WHERE r2.family_id = p_family_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0
   ORDER BY r2.period ASC, r2.id ASC
     FOR UPDATE;

  SELECT coalesce(sum(r2.balance), 0) INTO v_outstanding
    FROM public.receivables r2
   WHERE r2.family_id = p_family_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0;

  IF v_outstanding <= 0 THEN
    RAISE EXCEPTION 'Rule 7: family has no outstanding balance'
      USING ERRCODE = 'RUL07';
  END IF;

  IF p_amount > v_outstanding THEN
    RAISE EXCEPTION 'Rule 7: amount % exceeds outstanding balance %',
      p_amount, v_outstanding USING ERRCODE = 'RUL07';
  END IF;

  INSERT INTO public.payments (family_id, amount, method, reference, receiver,
                               notes, created_by)
  VALUES (p_family_id, p_amount, p_method, p_reference, p_receiver, p_notes,
          auth.uid())
  RETURNING id, receipt_no INTO v_payment_id, v_receipt;

  v_remaining := p_amount;

  FOR r IN SELECT r2.id, r2.period, r2.balance
             FROM public.receivables r2
            WHERE r2.family_id = p_family_id
              AND r2.status <> 'ملغي'
              AND r2.balance > 0
            ORDER BY r2.period ASC, r2.id ASC
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := least(v_remaining, r.balance);
    v_seq  := v_seq + 1;

    INSERT INTO public.payment_allocations
      (payment_id, receivable_id, period, amount, sequence_no)
    VALUES (v_payment_id, r.id, r.period, v_take, v_seq);

    -- ck_recv_paid (paid <= total) is the storage-engine backstop: if the maths
    -- above were ever wrong, this UPDATE fails and the whole call rolls back.
    UPDATE public.receivables SET paid = paid + v_take WHERE id = r.id;

    v_remaining := v_remaining - v_take;
    v_allocs := v_allocs || jsonb_build_object(
      'receivableId', r.id, 'period', r.period,
      'amount', v_take::text, 'sequenceNo', v_seq);
  END LOOP;

  IF v_remaining <> 0 THEN
    RAISE EXCEPTION 'INVARIANT: % left unallocated after FIFO', v_remaining
      USING ERRCODE = 'RUL07';
  END IF;

  -- Rule 8. uq_cash_payment makes a duplicate structurally impossible.
  INSERT INTO public.cash_movements
    (payment_id, family_id, amount, method, occurred_at)
  SELECT id, family_id, amount, method, paid_at
    FROM public.payments WHERE id = v_payment_id;

  PERFORM public.write_audit('payment.register',
    format('تحصيل %s من العائلة %s', p_amount::text, p_family_id),
    v_receipt);

  RETURN jsonb_build_object(
    'paymentId', v_payment_id,
    'receiptNo', v_receipt,
    'familyId',  p_family_id,
    'amount',    p_amount::text,
    'method',    p_method,
    'allocations', v_allocs);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 23 — POST /payments/:id/cancel.  The second critical transaction.
-- Rule 9: reverse the money, preserve every row.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cancel_payment(
  p_payment_id bigint,
  p_reason     text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_pay record;
  r     record;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED' USING ERRCODE = 'RUL09';
  END IF;

  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND' USING ERRCODE = 'RUL09';
  END IF;
  IF v_pay.status = 'ملغي' THEN
    RAISE EXCEPTION 'PAYMENT_ALREADY_CANCELLED' USING ERRCODE = 'RUL09';
  END IF;

  -- Same lock order as register_payment: period then id.
  FOR r IN
    SELECT a.receivable_id, a.amount, rc.period
      FROM public.payment_allocations a
      JOIN public.receivables rc ON rc.id = a.receivable_id
     WHERE a.payment_id = p_payment_id
     ORDER BY rc.period ASC, rc.id ASC
       FOR UPDATE OF rc
  LOOP
    -- ck_recv_paid (paid >= 0) catches a double reversal.
    UPDATE public.receivables SET paid = paid - r.amount
     WHERE id = r.receivable_id;
  END LOOP;

  UPDATE public.payments
     SET status = 'ملغي', cancelled_at = now(),
         cancelled_by = auth.uid(), cancel_reason = p_reason
   WHERE id = p_payment_id;

  -- Voided, never deleted — the cash screen renders it struck through.
  UPDATE public.cash_movements SET status = 'ملغي' WHERE payment_id = p_payment_id;

  PERFORM public.write_audit('payment.cancel',
    format('إلغاء %s: %s', v_pay.receipt_no, p_reason), v_pay.receipt_no);

  RETURN jsonb_build_object(
    'paymentId', p_payment_id, 'receiptNo', v_pay.receipt_no,
    'status', 'ملغي', 'amount', v_pay.amount::text, 'reason', p_reason);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 18 — POST /receivables/generate.
-- Rules 1, 3, 4, 5: eligibility at period end, total > 0 or skip, one live row
-- per (family, period), snapshot the settings.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.generate_period(p_period char(7))
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  s           record;
  f           record;
  v_end       date;
  v_total     numeric(12,2);
  v_father    record;
  v_recv_id   bigint;
  v_created   int := 0;
  v_skipped   int := 0;
  v_sons      int;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'BAD_PERIOD: %', p_period USING ERRCODE = 'RUL04';
  END IF;

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_end := (to_date(p_period || '-01', 'YYYY-MM-DD')
            + interval '1 month - 1 day')::date;

  FOR f IN SELECT id FROM public.families ORDER BY id LOOP
    SELECT * INTO v_father FROM public.members
      WHERE family_id = f.id AND kind = 'father';

    -- No father row means no one to bill and no name to snapshot.
    IF NOT FOUND THEN v_skipped := v_skipped + 1; CONTINUE; END IF;

    -- Rule 1: eligibility is age at PERIOD END, and member status overrides age
    -- — a موقوف or متوفى son is not billable however old he is.
    SELECT count(*) INTO v_sons FROM public.members m
     WHERE m.family_id = f.id AND m.kind = 'son' AND m.status = 'نشط'
       AND m.dob IS NOT NULL
       AND extract(year FROM age(v_end, m.dob)) >= s.eligibility_age;

    v_total := (CASE WHEN v_father.status = 'نشط' THEN s.father_fee ELSE 0 END)
             + s.son_fee * v_sons;

    -- Rule 3: nothing to charge means no row at all, not a zero row.
    IF v_total <= 0 THEN v_skipped := v_skipped + 1; CONTINUE; END IF;

    -- Rule 4 as idempotency: re-running the same period skips instead of
    -- raising a duplicate. The partial index is what makes this safe under
    -- concurrency, so two admins pressing the button together cannot double-bill.
    INSERT INTO public.receivables (
      family_id, period, period_end, father_fee, son_fee, father_member_id,
      father_name, eligibility_age_snapshot, warning_months_snapshot, total,
      created_by)
    VALUES (
      f.id, p_period, v_end, s.father_fee, s.son_fee, v_father.id,
      v_father.full_name, s.eligibility_age, s.warning_months, v_total,
      auth.uid())
    ON CONFLICT (family_id, period) WHERE status <> 'ملغي' DO NOTHING
    RETURNING id INTO v_recv_id;

    IF v_recv_id IS NULL THEN v_skipped := v_skipped + 1; CONTINUE; END IF;

    -- Snapshot who was billed. SUM(fee_amount) = total is the invariant the
    -- reconciler checks.
    IF v_father.status = 'نشط' THEN
      INSERT INTO public.receivable_lines
        (receivable_id, member_id, member_kind, member_name,
         member_national_id, fee_amount)
      VALUES (v_recv_id, v_father.id, 'father', v_father.full_name,
              v_father.national_id, s.father_fee);
    END IF;

    INSERT INTO public.receivable_lines
      (receivable_id, member_id, member_kind, member_name,
       member_national_id, fee_amount)
    SELECT v_recv_id, m.id, 'son', m.full_name, m.national_id, s.son_fee
      FROM public.members m
     WHERE m.family_id = f.id AND m.kind = 'son' AND m.status = 'نشط'
       AND m.dob IS NOT NULL
       AND extract(year FROM age(v_end, m.dob)) >= s.eligibility_age;

    v_created := v_created + 1;
    v_recv_id := NULL;
  END LOOP;

  PERFORM public.write_audit('receivables.generate',
    format('إنشاء استحقاقات %s: %s سجل', p_period, v_created), p_period);

  RETURN jsonb_build_object('period', p_period, 'created', v_created,
                            'skipped', v_skipped);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 19 — POST /receivables/auto-close.
-- Rule 6: backfill system_start → previous month. Idempotent via rule 4.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.auto_close_periods()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  s         record;
  v_cursor  date;
  v_last    date;
  v_period  char(7);
  v_created int := 0;
  v_periods jsonb := '[]'::jsonb;
  v_one     jsonb;
BEGIN
  PERFORM public.require_role('financeManager');

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_cursor := date_trunc('month', s.system_start)::date;
  -- PREVIOUS month, not this one. index.html labels the button with
  -- previousPeriod() (line 452) — the current month is not closed until it ends.
  v_last   := (date_trunc('month', current_date) - interval '1 month')::date;

  WHILE v_cursor <= v_last LOOP
    v_period := to_char(v_cursor, 'YYYY-MM');
    v_one    := public.generate_period(v_period);
    v_created := v_created + (v_one ->> 'created')::int;
    v_periods := v_periods || v_one;
    v_cursor := (v_cursor + interval '1 month')::date;
  END LOOP;

  RETURN jsonb_build_object('created', v_created, 'periods', v_periods);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoints 11 and 13 — POST /families, PUT /families/:id.
-- Rule 10: national_id unique across ALL members, DOB not future.
--
-- Sons arrive as a jsonb array. A son absent from the array is removed, and the
-- removal must be applied BEFORE the inserts, otherwise re-using the national ID
-- of a son you just removed trips uq_members_national_id — a bug this project
-- already hit once against MySQL.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.save_family(
  p_family_id bigint,      -- NULL to create
  p_father    jsonb,
  p_sons      jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_family_id bigint := p_family_id;
  v_code      text;
  v_keep      bigint[];
  son         jsonb;
  v_son_id    bigint;
BEGIN
  PERFORM public.require_role('financeManager');

  IF v_family_id IS NULL THEN
    INSERT INTO public.families (created_by, updated_by)
    VALUES (auth.uid(), auth.uid())
    RETURNING id INTO v_family_id;
  ELSE
    UPDATE public.families SET updated_by = auth.uid() WHERE id = v_family_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'FAMILY_NOT_FOUND' USING ERRCODE = 'RUL10';
    END IF;
  END IF;

  -- Father: upsert on the one-father partial index.
  INSERT INTO public.members (
    family_id, kind, full_name, national_id, phone, subscription_no, dob,
    nationality, workplace, registered_at, status)
  VALUES (
    v_family_id, 'father',
    p_father ->> 'fullName', p_father ->> 'nationalId',
    p_father ->> 'phone', p_father ->> 'subscriptionNo',
    nullif(p_father ->> 'dob', '')::date,
    coalesce(nullif(p_father ->> 'nationality', ''), 'ليبي'),
    p_father ->> 'workplace',
    coalesce(nullif(p_father ->> 'registeredAt', '')::date, current_date),
    coalesce(nullif(p_father ->> 'status', '')::member_status, 'نشط'))
  ON CONFLICT (family_id) WHERE kind = 'father' DO UPDATE SET
    full_name = excluded.full_name, national_id = excluded.national_id,
    phone = excluded.phone, subscription_no = excluded.subscription_no,
    dob = excluded.dob, nationality = excluded.nationality,
    workplace = excluded.workplace, status = excluded.status;

  -- Remove first, then insert. Order is the whole point.
  SELECT coalesce(array_agg((s ->> 'id')::bigint), '{}'::bigint[]) INTO v_keep
    FROM jsonb_array_elements(p_sons) s WHERE s ->> 'id' IS NOT NULL;

  DELETE FROM public.members
   WHERE family_id = v_family_id AND kind = 'son'
     AND NOT (id = ANY (v_keep))
     -- A son who has been billed cannot vanish: the receivable line references
     -- him. FK is ON DELETE SET NULL, which would silently orphan the line, so
     -- refuse instead and let the caller mark him موقوف.
     AND NOT EXISTS (SELECT 1 FROM public.receivable_lines l WHERE l.member_id = members.id);

  FOR son IN SELECT * FROM jsonb_array_elements(p_sons) LOOP
    v_son_id := nullif(son ->> 'id', '')::bigint;
    IF v_son_id IS NULL THEN
      INSERT INTO public.members (
        family_id, kind, full_name, national_id, phone, dob, nationality,
        workplace, registered_at, status)
      VALUES (
        v_family_id, 'son', son ->> 'fullName', son ->> 'nationalId',
        son ->> 'phone', nullif(son ->> 'dob', '')::date,
        coalesce(nullif(son ->> 'nationality', ''), 'ليبي'),
        son ->> 'workplace',
        coalesce(nullif(son ->> 'registeredAt', '')::date, current_date),
        coalesce(nullif(son ->> 'status', '')::member_status, 'نشط'));
    ELSE
      UPDATE public.members SET
        full_name = son ->> 'fullName', national_id = son ->> 'nationalId',
        phone = son ->> 'phone', dob = nullif(son ->> 'dob', '')::date,
        nationality = coalesce(nullif(son ->> 'nationality', ''), 'ليبي'),
        workplace = son ->> 'workplace',
        status = coalesce(nullif(son ->> 'status', '')::member_status, 'نشط')
       WHERE id = v_son_id AND family_id = v_family_id AND kind = 'son';
    END IF;
  END LOOP;

  SELECT family_code INTO v_code FROM public.families WHERE id = v_family_id;

  PERFORM public.write_audit(
    CASE WHEN p_family_id IS NULL THEN 'family.create' ELSE 'family.update' END,
    format('%s %s', CASE WHEN p_family_id IS NULL THEN 'إضافة' ELSE 'تعديل' END,
           v_code), v_code);

  RETURN jsonb_build_object('familyId', v_family_id, 'familyCode', v_code);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 8 — PUT /settings.  Rule 5's counterpart: changing these must not
-- touch history, which trg_recv_snapshot_immutable guarantees independently.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.update_settings(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_row record;
BEGIN
  PERFORM public.require_role('admin');

  UPDATE public.association_settings SET
    association_name = coalesce(p_patch ->> 'associationName', association_name),
    currency         = coalesce(p_patch ->> 'currency', currency),
    father_fee       = coalesce((p_patch ->> 'fatherFee')::numeric, father_fee),
    son_fee          = coalesce((p_patch ->> 'sonFee')::numeric, son_fee),
    eligibility_age  = coalesce((p_patch ->> 'eligibilityAge')::smallint, eligibility_age),
    warning_months   = coalesce((p_patch ->> 'warningMonths')::smallint, warning_months),
    system_start     = coalesce((p_patch ->> 'systemStart')::date, system_start),
    treasurer_name        = coalesce(p_patch ->> 'treasurerName', treasurer_name),
    treasurer_national_id = coalesce(p_patch ->> 'treasurerNationalId', treasurer_national_id),
    treasurer_phone       = coalesce(p_patch ->> 'treasurerPhone', treasurer_phone),
    finance_manager_name        = coalesce(p_patch ->> 'financeName', finance_manager_name),
    finance_manager_national_id = coalesce(p_patch ->> 'financeNationalId', finance_manager_national_id),
    finance_manager_phone       = coalesce(p_patch ->> 'financePhone', finance_manager_phone),
    updated_by = auth.uid()
  WHERE id = 1
  RETURNING * INTO v_row;

  PERFORM public.write_audit('settings.update', 'تحديث إعدادات الجمعية', 'settings');

  RETURN jsonb_build_object(
    'associationName', v_row.association_name, 'currency', v_row.currency,
    'fatherFee', v_row.father_fee::text, 'sonFee', v_row.son_fee::text,
    'eligibilityAge', v_row.eligibility_age, 'warningMonths', v_row.warning_months,
    'systemStart', v_row.system_start);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Endpoint 6 — PATCH /users/:id.  Self-elevation and last-admin are blocked by
-- trg_profiles_guard, so they hold even against the service_role key.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_user_access(
  p_user_id uuid, p_role app_role DEFAULT NULL, p_status app_status DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_row record;
BEGIN
  PERFORM public.require_role('admin');

  UPDATE public.profiles SET
    role   = coalesce(p_role, role),
    status = coalesce(p_status, status),
    approved_by = CASE WHEN p_status = 'approved' THEN auth.uid() ELSE approved_by END,
    approved_at = CASE WHEN p_status = 'approved' THEN now() ELSE approved_at END
  WHERE id = p_user_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'RUL00';
  END IF;

  PERFORM public.write_audit('user.access',
    format('%s → %s / %s', v_row.email, v_row.role, v_row.status),
    v_row.id::text);

  RETURN jsonb_build_object('id', v_row.id, 'email', v_row.email,
                            'role', v_row.role, 'status', v_row.status);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Purge — the ONE deliberate exception to rule 9, and the only way to erase
-- financial history. Settings → منطقة الخطر calls it.
--
-- WHY IT EXISTS: the association trials the app with practice figures before it
-- goes live. Cancelling every payment (rule 9's supported path) leaves the
-- practice rows on screen struck through forever, so there had to be a way to
-- actually start from zero.
--
-- WHY TRUNCATE AND NOT DELETE: the five financial tables carry BEFORE DELETE
-- triggers (refuse_delete) and audit_log carries refuse_audit_change. TRUNCATE
-- fires neither — only AFTER TRUNCATE statement triggers, and none are defined.
-- The alternative was ALTER TABLE … DISABLE TRIGGER around the DELETEs, which
-- takes the same ACCESS EXCLUSIVE lock but leaves a window in which the rule-9
-- guard is genuinely off. TRUNCATE never disarms anything, so a failure here
-- cannot leave the table unprotected. It also resets the identity sequences,
-- which is what makes the next receipt PAY-000001 instead of continuing the
-- practice run's numbering.
--
-- So rule 9 now reads: nothing can be hard-deleted except through this function,
-- which is admin-only, demands a typed confirmation, and is one transaction.
-- `authenticated` holds no TRUNCATE privilege on any table (see
-- 20260811091200_function_lockdown.sql), so this really is the only route.
--
-- WHAT SURVIVES: families, members, association_settings, profiles. The purge is
-- financial only — the directory is what the association spent the most effort
-- entering, and rebuilding it is not what "clear the figures" means.
--
-- WHAT DOES NOT: audit_log is truncated too, and NO entry is written afterwards.
-- That is a deliberate choice by the association's admin, and it is worth being
-- explicit about the cost: rule 12 makes the trail append-only precisely so an
-- administrator cannot quietly rewrite history, and this function is a hole in
-- that. After it runs there is no record inside the database that it ran, or of
-- anything that preceded it. If that is ever regretted, the fix is one line —
-- move the audit_log truncate out and write a 'data.purge' entry at the end.
--
-- No ordering hazard in the TRUNCATE list: every FK pointing INTO these six
-- tables originates in one of the six, so Postgres does not demand CASCADE.
-- Adding a seventh table that references payments without listing it here would
-- fail loudly rather than silently skip.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.purge_financial_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv  bigint;
  v_lines bigint;
  v_pay   bigint;
  v_alloc bigint;
  v_cash  bigint;
  v_audit bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- The typed phrase. Not UX politeness: register_payment and save_family are
  -- reachable by anyone who can read the anon key out of the APK, and so is
  -- this. require_role stops a treasurer; the phrase stops an admin's own
  -- mis-click and a replayed request. It must match wire_values.dart exactly.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح نهائي' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  -- Counted before, because TRUNCATE reports no row count. These tables are
  -- small enough that six counts cost nothing next to the truncate itself.
  SELECT count(*) INTO v_recv  FROM public.receivables;
  SELECT count(*) INTO v_lines FROM public.receivable_lines;
  SELECT count(*) INTO v_pay   FROM public.payments;
  SELECT count(*) INTO v_alloc FROM public.payment_allocations;
  SELECT count(*) INTO v_cash  FROM public.cash_movements;
  SELECT count(*) INTO v_audit FROM public.audit_log;

  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivable_lines,
           public.receivables,
           public.audit_log
    RESTART IDENTITY;

  RETURN jsonb_build_object(
    'receivables',     v_recv,
    'receivableLines', v_lines,
    'payments',        v_pay,
    'allocations',     v_alloc,
    'cashMovements',   v_cash,
    'auditEntries',    v_audit);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- Purge, the wider one — the directory as well as the money.
--
-- WHY IT CANNOT BE "FAMILIES ONLY": receivables, payments and cash_movements all
-- carry `family_id … ON DELETE RESTRICT`, and members does too. A purge that
-- removed families while a single receipt still pointed at one would be refused
-- by the storage engine, so the choice is between erasing the financial rows
-- alongside them or refusing whenever any exist. Refusing would mean the button
-- fails for exactly the person who wants it — an admin clearing a trial run —
-- and would leave him pressing two buttons in an order nothing tells him about.
-- So this is deliberately a SUPERSET of purge_financial_data, and the screen
-- says so rather than surprising him after the fact.
--
-- The separate confirmation phrase is the point of having two functions at all.
-- Both are admin-only and both truncate; what stops a mis-click from erasing the
-- directory when only the figures were meant is that 'مسح نهائي' does not
-- satisfy this function, and the app cannot send a phrase the admin did not type.
--
-- WHAT SURVIVES: association_settings and profiles. Wiping profiles would strand
-- the association outside its own app — the last-admin guard exists precisely to
-- make that unreachable — and settings are configuration, not data.
--
-- Order and CASCADE: every FK pointing INTO these eight originates in one of the
-- eight (members → families, receivable_lines → members, receivables →
-- father_member_id, and the four financial links), so Postgres does not demand
-- CASCADE. A ninth table referencing families and left off this list would fail
-- loudly instead of being silently skipped.
-- ═════════════════════════════════════════════════════════════════════════════
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

-- ═════════════════════════════════════════════════════════════════════════════
-- The family portal — issuing and redeeming an access code.
--
-- Two functions, and the split between them is the security boundary: an admin
-- CREATES a code for a family, and the head of family REDEEMS it for himself.
-- Nobody can do both halves, and no client ever writes profiles.family_id
-- directly — `authenticated` holds no UPDATE on profiles at all.
-- ═════════════════════════════════════════════════════════════════════════════

-- Endpoint: POST /families/:id/access-code.  Generates, or regenerates.
--
-- Regenerating REVOKES the previous code (one row per family, overwritten) but
-- does NOT sign out a head of family who already redeemed it: the binding lives
-- on profiles.family_id from that moment on. So an admin can reissue freely when
-- a WhatsApp message is lost, without breaking anybody.
--
-- The alphabet omits 0/O/1/I/L/U — the pairs a person mis-reads off a phone
-- screen, and U so no random draw can spell something unfortunate. 27 letters,
-- 12 characters, ~57 bits: not guessable over HTTPS, and readable aloud.
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

-- Endpoint: POST /access-code/redeem.  Called by the head of family himself,
-- once, right after he signs in with Google.
--
-- Binds his profile to the family and approves him. From then on my_role()
-- returns NULL for him and my_family_id() returns the family, so the RLS
-- policies in 20260811090500 decide everything he can see — this function is
-- never consulted again.
--
-- It refuses anyone who is already staff. Without that check an admin who typed
-- a code would set his own family_id, my_role() would start returning NULL, and
-- he would lock himself out of the association's own app — possibly as the last
-- admin, which no other guard would catch because his role never changed.
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

-- ── Execution grants ─────────────────────────────────────────────────────────
-- Every function re-checks the role internally, so granting EXECUTE broadly to
-- authenticated is safe: a viewer calling register_payment gets RUL00, not a row.
GRANT EXECUTE ON FUNCTION
  public.register_payment(bigint, numeric, pay_method, text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_family(bigint, jsonb, jsonb),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status),
  public.purge_financial_data(text),
  public.purge_all_data(text),
  public.issue_family_code(bigint),
  public.redeem_family_code(text)
TO authenticated;

-- write_audit is NOT granted: it is an internal helper. Exposing it would let
-- any signed-in user forge trail entries under someone else's name.


-- ==========================================================================
-- 20260811090700_views.sql
-- ==========================================================================

-- 20260811090700_views.sql — the read side of the 22 non-transactional endpoints.
--
-- Every one of these exists for a single reason: MONEY MUST NOT REACH DART AS A
-- NUMBER. PostgREST serialises numeric as an unquoted JSON literal
-- (`"amount":12345678.91`), dart:convert decodes that to double, and this
-- project's entire money discipline rests on never letting a float near a
-- balance. mysql2 handed back DECIMAL as a string and the Dart models are built
-- for strings. `::text` reproduces that exactly.
--
-- Proven, not assumed: supabase/tests/probe.sh compares json_agg output for a
-- raw numeric column against the cast one. PostgREST builds its response body
-- with json_agg inside Postgres, so that comparison is the wire format.
--
-- security_invoker = on is load-bearing. Without it a view runs with its
-- owner's rights and silently bypasses the RLS policies on the tables beneath —
-- an anon caller would read the whole ledger through the view.

-- ── Families list with debt totals (endpoint 10) ─────────────────────────────
CREATE VIEW public.v_families WITH (security_invoker = on) AS
SELECT
  f.id,
  f.family_code,
  f.created_at,
  father.id                        AS father_member_id,
  father.full_name                 AS father_name,
  father.national_id               AS father_national_id,
  father.phone                     AS father_phone,
  father.status                    AS father_status,
  (SELECT count(*) FROM public.members m
    WHERE m.family_id = f.id AND m.kind = 'son')          AS sons_count,
  coalesce(agg.debt, 0)::text      AS debt,
  coalesce(agg.paid, 0)::text      AS paid,
  coalesce(agg.issued, 0)::text    AS issued
FROM public.families f
LEFT JOIN public.members father
       ON father.family_id = f.id AND father.kind = 'father'
LEFT JOIN LATERAL (
  SELECT sum(r.balance) AS debt, sum(r.paid) AS paid, sum(r.total) AS issued
    FROM public.receivables r
   WHERE r.family_id = f.id AND r.status <> 'ملغي'
) agg ON true;

-- ── Members, unified father+son search (endpoint 15) ─────────────────────────
-- Eligibility is derived here rather than stored, matching the prototype's
-- memberStatus(), and computed against TODAY — a receivable's own eligibility
-- lives in its snapshot columns and is a different question.
CREATE VIEW public.v_members WITH (security_invoker = on) AS
SELECT
  m.id, m.family_id, f.family_code, m.kind, m.full_name, m.national_id,
  m.phone, m.subscription_no, m.dob, m.nationality, m.workplace,
  m.registered_at, m.status,
  CASE WHEN m.dob IS NULL THEN NULL
       ELSE extract(year FROM age(current_date, m.dob))::int END AS age,
  CASE
    WHEN m.status <> 'نشط' THEN 'inactive'
    WHEN m.dob IS NULL     THEN 'under'
    WHEN extract(year FROM age(current_date, m.dob)) >= s.eligibility_age
      THEN 'eligible'
    WHEN age(m.dob + make_interval(years => s.eligibility_age::int), current_date)
         <= make_interval(months => s.warning_months::int)
      AND m.dob + make_interval(years => s.eligibility_age::int) >= current_date
      THEN 'soon'
    ELSE 'under'
  END AS eligibility,
  CASE WHEN m.kind = 'father' THEN s.father_fee ELSE s.son_fee END::text
       AS current_fee
FROM public.members m
JOIN public.families f ON f.id = m.family_id
CROSS JOIN public.association_settings s;

-- ── Receivables (endpoints 16, 17) ───────────────────────────────────────────
CREATE VIEW public.v_receivables WITH (security_invoker = on) AS
SELECT
  r.id, r.family_id, f.family_code, r.father_name, r.period, r.period_end,
  r.total::text   AS total,
  r.paid::text    AS paid,
  r.balance::text AS balance,
  r.status, r.created_at, r.cancelled_at, r.cancel_reason,
  r.father_fee::text AS father_fee,
  r.son_fee::text    AS son_fee,
  r.eligibility_age_snapshot, r.warning_months_snapshot
FROM public.receivables r
JOIN public.families f ON f.id = r.family_id;

CREATE VIEW public.v_receivable_lines WITH (security_invoker = on) AS
SELECT l.id, l.receivable_id, l.member_id, l.member_kind, l.member_name,
       l.member_national_id, l.fee_amount::text AS fee_amount
FROM public.receivable_lines l;

-- ── Payments and allocations (endpoints 20, 21) ──────────────────────────────
CREATE VIEW public.v_payments WITH (security_invoker = on) AS
SELECT
  p.id, p.receipt_no, p.family_id, f.family_code,
  father.full_name AS family_name,
  p.amount::text   AS amount,
  p.method, p.reference, p.receiver, p.notes, p.status, p.paid_at,
  p.cancelled_at, p.cancel_reason
FROM public.payments p
JOIN public.families f ON f.id = p.family_id
LEFT JOIN public.members father
       ON father.family_id = p.family_id AND father.kind = 'father';

CREATE VIEW public.v_payment_allocations WITH (security_invoker = on) AS
SELECT a.id, a.payment_id, a.receivable_id, a.period,
       a.amount::text AS amount, a.sequence_no
FROM public.payment_allocations a;

-- ── Treasury (endpoints 24, 25) ──────────────────────────────────────────────
CREATE VIEW public.v_cash_movements WITH (security_invoker = on) AS
SELECT
  c.id, c.payment_id, p.receipt_no, c.family_id, f.family_code,
  father.full_name AS family_name,
  c.amount::text   AS amount,
  c.method, c.movement_type, c.status, c.occurred_at
FROM public.cash_movements c
JOIN public.payments p ON p.id = c.payment_id
JOIN public.families f ON f.id = c.family_id
LEFT JOIN public.members father
       ON father.family_id = c.family_id AND father.kind = 'father';

-- Cancelled movements are excluded from every total but stay visible in the
-- list above, struck through — rule 9 requires them shown, not hidden.
CREATE VIEW public.v_cash_summary WITH (security_invoker = on) AS
SELECT
  coalesce(sum(amount), 0)::text AS total,
  coalesce(sum(amount) FILTER (WHERE method = 'نقداً'), 0)::text        AS cash,
  coalesce(sum(amount) FILTER (WHERE method = 'تحويل مصرفي'), 0)::text AS transfer,
  coalesce(sum(amount) FILTER (WHERE occurred_at::date = current_date), 0)::text AS today,
  coalesce(sum(amount) FILTER (WHERE date_trunc('month', occurred_at)
                                    = date_trunc('month', current_date)), 0)::text AS month,
  coalesce(sum(amount) FILTER (WHERE date_trunc('year', occurred_at)
                                    = date_trunc('year', current_date)), 0)::text AS year
FROM public.cash_movements
WHERE status <> 'ملغي';

-- ── Dashboard stat cards (endpoint 26) ───────────────────────────────────────
CREATE VIEW public.v_dashboard_stats WITH (security_invoker = on) AS
SELECT
  (SELECT count(*) FROM public.families)                              AS families,
  (SELECT count(*) FROM public.members WHERE kind = 'son')            AS sons,
  (SELECT count(*) FROM public.v_members
    WHERE kind = 'son' AND eligibility = 'eligible')                  AS eligible,
  (SELECT count(*) FROM public.v_members
    WHERE kind = 'son' AND eligibility = 'soon')                      AS soon,
  (SELECT coalesce(sum(balance), 0)::text FROM public.receivables
    WHERE status <> 'ملغي')                                           AS debt,
  (SELECT count(DISTINCT family_id) FROM public.receivables
    WHERE status <> 'ملغي' AND balance > 0)                           AS indebted_families,
  (SELECT coalesce(sum(amount), 0)::text FROM public.cash_movements
    WHERE status <> 'ملغي')                                           AS collected,
  (SELECT coalesce(sum(amount), 0)::text FROM public.cash_movements
    WHERE status <> 'ملغي' AND method = 'نقداً')                      AS cash,
  (SELECT coalesce(sum(amount), 0)::text FROM public.cash_movements
    WHERE status <> 'ملغي' AND method = 'تحويل مصرفي')                AS transfer;

CREATE VIEW public.v_top_debtors WITH (security_invoker = on) AS
SELECT id AS family_id, family_code, father_name, debt
FROM public.v_families
WHERE debt::numeric > 0
ORDER BY debt::numeric DESC
LIMIT 10;

-- ── Officials (endpoint 9) ───────────────────────────────────────────────────
CREATE VIEW public.v_officials WITH (security_invoker = on) AS
SELECT 'treasurer' AS role, treasurer_name AS name,
       treasurer_national_id AS national_id, treasurer_phone AS phone
  FROM public.association_settings
UNION ALL
SELECT 'financeManager', finance_manager_name,
       finance_manager_national_id, finance_manager_phone
  FROM public.association_settings;

-- ── Settings, money as text (endpoint 7) ─────────────────────────────────────
CREATE VIEW public.v_settings WITH (security_invoker = on) AS
SELECT association_name, currency,
       father_fee::text AS father_fee,
       son_fee::text    AS son_fee,
       eligibility_age, warning_months, system_start, auto_close_previous_months,
       treasurer_name, treasurer_national_id, treasurer_phone,
       finance_manager_name, finance_manager_national_id, finance_manager_phone,
       updated_at
FROM public.association_settings;

-- security_invoker makes each view obey the caller's policies, so a plain SELECT
-- grant is all they need — the underlying table policies still decide.
GRANT SELECT ON
  public.v_families, public.v_members, public.v_receivables,
  public.v_receivable_lines, public.v_payments, public.v_payment_allocations,
  public.v_cash_movements, public.v_cash_summary, public.v_dashboard_stats,
  public.v_top_debtors, public.v_officials, public.v_settings
TO authenticated;


-- ==========================================================================
-- 20260811090800_lockdown.sql
-- ==========================================================================

-- 20260811090800_lockdown.sql — runs LAST, on purpose.
--
-- Postgres grants EXECUTE on every newly created function to PUBLIC. With no API
-- tier, that default is the difference between "only a treasurer can call
-- register_payment" and "anyone holding the anon key can call it and rely on the
-- inner role check being correct".
--
-- 20260811090500_rls.sql tried to fix this with
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- and it DOES NOT WORK. Verified on PostgreSQL 16.4: issued as the superuser that
-- owns these objects it is a silent no-op — no pg_default_acl row is recorded and
-- a function created immediately afterwards still comes out PUBLIC-executable.
-- Supabase migrations run as exactly that kind of role, so the pattern cannot be
-- relied on there either. The probe suite is what caught it: `anon` reached
-- register_payment, and a plain viewer successfully called write_audit, which
-- would have let any signed-in user forge audit-trail entries under their own
-- name.
--
-- Hence: an explicit revoke, after every function exists, followed by an
-- assertion. The assertion is the part that matters — it makes the guarantee
-- survive the next person who adds a function without reading this file, because
-- their migration will fail.

-- Revoked function by function, not `ON ALL FUNCTIONS IN SCHEMA public`, so an
-- extension installed in `public` on a real project keeps working. The assertion
-- below exempts extension-owned functions for the same reason.
DO $revoke$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
  END LOOP;
END $revoke$;

-- Re-state the whole allow-list here rather than trusting the grants made in
-- earlier files, so this one file is the complete answer to "what can a client
-- call?".
GRANT EXECUTE ON FUNCTION
  public.role_rank(app_role), public.my_role(), public.has_role(app_role)
TO authenticated;

GRANT EXECUTE ON FUNCTION
  public.register_payment(bigint, numeric, pay_method, text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_family(bigint, jsonb, jsonb),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status)
TO authenticated;

-- Deliberately NOT granted to anyone: write_audit (forgeable trail entries),
-- require_role (pointless alone), touch_updated_at / guard_* / derive_* /
-- refuse_* (trigger bodies — Postgres checks EXECUTE at CREATE TRIGGER time, not
-- when the trigger fires, so withholding it costs nothing).

-- ── The standing guarantee ───────────────────────────────────────────────────
-- Exposed as a function rather than inlined so the probe suite can call it, and
-- so it can be planted with a violation to prove it is capable of failing.
CREATE OR REPLACE FUNCTION public.assert_no_public_execute() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                    ', ' ORDER BY p.proname)
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND (
       -- NULL proacl means "built-in default", and the built-in default for a
       -- function includes EXECUTE for PUBLIC.
       p.proacl IS NULL
       OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                   WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
     )
     -- Functions belonging to an EXTENSION are not ours to lock down. A real
     -- Supabase project may have pgcrypto, uuid-ossp or similar installed in
     -- `public` rather than `extensions`, and revoking PUBLIC execute from them
     -- would break unrelated things — gen_random_uuid() among them. The rule is
     -- about the API surface this schema defines, not about every function that
     -- happens to live in the same namespace.
     AND NOT EXISTS (
       SELECT 1 FROM pg_depend d
        WHERE d.objid = p.oid
          AND d.classid = 'pg_proc'::regclass
          AND d.deptype = 'e'
     );

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these public functions are executable by PUBLIC (i.e. by anyone holding the anon key): %',
      v_bad;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_no_public_execute() FROM PUBLIC;

SELECT public.assert_no_public_execute();

-- Views obey the caller's policies only because every one of them was created
-- WITH (security_invoker = on). A view without it runs as its owner and reads
-- straight past RLS, so this is checked too rather than trusted to review.
CREATE OR REPLACE FUNCTION public.assert_views_security_invoker() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'v'
     -- reloptions stores the literal as written, so this is 'on', not 'true'.
     -- The first version of this check compared against 'true' and reported
     -- every view as unsafe, which is the right way for an assertion to be
     -- wrong: loudly.
     AND NOT coalesce((SELECT lower(option_value) IN ('on','true','1','yes')
                         FROM pg_options_to_table(c.reloptions)
                        WHERE option_name = 'security_invoker'), false);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these views bypass RLS because security_invoker is not on: %', v_bad;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_views_security_invoker() FROM PUBLIC;

SELECT public.assert_views_security_invoker();


-- ==========================================================================
-- 20260811091000_api_surface.sql
-- ==========================================================================

-- 20260811091000_api_surface.sql — the shape the Flutter app actually consumes.
--
-- This file replaces the snake_case views from 20260811090700 with ones whose
-- column names are the EXACT keys the Dart models parse. PostgREST returns a
-- view's column names verbatim, so quoting camelCase identifiers here means the
-- existing `fromJson` factories work untouched — no mapping layer, no model
-- rewrites, and the wire contract stays defined in SQL exactly as it was when the
-- Node API owned it.
--
-- Two mechanisms, chosen per shape:
--
--   VIEWS for flat lists. PostgREST filters, orders and paginates them, so the
--   Dart side needs no query-building RPCs.
--
--   FUNCTIONS returning jsonb for nested shapes — family detail wraps
--   family/father/sons/kpis, the dashboard wraps stats/topDebtors/upcomingSons.
--   A flat view cannot express that.
--
-- The read functions are STABLE and SECURITY INVOKER, deliberately. They run with
-- the caller's rights, so every RLS policy from 20260811090500 still applies. Only
-- the WRITE functions in 20260811090600 are SECURITY DEFINER, because only they
-- need to touch tables the client holds no privilege on.
--
-- MONEY IS TEXT EVERYWHERE. numeric serialises to a bare JSON number and
-- dart:convert turns that into a double. Every amount below is cast.
--
-- And every aggregate is cast to numeric(12,2) BEFORE text. `coalesce(sum(x), 0)`
-- falls back to an INTEGER literal, so an empty bucket serialises as "0" while
-- every other amount on the same screen is "0.00" — which the contract test
-- caught on the treasury's transfer total. Two decimals, always.

-- ── Arabic month label ───────────────────────────────────────────────────────
-- `periodLabel` was produced by the Node API, so the client has no month names of
-- its own and nothing in lib/l10n to build them from. Keeping the label
-- server-side preserves that and keeps one spelling of each month across the
-- receivables list, the dashboard button and the audit trail. IMMUTABLE so it can
-- be used in a view without blocking planning.
CREATE OR REPLACE FUNCTION public.period_label(p_period text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE substring(p_period FROM 6 FOR 2)
           WHEN '01' THEN 'يناير'   WHEN '02' THEN 'فبراير'
           WHEN '03' THEN 'مارس'    WHEN '04' THEN 'أبريل'
           WHEN '05' THEN 'مايو'    WHEN '06' THEN 'يونيو'
           WHEN '07' THEN 'يوليو'   WHEN '08' THEN 'أغسطس'
           WHEN '09' THEN 'سبتمبر'  WHEN '10' THEN 'أكتوبر'
           WHEN '11' THEN 'نوفمبر'  WHEN '12' THEN 'ديسمبر'
           ELSE p_period
         END || ' ' || substring(p_period FROM 1 FOR 4)
$$;

DROP VIEW IF EXISTS public.v_top_debtors;
DROP VIEW IF EXISTS public.v_dashboard_stats;
DROP VIEW IF EXISTS public.v_cash_summary;
DROP VIEW IF EXISTS public.v_cash_movements;
DROP VIEW IF EXISTS public.v_payment_allocations;
DROP VIEW IF EXISTS public.v_payments;
DROP VIEW IF EXISTS public.v_receivable_lines;
DROP VIEW IF EXISTS public.v_receivables;
DROP VIEW IF EXISTS public.v_members;
DROP VIEW IF EXISTS public.v_families;
DROP VIEW IF EXISTS public.v_officials;
DROP VIEW IF EXISTS public.v_settings;

-- ── Eligibility, derived once ────────────────────────────────────────────────
-- Rule 1 and rule 2 in one place. Every view and function that needs a member's
-- status reads it from here rather than repeating the arithmetic, which is how
-- the prototype's memberStatus() ended up disagreeing with itself.
CREATE VIEW public.v_member_status WITH (security_invoker = on) AS
SELECT
  m.id,
  m.family_id,
  m.kind,
  m.full_name,
  m.national_id,
  m.phone,
  m.subscription_no,
  m.dob,
  m.nationality,
  m.workplace,
  m.registered_at,
  m.status,
  CASE
    WHEN m.dob IS NULL THEN NULL
    ELSE extract(year FROM age(current_date, m.dob))::int
  END AS age_years,
  CASE
    WHEN m.status <> 'نشط' THEN 'inactive'
    WHEN m.dob IS NULL THEN 'under'
    WHEN extract(year FROM age(current_date, m.dob)) >= s.eligibility_age
      THEN 'eligible'
    -- "قريب من السن": the eligibility birthday is in the future but within
    -- warning_months of today.
    WHEN (m.dob + make_interval(years => s.eligibility_age::int)) > current_date
     AND (m.dob + make_interval(years => s.eligibility_age::int))
         <= (current_date + make_interval(months => s.warning_months::int))
      THEN 'soon'
    ELSE 'under'
  END AS eligibility,
  CASE WHEN m.kind = 'father' THEN s.father_fee ELSE s.son_fee END AS fee
FROM public.members m
CROSS JOIN public.association_settings s;

-- ── Settings (AssociationSettingsView) ───────────────────────────────────────
CREATE VIEW public.v_settings WITH (security_invoker = on) AS
SELECT
  association_name        AS "associationName",
  currency                AS "currency",
  father_fee::text        AS "fatherFee",
  son_fee::text           AS "sonFee",
  eligibility_age::int    AS "eligibilityAge",
  warning_months::int     AS "warningMonths",
  to_char(system_start, 'YYYY-MM-DD') AS "systemStart",
  auto_close_previous_months          AS "autoClosePreviousMonths"
FROM public.association_settings;

-- ── Officials ────────────────────────────────────────────────────────────────
CREATE VIEW public.v_officials WITH (security_invoker = on) AS
SELECT 'treasurer'::text AS "role",
       treasurer_name        AS "name",
       treasurer_national_id AS "nationalId",
       treasurer_phone       AS "phone"
  FROM public.association_settings
UNION ALL
SELECT 'financeManager'::text,
       finance_manager_name,
       finance_manager_national_id,
       finance_manager_phone
  FROM public.association_settings;

-- ── Families list (FamilyListItem) ───────────────────────────────────────────
CREATE VIEW public.v_families WITH (security_invoker = on) AS
SELECT
  f.id                                   AS "id",
  f.family_code                          AS "familyCode",
  coalesce(father.full_name, '')          AS "fatherName",
  -- Kept out of the model but needed for search: PostgREST filters on columns,
  -- so anything the app searches by has to be selectable.
  coalesce(father.national_id, '')        AS "fatherNationalId",
  (SELECT count(*) FROM public.members m
    WHERE m.family_id = f.id AND m.kind = 'son')::int AS "sonsCount",
  (SELECT count(*) FROM public.v_member_status v
    WHERE v.family_id = f.id AND v.kind = 'son'
      AND v.eligibility = 'eligible')::int            AS "eligibleCount",
  (SELECT count(*) FROM public.v_member_status v
    WHERE v.family_id = f.id AND v.kind = 'son'
      AND v.eligibility = 'soon')::int                AS "soonCount",
  coalesce(agg.debt, 0)::numeric(12,2)::text            AS "debt",
  coalesce(agg.paid, 0)::numeric(12,2)::text            AS "paid",
  coalesce(agg.issued, 0)::numeric(12,2)::text          AS "issued",
  -- What the family WOULD be charged today, from current settings — distinct
  -- from any receivable's snapshot. index.html shows both side by side.
  (
    coalesce((SELECT v.fee FROM public.v_member_status v
               WHERE v.family_id = f.id AND v.kind = 'father'
                 AND v.status = 'نشط'), 0)
    + coalesce((SELECT sum(v.fee) FROM public.v_member_status v
                 WHERE v.family_id = f.id AND v.kind = 'son'
                   AND v.eligibility = 'eligible'), 0)
  )::text                                AS "monthlyExpected"
FROM public.families f
LEFT JOIN public.members father
       ON father.family_id = f.id AND father.kind = 'father'
LEFT JOIN LATERAL (
  SELECT sum(r.balance) AS debt, sum(r.paid) AS paid, sum(r.total) AS issued
    FROM public.receivables r
   WHERE r.family_id = f.id AND r.status <> 'ملغي'
) agg ON true;

-- ── Members list (MemberListItem) ────────────────────────────────────────────
CREATE VIEW public.v_members WITH (security_invoker = on) AS
SELECT
  v.id                          AS "id",
  v.family_id                   AS "familyId",
  v.full_name                   AS "fullName",
  CASE WHEN v.kind = 'father' THEN 'الأب' ELSE 'ابن' END AS "relation",
  coalesce(father.full_name, '') AS "familyName",
  v.national_id                 AS "nationalId",
  coalesce(v.phone, '')         AS "phone",
  coalesce(v.workplace, '')     AS "workplace",
  v.age_years                   AS "age",
  v.eligibility                 AS "eligibility",
  v.status::text                AS "membershipStatus"
FROM public.v_member_status v
LEFT JOIN public.members father
       ON father.family_id = v.family_id AND father.kind = 'father';

-- ── Receivables (ReceivableItem) ─────────────────────────────────────────────
CREATE VIEW public.v_receivables WITH (security_invoker = on) AS
SELECT
  r.id                    AS "id",
  r.family_id             AS "familyId",
  r.father_name           AS "familyName",
  f.family_code           AS "familyCode",
  r.period                AS "period",
  public.period_label(r.period) AS "periodLabel",
  r.father_fee::text      AS "fatherFee",
  r.son_fee::text         AS "sonFee",
  -- A JSON ARRAY, not a joined string: ReceivableItem reads billedSonNames as a
  -- List. Joining here would also decide the separator on the client's behalf,
  -- which is a presentation choice the screen should keep.
  coalesce(
    (SELECT jsonb_agg(l.member_name ORDER BY l.id)
       FROM public.receivable_lines l
      WHERE l.receivable_id = r.id AND l.member_kind = 'son'),
    '[]'::jsonb
  )                       AS "billedSonNames",
  r.total::text           AS "total",
  r.paid::text            AS "paid",
  r.balance::text         AS "balance",
  r.status::text          AS "status"
FROM public.receivables r
JOIN public.families f ON f.id = r.family_id;

-- ── Payments (PaymentView, allocations nested) ───────────────────────────────
CREATE VIEW public.v_payments WITH (security_invoker = on) AS
SELECT
  p.id                       AS "id",
  p.receipt_no               AS "receiptNo",
  p.family_id                AS "familyId",
  coalesce(father.full_name, f.family_code) AS "familyName",
  p.amount::text             AS "amount",
  p.method::text             AS "method",
  coalesce(p.reference, '')  AS "reference",
  coalesce(p.receiver, '')   AS "receiver",
  coalesce(p.notes, '')      AS "notes",
  p.status::text             AS "status",
  to_char(p.paid_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "paidAt",
  coalesce(
    (SELECT jsonb_agg(
              jsonb_build_object(
                'receivableId', a.receivable_id,
                'period', a.period,
                'amount', a.amount::text)
              ORDER BY a.sequence_no)
       FROM public.payment_allocations a
      WHERE a.payment_id = p.id),
    '[]'::jsonb
  )                          AS "allocations"
FROM public.payments p
JOIN public.families f ON f.id = p.family_id
LEFT JOIN public.members father
       ON father.family_id = p.family_id AND father.kind = 'father';

-- ── Treasury (CashMovementView, CashSummaryView) ─────────────────────────────
CREATE VIEW public.v_cash_movements WITH (security_invoker = on) AS
SELECT
  c.id                       AS "id",
  p.receipt_no               AS "receiptNo",
  coalesce(father.full_name, f.family_code) AS "familyName",
  c.family_id                AS "familyId",
  c.amount::text             AS "amount",
  c.method::text             AS "method",
  c.movement_type::text      AS "movementType",
  c.status::text             AS "status",
  to_char(c.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "occurredAt"
FROM public.cash_movements c
JOIN public.payments p ON p.id = c.payment_id
JOIN public.families f ON f.id = c.family_id
LEFT JOIN public.members father
       ON father.family_id = c.family_id AND father.kind = 'father';

-- Cancelled movements are excluded from every total but stay visible in the list
-- above, struck through — rule 9 requires them shown, never hidden.
CREATE VIEW public.v_cash_summary WITH (security_invoker = on) AS
SELECT
  coalesce(sum(amount), 0)::numeric(12,2)::text AS "total",
  coalesce(sum(amount) FILTER (WHERE method = 'نقداً'), 0)::numeric(12,2)::text        AS "cash",
  coalesce(sum(amount) FILTER (WHERE method = 'تحويل مصرفي'), 0)::numeric(12,2)::text AS "transfer",
  coalesce(sum(amount) FILTER (WHERE occurred_at::date = current_date), 0)::numeric(12,2)::text
    AS "today",
  coalesce(sum(amount) FILTER (WHERE date_trunc('month', occurred_at)
                                  = date_trunc('month', current_date)), 0)::numeric(12,2)::text
    AS "month",
  coalesce(sum(amount) FILTER (WHERE date_trunc('year', occurred_at)
                                  = date_trunc('year', current_date)), 0)::numeric(12,2)::text
    AS "year"
FROM public.cash_movements
WHERE status <> 'ملغي';

-- ── Audit (AuditEntry) ───────────────────────────────────────────────────────
CREATE VIEW public.v_audit WITH (security_invoker = on) AS
SELECT
  a.id                  AS "id",
  a.event_type          AS "eventType",
  a.detail              AS "detail",
  a.ref                 AS "ref",
  a.actor_name          AS "actorName",
  to_char(a.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
                        AS "occurredAt"
FROM public.audit_log a;

-- ── Users (UserAccount) ──────────────────────────────────────────────────────
-- `id` is a uuid string, not a bigint. This is the one place the migration forces
-- a Dart model change: identity now belongs to auth.users, and AppUser.id /
-- UserAccount.id become String.
CREATE VIEW public.v_users WITH (security_invoker = on) AS
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

GRANT SELECT ON
  public.v_member_status, public.v_settings, public.v_officials,
  public.v_families, public.v_members, public.v_receivables,
  public.v_payments, public.v_cash_movements, public.v_cash_summary,
  public.v_audit, public.v_users
TO authenticated;


-- ==========================================================================
-- 20260811091100_api_reads.sql
-- ==========================================================================

-- 20260811091100_api_reads.sql — the nested read shapes.
--
-- Four of the app's screens consume JSON that no flat view can produce: family
-- detail wraps family/father/sons/kpis, the dashboard wraps
-- stats/topDebtors/upcomingSons, the report wraps totals plus a payment list, and
-- the statement is an ordered debit/credit merge with a running balance.
--
-- All STABLE and SECURITY INVOKER. They run as the caller, so the RLS policies
-- from 20260811090500 still decide what is visible — a viewer calling
-- api_dashboard() sees the association's figures, an unapproved user sees zeroes
-- and empty lists, and neither is a special case anyone had to write.
--
-- Money is text in every one of them.

-- ── MemberView, reused by family detail ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.member_json(p_member_id bigint) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', v.id,
    'fullName', v.full_name,
    'nationalId', v.national_id,
    'phone', coalesce(v.phone, ''),
    'subscriptionNo', coalesce(v.subscription_no, ''),
    'dob', coalesce(to_char(v.dob, 'YYYY-MM-DD'), ''),
    'age', v.age_years,
    'nationality', v.nationality,
    'workplace', coalesce(v.workplace, ''),
    'registeredAt', to_char(v.registered_at, 'YYYY-MM-DD'),
    'membershipStatus', v.status::text,
    -- An OBJECT, not a string: MemberView reads eligibility.key AND
    -- eligibility.label, and the Arabic label is server-side on purpose so the
    -- badge can never disagree with what the prototype showed for the same
    -- member. lib/l10n has no eligibility wording to rebuild it from.
    'eligibility', jsonb_build_object(
      'key', v.eligibility,
      'label', CASE v.eligibility
                 WHEN 'eligible' THEN 'مستحق'
                 WHEN 'soon'     THEN 'قريب من السن'
                 WHEN 'under'    THEN 'غير مستحق'
                 ELSE 'موقوف'
               END),
    'currentFee', v.fee::text)
  FROM public.v_member_status v WHERE v.id = p_member_id
$$;

-- ── Endpoint 12 — GET /families/:id (FamilyDetail) ───────────────────────────
CREATE OR REPLACE FUNCTION public.api_family_detail(p_family_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'family', jsonb_build_object(
      'id', f."id",
      'familyCode', f."familyCode"),
    'father', (SELECT public.member_json(m.id) FROM public.members m
                WHERE m.family_id = p_family_id AND m.kind = 'father'),
    'sons', coalesce(
      (SELECT jsonb_agg(public.member_json(m.id) ORDER BY m.dob NULLS LAST, m.id)
         FROM public.members m
        WHERE m.family_id = p_family_id AND m.kind = 'son'),
      '[]'::jsonb),
    'kpis', jsonb_build_object(
      'sonsCount', f."sonsCount",
      'eligibleCount', f."eligibleCount",
      'soonCount', f."soonCount",
      'monthlyExpected', f."monthlyExpected",
      'debt', f."debt",
      'paid', f."paid"))
  FROM public.v_families f WHERE f."id" = p_family_id
$$;

-- ── Endpoint 14 — GET /families/:id/statement (Statement) ────────────────────
-- Rule 11: a chronological merge of charges (debit) and payments (credit) with a
-- running balance. The running total is a window function over the merged set,
-- which is the whole reason this cannot be two separate list queries stitched
-- together in Dart — the order has to be established before the balance is.
CREATE OR REPLACE FUNCTION public.api_family_statement(p_family_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH movements AS (
    SELECT r.created_at AS at,
           r.period      AS reference,
           'استحقاق'::text AS kind,
           r.total       AS debit,
           NULL::numeric AS credit,
           public.period_label(r.period) AS note
      FROM public.receivables r
     WHERE r.family_id = p_family_id AND r.status <> 'ملغي'
    UNION ALL
    SELECT p.paid_at,
           p.receipt_no,
           'دفعة'::text,
           NULL::numeric,
           p.amount,
           coalesce(nullif(p.reference, ''), p.method::text)
      FROM public.payments p
     WHERE p.family_id = p_family_id AND p.status <> 'ملغي'
  ), ordered AS (
    SELECT *,
           sum(coalesce(debit, 0) - coalesce(credit, 0))
             OVER (ORDER BY at, reference
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS balance
      FROM movements
  )
  SELECT jsonb_build_object(
    'movements', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'date', to_char(o.at AT TIME ZONE 'UTC', 'YYYY-MM-DD'),
                  'reference', o.reference,
                  'type', o.kind,
                  'debit', o.debit::text,
                  'credit', o.credit::text,
                  'balance', o.balance::text,
                  'note', o.note)
                ORDER BY o.at, o.reference)
         FROM ordered o),
      '[]'::jsonb),
    'closingBalance',
      coalesce((SELECT o.balance::text FROM ordered o
                 ORDER BY o.at DESC, o.reference DESC LIMIT 1), '0.00'))
$$;

-- ── Endpoint 26 — GET /dashboard (DashboardData) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.api_dashboard() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  WITH period AS (
    -- The PREVIOUS month, not this one. index.html labels the close button with
    -- previousPeriod() (line 452); the current month is not closed until it ends.
    SELECT to_char(date_trunc('month', current_date) - interval '1 month',
                   'YYYY-MM') AS p
  )
  SELECT jsonb_build_object(
    'stats', jsonb_build_object(
      'families', (SELECT count(*) FROM public.families),
      'sons', (SELECT count(*) FROM public.members WHERE kind = 'son'),
      'eligible', (SELECT count(*) FROM public.v_member_status
                    WHERE kind = 'son' AND eligibility = 'eligible'),
      'soon', (SELECT count(*) FROM public.v_member_status
                WHERE kind = 'son' AND eligibility = 'soon'),
      'under', (SELECT count(*) FROM public.v_member_status
                 WHERE kind = 'son' AND eligibility = 'under'),
      'debt', (SELECT coalesce(sum(balance), 0)::numeric(12,2)::text FROM public.receivables
                WHERE status <> 'ملغي'),
      'collected', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                      FROM public.cash_movements WHERE status <> 'ملغي'),
      'cash', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text FROM public.cash_movements
                WHERE status <> 'ملغي' AND method = 'نقداً'),
      'transfer', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                     FROM public.cash_movements
                    WHERE status <> 'ملغي' AND method = 'تحويل مصرفي'),
      'indebtedFamilies', (SELECT count(DISTINCT family_id)
                             FROM public.receivables
                            WHERE status <> 'ملغي' AND balance > 0)),
    'topDebtors', coalesce(
      (SELECT jsonb_agg(d ORDER BY (d ->> 'debt')::numeric DESC)
         FROM (SELECT jsonb_build_object(
                        'familyId', f."id",
                        'familyCode', f."familyCode",
                        'fatherName', f."fatherName",
                        'debt', f."debt") AS d
                 FROM public.v_families f
                WHERE f."debt"::numeric > 0
                ORDER BY f."debt"::numeric DESC
                LIMIT 10) top),
      '[]'::jsonb),
    -- Rule 2: sons approaching the eligibility age, so the treasurer can see the
    -- charge coming before it appears.
    'upcomingSons', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'sonId', v.id,
                  'sonName', v.full_name,
                  'familyId', v.family_id,
                  'fatherName', coalesce(father.full_name, ''))
                ORDER BY v.dob DESC)
         FROM public.v_member_status v
         LEFT JOIN public.members father
                ON father.family_id = v.family_id AND father.kind = 'father'
        WHERE v.kind = 'son' AND v.eligibility = 'soon'),
      '[]'::jsonb),
    'closingPeriod', (SELECT p FROM period),
    'closingPeriodLabel', (SELECT public.period_label(p) FROM period))
$$;

-- ── Endpoint 27 — GET /alerts (AlertItem) ────────────────────────────────────
-- `text` is display prose, which the Node API also produced. It stays server-side
-- so one wording is used everywhere; the client has no month names or templates
-- of its own to rebuild it from.
CREATE OR REPLACE FUNCTION public.api_alerts() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_agg(a ORDER BY (a ->> 'severity') DESC), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
             'type', 'age',
             'severity', 'warning',
             'text', v.full_name || ' يقترب من سن الاستحقاق',
             'familyId', v.family_id) AS a
      FROM public.v_member_status v
     WHERE v.kind = 'son' AND v.eligibility = 'soon'
    UNION ALL
    SELECT jsonb_build_object(
             'type', 'debt',
             'severity', 'danger',
             'text', f."fatherName" || ' — مديونية ' || f."debt",
             'familyId', f."id")
      FROM public.v_families f
     WHERE f."debt"::numeric > 0
    UNION ALL
    SELECT jsonb_build_object(
             'type', 'partial',
             'severity', 'info',
             'text', r."familyName" || ' — ' || r."periodLabel"
                     || ' مسدد جزئياً (' || r."balance" || ' متبقٍ)',
             'familyId', r."familyId")
      FROM public.v_receivables r
     WHERE r."status" = 'مسدد جزئياً'
  ) alerts
$$;

-- ── Endpoint 28 — GET /reports/financial (FinancialReport) ───────────────────
CREATE OR REPLACE FUNCTION public.api_financial_report(p_from date, p_to date)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'from', to_char(p_from, 'YYYY-MM-DD'),
    'to', to_char(p_to, 'YYYY-MM-DD'),
    'issued', (SELECT coalesce(sum(r.total), 0)::numeric(12,2)::text FROM public.receivables r
                WHERE r.status <> 'ملغي'
                  AND r.created_at::date BETWEEN p_from AND p_to),
    'issuedCount', (SELECT count(*) FROM public.receivables r
                     WHERE r.status <> 'ملغي'
                       AND r.created_at::date BETWEEN p_from AND p_to),
    'collected', (SELECT coalesce(sum(p.amount), 0)::numeric(12,2)::text FROM public.payments p
                   WHERE p.status <> 'ملغي'
                     AND p.paid_at::date BETWEEN p_from AND p_to),
    'collectedCount', (SELECT count(*) FROM public.payments p
                        WHERE p.status <> 'ملغي'
                          AND p.paid_at::date BETWEEN p_from AND p_to),
    -- Outstanding is a position, not a flow: it is the balance as it stands, not
    -- something that accrued inside the window. Filtering it by date would report
    -- a smaller debt for a shorter report, which is what the prototype did NOT do.
    'debt', (SELECT coalesce(sum(r.balance), 0)::numeric(12,2)::text FROM public.receivables r
              WHERE r.status <> 'ملغي'),
    'partialCount', (SELECT count(*) FROM public.receivables r
                      WHERE r.status = 'مسدد جزئياً'),
    'payments', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'receiptNo', p."receiptNo",
                  'familyName', p."familyName",
                  'amount', p."amount",
                  'method', p."method",
                  'reference', p."reference",
                  'paidAt', p."paidAt")
                ORDER BY p."paidAt" DESC)
         FROM public.v_payments p
        WHERE p."status" <> 'ملغي'
          AND (p."paidAt")::timestamptz::date BETWEEN p_from AND p_to),
      '[]'::jsonb))
$$;

-- ── Endpoint 16 — GET /receivables (ReceivablesPage) ────────────────────────
-- The list itself is a plain view read, but the summary has to be computed over
-- the SAME filter, so the two travel together rather than risking a client that
-- filters the list one way and the totals another.
CREATE OR REPLACE FUNCTION public.api_receivables(p_period text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH filtered AS (
    SELECT * FROM public.v_receivables r
     WHERE p_period IS NULL OR p_period = '' OR r."period" = p_period
  )
  SELECT jsonb_build_object(
    'items', coalesce(
      (SELECT jsonb_agg(to_jsonb(f) ORDER BY f."period" DESC, f."id" DESC)
         FROM filtered f),
      '[]'::jsonb),
    'summary', jsonb_build_object(
      'issued', (SELECT coalesce(sum(f."total"::numeric), 0)::numeric(12,2)::text FROM filtered f
                  WHERE f."status" <> 'ملغي'),
      'collected', (SELECT coalesce(sum(f."paid"::numeric), 0)::numeric(12,2)::text
                      FROM filtered f WHERE f."status" <> 'ملغي'),
      'outstanding', (SELECT coalesce(sum(f."balance"::numeric), 0)::numeric(12,2)::text
                        FROM filtered f WHERE f."status" <> 'ملغي')))
$$;

-- ── Endpoint 7 — GET /settings, full editable shape (EditableSettings) ───────
CREATE OR REPLACE FUNCTION public.api_settings() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'associationName', s.association_name,
    'currency', s.currency,
    'fatherFee', s.father_fee::text,
    'sonFee', s.son_fee::text,
    'eligibilityAge', s.eligibility_age::int,
    'warningMonths', s.warning_months::int,
    'systemStart', to_char(s.system_start, 'YYYY-MM-DD'),
    'autoClosePreviousMonths', s.auto_close_previous_months,
    'treasurer', jsonb_build_object(
      'name', s.treasurer_name,
      'nationalId', s.treasurer_national_id,
      'phone', s.treasurer_phone),
    'financeManager', jsonb_build_object(
      'name', s.finance_manager_name,
      'nationalId', s.finance_manager_national_id,
      'phone', s.finance_manager_phone))
  FROM public.association_settings s WHERE s.id = 1
$$;

-- ── Endpoint 4 — the caller's own profile ────────────────────────────────────
-- Readable by a pending or suspended account, because the app has to be able to
-- render "awaiting approval" for exactly those users. Reads through the
-- read_own_profile policy, not around it.
-- `familyId` is what makes the app branch. NULL means association staff and the
-- normal interface; non-NULL means a head of family, and the router sends him to
-- the family portal instead. It is the same column my_role() consults, so the
-- screen he gets and the rows RLS will give him can never disagree.
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

-- Records the sign-in. SECURITY DEFINER because `last_login_at` lives on a table
-- the client cannot write — and must not be able to, or it could rewrite anyone's.
-- The WHERE clause pins it to the caller's own row regardless.
CREATE OR REPLACE FUNCTION public.api_touch_login() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, auth AS $$
  UPDATE public.profiles SET last_login_at = now() WHERE id = auth.uid()
$$;

GRANT EXECUTE ON FUNCTION
  public.period_label(text),
  public.member_json(bigint),
  public.api_family_detail(bigint),
  public.api_family_statement(bigint),
  public.api_dashboard(),
  public.api_alerts(),
  public.api_financial_report(date, date),
  public.api_receivables(text),
  public.api_settings(),
  public.api_me(),
  public.api_touch_login()
TO authenticated;

-- ── Re-run the standing guarantees ───────────────────────────────────────────
-- 20260811090800 revoked PUBLIC execute and asserted it, but every function and
-- view created since then came out PUBLIC-executable again, because Postgres
-- grants that by default and ALTER DEFAULT PRIVILEGES does not work here (see that
-- file's header). So the lockdown has to be the LAST thing that runs, every time
-- the surface grows.
DO $revoke$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
  END LOOP;
END $revoke$;

GRANT EXECUTE ON FUNCTION
  public.role_rank(app_role), public.my_role(), public.has_role(app_role),
  public.register_payment(bigint, numeric, pay_method, text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_family(bigint, jsonb, jsonb),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status),
  public.period_label(text),
  public.member_json(bigint),
  public.api_family_detail(bigint),
  public.api_family_statement(bigint),
  public.api_dashboard(),
  public.api_alerts(),
  public.api_financial_report(date, date),
  public.api_receivables(text),
  public.api_settings(),
  public.api_me(),
  public.api_touch_login()
TO authenticated;

SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();


-- ==========================================================================
-- 20260811091200_function_lockdown.sql
-- ==========================================================================

-- 20260811091200_function_lockdown.sql — runs LAST. The real function lockdown.
--
-- ═══════════════════════════════════════════════════════════════════════════
--  WHY THIS FILE EXISTS, AND WHY THE EARLIER ONES WERE NOT ENOUGH
-- ═══════════════════════════════════════════════════════════════════════════
--
-- 20260811090800_lockdown.sql revoked EXECUTE from PUBLIC and asserted that no
-- function in `public` was PUBLIC-executable. That assertion passed on the live
-- project. And `write_audit` was still callable by any signed-in user, who could
-- forge audit-trail entries under their own name. A forged row was actually
-- written during verification.
--
-- The reason: a real Supabase project ships with
--
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public
--       GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
--
-- so every function created in `public` comes out with EXECUTE granted to `anon`
-- and `authenticated` **BY NAME**. Nothing is granted to PUBLIC, which is exactly
-- why the PUBLIC-only check reported success. Revoking from PUBLIC on a Supabase
-- project changes nothing at all.
--
-- This was invisible locally because supabase/tests/00_local_shim.sql did not
-- reproduce those default privileges. It does now, and the probe suite fails
-- without this file.
--
-- ═══════════════════════════════════════════════════════════════════════════
--
-- The rule enforced here: the set of functions callable by a client is EXACTLY
-- the allow-list below. Not "at least" — exactly. A function added later is
-- unreachable until someone adds it here on purpose, and a function removed from
-- the list but still granted fails the assertion.

-- ── The allow-list ───────────────────────────────────────────────────────────
-- Everything a signed-in client may call, and nothing else. Each write function
-- checks the caller's role internally with require_role(), so granting them all
-- to `authenticated` is safe: a viewer calling register_payment gets RUL00.
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

-- Deliberately ABSENT, and each for a reason:
--
--   write_audit          — no internal role check. Exposing it lets any signed-in
--                          user forge trail entries under someone else's name, in
--                          a system whose rule 12 exists to make the trail
--                          trustworthy. This is the function that was actually
--                          exploited during verification.
--   require_role         — pointless alone, and returns nothing useful.
--   handle_new_user      — a trigger on auth.users. Calling it directly would let
--                          a client insert profile rows.
--   touch_updated_at     — trigger body.
--   guard_*, derive_*, refuse_*  — trigger bodies. Postgres checks EXECUTE at
--                          CREATE TRIGGER time, not when a trigger fires, so
--                          withholding it costs nothing.
--   assert_*             — migration-time guards.
--   client_callable_functions — this list itself.

-- ── Revoke from every client role, then grant back the list ──────────────────
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

-- ── The standing guarantee ───────────────────────────────────────────────────
-- Exact-set, not a floor. Exposed as a function so the probe suite can call it
-- and can plant a violation to prove it fails.
CREATE OR REPLACE FUNCTION public.assert_function_grants() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_extra   text;
  v_missing text;
BEGIN
  -- Anything callable by a client that is not on the list.
  SELECT string_agg(sig, ', ' ORDER BY sig) INTO v_extra
    FROM (
      SELECT replace(replace(p.oid::regprocedure::text, 'public.', ''), ' ', '')
               AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public'
         AND NOT EXISTS (SELECT 1 FROM pg_depend d
                          WHERE d.objid = p.oid
                            AND d.classid = 'pg_proc'::regclass
                            AND d.deptype = 'e')
         AND (
           p.proacl IS NULL   -- built-in default includes PUBLIC
           OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                       WHERE a.privilege_type = 'EXECUTE'
                         AND (a.grantee = 0
                              OR a.grantee = 'anon'::regrole
                              OR a.grantee = 'authenticated'::regrole))
         )
    ) callable
   WHERE sig <> ALL (SELECT replace(a, ' ', '')
                       FROM unnest(public.client_callable_functions()) a);

  IF v_extra IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these functions are callable by anon/authenticated but are not '
      'on the allow-list in 20260811091200_function_lockdown.sql: %', v_extra;
  END IF;

  -- And anything on the list that is NOT callable — a typo in a signature would
  -- otherwise silently break a screen at runtime instead of failing the migration.
  SELECT string_agg(a, ', ') INTO v_missing
    FROM unnest(public.client_callable_functions()) a
   WHERE NOT EXISTS (
     SELECT 1 FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND replace(replace(p.oid::regprocedure::text, 'public.', ''), ' ', '')
            = replace(a, ' ', '')
        AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
   );

  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these allow-listed functions are missing or not granted — check '
      'the signatures: %', v_missing;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_function_grants() FROM PUBLIC, anon,
  authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.client_callable_functions() FROM PUBLIC, anon,
  authenticated, service_role;

SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

-- ── Tables and sequences, same reasoning ─────────────────────────────────────
-- Supabase's default privileges also GRANT ALL ON TABLES to anon and
-- authenticated. 20260811090500_rls.sql revokes that and grants back only SELECT,
-- and every table is created before it runs — but re-stating it here means the
-- last migration is the complete picture rather than something spread over three
-- files.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON ALL TABLES IN SCHEMA public FROM authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

DO $tables$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s:%s', table_name, privilege_type), ', ')
    INTO v_bad
    FROM information_schema.role_table_grants
   WHERE table_schema = 'public'
     AND grantee IN ('anon', 'authenticated')
     AND (grantee = 'anon'
          OR privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'LOCKDOWN: unexpected table privileges: %', v_bad;
  END IF;
END $tables$;


-- ============================================================================
--  Post-apply checks. These run inside the same transaction, so a failure here
--  rolls the whole schema back rather than leaving it in place unverified.
-- ============================================================================

DO $verify$
DECLARE
  v_tables int;
  v_views  int;
  v_funcs  int;
  v_rls    int;
BEGIN
  SELECT count(*) INTO v_tables FROM pg_tables
   WHERE schemaname = 'public'
     AND tablename IN ('profiles','association_settings','families','members',
                       'receivables','receivable_lines','payments',
                       'payment_allocations','cash_movements','audit_log',
                       'family_access_codes');
  IF v_tables <> 11 THEN
    RAISE EXCEPTION 'expected 11 tables, found %', v_tables;
  END IF;

  SELECT count(*) INTO v_views FROM pg_views
   WHERE schemaname = 'public' AND viewname LIKE 'v\_%';
  IF v_views < 11 THEN
    RAISE EXCEPTION 'expected at least 11 v_* views, found %', v_views;
  END IF;

  SELECT count(*) INTO v_funcs FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('register_payment','cancel_payment','generate_period',
                       'auto_close_periods','save_family','update_settings',
                       'set_user_access','purge_financial_data','purge_all_data',
                       'issue_family_code','redeem_family_code','my_family_id',
                       'api_dashboard','api_family_detail','api_family_statement',
                       'api_receivables','api_alerts','api_financial_report',
                       'api_settings','api_me');
  IF v_funcs <> 20 THEN
    RAISE EXCEPTION 'expected 20 API functions, found %', v_funcs;
  END IF;

  -- Every table must have RLS ON. A table without it is readable by anyone
  -- holding the anon key, which is everyone.
  SELECT count(*) INTO v_rls FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity;
  IF v_rls > 0 THEN
    RAISE EXCEPTION '% table(s) in public have RLS disabled', v_rls;
  END IF;

  RAISE INFO 'schema verified: % tables, % views, % functions, RLS on everywhere',
    v_tables, v_views, v_funcs;
END $verify$;

-- The two standing guarantees, re-run last.
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed.
SELECT 'tables' AS kind, count(*)::text AS n FROM pg_tables
 WHERE schemaname = 'public'
UNION ALL SELECT 'views', count(*)::text FROM pg_views
 WHERE schemaname = 'public'
UNION ALL SELECT 'functions', count(*)::text FROM pg_proc p
 JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'
UNION ALL SELECT 'policies', count(*)::text FROM pg_policies
 WHERE schemaname = 'public';
