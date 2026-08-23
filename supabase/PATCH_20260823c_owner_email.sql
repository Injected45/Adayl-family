-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-23 (c).  البريدُ هو صاحبُ العديل.
--
--  الطلب: «عديل فعّل مفتاحاً بهاتفٍ معيّن — لا يُفعَّل أيُّ مفتاحٍ جديدٍ لهذا
--  العديل إلا بنفس البريد. وإذا أراد هاتفاً جديداً: يدخل بنفس البريد، ثمّ يصله
--  كودٌ من الأدمن، فيُفتح بعد التطابق بين الكود والبريد.»
--
--  ما كان: PATCH_20260823b جعل الاسترداد **يطرد** الحساب السابق — بريدٌ جديد
--  يحمل مفتاحاً صحيحاً كان يأخذ العديل ويُخرج صاحبَه. هذا يُلغى.
--
--  ما صار:
--    §1 الاسترداد يرفض إن كان العديل مرتبطاً ببريدٍ آخر. الهاتف حرّ — يتغيّر
--       بمفتاحٍ جديد — والبريد لا.
--    §2 unbind_adeel(id): مخرجُ الإدارة. بدونه يصير خطأٌ في الربط سجناً
--       مؤبّداً: بريدٌ ضاع، أو رجلٌ ربط عديلاً ليس له، ولا سبيل لإصلاحه.
--    §3 كنسُ الصلاحيات، لأنّ §2 دالّةٌ جديدة.
--    §4 الحارس يعرف القاعدة الجديدة.
--
--  SQL Editor → New query → paste → Run. معاملةٌ واحدة، تُشغَّل مرّتين بأمان.
-- ============================================================================

BEGIN;

-- ── §1. الاسترداد: بريدُ الأوّل هو صاحبُ العديل ─────────────────────────────
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

  -- ── ⚠ حسابٌ مربوطٌ بعديل لا يُربط بعديلٍ آخر، ويُقال له لماذا ───────────
  --
  --   THIS WAS ALREADY REFUSED and that is worth stating plainly: the UPDATE
  --   at the end of this function trips guard_profile_change, which raises
  --   «FORBIDDEN: cannot change your own عديل binding». The rule was never
  --   missing. What was missing was SAYING SO — the association typed
  --   عبدالعزيز's key into a handset bound to ايمن, saw a bare refusal, pressed
  --   again, and was let in by a different door entirely (see §1). A refusal
  --   nobody can read is a refusal nobody trusts, and it sent an hour of
  --   testing looking at the wrong thing.
  --
  -- ⚠ AND IT MUST NOT REFUSE HIS OWN KEY. Re-redeeming the SAME عديل is the
  --   ordinary case — a new phone, a reissued code — so the test is «a
  --   DIFFERENT عديل», never «already bound».
  IF v_me.adeel_id IS NOT NULL AND v_me.adeel_id IS DISTINCT FROM
     (SELECT adeel_id FROM public.adeel_access_codes
       WHERE code = upper(regexp_replace(coalesce(p_code,''),'[^0-9A-Za-z]','','g'))) THEN
    RAISE EXCEPTION 'هذا الحساب مرتبط بعديلٍ آخر. لفكّ الارتباط راجع إدارة الجمعية'
      USING ERRCODE = 'RUL14';
  END IF;

  -- Typed by a person off a phone screen: dashes, spaces and lower case are all
  -- expected and none of them are part of the code.
  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));

  SELECT * INTO v_row FROM public.adeel_access_codes WHERE code = v_norm;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رمز الدخول غير صحيح' USING ERRCODE = 'RUL14';
  END IF;

  -- ⚠ A KEY THAT WAS NEVER USED STOPS BEING A KEY. A slip of paper handed
  --   over months ago, or photographed into a WhatsApp group, worked forever:
  --   there was no clock on it at all. Seven days is long enough to reach a
  --   man in the جمعية and short enough that a lost code is a dead code,
  --   and reissuing costs the admin one tap.
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
  --   Letting the CALLER name the handset he was claiming made
  --   «عديل واحد، جهاز واحد» a request rather than a rule: two phones
  --   send the same string, both hold the binding, and the register
  --   afterwards shows one device id with nothing in it to say two men are
  --   behind it.
  --
  --   The header is client-set too and can be forged — but forgery was never
  --   the threat. SHARING is, and a forwarded code plus a hand-typed device
  --   id was sharing with the lock left hanging open.
  --
  --   The argument stays so no installed handset breaks. Same treatment
  --   p_spent_at got the day a voucher could be dated tomorrow: keep the
  --   parameter, ignore the value, take the fact from the server.
  v_device := public.request_device_id();
  IF v_device IS NULL THEN
    RAISE EXCEPTION 'تعذّر التعرّف على الجهاز، حدِّث التطبيق وأعد المحاولة'
      USING ERRCODE = 'RUL14';
  END IF;

  -- الحسابُ الذي فعّل هذا العديل أوّلَ مرّة هو صاحبُه، ولا يُنزع منه.
  IF EXISTS (SELECT 1 FROM public.profiles
              WHERE adeel_id = v_row.adeel_id AND id <> auth.uid()) THEN
    RAISE EXCEPTION
      'هذا العديل مرتبط ببريدٍ آخر. لا يُفتح إلا بنفس البريد، أو تفكّ الإدارة الارتباط'
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

