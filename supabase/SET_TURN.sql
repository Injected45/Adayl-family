-- ============================================================================
--  جمعية العدايل — SET_TURN.sql.  مُرحِّلٌ حيّ، فتعمل المكالمات بين الشبكات.
--
--  ⚠ THIS IS THE ONE THING STOPPING CROSS-NETWORK CALLS, AND IT IS NOT CODE.
--    Two men on the SAME wifi connect directly: the browser finds a host or a
--    server-reflexive candidate and the audio never touches a relay. Two men on
--    DIFFERENT networks usually cannot, because Libyan carriers run
--    carrier-grade NAT — both sides are behind an address neither can reach, and
--    STUN can only describe that, not solve it. The audio has to be RELAYED,
--    and a relay is a server somebody pays for.
--
--  ⚠ AND THE ONE CONFIGURED HERE IS DEAD. `openrelay.metered.ca` was a free
--    public relay that has stopped answering. That is why «فحص مسار الاتصال»
--    reports host ✅ STUN ✅ **TURN ❌** — and why calls work on one wifi and
--    fail the moment somebody switches to his own data.
--
--  ── ما تحتاجه قبل تشغيل هذا الملف ─────────────────────────────────────────
--    A TURN server with a STATIC username and password. metered.ca is the
--    reason this project can do it with one UPDATE and no server of its own:
--    most providers mint short-lived credentials through an API, which would
--    need something running to mint them. Static credentials sit in a column.
--
--      1. metered.ca → create a free account.
--      2. Open the TURN server / credentials page.
--      3. Copy three things: the HOST, the USERNAME, the PASSWORD.
--
--  ⚠ REPLACE ALL THREE BELOW. The file REFUSES to apply while a placeholder is
--    still there — a half-filled relay config is worse than the dead one,
--    because it looks configured.
--
--  HOW TO APPLY
--    Edit the three values IN YOUR EDITOR — never in this file — then
--    SQL Editor → paste → Run. Then open «فحص مسار الاتصال» on ONE phone: it
--    must now report relay. No new APK: every handset reads this column on its
--    next call.
--
--  ⚠ THIS FILE IS A TEMPLATE AND MUST STAY ONE. DO NOT FILL IN THE REAL
--    VALUES AND COMMIT THEM. This repository is PUBLIC, and a TURN password
--    committed here is the same mistake as the admin password in
--    `run_emulator.bat` — smaller in blast radius (it spends the association's
--    relay quota, it does not open the database) and identical in kind.
--    Deleting the line later does not help; it stays in the git history.
--
--    The placeholder guard below is what enforces it: the file refuses to
--    apply while `PUT-…` is present, so an untouched copy in the repo can
--    never be «the config», only the recipe for one.
--
--  STATE ON 2026-08-23
--    The live project IS configured — metered.ca, host
--    `global.relay.metered.ca`, four relay URLs plus two STUN — applied by
--    pasting a filled-in copy directly into the SQL Editor. «فحص مسار الاتصال»
--    on a real handset reported **TURN ✅ المكالمات تعمل بين شبكتين مختلفتين**.
--    So running THIS file changes nothing and will refuse; it exists for the
--    day the relay has to be replaced.
--
--  ⚠ AND WHEN THAT DAY COMES, THE FIRST THING TO CHECK IS THE QUOTA, NOT THE
--    CODE. The free tier is 0.5 GB a month — roughly sixteen hours of RELAYED
--    voice, and only relayed legs count. Over the limit the server simply
--    stops, and the symptom is «المكالمة لا تُفتح» on mobile data with nothing
--    anywhere saying why.
-- ============================================================================

BEGIN;

DO $turn$
DECLARE
  -- ⚠ ✂ ------------------ ضع قيمك هنا ------------------ ✂
  v_host text := 'PUT-YOUR-TURN-HOST-HERE';   -- مثال: a.relay.metered.ca
  v_user text := 'PUT-YOUR-USERNAME-HERE';
  v_pass text := 'PUT-YOUR-PASSWORD-HERE';
  -- ⚠ ✂ --------------------------------------------------- ✂
  v_ice  jsonb;
  v_n    int;
