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
