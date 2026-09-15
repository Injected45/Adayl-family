-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-15 (c).  «حركة العدايل»: صافي كلّ مشترك.
--
--  ما الذي يفعله هذا الملف
--    يضيف قائمةً للقراءة فقط اسمها v_member_net: لكلّ مشتركٍ في السجلّ ما
--    دفعه، وما استلمه، والفرق بينهما — بالقاعدة نفسها التي تحسب بها شاشة
--    «الجدوى» (الإيصالاتُ غيرُ الملغاة، وسنداتُ الصرف له غيرُ الملغاة) —
--    ومعها إجماليُّ الفرق لكلّ المشتركين.
--
--  منها تُرسم حاويةُ «حركة العدايل» في شاشة الصندوق: الإجماليُّ على عنوانها،
--  وتحتها كلُّ مشتركٍ و«صافي رصيد مستحق له» أو «رصيد مستحق عليه».
--
--  ⚠ الحسابُ هنا لا في الهاتف: المبالغ نصٌّ من الخادم في هذا التطبيق، ولا
--    يجمع التطبيقُ مالًا بنفسه. والإجماليُّ دالّةُ نافذةٍ في القائمة نفسِها،
--    فلا يختلف مجموعُ الأسطر عن الرقم على العنوان أبدًا.
--
--  ⚠ للقراءة فقط. لا يُكتب صفّ، ولا يتغيّر رقم، ولا دالّةٌ ماليّة. والقائمةُ
--    بصلاحيّة القارئ: الأدمن يرى الجميع، والمشتركُ لو قرأها لا يرى إلا نفسه.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.payments') IS NULL
     OR to_regclass('public.disbursements') IS NULL
     OR to_regclass('public.adeels') IS NULL THEN
    RAISE EXCEPTION 'هذا ليس مشروع الجمعية بنظام الصرف — لم يتغيّر شيء.';
  END IF;
END $prereq$;

-- == 1. القائمة ============================================================
-- ⚠ «دفع» = الإيصالاتُ غير الملغاة، و«استلم» = سنداتُ الصرف المسمّاة باسمه غير
--   الملغاة — حرفًا كما في api_member_value، فلا يختلف رقمٌ هنا عن «الجدوى».
--   الصرفُ الجماعيّ لا يُنسب لأحد، فلا يدخل في «استلم» لأيّ مشترك.
CREATE OR REPLACE VIEW public.v_member_net WITH (security_invoker = on) AS
SELECT a.id                                      AS "adeelId",
       a.adeel_code                              AS "adeelCode",
       a.full_name                               AS "adeelName",
       p.paid::numeric(12,2)::text               AS "paid",
       r.received::numeric(12,2)::text           AS "received",
       (p.paid - r.received)::numeric(12,2)::text AS "net",
       (sum(p.paid - r.received) OVER ())::numeric(12,2)::text AS "totalNet"
  FROM public.adeels a
  CROSS JOIN LATERAL (
    SELECT coalesce(sum(x.amount), 0) AS paid
      FROM public.payments x
     WHERE x.adeel_id = a.id AND x.status <> 'ملغي'
  ) p
  CROSS JOIN LATERAL (
    SELECT coalesce(sum(d.amount), 0) AS received
      FROM public.disbursements d
     WHERE d.payee_adeel_id = a.id AND d.status <> 'ملغي'
  ) r;

REVOKE ALL ON public.v_member_net FROM PUBLIC, anon;
GRANT SELECT ON public.v_member_net TO authenticated;

-- == 2. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 3. النتيجة: آخرُ جدولٍ يظهر في المحرّر ================================
SELECT "adeelCode" AS "الكود",
       "adeelName" AS "المشترك",
       "paid"      AS "دفع",
       "received"  AS "استلم",
       "net"       AS "الصافي (موجب = مستحق له)",
       "totalNet"  AS "إجمالي الفرق"
  FROM public.v_member_net
 ORDER BY "adeelCode";

COMMIT;
