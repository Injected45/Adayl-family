-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-23 (a).  محادثة بين عديلٍ وعديل.
--
--  «انشأ لي محادثه بين عديل وعديل».
--
--  ⚠ AND THE ASSOCIATION CHOSE: خاصّة تماماً — لا يقرؤها الأدمن.
--    That was asked before a line was written, because it is a decision about
--    the جمعية rather than about code, and the two answers are different
--    features. What it BUYS is a private conversation. What it COSTS, and the
--    association accepted it knowingly:
--
--      • the admin cannot read a direct thread, so he cannot moderate one;
--      • he cannot delete an offensive message in one — see §5, where the
--        admin exception is deliberately removed for these rows;
--      • if two men fall out, there is nothing in the system to refer to.
--
--    Written here rather than in anyone's memory, so the next person to widen
--    the read policy knows he is reversing a decision, not fixing an oversight.
--
--  ── الشكل: ثلاث غرف، ومفتاحٌ واحد يميّزها ────────────────────────────────
--      1. المجلس        thread_adeel_id IS NULL, peer_a IS NULL
--      2. خيط الإدارة   thread_adeel_id = <عديل>, peer_a IS NULL
--      3. ثنائية        thread_adeel_id IS NULL, peer_a < peer_b
--
--  ⚠ THE PAIR IS CANONICAL: `peer_a < peer_b` IS A CHECK, NOT A CONVENTION.
--    Without it, (3,7) and (7,3) are two different threads for the same two
--    men — each seeing half the conversation, both convinced the other is not
--    replying. Sorting in the client would be a rule anybody could forget;
--    a CHECK is one nothing can. It also forbids peer_a = peer_b, which is a
--    man writing to himself.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ It changes NO existing message and locks nobody out. Every current row
--      has peer_a NULL and stays exactly where it is.
-- ============================================================================

BEGIN;

-- ── §1. الطرفان ─────────────────────────────────────────────────────────
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS peer_a bigint REFERENCES public.adeels(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS peer_b bigint REFERENCES public.adeels(id) ON DELETE CASCADE;

-- ⚠ ON DELETE CASCADE, unlike receivables. A conversation between two men is
--   not a financial record: deleting an عديل who was never billed should not
--   be blocked by chat, and delete_adeel already refuses the moment he has a
--   receivable or a payment.

ALTER TABLE public.chat_messages DROP CONSTRAINT IF EXISTS ck_chat_shape;
ALTER TABLE public.chat_messages ADD CONSTRAINT ck_chat_shape CHECK (
  -- المجلس
  (thread_adeel_id IS NULL AND peer_a IS NULL AND peer_b IS NULL)
  -- خيط الإدارة
  OR (thread_adeel_id IS NOT NULL AND peer_a IS NULL AND peer_b IS NULL)
  -- ثنائية، ومرتّبة
  OR (thread_adeel_id IS NULL AND peer_a IS NOT NULL AND peer_b IS NOT NULL
      AND peer_a < peer_b)
);

CREATE INDEX IF NOT EXISTS ix_chat_pair
  ON public.chat_messages (peer_a, peer_b, id DESC)
  WHERE peer_a IS NOT NULL;


-- ── §2. من يقرأ ماذا ────────────────────────────────────────────────────
--
-- ⚠ THE المجلس CLAUSE HAD TO BE TIGHTENED, AND MISSING THAT WOULD HAVE BEEN
--   THE WHOLE BUG. The old policy admitted `thread_adeel_id IS NULL` as «the
--   general room» — and a direct message ALSO has thread_adeel_id NULL. Left
--   as it was, every private conversation in the association would have
--   appeared in المجلس for everyone, which is the exact opposite of what was
--   asked for and would have looked like a feature working.
--
-- ⚠ AND has_role(viewer) — WHICH IS THE ADMIN — DELIBERATELY DOES NOT REACH
--   THE THIRD CLAUSE. It still gives him every board thread, because that is
--   what those are for. It gives him nothing here. That is the association's
--   decision, in one line.
DROP POLICY IF EXISTS read_chat ON public.chat_messages;
CREATE POLICY read_chat ON public.chat_messages
  FOR SELECT TO authenticated
  USING (
    public.in_association()
    AND (
      (thread_adeel_id IS NULL AND peer_a IS NULL)
      OR (thread_adeel_id IS NOT NULL
          AND (thread_adeel_id = public.my_adeel_id()
               OR public.has_role('viewer'::app_role)))
      OR (peer_a IS NOT NULL
          AND public.my_adeel_id() IN (peer_a, peer_b))
    ));


-- ── §3. الإرسال ─────────────────────────────────────────────────────────
--
-- ⚠ THE OLD TWO-ARGUMENT VERSION IS DROPPED, NOT LEFT BESIDE THIS ONE.
--   PostgREST dispatches on the NAMED parameters a client sends, so both
--   overloads would be reachable — and a client sending p_body plus
--   p_thread_adeel_id would land on the old function, which knows nothing
--   about peers and would file a private message into المجلس. That is the
--   redeem_adeel_code trap, found the hard way three days ago.
DROP FUNCTION IF EXISTS public.send_chat_message(text, bigint);

CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_body            text,
  p_thread_adeel_id bigint DEFAULT NULL,
  p_to_adeel_id     bigint DEFAULT NULL
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

  IF v_body = '' THEN
    RAISE EXCEPTION 'الرسالة فارغة' USING ERRCODE = 'RUL18';
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
     thread_adeel_id, peer_a, peer_b)
  VALUES (auth.uid(), coalesce(v_name, '—'), v_adeel, v_role IS NOT NULL,
          v_body, p_thread_adeel_id, v_a, v_b)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id, 'authorName', v_name);
