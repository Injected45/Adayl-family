-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-15 (f).  التحكّم في حذف رسائل المحادثات.
--
--  ما الذي يفعله هذا الملف — ثلاثُ دوالّ، والحذفُ الفرديُّ كما هو:
--
--    فرديّ  delete_chat_message   (موجودة، لم تتغيّر) رسالةٌ واحدة.
--    جزئيّ  delete_chat_messages  رسائلُ محدَّدة معًا، بالقاعدة نفسِها تمامًا:
--                                  صاحبُ الرسالة، أو الأدمن في المحادثة الجماعية
--                                  ومحادثات المشتركين مع الإدارة. يبقى مكانُ
--                                  كلِّ رسالة «حُذفت الرسالة» كالحذف الفرديّ.
--    كلّيّ  clear_chat_thread      يمسح محادثةَ مشتركٍ واحد مع الإدارة كلَّها.
--           clear_all_board_threads يمسح كلَّ محادثات المشتركين مع الإدارة.
--
--  ⚠ المسحُ الكلّيّ للأدمن وحده، ويحذف الصفوفَ نفسَها: محادثةٌ ممسوحة لا تبقى
--    قائمةً من «حُذفت الرسالة».
--
--  ⚠ لا يمسّ المحادثةَ الجماعيّة ولا المحادثاتِ الثنائيّة بين المشتركين: تلك
--    خاصّةٌ تمامًا ولا يقرؤها الأدمن، فلا يحذفها. كلُّ حذفٍ يُسجَّل في سجلّ
--    العمليات بمَن ومتى وكم.
--
--  ⚠ الجزئيّ «كلُّه أو لا شيء»: إن كانت بين المحدَّد رسالةٌ لا يحقّ للطالب
--    حذفُها رُفض الطلبُ كاملًا ولم تُحذف رسالةٌ واحدة.
--
--  ⚠ وإصلاحُ ثغرةٍ في الحذف الفرديّ الموجود: شرطُ «هل هو أدمن؟» كان يُعطي NULL
--    لحساب المشترك (my_role() لا تُرجع له دورًا)، وNULL في شرط IF يُعامَل كأنّه
--    «لا تمنع»، فكان المشتركُ يستطيع — من خارج التطبيق — حذفَ رسالة الأدمن
--    ورسائل المشتركين الآخرين للإدارة. التطبيقُ لم يعرض ذلك قطّ، والقاعدةُ الآن
--    تمنعه. الإصلاحُ: coalesce(…, false) — والدالّةُ منقولةٌ حرفًا من ملفّ
--    PATCH_20260826a_voice_notes.sql لا يتغيّر فيها غيرُ هذا الشرط.
--
--  ⚠ لا يتغيّر أيُّ رقمٍ ماليّ ولا أيُّ دالّةٍ ماليّة.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.chat_messages') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'chat_messages'
                       AND column_name = 'peer_a')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'chat_messages'
                       AND column_name = 'voice_path') THEN
    RAISE EXCEPTION 'جدول المحادثات ليس على آخر نسخة — لم يتغيّر شيء.';
  END IF;
  IF to_regprocedure('public.require_role(app_role)') IS NULL
     OR to_regprocedure('public.my_role()') IS NULL
     OR to_regprocedure('public.write_audit(text,text,text)') IS NULL
     OR to_regprocedure('public.client_callable_functions()') IS NULL THEN
    RAISE EXCEPTION 'هذا ليس مشروع الجمعية — لم يتغيّر شيء.';
  END IF;

  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);
END $prereq$;

