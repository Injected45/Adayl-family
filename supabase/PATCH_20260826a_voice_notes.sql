-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-26 (a).  مقاطعُ صوتيّة، بشروط الرسائل.
--
--  الطلب: «تسجيل وإرسال مقاطع صوتية من داخل المحادثات بنفس شروط الرسائل».
--
--  ── أصعبُ ما فيه ليس التسجيل ─────────────────────────────────────────────
--    A clip is a FILE IN A BUCKET, not a row in a table, and Supabase Storage
--    has its own RLS on storage.objects. Write a second rule there and it can
--    disagree with read_chat — a private note between two عدايل audible to
--    anybody who could guess a path, while the MESSAGE that carried it stayed
--    correctly hidden. That is the worst shape a leak takes: the guarded thing
--    guarded, and its contents open.
--
--  ⚠ SO THE FILE ASKS THE MESSAGE. The SELECT policy joins v_chat_messages —
--    SECURITY INVOKER, so read_chat evaluates for the CALLER exactly as it does
--    for the text. A clip is audible if and only if its message is readable.
--    Not «the same rule written twice»: the SAME rule, once.
--
--  ⚠ AND THE UPLOAD CANNOT WORK THAT WAY, because the file exists before the
--    message does. So writing is fixed to «my uid / …» — a man may only put
--    bytes under his own name — and send_chat_message refuses to attach a path
--    that is not his. Two guards saying one thing, because attaching is what
--    makes a file audible.
--
--  ⚠ THE BUCKET MUST BE PRIVATE. A public bucket serves every object by URL to
--    anybody on earth, and no policy in this file would be consulted. The smoke
--    test refuses to finish otherwise.
--
--  HOW TO APPLY
--    Storage → New bucket → name «voice» → Private. Then paste and Run.
-- ============================================================================

BEGIN;

-- ── §1. عمودان على الرسالة ──────────────────────────────────────────────
--
-- ⚠ ON chat_messages RATHER THAN A TABLE OF ITS OWN. A voice note IS a
--   message — same room, same author, same 20-a-minute limit, same tombstone
--   on deletion. A second table would need every one of those rules copied,
--   and a copy is a thing that drifts.
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS voice_path text,
  ADD COLUMN IF NOT EXISTS voice_ms   integer;

-- ⚠ ONE MESSAGE PER FILE, ENFORCED. Without it two rows could point at one
--   object and deleting either would silence both.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_voice_path
  ON public.chat_messages (voice_path) WHERE voice_path IS NOT NULL;


-- ⚠ AND THE BODY CONSTRAINT HAS TO WIDEN WITH IT. ck_chat_body demanded a
--   non-empty body on every live row — right when a message was words and only
--   words. A voice note is a message with NO words, and the old check refused
--   it before send_chat_message ever ran.
--
-- ⚠ THE RULE IS NOT DROPPED, IT IS RESTATED: a live message must carry SOMETHING
--   — words or a clip. An empty send is still refused, by the table, not only by
--   the function.
ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS ck_chat_body;
ALTER TABLE public.chat_messages ADD CONSTRAINT ck_chat_body CHECK (
  char_length(body) <= 1000
  AND (deleted_at IS NOT NULL
       OR btrim(body) <> ''
       OR voice_path IS NOT NULL)
);


-- ── §2. الإرسال ─────────────────────────────────────────────────────────
--
-- ⚠ THE THREE-ARGUMENT VERSION IS DROPPED, NOT LEFT BESIDE THIS ONE. PostgREST
--   dispatches on the NAMED parameters a client sends, so both overloads would
--   be reachable — and an old handset sending p_body + p_thread_adeel_id would
--   land on the previous function, which knows nothing about voice. That is the
--   redeem_adeel_code trap, and this project has now paid for it twice.
DROP FUNCTION IF EXISTS public.send_chat_message(text, bigint, bigint);

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_body            text,
  p_thread_adeel_id bigint DEFAULT NULL,
  p_to_adeel_id     bigint DEFAULT NULL,
  p_voice_path      text DEFAULT NULL,
  p_voice_ms        integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_adeel  bigint := public.my_adeel_id();
  v_role   app_role := public.my_role();
  v_body   text := btrim(coalesce(p_body, ''));
  v_name   text;
  v_recent int;
  v_id     bigint;
  v_a      bigint;
  v_b      bigint;
