-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-23 (d).  الاسمُ في المكالمة اسمُ العديل.
--
--  الطلب: «الاسم الذي يظهر أثناء الاتصال أريده اسم العديل كما هو مسجّل من قبل
--  الأدمن في التطبيق، وليس اسم الإيميل.»
--
--  السبب: start_call و join_call كانتا تلتقطان profiles.display_name — وهو
--  الاسم الذي تُعطيه جوجل عند أوّل دخول، فيكون اسم حساب البريد. اسمُ العديل
--  في adeels.full_name، وهو الاسم الذي كتبه الأدمن.
--
--  ⚠ AND send_chat_message ALREADY DID IT RIGHT — adeels.full_name first, then
--    display_name, then the local part of the email. So المجلس has been
--    printing the register's names all along while the call printed Google's.
--    That is the drift a shared helper exists to stop, which is why this patch
--    adds one instead of copying the expression a third time.
--
--  ⚠ الأسماءُ لقطةٌ على الصفّ، فالمكالماتُ القديمةُ تبقى بأسمائها. لا يضرّ:
--    المكالمة تنتهي بعد دقائق، والسجلّ ليس فيه ما يُقرأ لاحقاً.
--
--  SQL Editor → New query → paste → Run. معاملةٌ واحدة، تُشغَّل مرّتين بأمان.
-- ============================================================================

BEGIN;

-- ── §1. مَن أنا، بالاسم الذي تعرفه الجمعية ─────────────────────────────────
--
-- ⚠ ONE PLACE ANSWERS ONE QUESTION. Three call sites wanted this name and each
--   had its own copy; the chat's copy was right and the two call copies were
--   wrong, and nothing could have noticed — a name is a name on screen.
--
-- ⚠ SECURITY DEFINER because it reads adeels, which an عديل may only see one
--   row of and a stranger none. It returns nothing but the CALLER'S OWN name,
--   so it opens no door: it is «what shall I be called», asked about oneself.
--
-- ⚠ AND THE EMAIL IS THE LAST RESORT, not the first — and only its local part.
--   A man with no عديل and no Google name is staff; printing his full address
--   in a call banner would put it on someone else's screen.
CREATE OR REPLACE FUNCTION public.my_display_name() RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $mdn$
DECLARE v_name text;
BEGIN
  SELECT nullif(btrim(a.full_name), '') INTO v_name
    FROM public.profiles p
    JOIN public.adeels a ON a.id = p.adeel_id
   WHERE p.id = auth.uid();

  IF v_name IS NULL THEN
    SELECT nullif(btrim(p.display_name), '') INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;

  IF v_name IS NULL THEN
    SELECT nullif(split_part(p.email, '@', 1), '') INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;

  RETURN coalesce(v_name, 'الإدارة');
END $mdn$;


