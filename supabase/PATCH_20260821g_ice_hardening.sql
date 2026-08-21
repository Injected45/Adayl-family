-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (g).  تقوية مسار الاتصال عبر الشبكات.
--
--  WHAT CHANGES
--    One column: association_settings.ice_servers is replaced with a wider
--    list. No table, no function, no policy — this is a data change wearing a
--    patch's clothes, and it is a patch only because that column is the one
--    place the app reads its network path from.
--
--  ⚠ WHY, AND IT IS THE ONE THING MOST LIKELY TO DECIDE WHETHER A CALL BETWEEN
--    TWO DIFFERENT NETWORKS CONNECTS AT ALL.
--
--    Two phones on the same wifi find each other with a HOST candidate and
--    need nothing. Two phones on different networks need one of:
--
--      • srflx (STUN) — works when at least one side's NAT is permissive.
--      • relay (TURN) — works when neither is, which on Libyan mobile
--        carriers is the common case, because they run carrier-grade NAT.
--
--    ⚠ AND TURN OVER UDP IS NOT ENOUGH. Mobile carriers and office wifi block
--      or throttle UDP on unusual ports far more often than they block TCP 443
--      — which is indistinguishable from ordinary HTTPS. A list with only
--      `turn:host:3478` fails on exactly the networks TURN exists for. So the
--      list below climbs: UDP first because it is best for voice, then TCP 80,
--      then TCP 443, then TLS on 443 as the last resort that almost nothing
--      can tell apart from web traffic.
--
--  ⚠ THESE ARE PUBLIC, BORROWED SERVERS, and that is a real limitation stated
--    plainly rather than hidden. They need no account, which is why they are
--    the default — and nobody owes the association any uptime. The moment
--    «فحص الاتصال» in the app reports TURN as unreachable, the answer is to
--    put a paid relay in this column. That is ONE UPDATE, from the SQL editor,
--    with no new APK:
--
--      UPDATE public.association_settings
--         SET ice_servers = '[
--               {"urls": "stun:stun.l.google.com:19302"},
--               {"urls": ["turn:YOUR-HOST:3478",
--                         "turn:YOUR-HOST:443?transport=tcp",
--                         "turns:YOUR-HOST:443?transport=tcp"],
--                "username": "…", "credential": "…"}
--             ]'::jsonb
--       WHERE id = 1;
--
--    That is the whole upgrade path, and it is why this list was never
--    compiled into the app.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ Requires PATCH_20260821d_voice_calls.sql (it created the column).
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name   = 'association_settings'
       AND column_name  = 'ice_servers'
  ) THEN
    RAISE EXCEPTION
      'العمود ice_servers غير موجود. طبّق supabase/PATCH_20260821d_voice_calls.sql أولاً.';
  END IF;
END
$prereq$;


-- ── القائمة الجديدة ────────────────────────────────────────────────────────
--
-- ⚠ FOUR STUN HOSTS, NOT ONE. Gathering a srflx candidate is the cheap half of
--   the problem and one unreachable host should not cost it. They are
--   different machines behind the same name, and asking all four costs a few
--   UDP packets.
--
-- ⚠ AND THE TURN ENTRY LISTS ITS URLS AS AN ARRAY under ONE credential, which
--   is what the WebRTC spec is for: the browser or the phone tries them in
--   order and stops at the first that answers. Four separate objects with the
--   same username would work too and would make the intent — «one server,
--   four ways in» — impossible to read.
UPDATE public.association_settings
   SET ice_servers = '[
         {"urls": "stun:stun.l.google.com:19302"},
         {"urls": "stun:stun1.l.google.com:19302"},
         {"urls": "stun:stun2.l.google.com:19302"},
         {"urls": "stun:stun.cloudflare.com:3478"},
         {"urls": [
            "turn:openrelay.metered.ca:80",
            "turn:openrelay.metered.ca:443",
            "turn:openrelay.metered.ca:443?transport=tcp",
            "turns:openrelay.metered.ca:443?transport=tcp"
          ],
          "username": "openrelayproject",
          "credential": "openrelayproject"}
       ]'::jsonb
 WHERE id = 1;


-- And the same list becomes the DEFAULT, so a project reset does not go back
-- to the narrower one.
ALTER TABLE public.association_settings
  ALTER COLUMN ice_servers SET DEFAULT '[
    {"urls": "stun:stun.l.google.com:19302"},
    {"urls": "stun:stun1.l.google.com:19302"},
    {"urls": "stun:stun2.l.google.com:19302"},
    {"urls": "stun:stun.cloudflare.com:3478"},
    {"urls": [
       "turn:openrelay.metered.ca:80",
       "turn:openrelay.metered.ca:443",
       "turn:openrelay.metered.ca:443?transport=tcp",
       "turns:openrelay.metered.ca:443?transport=tcp"
     ],
     "username": "openrelayproject",
     "credential": "openrelayproject"}
  ]'::jsonb;


-- ── الحُرّاس ────────────────────────────────────────────────────────────────
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
