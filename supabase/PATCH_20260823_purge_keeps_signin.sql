-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-23.  المسح لا يترك مشتركاً خارج تطبيقه.
--
--  WHAT WENT WRONG, and it was reported the moment it bit
--    After purge_all_data, a member signed in with Google and was told:
--    «تم تسجيل الدخول، لكن لا يوجد سجل لهذا الحساب في قاعدة البيانات. لن
--    تنجح المحاولة مرة أخرى». The message is accurate, which is the worst part.
--
--  ⚠ WHY SIGNING IN AGAIN CANNOT FIX IT. A profile is created by
--    trg_auth_user_created, which fires AFTER INSERT ON auth.users. Signing
--    in inserts nothing — the account has existed since the first time. So
--    the one event that creates a profile already happened, once, and will
--    never happen again for that person.
--
--    purge_all_data deleted every portal profile and left auth.users standing,
--    with a comment asserting the opposite. Every عديل who had ever opened
--    the app was locked out of it, permanently, by a button in الإعدادات.
--
--  ⚠ AND IT IS THE SAME FAILURE AS 16/08, which is why this file exists
--    rather than a note. That reset dropped public.profiles and left
--    auth.users, and the association was locked out of its own app until
--    bootstrap_first_admin.sql was run by hand. The migration that owns
--    profiles carries a backfill for exactly this; the purge did not.
--
--  WHAT THIS DOES
--    1. Backfills a blank profile for every auth.users row that has none —
--       which un-strands everyone stranded RIGHT NOW.
--    2. Replaces purge_all_data so it does that backfill itself, and the
--       next purge cannot strand anybody.
--
--  ⚠ viewer/pending, SO IT GRANTS NOTHING. That is the state every new
--    sign-in lands in. The man then types the access code on /pending and
--    redeem_adeel_code binds him to his عديل — the ordinary path, unchanged.
--
--  ⚠ NO FIGURE MOVES. The only rows written are profiles for accounts that
--    already exist in auth.users and have nothing in public.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

-- == 1. من عَلِق الآن، يُفَكّ الآن ==========================================
-- Character for character the backfill in 20260811090100_profiles.sql. Not
-- «similar to» it — the same statement, so the two cannot drift into
-- disagreeing about what a fresh profile looks like.
INSERT INTO public.profiles (id, email, display_name, picture_url)
SELECT u.id,
       coalesce(u.email, ''),
       coalesce(u.raw_user_meta_data ->> 'full_name',
                u.raw_user_meta_data ->> 'name',
                split_part(coalesce(u.email, ''), '@', 1)),
       u.raw_user_meta_data ->> 'avatar_url'
  FROM auth.users u
 WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
ON CONFLICT DO NOTHING;

