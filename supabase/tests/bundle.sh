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
FOOTER
} > "$OUT"

echo "wrote $OUT"
echo "  $(wc -l < "$OUT" | tr -d ' ') lines, $(wc -c < "$OUT" | tr -d ' ') bytes"