BEGIN
  IF v_host LIKE 'PUT-%' OR v_user LIKE 'PUT-%' OR v_pass LIKE 'PUT-%' THEN
    RAISE EXCEPTION
      'لم تُستبدل القيم الثلاث — عدّل السطور أعلاه ثم أعد التشغيل. لم يتغيّر شيء.';
  END IF;

  IF btrim(v_host) = '' OR btrim(v_user) = '' OR btrim(v_pass) = '' THEN
    RAISE EXCEPTION 'قيمة فارغة — المُرحِّل بلا اعتماد لا يعمل. لم يتغيّر شيء.';
  END IF;

  -- ── STUN FIRST, AND IT STAYS ───────────────────────────────────────────
  -- ⚠ REMOVING IT WOULD SEND EVERY CALL THROUGH THE RELAY, including two men
  --   sitting in the same room on the same wifi. ICE tries the cheap paths
  --   first and only falls back to a relay when it must, so keeping STUN is
  --   what stops the association paying for traffic it does not need.
  --
  -- ── AND THE RELAY IS OFFERED FOUR WAYS ────────────────────────────────
  -- ⚠ UDP IS THE FAST ONE AND IS ALSO THE ONE THAT GETS BLOCKED. Carrier
  --   networks and café wifi routinely drop it. 443/TCP and TLS look like
  --   ordinary HTTPS traffic and pass almost everywhere — slower, and the
  --   difference between a call that connects and one that does not.
  v_ice := jsonb_build_array(
    jsonb_build_object('urls', 'stun:stun.l.google.com:19302'),
    jsonb_build_object('urls', 'stun:stun1.l.google.com:19302'),
    jsonb_build_object('urls', 'stun:stun.cloudflare.com:3478'),
    jsonb_build_object(
      'urls', jsonb_build_array(
        'turn:'  || v_host || ':80',
        'turn:'  || v_host || ':443',
        'turn:'  || v_host || ':443?transport=tcp',
        'turns:' || v_host || ':443?transport=tcp'),
      'username',   v_user,
      'credential', v_pass));

  UPDATE public.association_settings SET ice_servers = v_ice;

  -- ── ولا نصدّق ما لم نقرأه بعد الكتابة ─────────────────────────────────
  SELECT count(*) INTO v_n
    FROM public.association_settings s,
         jsonb_array_elements(s.ice_servers) e
   WHERE e::text LIKE '%turn:%' AND e ? 'credential';
  IF v_n < 1 THEN
    RAISE EXCEPTION 'لم يُكتب مُرحِّل باعتماد — أُلغي كل شيء.';
  END IF;

  SELECT count(*) INTO v_n
    FROM public.association_settings s,
         jsonb_array_elements(s.ice_servers) e
   WHERE e ->> 'urls' LIKE 'stun:%';
  IF v_n < 1 THEN
    RAISE EXCEPTION 'ضاعت خوادم STUN — كل مكالمة ستمرّ بالمُرحِّل. أُلغي كل شيء.';
  END IF;

  -- ⚠ AND THE DEAD ONE MUST BE GONE. Leaving it in the list costs every call
  --   the seconds ICE spends trying it before giving up, on both handsets.
  SELECT count(*) INTO v_n
    FROM public.association_settings s
   WHERE s.ice_servers::text LIKE '%openrelay%';
  IF v_n > 0 THEN
    RAISE EXCEPTION 'المُرحِّل الميّت ما زال في القائمة — أُلغي كل شيء.';
  END IF;

  RAISE NOTICE 'المُرحِّل ضُبط على %. جرّب «فحص مسار الاتصال» على هاتف واحد.', v_host;
END $turn$;

SELECT public.assert_signin_intact();
SELECT public.assert_two_doors_only();

COMMIT;
