-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (i).  المكالمة تَرِنّ فعلاً، ولا تبقى جثّة.
--
--  ⚠ TWO BUGS, BOTH FOUND ON THE FIRST REAL CALL BETWEEN TWO HANDSETS.
--
--  ① THE CALL STOPPED RINGING A SECOND AFTER IT WAS MADE.
--    The caller joins his own call immediately — that is how he gets the
--    seat id that decides who offers whom — and join_call flipped «ترن» to
--    «جارية» on ANY join. By the time the other handset polled, three
--    seconds later, the call was no longer ringing; the banner asks for a
--    RINGING call, so nothing appeared and the man being called was never
--    told. Answering is joining, and the caller is not answering himself.
--
--  ② A «جارية» CALL NEVER ENDED IF ITS PEOPLE VANISHED.
--    leave_call closes a call when the last man leaves PROPERLY; a handset
--    that crashed never calls it. The row stayed live forever — and
--    start_call returns an existing live call instead of raising a new one.
--    So ONE failed attempt poisoned the thread: every later call joined a
--    corpse and rang nobody, which is why it looked permanent.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    No lockdown sweep: every function is CREATE OR REPLACE on one that
--    already exists, so its grants are kept.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.call_participants') IS NULL THEN
    RAISE EXCEPTION 'لا يوجد جدول مشاركي المكالمة. طبّق الملف السابق أولاً.';
  END IF;
END
$prereq$;


CREATE OR REPLACE FUNCTION public.join_call(p_call_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_thread bigint;
  v_status text;
  v_name   text;
  v_max    integer;
  v_now    integer;
  v_id     bigint;
BEGIN
  SELECT c.thread_adeel_id, c.status INTO v_thread, v_status
    FROM public.calls c WHERE c.id = p_call_id;
  IF NOT FOUND OR NOT public.may_join_thread(v_thread) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;
  IF v_status NOT IN ('ترن', 'جارية') THEN
    RAISE EXCEPTION 'المكالمة انتهت.' USING ERRCODE = 'RUL18';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('callseat:' || p_call_id::text));

  SELECT s.call_max_participants INTO v_max
    FROM public.association_settings s WHERE s.id = 1;
  v_max := coalesce(v_max, 6);

  SELECT count(*) INTO v_now
    FROM public.call_participants p
   WHERE p.call_id = p_call_id
     AND p.left_at IS NULL
     AND p.last_seen >= now() - interval '20 seconds'
     AND p.user_id <> auth.uid();

  IF v_now >= v_max THEN
    RAISE EXCEPTION 'المكالمة ممتلئة (% مشاركين).', v_max
      USING ERRCODE = 'RUL19';
  END IF;

  SELECT coalesce(nullif(trim(p.display_name), ''), 'الإدارة') INTO v_name
    FROM public.profiles p WHERE p.id = auth.uid();

  -- ⚠ ON CONFLICT UPDATE, so a man whose app restarted takes back the SAME
  --   seat. A second row would give him a second id — and the id is what
  --   decides who offers whom, so his peers would all try to renegotiate with
  --   somebody who is already connected to them.
  INSERT INTO public.call_participants (call_id, user_id, display_name)
  VALUES (p_call_id, auth.uid(), coalesce(v_name, 'الإدارة'))
  ON CONFLICT (call_id, user_id) DO UPDATE
     SET last_seen = now(), left_at = NULL
  RETURNING id INTO v_id;

  -- The first answer is what turns a ringing call into a live one, whether it
  -- came through answer_call on a private thread or through joining المجلس.
  UPDATE public.calls
     SET status = 'جارية', answered_at = coalesce(answered_at, now())
   WHERE id = p_call_id AND status = 'ترن'
     -- ⚠ AND ONLY WHEN SOMEBODY OTHER THAN THE CALLER TAKES A SEAT.
     --
     --   The caller joins his OWN call the instant he raises it — that is
     --   how he gets the seat id, and the seat id decides who offers whom.
     --   The old rule flipped «ترن» to «جارية» on ANY join, so the call
     --   stopped ringing about a second after it was made, before the other
     --   handset's three-second poll had ever seen it. The banner asks for a
     --   RINGING call, so it never appeared and the man being called was
     --   never told anything at all.
     --
     --   Answering is joining, and the caller is not answering himself.
     AND caller_user_id <> auth.uid();

  RETURN v_id;
