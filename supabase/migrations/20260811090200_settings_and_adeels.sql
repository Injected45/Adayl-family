-- 20260811090200_settings_and_adeels.sql
-- Ports api/migrations/003, 004, 005.

-- ─────────────────────────────────────────────────────────────────────────────
-- association_settings — the singleton. Drives every FUTURE calculation and
-- never alters history: a receivable snapshots these values at creation.
--
-- father_fee + son_fee collapsed into ONE member_fee. The association charges
-- every عديل the same monthly subscription, so a second rate had nothing left to
-- distinguish.
--
-- eligibility_age and warning_months are GONE with the age gate. Billing no
-- longer asks how old anyone is: an عديل on the register with status 'نشط' is
-- billed, full stop. Everything they drove — the مؤهل / قريباً / دون السن
-- states, the "approaching eligibility" dashboard card — went with them.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.association_settings (
  id                          smallint      NOT NULL DEFAULT 1,
  association_name            text          NOT NULL DEFAULT 'مشروع جمعية العدايل',
  currency                    text          NOT NULL DEFAULT 'د.ل',
  member_fee                  numeric(12,2) NOT NULL DEFAULT 20.00,
  system_start                date          NOT NULL,
  auto_close_previous_months  boolean       NOT NULL DEFAULT true,

  treasurer_name              text          NOT NULL DEFAULT '',
  treasurer_phone             text          NOT NULL DEFAULT '',

  finance_manager_name        text          NOT NULL DEFAULT '',
  finance_manager_phone       text          NOT NULL DEFAULT '',

  -- ── The association's own receiving bank account ──────────────────────────
  -- Where a تحويل مصرفي lands. ONE account, held here rather than typed per
  -- payment, for the same reason the officials' names are: it is a property of
  -- the association, and a treasurer retyping it on every receipt would produce
  -- a different digit string sooner or later — on the one field whose whole
  -- purpose is matching the bank's statement.
  --
  -- Readable by every approved member INCLUDING an عديل on the portal
  -- (read_settings_adeel), which is intended: he is the one being asked to
  -- transfer, so the account he must send to cannot be staff-only.
  --
  -- Empty by default and never validated for format. Libyan IBANs, plain
  -- account numbers and whatever a given bank prints are all legitimate here,
  -- and a CHECK would refuse the association's real account on the day they
  -- open one at a different bank.
  bank_account_no             text          NOT NULL DEFAULT '',
  bank_account_name           text          NOT NULL DEFAULT '',

  updated_by                  uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at                  timestamptz   NOT NULL DEFAULT now(),

  PRIMARY KEY (id),
  CONSTRAINT ck_settings_singleton CHECK (id = 1),
  CONSTRAINT ck_settings_fee       CHECK (member_fee >= 0)
);

