-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-20.  ترقية غرفة المجلس إلى الغرفتين.
--
--  WHAT THIS FIXES, AND HOW IT SHOWED ITSELF
--    On a handset the room opened and said «حدث خطأ غير متوقع [42703]», with
--    «قاعدة البيانات لا تطابق هذا الإصدار من التطبيق [PGRST202]» beneath it.
--
--    42703 is undefined_column and PGRST202 is function-not-found, and together
--    they name the state exactly: this project holds the FIRST shape of
--    chat_messages — one open room — while the app on the phone was built for
--    the second, which added a private thread with الإدارة beside المجلس.
--
--      • chat_messages has no thread_adeel_id, so every read that asks which
--        room a message is in fails with 42703;
--      • send_chat_message takes ONE argument here and the app calls it with
--        two, so PostgREST finds no such function and answers PGRST202.
--
--  ⚠ RE-RUNNING PATCH_20260819_chat.sql DOES NOT FIX IT, which is the whole
--    reason this file exists. That patch creates the table with
--    CREATE TABLE IF NOT EXISTS — on a project that already has the table it
--    skips the statement entirely, column and all, and then dies at
--    CREATE INDEX ... (thread_adeel_id) with the same 42703 it was meant to
--    cure. IF NOT EXISTS protects a table from being replaced; it does not
--    migrate one.
--
--  WHAT IT DOES
--    §1  ADD COLUMN IF NOT EXISTS thread_adeel_id, with its FK and its index.
--    §2  Rebuilds read_chat so a private thread is readable by its two sides.
--    §3  DROPS and recreates v_chat_messages and v_chat_threads. Dropped rather
--        than replaced: CREATE OR REPLACE VIEW cannot change a column list
--        except by appending, and rebuilding from one definition is what keeps
--        this file honest about what the view now is.
--    §4  Replaces send_chat_message with the two-argument form and
--        delete_chat_message with the current body.
--    §5  Re-runs the lockdown sweep, which is NOT optional here: §4 drops a
--        function, a dropped function loses its ACL, and a function created
--        fresh gets EXECUTE to PUBLIC by default with anon layered on top.
--
--  ⚠ NO MESSAGE IS LOST AND NO MONEY IS TOUCHED. Every existing row keeps its
--    text, its author and its timestamp, and gets thread_adeel_id = NULL —
--    which is المجلس, where all of them were sent. This patch reads no
--    receivable, writes no payment and changes no view any figure comes from.
--
--  SAFE ON EITHER STATE. On a project that already has the two rooms every
--  statement is a no-op or an identical replacement, so running it after
--  PATCH_20260819_chat.sql changes nothing. Run it twice if unsure.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes.
-- ============================================================================

BEGIN;

-- == 0. The prerequisite ====================================================
DO $prereq$
BEGIN
  IF to_regclass('public.chat_messages') IS NULL THEN
    RAISE EXCEPTION
      'لا توجد غرفة أصلاً: طبّق supabase/PATCH_20260819_chat.sql أولاً — راجع supabase/WHICH_STATE.sql.';
  END IF;
END $prereq$;

