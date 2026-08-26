-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-23 (f).  الغرفةُ تُقال، لا تُستنتج.
--
--  ⚠ REPORTED: «عندما أرسل محادثة من عديل إلى عديل فإن الرسالة … تظهر أيضاً في
--    المحادثة العامة يراها الجميع.»
--
--  ── ما هو حقّاً، بعد تشغيله ───────────────────────────────────────────────
--    RLS HELD. Tested with the role the app actually uses — a THIRD member's
--    hall query returned the public message and ZERO of the private one. The
--    read_chat policy's «thread_adeel_id IS NULL AND peer_a IS NULL» works.
--
--    What is broken is narrower and still bad: THE TWO PARTICIPANTS see their
--    own private message inside المجلس. The client asks for the hall with
--    «threadAdeelId IS NULL» — and a direct message has that NULL too. RLS
--    hands each of them their own direct rows (it must; that is their
--    conversation), and the client's filter cannot tell them apart. So the
--    sender and the recipient both watch a private line appear in the public
--    room, and reasonably conclude everyone else is watching it too.
--
--  ── الداء، وهو نفسه للمرّة الثانية ────────────────────────────────────────
--    `thread_adeel_id IS NULL` MEANS TWO THINGS: «المجلس» and «a direct
--    message». PATCH_20260823a already paid for this once — its own note says
--    the policy «had to be tightened to peer_a IS NULL», because otherwise
--    «every private conversation would have appeared in المجلس for everyone,
--    and looked like the feature working». The policy was fixed. Every OTHER
--    reader of that column was not.
--
--  ── الدواء: عمودٌ يقول الغرفةَ بالاسم ─────────────────────────────────────
--    v_chat_messages gains `room` — 'hall' | 'board' | 'direct' — so no caller
--    ever again infers a room from two nullable columns. The client filters on
--    it; the next query is correct by construction rather than by remembering.
--
--  ⚠ APPENDED, NEVER REORDERED. CREATE OR REPLACE VIEW permits adding columns
--    at the END and nothing else, which is also why every installed handset
--    keeps working: it selects the columns it knows and ignores this one.
--
--  ⚠ THIS PATCH ALONE DOES NOT FIX THE SCREEN. The wrong filter is in the app.
--    Until the new APK is installed, the two participants go on seeing their
--    own private message in المجلس — and nobody else ever did.
--
--  SQL Editor → New query → paste → Run. معاملةٌ واحدة، تُشغَّل مرّتين بأمان.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_chat_messages
WITH (security_invoker = on) AS
  SELECT m.id,
         m.author_name  AS "authorName",
         m.author_adeel_id AS "authorAdeelId",
         m.from_staff   AS "fromStaff",
         CASE WHEN m.deleted_at IS NULL THEN m.body ELSE '' END AS body,
         m.deleted_at IS NOT NULL AS deleted,
         m.author_user_id = auth.uid() AS mine,
         to_char(m.created_at AT TIME ZONE 'UTC',
                 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "createdAt",
         m.thread_adeel_id AS "threadAdeelId",
         ta.full_name      AS "threadName",
         m.peer_a          AS "peerA",
         m.peer_b          AS "peerB",
         -- ⚠ THE ORDER OF THESE TESTS IS THE RULE. `direct` is decided FIRST,
         --   because a direct message has thread_adeel_id NULL — which is
         --   exactly what made «المجلس» ambiguous. Asking about the hall first
         --   would rebuild the bug inside the fix.
         CASE WHEN m.peer_a IS NOT NULL          THEN 'direct'
              WHEN m.thread_adeel_id IS NOT NULL THEN 'board'
              ELSE 'hall' END AS "room"
    FROM public.chat_messages m
    LEFT JOIN public.adeels ta ON ta.id = m.thread_adeel_id;

-- ⚠ RESTATED, AND NOT REDUNDANT — see the note in PATCH_20260823a. A view that
--   is dropped for any reason comes back with no ACL, and every member gets
--   «permission denied» with the chat simply blank.
GRANT SELECT ON public.v_chat_messages TO authenticated;


-- ── ولا نصدّق ما لم نُشغّله ──────────────────────────────────────────────
--
-- ⚠ THE THREE ROOMS ARE CHECKED AGAINST REAL ROWS, not against the CASE we
--   just wrote. A message is inserted in each shape, read back, and removed.
DO $smoke$
DECLARE
  v_u   uuid;
  v_a   bigint;
  v_b   bigint;
  v_got text;
  v_ids bigint[] := '{}';
  v_id  bigint;
BEGIN
  SELECT id INTO v_u FROM public.profiles ORDER BY id LIMIT 1;
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT id FROM public.adeels ORDER BY id LIMIT 2) q;

  -- ⚠ THIS SKIP ONCE HID A REAL DEFECT. The block below was written, the
  --   patch reported success, and the INSERT it contains had never run — the
  --   local database happened to hold fewer than two عدايل, so the test
  --   skipped itself with a NOTICE nobody reads, and a missing from_staff
  --   reached the association's project as 23502.
  --
  --   A check that skips is not a check that passed. It still tolerates a
  --   database with nothing in it — a fresh project has no rows and must not
  --   be refused — but it says so where it cannot be scrolled past.
  IF v_u IS NULL OR coalesce(array_length(v_ids, 1), 0) < 2 THEN
    RAISE WARNING '⚠⚠ اختبار الغرف لم يعمل: لا يوجد حساب أو عديلان في هذه القاعدة';
    RAISE WARNING '⚠⚠ العرضُ طُبِّق، ولكن لم يُختبر على صفٍّ حقيقي';
    RETURN;
  END IF;
  v_a := v_ids[1]; v_b := v_ids[2];

  -- (١) المجلس
  -- ⚠ from_staff IS NOT NULL AND HAS NO DEFAULT. Omitting it raised 23502 on
  --   the association's project — and NOT here, because this block had quietly
  --   skipped itself (see the RAISE below). Two failures in one line.
  INSERT INTO public.chat_messages
    (author_user_id, author_name, from_staff, body)
  VALUES (v_u, 'اختبار', false, 'م') RETURNING id INTO v_id;
  SELECT "room" INTO v_got FROM public.v_chat_messages WHERE id = v_id;
  IF v_got <> 'hall' THEN RAISE EXCEPTION 'رسالةُ المجلس صُنّفت %', v_got; END IF;
  DELETE FROM public.chat_messages WHERE id = v_id;

  -- (٢) خيط الإدارة
  INSERT INTO public.chat_messages
    (author_user_id, author_name, from_staff, body, thread_adeel_id)
  VALUES (v_u, 'اختبار', false, 'خ', v_a) RETURNING id INTO v_id;
  SELECT "room" INTO v_got FROM public.v_chat_messages WHERE id = v_id;
  IF v_got <> 'board' THEN RAISE EXCEPTION 'خيطُ الإدارة صُنّف %', v_got; END IF;
  DELETE FROM public.chat_messages WHERE id = v_id;

  -- (٣) الثنائية — والحالةُ التي بدأ منها كلُّ هذا: thread فارغ، وليست مجلساً
  INSERT INTO public.chat_messages
    (author_user_id, author_name, from_staff, body, peer_a, peer_b)
  VALUES (v_u, 'اختبار', false, 'ث', least(v_a,v_b), greatest(v_a,v_b))
  RETURNING id INTO v_id;
  SELECT "room" INTO v_got FROM public.v_chat_messages WHERE id = v_id;
  IF v_got <> 'direct' THEN
    RAISE EXCEPTION 'الرسالةُ الخاصّة صُنّفت % — وهذه هي العلّة بعينها', v_got;
  END IF;
  DELETE FROM public.chat_messages WHERE id = v_id;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
