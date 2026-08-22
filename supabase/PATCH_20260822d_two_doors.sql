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
--    Measured on a reconstruction of the live roster before and after:
--    ftymhb@gmail.com — the account from the incident — returned `viewer` from
--    my_role() before this file and NULL after it.
--
--  ── الدستور: بابان ────────────────────────────────────────────────────────
--      ١. **أدمن** — role = admin، وله كل شيء.
--      ٢. **عديل بمفتاح من الأدمن** — سجلّه هو، وبوّابته هو، والمجلس، ولا شيء
--         من مال الجمعية.
--    ولا ثالث. «لا أريد كثرة صلاحيات، ولا موظف ولا زائر ولا غير ذلك».
--
--  ⚠ THIS FILE IS DELIBERATELY SMALL, AND THE FIRST ONE WAS NOT.
--    The version handed over first was 26 KB: it also rebuilt
--    client_callable_functions() and swept every grant in the schema. It
--    ROLLED BACK on the live project and the cause was never identified — and
--    it did not matter, because that half was never needed. Every function
--    here is CREATE OR REPLACE at a signature that already exists, so Postgres
--    keeps the ACL and there is nothing to re-grant. What is left is the rule.
--
--  ⚠ AND ONE HOLE THIS FILE CANNOT CLOSE, BECAUSE IT IS NOT IN THE DATABASE.
--    `run_emulator.bat` carries the password of an approved admin, and this
--    repository is PUBLIC. The anon key is public by design, so anyone who
--    reads the file can sign in to the live project AS THAT ADMIN — without
--    the app, without a device id, without a code. Deleting the line does not
--    help: it is in the git history.
--
--    On 2026-08-22 that account was found to be the association's ONLY
--    administrator. It was closed by hand, in this order and no other: the
--    owner's Google account was promoted to admin, he signed in with it once,
--    and only then was admin@adayl.test disabled — password scrambled,
--    `banned_until` set to infinity, profile suspended. It was NOT deleted:
--    `receivables.created_by` references profiles ON DELETE SET NULL, and that
--    SET NULL is an UPDATE the rule-5 snapshot trigger refuses. It had
--    authored real receivables.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    ⚠ IT DELETES EVERY ACCESS KEY AND UNBINDS EVERY HANDSET:
--      «امسح جدول الدخول بالكامل لأمنح مفاتيح الدخول من جديد».
-- ============================================================================

BEGIN;

-- ── §1. لا نقفل الباب على أهل البيت ─────────────────────────────────────
-- ⚠ WITHOUT THIS, A PROJECT WITH NO APPROVED ADMIN WOULD BE LOCKED OUT OF
--   ITSELF by a file whose entire subject is access. That is not a theory:
--   RESET_AND_APPLY dropped public.profiles once and the جمعية lost its own
--   app until bootstrap_first_admin.sql was run again.
DO $seed$
DECLARE v_admins int;
BEGIN
  SELECT count(*) INTO v_admins FROM public.profiles
   WHERE role = 'admin' AND status = 'approved';
  IF v_admins = 0 THEN
    RAISE EXCEPTION 'لا يوجد أدمن معتمد — هذا الملف كان سيقفل التطبيق على الجميع';
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


-- ── §3. مسح الدخول بالكامل ──────────────────────────────────────────────
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

-- ⚠ AND A SUSPENSION SURVIVES THE WIPE. This UPDATE ran a second time on
--   the live project, after admin@adayl.test had been disabled — and because
--   its role was no longer 'admin' it matched the WHERE and was set back to
--   'pending'. A wipe that REVIVES a deliberately disabled account is granting
--   access, not removing it, which is the exact opposite of what it is for.
--
--   Rewriting status through a CASE rather than the WHERE is deliberate: a
--   SUSPENDED member must still lose his key, his handset and his binding.
--   Only the suspension itself is preserved.
UPDATE public.profiles
   SET adeel_id  = NULL,
       device_id = NULL,
       role      = 'viewer',
       status    = CASE WHEN status = 'suspended' THEN status ELSE 'pending' END
 WHERE role <> 'admin'
    OR adeel_id IS NOT NULL;


-- ── §4. الحارس الذي لم يكن موجوداً ──────────────────────────────────────
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
    RAISE EXCEPTION 'ACCESS: معتمد وليس أدمن ولا مربوطاً بعديل: %', v_who;
  END IF;
END $$;

-- A guard is not a client endpoint. It is called from the tail of a patch and
-- from WHICH_STATE, both of which run as the owner.
REVOKE ALL ON FUNCTION public.assert_two_doors_only()
  FROM PUBLIC, anon, authenticated, service_role;


-- ── §5. ولا نصدّق ما لم نُشغّله ──────────────────────────────────────────
--
-- ⚠ THE WIPE IS CHECKED IN THREE PLACES, not one. «No approved stranger» alone
--   would pass on a project where the keys survived and every handset was
--   still bound — which is most of what «امسح الدخول» actually means.
DO $smoke$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.profiles
   WHERE status = 'approved' AND adeel_id IS NULL AND role <> 'admin';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'ما زال % حساباً معتمداً بلا عديل وليس أدمن', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.adeel_access_codes;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'بقي % مفتاحاً بعد المسح', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM public.profiles WHERE device_id IS NOT NULL;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'بقي % جهازاً مربوطاً بعد المسح', v_n;
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