-- == 1. The column the second room turns on =================================
-- ON DELETE CASCADE, matching the table's own definition: a man removed from
-- the register takes his private conversation with him. المجلس is untouched by
-- that — those rows carry NULL and belong to nobody in particular.
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS thread_adeel_id bigint
  REFERENCES public.adeels(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS ix_chat_thread
  ON public.chat_messages (thread_adeel_id, id DESC);

-- == 2. Who reads which room ================================================
-- ── Read: the room for everyone, and each private thread for its two sides ──
-- المجلس (thread_adeel_id IS NULL) is deliberately NOT scoped per person. It is
-- one room; a chat where each reader sees a different subset is not a chat.
--
-- A PRIVATE thread has exactly two sides, and the OR below is each of them:
--
--   • the man it is about — `thread_adeel_id = my_adeel_id()`. NULL for staff,
--     and NULL for an عديل on an unrecognised handset, so neither matches here
--     by accident;
--   • الإدارة — `has_role('viewer')`, which is FALSE for a bound portal account
--     because my_role() returns NULL while adeel_id is set. That one clause is
--     what stops a member reading another member's private thread, and it costs
--     nothing extra: it is the same function every staff policy in this schema
--     already goes through.
--
-- ⚠ WHY ANY STAFF AND NOT JUST admin. Every approved staff account already
--   reads his name, his telephone, every dinar he owes and every receipt he was
--   given. A message saying «متى أستطيع الدفع» is less sensitive than what the
--   register hands them before he types it, so a stricter rule here would
--   protect nothing while leaving his question unanswered whenever one person
--   is away. Tightening it is one word — `has_role('admin')` — if the
--   association ever wants that trade instead.
DROP POLICY IF EXISTS read_chat ON public.chat_messages;
CREATE POLICY read_chat ON public.chat_messages
  FOR SELECT TO authenticated
  USING (
    public.in_association()
    AND (
      thread_adeel_id IS NULL
      OR thread_adeel_id = public.my_adeel_id()
      OR public.has_role('viewer')
    )
  );


-- ⚠ SELECT ON THE BASE TABLE, and it is not a hole. `v_chat_messages` is
--   SECURITY INVOKER, which means Postgres reads chat_messages AS THE CALLER —
--   so without this the view raises "permission denied" for everyone and the
--   room never opens. Every other base table in this schema is granted for the
--   same reason (see the block in 20260811090500_rls.sql); what decides who
--   sees what is read_chat above, and it is the same policy either way.
--
--   No INSERT, UPDATE or DELETE is granted, here or anywhere, so the two
--   functions remain the only way a row is written.
GRANT SELECT ON public.chat_messages TO authenticated;
-- No INSERT, UPDATE or DELETE policy exists, so `authenticated` cannot write a
-- message however it reaches PostgREST. Sending goes through send_chat_message,
-- which is where the rate limit and the identity snapshot live — a policy can
-- judge the row in front of it and cannot count what the author sent a minute
-- ago.


-- == 3. The two views, rebuilt ==============================================
-- DROPPED rather than replaced: the old v_chat_messages has no "threadAdeelId"
-- and no "threadName", and CREATE OR REPLACE VIEW may only APPEND to a column
-- list — which would work here by luck and would stop working the first time a
-- column moves. Rebuilding from the definition is the form that keeps working.
DROP VIEW IF EXISTS public.v_chat_threads;
DROP VIEW IF EXISTS public.v_chat_messages;


-- ── The room, as the app reads it ───────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_chat_messages WITH (security_invoker = on) AS
SELECT
  m.id                                   AS "id",
  m.author_name                          AS "authorName",
  m.author_adeel_id                      AS "authorAdeelId",
  m.from_staff                           AS "fromStaff",
  -- ⚠ A DELETED MESSAGE'S TEXT NEVER LEAVES THE DATABASE. The column is already
  --   emptied by delete_chat_message; this is the second lock on the same door,
  --   so a future path that forgot to blank it still cannot serve the words.
  CASE WHEN m.deleted_at IS NULL THEN m.body ELSE '' END AS "body",
  (m.deleted_at IS NOT NULL)             AS "deleted",
  -- Whose bubble sits on which side, and who may delete it. Computed here
  -- rather than sent as a raw uuid: the client has no business holding other
  -- people's user ids, and comparing them in Dart would be a second
  -- implementation of a permission.
  (m.author_user_id = auth.uid())        AS "mine",
  to_char(m.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                                         AS "createdAt",
  -- Which room. NULL is المجلس; an id is that man's private thread with الإدارة.
  m.thread_adeel_id                      AS "threadAdeelId",
  -- ── The thread's owner, JOINED rather than snapshot ──────────────────────
  -- The opposite choice from author_name above, and for a reason that is worth
  -- being exact about: the join is safe HERE precisely because read_chat only
  -- ever hands a reader rows whose thread he is a side of. A member sees NULL
  -- threads (no join) or his own (an adeels row read_own_adeel already gives
  -- him); staff read the register outright. There is no reader for whom this
  -- returns a name he could not otherwise obtain, and no reader for whom it
  -- silently returns NULL — which is the failure the author's name is
  -- snapshot to avoid.
  --
  -- Joined rather than snapshot because it is the INBOX heading on the board's
  -- screen: a corrected spelling should correct the heading, not leave the old
  -- one on a conversation that is still open.
  ta.full_name                           AS "threadName"
FROM public.chat_messages m
LEFT JOIN public.adeels ta ON ta.id = m.thread_adeel_id;

GRANT SELECT ON public.v_chat_messages TO authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- الرسائل الخاصة — the board's inbox, one row per conversation.
--
-- Staff only, and by the same clause as everything else: `has_role('viewer')`
-- is FALSE for a bound portal account, so an عديل reading this view gets his
-- own thread and nothing else — the underlying policy is doing the work and
-- this view adds no rule of its own.
--
-- ⚠ A LIST OF THREADS, NOT OF MEMBERS. It is built from the messages, so a man
--   who has never written appears nowhere. That is deliberate: an inbox listing
--   every عديل on the register with «لا رسائل» beside him is a register, and
--   the association already has one. Starting a conversation from the board's
--   side is done from HIS page, where the board is already looking at him.
--
-- The preview is the LAST message either side sent, which is what an inbox is
-- read for — «هل ردّوا عليّ» and «من ينتظر ردّاً» are the same question asked
-- from the two ends, and both are answered by that one row.
CREATE OR REPLACE VIEW public.v_chat_threads WITH (security_invoker = on) AS
SELECT
  t.thread_adeel_id                      AS "adeelId",
  a.full_name                            AS "adeelName",
  a.adeel_code                           AS "adeelCode",
  t.messages                             AS "messages",
  -- Emptied when the last message was deleted, exactly as the room does it: an
  -- inbox preview is a second place the words could leak from, and it must obey
  -- the same rule as the first.
  CASE WHEN t.last_deleted THEN '' ELSE t.last_body END AS "lastBody",
  t.last_from_staff                      AS "lastFromStaff",
  to_char(t.last_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                                         AS "lastAt"
FROM (
  SELECT DISTINCT ON (m.thread_adeel_id)
         m.thread_adeel_id,
         count(*) OVER (PARTITION BY m.thread_adeel_id) AS messages,
         m.body                                          AS last_body,
         (m.deleted_at IS NOT NULL)                      AS last_deleted,
         m.from_staff                                    AS last_from_staff,
         m.created_at                                    AS last_at
    FROM public.chat_messages m
   WHERE m.thread_adeel_id IS NOT NULL
   ORDER BY m.thread_adeel_id, m.id DESC
) t
JOIN public.adeels a ON a.id = t.thread_adeel_id
-- Newest conversation first: an inbox is worked from the top.
ORDER BY t.last_at DESC;

GRANT SELECT ON public.v_chat_threads TO authenticated;

-- == 4. The two writes ======================================================
--
-- p_thread_adeel_id decides WHICH room: NULL is المجلس, an id is that man's
-- private thread with الإدارة. The two are one function because everything
-- around the destination — the length cap, the rate limit, the name snapshot —
-- is identical, and a second function would be a second copy of all of it.
-- ═════════════════════════════════════════════════════════════════════════════
-- ⚠ DROP FIRST: the signature gained p_thread_adeel_id, and CREATE OR REPLACE
--   cannot change a parameter list. Dropping also drops the ACL, which is why
--   the lockdown sweep at the foot of this patch is not optional — a function
--   created fresh gets EXECUTE to PUBLIC by default.
DROP FUNCTION IF EXISTS public.send_chat_message(text);
CREATE OR REPLACE FUNCTION public.send_chat_message(
  p_body            text,
  p_thread_adeel_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_adeel  bigint := public.my_adeel_id();
  v_role   app_role := public.my_role();
  v_body   text := btrim(coalesce(p_body, ''));
  v_name   text;
  v_recent int;
  v_id     bigint;
BEGIN
  IF v_role IS NULL AND v_adeel IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  -- ── WHO MAY WRITE INTO A PRIVATE THREAD ───────────────────────────────────
  -- Its two sides and nobody else. A member may write into HIS OWN and only his
  -- own — `p_thread_adeel_id = v_adeel` — which is the clause that stops him
  -- addressing another member through a thread that is not his. Staff may write
  -- into any, because the board is the other side of every one of them.
  --
  -- Mirrored on the read side by read_chat. Both must agree: a gap between them
  -- is a message a man can send and then never see.
  IF p_thread_adeel_id IS NOT NULL THEN
    IF v_role IS NULL AND p_thread_adeel_id IS DISTINCT FROM v_adeel THEN
      RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
    END IF;
    -- Staff writing to a man who is not on the register would create a thread
    -- with nobody at the other end. The FK would refuse it anyway; this says so
    -- in words the app can show.
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

  -- ── The rate limit, which is not politeness ────────────────────────────────
  -- The anon key ships inside the APK and cannot be made secret. Any signed-in
  -- member can therefore call this in a loop from a script, and without a cap
  -- one person can fill the room — and the project's free storage — in minutes.
  -- Twenty a minute is far above anyone typing and far below anyone scripting.
  --
  -- Counted across BOTH rooms on purpose: the limit is on the author, and
  -- counting per-room would let one phone send twenty into المجلس and twenty
  -- more into a private thread in the same minute.
  SELECT count(*) INTO v_recent
    FROM public.chat_messages
   WHERE author_user_id = auth.uid()
     AND created_at > now() - interval '1 minute';
  IF v_recent >= 20 THEN
    RAISE EXCEPTION 'أرسلت رسائل كثيرة في وقت قصير، انتظر قليلاً'
      USING ERRCODE = 'RUL18';
  END IF;

  -- ── The name the association knows him by ─────────────────────────────────
  -- His REGISTER name, not the one Google gave the account. «أيمن صالح بلها» is
  -- who the room knows; "Ayman S." is who signed in, and they are frequently
  -- not the same string.
  IF v_adeel IS NOT NULL THEN
    SELECT a.full_name INTO v_name FROM public.adeels a WHERE a.id = v_adeel;
  END IF;
  IF v_name IS NULL OR btrim(v_name) = '' THEN
    SELECT nullif(btrim(p.display_name), '') INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;
  -- Last resort, and it never reads as blank: a nameless bubble in a room is
  -- worse than an ugly one.
  IF v_name IS NULL OR btrim(v_name) = '' THEN
    SELECT split_part(p.email, '@', 1) INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;

  INSERT INTO public.chat_messages
    (author_user_id, author_name, author_adeel_id, from_staff, body,
     thread_adeel_id)
  VALUES (auth.uid(), coalesce(v_name, '—'), v_adeel, v_role IS NOT NULL, v_body,
          p_thread_adeel_id)
  RETURNING id INTO v_id;

  -- No audit entry. Rule 12 exists so a FIGURE can be reconstructed from the
  -- trail; a room of conversation writing one line per message would bury the
  -- money it was built for. Deletion is audited, because that is an act on
  -- someone else's words.
  RETURN jsonb_build_object('id', v_id, 'authorName', v_name);
END $$;

-- ═════════════════════════════════════════════════════════════════════════════
-- DELETE /chat/:id — a man's own message, or any message if you are admin.
--
-- financeManager is deliberately NOT enough. Moderating what a member said is
-- not a financial act, and the association put the whole outgoing side of the
-- treasury a rung above finance for the same reason: some powers belong to the
-- board rather than to whoever handles money.
-- ═════════════════════════════════════════════════════════════════════════════
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

  IF v_msg.author_user_id <> auth.uid() AND NOT v_admin THEN
    RAISE EXCEPTION 'لا يمكنك حذف رسالة غيرك' USING ERRCODE = 'RUL00';
  END IF;

  -- Refused rather than ignored, exactly as cancel_payment refuses a second
  -- cancellation: a silent success on an already-deleted row would tell the
  -- caller something happened that did not.
  IF v_msg.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'الرسالة محذوفة أصلاً' USING ERRCODE = 'RUL18';
  END IF;

  UPDATE public.chat_messages
     SET deleted_at = now(),
         deleted_by = auth.uid(),
         -- The words go. See the column note.
         body       = ''
   WHERE id = p_id;

  -- The ACT is recorded, never the content. An admin reaching into the room and
  -- removing somebody else's words is precisely the kind of thing rule 12 was
  -- built to leave a mark of.
  PERFORM public.write_audit(
    'chat.delete',
    CASE WHEN v_msg.author_user_id = auth.uid()
         THEN format('حذف رسالته رقم %s', p_id)
         ELSE format('حذف رسالة %s رقم %s', v_msg.author_name, p_id)
    END,
    p_id::text);

  RETURN jsonb_build_object('id', p_id);
END $$;

-- == 5. The allow-list, and the lockdown sweep =============================
-- Three functions created FRESH here, so none has an ACL to keep: Postgres
-- materialises EXECUTE to PUBLIC and Supabase layers anon on top. The sweep
-- recomputes every grant from the list, which is what takes it back.
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    -- Role helpers. The RLS policies call these, so they must be executable by
    -- the caller whose policy is being evaluated. They leak nothing beyond that
    -- caller's own role.
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    -- Answers only for the caller's own عديل binding, and the عديل-scoped
    -- policies call it, so the caller whose policy is being evaluated must hold
    -- EXECUTE — otherwise every one of those policies ERRORS instead of denying,
    -- and the failure surfaces as "permission denied for function my_adeel_id"
    -- on screens that have nothing to do with the portal.
    'my_adeel_id()',
    -- Echoes the caller's own x-device-id header back. api_me() is SECURITY
    -- INVOKER and calls it, so the caller must hold EXECUTE or every launch
    -- fails with "permission denied for function request_device_id".
    'request_device_id()',
    -- عهد المشتركين. v_cash_summary is SECURITY INVOKER and calls it, so staff
    -- reading the treasury screen must hold EXECUTE or the whole view errors.
    -- It returns ONE aggregate and no row, no name and no receipt — and the
    -- figure it returns is already on that screen beside it.
    'members_held(bigint)',

    -- Writes. Each require_role()-gated, each one transaction.
    'register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_adeel(bigint,jsonb)',
    -- The only hard delete outside the purges, and it refuses any عديل who has
    -- ever been billed or has ever paid. Retiring someone with history is a
    -- status change, not a deletion.
    'delete_adeel(bigint)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    -- The two destructive ones. admin-only, and each refuses without its OWN
    -- typed phrase, so the phrase that clears the figures cannot clear the
    -- register. They are on the list because Settings calls them directly; the
    -- reason that is safe is the same reason the others are — the gate is inside
    -- the body, not in who can reach it.
    'purge_financial_data(text)',
    'purge_all_data(text)',

    -- The عديل portal. issue_ is admin-gated; redeem_ deliberately is NOT — it
    -- is the one write a signed-in stranger may call, because until he redeems a
    -- code he has no role and no binding, and the code itself is the
    -- authorisation. It refuses anyone who is already staff.
    'issue_adeel_code(bigint)',
    'redeem_adeel_code(text,text)',

    -- Money OUT. Both admin-gated inside their bodies; register_disbursement
    -- also refuses to spend past the treasury balance, which is rule 7 read
    -- backwards and the reason the fund cannot be overdrawn from a phone.
    'register_disbursement(numeric,disbursement_kind,pay_method,bigint,expense_category,text,text,text,text,text,text,date)',
    'cancel_disbursement(bigint,text)',
    -- The room. `in_association()` is called by read_chat, which is an RLS
    -- policy — so the caller whose policy is being evaluated must hold EXECUTE
    -- or the whole chat screen errors instead of being empty. It answers one
    -- boolean about the CALLER and nothing about anyone else.
    'in_association()',
    'send_chat_message(text,bigint)',
    'delete_chat_message(bigint)',

    -- Reads. STABLE and SECURITY INVOKER, so RLS still decides what they return.
    'period_label(text)',
    'adeel_json(bigint)',
    'api_adeel_detail(bigint)',
    'api_adeel_statement(bigint)',
    -- What the association GAVE him, beside what he owes it. SECURITY INVOKER,
    -- so staff read any man's and an عديل reads only his own — through
    -- read_own_disbursements, which is scoped on payee_adeel_id.
    'api_adeel_aid(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_closable_periods()',
    'api_settings()',
    'api_me()',
    'api_touch_login()',
    -- Aggregates only, and SECURITY DEFINER on purpose: an عديل's RLS on
    -- cash_movements is `adeel_id = my_adeel_id()`, so a SECURITY INVOKER
    -- version would show him HIS OWN four figures under headings that say
    -- "the association's" — a wrong answer he has no way to doubt. It returns
    -- no name, no receipt and no row, takes no argument, and writes nothing.
    'api_association_finance()'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- == 5b. Re-run the lockdown sweep ===========================================
-- Byte-for-byte the loop from 20260811091200_function_lockdown.sql, which runs
-- LAST on a full apply. A patch gets no such pass, and send_chat_message is
-- DROPPED and recreated here — so Postgres materialises the built-in default ACL (EXECUTE to
-- PUBLIC) and Supabase's ALTER DEFAULT PRIVILEGES layers `anon` on top.
-- assert_no_public_execute() would then roll this patch back with a message
-- naming the function rather than the missing REVOKE, which reads like a defect
-- in the file.
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


-- == 6. Confirmation ========================================================
-- Read-only. Every row must say true.
SELECT 'العمود thread_adeel_id موجود' AS "الفحص",
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='chat_messages'
                  AND column_name='thread_adeel_id') AS "النتيجة"
-- ⚠ THE TWO ERRORS FROM THE PHONE, ASSERTED AS THE ROWS THAT CURE THEM.
UNION ALL SELECT 'ودالة الإرسال تقبل مُعاملين (PGRST202)',
       (to_regprocedure('public.send_chat_message(text,bigint)') IS NOT NULL)
UNION ALL SELECT 'ولم تعد النسخة ذات المُعامل الواحد قائمة',
       (to_regprocedure('public.send_chat_message(text)') IS NULL)
UNION ALL SELECT 'والعرض يحمل عمود الغرفة (42703)',
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='v_chat_messages'
                  AND column_name='threadAdeelId')
UNION ALL SELECT 'وفهرس الإدارة للمحادثات موجود',
       (to_regclass('public.v_chat_threads') IS NOT NULL)
-- ⚠ AND THE WALL BETWEEN TWO MEMBERS. has_role('viewer') is what stops one
--   member reading another's private thread — it is FALSE for a bound portal
--   account because my_role() returns NULL while adeel_id is set.
UNION ALL SELECT 'والخاص محجوب بين المشتركين',
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='chat_messages'
                  AND policyname='read_chat'
                  AND qual LIKE '%my_adeel_id%' AND qual LIKE '%has_role%'
                  AND qual LIKE '%in_association%')
UNION ALL SELECT 'ولا سياسة كتابة البتة',
       NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='chat_messages'
                      AND cmd <> 'SELECT')
UNION ALL SELECT 'ولا تُنفَّذ من anon',
       NOT has_function_privilege('anon', 'public.send_chat_message(text,bigint)', 'EXECUTE')
-- ⚠ AND NO DELETED MESSAGE LEAKS ITS WORDS. The view is rebuilt in §3, and this
--   is the rule most easily lost in a rebuild: a tombstone must serve an empty
--   body however the SELECT is written.
UNION ALL SELECT 'ولا نصّ محذوف يظهر',
       NOT EXISTS (SELECT 1 FROM public.v_chat_messages
                    WHERE "deleted" AND "body" <> '')
-- ⚠ AND NOTHING FINANCIAL MOVED.
UNION ALL SELECT 'ولم يتغيّر أي رقم مالي',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
           AND "outstanding"::numeric = (SELECT coalesce(sum(balance), 0)
                                           FROM public.receivables
                                          WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 7. The four guards =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
