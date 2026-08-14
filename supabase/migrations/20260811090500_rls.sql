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
