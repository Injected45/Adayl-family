-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (b).  «ماعدا» يُقرأ، والحارس يرفض.
--
--  TWO CHANGES, NEITHER OF WHICH TOUCHES A ROW.
--
--  1. v_settings gains `feeExceptions`.
--     «الاشتراك الشهري: 100» is a complete answer only while every month
--     costs 100. Since the association priced يناير and يونيو differently the
--     card has been NOT WRONG BUT INCOMPLETE — and an incomplete figure is
--     worse than a missing one, because nothing about it invites the second
--     look that would correct it. generate_period already bills the month's
--     own rate; this is the same fact, said where a man reads his fee.
--
--     ⚠ ON v_settings, THE WIDELY READABLE VIEW, and not only on the
--       admin-only api_settings — because the عديل reads this view too and the
--       fee is printed on HIS page as well. Same reasoning that put the bank
--       account here rather than on the admin shape.
--
--     ⚠ CREATE OR REPLACE VIEW can only APPEND a column, never reorder or
--       retype one. The eight that were there come back in the same order and
--       the new one is last, which is the only shape Postgres accepts.
--
--  2. assert_signin_intact() RAISES instead of warning.
--     It has always checked for accounts with no profile — and only warned.
--     On 2026-08-20 purge_all_data deleted every portal profile, left
--     auth.users standing, and PASSED this guard. A warning in a dashboard is
--     read by nobody, so the association found out from a member who could
--     not get in.
--
--     ⚠ THE COST IS REAL AND IS THE POINT: from now on any patch fails while
--       one account is stranded, even a patch about something else. A schema
--       change is exactly the moment to refuse to build on top of a broken
--       door. The message carries the one statement that fixes it.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public'
                    AND table_name = 'association_settings'
                    AND column_name = 'fee_exceptions') THEN
    RAISE EXCEPTION
      'لا يوجد عمود ماعدا. طبّق supabase/PATCH_20260820c_fee_exceptions.sql أولاً.';
  END IF;
END $prereq$;

-- == 1. «ماعدا» على العرض الذي يقرؤه الجميع ================================
-- The eight existing columns, unchanged and in order, then the new one.
CREATE OR REPLACE VIEW public.v_settings WITH (security_invoker = on) AS
SELECT
  association_name        AS "associationName",
  currency                AS "currency",
  member_fee::text        AS "memberFee",
  to_char(system_start, 'YYYY-MM-DD') AS "systemStart",
  auto_close_previous_months          AS "autoClosePreviousMonths",
  bank_account_no                     AS "bankAccountNo",
  bank_account_name                   AS "bankAccountName",
  bank_name                           AS "bankName",
  -- ⚠ APPENDED, and it has to be. CREATE OR REPLACE VIEW refuses to reorder
  --   or retype an existing column; only a new one at the end is allowed.
  fee_exceptions                      AS "feeExceptions"
FROM public.association_settings;

