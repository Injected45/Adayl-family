-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-22.  الاتصال بين عديل وعديل.
--
--  WHAT THIS ADDS
--    A direct voice call from one عديل to another, using the same mesh, the
--    same signalling and the same expiries as the two rooms already do.
--
--  ⚠ THE SHAPE IS «OPEN»: any member may call any member, and the app shows
--    him a directory of names to pick from. docs/MEMBER_TO_MEMBER_CALLS.md
--    recommended the narrower «admin opens a line between two men», and this
--    goes the other way for a reason that document did not have in front of
--    it: **المجلس already shows every member every other member's name and
--    words.** A directory is not new exposure. What the association refused,
--    when it rejected «أسلاف للغير» by name, was MONEY against a name — and
--    that is untouched here.
--
--    The narrow shape would also have meant an admin pairing eight men who
--    speak daily, one pair at a time, before any of them could ring anybody.
--
--  ⚠ AND STAFF CANNOT SEE A PEER CALL. `read_calls` grants staff every
--    THREAD, because a private thread is with الإدارة as an institution. A
--    call between two members is with neither, so the staff branch is
--    deliberately absent from the peer clause below. This is the first row in
--    this schema that an admin is not a party to, and it is meant to be.
--
--  ── الشكل الثالث ──────────────────────────────────────────────────────────
--    thread_adeel_id IS NOT NULL              → محادثة خاصة مع الإدارة
--    thread NULL AND peer NULL                → المجلس
--    thread NULL AND peer IS NOT NULL         → عديل ← عديل   (جديد)
--
--    ck_call_shape refuses both at once, the way ck_disb_shape refuses a
--    collective voucher with a payee: a row that could be read two ways is
--    a row two policies will disagree about.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.calls') IS NULL THEN
    RAISE EXCEPTION 'لا يوجد جدول مكالمات. طبّق ملفات الاتصال أولاً.';
  END IF;
END
$prereq$;


-- ── §1. العمود الثالث ───────────────────────────────────────────────────
ALTER TABLE public.calls
  ADD COLUMN IF NOT EXISTS peer_adeel_id bigint
    REFERENCES public.adeels(id) ON DELETE CASCADE;

ALTER TABLE public.calls DROP CONSTRAINT IF EXISTS ck_call_shape;
ALTER TABLE public.calls
  ADD CONSTRAINT ck_call_shape
  CHECK (thread_adeel_id IS NULL OR peer_adeel_id IS NULL);

CREATE INDEX IF NOT EXISTS ix_calls_peer
  ON public.calls (peer_adeel_id, id DESC)
  WHERE status IN ('ترن', 'جارية');


-- ── §2. من يحقّ له أن يكون طرفاً ────────────────────────────────────────
--
-- ⚠ REPLACES may_join_thread(bigint). The signature has to change — a call
--   now has two possible addresses — and Postgres offers no other way than
--   DROP and CREATE. Everything that called the old one is replaced below,
--   and §7 sweeps the grants a fresh function does not inherit.
--
-- ⚠ p_caller IS WHAT MAKES A PEER CALL TWO-SIDED. The callee matches on
--   my_adeel_id(); the caller matches on being the man who raised it. Without
--   the second, a member could not read back his own outgoing call — he would
--   dial and then be refused sight of the row he had just written.
DROP FUNCTION IF EXISTS public.may_join_thread(bigint);

CREATE OR REPLACE FUNCTION public.may_join_call(
  p_thread bigint,
  p_peer   bigint,
  p_caller uuid DEFAULT NULL
)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.in_association()
     AND CASE
           WHEN p_peer IS NOT NULL THEN
             -- ⚠ NO STAFF BRANCH. A call between two members is not the
             --   association's to sit in.
             p_peer = public.my_adeel_id() OR p_caller = auth.uid()
           ELSE
             p_thread IS NULL
             OR p_thread = public.my_adeel_id()
             OR public.has_role('viewer')
         END;
$$;


-- ── §3. من يرى ماذا ────────────────────────────────────────────────────
DROP POLICY IF EXISTS read_calls ON public.calls;
CREATE POLICY read_calls ON public.calls
  FOR SELECT TO authenticated
  USING (
    public.in_association()
    AND CASE
          WHEN peer_adeel_id IS NOT NULL THEN
            peer_adeel_id = public.my_adeel_id()
            OR caller_user_id = auth.uid()
          ELSE
            thread_adeel_id IS NULL
            OR thread_adeel_id = public.my_adeel_id()
            OR public.has_role('viewer')
        END
  );

-- The signals and the seats follow the call, restated as a subquery so the
-- three cannot drift apart.
DROP POLICY IF EXISTS read_call_signals ON public.call_signals;
CREATE POLICY read_call_signals ON public.call_signals
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.calls c
             WHERE c.id = call_signals.call_id
               AND public.may_join_call(c.thread_adeel_id, c.peer_adeel_id,
                                        c.caller_user_id))
  );

