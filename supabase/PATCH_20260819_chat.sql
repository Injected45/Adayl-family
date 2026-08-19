-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-19.  مجلس العدايل: دردشة داخل التطبيق.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  WHAT THIS DOES
--    Adds one room that every member of the association is in — staff and
--    عدايل alike — with the words themselves living in Postgres and nothing
--    else. No third-party service, no extra cost, nothing to configure in the
--    dashboard.
--
--    • chat_messages, plus v_chat_messages for reading it and v_chat_threads
--      for the board's inbox of private conversations;
--    • in_association(), the one place "is this person in the association"
--      is answered — staff by role, an عديل by his binding AND his handset;
--    • send_chat_message / delete_chat_message, the only two writes;
--    • chat_messages joins purge_all_data's TRUNCATE list (see the ⚠ below).
--
--
--  ⚠ TWO ROOMS, ONE TABLE. `thread_adeel_id` decides which: NULL is المجلس, the
--    open room everyone reads; an id is that man's private thread with الإدارة.
--    The private side has exactly two sides — the man it is about, and any
--    approved staff account — and the clause that walls one member off from
--    another is `has_role('viewer')`, which is FALSE for a bound portal account
--    because my_role() returns NULL while adeel_id is set.
--
--    الإدارة is an INSTITUTION here, never a named officer: a question is
--    answered by whoever is on duty rather than waiting for one man to return.
--
--    ⚠ ANY approved staff account reads the private threads, not only an admin.
--      They already read his name, his telephone, every dinar he owes and every
--      receipt he was given, so a message saying «متى أستطيع الدفع» is less
--      sensitive than what the register hands them before he types it — and a
--      stricter rule would leave his question unanswered whenever one person is
--      away. Tightening it is one word (`has_role('admin')`) if the association
--      ever wants that trade instead.
--  ⚠ IT IS THE FIRST TABLE BOTH KINDS OF ACCOUNT REACH, and that is the whole
--    design problem. Every other table belongs to one audience: staff read the
--    association through has_role(), an عديل reads himself through
--    my_adeel_id(), and my_role() returning NULL for a bound portal account is
--    what keeps the two apart. `read_chat` deliberately admits both. What it
--    still refuses is everyone else — a pending applicant, a suspended account,
--    and an عديل on a handset that has not claimed his code. All three are
--    asserted from both sides in supabase/tests/46_chat.sql.
--
--  ⚠ THE PURGE CHANGES, and not optionally. chat_messages references adeels, and
--    Postgres refuses to TRUNCATE a table that a surviving table points at — so
--    without adding it to purge_all_data, «مسح كل البيانات» would FAIL with a
--    foreign-key error rather than merely leave messages behind. It is NOT added
--    to purge_financial_data: wiping the figures is not a reason to erase what
--    people said to each other.
--
--  ⚠ NO MONEY IS TOUCHED. This patch adds one table and three functions and
--    replaces one function body (purge_all_data, by one line in its TRUNCATE
--    list). It reads no receivable, writes no payment and changes no view that
--    any figure comes from.
--
--  ── WHY IT IS NOT REALTIME ──────────────────────────────────────────────────
--  Supabase Realtime is the reflex and it would silently exclude the people the
--  feature is for. my_adeel_id() reads the `x-device-id` REQUEST HEADER — one
--  handset per عديل — and a websocket carries no headers, so a postgres_changes
--  subscription evaluated for a portal member matches no policy and delivers him
--  nothing. Staff would watch messages appear live while every member sat on a
--  screen that never moved, with the REST reads working perfectly: a failure
--  invisible to anyone testing with a staff account.
--
--  The app polls instead — `id > lastSeen` against an index, while the screen is
--  open and not otherwise. Nothing here needs enabling in the dashboard.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes. Safe to run twice.
--    Requires PATCH_20260818c_member_holdings.sql — check with
--    supabase/WHICH_STATE.sql.
-- ============================================================================

BEGIN;

-- == 0. The prerequisite, stated rather than assumed =========================
DO $prereq$
BEGIN
  IF to_regprocedure('public.members_held(bigint)') IS NULL THEN
    RAISE EXCEPTION
      'PATCH_20260818c_member_holdings.sql has not been applied here. Apply the 18/08 patches first — see supabase/WHICH_STATE.sql.';
  END IF;
END $prereq$;

-- == 1. The room ============================================================

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