BEGIN
  IF v_role IS NULL AND v_adeel IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  -- ── ثنائية ────────────────────────────────────────────────────────────
  IF p_to_adeel_id IS NOT NULL THEN
    IF p_thread_adeel_id IS NOT NULL THEN
      RAISE EXCEPTION 'لا يمكن الجمع بين خيط الإدارة والمحادثة الثنائية'
        USING ERRCODE = 'RUL18';
    END IF;

    -- ⚠ AN عديل ONLY. The admin holds no adeel_id — my_role() returns NULL
    --   the moment one is set — so he has no seat in a two-man conversation
    --   and cannot open one. That is what «خاصّة تماماً» means on the write
    --   side, and it is the same clause that keeps him out on the read side.
    IF v_adeel IS NULL THEN
      RAISE EXCEPTION 'المحادثة الثنائية بين العدايل وحدهم'
        USING ERRCODE = 'RUL00';
    END IF;

    IF p_to_adeel_id = v_adeel THEN
      RAISE EXCEPTION 'لا يمكنك مراسلة نفسك' USING ERRCODE = 'RUL18';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.adeels a WHERE a.id = p_to_adeel_id) THEN
      RAISE EXCEPTION 'العديل غير موجود' USING ERRCODE = 'RUL18';
    END IF;

    -- The canonical pair — the same two numbers whoever is writing.
    v_a := least(v_adeel, p_to_adeel_id);
    v_b := greatest(v_adeel, p_to_adeel_id);

  -- ── خيط الإدارة ───────────────────────────────────────────────────────
  ELSIF p_thread_adeel_id IS NOT NULL THEN
    IF v_role IS NULL AND p_thread_adeel_id IS DISTINCT FROM v_adeel THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.adeels a WHERE a.id = p_thread_adeel_id)
    THEN
      RAISE EXCEPTION 'العديل غير موجود' USING ERRCODE = 'RUL18';
    END IF;
  END IF;

  -- ⚠ A VOICE NOTE IS A MESSAGE WITH NO WORDS, and «الرسالة فارغة» is still
  --   the rule for one with neither. The body stays optional ONLY when a clip
  --   is attached, so an empty send is refused exactly as before.
  IF v_body = '' AND p_voice_path IS NULL THEN
    RAISE EXCEPTION 'الرسالة فارغة' USING ERRCODE = 'RUL18';
  END IF;

  -- ── ⚠ الصوت: مسارٌ يخصّه هو، ومدّةٌ معقولة ──────────────────────────────
  IF p_voice_path IS NOT NULL THEN
    -- ⚠ THE PATH MUST START WITH HIS OWN uid, AND THE STORAGE POLICY DEMANDS
    --   THE SAME. Two guards saying one thing: without this a man could attach
    --   somebody else's clip to his own message and republish it into a room
    --   its owner never chose. The upload policy fixes the prefix; this fixes
    --   what may be NAMED, and a message is what makes a file audible.
    IF p_voice_path NOT LIKE (auth.uid()::text || '/%') THEN
      RAISE EXCEPTION 'مسار المقطع غير صحيح' USING ERRCODE = 'RUL18';
    END IF;

    -- ⚠ SIXTY SECONDS. A voice note is a sentence, not a broadcast — and the
    --   bucket is a free tier the association does not pay for. The client
    --   stops at the same figure; this is the one that cannot be edited out.
    IF coalesce(p_voice_ms, 0) <= 0 OR p_voice_ms > 60000 THEN
      RAISE EXCEPTION 'مدة المقطع غير مقبولة' USING ERRCODE = 'RUL18';
    END IF;

    -- ⚠ ONE CLIP PER MESSAGE, AND NEVER TWICE. Naming a path that is already
    --   attached would let a man point a second message at the first one's
    --   file — and deleting either would silence both.
    IF EXISTS (SELECT 1 FROM public.chat_messages m
                WHERE m.voice_path = p_voice_path) THEN
      RAISE EXCEPTION 'هذا المقطع مُرسل بالفعل' USING ERRCODE = 'RUL18';
    END IF;
  END IF;
  IF char_length(v_body) > 1000 THEN
    RAISE EXCEPTION 'الرسالة أطول من 1000 حرف' USING ERRCODE = 'RUL18';
  END IF;

  SELECT count(*) INTO v_recent
    FROM public.chat_messages
   WHERE author_user_id = auth.uid()
     AND created_at > now() - interval '1 minute';
  IF v_recent >= 20 THEN
    RAISE EXCEPTION 'أرسلت رسائل كثيرة في وقت قصير، انتظر قليلاً'
      USING ERRCODE = 'RUL18';
  END IF;

  IF v_adeel IS NOT NULL THEN
    SELECT a.full_name INTO v_name FROM public.adeels a WHERE a.id = v_adeel;
  END IF;
  IF v_name IS NULL OR btrim(v_name) = '' THEN
    SELECT nullif(btrim(p.display_name), '') INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;
  IF v_name IS NULL OR btrim(v_name) = '' THEN
    SELECT split_part(p.email, '@', 1) INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;

  INSERT INTO public.chat_messages
    (author_user_id, author_name, author_adeel_id, from_staff, body,
     thread_adeel_id, peer_a, peer_b, voice_path, voice_ms)
  VALUES (auth.uid(), coalesce(v_name, '—'), v_adeel, v_role IS NOT NULL,
          v_body, p_thread_adeel_id, v_a, v_b, p_voice_path, p_voice_ms)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'authorName', v_name);