-- == 2. الحارس يرفض بدل أن يحذّر ===========================================
-- ⚠ THE BODY IS THE INSTALLED ONE, LIFTED WHOLE. Only the orphan branch
--   differs — everything above it already refuses, and retyping it would risk
--   losing a check that has been guarding sign-in since day one.
CREATE OR REPLACE FUNCTION public.assert_signin_intact() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_fn      bool;
  v_trigger bool;
  v_enabled bool;
  v_orphans bigint;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'handle_new_user')
    INTO v_fn;

  -- tgisinternal excludes the constraint triggers Postgres creates for foreign
  -- keys, which would otherwise make a missing trigger look present.
  SELECT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)
    INTO v_trigger;

  -- 'D' is DISABLED. A disabled trigger exists, reports present in every naive
  -- check, and does nothing at all — the same broken sign-in wearing a
  -- convincing disguise.
  SELECT EXISTS (SELECT 1 FROM pg_trigger
                  WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal
                    AND tgenabled <> 'D')
    INTO v_enabled;

  IF NOT v_fn THEN
    RAISE EXCEPTION
      'SIGN-IN: public.handle_new_user() is missing. Any new account would fail '
      'to be created and nobody new could sign in. Nothing has been committed.'
      USING ERRCODE = 'RUL01';
  END IF;

  IF NOT v_trigger THEN
    RAISE EXCEPTION
      'SIGN-IN: trigger trg_auth_user_created on auth.users is missing — this is '
      'what DROP SCHEMA public CASCADE removes. First-time sign-in would fail '
      'with "Database error saving new user". Nothing has been committed.'
      USING ERRCODE = 'RUL01';
  END IF;

  IF NOT v_enabled THEN
    RAISE EXCEPTION
      'SIGN-IN: trigger trg_auth_user_created exists but is DISABLED, so it '
      'creates no profile. Nothing has been committed.' USING ERRCODE = 'RUL01';
  END IF;

  -- ⚠ FATAL NOW, AND IT WAS A WARNING UNTIL 2026-08-21.
  --
  --   «Not fatal» was the reasoning: an account with no profile can still
  --   authenticate and the app says so plainly. Both halves are true and the
  --   conclusion was wrong. What the app says plainly is «لن تنجح المحاولة
  --   مرة أخرى» — which is correct, and which nothing the man does can undo,
  --   because trg_auth_user_created fires AFTER INSERT ON auth.users and
  --   signing in inserts nothing.
  --
  --   On 2026-08-20 purge_all_data deleted every portal profile, left
  --   auth.users standing, and passed this guard — because a WARNING in a
  --   dashboard is read by nobody. Every عديل was locked out of the app by a
  --   button in الإعدادات, and it was found by a member reporting it.
  --
  -- ⚠ THE COST, ACCEPTED DELIBERATELY: from now on ANY patch fails while a
  --   single account is stranded, including patches that have nothing to do
  --   with sign-in. That is the point. A schema change is exactly the moment
  --   to refuse to build on top of a broken door — and the fix is one
  --   statement, named in the message.
  SELECT count(*) INTO v_orphans
    FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);

  IF v_orphans > 0 THEN
    RAISE EXCEPTION
      'SIGN-IN: % account(s) exist with no profiles row. They can sign in and '
      'are then told «لا يوجد سجل لهذا الحساب», which nothing they do will '
      'fix — trg_auth_user_created fires on INSERT into auth.users, and '
      'signing in inserts nothing. Nothing has been committed. Apply '
      'supabase/PATCH_20260820e_purge_keeps_signin.sql, whose first '
      'statement backfills exactly these accounts, then re-run this.',
      v_orphans
      USING ERRCODE = 'RUL01';
  END IF;
END $$;

-- == 3. Confirmation ========================================================
-- Read-only. Every row must say true.
SELECT '«ماعدا» على v_settings' AS "الفحص",
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = 'v_settings'
                  AND column_name = 'feeExceptions') AS "النتيجة"
-- ⚠ AND THE VIEW STILL OBEYS THE CALLER'S POLICIES. A replace that dropped
--   security_invoker would run as its owner and read straight past RLS — on
--   the one view an عديل is allowed to read.
UNION ALL SELECT 'وما زال العرض يخضع لسياسات المستدعي',
       coalesce((SELECT lower(option_value) IN ('on','true','1','yes')
                   FROM pg_class c
                   JOIN pg_namespace n ON n.oid = c.relnamespace,
                        pg_options_to_table(c.reloptions)
                  WHERE n.nspname = 'public' AND c.relname = 'v_settings'
                    AND option_name = 'security_invoker'), false)
UNION ALL SELECT 'والحارس يرفض الآن ولا يحذّر',
       coalesce((SELECT pg_get_functiondef(p.oid) NOT LIKE '%RAISE WARNING%'
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public'
                    AND p.proname = 'assert_signin_intact'), false)
UNION ALL SELECT 'ولا حساب بلا ملف',
       NOT EXISTS (SELECT 1 FROM auth.users u
                    WHERE NOT EXISTS (SELECT 1 FROM public.profiles p
                                       WHERE p.id = u.id))
UNION ALL SELECT 'ولم يتغيّر أي رقم مالي',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 4. The four guards =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