END
$$;


CREATE OR REPLACE FUNCTION public.start_call(p_thread_adeel_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id      bigint;
  v_name    text;
  v_live    bigint;
BEGIN
  IF NOT public.may_join_thread(p_thread_adeel_id) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  -- ⚠ THE LOCK IS ON THE THREAD, taken before the check. Without it the two
  --   simultaneous callers both SELECT «nothing live» and both INSERT.
  PERFORM pg_advisory_xact_lock(
    hashtext('call:' || coalesce(p_thread_adeel_id::text, 'hall'))
  );

  SELECT c.id INTO v_live
    FROM public.calls c
   WHERE c.thread_adeel_id IS NOT DISTINCT FROM p_thread_adeel_id
     AND (
       -- ⚠ «LIVE» MEANS SOMEBODY IS ACTUALLY ON IT. The old test accepted
       --   any row marked «جارية», and nothing ever un-marks one whose
       --   participants all vanished — so ONE crashed call poisoned the
       --   thread permanently: every later attempt returned that dead id and
       --   rang nobody. That is why the failure looked permanent rather than
       --   intermittent. Same twenty-second rule as v_call_participants, so
       --   the three places that answer «who is on this call» agree.
       (c.status = 'جارية' AND EXISTS (
           SELECT 1 FROM public.call_participants p
            WHERE p.call_id = c.id
              AND p.left_at IS NULL
              AND p.last_seen >= now() - interval '20 seconds'))
       OR (c.status = 'ترن' AND c.started_at >= now() - interval '60 seconds')
     )
   ORDER BY c.id DESC
   LIMIT 1;

  IF v_live IS NOT NULL THEN
    -- Not an error the caller should be shown as a failure: somebody is
    -- already on this line, and joining that call is what he meant.
    RETURN v_live;
  END IF;

  SELECT coalesce(nullif(trim(p.display_name), ''), 'الإدارة') INTO v_name
    FROM public.profiles p WHERE p.id = auth.uid();

  INSERT INTO public.calls (thread_adeel_id, caller_user_id, caller_name)
  VALUES (p_thread_adeel_id, auth.uid(), coalesce(v_name, 'الإدارة'))
  RETURNING id INTO v_id;

  RETURN v_id;
END
$$;


CREATE OR REPLACE VIEW public.v_calls
WITH (security_invoker = true) AS
  SELECT
    c.id                            AS "id",
    c.thread_adeel_id               AS "threadAdeelId",
    c.caller_name                   AS "callerName",
    (c.caller_user_id = auth.uid()) AS "mine",
    CASE
      WHEN c.status = 'ترن'
       AND c.started_at < now() - interval '60 seconds' THEN 'فائتة'
      -- ⚠ AND A «جارية» CALL WITH NO LIVE SEAT IS OVER. Nothing else ends
      --   one: leave_call closes a call when the last man leaves PROPERLY,
      --   and a handset that crashed or lost signal never calls it. The row
      --   then stays live forever.
      --
      --   Computed HERE, so nothing has to RUN for it to be true — the same
      --   reason the ring expires in this view.
      WHEN c.status = 'جارية' AND NOT EXISTS (
             SELECT 1 FROM public.call_participants p
              WHERE p.call_id = c.id
                AND p.left_at IS NULL
                AND p.last_seen >= now() - interval '20 seconds'
           ) THEN 'انتهت'
      ELSE c.status
    END                             AS "status",
    c.started_at                    AS "startedAt",
    c.answered_at                   AS "answeredAt",
    c.ended_at                      AS "endedAt"
  FROM public.calls c;

GRANT SELECT ON public.v_calls TO authenticated;


-- ── وتنظيف الجثث الموجودة ───────────────────────────────────────────────
-- ⚠ THE FIX DOES NOT UNDO THE PAST. start_call reads the TABLE, not the
--   view, so calls already stuck at «جارية» would go on blocking their
--   thread. One statement closes them.
UPDATE public.calls c
   SET status = 'انتهت', ended_at = coalesce(ended_at, now())
 WHERE c.status IN ('ترن', 'جارية')
   AND NOT EXISTS (
     SELECT 1 FROM public.call_participants p
      WHERE p.call_id = c.id
        AND p.left_at IS NULL
        AND p.last_seen >= now() - interval '20 seconds'
   );


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
