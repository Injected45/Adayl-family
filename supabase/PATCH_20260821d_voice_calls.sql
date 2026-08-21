-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (d).  المرحلة الأولى من الاتصال الصوتي.
--
--  WHAT THIS ADDS
--    A one-to-one voice call inside the private thread — «الإدارة ↔ المشترك» —
--    carried peer-to-peer between the two handsets by WebRTC, with the whole
--    handshake going through this database.
--
--  ⚠ AND IT ASKS NOTHING OF THE ASSOCIATION BUT RUNNING THIS FILE, which is
--    the constraint it was designed under and the reason it looks the way it
--    does. The earlier design in docs/VOICE_CALLS.md wanted a LiveKit account
--    and an Edge Function; both are gone. What replaced them:
--
--      • the MEDIA is peer-to-peer. Two people need no SFU — an SFU is what a
--        GROUP call needs, and that is stage 2.
--      • the SIGNALLING is a table and a poll, exactly like the chat. Not
--        Realtime: my_adeel_id() reads the x-device-id REQUEST HEADER and a
--        websocket carries none, so a subscription evaluated for a portal
--        member matches no policy and delivers him nothing. Staff would be
--        able to call each other while no عديل could be reached — invisible to
--        anyone testing with a staff account.
--      • the ICE SERVERS live in THIS DATABASE, in association_settings. Not
--        hardcoded in the APK: the day a STUN or TURN host disappears, the fix
--        is one UPDATE in the SQL Editor rather than a new APK on eight
--        handsets. See §1.
--
--  ⚠ WHO IS CALLED, AND WHY IT IS NOT ONE NAMED OFFICER. A private thread has
--    two sides: the member, and الإدارة as an institution. So a call raised in
--    thread X rings for member X and for every staff account, and whoever is
--    free answers. That is not a shortcut — it is the same rule the private
--    CHAT already runs on, chosen so a question is answered by whoever is on
--    duty instead of waiting for one man to come back.
--
--  ⚠ A RINGING CALL EXPIRES IN THE VIEW, NOT ON A TIMER. v_calls reports a
--    «ترن» older than sixty seconds as «فائتة». A phone that died mid-call, an
--    app killed from the task switcher, a battery that ran out — none of them
--    can leave a handset ringing forever, because nothing has to run for the
--    expiry to happen. A cron job or a client-side cancel would each be a
--    thing that can fail to run.
--
--  WHAT IT DELIBERATELY DOES NOT DO
--    No group call (stage 2 — it needs an SFU, and an SFU is a server).
--    No ringing while the app is CLOSED (that needs a push service).
--    No video. No recording. No call log in the audit trail — rule 12 exists
--    so a FIGURE can be reconstructed, and conversations would bury it.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ Run supabase/PATCH_20260821c_aid_others_ledger.sql FIRST if it has not
--      been run — this file does not depend on it, but running them in order
--      keeps WHICH_STATE.sql able to report a single coherent level.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.chat_messages') IS NULL THEN
    RAISE EXCEPTION
      'لا يوجد جدول محادثات. طبّق supabase/PATCH_20260819_chat.sql أولاً.';
  END IF;
  IF to_regprocedure('public.in_association()') IS NULL THEN
    RAISE EXCEPTION
      'الدالة in_association غير موجودة. طبّق حزمة المحادثات أولاً.';
  END IF;
END
$prereq$;


