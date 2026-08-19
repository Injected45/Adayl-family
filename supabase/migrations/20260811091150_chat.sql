-- ═════════════════════════════════════════════════════════════════════════════
-- مجلس العدايل — one room, and everyone in the association is in it.
--
-- The association has two disjoint ways in: staff, who hold a role, and عدايل,
-- who hold a portal binding and no role at all. Every other table in this schema
-- is reached by exactly one of them. This is the first that is reached by BOTH,
-- and that is the whole design problem.
--
-- ── WHY THE AUTHOR'S NAME IS SNAPSHOT ONTO THE ROW ──────────────────────────
-- The obvious shape is `author_user_id` alone and a join to profiles (and to
-- adeels) at read time. It cannot work, and the way it fails is the dangerous
-- kind: `v_chat_messages` is SECURITY INVOKER, an عديل's RLS on `profiles` shows
-- him his OWN row and nothing else, so the join would return his name beside his
-- messages and NULL beside everyone else's. Not an error — a chat where every
-- other person is nameless, on a screen with nothing to say why.
--
-- The alternative was a SECURITY DEFINER read function. Snapshotting is better
-- than both: with the name on the row, reading the chat needs no access to the
-- register or the staff list AT ALL. A member sees the names of people who
-- spoke, and there is no path from this table to anything else about them.
--
-- The cost, stated: renaming a man does not rename him on messages he has
-- already sent. That is the same rule disbursements.payee_name follows, and for
-- a record of who said what it is arguably the right one.
--
-- ── WHY IT IS NOT REALTIME ──────────────────────────────────────────────────
-- Supabase Realtime would be the reflex, and for THIS app it silently excludes
-- the people the feature is for. `my_adeel_id()` reads the `x-device-id`
-- REQUEST HEADER — one handset per عديل, see profiles — and a websocket carries
-- no such header. So a postgres_changes subscription evaluated for a portal
-- member returns NULL from that function, matches no policy, and delivers him
-- nothing. Staff would see messages appear live; every عديل would sit on a
-- screen that never updates, with the REST reads working perfectly. A failure
-- that is invisible in testing by anyone holding a staff account.
--
-- The client therefore polls: `id > lastSeen` against ix_chat_id, while the
-- screen is open and not otherwise. On an association of tens of people that is
-- a few rows a second at worst, it costs nothing on the free tier, needs no
-- dashboard configuration, and behaves identically for both kinds of account.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── Who may be in the room ──────────────────────────────────────────────────
-- Staff OR a bound عديل, and nobody else — not a pending account, not a
-- suspended one, not an عديل whose code was reissued and whose handset has not
-- claimed it again. Both halves of that come free: my_role() and my_adeel_id()
-- each already require `status = 'approved'`, and my_adeel_id() additionally
-- requires the device to match.
--
-- One function rather than the same OR written into four policies and two
-- function bodies. It is the identity question this whole feature turns on, and
-- six copies of it is six chances to fix five.
--
-- SECURITY DEFINER because the two functions it calls are, and for the same
-- reason: it must read `profiles` rows the caller cannot.
CREATE OR REPLACE FUNCTION public.in_association() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT public.my_role() IS NOT NULL OR public.my_adeel_id() IS NOT NULL
$$;