-- == 2. ولا يعود المسح يُعلِّق أحداً ========================================
-- ⚠ THE BODY BELOW IS THE INSTALLED ONE, LIFTED WHOLE. Only the block after
--   `DELETE FROM public.profiles` differs — a patch that retyped the rest
--   would silently revert whatever the earlier patches put there.
CREATE OR REPLACE FUNCTION public.purge_all_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv   bigint;
  v_pay    bigint;
  v_alloc  bigint;
  v_cash   bigint;
  v_audit  bigint;
  v_adeels bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- Distinct from purge_financial_data's phrase ON PURPOSE. See above.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح كل البيانات' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  SELECT count(*) INTO v_recv   FROM public.receivables;
  SELECT count(*) INTO v_pay    FROM public.payments;
  SELECT count(*) INTO v_alloc  FROM public.payment_allocations;
  SELECT count(*) INTO v_cash   FROM public.cash_movements;
  SELECT count(*) INTO v_audit  FROM public.audit_log;
  SELECT count(*) INTO v_adeels FROM public.adeels;

  -- ── Why adeels is DELETEd while the five financial tables are TRUNCATEd ────
  -- profiles.adeel_id references adeels, and TRUNCATE refuses whenever ANY table
  -- outside its list carries a foreign key into one being truncated — the
  -- constraint's existence is what it checks, not whether rows remain. So
  -- emptying profiles first does not help: it still dies with 0A000 "cannot
  -- truncate a table referenced in a foreign key constraint". Listing profiles
  -- would delete the association's own staff accounts, and CASCADE would do the
  -- same silently.
  --
  -- DELETE has no such rule, and adeels carries no refuse_delete trigger — that
  -- guard is on the financial tables, which keep their TRUNCATE. The identity is
  -- then restarted by hand, because that is the part RESTART IDENTITY was doing
  -- and the reason the next عديل must be A-0001.
  --
  -- ORDER MATTERS, and not for the reason it looks like. The truncate comes
  -- FIRST because receivables.created_by references profiles ON DELETE SET NULL,
  -- and that SET NULL is an UPDATE which trg_recv_snapshot_immutable rejects
  -- (created_by is a snapshot column). Deleting profiles while any receivable
  -- survives would therefore abort the whole purge with RUL05. Emptying the
  -- financial tables first leaves nothing for the cascade to touch.
  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivables,
           public.closed_periods,
           public.disbursements,
           -- ⚠ AND THE CHAT, which is not optional here: chat_messages
           --   references adeels, and Postgres refuses to TRUNCATE a table that
           --   a surviving table points at — so leaving this out does not make
           --   the purge incomplete, it makes it FAIL. The room also has to go
           --   on its own merits: every portal profile is deleted below, so what
           --   would remain is a conversation whose speakers no longer exist.
           --
           --   It is NOT in purge_financial_data. Wiping the figures is not a
           --   reason to erase what people said to each other.
           public.chat_messages,
           public.audit_log
    RESTART IDENTITY;

  -- Portal accounts go entirely: their عديل is being erased, so leaving the
  -- profile would leave a dangling scope and my_adeel_id() would answer with a
  -- dead id.
  DELETE FROM public.profiles WHERE adeel_id IS NOT NULL;

  -- ⚠ AND IMMEDIATELY PUT BACK A BLANK ONE, which the previous version did
  --   not — its comment claimed «auth.users survives, so the same person can
  --   sign in again», and that is false in the one way that matters.
  --
  --   trg_auth_user_created fires AFTER INSERT ON auth.users and on nothing
  --   else. Signing in INSERTS NOTHING: the account already exists. So a man
  --   whose profile was deleted signs in successfully, lands with no row, no
  --   role and no approval, and the app tells him «لا يوجد سجل لهذا الحساب —
  --   لن تنجح المحاولة مرة أخرى». It is right: nothing he can do will fix it,
  --   because the only thing that creates a profile is an event that has
  --   already happened once and cannot happen twice.
  --
  --   This is the same failure the 16/08 reset caused for the whole
  --   association, and 20260811090100_profiles.sql carries the same backfill
  --   for the same reason. A purge that strands every member is not a purge,
  --   it is a lockout with a confirmation phrase.
  --
  -- ⚠ viewer/pending, GRANTING NOTHING. That is exactly the state a brand new
  --   sign-in lands in, and it is what /pending is for: he types the access
  --   code the admin issues him, redeem_adeel_code binds him to his عديل, and
  --   the guard trigger allows that one pending → approved self-change.
  INSERT INTO public.profiles (id, email, display_name, picture_url)
  SELECT u.id,
         coalesce(u.email, ''),
         coalesce(u.raw_user_meta_data ->> 'full_name',
                  u.raw_user_meta_data ->> 'name',
                  split_part(coalesce(u.email, ''), '@', 1)),
         u.raw_user_meta_data ->> 'avatar_url'
    FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
  ON CONFLICT DO NOTHING;

  DELETE FROM public.adeels;

  ALTER TABLE public.adeels ALTER COLUMN id RESTART WITH 1;

  RETURN jsonb_build_object(
    'receivables',   v_recv,
    'payments',      v_pay,
    'allocations',   v_alloc,
    'cashMovements', v_cash,
    'auditEntries',  v_audit,
    'adeels',        v_adeels);
END $$;

-- == 3. Confirmation ========================================================
-- Read-only. Every row must say true.
SELECT 'لا حساب بلا ملف' AS "الفحص",
       NOT EXISTS (SELECT 1 FROM auth.users u
                    WHERE NOT EXISTS (SELECT 1 FROM public.profiles p
                                       WHERE p.id = u.id)) AS "النتيجة"
UNION ALL SELECT 'والمسح صار يُعيد بناءها',
       coalesce((SELECT p.prosrc LIKE '%INSERT INTO public.profiles%'
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = 'purge_all_data'),
                false)
-- ⚠ AND THE ADMIN IS STILL THERE. A backfill that somehow collided with the
--   email unique constraint and rolled a role back would show up here first.
UNION ALL SELECT 'ومدير معتمد قائم',
       EXISTS (SELECT 1 FROM public.profiles
                WHERE role = 'admin' AND status = 'approved')
-- ⚠ AND NOBODY WAS GRANTED ANYTHING. Every profile this created is pending,
--   so the backfill cannot have handed the association out to a stranger.
UNION ALL SELECT 'ولم يُمنح أحد صلاحية',
       NOT EXISTS (SELECT 1 FROM public.profiles
                    WHERE status = 'approved' AND role <> 'admin'
                      AND adeel_id IS NULL);

-- == 4. The four guards =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
