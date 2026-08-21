-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (e).  المرحلة الثانية: مكالمة المجلس.
--
--  WHAT THIS ADDS
--    A group voice call in المجلس — everyone in the association on one line,
--    started from the same handset button, still with no server and still
--    asking nothing of the association but running this file.
--
--  ⚠ AND IT CONTRADICTS WHAT WAS WRITTEN IN docs/VOICE_CALLS.md, which said a
--    group call needs an SFU. That was right about VIDEO and wrong about this
--    association. A mesh means every phone sends its own audio to every other
--    one, and the arithmetic decides it:
--
--        Opus voice          ≈ 32 kbps per stream
--        5 in a call         → 4 up + 4 down  = 128 kbps up
--        8 in a call         → 7 up + 7 down  = 224 kbps up
--
--    A 2 Mbps phone carries the first comfortably. Video would be twenty times
--    those figures, which is where the SFU argument actually comes from — and
--    the association asked for صوتي.
--
--  ⚠ SO THE CAP IS THE DESIGN, and it is a SETTING rather than a constant.
--    call_max_participants starts at 6. If calls start breaking up when the
--    sixth man joins, that number comes down by one UPDATE; if the connection
--    turns out to carry more, it goes up the same way. Compiling it into the
--    APK would make a tuning decision into a release.
--
--  ⚠ THE SIGNALLING BECOMES PAIRWISE, and this is the part stage 1 could not
--    have. With two people, every signal on a call belongs to the other one and
--    a broadcast is exact. With four, an offer from A to B is read by C and D
--    as well — each sets it as ITS remote description, and the call collapses
--    in a way that looks like a network fault. call_signals therefore gains a
--    recipient, and it is NULLABLE so every stage-1 row and every stage-1
--    client keeps working untouched.
--
--  ⚠ AND WHO OFFERS WHOM IS DECIDED BY ARITHMETIC, NOT BY NEGOTIATION. The man
--    who joins LATER offers to everyone already in the room — «later» being a
--    larger participant id, which Postgres already hands out in order. Both
--    sides compute the same answer from the same two numbers, so there is no
--    round of «you go first» to lose, and no glare: two peers can never both
--    offer, because one id is always the larger.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ Requires PATCH_20260821d_voice_calls.sql. It refuses without it.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION
      'لا يوجد جدول مكالمات. طبّق supabase/PATCH_20260821d_voice_calls.sql أولاً.';
  END IF;
END
$prereq$;


-- ── §1. سقف المشاركين ──────────────────────────────────────────────────────
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS call_max_participants integer NOT NULL DEFAULT 6;

ALTER TABLE public.association_settings
  DROP CONSTRAINT IF EXISTS ck_call_max_participants;
ALTER TABLE public.association_settings
  ADD CONSTRAINT ck_call_max_participants
  CHECK (call_max_participants BETWEEN 2 AND 12);


-- ── §2. من في المكالمة الآن ────────────────────────────────────────────────
--
-- ⚠ A ROW PER PERSON PER CALL, and `last_seen` is what makes it truthful. A
--   phone that loses signal mid-call never says it left — so «who is on this
--   call» cannot be «who has a row», it has to be «who has a row and was heard
--   from recently». Twenty seconds, and the view applies it, exactly as v_calls
--   expires a stale ring: nothing has to RUN for the answer to be right.
CREATE TABLE IF NOT EXISTS public.call_participants (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  call_id      bigint NOT NULL REFERENCES public.calls(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Snapshot, for the reason calls.caller_name is one: v_call_participants is
  -- SECURITY INVOKER and a member's RLS on profiles shows him his own row only,
  -- so a join at read time would name him and nobody else.
  display_name text NOT NULL,

  joined_at    timestamptz NOT NULL DEFAULT now(),
  last_seen    timestamptz NOT NULL DEFAULT now(),
  left_at      timestamptz,

  -- ⚠ ONE ROW PER PERSON PER CALL, so a man whose app restarted rejoins the
  --   same seat instead of appearing twice — and so the id that decides who
  --   offers whom stays stable across a reconnect.
  CONSTRAINT uq_call_participant UNIQUE (call_id, user_id)
);

CREATE INDEX IF NOT EXISTS ix_call_participants_live
  ON public.call_participants (call_id, id)
  WHERE left_at IS NULL;


-- ── §3. الإشارة تصير موجَّهة ───────────────────────────────────────────────
--
-- NULL means «to everyone on this call», which is what every stage-1 row is and
-- what a two-person call still uses. An id means «to this man only».
ALTER TABLE public.call_signals
  ADD COLUMN IF NOT EXISTS recipient_user_id uuid
    REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS ix_call_signals_to
  ON public.call_signals (call_id, recipient_user_id, id);


-- ── §4. من يرى ماذا ────────────────────────────────────────────────────────
ALTER TABLE public.call_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS read_call_participants ON public.call_participants;
CREATE POLICY read_call_participants ON public.call_participants
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.calls c
       WHERE c.id = call_participants.call_id
         AND public.in_association()
         AND (
           c.thread_adeel_id IS NULL
           OR c.thread_adeel_id = public.my_adeel_id()
           OR public.has_role('viewer')
         )
    )
  );

