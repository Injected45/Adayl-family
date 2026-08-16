-- ============================================================================
--  VERIFY_INSTALL.sql — did the schema actually land?
--
--  READ-ONLY. It creates nothing, drops nothing and writes nothing. Safe to run
--  on a live project as often as you like.
--
--  HOW TO USE
--    Supabase dashboard → SQL Editor → New query → paste all of this → Run.
--    Read the `status` column. Every row must say OK.
--
--  WHAT IT IS FOR
--    APPLY_TO_SUPABASE.sql is one transaction, so it either lands completely or
--    not at all — there is no half-applied state to find. What this script
--    actually answers is the question that DOES have a wrong answer:
--    "is what is in the database the schema I think it is?" A project that
--    still holds the OLD family/member schema, or one where the bundle was
--    never run, or one where the first admin was never bootstrapped, all look
--    identical from the app: a login screen that goes nowhere.
-- ============================================================================

WITH
-- ── What the current schema is supposed to contain ──────────────────────────
expected_tables(n) AS (
  VALUES ('profiles'), ('association_settings'), ('adeels'),
         ('adeel_access_codes'), ('receivables'), ('payments'),
         ('payment_allocations'), ('cash_movements'), ('audit_log'),
         ('closed_periods')
),
expected_views(n) AS (
  VALUES ('v_settings'), ('v_officials'), ('v_adeels'), ('v_receivables'),
         ('v_payments'), ('v_cash_movements'), ('v_cash_summary'),
         ('v_audit'), ('v_users')
),
expected_funcs(n) AS (
  VALUES ('register_payment'), ('cancel_payment'), ('generate_period'),
         ('auto_close_periods'), ('save_adeel'), ('delete_adeel'),
         ('update_settings'), ('set_user_access'), ('purge_financial_data'),
         ('purge_all_data'), ('issue_adeel_code'), ('redeem_adeel_code'),
         ('api_adeel_detail'), ('api_adeel_statement'), ('api_dashboard'),
         ('api_alerts'), ('api_financial_report'), ('api_receivables'),
         ('api_settings'), ('api_me'), ('api_touch_login'),
         ('my_role'), ('my_adeel_id'), ('has_role'), ('require_role')
),
-- Tables that must NOT exist. Their presence means the project is still on the
-- family/member schema — the bundle was never run here, or was run on a
-- different project.
forbidden_tables(n) AS (
  VALUES ('families'), ('members'), ('receivable_lines'), ('family_access_codes')
),

-- ── What is actually there ──────────────────────────────────────────────────
have_tables AS (
  SELECT tablename AS n FROM pg_tables WHERE schemaname = 'public'
),
have_views AS (
  SELECT viewname AS n FROM pg_views WHERE schemaname = 'public'
),
have_funcs AS (
  SELECT DISTINCT p.proname AS n
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public'
),

