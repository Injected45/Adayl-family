-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-26 (b).  الأدمن يتّصل باسم «الإدارة».
--
--  الطلب: «نعم أظهر الأدمن» — أي أن تحمل مكالمةُ الإدارة اسمَ المؤسسة، لا اسمَ
--  حساب جوجل الذي سُجّل به.
--
--  ── ما الذي كان يحدث، ولماذا لم يكن عطلاً ────────────────────────────────
--    my_display_name() falls through a chain: the register's full_name, then
--    the Google display name, then the email local part. A member has a
--    full_name so he shows correctly — «ايمن صالح بلها», proven on the live
--    calls. The ADMIN holds no adeel_id at all, so the chain reached the second
--    rung and every call he placed was signed «Shobke Mhde».
--
--  ⚠ THE FIX IS A BRANCH, NOT A REORDER. Moving 'الإدارة' up the chain would
--    swallow the member too — my_role() is NULL for him, so the two cases are
--    told apart by exactly one question and it is asked first.
--
--  ⚠ AND IT IS my_role(), WHICH IS THE ONE PLACE THAT DECIDES «staff». It ends
--    `AND p.role = 'admin'` and returns NULL the moment adeel_id is set, so
--    this inherits «بابان لا ثالث لهما» rather than restating it. A hand-written
--    `role = 'admin'` here would be a second answer to that question, free to
--    disagree with the first.
--
--  ⚠ ONE FUNCTION, SAME SIGNATURE, so the ACL is kept and no lockdown sweep is
--    needed. start_call and join_call are untouched — they already ask.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.my_display_name() RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $mdn$
DECLARE v_name text;
BEGIN
  -- ── الإدارة تتكلّم باسم المؤسسة ────────────────────────────────────────
  -- ⚠ FIRST, AND BEFORE THE REGISTER IS EVEN CONSULTED. An admin has no row in
  --   adeels, so the question «what is his name here» has no answer — and the
  --   name of the person holding the account is not the answer the man
  --   receiving the call needs. He needs to know the association is calling.
  IF public.my_role() IS NOT NULL THEN
    RETURN 'الإدارة';
  END IF;

  SELECT nullif(btrim(a.full_name), '') INTO v_name
    FROM public.profiles p
    JOIN public.adeels a ON a.id = p.adeel_id
   WHERE p.id = auth.uid();

  IF v_name IS NULL THEN
    SELECT nullif(btrim(p.display_name), '') INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;

  IF v_name IS NULL THEN
    SELECT nullif(split_part(p.email, '@', 1), '') INTO v_name
      FROM public.profiles p WHERE p.id = auth.uid();
  END IF;

  RETURN coalesce(v_name, 'الإدارة');
END $mdn$;

-- ⚠ RESTATED, THOUGH CREATE OR REPLACE KEEPS THE ACL. It costs nothing and it
--   is the line assert_no_public_execute would otherwise roll this back over.
REVOKE ALL ON FUNCTION public.my_display_name()
  FROM PUBLIC, anon, authenticated, service_role;


-- ── ولا نصدّق ما لم نُشغّله ──────────────────────────────────────────────
--
-- ⚠ AND THIS ONE ACTUALLY EXERCISES THE BRANCH RATHER THAN READING THE SOURCE.
--   The editor runs as `postgres` with no session, so auth.uid() is NULL and a
--   bare call falls through to the same 'الإدارة' by coalesce — it would pass
--   with the new branch DELETED. So the claim is set for the duration of the
--   transaction (`set_config(..., true)` is transaction-local and dies at
--   COMMIT), and the function is asked as a real admin and as a real عديل.
--
--   That is the difference between «the file landed» and «the thing works»,
--   and this project has paid for the gap more than once.
DO $smoke$
DECLARE
  v_admin uuid;
  v_adeel uuid;
  v_want  text;
  v_got   text;
BEGIN
  SELECT p.id INTO v_admin
    FROM public.profiles p
   WHERE p.role = 'admin' AND p.status = 'approved' AND p.adeel_id IS NULL
   LIMIT 1;
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'لا يوجد أدمن معتمد لاختبار الاسم';
  END IF;

  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_admin)::text, true);
  v_got := public.my_display_name();
  IF v_got <> 'الإدارة' THEN
    RAISE EXCEPTION 'الأدمن ما زال يتصل باسم «%»', v_got;
  END IF;

  -- ⚠ AND THE MEMBER MUST BE UNTOUCHED. A patch that makes the admin right and
  --   the eight wrong would be a worse state than the one it replaced, and
  --   «ايمن صالح بلها» on the live calls is what it must not break.
  SELECT p.id, a.full_name INTO v_adeel, v_want
    FROM public.profiles p
    JOIN public.adeels a ON a.id = p.adeel_id
   WHERE btrim(coalesce(a.full_name, '')) <> ''
   LIMIT 1;
  IF v_adeel IS NULL THEN
    RAISE EXCEPTION 'لا يوجد عديل مربوط لاختبار الاسم';
  END IF;

  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_adeel)::text, true);
  v_got := public.my_display_name();
  IF v_got <> btrim(v_want) THEN
    RAISE EXCEPTION 'العديل يظهر باسم «%» بدل «%»', v_got, btrim(v_want);
  END IF;

  PERFORM set_config('request.jwt.claims', '', true);
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