GRANT SELECT ON public.call_participants TO authenticated;


-- ── §5. القراءة ────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_call_participants
WITH (security_invoker = true) AS
  SELECT
    p.id                              AS "id",
    p.call_id                         AS "callId",
    p.user_id                         AS "userId",
    p.display_name                    AS "displayName",
    (p.user_id = auth.uid())          AS "mine",
    p.joined_at                       AS "joinedAt"
  FROM public.call_participants p
  -- ⚠ THE LIVENESS TEST IS HERE, so a client cannot forget it and cannot
  --   disagree with another client about who is on the call. A row whose owner
  --   has not been heard from in twenty seconds is simply not returned.
  WHERE p.left_at IS NULL
    AND p.last_seen >= now() - interval '20 seconds';

GRANT SELECT ON public.v_call_participants TO authenticated;


-- ── §6. الانضمام، النبض، المغادرة ──────────────────────────────────────────

-- ⚠ THE CAP IS CHECKED UNDER A LOCK. Without it, six people tapping «انضم» in
--   the same second each count five others and each join, and the seventh
--   handset is the one whose audio breaks up for everybody.
CREATE OR REPLACE FUNCTION public.join_call(p_call_id bigint)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_thread bigint;
  v_status text;
  v_name   text;
  v_max    integer;
  v_now    integer;
  v_id     bigint;
BEGIN
  SELECT c.thread_adeel_id, c.status INTO v_thread, v_status
    FROM public.calls c WHERE c.id = p_call_id;
  IF NOT FOUND OR NOT public.may_join_thread(v_thread) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;
  IF v_status NOT IN ('ترن', 'جارية') THEN
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

  SELECT coalesce(nullif(trim(p.display_name), ''), 'الإدارة') INTO v_name
    FROM public.profiles p WHERE p.id = auth.uid();

  -- ⚠ ON CONFLICT UPDATE, so a man whose app restarted takes back the SAME
  --   seat. A second row would give him a second id — and the id is what
  --   decides who offers whom, so his peers would all try to renegotiate with
  --   somebody who is already connected to them.
  INSERT INTO public.call_participants (call_id, user_id, display_name)
  VALUES (p_call_id, auth.uid(), coalesce(v_name, 'الإدارة'))
  ON CONFLICT (call_id, user_id) DO UPDATE
     SET last_seen = now(), left_at = NULL
  RETURNING id INTO v_id;

  -- The first answer is what turns a ringing call into a live one, whether it
  -- came through answer_call on a private thread or through joining المجلس.
  UPDATE public.calls
     SET status = 'جارية', answered_at = coalesce(answered_at, now())
   WHERE id = p_call_id AND status = 'ترن';

  RETURN v_id;
END
$$;


