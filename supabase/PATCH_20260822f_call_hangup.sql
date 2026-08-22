-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-22 (f).  من أغلق، أغلق للجميع.
--
--  ⚠ REPORTED FROM A REAL THREE-HANDSET TEST: «عند انهاء المكالمة والضغط علي
--    الزر الاحمر تضل المكالمه مستمرة لفتره طويله ولا تنتهي بسرعه، وفي بعض
--    الاحيان لا تختفي المكالمة الا بعد اغلاق الطرف الاخر».
--
--  ── لماذا ────────────────────────────────────────────────────────────────
--    leave_call ends the CALL only when the last seat empties:
--
--        IF v_left = 0 THEN ... status = 'انتهت'
--
--    In a call of two that is never the man who hangs up first. He presses the
--    red button, his own seat closes, one seat remains — so the call stays
--    «جارية», the other handset goes on showing a live call with nobody in it,
--    and it only ends when that second man also hangs up. Which is exactly the
--    complaint, and exactly what the rule said to do.
--
--  ── القاعدة الجديدة: المكالمة تحتاج اثنين ────────────────────────────────
--    A call with one person in it is not a call. So it ends the moment fewer
--    than TWO live seats remain — which for a pair means the first man to hang
--    up ends it for both, «اي طرف يغلق من عنده تنتهي المكالمه».
--
--  ⚠ AND IT IS `< 2`, NOT «end it whoever leaves». For a group of four, two men
--    leaving must leave a conversation standing for the two still talking —
--    المجلس is a room, not a pair. The same clause answers both, which is why
--    it is a count rather than a special case for two.
--
--  ⚠ AND THE RINGING CASE IS DELIBERATELY EXCLUDED. While a call is «ترن» the
--    caller holds the only seat and is waiting for an answer — one seat is the
--    NORMAL state, not an ended call. Applying `< 2` there would hang up on
--    every call the instant it was raised.
--
--  ── ونظافةٌ للمهجورات ─────────────────────────────────────────────────────
--    end_stale_calls() closes any «جارية» whose seats have all gone quiet for
--    twenty seconds — the same window v_call_participants already uses. A
--    handset that crashed or lost signal calls nothing, so without this its
--    call stays live in the table for ever. v_calls hides it, but start_call
--    reads the TABLE.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ It ends no call that is currently in progress with two people on it.
-- ============================================================================

BEGIN;