-- ── §2. مخرجُ الإدارة ───────────────────────────────────────────────────────
--
-- ⚠ A RULE WITHOUT A REMEDY IS A TRAP. §1 makes the first email the owner of
--   that عديل for good — which is what was asked, and which turns three
--   ordinary accidents into permanent lockouts: a man redeems with the wrong
--   Google account, a member loses access to his email, or a code reaches the
--   wrong hands once. Before this, «issue a new key» quietly repaired all
--   three by eviction. Now nothing does, so the repair has to be deliberate,
--   admin-only, and written in the audit trail.
--
-- ⚠ IT DELETES THE CODE TOO. Leaving a live key behind would let whoever holds
--   the slip re-bind the moment the seat is empty, which is the opposite of
--   what unbinding is for.
--
-- ⚠ AND IT LEAVES status = 'pending', NOT 'approved'. An unbound approved
--   viewer is a «غريب في الداخل» — the exact shape assert_two_doors_only
--   refuses and PATCH_20260823b had to clean up three of.
CREATE OR REPLACE FUNCTION public.unbind_adeel(p_adeel_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $unbind$
DECLARE
  v_adeel record;
  v_who   text;
  v_n     int;
BEGIN
  PERFORM public.require_role('admin');

  SELECT id, adeel_code, full_name INTO v_adeel
    FROM public.adeels WHERE id = p_adeel_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  SELECT string_agg(coalesce(nullif(email,''), id::text), ', '), count(*)
    INTO v_who, v_n
    FROM public.profiles WHERE adeel_id = p_adeel_id;

  UPDATE public.profiles
     SET adeel_id = NULL, device_id = NULL, status = 'pending'
   WHERE adeel_id = p_adeel_id;

  DELETE FROM public.adeel_access_codes WHERE adeel_id = p_adeel_id;

  PERFORM public.write_audit('adeel.unbind',
    format('فكّ ارتباط العديل %s عن %s', v_adeel.adeel_code,
           coalesce(v_who, 'لا حساب')),
    v_adeel.adeel_code);

  RETURN jsonb_build_object('adeelId', p_adeel_id,
                            'adeelCode', v_adeel.adeel_code,
                            'unbound', coalesce(v_n, 0));
END $unbind$;




-- ── §4. الحارس يعرف القاعدة الجديدة ─────────────────────────────────────────
--
-- ⚠ IT READS THE BODY. The signature does not change when the refusal is
--   swapped back for an eviction, and neither does any grant — so every other
--   guard would stay green while the rule the association asked for quietly
--   went away.
CREATE OR REPLACE FUNCTION public.assert_owner_email_sticky()
RETURNS void LANGUAGE plpgsql AS $own$
DECLARE v_src text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code';

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'OWNER: redeem_adeel_code مفقودة';
  END IF;
  IF v_src NOT LIKE '%مرتبط ببريدٍ آخر%' THEN
    RAISE EXCEPTION 'OWNER: الاسترداد لا يرفض بريداً آخر لنفس العديل';
  END IF;
  -- ⚠ NOT «AND id <> auth.uid()» — THE FIRST DRAFT USED THAT AND FAILED ON
  --   ITS OWN PATCH. The new REFUSAL contains that clause too («does anybody
  --   else hold this عديل»), so the guard was matching the very rule it was
  --   written to protect. The eviction's distinctive act is CLEARING a
  --   binding, and nothing in the redeeming path clears one any more.
  IF v_src LIKE '%SET adeel_id = NULL%' THEN
    RAISE EXCEPTION 'OWNER: الاسترداد ما زال يطرد الحساب السابق بدل رفضه';
  END IF;

  SELECT count(*) INTO v_n FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'unbind_adeel';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'OWNER: لا مخرجَ للإدارة — unbind_adeel مفقودة';
  END IF;
END $own$;

REVOKE ALL ON FUNCTION public.assert_owner_email_sticky()
  FROM PUBLIC, anon, authenticated, service_role;



-- ── §3. الصلاحية: نُضيف إلى قائمته الحيّة، ولا نكتبها من جديد ──────────────
--
-- ⚠ THE FIRST DRAFT REPLACED client_callable_functions() WITH THE ARRAY WRITTEN
--   IN PATCH_20260823a, AND THE ASSOCIATION'S PROJECT REFUSED IT — naming six:
--   save_adeel(jsonb), api_reports(text,text), generate_period(text),
--   register_disbursement(jsonb), api_member_months(bigint) and
--   register_payment(bigint,numeric,payment_method,text,text).
--
--   The live list and the list in that file had DRIFTED. Restating it from the
--   file therefore threw away the correct one, the sweep revoked everything and
--   re-granted only what the stale array named, and six working endpoints lost
--   their grant. The transaction rolled it all back, which is the only reason
--   this was an error message rather than an outage.
--
-- ⚠ SO IT IS APPENDED IN PLACE. The live array is read, one entry is added, and
--   the function is rewritten from THAT — so whatever the project actually
--   holds survives, and this patch cannot be wrong about signatures it never
--   names. A hard-coded allow-list in a patch is a claim about a database the
--   patch cannot see.
--
-- ⚠ AND NO SWEEP. Only ONE function is new here; everything else is CREATE OR
--   REPLACE on an existing signature, which keeps its ACL. Sweeping would
--   revoke and re-grant forty endpoints to fix one, which is exactly the blast
--   radius that just caused this.
DO $allow$
DECLARE v_list text[];
BEGIN
  v_list := public.client_callable_functions();
  IF NOT ('unbind_adeel(bigint)' = ANY (v_list)) THEN
    -- ⚠ ::text IS LOAD-BEARING. Without it Postgres reads the untyped literal
    --   as an ARRAY literal — text[] || unknown prefers array||array — and
    --   raises «malformed array literal: "unbind_adeel(bigint)"». The first
    --   draft had no cast and appeared to pass, because the entry was already
    --   in the list from an earlier run and this branch never executed.
    v_list := v_list || 'unbind_adeel(bigint)'::text;
  END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.client_callable_functions() '
    'RETURNS text[] LANGUAGE sql IMMUTABLE AS $b$ SELECT %L::text[] $b$',
    v_list);