-- «I am still here.» Called on the same clock the client polls on.
CREATE OR REPLACE FUNCTION public.heartbeat_call(p_call_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.call_participants
     SET last_seen = now()
   WHERE call_id = p_call_id AND user_id = auth.uid() AND left_at IS NULL;
END
$$;


-- ⚠ LEAVING IS NOT ENDING. In المجلس the call goes on without him; it ends
--   when the LAST person leaves, which is decided here rather than by whoever
--   happens to press the red button. A group call that hung up on everyone
--   because one man left would be unusable.
CREATE OR REPLACE FUNCTION public.leave_call(p_call_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_left integer;
BEGIN
  UPDATE public.call_participants
     SET left_at = now()
   WHERE call_id = p_call_id AND user_id = auth.uid() AND left_at IS NULL;

  SELECT count(*) INTO v_left
    FROM public.call_participants p
   WHERE p.call_id = p_call_id
     AND p.left_at IS NULL
     AND p.last_seen >= now() - interval '20 seconds';

  IF v_left = 0 THEN
    UPDATE public.calls
       SET status = 'انتهت', ended_at = now()
     WHERE id = p_call_id AND status IN ('ترن', 'جارية');
  END IF;
END
$$;


-- ── §7. الإشارة الموجَّهة ───────────────────────────────────────────────────
--
-- ⚠ DROP AND CREATE, because the SIGNATURE changes and Postgres has no other
--   way. The consequence is the one PATCH_20260820b was rolled back for: a
--   function created FRESH has no ACL to keep, so it materialises the built-in
--   default of EXECUTE TO PUBLIC. §9 is what takes that away again, and it is
--   why §9 comes after every CREATE in this file.
--
--   `p_to` defaults to NULL, so a stage-1 client calling send_signal with three
--   arguments still resolves to this function and still broadcasts.
DROP FUNCTION IF EXISTS public.send_signal(bigint, text, jsonb);

CREATE OR REPLACE FUNCTION public.send_signal(
  p_call_id bigint,
  p_kind    text,
  p_payload jsonb,
  p_to      uuid DEFAULT NULL
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
  IF v_status NOT IN ('ترن', 'جارية') THEN
    RAISE EXCEPTION 'المكالمة انتهت.' USING ERRCODE = 'RUL18';
  END IF;

  INSERT INTO public.call_signals
    (call_id, sender_user_id, kind, payload, recipient_user_id)
  VALUES (p_call_id, auth.uid(), p_kind, p_payload, p_to)
  RETURNING id INTO v_id;

  RETURN v_id;
END
$$;


-- The recipient has to be readable, or a client cannot tell which offer is
-- addressed to it. Appending a column is the one change CREATE OR REPLACE VIEW
-- permits — the existing columns keep their names, types and order.
CREATE OR REPLACE VIEW public.v_call_signals
WITH (security_invoker = true) AS
  SELECT
    s.id                                   AS "id",
    s.call_id                              AS "callId",
    s.kind                                 AS "kind",
    s.payload                              AS "payload",
    (s.sender_user_id = auth.uid())        AS "mine",
    s.created_at                           AS "createdAt",
    s.sender_user_id                       AS "fromUserId",
    s.recipient_user_id                    AS "toUserId"
  FROM public.call_signals s;

GRANT SELECT ON public.v_call_signals TO authenticated;


-- ── §8. المسح ──────────────────────────────────────────────────────────────
--
-- ⚠ REQUIRED, NOT TIDY. call_participants references calls, so omitting it
--   does not leave stale rows behind — it makes purge_all_data FAIL.
--
-- ⚠ AND THE BODY IS LIFTED FROM THE PREVIOUS PATCH, NOT RETYPED. Writing it
--   from memory was tried in this same session and produced the wrong
--   signature, the wrong profile columns and the wrong return shape — which
--   would have replaced a working purge with one that cannot run.

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
           -- ⚠ ADDED BY PATCH_20260821e: call_participants references
           --   calls, so it is under the same 0A000 rule as the rest.
           public.call_participants,
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


-- ── §9. قائمة الدوال، ثم كنس الصلاحيات ─────────────────────────────────────
--
-- ⚠ A PATCH GETS NO FREE LOCKDOWN PASS, and this one needs it more than most:
--   §7 DROPPED a function and CREATEd it fresh, so it has no ACL to keep and
--   Postgres materialises the built-in default of EXECUTE TO PUBLIC. The
--   sweep below takes that away — and it sits after every CREATE in this
--   file, which is the rule PATCH_20260820b was rolled back for breaking.

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
    -- ⚠ FOUR ARGUMENTS NOW. PATCH_20260821e DROPPED the three-argument
    --   version to add a recipient, and a dropped function left on this
    --   list fails assert_function_grants — it is asserted EXACT in both
    --   directions. p_to defaults to NULL, so a caller passing three
    --   arguments still resolves here and still broadcasts.
    'send_signal(bigint,text,jsonb,uuid)',
    -- مكالمة المجلس: مقعد، ونبض، ومغادرة.
    'join_call(bigint)',
    'heartbeat_call(bigint)',
    'leave_call(bigint)'
  ]::text[]
$$;

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


-- ── §10. الحُرّاس ───────────────────────────────────────────────────────────
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