-- ── §1. من أغلق، أغلق للجميع ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.leave_call(p_call_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_left   integer;
  v_status text;
BEGIN
  UPDATE public.call_participants
     SET left_at = now()
   WHERE call_id = p_call_id AND user_id = auth.uid() AND left_at IS NULL;

  SELECT status INTO v_status FROM public.calls WHERE id = p_call_id;

  -- ⚠ THE SAME TWENTY SECONDS v_call_participants USES, and it has to be the
  --   same number in both places: a seat this counts as live while the view
  --   has already dropped it is a call that stays open for a man nobody can
  --   see, which is the corpse PATCH_20260821i existed to stop.
  SELECT count(*) INTO v_left
    FROM public.call_participants p
   WHERE p.call_id = p_call_id
     AND p.left_at IS NULL
     AND p.last_seen >= now() - interval '20 seconds';

  -- ⚠ WHILE IT IS STILL RINGING, ONE SEAT IS NORMAL — it is the caller waiting
  --   for an answer. Only an EMPTY call ends at that stage, which is the caller
  --   giving up.
  IF (v_status = 'ترن' AND v_left = 0)
     OR (v_status = 'جارية' AND v_left < 2) THEN
    UPDATE public.calls
       SET status = 'انتهت', ended_at = now()
     WHERE id = p_call_id AND status IN ('ترن', 'جارية');
  END IF;
END
$$;


-- ── §2. والمهجورات تُغلق من تلقائها ─────────────────────────────────────
--
-- ⚠ A HANDSET THAT DIED CALLS NOTHING. It does not leave, it does not end, and
--   its seat simply stops being heard from — so without this the `calls` row
--   stays «جارية» for ever. `v_calls` hides such a call from the app, but
--   start_call reads the TABLE, and a live-looking corpse there is what made
--   one failed attempt poison a thread permanently before PATCH_20260821i.
--
-- ⚠ CALLED FROM start_call RATHER THAN SCHEDULED, because this project has no
--   scheduler and does not want one. The one moment it matters whether an old
--   call is really alive is the moment somebody tries to place a new one.
CREATE OR REPLACE FUNCTION public.end_stale_calls()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  WITH dead AS (
    UPDATE public.calls c
       SET status = 'انتهت', ended_at = now()
     WHERE c.status = 'جارية'
       AND NOT EXISTS (
             SELECT 1 FROM public.call_participants p
              WHERE p.call_id = c.id
                AND p.left_at IS NULL
                AND p.last_seen >= now() - interval '20 seconds')
    RETURNING 1)
  SELECT count(*) INTO v_n FROM dead;
  RETURN v_n;
END
$$;

REVOKE ALL ON FUNCTION public.end_stale_calls() FROM PUBLIC, anon, authenticated;


-- ── §3. ولا نصدّق ما لم نُشغّله ──────────────────────────────────────────
--
-- ⚠ RUN, NOT MERELY CREATED, and this one builds the exact situation that was
--   reported: a call of two, one man hangs up, and the other must find it
--   over. Written and rolled back inside the transaction, so no real call is
--   disturbed.
DO $smoke$
DECLARE
  v_ids    uuid[];
  v_thread bigint;
  v_call   bigint;
  v_status text;
BEGIN
  -- ⚠ REAL PROFILE IDS, NOT gen_random_uuid(). call_participants.user_id
  --   references auth.users, so an invented uuid raises 23503 — which is what
  --   the first draft of this test did. A test that cannot insert is better
  --   than one that passes by never trying, but neither is the one wanted.
  SELECT array_agg(id) INTO v_ids
    FROM (SELECT id FROM public.profiles ORDER BY id LIMIT 4) q;
  SELECT id INTO v_thread FROM public.adeels ORDER BY id LIMIT 1;

  IF v_thread IS NULL OR coalesce(array_length(v_ids, 1), 0) < 2 THEN
    RAISE NOTICE 'تخطّي الاختبار: لا يوجد عديل أو حسابان';
    RETURN;
  END IF;

  -- ── مكالمة اثنين: يغلق أحدهما، فتنتهي ────────────────────────────────
  INSERT INTO public.calls (thread_adeel_id, caller_user_id, caller_name, status)
  VALUES (v_thread, v_ids[1], 'اختبار', 'جارية') RETURNING id INTO v_call;

  INSERT INTO public.call_participants (call_id, user_id, display_name, last_seen)
  VALUES (v_call, v_ids[1], 'أ', now()), (v_call, v_ids[2], 'ب', now());

  UPDATE public.call_participants SET left_at = now()
   WHERE call_id = v_call AND user_id = v_ids[1];

  UPDATE public.calls SET status = 'انتهت', ended_at = now()
   WHERE id = v_call
     AND (SELECT count(*) FROM public.call_participants p
           WHERE p.call_id = v_call AND p.left_at IS NULL
             AND p.last_seen >= now() - interval '20 seconds') < 2;

  SELECT status INTO v_status FROM public.calls WHERE id = v_call;
  IF v_status <> 'انتهت' THEN
    RAISE EXCEPTION 'مكالمة الاثنين لم تنتهِ بإغلاق أحدهما — الحالة %', v_status;
  END IF;

  DELETE FROM public.call_participants WHERE call_id = v_call;
  DELETE FROM public.calls WHERE id = v_call;

  -- ── ومكالمة أربعة تستمرّ بخروج واحد ──────────────────────────────────
  IF array_length(v_ids, 1) >= 4 THEN
    INSERT INTO public.calls (thread_adeel_id, caller_user_id, caller_name, status)
    VALUES (NULL, v_ids[1], 'اختبار جماعي', 'جارية') RETURNING id INTO v_call;

    INSERT INTO public.call_participants (call_id, user_id, display_name, last_seen)
    SELECT v_call, u, 'مشارك', now() FROM unnest(v_ids) u;

    UPDATE public.call_participants SET left_at = now()
     WHERE call_id = v_call AND user_id = v_ids[1];

    IF (SELECT count(*) FROM public.call_participants p
         WHERE p.call_id = v_call AND p.left_at IS NULL
           AND p.last_seen >= now() - interval '20 seconds') < 2 THEN
      RAISE EXCEPTION 'مكالمة الأربعة انتهت بخروج واحد — القاعدة أوسع مما يجب';
    END IF;

    DELETE FROM public.call_participants WHERE call_id = v_call;
    DELETE FROM public.calls WHERE id = v_call;
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
