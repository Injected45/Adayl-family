-- ============================================================================
--  PATCH: restore Google sign-in for NEW users, 2026-08-16.
--
--  SYMPTOM THIS FIXES
--    Accounts that had signed in before can still sign in. Anyone signing in
--    for the FIRST time gets "حدث خطأ غير متوقع" — and, on a second attempt,
--    "تم إلغاء تسجيل الدخول", which is Credential Manager cancelling a retry
--    and not a second fault. Nothing in Google Cloud, Supabase Auth or the app
--    is wrong; the two messages are one cause.
--
--  WHY IT HAPPENS
--    A first sign-in INSERTs a row into auth.users. `trg_auth_user_created`
--    fires on that INSERT and creates the person's public.profiles row. The
--    trigger lives on auth.users but calls a function in `public`, so
--    DROP SCHEMA public CASCADE — which RESET_AND_APPLY.sql does — takes it
--    with the schema. If it is not back, the INSERT that creates the account
--    raises, GoTrue answers "Database error saving new user", and no new person
--    can ever sign in. Existing accounts are unaffected: they insert nothing.
--
--    That asymmetry is why this reads as "it worked, then it came back":
--    whoever tests it is usually already in auth.users.
--
--  WHAT IT DOES
--    1. Recreates handle_new_user() and the trigger. Both idempotent.
--    2. Backfills a profile for any auth.users row that has none — the people
--       who tried to sign in while the trigger was missing, whose accounts may
--       have been created before the failure. They land viewer/pending, exactly
--       as the trigger would have made them. No access is granted here.
--    3. Reports what it found, so a no-op run says so instead of looking the
--       same as a repair.
--
--  SAFE ON A LIVE PROJECT. It touches no application table, no policy and no
--  grant, and creates no access. One transaction. Re-running is harmless.
--
--  HOW TO APPLY
--    Supabase dashboard → SQL Editor → New query → paste all of this → Run.
-- ============================================================================

BEGIN;

-- ── 1. The function. Byte-identical to 20260811090100_profiles.sql ──────────
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name, picture_url)
  VALUES (
    NEW.id,
    coalesce(NEW.email, ''),
    coalesce(NEW.raw_user_meta_data ->> 'full_name',
             NEW.raw_user_meta_data ->> 'name',
             split_part(coalesce(NEW.email, ''), '@', 1)),
    NEW.raw_user_meta_data ->> 'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END $$;

-- ── 2. The trigger ──────────────────────────────────────────────────────────
-- DROP first: CREATE TRIGGER has no OR REPLACE before PostgreSQL 14, and a
-- plain CREATE aborts the whole transaction with 42710 when the trigger is
-- already there — which is the case this file must survive, since it is meant
-- to be run without knowing whether anything is broken.
DO $restore$
DECLARE
  v_had boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid = 'auth.users'::regclass
       AND tgname  = 'trg_auth_user_created'
       AND NOT tgisinternal
  ) INTO v_had;

  IF v_had THEN
    RAISE INFO 'trigger was already present — first sign-in was NOT broken by this';
  ELSE
    RAISE WARNING 'trigger was MISSING — this is why no new user could sign in';
  END IF;
END $restore$;

DROP TRIGGER IF EXISTS trg_auth_user_created ON auth.users;

CREATE TRIGGER trg_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ── 3. Backfill anyone the missing trigger skipped ──────────────────────────
DO $backfill$
DECLARE
  v_added int;
BEGIN
  INSERT INTO public.profiles (id, email, display_name, picture_url)
  SELECT u.id,
         coalesce(u.email, ''),
         coalesce(u.raw_user_meta_data ->> 'full_name',
                  u.raw_user_meta_data ->> 'name',
                  split_part(coalesce(u.email, ''), '@', 1)),
         u.raw_user_meta_data ->> 'avatar_url'
    FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
  ON CONFLICT (id) DO NOTHING;

  GET DIAGNOSTICS v_added = ROW_COUNT;
  RAISE INFO 'backfilled % profile row(s)', v_added;
END $backfill$;

COMMIT;

-- ── 4. Confirm ──────────────────────────────────────────────────────────────
-- `trigger` must be present, and `auth users without a profile` must be 0.
SELECT 'trigger on auth.users' AS check,
       coalesce((SELECT string_agg(tgname, ', ')
                   FROM pg_trigger
                  WHERE tgrelid = 'auth.users'::regclass AND NOT tgisinternal),
                'STILL MISSING') AS value
UNION ALL
SELECT 'auth users', (SELECT count(*)::text FROM auth.users)
UNION ALL
SELECT 'profiles', (SELECT count(*)::text FROM public.profiles)
UNION ALL
SELECT 'auth users without a profile',
       (SELECT count(*)::text FROM auth.users u
         WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id));