results(sort_key, check_name, detail, status) AS (

  -- 1. Tables
  SELECT 1, 'tables',
         CASE WHEN count(*) = 0 THEN (SELECT count(*)::text FROM expected_tables) || ' present'
              ELSE 'MISSING: ' || string_agg(n, ', ' ORDER BY n) END,
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'FAIL' END
    FROM (SELECT n FROM expected_tables EXCEPT SELECT n FROM have_tables) m

  -- 2. Views
  UNION ALL
  SELECT 2, 'views',
         CASE WHEN count(*) = 0 THEN (SELECT count(*)::text FROM expected_views) || ' present'
              ELSE 'MISSING: ' || string_agg(n, ', ' ORDER BY n) END,
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'FAIL' END
    FROM (SELECT n FROM expected_views EXCEPT SELECT n FROM have_views) m

  -- 3. Functions
  UNION ALL
  SELECT 3, 'functions',
         CASE WHEN count(*) = 0 THEN (SELECT count(*)::text FROM expected_funcs) || ' present'
              ELSE 'MISSING: ' || string_agg(n, ', ' ORDER BY n) END,
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'FAIL' END
    FROM (SELECT n FROM expected_funcs EXCEPT SELECT n FROM have_funcs) m

  -- 4. The OLD schema must be gone. This is the check that catches "I ran it on
  --    the wrong project" and "I never ran it at all".
  UNION ALL
  SELECT 4, 'old family schema is absent',
         CASE WHEN count(*) = 0 THEN 'no family/member tables'
              ELSE 'STILL PRESENT: ' || string_agg(n, ', ' ORDER BY n)
                   || ' — this project is on the OLD schema' END,
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'FAIL' END
    FROM (SELECT n FROM forbidden_tables INTERSECT SELECT n FROM have_tables) f

  -- 5. RLS on every table. A table without it is readable by anyone holding the
  --    publishable key, which is everyone.
  UNION ALL
  SELECT 5, 'row level security',
         CASE WHEN count(*) = 0 THEN 'enabled on every table'
              ELSE 'DISABLED ON: ' || string_agg(c.relname, ', ' ORDER BY c.relname) END,
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'FAIL' END
    FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
   WHERE ns.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity

  -- 6. Policies. Sixteen on a correct install; fewer means a policy failed to
  --    create, which RLS would then silently deny rather than error on.
  UNION ALL
  SELECT 6, 'policies',
         count(*)::text || ' (expected 17)',
         CASE WHEN count(*) = 17 THEN 'OK' ELSE 'CHECK' END
    FROM pg_policies WHERE schemaname = 'public'

  -- 7. Money is text. Reads the live view rather than trusting the definition:
  --    if the ::text casts were lost, this is where the treasury starts running
  --    on binary floating point.
  UNION ALL
  SELECT 7, 'money reaches the client as text',
         'v_adeels.debt is ' || coalesce(
           (SELECT data_type FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'v_adeels'
               AND column_name = 'debt'), 'MISSING'),
         CASE WHEN (SELECT data_type FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'v_adeels'
                       AND column_name = 'debt') = 'text'
              THEN 'OK' ELSE 'FAIL' END

  -- 8. The settings singleton, seeded by the migration itself.
  UNION ALL
  SELECT 8, 'association settings row',
         coalesce((SELECT 'member_fee = ' || member_fee::text
                     FROM public.association_settings WHERE id = 1), 'MISSING'),
         CASE WHEN EXISTS (SELECT 1 FROM public.association_settings WHERE id = 1)
              THEN 'OK' ELSE 'FAIL' END

  -- 9. THE STEP THAT IS NOT IN THE BUNDLE. Every profile is created
  --    viewer/pending, so without bootstrap_first_admin.sql there is nobody who
  --    can approve anybody and the app is a locked door for everyone.
  UNION ALL
  SELECT 9, 'first admin bootstrapped',
         CASE WHEN count(*) = 0
              THEN 'NO approved admin — run supabase/bootstrap_first_admin.sql'
              ELSE count(*)::text || ' approved admin(s): '
                   || string_agg(email, ', ' ORDER BY email) END,
         CASE WHEN count(*) > 0 THEN 'OK' ELSE 'TODO' END
    FROM public.profiles WHERE role = 'admin' AND status = 'approved'

  -- 10. Google sign-in is a dashboard setting, not SQL, so this only reports
  --     whether anyone has ever signed in at all.
  UNION ALL
  SELECT 10, 'accounts that have signed in',
         count(*)::text || ' profile(s)',
         CASE WHEN count(*) > 0 THEN 'OK' ELSE 'TODO' END
    FROM public.profiles

  -- ── 11. THE CHECK THIS FILE EXISTED WITHOUT, AND SHOULD NOT HAVE ──────────
  -- VERIFY_INSTALL is here to tell apart the several ways a project ends up as
  -- "a login screen that goes nowhere". This is the most common of them and it
  -- was the one thing not checked.
  --
  -- trg_auth_user_created sits on auth.users but calls a function in `public`,
  -- so DROP SCHEMA public CASCADE — what RESET_AND_APPLY.sql runs — takes it.
  -- Without it, creating an account raises and GoTrue answers "Database error
  -- saving new user". EXISTING accounts are unaffected, because signing in
  -- inserts nothing — which is why it reads as "it works for me" to whoever
  -- checks.
  UNION ALL
  SELECT 11, 'sign-in trigger (new accounts)',
         CASE
           WHEN NOT EXISTS (SELECT 1 FROM pg_proc p
                              JOIN pg_namespace n ON n.oid = p.pronamespace
                             WHERE n.nspname = 'public'
                               AND p.proname = 'handle_new_user')
             THEN 'handle_new_user() MISSING — nobody new can sign in'
           WHEN NOT EXISTS (SELECT 1 FROM pg_trigger
                             WHERE tgname = 'trg_auth_user_created'
                               AND NOT tgisinternal)
             THEN 'trg_auth_user_created MISSING — run '
                  || 'supabase/PATCH_20260816_restore_signin_trigger.sql'
           WHEN EXISTS (SELECT 1 FROM pg_trigger
                         WHERE tgname = 'trg_auth_user_created'
                           AND NOT tgisinternal AND tgenabled = 'D')
             THEN 'trigger present but DISABLED — it creates no profile'
           ELSE 'present and enabled'
         END,
         CASE
           WHEN EXISTS (SELECT 1 FROM pg_trigger
                         WHERE tgname = 'trg_auth_user_created'
                           AND NOT tgisinternal AND tgenabled <> 'D')
            AND EXISTS (SELECT 1 FROM pg_proc p
                          JOIN pg_namespace n ON n.oid = p.pronamespace
                         WHERE n.nspname = 'public'
                           AND p.proname = 'handle_new_user')
             THEN 'OK' ELSE 'FAIL'
         END

  -- 12. The other half of the same fault. A reset empties `public` but leaves
  --     auth.users, and signing in creates no profile because it inserts
  --     nothing — so everyone who already had an account is stranded on "this
  --     account has no row in the database" until they are backfilled.
  UNION ALL
  SELECT 12, 'accounts with no profile row',
         CASE WHEN count(*) = 0 THEN 'none — every account has a profile'
              ELSE count(*)::text || ' stranded; re-run the bundle or '
                   || 'PATCH_20260816_restore_signin_trigger.sql' END,
         CASE WHEN count(*) = 0 THEN 'OK' ELSE 'FAIL' END
    FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
)

SELECT check_name AS "الفحص", detail AS "التفصيل", status AS "الحالة"
  FROM results ORDER BY sort_key;