END $$;

-- ── §3. العرض يحمل المقطع ───────────────────────────────────────────────
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
         CASE WHEN m.peer_a IS NOT NULL          THEN 'direct'
              WHEN m.thread_adeel_id IS NOT NULL THEN 'board'
              ELSE 'hall' END AS "room",
         CASE WHEN m.deleted_at IS NULL THEN m.voice_path END AS "voicePath",
         CASE WHEN m.deleted_at IS NULL THEN m.voice_ms   END AS "voiceMs"
    FROM public.chat_messages m
    LEFT JOIN public.adeels ta ON ta.id = m.thread_adeel_id;

GRANT SELECT ON public.v_chat_messages TO authenticated;


-- ── §4. الحذف يُفرّغ الصوت كما يُفرّغ النصّ ──────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_chat_message(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $del$
DECLARE v_row record; v_role app_role := public.my_role();
BEGIN
  SELECT * INTO v_row FROM public.chat_messages WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الرسالة غير موجودة' USING ERRCODE = 'RUL18';
  END IF;

  IF v_row.author_user_id <> auth.uid()
     AND NOT (v_role = 'admin' AND v_row.peer_a IS NULL) THEN
    RAISE EXCEPTION 'لا يمكنك حذف رسالة غيرك' USING ERRCODE = 'RUL00';
  END IF;

  UPDATE public.chat_messages
     SET deleted_at = now(), deleted_by = auth.uid(),
         body = '', voice_path = NULL, voice_ms = NULL
   WHERE id = p_id;

  PERFORM public.write_audit('chat.delete',
    format('حذف رسالة %s', p_id), p_id::text);

  RETURN jsonb_build_object('id', p_id, 'voicePath', v_row.voice_path);
END $del$;


-- ── §5. المخزن: الملفُّ يسأل الرسالة ────────────────────────────────────
--
-- ⚠ EVERY POLICY HERE IS SCOPED TO bucket_id = 'voice'. Storage holds one
--   objects table for every bucket in the project, so an unscoped policy is a
--   rule about files this feature has never heard of.
DROP POLICY IF EXISTS voice_read   ON storage.objects;
DROP POLICY IF EXISTS voice_upload ON storage.objects;
DROP POLICY IF EXISTS voice_remove ON storage.objects;

-- ⚠ THE WHOLE SECURITY ARGUMENT IS THIS JOIN. v_chat_messages is SECURITY
--   INVOKER, so read_chat evaluates for the CALLER — a clip is audible if and
--   only if its message is readable, by the same rule, evaluated once. A
--   hand-written copy of read_chat here would be a second rule free to drift
--   from the first, and the drift would be silent.
CREATE POLICY voice_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'voice'
    AND EXISTS (SELECT 1 FROM public.v_chat_messages v
                 WHERE v."voicePath" = storage.objects.name)
  );