CREATE TABLE public.chat_messages (
  id              bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  -- WHO, for the rules. Never displayed and never joined to at read time; it
  -- exists so a man can delete his own message and so the trail can name him.
  author_user_id  uuid        NOT NULL REFERENCES public.profiles(id)
                                ON DELETE CASCADE,

  -- WHO, for the reader. A snapshot — see the note above.
  author_name     text        NOT NULL,

  -- ⚠ THE FOREIGN KEY IS LOAD-BEARING, and not for integrity.
  --   purge_all_data TRUNCATEs `adeels`, and Postgres refuses to truncate a
  --   table referenced from one that is not in the same statement. So this
  --   constraint makes it IMPOSSIBLE to add the chat and forget the purge: the
  --   omission fails loudly the first time someone wipes the register, rather
  --   than leaving messages behind pointing at people who no longer exist.
  --   Same argument the disbursements entry in that TRUNCATE list makes.
  author_adeel_id bigint      REFERENCES public.adeels(id) ON DELETE SET NULL,

  -- Whether it came from the board. A snapshot too: a treasurer who is later
  -- demoted did speak as staff at the time, and rewriting that would misreport
  -- what the room saw.
  from_staff      boolean     NOT NULL,

  -- ── WHICH ROOM: NULL is المجلس, an id is that man's private thread ────────
  -- One column rather than a second table, and the saving is not the table —
  -- it is that the rate limit, the name snapshot, the deletion rule, the
  -- tombstone and the poll are all written once and apply to both. A separate
  -- private_messages table would have needed every one of them again, and the
  -- second copy is where they drift.
  --
  -- The thread is with الإدارة as an INSTITUTION, never with a named officer.
  -- A member writes one message and whoever is on duty answers it; addressing a
  -- person would mean his question goes unanswered while that person is away,
  -- which for an association of a few staff is most of the time.
  --
  -- ⚠ CASCADE, unlike author_adeel_id's SET NULL. A thread is ABOUT him: with
  --   the man gone there is no conversation left, only two halves of one that
  --   nobody can answer. delete_adeel already refuses anyone with a financial
  --   record, so this only ever fires on a mistyped entry.
  thread_adeel_id bigint      REFERENCES public.adeels(id) ON DELETE CASCADE,

  body            text        NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),

  -- ── Deletion EMPTIES the text, it does not merely flag it ─────────────────
  -- The row stays (there is a tombstone in the room, so a gap in a conversation
  -- is visible rather than silent), and the words are gone from the database
  -- entirely. Keeping text that no policy will ever return is a liability with
  -- no reader: even an admin cannot see it through v_chat_messages, so storing
  -- it protects nobody and exposes everybody.
  --
  -- What survives is the ACT, in the audit trail: who deleted whose message and
  -- when. Rule 12 records what was done; it was never meant to archive what was
  -- said.
  deleted_at      timestamptz,
  deleted_by      uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,

  -- The length cap is a real limit, not tidiness: with the anon key public,
  -- anything unbounded is an invitation to fill the free tier's disk from a
  -- phone. 1000 characters is longer than anyone types into a chat box.
  CONSTRAINT ck_chat_body CHECK (
    char_length(body) <= 1000
    AND (deleted_at IS NOT NULL OR btrim(body) <> '')),
  -- Both halves of a deletion or neither, so "deleted" is never ambiguous.
  CONSTRAINT ck_chat_deleted CHECK ((deleted_at IS NULL) = (deleted_by IS NULL))
);

-- The room is read newest-first and polled with `id > :lastSeen`. Both are this
-- index.
-- The public room and each private thread are read as separate lists, so the
-- thread is the leading column: without it every poll of المجلس walks the
-- private messages too.
CREATE INDEX ix_chat_thread ON public.chat_messages (thread_adeel_id, id DESC);
CREATE INDEX ix_chat_id     ON public.chat_messages (id DESC);
-- Rate limiting counts one author's recent messages; without this it is a scan
-- of the whole room on every single send.
CREATE INDEX ix_chat_author ON public.chat_messages (author_user_id, created_at DESC);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

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

-- ── The room, as the app reads it ───────────────────────────────────────────
CREATE VIEW public.v_chat_messages WITH (security_invoker = on) AS
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
-- POST /chat.
--
-- The only write, and the reason there is no INSERT policy: three things have
-- to happen together and only one of them is about the row being written.
--
-- p_thread_adeel_id decides WHICH room: NULL is المجلس, an id is that man's
-- private thread with الإدارة. The two are one function because everything
-- around the destination — the length cap, the rate limit, the name snapshot —
-- is identical, and a second function would be a second copy of all of it.
-- ═════════════════════════════════════════════════════════════════════════════
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
CREATE VIEW public.v_chat_threads WITH (security_invoker = on) AS
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