END $allow$;

-- ⚠ A FUNCTION CREATED FRESH HAS NO ACL TO KEEP, so Postgres materialises the
--   built-in default — EXECUTE to PUBLIC — and Supabase layers anon on top.
--   assert_no_public_execute() catches it; this is the REVOKE that stops it
--   ever getting there.
REVOKE ALL ON FUNCTION public.unbind_adeel(bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unbind_adeel(bigint) TO authenticated;


-- ── §5. ولا نصدّق ما لم نُشغّله ────────────────────────────────────────────
DO $smoke$
DECLARE v_src text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code';
  IF v_src NOT LIKE '%مرتبط ببريدٍ آخر%' THEN
    RAISE EXCEPTION 'الاسترداد لا يحمل قاعدة البريد';
  END IF;
  IF v_src NOT LIKE '%device_id = v_device%' THEN
    RAISE EXCEPTION 'الاسترداد لم يعد يربط الجهاز — لا باب للعديل';
  END IF;
  -- والهاتف يبقى حرّاً: issue_adeel_code هو ما يمسحه.
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'issue_adeel_code';
  IF v_src NOT LIKE '%device_id = NULL%' THEN
    RAISE EXCEPTION 'إصدار المفتاح لم يعد يحرّر الهاتف — لا تغيير للهاتف';
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();
SELECT public.assert_login_lockdown();
SELECT public.assert_owner_email_sticky();

COMMIT;
