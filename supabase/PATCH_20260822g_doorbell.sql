-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-22 (g).  جرس الباب.
--
--  ⚠ WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT.
--    It is a DOORBELL: a broadcast that carries the word «something happened»
--    and nothing else. No message text, no sender, no id, no amount. Every
--    handset that hears it does the same authenticated REST read it does today,
--    so **RLS still decides everything and not one policy on any table changes**.
--
--    It is NOT `postgres_changes`. That is the thing this schema cannot use:
--    `my_adeel_id()` reads the `x-device-id` REQUEST HEADER, a websocket carries
--    no headers, and a row-level subscription evaluated for a portal member
--    would therefore match no policy and deliver him nothing — while working
--    perfectly for staff, which is the worst shape a bug can have.
--
--  ── ولماذا القناة خاصّة، وكيف أمكن ذلك ────────────────────────────────────
--    A PUBLIC broadcast channel needs no policy at all and would have worked —
--    but anyone holding the anon key (which is public by design) could then
--    listen and learn WHEN a message was sent. Not who, not to whom, not what.
--    Small, and avoidable, so it is avoided.
--
--  ⚠ AND THE HEADER PROBLEM DOES NOT ARISE HERE, WHICH IS THE WHOLE TRICK. The
--    device lock answers «WHICH HANDSET?» — a question worth asking of a man's
--    dues and his receipts. A doorbell hands over nothing that deserves it, so
--    the channel only has to answer «is this account in the association?», and
--    that is answerable from auth.uid() alone:
--
--        approved, AND (an admin OR bound to an عديل)
--
--    Deliberately NOT in_association(): that calls my_adeel_id(), which requires
--    the device to match — and a websocket has no device header, so using it
--    here would shut out every عديل and leave staff hearing the bell. The exact
--    failure this design exists to avoid.
--
--  ── وإن سقط الجرس، لا يسقط شيء ────────────────────────────────────────────
--    The polls stay exactly as they are, underneath. A websocket refused by a
--    carrier, a Realtime service not enabled, a broadcast that never arrives —
--    all of them cost the app the speed and nothing else. It is acceleration,
--    never a dependency.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ AND CHECK THE LAST ROW. If Realtime has never been used on this project,
--      `realtime.messages` may not exist yet — the file says so plainly rather
--      than failing, and the app simply goes on polling as it does today.
-- ============================================================================

BEGIN;

DO $bell$
DECLARE
  v_has boolean := to_regclass('realtime.messages') IS NOT NULL;
BEGIN
  IF NOT v_has THEN
    RAISE NOTICE 'realtime.messages غير موجود — فعّل Realtime من اللوحة ثم أعد تشغيل هذا الملف. التطبيق يعمل بدونه.';
    RETURN;
  END IF;

  -- ⚠ DROPPED FIRST SO THE FILE IS SAFE TO RUN TWICE. CREATE POLICY has no
  --   OR REPLACE, and a second run would fail on 42710 with the transaction
  --   half-read — which reads like the patch is broken rather than repeated.
  DROP POLICY IF EXISTS doorbell_listen ON realtime.messages;
  DROP POLICY IF EXISTS doorbell_ring   ON realtime.messages;

  -- ── من يسمع الجرس ────────────────────────────────────────────────────
  --
  -- ⚠ SCOPED TO ONE TOPIC BY NAME. Without the topic test this policy would
  --   open EVERY private channel this project ever creates to the same
  --   audience — including ones written years from now for something else
  --   entirely. A policy on realtime.messages is not «my feature's policy»;
  --   it is the whole schema's.
  EXECUTE $p$
    CREATE POLICY doorbell_listen ON realtime.messages
      FOR SELECT TO authenticated
      USING (
        realtime.topic() = 'association'
        AND EXISTS (
              SELECT 1 FROM public.profiles p
               WHERE p.id = auth.uid()
                 AND p.status = 'approved'
                 AND (p.role = 'admin' OR p.adeel_id IS NOT NULL)))
  $p$;

  -- ── ومن يدقّه ─────────────────────────────────────────────────────────
  --
  -- The same audience. A man who may hear that something happened may say that
  -- something happened — he has just written a message or raised a call, and
  -- the ring carries no more than the fact.
  EXECUTE $p$
    CREATE POLICY doorbell_ring ON realtime.messages
      FOR INSERT TO authenticated
      WITH CHECK (
        realtime.topic() = 'association'
        AND EXISTS (
              SELECT 1 FROM public.profiles p
               WHERE p.id = auth.uid()
                 AND p.status = 'approved'
                 AND (p.role = 'admin' OR p.adeel_id IS NOT NULL)))
  $p$;

  RAISE NOTICE 'جرس الباب مفعّل على القناة association.';
END $bell$;


-- ── ولا نصدّق ما لم نُشغّله ──────────────────────────────────────────────
--
-- ⚠ IT CHECKS THE PREDICATE, NOT THE POLICY NAME. A policy that exists and
--   admits nobody is the failure that would present as «Realtime does not
--   work», and a name check cannot tell the two apart.
DO $smoke$
DECLARE
  v_n int;
  v_admin uuid;
  v_ok boolean;
BEGIN
  IF to_regclass('realtime.messages') IS NULL THEN RETURN; END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname = 'realtime' AND tablename = 'messages'
     AND policyname IN ('doorbell_listen', 'doorbell_ring');
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'لم تُنشأ سياستا الجرس — وُجد % منهما', v_n;
  END IF;

  -- The admin must satisfy it.
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin' AND status = 'approved' LIMIT 1;

  SELECT EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.id = v_admin AND p.status = 'approved'
                    AND (p.role = 'admin' OR p.adeel_id IS NOT NULL))
    INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'الأدمن نفسه لا يسمع الجرس — الشرط خاطئ';
  END IF;

  -- ⚠ AND A PENDING ACCOUNT MUST NOT. This is the same class of account that
  --   walked into the association app in August; a doorbell is far less than
  --   that, and it still is not his.
  SELECT EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.status <> 'approved'
                    AND p.status IS NOT NULL
                    AND (p.role = 'admin' OR p.adeel_id IS NOT NULL))
    INTO v_ok;
  IF v_ok THEN
    RAISE EXCEPTION 'حسابٌ غير معتمد يمرّ من شرط الجرس';
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
