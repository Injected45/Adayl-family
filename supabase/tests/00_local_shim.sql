-- 00_local_shim.sql — LOCAL TEST HARNESS ONLY. NEVER APPLIED TO SUPABASE.
--
-- Supabase provisions the `auth` schema, the `anon` / `authenticated` /
-- `service_role` roles, and the auth.uid() / auth.role() / auth.jwt() helpers
-- before any user migration runs. This file recreates them on a bare Postgres
-- so the probes exercise the same RLS surface the real platform will.
--
-- The definitions below are Supabase's own, transcribed. auth.uid() reads the
-- JWT claim out of a GUC exactly as PostgREST sets it, which is what makes
-- `SET LOCAL request.jwt.claims` a faithful stand-in for a real bearer token.

CREATE SCHEMA IF NOT EXISTS auth;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END $$;

GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

-- Supabase's auth.users. Only the columns this project reads are modelled.
CREATE TABLE IF NOT EXISTS auth.users (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email      text UNIQUE,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;

GRANT EXECUTE ON FUNCTION auth.uid(), auth.role(), auth.jwt(), auth.email()
  TO anon, authenticated, service_role;
GRANT SELECT ON auth.users TO authenticated, service_role;

-- ── Supabase's OWN default privileges ────────────────────────────────────────
-- This block is the reason the shim exists at all, and it was missing.
--
-- A real Supabase project ships with:
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public
--       GRANT ALL ON TABLES    TO postgres, anon, authenticated, service_role;
--     ... same for FUNCTIONS and SEQUENCES
--
-- so every function created in `public` comes out with EXECUTE granted to `anon`
-- and `authenticated` BY NAME — not through PUBLIC. A lockdown that only revokes
-- from PUBLIC therefore changes nothing, and `write_audit` stayed callable by any
-- signed-in user.
--
-- That was found on the live project, not here, because this shim did not
-- reproduce the platform's defaults. It does now, so the probe suite fails
-- locally if the lockdown ever regresses.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