-- ── §2. المكالمة تسأل الدالّة، ولا تنسخ التعبير ────────────────────────────
CREATE OR REPLACE FUNCTION public.start_call(
  p_thread_adeel_id bigint,
  p_peer_adeel_id   bigint DEFAULT NULL
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id   bigint;
  v_name text;
  v_live bigint;
  v_me   bigint := public.my_adeel_id();
BEGIN
  IF p_thread_adeel_id IS NOT NULL AND p_peer_adeel_id IS NOT NULL THEN
    RAISE EXCEPTION 'مكالمة لا تكون في محادثة وبين عديلين معاً.'
      USING ERRCODE = 'RUL16';
  END IF;

  IF NOT public.may_join_call(p_thread_adeel_id, p_peer_adeel_id, auth.uid())
  THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  -- ⚠ ONLY A BOUND عديل MAY RING ANOTHER. Staff calling a member directly
  --   would bypass the private thread, which is where the association speaks
  --   to him as an institution — and it is the thread the audit trail and the
  --   inbox are built around.
  IF p_peer_adeel_id IS NOT NULL AND v_me IS NULL THEN
    RAISE EXCEPTION 'الاتصال بين المشتركين، والإدارة تتصل عبر المحادثة الخاصة.'
      USING ERRCODE = 'RUL00';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtext('call:' || coalesce(p_thread_adeel_id::text, '') || ':' ||
             coalesce(p_peer_adeel_id::text, '') || ':' ||
             coalesce(v_me::text, 'staff'))
  );

  -- ⚠ THE LIVE TEST NOW COVERS BOTH DIRECTIONS OF A PEER CALL. Without the
  --   second half, two men ringing each other at the same instant raise two
  --   calls and each hears the other ring while neither connects.
  SELECT c.id INTO v_live
    FROM public.calls c
   WHERE (
           (p_peer_adeel_id IS NULL
            AND c.peer_adeel_id IS NULL
            AND c.thread_adeel_id IS NOT DISTINCT FROM p_thread_adeel_id)
           OR (p_peer_adeel_id IS NOT NULL
               AND ((c.peer_adeel_id = p_peer_adeel_id
                     AND c.caller_user_id = auth.uid())
                    OR (c.peer_adeel_id = v_me
                        AND EXISTS (SELECT 1 FROM public.profiles p
                                     WHERE p.id = c.caller_user_id
                                       AND p.adeel_id = p_peer_adeel_id))))
         )
     AND (
           (c.status = 'ترن' AND c.started_at >= now() - interval '60 seconds')
           OR (c.status = 'جارية' AND EXISTS (
                 SELECT 1 FROM public.call_participants p
                  WHERE p.call_id = c.id
                    AND p.left_at IS NULL
                    AND p.last_seen >= now() - interval '20 seconds'))
         )
   ORDER BY c.id DESC
   LIMIT 1;

  IF v_live IS NOT NULL THEN
    RETURN v_live;
  END IF;

  v_name := public.my_display_name();

  INSERT INTO public.calls
    (thread_adeel_id, peer_adeel_id, caller_user_id, caller_name)
  VALUES (p_thread_adeel_id, p_peer_adeel_id, auth.uid(),
          coalesce(v_name, 'الإدارة'))
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.join_call(p_call_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_c    record;
  v_name text;
  v_max  integer;
  v_now  integer;
  v_id   bigint;
BEGIN
  SELECT * INTO v_c FROM public.calls c WHERE c.id = p_call_id;
  IF NOT FOUND
     OR NOT public.may_join_call(v_c.thread_adeel_id, v_c.peer_adeel_id,
                                 v_c.caller_user_id) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;
  IF v_c.status NOT IN ('ترن', 'جارية') THEN
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

  v_name := public.my_display_name();

  INSERT INTO public.call_participants (call_id, user_id, display_name)
  VALUES (p_call_id, auth.uid(), coalesce(v_name, 'الإدارة'))
  ON CONFLICT (call_id, user_id) DO UPDATE
     SET last_seen = now(), left_at = NULL
  RETURNING id INTO v_id;

  UPDATE public.calls
     SET status = 'جارية', answered_at = coalesce(answered_at, now())
   WHERE id = p_call_id AND status = 'ترن'
     AND caller_user_id <> auth.uid();

  RETURN v_id;
END $$;

-- ── §3. الصلاحيات: الدالّة للخادم لا للتطبيق ───────────────────────────────
--
-- ⚠ A FUNCTION CREATED FRESH TAKES EXECUTE TO PUBLIC by default, and Supabase
--   layers anon on top. It is called only from inside two SECURITY DEFINER
--   functions, so no client ever needs it — and assert_no_public_execute()
--   would roll this patch back without the REVOKE, naming a function rather
--   than the missing line.
REVOKE ALL ON FUNCTION public.my_display_name()
  FROM PUBLIC, anon, authenticated, service_role;


-- ── §4. ولا نصدّق ما لم نُشغّله ────────────────────────────────────────────
DO $smoke$
DECLARE v_src text;
BEGIN
  FOR v_src IN
    SELECT pg_get_functiondef(p.oid)
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname IN ('start_call','join_call')
  LOOP
    IF v_src LIKE '%p.display_name%' THEN
      RAISE EXCEPTION 'ما زالت المكالمة تلتقط اسم جوجل بدل اسم العديل';
    END IF;
    IF v_src NOT LIKE '%my_display_name()%' THEN
      RAISE EXCEPTION 'المكالمة لا تسأل my_display_name()';
    END IF;
  END LOOP;

  -- والدالّة نفسها تعمل: تُستدعى بلا جلسة فتُرجع الافتراضي بدل أن ترفع خطأ.
  IF public.my_display_name() IS NULL THEN
    RAISE EXCEPTION 'my_display_name() أرجعت NULL';
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