END $$;


-- ── §4. العرض يحمل الطرفين ──────────────────────────────────────────────
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
         m.peer_b          AS "peerB"
    FROM public.chat_messages m
    LEFT JOIN public.adeels ta ON ta.id = m.thread_adeel_id;

-- ⚠ THE GRANT IS RESTATED, AND IT IS NOT REDUNDANT. CREATE OR REPLACE keeps
--   a view ACL only while the view SURVIVES the statement. Drop it for any
--   reason — a CASCADE from a column, a rebuild, a hand-fix — and the
--   replacement comes back with NO grant at all, and every member gets
--   «permission denied for view v_chat_messages» with the chat simply blank.
--
--   Found by applying this patch to a database that had never held it, which
--   is the state it is actually FOR. And nothing would have caught it:
--   assert_views_security_invoker checks the option, not the privilege.
GRANT SELECT ON public.v_chat_messages TO authenticated;


-- ── §5. الحذف: صاحبها وحده ──────────────────────────────────────────────
--
-- ⚠ THE ADMIN EXCEPTION IS REMOVED FOR DIRECT MESSAGES, and this is the cost
--   of «خاصّة تماماً» made explicit rather than left implicit. He cannot READ
--   one, so he could only ever delete it by guessing an id — but a moderation
--   power that works blind is worse than none, and it would contradict the
--   promise the read policy makes. Board threads and المجلس keep the
--   exception exactly as they had it.
CREATE OR REPLACE FUNCTION public.delete_chat_message(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_msg   record;
  v_admin boolean := public.has_role('admin');
BEGIN
  IF NOT public.in_association() THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  SELECT * INTO v_msg FROM public.chat_messages WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الرسالة غير موجودة' USING ERRCODE = 'RUL18';
  END IF;

  IF v_msg.peer_a IS NOT NULL THEN
    IF v_msg.author_user_id <> auth.uid() THEN
      RAISE EXCEPTION 'لا يمكنك حذف رسالة غيرك' USING ERRCODE = 'RUL00';
    END IF;
  ELSIF v_msg.author_user_id <> auth.uid() AND NOT v_admin THEN
    RAISE EXCEPTION 'لا يمكنك حذف رسالة غيرك' USING ERRCODE = 'RUL00';
  END IF;

  IF v_msg.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'الرسالة محذوفة أصلاً' USING ERRCODE = 'RUL18';
  END IF;

  UPDATE public.chat_messages
     SET deleted_at = now(), deleted_by = auth.uid()
   WHERE id = p_id;

  PERFORM public.write_audit('chat.delete',
    format('حذف رسالة %s', p_id), p_id::text);

  RETURN jsonb_build_object('id', p_id);
END $$;


-- ── §6. صندوق المحادثات الثنائية ────────────────────────────────────────
--
-- ⚠ A FUNCTION, AND THE FIRST ATTEMPT WAS A SECURITY INVOKER VIEW THAT CAME
--   BACK EMPTY. It joined public.adeels for the other man's NAME — and a
--   member sees exactly one row there, his own (read_own_adeel). So the join
--   dropped every thread, and a man holding two messages was shown an empty
--   inbox. The policy was right, the messages were readable, and the screen
--   said nothing: a failure that reads as «the feature does not work» and is
--   in fact one JOIN.
--
-- ⚠ AND SECURITY DEFINER OPENS NO NEW DOOR HERE, which is why it is allowed.
--   api_call_directory already hands every member the name of every other
--   bound member so he can call him. Naming the man he is already talking to
--   is strictly less than that.
--
-- ⚠ THE PAIR TEST IS THE WHOLE GATE: my_adeel_id() must be one of the two. An
--   admin holds no adeel_id — my_role() returns NULL the moment one is set —
--   so he matches no pair and gets an empty list, which is the same answer the
--   read policy gives him, derived from the same fact rather than a second
--   rule that could drift from it.
DROP VIEW IF EXISTS public.v_direct_threads;

CREATE OR REPLACE FUNCTION public.api_direct_threads() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $dt$
DECLARE
  v_me bigint := public.my_adeel_id();
  v    jsonb;
BEGIN
  IF NOT public.in_association() THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;
  IF v_me IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'adeelId',   t.other,
           'adeelName', a.full_name,
           'adeelCode', a.adeel_code,
           'messages',  t.messages,
           'lastBody',  CASE WHEN t.last_deleted THEN '' ELSE t.last_body END,
           'lastMine',  t.last_mine,
           'lastId',    t.last_id,
           'lastAt',    to_char(t.last_at AT TIME ZONE 'UTC',
                                'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
         ORDER BY t.last_at DESC), '[]'::jsonb) INTO v
    FROM (
      SELECT DISTINCT ON (m.peer_a, m.peer_b)
             CASE WHEN m.peer_a = v_me THEN m.peer_b ELSE m.peer_a END AS other,
             count(*) OVER (PARTITION BY m.peer_a, m.peer_b) AS messages,
             m.body                        AS last_body,
             m.deleted_at IS NOT NULL      AS last_deleted,
             m.author_user_id = auth.uid() AS last_mine,
             m.created_at                  AS last_at,
             m.id                          AS last_id
        FROM public.chat_messages m
       WHERE v_me IN (m.peer_a, m.peer_b)
       ORDER BY m.peer_a, m.peer_b, m.id DESC) t
    JOIN public.adeels a ON a.id = t.other;

  RETURN v;
