-- bootstrap_first_admin.sql — run ONCE, by hand, in the Supabase SQL editor.
--
-- ═══════════════════════════════════════════════════════════════════════════
--  EDIT THIS ONE LINE, then run the whole file.
-- ═══════════════════════════════════════════════════════════════════════════
--
--      ↓↓↓  put your own address here  ↓↓↓
--
--          'you@example.com'
--
-- It appears once, in the DO block below, marked ADMIN EMAIL.
--
-- ═══════════════════════════════════════════════════════════════════════════
--
-- THE PROBLEM THIS SOLVES
--
-- `handle_new_user()` creates every profile as `viewer` / `pending`, deliberately:
-- signing in with Google must not grant access until an administrator approves it.
-- But the first person to sign in has no administrator to approve them, and
-- `set_user_access()` requires the very admin role it would be granting. Nobody
-- can get in.
--
-- The escape has to be outside the app and it has to be manual — an automatic
-- "first user becomes admin" rule would hand the association's treasury to
-- whoever discovered the URL first.
--
-- HOW TO USE IT
--
--   1. Sign in to the app with Google once. It will say "awaiting approval".
--      That is correct: the sign-in worked and created your account.
--   2. Edit the address below, paste this whole file into the SQL editor, Run.
--   3. Reload the app.
--
-- Running it a second time is harmless.
--
-- NOTE ON SYNTAX: no `\set` and no `:'variable'`. Those are psql meta-commands;
-- the Supabase SQL editor is not psql and does not process them, and they are not
-- substituted inside a dollar-quoted block even when it is. An earlier version of
-- this file used them and failed with "syntax error at or near :" — in the one
-- place it was written to run.

DO $bootstrap$
DECLARE
  -- ▼▼▼ ADMIN EMAIL — change this ▼▼▼
  v_email text := 'you@example.com';
  -- ▲▲▲ ADMIN EMAIL ▲▲▲

  v_id    uuid;
  v_added int;
BEGIN
  -- ── Backfill any auth user that has no profile ─────────────────────────────
  --
  -- `handle_new_user()` fires on INSERT into auth.users, so anyone who signed up
  -- BEFORE this schema was applied has an account and no profile row: the trigger
  -- did not exist yet to create one. That is easy to hit — sign in to check the
  -- project works, then apply the schema. Without this, such a user is permanently
  -- invisible to the app and the error below would not explain why.
  --
  -- Everyone backfilled lands as viewer/pending, exactly as the trigger would have
  -- created them. No access is granted here.
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
  IF v_added > 0 THEN
    RAISE INFO 'backfilled % profile row(s) for pre-existing auth users', v_added;
  END IF;

  -- ── Promote ────────────────────────────────────────────────────────────────
  SELECT id INTO v_id FROM public.profiles WHERE email = v_email;

  IF v_id IS NULL THEN
    RAISE EXCEPTION
      'No account for %. Sign in to the app with that address FIRST — this '
      'script can create a missing PROFILE, but only Supabase Auth can create '
      'the account itself.',
      v_email;
  END IF;

  -- A direct UPDATE, not set_user_access(): that function calls
  -- require_role('admin') and there is no admin yet. The SQL editor runs as
  -- `postgres`, the one context allowed to break the circle.
  --
  -- trg_profiles_guard still applies, and still permits this: its self-elevation
  -- check only fires when auth.uid() is non-null, and there is no JWT here, so
  -- nobody is elevating themselves.
  UPDATE public.profiles
     SET role = 'admin',
         status = 'approved',
         approved_at = now()
   WHERE id = v_id;

  INSERT INTO public.audit_log (event_type, detail, ref, actor_name)
  VALUES ('user.bootstrap',
          format('%s promoted to admin by bootstrap script', v_email),
          v_id::text,
          'bootstrap');

  RAISE INFO '% is now an approved admin.', v_email;
END $bootstrap$;

-- Confirm, and check nobody else was let in by accident.
SELECT email, role, status FROM public.profiles ORDER BY role DESC, email;