-- ── §1. خوادم ICE، في قاعدة البيانات لا في التطبيق ─────────────────────────
--
-- Two phones on Libyan mobile data are both behind carrier-grade NAT and
-- usually cannot open a direct path to each other. STUN tells each what its
-- public address is — enough on wifi, often not enough on mobile. TURN is a
-- relay both can reach, and it carries the audio.
--
-- ⚠ THE DEFAULTS BELOW NEED NO ACCOUNT AND NO KEY, which is why they are the
--   defaults. The STUN hosts are Google's public ones. The TURN entry is
--   Open Relay, published for exactly this use with a fixed public credential.
--
-- ⚠ AND A PUBLIC TURN IS A BORROWED THING. If calls start failing to connect
--   on mobile data while working on wifi, TURN is what has stopped working,
--   and the fix is this column — not a code change:
--
--     UPDATE public.association_settings
--        SET ice_servers = '[{"urls":"stun:stun.l.google.com:19302"},
--                            {"urls":"turn:YOUR-HOST:3478",
--                             "username":"…","credential":"…"}]'::jsonb
--      WHERE id = 1;
--
--   That is the whole upgrade path to a paid TURN, and it is one statement.
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS ice_servers jsonb NOT NULL DEFAULT
    '[
      {"urls": "stun:stun.l.google.com:19302"},
      {"urls": "stun:stun1.l.google.com:19302"},
      {"urls": "turn:openrelay.metered.ca:80",
       "username": "openrelayproject", "credential": "openrelayproject"},
      {"urls": "turn:openrelay.metered.ca:443",
       "username": "openrelayproject", "credential": "openrelayproject"}
    ]'::jsonb;


-- ── §2. المكالمة ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.calls (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  -- NULL is المجلس, an id is that man's private thread — the SAME
  -- discriminator chat_messages uses, so «which room» is one concept in this
  -- schema rather than two. Stage 1 only ever writes a non-null id; the column
  -- is nullable now so stage 2 needs no migration of live rows.
  thread_adeel_id bigint REFERENCES public.adeels(id) ON DELETE CASCADE,

  caller_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- ⚠ SNAPSHOT, for the reason chat_messages.author_name is one. v_calls is
  --   SECURITY INVOKER and a member's RLS on profiles shows him his own row
  --   only — so a join at read time would put his name on every call and NULL
  --   on everyone else's. With the name on the row, showing «فلان يتصل» needs
  --   no access to the staff list at all.
  caller_name     text NOT NULL,

  answered_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL,

  status          text NOT NULL DEFAULT 'ترن',
  started_at      timestamptz NOT NULL DEFAULT now(),
  answered_at     timestamptz,
  ended_at        timestamptz,

  CONSTRAINT ck_call_status CHECK (
    status IN ('ترن', 'جارية', 'انتهت', 'مرفوضة', 'فائتة')
  )
);

-- The one question every poll asks: «is anything live in this thread».
CREATE INDEX IF NOT EXISTS ix_calls_live
  ON public.calls (thread_adeel_id, id DESC)
  WHERE status IN ('ترن', 'جارية');


-- ── §3. الإشارة ─────────────────────────────────────────────────────────────
--
-- The SDP offer, the answer, and the ICE candidates that follow. Rows, polled
-- by id — the cheapest question this schema can be asked, and the same shape
-- the chat uses.
CREATE TABLE IF NOT EXISTS public.call_signals (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  call_id        bigint NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
  sender_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind           text NOT NULL,
  payload        jsonb NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ck_signal_kind CHECK (kind IN ('offer', 'answer', 'ice'))
);

CREATE INDEX IF NOT EXISTS ix_call_signals_call
  ON public.call_signals (call_id, id);


-- ── §4. التاريخ من ساعة الخادم ─────────────────────────────────────────────
--
-- Same rule as disb_stamp_time() and pay_stamp_time(): the client proposes no
-- time. Here it matters for the sixty-second expiry — a handset whose clock is
-- a week behind would otherwise raise a call that is «missed» the instant it
-- is created, or one that rings forever.
CREATE OR REPLACE FUNCTION public.call_stamp_time()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.started_at := now();
  ELSIF NEW.started_at IS DISTINCT FROM OLD.started_at THEN
    RAISE EXCEPTION 'لا يُعدَّل وقت بدء المكالمة بعد تسجيلها.'
      USING ERRCODE = 'RUL17';
  END IF;
  RETURN NEW;
END
$$;