-- ⚠ WRITING CANNOT ASK THE MESSAGE, because the file exists before the message
--   does. So a man may only put bytes under his own uid — and
--   send_chat_message refuses to ATTACH a path that is not his, which is what
--   makes a file audible at all. Junk under his own prefix is bounded and
--   inaudible.
CREATE POLICY voice_upload ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'voice'
    AND public.in_association()
    AND name LIKE (auth.uid()::text || '/%')
  );

-- ⚠ AND HE MAY REMOVE HIS OWN — how a deleted message's file goes, and how a
--   recording abandoned before sending is cleaned up.
CREATE POLICY voice_remove ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'voice'
    AND name LIKE (auth.uid()::text || '/%')
  );


-- ── §6. الصلاحية: تُبدَّل في القائمة الحيّة، ولا تُكتب من جديد ───────────
--
-- ⚠ THE SIGNATURE CHANGED, so the old one is no longer callable and the new
--   one is not on the list. Both halves must move together or
--   assert_function_grants rolls the patch back — which is exactly what it did
--   on the first run of this file.
--
-- ⚠ AND THE LIST IS READ, NOT RESTATED. On 23/08 a patch rebuilt
--   client_callable_functions() from an array written in an older file, the
--   live list had drifted, and six working endpoints lost their grant. Read the
--   live value, swap one entry, rewrite from THAT. The ::text is load-bearing —
--   text[] || 'x' parses as array||array.
DO $allow$
DECLARE v_list text[];
BEGIN
  SELECT array_agg(x) INTO v_list
    FROM unnest(public.client_callable_functions()) x
   WHERE x <> 'send_chat_message(text,bigint,bigint)';

  IF NOT ('send_chat_message(text,bigint,bigint,text,integer)' = ANY (v_list))
  THEN
    v_list := v_list || 'send_chat_message(text,bigint,bigint,text,integer)'::text;
  END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.client_callable_functions() '
    'RETURNS text[] LANGUAGE sql IMMUTABLE AS $b$ SELECT %L::text[] $b$',
    v_list);
END $allow$;

-- ⚠ A FUNCTION CREATED FRESH HAS NO ACL TO KEEP — DROP + CREATE is what
--   changing a signature costs — so Postgres materialises EXECUTE to PUBLIC and
--   Supabase layers anon on top. assert_no_public_execute catches it; this is
--   the REVOKE that stops it getting there.
REVOKE ALL ON FUNCTION
  public.send_chat_message(text, bigint, bigint, text, integer)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.send_chat_message(text, bigint, bigint, text, integer)
  TO authenticated;

-- ── §7. ولا نصدّق ما لم نُشغّله ─────────────────────────────────────────
DO $smoke$
DECLARE v_n int; v_pub boolean;
BEGIN
  SELECT b.public INTO v_pub FROM storage.buckets b WHERE b.id = 'voice';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد مخزن باسم voice — أنشئه أولاً: Storage → New bucket';
  END IF;
  -- ⚠ A PUBLIC BUCKET SERVES EVERY OBJECT BY URL and consults no policy at
  --   all. Every line above would be decoration.
  IF v_pub THEN
    RAISE EXCEPTION 'المخزن voice عامّ — اجعله Private، وإلا فكل مقطع مقروء برابطه';
  END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname IN ('voice_read','voice_upload','voice_remove');
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'سياسات المخزن ناقصة: % من ٣', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'send_chat_message';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ما زال هناك % نسخة من send_chat_message', v_n;
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
