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
-- changing them would break the client.

-- member_kind ('father','son') is GONE, and so is the household it discriminated
-- inside. The association no longer bills a family through its head: every عديل
-- is billed in his own right, for the same monthly subscription, so `families`
-- and `members` collapsed into the single `adeels` table in the next migration
-- but one. Removing the type rather than leaving it unused is deliberate — an
-- unused enum is an invitation to reintroduce the two-tier model by accident.
--
-- member_status keeps its name: an عديل IS a member of the association, and the
-- three labels mean exactly what they always meant. Only the entity they hang
-- off changed.
CREATE TYPE app_role       AS ENUM ('viewer','treasurer','financeManager','admin');
CREATE TYPE app_status     AS ENUM ('pending','approved','suspended');
CREATE TYPE member_status  AS ENUM ('نشط','موقوف','متوفى');
CREATE TYPE recv_status    AS ENUM ('غير مسدد','مسدد جزئياً','مسدد بالكامل','ملغي');
CREATE TYPE pay_method     AS ENUM ('نقداً','تحويل مصرفي');
CREATE TYPE pay_status     AS ENUM ('معتمد','ملغي');
CREATE TYPE cash_kind      AS ENUM ('تحصيل');

-- ── The TWO kinds of spending, which are different in kind and not in degree ──
-- The association spends its money on exactly two things, and it asked for them
-- to be told apart at the top of the form rather than buried in one long list:
--
--   لمشترك — money to a NAMED man on the register. The عديل IS the heading;
--            asking which category besides would be asking the same question
--            twice.
--   جماعي  — money spent on an OCCASION, for everybody. Nobody receives it in
--            the sense a member does, so there is no payee at all, and the
--            heading is the whole answer to "what was it for".
--
-- Modelled as an enum on the row rather than as two tables: they share every
-- money column, the treasury sums both, and rule 9 reverses both identically.
-- What differs is only which of two shapes the row must take — and that is a
-- CHECK constraint, which is where a rule of this kind belongs.
CREATE TYPE disbursement_kind AS ENUM ('لمشترك','جماعي');

-- ── What a COLLECTIVE disbursement was for ───────────────────────────────────
-- A FIXED list, chosen over free text deliberately: "كم أنفقنا على كل بند" is
-- the only question this column exists to answer, and free text turns
-- عزاء / العزاء / مصاريف عزاء into three separate answers to it.
--
-- These five are the association's own, named by it. There is deliberately no
-- 'أخرى': the earlier nine had one because they tried to cover rent and bank
-- fees as well, and a list that broad always needs an escape hatch. These five
-- describe occasions the association actually holds, and an occasion that fits
-- none of them is a reason to name a sixth rather than to file it under a
-- heading that says nothing.
--
-- An ENUM rather than a lookup table: a sixth is a schema change, which is the
-- correct amount of friction for a category every historical report groups by.
-- Postgres keeps the label on the row, so a heading retired later still reads
-- correctly on the vouchers that used it.
CREATE TYPE expense_category AS ENUM (
  'فرح',
  'عزاء',
  'فطور رمضان',
  'مناسبة اجتماعية',
  'حالات طارئة'
);

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