DROP TRIGGER IF EXISTS trg_call_stamp_time ON public.calls;
CREATE TRIGGER trg_call_stamp_time
  BEFORE INSERT OR UPDATE ON public.calls
  FOR EACH ROW EXECUTE FUNCTION public.call_stamp_time();


-- ── §5. من يرى ماذا ────────────────────────────────────────────────────────
--
-- ⚠ read_calls IS read_chat, clause for clause. Not «similar to»: if a man may
--   not read the thread, he may not see that it is ringing. Writing a second,
--   independent rule here would be a second implementation of the wall between
--   two members — free to disagree with the one that decides everything else.
ALTER TABLE public.calls          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.call_signals   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS read_calls ON public.calls;
CREATE POLICY read_calls ON public.calls
  FOR SELECT TO authenticated
  USING (
    public.in_association()
    AND (
      thread_adeel_id IS NULL
      OR thread_adeel_id = public.my_adeel_id()
      OR public.has_role('viewer')
    )
  );

-- A signal belongs to whoever may see the call it belongs to. Expressed as a
-- subquery against calls rather than repeated, so the two can never drift.
DROP POLICY IF EXISTS read_call_signals ON public.call_signals;
CREATE POLICY read_call_signals ON public.call_signals
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.calls c
       WHERE c.id = call_signals.call_id
         AND public.in_association()
         AND (
           c.thread_adeel_id IS NULL
           OR c.thread_adeel_id = public.my_adeel_id()
           OR public.has_role('viewer')
         )
    )
  );

-- ⚠ SELECT ON THE BASE TABLES, and it is not a hole — the views are SECURITY
--   INVOKER, so Postgres reads these AS THE CALLER and without this every view
--   raises «permission denied» for everyone. What decides who sees what is the
--   two policies above. No INSERT, UPDATE or DELETE is granted here or
--   anywhere, so the four functions below stay the only way a row is written.
GRANT SELECT ON public.calls        TO authenticated;
GRANT SELECT ON public.call_signals TO authenticated;


-- ── §6. القراءة ────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_calls
WITH (security_invoker = true) AS
  SELECT
    c.id                                   AS "id",
    c.thread_adeel_id                      AS "threadAdeelId",
    c.caller_name                          AS "callerName",
    (c.caller_user_id = auth.uid())        AS "mine",
    -- ⚠ THE EXPIRY LIVES HERE. A «ترن» older than sixty seconds IS a missed
    --   call, whatever the row says — so a client that died between the invite
    --   and the answer cannot leave a phone ringing. Nothing has to run for
    --   this to be true, which is the whole point of computing it in the view.
    CASE
      WHEN c.status = 'ترن'
       AND c.started_at < now() - interval '60 seconds' THEN 'فائتة'
      ELSE c.status
    END                                    AS "status",
    c.started_at                           AS "startedAt",
    c.answered_at                          AS "answeredAt",
    c.ended_at                             AS "endedAt"
  FROM public.calls c;

CREATE OR REPLACE VIEW public.v_call_signals
WITH (security_invoker = true) AS
  SELECT
    s.id                                   AS "id",
    s.call_id                              AS "callId",
    s.kind                                 AS "kind",
    s.payload                              AS "payload",
    (s.sender_user_id = auth.uid())        AS "mine",
    s.created_at                           AS "createdAt"
  FROM public.call_signals s;

GRANT SELECT ON public.v_calls        TO authenticated;
GRANT SELECT ON public.v_call_signals TO authenticated;


-- ── §7. الكتابة، عبر الدوال وحدها ──────────────────────────────────────────

-- The ICE list, for a caller who is actually inside the association.
--
-- SECURITY DEFINER on purpose: association_settings is not readable by a
-- portal member, and pointing him at it to fetch a STUN host would mean
-- widening a policy on the row that holds the monthly fee. This hands back one
-- jsonb array and nothing else.
CREATE OR REPLACE FUNCTION public.api_ice_servers()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.in_association() THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;
  SELECT s.ice_servers INTO v FROM public.association_settings s WHERE s.id = 1;
  RETURN coalesce(v, '[]'::jsonb);