CREATE TRIGGER trg_settings_touch
  BEFORE UPDATE ON public.association_settings
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- system_start is 1 January of the current year, as
-- `new Date().getFullYear()+"-01-01"` produced.
INSERT INTO public.association_settings (id, system_start)
VALUES (1, make_date(extract(year FROM current_date)::int, 1, 1))
ON CONFLICT (id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- adeels — THE register. One row per عديل, and the unit everything else hangs
-- off: receivables, payments, cash movements and the portal binding.
--
-- This ONE table replaces the previous `families` + `members` pair. The old
-- schema modelled a household billed through its head — father{} plus sons[],
-- with a `kind` discriminator, a partial unique index enforcing one father per
-- family, and two fee rates. The association stopped working that way: every
-- عديل carries the same subscription in his own right, so the hierarchy had
-- nothing left to express and the join it forced onto every read was pure cost.
--
-- adeel_code is a GENERATED column. MySQL forbade generated columns that
-- reference AUTO_INCREMENT, which forced the API to INSERT then UPDATE inside
-- the creating transaction. Postgres computes it from the identity value in the
-- same row, so the code cannot collide and no second statement exists to fail
-- between.
--
-- ⚠ THERE IS NO NATURAL KEY ANY MORE. `national_id NOT NULL UNIQUE` was business
-- rule 10 and it is gone at the association's request. Nothing now stops the
-- same person being entered twice, and a duplicate row is billed the monthly fee
-- a second time — so a duplicate is not a cosmetic problem here, it is an
-- overcharge that reconciles perfectly and looks correct on every report.
--
-- `adeel_code` does not close that hole: it is GENERATED from the identity, so a
-- second row for the same man simply gets a second code.
--
-- Nor is there anything left to promote INTO a key. `subscription_no` was the
-- one candidate the association issued itself, and it was removed at their
-- request along with `nationality` and `workplace`. Restoring the guarantee now
-- means adding a column back first, not adding a constraint.
--
-- WHAT A ROW HOLDS, and it is deliberately little: a name, a phone, a date of
-- birth, a registration date, a status and free-text notes. Everything else the
-- association decided it does not collect.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.adeels (
  id              bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  adeel_code      text          GENERATED ALWAYS AS ('A-' || lpad(id::text, 4, '0')) STORED,
  full_name       text          NOT NULL,
  phone           text,
  dob             date,
  registered_at   date          NOT NULL,
  status          member_status NOT NULL DEFAULT 'نشط',
  notes           text,
  legacy_id       text,
  created_at      timestamptz   NOT NULL DEFAULT now(),
  created_by      uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at      timestamptz   NOT NULL DEFAULT now(),
  updated_by      uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,

  CONSTRAINT uq_adeels_code        UNIQUE (adeel_code),
  CONSTRAINT uq_adeels_legacy      UNIQUE (legacy_id),
  CONSTRAINT ck_adeels_name        CHECK (btrim(full_name) <> '')
);

CREATE INDEX ix_adeels_name   ON public.adeels (full_name);
CREATE INDEX ix_adeels_status ON public.adeels (status);
CREATE INDEX ix_adeels_dob    ON public.adeels (dob);

CREATE TRIGGER trg_adeels_touch
  BEFORE UPDATE ON public.adeels
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- What is LEFT of rule 10: a date of birth cannot be in the future. A trigger,
-- not a CHECK, because CURRENT_DATE is not immutable and Postgres rejects it in
-- a CHECK constraint for the same reason MySQL did. The rule's other half — the
-- unique national ID — was removed with the column above.
--
-- The old carried-forward conflict here (index.html validated sons' dates of
-- birth but not the father's) died with the father/son split. There is one kind
-- of row now, and it gets the strict check.
CREATE OR REPLACE FUNCTION public.guard_adeel_dob() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.dob IS NOT NULL AND NEW.dob > current_date THEN
    RAISE EXCEPTION 'تاريخ الميلاد لا يمكن أن يكون مستقبلياً'
      USING ERRCODE = 'RUL10';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_adeels_dob
  BEFORE INSERT OR UPDATE ON public.adeels
  FOR EACH ROW EXECUTE FUNCTION public.guard_adeel_dob();

-- ─────────────────────────────────────────────────────────────────────────────
-- profiles.adeel_id → adeels.id
--
-- Declared here rather than on the column, because profiles is created one
-- migration earlier than adeels and a REFERENCES clause cannot point forward.
-- See the header of profiles for why the portal discriminator is a column rather
-- than a new app_role value.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD CONSTRAINT fk_profiles_adeel
  FOREIGN KEY (adeel_id) REFERENCES public.adeels(id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────
-- adeel_access_codes — one code per عديل, the thing he types once to bind his
-- Google account to his own subscription and nothing else.
--
-- PRIMARY KEY (adeel_id): one live code each. Re-issuing overwrites, which is
-- what "regenerate" means and also what revokes the old code — there is no
-- second row for the previous one to keep working from.
--
-- Re-issuing does NOT sign anybody out. The binding lives on profiles.adeel_id
-- once redeemed; the code is only the thing that creates that binding. So an
-- admin can regenerate freely without breaking someone who is already in.
--
-- THE CODE IS STORED IN PLAINTEXT, deliberately, and it is worth being explicit
-- about the trade:
--   * only an admin can read this table (RLS, 20260811090500), and only through
--     an admin-gated function; anon and every other role get nothing;
--   * the admin has to be able to re-read a code to resend it over WhatsApp. A
--     hash would force "regenerate" every time the message is lost, which for a
--     non-technical treasurer is a footgun, not a safeguard;
--   * the code reaches the عديل over WhatsApp anyway, so it already exists in
--     plaintext somewhere far less protected than this table.
-- What a hash WOULD buy is protection of old codes in a leaked backup. Against
-- that: the codes grant read-only access to one man's own figures, and rotating
-- every code is one button each.
--
-- `code` is 12 characters from an unambiguous 32-letter alphabet ≈ 60 bits.
-- Guessing one over HTTPS is not a threat worth rate-limiting for; guessing it
-- offline buys the attacker one عديل's balance.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.adeel_access_codes (
  adeel_id    bigint      PRIMARY KEY REFERENCES public.adeels(id) ON DELETE CASCADE,
  code        text        NOT NULL,
  issued_at   timestamptz NOT NULL DEFAULT now(),
  issued_by   uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  redeemed_at timestamptz,
  redeemed_by uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,

  CONSTRAINT uq_adeel_code     UNIQUE (code),
  CONSTRAINT ck_adeel_code_len CHECK (char_length(code) BETWEEN 8 AND 64)
);
