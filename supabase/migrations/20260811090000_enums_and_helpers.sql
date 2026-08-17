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

-- ── What the association spent the money ON ──────────────────────────────────
-- A FIXED list, chosen over free text deliberately: "كم أنفقنا على كل بند" is
-- the only question a disbursement record exists to answer, and free text turns
-- كهرباء / الكهرباء / فاتورة كهرباء into three separate answers to it.
--
-- 'أخرى' is the escape hatch, and the voucher's free `note` is what explains it.
-- Without it a spend that fits no heading could not be recorded at all, which
-- would push the treasurer into miscategorising rather than into asking for a
-- new heading.
--
-- An ENUM rather than a lookup table: the association named these nine and a
-- tenth is a schema change, which is the correct amount of friction for a
-- category that every historical report is grouped by. Postgres keeps the label
-- on the row, so a heading retired later still reads correctly on the vouchers
-- that used it.
CREATE TYPE expense_category AS ENUM (
  'إعانة اجتماعية',
  'عزاء ووفاة',
  'مناسبة زواج',
  'علاج ومرض',
  'مصاريف إدارية',
  'إيجار وخدمات',
  'ضيافة واجتماعات',
  'رسوم مصرفية',
  'أخرى'
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
