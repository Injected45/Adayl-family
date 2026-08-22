-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-22 (d).  بابان لا ثالث لهما.
--
--  ⚠ WHAT HAPPENED ON THE LIVE PROJECT. A member signed in with Google, was
--    never asked for a code, and landed INSIDE the association app under his
--    own name. Six accounts sat at role=viewer, status=approved, adeel_id NULL.
--
--    my_role() returned the role for any approved profile with no عديل
--    binding — and `viewer` here was never «a visitor who sees nothing», it
--    was the LOWEST STAFF RANK: the register, the treasury, every man's dues.
--    So APPROVAL ALONE WAS STAFF ACCESS, and approval happens for ordinary
--    reasons — an admin waving somebody through, a backfill after a purge, a
--    binding cleared later and never restored.
--
--  ⚠ THE ROOT CAUSE IS THAT «approved» MEANT TWO DIFFERENT THINGS: «this
--    person is who he says he is» and «this person is staff». Two facts in one
--    column, and nothing anywhere asked which of them was meant.
--
--  ── الدستور: بابان ────────────────────────────────────────────────────────
--      ١. **أدمن** — role = admin، وله كل شيء.
--      ٢. **عديل بمفتاح من الأدمن** — سجلّه هو، وبوّابته هو، والمجلس، ولا شيء
--         من مال الجمعية.
--    ولا ثالث. «لا أريد كثرة صلاحيات، ولا موظف ولا زائر ولا غير ذلك».
--
--  ── وسبعة حرّاس على الباب ─────────────────────────────────────────────────
--    §2  my_role() = admin only. One clause — and every staff policy in this
--        schema already goes through it, so none of them had to be edited.
--    §3  set_user_access refuses to hand out any other role.
--    §4  المفتاح ينتهي بعد سبعة أيام، وإعادة الإصدار تُعيد ضبط المدّة.
--    §5  المحاولات تُعدّ وتُسجَّل — خمسٌ في الساعة ثم تُرفض.
--    §6  الجهاز من ترويسة الطلب وحدها؛ لم يعد المتصل يسمّي جهازه بنفسه.
--    §7  مسح الدخول بالكامل، كما طلبت الجمعية.
--    §8  assert_two_doors_only() — يُرجع أي ترقيع، وهذا منها، يترك أحداً
--        واقفاً في الداخل لم يُؤذَن له.
--
--  ⚠ AND ONE HOLE THIS FILE CANNOT CLOSE, BECAUSE IT IS NOT IN THE DATABASE.
--    `run_emulator.bat` carries the password of an approved admin, and that
--    repository is PUBLIC. The anon key is public by design, so anyone who
--    reads the file can sign in to the live project AS THAT ADMIN — without
--    the app, without a device id, without a code. Deleting the line does not
--    help: it is in the git history.
--
--    عالِجها من لوحة Supabase: Authentication → Users → احذف admin@adayl.test
--    أو غيِّر كلمة سرّه. §1 يرفض تشغيل هذا الملف إن لم يوجد أدمن معتمد آخر،
--    حتى لا يبقى المشروع بلا مالك.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ IT DELETES EVERY ACCESS KEY AND UNBINDS EVERY HANDSET:
--      «امسح جدول الدخول بالكامل لأمنح مفاتيح الدخول من جديد».
-- ============================================================================

BEGIN;

-- ── §1. لا نقفل الباب على أهل البيت ─────────────────────────────────────
-- ⚠ WITHOUT THIS, A PROJECT WITH NO APPROVED ADMIN WOULD BE LOCKED OUT OF
--   ITSELF by a patch whose entire subject is access. That is not a theory:
--   RESET_AND_APPLY dropped public.profiles once and the جمعية lost its own
--   app until bootstrap_first_admin.sql was run again.
DO $seed$
DECLARE v_admins int;
BEGIN
  SELECT count(*) INTO v_admins FROM public.profiles
   WHERE role = 'admin' AND status = 'approved';
  IF v_admins = 0 THEN
    RAISE EXCEPTION
      'لا يوجد أدمن معتمد — هذا الملف كان سيقفل التطبيق على الجميع';
  END IF;
END $seed$;