CREATE TABLE IF NOT EXISTS public.chat_messages (
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
CREATE INDEX IF NOT EXISTS ix_chat_thread ON public.chat_messages (thread_adeel_id, id DESC);
CREATE INDEX IF NOT EXISTS ix_chat_id     ON public.chat_messages (id DESC);
-- Rate limiting counts one author's recent messages; without this it is a scan
-- of the whole room on every single send.
CREATE INDEX IF NOT EXISTS ix_chat_author ON public.chat_messages (author_user_id, created_at DESC);

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

-- == 2. The wider purge takes the room with it =============================
-- One line added to its TRUNCATE list. See the ⚠ in the header: without it
-- «مسح كل البيانات» fails outright rather than leaving messages behind.
CREATE OR REPLACE FUNCTION public.purge_all_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv   bigint;
  v_pay    bigint;
  v_alloc  bigint;
  v_cash   bigint;
  v_audit  bigint;
  v_adeels bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- Distinct from purge_financial_data's phrase ON PURPOSE. See above.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح كل البيانات' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  SELECT count(*) INTO v_recv   FROM public.receivables;
  SELECT count(*) INTO v_pay    FROM public.payments;
  SELECT count(*) INTO v_alloc  FROM public.payment_allocations;
  SELECT count(*) INTO v_cash   FROM public.cash_movements;
  SELECT count(*) INTO v_audit  FROM public.audit_log;
  SELECT count(*) INTO v_adeels FROM public.adeels;

  -- ── Why adeels is DELETEd while the five financial tables are TRUNCATEd ────
  -- profiles.adeel_id references adeels, and TRUNCATE refuses whenever ANY table
  -- outside its list carries a foreign key into one being truncated — the
  -- constraint's existence is what it checks, not whether rows remain. So
  -- emptying profiles first does not help: it still dies with 0A000 "cannot
  -- truncate a table referenced in a foreign key constraint". Listing profiles
  -- would delete the association's own staff accounts, and CASCADE would do the
  -- same silently.
  --
  -- DELETE has no such rule, and adeels carries no refuse_delete trigger — that
  -- guard is on the financial tables, which keep their TRUNCATE. The identity is
  -- then restarted by hand, because that is the part RESTART IDENTITY was doing
  -- and the reason the next عديل must be A-0001.
  --
  -- ORDER MATTERS, and not for the reason it looks like. The truncate comes
  -- FIRST because receivables.created_by references profiles ON DELETE SET NULL,
  -- and that SET NULL is an UPDATE which trg_recv_snapshot_immutable rejects
  -- (created_by is a snapshot column). Deleting profiles while any receivable
  -- survives would therefore abort the whole purge with RUL05. Emptying the
  -- financial tables first leaves nothing for the cascade to touch.
  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivables,
           public.closed_periods,
           public.disbursements,
           -- ⚠ AND THE CHAT, which is not optional here: chat_messages
           --   references adeels, and Postgres refuses to TRUNCATE a table that
           --   a surviving table points at — so leaving this out does not make
           --   the purge incomplete, it makes it FAIL. The room also has to go
           --   on its own merits: every portal profile is deleted below, so what
           --   would remain is a conversation whose speakers no longer exist.
           --
           --   It is NOT in purge_financial_data. Wiping the figures is not a
           --   reason to erase what people said to each other.
           public.chat_messages,
           public.audit_log
    RESTART IDENTITY;

  -- Portal accounts go entirely: their عديل is being erased, so leaving the
  -- profile would leave a dangling scope and my_adeel_id() would answer with a
  -- dead id. auth.users survives, so the same person can sign in again and redeem
  -- a fresh code later.
  DELETE FROM public.profiles WHERE adeel_id IS NOT NULL;

  DELETE FROM public.adeels;

  ALTER TABLE public.adeels ALTER COLUMN id RESTART WITH 1;

  RETURN jsonb_build_object(
    'receivables',   v_recv,
    'payments',      v_pay,
    'allocations',   v_alloc,
    'cashMovements', v_cash,
    'auditEntries',  v_audit,
    'adeels',        v_adeels);
END $$;

-- == 3. The allow-list, and the lockdown sweep =============================
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

-- == 4. Re-run the lockdown sweep ===========================================
-- Byte-for-byte the loop from 20260811091200_function_lockdown.sql, which runs
-- LAST on a full apply. A patch gets no such pass, and api_adeel_aid is created
-- FRESH here — so Postgres materialises the built-in default ACL (EXECUTE to
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


-- == 4. Confirmation ========================================================
-- Read-only. Every row must say true.
SELECT 'الغرفة موجودة' AS "الفحص",
       (to_regclass('public.chat_messages') IS NOT NULL) AS "النتيجة"
UNION ALL SELECT 'وتُقرأ من خلال عرض',
       (to_regclass('public.v_chat_messages') IS NOT NULL)
-- The identity question the whole feature turns on, in ONE place.
UNION ALL SELECT 'وسؤال «هل هذا الشخص من الجمعية» في مكان واحد',
       (to_regprocedure('public.in_association()') IS NOT NULL)
UNION ALL SELECT 'والكتابة عبر دالتين لا غير',
       (to_regprocedure('public.send_chat_message(text,bigint)') IS NOT NULL
        AND to_regprocedure('public.delete_chat_message(bigint)') IS NOT NULL)
UNION ALL SELECT 'وكلها على قائمة الأذونات',
       ('in_association()' = ANY (public.client_callable_functions())
        AND 'send_chat_message(text,bigint)' = ANY (public.client_callable_functions())
        AND 'delete_chat_message(bigint)' = ANY (public.client_callable_functions()))
UNION ALL SELECT 'ولا تُنفَّذ من anon',
       NOT has_function_privilege('anon', 'public.send_chat_message(text,bigint)', 'EXECUTE')
-- ⚠ THE RULE THAT MATTERS. The room is the first table both kinds of account
--   reach, and the way it fails is silent in both directions: too narrow and an
--   عديل sees an empty room, too wide and a pending applicant is sitting in the
--   association's private conversation.
UNION ALL SELECT 'وللغرفة سياسة قراءة واحدة تشمل الإدارة والعديل معاً',
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='chat_messages'
                  AND policyname='read_chat' AND cmd='SELECT'
                  AND qual LIKE '%in_association%')
-- And no write policy of any kind, so PostgREST cannot insert whatever a client
-- sends — which is where the rate limit and the name snapshot live.
UNION ALL SELECT 'ولا سياسة كتابة البتة',
       NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='chat_messages'
                      AND cmd <> 'SELECT')
