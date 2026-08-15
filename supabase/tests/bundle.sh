#!/usr/bin/env bash
# bundle.sh — concatenates every migration into ONE file to paste into the
# Supabase SQL editor.
#
# Why this exists: `supabase db push` needs the database password or a personal
# access token, and neither is available here. The SQL editor needs neither — it
# runs as `postgres` inside the project. One paste applies the whole schema.
#
# What is deliberately NOT included: supabase/tests/00_local_shim.sql. That file
# recreates the `auth` schema, `auth.users`, and the anon/authenticated/service_role
# roles so the migrations can run on a bare local Postgres. A real project already
# has all of it, and applying the shim would collide with the real thing.
#
# The bundle is wrapped in a single transaction, so a failure anywhere leaves the
# project exactly as it was rather than half-migrated.
#
#   bash supabase/tests/bundle.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/../APPLY_TO_SUPABASE.sql"

{
  cat <<'HEADER'
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
HEADER

  for f in "$HERE/../migrations"/*.sql; do
    printf '\n\n-- ==========================================================================\n'
    printf -- '-- %s\n' "$(basename "$f")"
    printf -- '-- ==========================================================================\n\n'
    cat "$f"
  done

  cat <<'FOOTER'


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
     AND tablename IN ('profiles','association_settings','adeels',
                       'receivables','payments','payment_allocations',
                       'cash_movements','audit_log','adeel_access_codes',
                       'closed_periods');
  IF v_tables <> 10 THEN
    RAISE EXCEPTION 'expected 10 tables, found %', v_tables;
  END IF;

  SELECT count(*) INTO v_views FROM pg_views
   WHERE schemaname = 'public' AND viewname LIKE 'v\_%';
  IF v_views < 9 THEN
    RAISE EXCEPTION 'expected at least 9 v_* views, found %', v_views;
  END IF;

  SELECT count(*) INTO v_funcs FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('register_payment','cancel_payment','generate_period',
                       'auto_close_periods','save_adeel','delete_adeel',
                       'update_settings','set_user_access',
                       'purge_financial_data','purge_all_data',
                       'issue_adeel_code','redeem_adeel_code','my_adeel_id',
                       'api_dashboard','api_adeel_detail','api_adeel_statement',
                       'api_receivables','api_alerts','api_financial_report',
                       'api_settings','api_me','api_closable_periods');
  IF v_funcs <> 22 THEN
    RAISE EXCEPTION 'expected 22 API functions, found %', v_funcs;
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
FOOTER
} > "$OUT"

echo "wrote $OUT"
echo "  $(wc -l < "$OUT" | tr -d ' ') lines, $(wc -c < "$OUT" | tr -d ' ') bytes"

# ---------------------------------------------------------------------------
#  The same schema, for a project that already holds an OLD one.
#
#  APPLY_TO_SUPABASE.sql cannot be run twice, and cannot be run over the
#  family/member schema: `CREATE TYPE` has no IF NOT EXISTS, so the first enum
#  aborts the whole transaction with 42710. The honest fix for a project that
#  is already wrong is to empty `public` and rebuild it, which is what this
#  second file does — the identical body, behind a reset preamble.
#
#  It is DERIVED from $OUT rather than assembled again, so the two can never
#  drift into applying different schemas.
# ---------------------------------------------------------------------------
RESET="$HERE/../RESET_AND_APPLY.sql"

# Everything up to and including the first `BEGIN;` is the fresh-project header,
# and it is replaced wholesale. Sliced with tail rather than awk because the
# migrations are a mix of LF and CRLF files and awk rewrites the line endings of
# whatever passes through it — which would break the byte-identity asserted
# below while changing nothing a reader could see.
BODY_FROM=$(grep -n -m1 '^BEGIN;' "$OUT" | cut -d: -f1)
tail -n +$((BODY_FROM + 1)) "$OUT" > "$RESET.body"

{
  cat <<'RESETHEADER'
-- ============================================================================
--  Family App — REBUILD a project that already has a schema.
--
--  GENERATED FILE. Do not edit. Regenerate with:
--      bash supabase/tests/bundle.sh
--
--  ⚠ THIS DESTROYS EVERYTHING IN THE `public` SCHEMA ⚠
--
--  Every table, view, function, policy and ROW of application data in `public`
--  is dropped and the schema is rebuilt from nothing. There is no backup and no
--  undo. Read the two paragraphs below before running it.
--
--  WHEN TO USE IT — and only then
--    The project holds an OLD schema (the family/member one) and you want the
--    عديل schema in its place. APPLY_TO_SUPABASE.sql cannot do that: it targets
--    a fresh project, and `CREATE TYPE app_role` fails with 42710 the moment the
--    type already exists. Use APPLY_TO_SUPABASE.sql on a NEW project; use this
--    one to convert an existing project you are willing to empty.
--
--  WHAT SURVIVES
--    Auth accounts. `auth.users` is Supabase's, not ours, and is untouched — so
--    everyone who signed in keeps their login. What they LOSE is their row in
--    public.profiles, which means their role and approval are gone: after this
--    runs, every account is a pending viewer again and step 4 below is not
--    optional. Storage buckets and anything in other schemas also survive.
--
--  WHAT DOES NOT
--    Every عديل, receivable, payment, cash movement and audit entry. If this
--    project holds real association records, take a backup from
--    Database → Backups FIRST, or apply to a new project instead.
--
--  HOW TO APPLY
--    Supabase dashboard → SQL Editor → New query → paste all of this → Run.
--    It is one transaction: if anything fails, the OLD schema is still there.
--
--  AFTER APPLYING
--    1. Run supabase/VERIFY_INSTALL.sql — it names what actually landed.
--    2. Authentication → Providers → Google: on, with your client ID + secret.
--    3. Authentication → URL Configuration → Redirect URLs:
--         com.family.app://login-callback
--    4. Sign in to the app once (you will see "awaiting approval"), then run
--       supabase/bootstrap_first_admin.sql with your address.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
--  The reset. Everything below this point is byte-identical to
--  APPLY_TO_SUPABASE.sql.
-- ----------------------------------------------------------------------------

-- Preflight: refuse if anything OTHER than this application lives in public.
--
-- CASCADE takes extensions with it. Supabase installs them in `extensions` by
-- default, but a project that ran `CREATE EXTENSION pgcrypto` without a schema
-- put it in public — and dropping it there silently breaks every column default
-- and function that calls into it, in this project and any other app sharing the
-- database. That is not a cost to pay by accident, so this refuses instead and
-- names what it found. Nothing has been dropped when it raises.
DO $preflight$
DECLARE
  v_ext text;
BEGIN
  SELECT string_agg(e.extname, ', ' ORDER BY e.extname) INTO v_ext
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
   WHERE n.nspname = 'public';

  IF v_ext IS NOT NULL THEN
    RAISE EXCEPTION
      'REFUSING TO RESET: extension(s) installed in public: %. '
      'Dropping the schema would drop them. Move each one first with '
      '"ALTER EXTENSION <name> SET SCHEMA extensions;" then re-run this file.',
      v_ext;
  END IF;
END $preflight$;

-- CASCADE also drops the trigger this schema puts on auth.users: it lives in
-- the auth schema but calls a function in public, so it goes with the function.
-- The migrations recreate both.
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- Supabase's own baseline for a new project, restored exactly. The migrations
-- are written against it — 20260811091200_function_lockdown.sql REVOKEs the
-- blanket grants these lines hand out, and it can only revoke what exists.
-- Leave them off and the project stops resembling a fresh one for anything
-- created later.
ALTER SCHEMA public OWNER TO pg_database_owner;
COMMENT ON SCHEMA public IS 'standard public schema';

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL   ON SCHEMA public TO postgres, pg_database_owner;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES    TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
RESETHEADER

  cat "$RESET.body"
} > "$RESET"

# The whole point of deriving one file from the other: prove they still carry
# the same schema. A reset that quietly applied a different one would be
# discovered by whoever ran it, on their live project.
if [ "$(tail -n +$((BODY_FROM + 1)) "$OUT" | md5sum | cut -d' ' -f1)" \
  != "$(tail -n "$(wc -l < "$RESET.body")" "$RESET" | md5sum | cut -d' ' -f1)" ]; then
  echo "FATAL: RESET_AND_APPLY.sql body differs from APPLY_TO_SUPABASE.sql" >&2
  exit 1
fi
rm -f "$RESET.body"

echo "wrote $RESET"
echo "  $(wc -l < "$RESET" | tr -d ' ') lines, $(wc -c < "$RESET" | tr -d ' ') bytes"