-- ── §2. القاعدة كلّها في سطر واحد ───────────────────────────────────────
--
-- Everything above the last clause is what my_role() always said: NULL for
-- anyone holding an عديل, NULL unless approved. The last clause is the fix,
-- and it belongs HERE rather than in the policies because every staff policy
-- in this schema already goes through has_role() → my_role(). One clause
-- closes all of them at once, and a policy written tomorrow inherits it.
CREATE OR REPLACE FUNCTION public.my_role() RETURNS app_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.role
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.adeel_id IS NULL
     AND p.role = 'admin'
$$;


-- ── §3. ولا تُمنح صلاحية غيرها ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_user_access(
  p_user_id uuid, p_role app_role DEFAULT NULL, p_status app_status DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_row record;
BEGIN
  PERFORM public.require_role('admin');

  -- ⚠ «admin» IS NOW THE ONLY ROLE THAT REACHES ANYTHING, so handing out
  --   any other grants nothing at all — and a permission that silently does
  --   nothing is worse than one that is refused, because the admin who
  --   granted it believes he granted something.
  IF p_role IS NOT NULL AND p_role <> 'admin' THEN
    RAISE EXCEPTION 'لا توجد إلا صلاحية أدمن. وغير الأدمن يدخل بمفتاح عديل.'
      USING ERRCODE = 'RUL00';
  END IF;

  UPDATE public.profiles SET
    role   = coalesce(p_role, role),
    status = coalesce(p_status, status),
    approved_by = CASE WHEN p_status = 'approved' THEN auth.uid() ELSE approved_by END,
    approved_at = CASE WHEN p_status = 'approved' THEN now() ELSE approved_at END
  WHERE id = p_user_id
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'RUL00';
  END IF;

  PERFORM public.write_audit('user.access',
    format('%s → %s / %s', v_row.email, v_row.role, v_row.status),
    v_row.id::text);

  RETURN jsonb_build_object('id', v_row.id, 'email', v_row.email,
                            'role', v_row.role, 'status', v_row.status);
END $$;


-- ── §4. المفتاح ينتهي ───────────────────────────────────────────────────
ALTER TABLE public.adeel_access_codes
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

-- Codes already in the field get the same clock, measured from when they were
-- issued. §7 deletes them all a few statements below; this is for a project
-- applying the file with codes outstanding.
UPDATE public.adeel_access_codes
   SET expires_at = issued_at + interval '7 days'
 WHERE expires_at IS NULL;

CREATE OR REPLACE FUNCTION public.issue_adeel_code(p_adeel_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_alphabet CONSTANT text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_code text := '';
  v_code_fmt text;
  v_adeel record;
  i int;
BEGIN
  PERFORM public.require_role('admin');

  SELECT id, adeel_code INTO v_adeel FROM public.adeels WHERE id = p_adeel_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  FOR i IN 1..12 LOOP
    -- random() is not cryptographic. It does not need to be: the row is written
    -- under a UNIQUE constraint, the code is delivered out of band, and the
    -- worst case for a predicted code is read-only sight of one man's own
    -- figures. gen_random_bytes would drag in pgcrypto for that.
    v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
  END LOOP;

  -- Grouped for reading aloud. redeem_adeel_code strips the dashes back out, so
  -- what the admin sees and what the عديل types are the same thing.
  v_code_fmt := substr(v_code,1,4) || '-' || substr(v_code,5,4) || '-' || substr(v_code,9,4);

  -- ⚠ AND ISSUING RESETS THE CLOCK. Without expires_at in the UPDATE
  --   branch, the ON CONFLICT path would keep the ORIGINAL expiry — so
  --   reissuing to a man whose first code had lapsed would hand him a key
  --   that was already dead, and the admin would watch him fail with a code
  --   issued one minute earlier.
  INSERT INTO public.adeel_access_codes
    (adeel_id, code, issued_by, expires_at)
  VALUES (p_adeel_id, v_code, auth.uid(), now() + interval '7 days')
  ON CONFLICT (adeel_id) DO UPDATE SET
    code = excluded.code, issued_at = now(), issued_by = excluded.issued_by,
    expires_at = excluded.expires_at,
    -- Cleared: this is a NEW code, and it has not been redeemed.
    redeemed_at = NULL, redeemed_by = NULL;

  -- ── Reissuing IS the way to release a lost phone ──────────────────────────
  -- Clearing device_id here is the only unlock the system has, and it was a
  -- deliberate choice over a second button: an عديل whose handset is stolen,
  -- wiped or replaced is otherwise locked out permanently, and the admin has to
  -- reissue his code in that situation anyway.
  --
  -- The binding itself (`adeel_id`) is deliberately LEFT ALONE. Clearing it too
  -- would drop him back to a plain approved viewer for as long as it took him
  -- to redeem again — and a viewer with no adeel_id reads the WHOLE
  -- association, because my_role() only returns NULL while an adeel_id is set.
  -- The unlock would have been a privilege escalation with a time window.
  --
  -- So he stays bound and stays locked out — my_adeel_id() refuses a NULL
  -- device_id — until the phone holding the new code opens the app and
  -- api_touch_login() claims it.
  UPDATE public.profiles
     SET device_id = NULL
   WHERE adeel_id = p_adeel_id
     AND device_id IS NOT NULL;

  PERFORM public.write_audit('adeel.code.issue',
    format('إصدار رمز دخول للعديل %s', v_adeel.adeel_code), v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', p_adeel_id, 'adeelCode', v_adeel.adeel_code, 'code', v_code_fmt);
END $$;


-- ── §5. المحاولات تُعدّ وتُسجَّل ─────────────────────────────────────────
--
-- ⚠ A WRONG CODE WAS A SILENCE. Nothing recorded it, nothing counted it, and
--   one account could try forever at no cost. Twelve characters out of a
--   thirty-letter alphabet is not guessable — but «not guessable» is an
--   argument about arithmetic, and an argument is not a guard. This is one,
--   and it costs one insert per member per year.
CREATE TABLE IF NOT EXISTS public.code_attempts (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_code_attempts_recent
  ON public.code_attempts (user_id, at DESC);

-- ⚠ RLS ON AND NO POLICY AT ALL — deliberately, and not an oversight for a
--   later patch to «fix». Nobody reads this from a client, not even his own
--   attempts: it is written by a SECURITY DEFINER function and read by an
--   admin in the SQL editor, which is where an investigation happens. A table
--   with RLS on and no policy returns zero rows to everyone, which is exactly
--   the intended answer.
ALTER TABLE public.code_attempts ENABLE ROW LEVEL SECURITY;


-- ── §6. الجهاز من الترويسة، والمفتاح له عمر ─────────────────────────────
CREATE OR REPLACE FUNCTION public.redeem_adeel_code(
  p_code      text,
  p_device_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_norm   text;
  v_device text;
  v_row    record;
  v_me     record;
  v_adeel  record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً' USING ERRCODE = 'RUL14';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  IF v_me.role <> 'viewer' THEN
    RAISE EXCEPTION 'هذا الحساب حساب إداري ولا يمكن ربطه بعديل'
      USING ERRCODE = 'RUL14';
  END IF;

  -- A SUSPENDED account cannot redeem its way back in.
  --
  -- This is the one status that has to be checked here, and it is easy to miss
  -- because the check that matters is not in this function — it is in
  -- guard_profile_change. That trigger normally refuses any self-change of
  -- `status`, and it makes ONE exception (`v_redeeming`) for the update below,
  -- which sets status = 'approved' on the caller's own row. The exception exists
  -- for pending → approved, which is the whole redemption flow.
  --
  -- Nothing distinguished suspended → approved from it. So an admin could
  -- suspend an account and that account could restore itself to `approved` by
  -- redeeming any unredeemed access code — coming back with read access to one
  -- عديل's dues, receipts and statement. The role never changed, so no other
  -- guard had anything to notice.
  --
  -- `pending` must still pass: a new Google account is created viewer/pending by
  -- handle_new_user, and redeeming is exactly how an عديل turns that into access
  -- without an admin approving him as staff. Only `suspended` is refused.
  IF v_me.status = 'suspended' THEN
    RAISE EXCEPTION 'هذا الحساب موقوف، راجع إدارة الجمعية'
      USING ERRCODE = 'RUL14';
  END IF;

  -- Typed by a person off a phone screen: dashes, spaces and lower case are all
  -- expected and none of them are part of the code.
  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));

  -- ⚠ COUNTED BEFORE THE LOOKUP, AND EVERY ATTEMPT COUNTS, not only the
  --   failures. Counting failures alone leaks the answer — a caller who is
  --   never throttled has learnt that his last guess was RIGHT. Five an hour
  --   is far above what a man typing a code off a phone screen needs, and
  --   far below what guessing twelve characters would take.
  IF (SELECT count(*) FROM public.code_attempts a
       WHERE a.user_id = auth.uid()
         AND a.at > now() - interval '1 hour') >= 5 THEN
    RAISE EXCEPTION 'محاولات كثيرة. انتظر ساعة ثم أعد المحاولة.'
      USING ERRCODE = 'RUL14';
  END IF;

  INSERT INTO public.code_attempts (user_id) VALUES (auth.uid());

  SELECT * INTO v_row FROM public.adeel_access_codes WHERE code = v_norm;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رمز الدخول غير صحيح' USING ERRCODE = 'RUL14';
  END IF;

  -- ⚠ AND A KEY THAT WAS NEVER USED STOPS BEING A KEY. A slip of paper
  --   handed over months ago, or photographed into a WhatsApp group, worked
  --   forever: there was no clock on it at all. Seven days is long enough to
  --   reach a man in the جمعية and short enough that a lost code is a dead
  --   code, and reissuing costs the admin one tap.
  IF v_row.expires_at IS NOT NULL AND v_row.expires_at < now() THEN
    RAISE EXCEPTION 'انتهت صلاحية هذا الرمز، اطلب رمزاً جديداً من الإدارة'
      USING ERRCODE = 'RUL14';
  END IF;

  -- One code, one man. A second person redeeming the same code would get his own
  -- read-only view of someone else's figures — which is a decision for the admin
  -- to make by reissuing, not something a forwarded WhatsApp message should be
  -- able to do.
  IF v_row.redeemed_at IS NOT NULL AND v_row.redeemed_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'هذا الرمز مستعمل بالفعل، اطلب رمزاً جديداً'
      USING ERRCODE = 'RUL14';
  END IF;

  -- ⚠ THE HEADER, AND ONLY THE HEADER — p_device_id IS NOW INERT.
  --
  --   Letting the CALLER name the handset he was claiming made «عديل واحد،
  --   جهاز واحد» a request rather than a rule: two phones send the same
  --   string, both hold the binding, and afterwards the register shows one
  --   device id with nothing in it to say two men are behind it.
  --
  --   The header is client-set too and can be forged — but forgery was never
  --   the threat here. SHARING is, and a forwarded code plus a hand-typed
  --   device id was sharing with the lock left hanging open.
  --
  --   The argument stays so no client breaks. This is the same treatment
  --   p_spent_at got the day a voucher could be dated tomorrow: keep the
  --   parameter, ignore the value, take the fact from the server.
  v_device := public.request_device_id();
  IF v_device IS NULL THEN
    RAISE EXCEPTION 'تعذّر التعرّف على الجهاز، حدِّث التطبيق وأعد المحاولة'
      USING ERRCODE = 'RUL14';
  END IF;

  UPDATE public.profiles
     SET adeel_id  = v_row.adeel_id,
         status    = 'approved',
         role      = 'viewer',
         device_id = v_device
   WHERE id = auth.uid();

  UPDATE public.adeel_access_codes
     SET redeemed_at = now(), redeemed_by = auth.uid()
   WHERE adeel_id = v_row.adeel_id;

  SELECT adeel_code INTO v_adeel FROM public.adeels WHERE id = v_row.adeel_id;

  PERFORM public.write_audit('adeel.code.redeem',
    format('ربط حساب %s بالعديل %s', v_me.email, v_adeel.adeel_code),
    v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', v_row.adeel_id, 'adeelCode', v_adeel.adeel_code);
END $$;


-- ── §7. مسح الدخول بالكامل ──────────────────────────────────────────────
--
-- «امسح جدول الدخول بالكامل لأمنح مفاتيح الدخول من جديد واختبر النظام».
--
-- ⚠ AND role IS RESET TO viewer, WHICH IS NOT COSMETIC. redeem_adeel_code
--   refuses any caller whose role is not exactly `viewer`, and
--   guard_profile_change permits the one self-change a redemption needs only
--   while OLD.role = NEW.role = viewer. Leave a former treasurer at his old
--   role and he can never redeem a key again — locked out, with no error that
--   explains why.
--
-- ⚠ AND adeel_id IS CLEARED, WHICH IT DELIBERATELY WAS NOT BEFORE. The same
--   guard recognises a redemption by the row ACQUIRING a binding
--   (OLD.adeel_id IS NULL AND NEW.adeel_id IS NOT NULL). A man who still holds
--   one is refused outright — so «امنحه مفتاحاً جديداً» would have failed for
--   every member already inside, which is all of them.
--
--   Clearing it used to be an ESCALATION: it dropped a man to a plain approved
--   viewer, and an approved viewer read the WHOLE association. §2 is precisely
--   what makes it safe now — that account reaches nothing at all.
DELETE FROM public.adeel_access_codes;

UPDATE public.profiles
   SET adeel_id  = NULL,
       device_id = NULL,
       role      = 'viewer',
       status    = 'pending'
 WHERE role <> 'admin'
    OR adeel_id IS NOT NULL;


-- ── §8. الحارس الذي لم يكن موجوداً ──────────────────────────────────────
--
-- ⚠ NOTHING WATCHED FOR THIS. Every guard in this schema asks whether the
--   PLUMBING is intact — grants, policies, sign-in, callable functions — and
--   all four passed on the day a member opened the association app. None of
--   them asked the question that actually mattered: **is anybody standing
--   inside who was never let in?**
CREATE OR REPLACE FUNCTION public.assert_two_doors_only()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_who text;
BEGIN
  SELECT string_agg(coalesce(nullif(email, ''), id::text), ', ')
    INTO v_who
    FROM public.profiles
   WHERE status = 'approved'
     AND adeel_id IS NULL
     AND role <> 'admin';

  IF v_who IS NOT NULL THEN
    RAISE EXCEPTION
      'ACCESS: معتمد وليس أدمن ولا مربوطاً بعديل: %', v_who;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public.assert_two_doors_only()
  FROM PUBLIC, anon, authenticated;


-- ── §9. القائمة، ثم كنس الصلاحيات ───────────────────────────────────────
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

-- ⚠ AFTER THE LAST CREATE, and that is the whole of the rule.
--   PATCH_20260820b put this sweep in the middle and created a trigger
--   function below it; that function took the built-in default of EXECUTE TO
--   PUBLIC, and assert_function_grants() rolled the entire patch back. The
--   guard was right and the ORDER was wrong.
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
        'GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
        r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;


-- ── §10. ولا نصدّق ما لم نُشغّله ────────────────────────────────────────
--
-- ⚠ RUN, NOT MERELY CREATED. Two patches in a row were syntactically perfect
--   and raised on their first real call — 42501 on a missing grant, 42803 on
--   a window nested inside an aggregate. A file that only CREATEs proves
--   nothing about whether the thing works.
--
--   my_role() cannot be called directly here: the SQL editor runs as postgres
--   with auth.uid() NULL, so it would return NULL for everybody and prove
--   nothing either. Its BODY is executed instead, against real rows.
DO $smoke$
DECLARE
  v_admin uuid;
  v_role  text;
  v_n     int;
BEGIN
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin' AND status = 'approved' LIMIT 1;

  -- The admin still passes every clause.
  SELECT p.role::text INTO v_role FROM public.profiles p
   WHERE p.id = v_admin AND p.status = 'approved'
     AND p.adeel_id IS NULL AND p.role = 'admin';
  IF v_role IS DISTINCT FROM 'admin' THEN
    RAISE EXCEPTION 'my_role() لم يعد يعرف الأدمن — لا تُطبّق';
  END IF;

  -- And nobody who is not an admin does.
  SELECT count(*) INTO v_n FROM public.profiles p
   WHERE p.status = 'approved' AND p.adeel_id IS NULL
     AND p.role <> 'admin';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'ما زال % حساباً معتمداً بلا عديل وليس أدمن', v_n;
  END IF;

  -- The wipe actually emptied the table.
  SELECT count(*) INTO v_n FROM public.adeel_access_codes;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'بقي % مفتاحاً بعد المسح', v_n;
  END IF;

  -- And the throttle table takes the write redeem_adeel_code now depends on.
  INSERT INTO public.code_attempts (user_id) VALUES (v_admin);
  DELETE FROM public.code_attempts WHERE user_id = v_admin;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_api_functions_callable();
SELECT public.assert_two_doors_only();

COMMIT;