DROP POLICY IF EXISTS read_call_participants ON public.call_participants;
CREATE POLICY read_call_participants ON public.call_participants
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.calls c
             WHERE c.id = call_participants.call_id
               AND public.may_join_call(c.thread_adeel_id, c.peer_adeel_id,
                                        c.caller_user_id))
  );


-- ── §4. القراءة ────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_calls
WITH (security_invoker = true) AS
  SELECT
    c.id                            AS "id",
    c.thread_adeel_id               AS "threadAdeelId",
    c.caller_name                   AS "callerName",
    (c.caller_user_id = auth.uid()) AS "mine",
    CASE
      WHEN c.status = 'ترن'
       AND c.started_at < now() - interval '60 seconds' THEN 'فائتة'
      WHEN c.status = 'جارية' AND NOT EXISTS (
             SELECT 1 FROM public.call_participants p
              WHERE p.call_id = c.id
                AND p.left_at IS NULL
                AND p.last_seen >= now() - interval '20 seconds'
           ) THEN 'انتهت'
      ELSE c.status
    END                             AS "status",
    c.started_at                    AS "startedAt",
    c.answered_at                   AS "answeredAt",
    c.ended_at                      AS "endedAt",
    c.peer_adeel_id                 AS "peerAdeelId"
  FROM public.calls c;

GRANT SELECT ON public.v_calls TO authenticated;


-- ── §5. دليل من يمكن الاتصال به ─────────────────────────────────────────
--
-- ⚠ NAMES AND CODES ONLY — no phone, no balance, no dues. The directory
--   exists to answer «من أتصل به», and every other column would be an answer
--   to a question it was not asked.
--
-- ⚠ SECURITY DEFINER, because a member has no read on `adeels` at all and
--   widening that policy to hand out a list would open the whole register.
--   in_association() is the gate, which is the same one the chat uses.
--
-- ⚠ AND HE IS NOT IN HIS OWN DIRECTORY. A row you can tap and ring yourself
--   with is a bug wearing the shape of a feature.
CREATE OR REPLACE FUNCTION public.api_call_directory()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.in_association() THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'adeelId', a.id,
           'name',    a.full_name,
           'code',    a.adeel_code)
         ORDER BY a.adeel_code), '[]'::jsonb) INTO v
    FROM public.adeels a
   WHERE a.id IS DISTINCT FROM public.my_adeel_id()
     -- Only men who can actually answer: a portal account, bound to a
     -- handset. Listing a man with no app is offering a call that rings in
     -- an empty room.
     AND EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.adeel_id = a.id
                    AND p.device_id IS NOT NULL);

  RETURN v;
END $$;


-- ── §6. الكتابة ────────────────────────────────────────────────────────
--
-- ⚠ start_call GAINS A SECOND ARGUMENT, so it too is DROP + CREATE. p_peer
--   defaults to NULL, so «call this thread» and «call المجلس» read exactly as
--   before.
DROP FUNCTION IF EXISTS public.start_call(bigint);

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

  SELECT coalesce(nullif(trim(p.display_name), ''), 'الإدارة') INTO v_name
    FROM public.profiles p WHERE p.id = auth.uid();

  INSERT INTO public.calls
    (thread_adeel_id, peer_adeel_id, caller_user_id, caller_name)
  VALUES (p_thread_adeel_id, p_peer_adeel_id, auth.uid(),
          coalesce(v_name, 'الإدارة'))
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;


-- The other three writes: same bodies, the new permission test.
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

  SELECT coalesce(nullif(trim(p.display_name), ''), 'الإدارة') INTO v_name
    FROM public.profiles p WHERE p.id = auth.uid();

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

CREATE OR REPLACE FUNCTION public.end_call(
  p_call_id  bigint,
  p_declined boolean DEFAULT false
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_c record;
BEGIN
  SELECT * INTO v_c FROM public.calls c WHERE c.id = p_call_id;
  IF NOT FOUND
     OR NOT public.may_join_call(v_c.thread_adeel_id, v_c.peer_adeel_id,
                                 v_c.caller_user_id) THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  UPDATE public.calls
     SET status   = CASE WHEN p_declined AND status = 'ترن'
                         THEN 'مرفوضة' ELSE 'انتهت' END,
         ended_at = now()
   WHERE id = p_call_id
     AND status IN ('ترن', 'جارية');
END $$;

CREATE OR REPLACE FUNCTION public.send_signal(
  p_call_id bigint,
  p_kind    text,
  p_payload jsonb,
  p_to      uuid DEFAULT NULL
)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_c  record;
  v_id bigint;
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

  INSERT INTO public.call_signals
    (call_id, sender_user_id, kind, payload, recipient_user_id)
  VALUES (p_call_id, auth.uid(), p_kind, p_payload, p_to)
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;


-- ── §7. القائمة ثم كنس الصلاحيات ────────────────────────────────────────
-- The list is computed from every version ever shipped — see PATCH_20260821k
-- for what happens when it is retyped instead.
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
    'send_chat_message(text,bigint)',
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
    'api_call_directory()'
  ]::text[]
$$;

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


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_api_functions_callable();

COMMIT;