END
$$;


-- May this caller be a party to a call in this thread? The same three-way test
-- read_calls makes, in a form the write path can call.
CREATE OR REPLACE FUNCTION public.may_join_thread(p_thread_adeel_id bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.in_association()
     AND (
       p_thread_adeel_id IS NULL
       OR p_thread_adeel_id = public.my_adeel_id()
       OR public.has_role('viewer')
     );
$$;


-- ⚠ ONE LIVE CALL PER THREAD, enforced here rather than by an index, because
--   «live» is two statuses and a partial unique index cannot express «at most
--   one row whose status is either of these». Two people pressing the handset
--   at the same instant would otherwise each raise a call and each hear the
--   other ringing while neither was connected.
CREATE OR REPLACE FUNCTION public.start_call(p_thread_adeel_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id      bigint;
  v_name    text;
  v_live    bigint;
BEGIN
  IF NOT public.may_join_thread(p_thread_adeel_id) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  -- ⚠ THE LOCK IS ON THE THREAD, taken before the check. Without it the two
  --   simultaneous callers both SELECT «nothing live» and both INSERT.
  PERFORM pg_advisory_xact_lock(
    hashtext('call:' || coalesce(p_thread_adeel_id::text, 'hall'))
  );

  SELECT c.id INTO v_live
    FROM public.calls c
   WHERE c.thread_adeel_id IS NOT DISTINCT FROM p_thread_adeel_id
     AND (
       c.status = 'جارية'
       OR (c.status = 'ترن' AND c.started_at >= now() - interval '60 seconds')
     )
   ORDER BY c.id DESC
   LIMIT 1;

  IF v_live IS NOT NULL THEN
    -- Not an error the caller should be shown as a failure: somebody is
    -- already on this line, and joining that call is what he meant.
    RETURN v_live;
  END IF;

  SELECT coalesce(nullif(trim(p.display_name), ''), 'الإدارة') INTO v_name
    FROM public.profiles p WHERE p.id = auth.uid();

  INSERT INTO public.calls (thread_adeel_id, caller_user_id, caller_name)
  VALUES (p_thread_adeel_id, auth.uid(), coalesce(v_name, 'الإدارة'))
  RETURNING id INTO v_id;

  RETURN v_id;
END
$$;


-- ⚠ EXACTLY ONE ANSWERER. The UPDATE carries `status = 'ترن'` in its WHERE, so
--   the second person to press «رد» updates zero rows and is told the call was
--   already taken — rather than both being told they answered and one of them
--   sitting on a connection nobody is at the other end of.
CREATE OR REPLACE FUNCTION public.answer_call(p_call_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_thread bigint;
BEGIN
  SELECT c.thread_adeel_id INTO v_thread
    FROM public.calls c WHERE c.id = p_call_id;
  IF NOT FOUND OR NOT public.may_join_thread(v_thread) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  UPDATE public.calls
     SET status = 'جارية', answered_at = now(), answered_by = auth.uid()
   WHERE id = p_call_id
     AND status = 'ترن'
     AND started_at >= now() - interval '60 seconds';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'المكالمة لم تعد متاحة.' USING ERRCODE = 'RUL18';
  END IF;
END
$$;


-- Ending and declining are the same act with a different word for it, so they
-- are one function: a call the other side never answered ended too.
CREATE OR REPLACE FUNCTION public.end_call(
  p_call_id  bigint,
  p_declined boolean DEFAULT false
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_thread bigint;
BEGIN
  SELECT c.thread_adeel_id INTO v_thread
    FROM public.calls c WHERE c.id = p_call_id;
  IF NOT FOUND OR NOT public.may_join_thread(v_thread) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  UPDATE public.calls
     SET status   = CASE WHEN p_declined AND status = 'ترن'
                         THEN 'مرفوضة' ELSE 'انتهت' END,
         ended_at = now()
   WHERE id = p_call_id
     AND status IN ('ترن', 'جارية');
END
$$;


-- One offer, one answer, and as many ICE candidates as the connection needs.
CREATE OR REPLACE FUNCTION public.send_signal(
  p_call_id bigint,
  p_kind    text,
  p_payload jsonb
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_thread bigint;
  v_status text;
  v_id     bigint;
BEGIN
  SELECT c.thread_adeel_id, c.status INTO v_thread, v_status
    FROM public.calls c WHERE c.id = p_call_id;
  IF NOT FOUND OR NOT public.may_join_thread(v_thread) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  -- ⚠ A FINISHED CALL TAKES NO MORE SIGNALS. Without this an app that lost
  --   the network goes on posting candidates into a call that ended, and the
  --   table grows with rows nothing will ever read.
  IF v_status NOT IN ('ترن', 'جارية') THEN
    RAISE EXCEPTION 'المكالمة انتهت.' USING ERRCODE = 'RUL18';
  END IF;

  INSERT INTO public.call_signals (call_id, sender_user_id, kind, payload)
  VALUES (p_call_id, auth.uid(), p_kind, p_payload)
  RETURNING id INTO v_id;

  RETURN v_id;
END
$$;


-- ── §8. المسح ──────────────────────────────────────────────────────────────
--
-- ⚠ NOT OPTIONAL, AND NOT A TIDINESS CHOICE. calls references adeels, and
--   Postgres refuses to TRUNCATE a table that a surviving table points at — so
--   omitting these two does not leave stale calls behind, it makes
--   purge_all_data FAIL. Exactly the constraint chat_messages is under.
--
--   And like the chat, they are NOT in purge_financial_data: wiping the
--   figures is not a reason to erase that people spoke.
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
           -- ⚠ AND THE CALLS, under exactly the same constraint: calls
           --   references adeels and call_signals references calls, so
           --   leaving them out does not leave stale rows behind — it
           --   makes this TRUNCATE die with 0A000 and the whole purge
           --   FAIL. call_signals is listed first because it points at
           --   calls.
           --
           --   Not in purge_financial_data either: wiping the figures is
           --   not a reason to erase that people spoke to each other.
           public.call_signals,
           public.calls,
           public.audit_log
    RESTART IDENTITY;

  -- Portal accounts go entirely: their عديل is being erased, so leaving the
  -- profile would leave a dangling scope and my_adeel_id() would answer with a
  -- dead id.
  DELETE FROM public.profiles WHERE adeel_id IS NOT NULL;

  -- ⚠ AND IMMEDIATELY PUT BACK A BLANK ONE, which the previous version did
  --   not — its comment claimed «auth.users survives, so the same person can
  --   sign in again», and that is false in the one way that matters.
  --
  --   trg_auth_user_created fires AFTER INSERT ON auth.users and on nothing
  --   else. Signing in INSERTS NOTHING: the account already exists. So a man
  --   whose profile was deleted signs in successfully, lands with no row, no
  --   role and no approval, and the app tells him «لا يوجد سجل لهذا الحساب —
  --   لن تنجح المحاولة مرة أخرى». It is right: nothing he can do will fix it,
  --   because the only thing that creates a profile is an event that has
  --   already happened once and cannot happen twice.
  --
  --   This is the same failure the 16/08 reset caused for the whole
  --   association, and 20260811090100_profiles.sql carries the same backfill
  --   for the same reason. A purge that strands every member is not a purge,
  --   it is a lockout with a confirmation phrase.
  --
  -- ⚠ viewer/pending, GRANTING NOTHING. That is exactly the state a brand new
  --   sign-in lands in, and it is what /pending is for: he types the access
  --   code the admin issues him, redeem_adeel_code binds him to his عديل, and
  --   the guard trigger allows that one pending → approved self-change.
  INSERT INTO public.profiles (id, email, display_name, picture_url)
  SELECT u.id,
         coalesce(u.email, ''),
         coalesce(u.raw_user_meta_data ->> 'full_name',
                  u.raw_user_meta_data ->> 'name',
                  split_part(coalesce(u.email, ''), '@', 1)),
         u.raw_user_meta_data ->> 'avatar_url'
    FROM auth.users u
   WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
  ON CONFLICT DO NOTHING;

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


-- ── §9. قائمة الدوال المسموح استدعاؤها ─────────────────────────────────────
--
-- ⚠ A PATCH GETS NO FREE LOCKDOWN PASS. On a full apply the sweep runs last
--   and normalises every grant; here it has to be carried in by hand — and the
--   allow-list is asserted EXACT, so a function created without being listed
--   is unreachable and one listed but ungranted fails the migration.
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
    'api_association_finance()',
    -- ── نظام الاتصال الصوتي — المرحلة الأولى ─────────────────────────────
    -- Reads the ICE list for a caller who is inside the association. SECURITY
    -- DEFINER, because association_settings is not readable by a portal member
    -- and widening a policy on the row that holds the monthly fee just to hand
    -- out a STUN host would be the wrong trade.
    'api_ice_servers()',
    -- The three-way test read_calls makes, in a form the write path can call.
    -- Granted because the four writes call it — and because a client may ask
    -- it directly to decide whether to draw the handset at all.
    'may_join_thread(bigint)',
    -- The four writes. Each checks may_join_thread() itself, so granting them
    -- to authenticated is safe: an outsider calling any of them gets RUL00.
    'start_call(bigint)',
    'answer_call(bigint)',
    'end_call(bigint,boolean)',
    'send_signal(bigint,text,jsonb)'
  ]::text[]
$$;


-- ── §10. كنس الصلاحيات، بعد آخر CREATE ─────────────────────────────────────
--
-- ⚠ AFTER THE LAST CREATE, AND THAT IS THE WHOLE OF THE RULE. PATCH_20260820b
--   put this in the middle and created a trigger function below it; the sweep
--   never saw it, it kept the built-in default of EXECUTE TO PUBLIC, and
--   assert_no_public_execute() rolled the entire patch back naming a function
--   that looked innocent. call_stamp_time() above is exactly such a trigger
--   function — Postgres calls it, never a client, so it is not on the
--   allow-list and it needs this sweep.
-- ⚠ THIS SWEEP IS LIFTED VERBATIM FROM
--   supabase/migrations/20260811091200_function_lockdown.sql, and the reason
--   is written in its own comment below: a hand-written version using
--   pg_get_function_identity_arguments() matches NOTHING except the
--   zero-argument functions, because that form carries PARAMETER NAMES
--   («p_period character») while the allow-list is written in the type-only
--   form regprocedure renders («generate_period(character)»).
--
--   That bug was found once, fixed, and documented there — and then written
--   again from memory into this patch, which is how it reached the
--   association: assert_function_grants() named thirty functions as
--   ungranted and rolled the whole patch back. The guard was right.
--
--   The rule this cost is now in the memory file and in
--   docs/MEMBER_TO_MEMBER_CALLS.md: lift SQL from its source, never retype
--   it. There is no compiler here to catch the difference.
DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    -- regprocedure, NOT pg_get_function_identity_arguments(): the latter includes
    -- PARAMETER NAMES ("p_period character"), while regprocedure renders the
    -- type-only form the allow-list is written in ("generate_period(character)").
    -- Comparing against identity arguments silently matched nothing except the
    -- zero-argument functions, so fourteen were left ungranted.
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       -- Extension functions are not ours. A project with pgcrypto or uuid-ossp
       -- in `public` would otherwise lose gen_random_uuid() and friends.
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    -- PUBLIC *and* the named roles. Supabase's default privileges grant to the
    -- names, so a PUBLIC-only revoke is a no-op on a real project.
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.full_sig);

    -- Normalise: strip spaces, and drop a leading `public.` in case the role's
    -- search_path does not include public and regprocedure qualifies the name.
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      -- service_role too: it is a trusted server-side context, and the phase-4
      -- legacy import needs the write functions.
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;


-- ── §11. الحُرّاس ───────────────────────────────────────────────────────────
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