-- == 0. الحذفُ الفرديّ: الثغرةُ مُغلقة =========================================
-- ⚠ منقولةٌ من PATCH_20260826a_voice_notes.sql §4 كما هي، إلا الشرط:
--   كان  AND NOT (v_role = 'admin' AND v_row.peer_a IS NULL)
--   فلحساب المشترك v_role = NULL، والتعبيرُ كلُّه NULL، وIF NULL لا يرفع — فيمضي
--   الحذف. coalesce(…, false) تجعل «ليس أدمنًا» جوابًا لا فراغًا.
CREATE OR REPLACE FUNCTION public.delete_chat_message(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $del$
DECLARE v_row record; v_role app_role := public.my_role();
BEGIN
  SELECT * INTO v_row FROM public.chat_messages WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الرسالة غير موجودة' USING ERRCODE = 'RUL18';
  END IF;

  IF v_row.author_user_id IS DISTINCT FROM auth.uid()
     AND NOT coalesce(v_role = 'admin' AND v_row.peer_a IS NULL, false) THEN
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

-- == 1. جزئيّ: رسائلُ محدَّدة معًا ============================================
-- ⚠ القاعدةُ حرفًا كما في delete_chat_message: صاحبُ الرسالة، أو الأدمن ما دامت
--   الرسالةُ ليست في محادثةٍ ثنائيّة (peer_a IS NULL).
CREATE OR REPLACE FUNCTION public.delete_chat_messages(p_ids bigint[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $dm$
DECLARE
  v_role    app_role := public.my_role();
  v_ids     bigint[];
  v_found   int;
  v_refused int;
  v_done    int;
BEGIN
  SELECT array_agg(DISTINCT x) INTO v_ids
    FROM unnest(coalesce(p_ids, '{}'::bigint[])) x
   WHERE x IS NOT NULL;

  IF v_ids IS NULL THEN
    RAISE EXCEPTION 'لم تُحدَّد رسائل للحذف' USING ERRCODE = 'RUL18';
  END IF;
  IF cardinality(v_ids) > 500 THEN
    RAISE EXCEPTION 'لا يُحذف أكثر من 500 رسالة في المرة الواحدة'
      USING ERRCODE = 'RUL18';
  END IF;

  SELECT count(*) INTO v_found
    FROM public.chat_messages WHERE id = ANY (v_ids);
  IF v_found <> cardinality(v_ids) THEN
    RAISE EXCEPTION 'بعض الرسائل المحدَّدة غير موجودة' USING ERRCODE = 'RUL18';
  END IF;

  SELECT count(*) INTO v_refused
    FROM public.chat_messages m
   WHERE m.id = ANY (v_ids)
     AND m.author_user_id IS DISTINCT FROM auth.uid()
     AND NOT coalesce(v_role = 'admin' AND m.peer_a IS NULL, false);
  IF v_refused > 0 THEN
    RAISE EXCEPTION 'لا يمكنك حذف رسالة غيرك' USING ERRCODE = 'RUL00';
  END IF;

  UPDATE public.chat_messages
     SET deleted_at = now(), deleted_by = auth.uid(),
         body = '', voice_path = NULL, voice_ms = NULL
   WHERE id = ANY (v_ids) AND deleted_at IS NULL;
  GET DIAGNOSTICS v_done = ROW_COUNT;

  PERFORM public.write_audit('chat.delete',
    format('حذف %s رسالة معًا', v_done), array_to_string(v_ids, ','));

  RETURN jsonb_build_object('deleted', v_done);
END $dm$;

-- == 2. كلّيّ: محادثةُ مشتركٍ واحد مع الإدارة =================================
CREATE OR REPLACE FUNCTION public.clear_chat_thread(p_thread_adeel_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $ct$
DECLARE
  v_deleted bigint;
  v_code    text;
BEGIN
  PERFORM public.require_role('admin');

  IF p_thread_adeel_id IS NULL THEN
    RAISE EXCEPTION 'حدِّد المحادثة المراد مسحها' USING ERRCODE = 'RUL18';
  END IF;

  -- ⚠ peer_a IS NULL صريحةً: محادثاتُ المشتركين الثنائيّة لا تُمسّ أبدًا.
  DELETE FROM public.chat_messages
   WHERE thread_adeel_id = p_thread_adeel_id AND peer_a IS NULL;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  SELECT a.adeel_code INTO v_code FROM public.adeels a WHERE a.id = p_thread_adeel_id;

  PERFORM public.write_audit('chat.clear',
    format('مسح محادثة %s مع الإدارة (%s رسالة)',
           coalesce(v_code, p_thread_adeel_id::text), v_deleted),
    p_thread_adeel_id::text);

  RETURN jsonb_build_object('deleted', v_deleted);
END $ct$;

-- == 3. كلّيّ: كلُّ محادثات المشتركين مع الإدارة ===============================
CREATE OR REPLACE FUNCTION public.clear_all_board_threads()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $ca$
DECLARE
  v_deleted bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- ⚠ المحادثةُ الجماعيّة (thread_adeel_id IS NULL) والثنائيّة (peer_a) لا تُمسّان.
  DELETE FROM public.chat_messages
   WHERE thread_adeel_id IS NOT NULL AND peer_a IS NULL;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  PERFORM public.write_audit('chat.clear',
    format('مسح كل محادثات المشتركين مع الإدارة (%s رسالة)', v_deleted));

  RETURN jsonb_build_object('deleted', v_deleted);
END $ca$;

-- == 4. قائمةُ السماح =======================================================
DO $allow$
DECLARE
  v_new  text[] := public.client_callable_functions();
  v_sig  text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'delete_chat_messages(bigint[])',
    'clear_chat_thread(bigint)',
    'clear_all_board_threads()'
  ] LOOP
    IF NOT (v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_new) a)) THEN
      v_new := v_new || v_sig;
    END IF;
  END LOOP;

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

-- == 5. المسحة، بعد آخر CREATE في هذا الملف ================================
DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.full_sig);
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;

-- == 6. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 7. النتيجة: آخرُ جدولٍ يظهر في المحرّر، وكلُّ صفٍّ يجب أن يقول true ======
SELECT 'الحذفُ الجزئيّ والمسحُ الكلّيّ متاحان للتطبيق' AS "الفحص",
       (has_function_privilege('authenticated', 'public.delete_chat_messages(bigint[])', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.clear_chat_thread(bigint)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.clear_all_board_threads()', 'EXECUTE'))::text
         AS "النتيجة"
UNION ALL SELECT 'ولا يصل إليها غيرُ المسجَّل',
       (NOT has_function_privilege('anon', 'public.delete_chat_messages(bigint[])', 'EXECUTE')
        AND NOT has_function_privilege('anon', 'public.clear_chat_thread(bigint)', 'EXECUTE')
        AND NOT has_function_privilege('anon', 'public.clear_all_board_threads()', 'EXECUTE'))::text
UNION ALL SELECT 'والحذفُ الفرديُّ باقٍ، وثغرتُه مُغلقة',
       (has_function_privilege('authenticated', 'public.delete_chat_message(bigint)', 'EXECUTE')
        AND (SELECT prosrc LIKE '%coalesce(v_role = ''admin''%'
               FROM pg_proc WHERE oid = 'public.delete_chat_message(bigint)'::regprocedure))::text
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       ((SELECT row_to_json(s)::text FROM public.v_cash_summary s)
          = current_setting('adayl.fund_before', true))::text;

COMMIT;