UNION ALL SELECT 'ولا امتياز كتابة على الجدول',
       NOT has_table_privilege('authenticated', 'public.chat_messages', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.chat_messages', 'UPDATE')
        AND NOT has_table_privilege('authenticated', 'public.chat_messages', 'DELETE')
-- ⚠ AND THE WALL BETWEEN TWO MEMBERS. `has_role('viewer')` is the clause that
--   stops a member reading another member's private thread — it is FALSE for a
--   bound portal account because my_role() returns NULL while adeel_id is set.
--   Loosened to anything weaker and every member reads everyone's private
--   messages with nothing on any screen looking different.
UNION ALL SELECT 'والخاص محجوب بين المشتركين',
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='chat_messages'
                  AND policyname='read_chat'
                  AND qual LIKE '%my_adeel_id%' AND qual LIKE '%has_role%')
UNION ALL SELECT 'وفهرس الإدارة للمحادثات موجود',
       (to_regclass('public.v_chat_threads') IS NOT NULL)
-- ⚠ AND THE PURGE. Without this, «مسح كل البيانات» does not merely leave
--   messages behind — it FAILS, because chat_messages references adeels and
--   Postgres refuses to truncate a table a survivor points at.
UNION ALL SELECT 'ومسح كل البيانات يشمل الغرفة',
       (SELECT pg_get_functiondef(p.oid) LIKE '%chat_messages%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='purge_all_data')
-- ...and the FINANCIAL purge does not. Wiping the figures is not a reason to
-- erase what people said to each other.
UNION ALL SELECT 'ومسح البيانات المالية لا يمسّها',
       (SELECT pg_get_functiondef(p.oid) NOT LIKE '%chat_messages%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='purge_financial_data')
-- ⚠ AND NOTHING FINANCIAL MOVED. This patch reads no receivable and writes no
--   payment; these are the totals it must have left exactly as it found them.
UNION ALL SELECT 'ولم يتغيّر أي رقم مالي',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
           AND "outstanding"::numeric = (SELECT coalesce(sum(balance), 0)
                                           FROM public.receivables
                                          WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 5. The four guards =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