END $dt$;


-- ── §7. القائمة، ثم كنس الصلاحيات ───────────────────────────────────────
--
-- ⚠ REQUIRED HERE, unlike the last three patches: §3 DROPPED a function and
--   created one with a NEW signature, so it has no ACL to keep and Postgres
--   materialises the built-in default — EXECUTE TO PUBLIC.
--   assert_no_public_execute would roll this whole patch back naming it.
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    'my_adeel_id()',
    'request_device_id()',
    'members_held(bigint)',
    'register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_adeel(bigint,jsonb)',
    'delete_adeel(bigint)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    'purge_financial_data(text)',
    'purge_all_data(text)',
    'issue_adeel_code(bigint)',
    'redeem_adeel_code(text,text)',
    'register_disbursement(numeric,disbursement_kind,pay_method,bigint,expense_category,text,text,text,text,text,text,date)',
    'cancel_disbursement(bigint,text)',
    'in_association()',
    'delete_chat_message(bigint)',
    'period_label(text)',
    'adeel_json(bigint)',
    'api_adeel_detail(bigint)',
    'api_adeel_statement(bigint)',
    'api_adeel_aid(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_closable_periods()',
    'api_settings()',
    'api_me()',
    'api_touch_login()',
    'api_association_finance()',
    'api_aid_others(bigint)',
    'api_member_value(bigint)',
    'api_ice_servers()',
    'answer_call(bigint)',
    'end_call(bigint,boolean)',
    'send_signal(bigint,text,jsonb,uuid)',
    'join_call(bigint)',
    'heartbeat_call(bigint)',
    'leave_call(bigint)',
    'revoke_all_adeel_access(text)',
    'may_join_call(bigint,bigint,uuid)',
    'start_call(bigint,bigint)',
    'api_call_directory()',
    'send_chat_message(text,bigint,bigint)',
    'api_direct_threads()'
  ]::text[]
$$;

-- ⚠ AFTER THE LAST CREATE, and that is the whole of the rule.
DO $lockdown$
DECLARE
  r       record;
  v_allow text[] := public.client_callable_functions();
  v_sig   text;
BEGIN
  FOR r IN
    SELECT p.oid, p.oid::regprocedure::text AS full_sig
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
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_api_functions_callable();
SELECT public.assert_two_doors_only();

COMMIT;
