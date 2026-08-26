-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-23 (e).  لوحُ المتأخّرات — شفافيةٌ بالاسم.
--
--  الطلب: «أضف اسم أي عديل عليه قيمة متأخرة وكم القيمة المستحقة عليه، وإذا كان
--  لديه عهدة تظهره أن له عهدة، في تبويب الصندوق أعلى القائمة فوق المحصّل نقداً،
--  ليكون واضحاً وضعُ الصندوق بالتزاماته … ليصبح كل العدايل على دراية بكل من
--  عليهم مستحقات ولم يدفعوا.»
--
--  ⚠ AND THIS REVERSES A DELIBERATE RULE, WHICH IS WHY IT IS WRITTEN DOWN.
--    api_association_finance() carries the comment «Counts, not money, and
--    deliberately only the two a member can already infer … No breakdown by
--    person», and portal_sections.dart says «Aggregates only: no name, no
--    receipt, no per-member figure». The association has now asked for the
--    opposite, for a stated reason: pressure to pay is the point.
--
--  ⚠ IT IS NOT THE SAME DECISION AS THE AID VOUCHERS, and the line between
--    them is worth keeping. «فلان لم يدفع اشتراك ثلاثة أشهر» is a duty toward
--    the group, and the group is entitled to it. «فلان أُعطي 500 لعزاء» is the
--    most private fact this system holds, and read_all_disbursements_adeel was
--    DROPPED for exactly that reason (PATCH_20260823a's note). This patch
--    exposes arrears and prepaid credit — nothing about aid, nothing about
--    receipts, nothing about who received what.
--
--  ⚠ «عهدة» HERE IS THE PREPAID CREDIT, not association money in his hands:
--    Σ payments − Σ allocations for that man, the same arithmetic
--    members_held() sums across everyone. It is a LIABILITY of the fund and is
--    shown as «له», never as «عليه».
--
--  SQL Editor → New query → paste → Run. معاملةٌ واحدة، تُشغَّل مرّتين بأمان.
-- ============================================================================

BEGIN;

-- ── §1. مَن عليه، ومن له ────────────────────────────────────────────────────
--
-- ⚠ SECURITY DEFINER, AND IT HAS TO BE. A member's RLS on receivables and
--   payments is «his own row», so a SECURITY INVOKER version would hand every
--   man his OWN arrears under a heading that says «الجمعية» — the same wrong
--   answer with nothing on screen to doubt that api_association_finance was
--   made DEFINER to avoid.
--
-- ⚠ THE GATE IS in_association(), the one place that question is answered:
--   staff by my_role(), an عديل by my_adeel_id(). It already refuses a pending
--   applicant, a suspended account, and a handset that has not claimed its key
--   — so a stranger holding the anon key gets a refusal, not a roster of who
--   owes what.
--
-- ⚠ ONLY MEN WITH SOMETHING TO SHOW. A row reading «0 / 0» for every man who
--   is straight would bury the four who are not, which is the opposite of what
--   the list is for. Ordered by what is owed, largest first.
--
-- ⚠ AND NO RECEIPT NUMBERS, NO DATES, NO METHOD. Two figures and a name — the
--   least that answers «من عليه ولم يدفع».
CREATE OR REPLACE FUNCTION public.api_arrears_board() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $board$
DECLARE v_out jsonb;
BEGIN
  IF NOT public.in_association() THEN
    RAISE EXCEPTION 'غير مصرح.' USING ERRCODE = 'RUL00';
  END IF;

  -- ⚠ jsonb_build_object RATHER THAN jsonb_agg(t), AND THE FIRST DRAFT DID NOT
  --   AND FAILED ON ITS FIRST RUN. Aggregating the row wholesale meant carrying
  --   the numeric columns the ORDER BY needs alongside the text ones the wire
  --   needs — and «owed» and "owed" are the SAME identifier in Postgres, so the
  --   subquery had two columns of each name. Building the object explicitly
  --   keeps the sort on numbers and the payload on text, with one name each.
  --
  -- ⚠ AND MONEY GOES OUT AS TEXT, like every other amount in this schema:
  --   Postgres serialises numeric as a bare JSON number and dart:convert
  --   decodes that to double.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'adeelId',   t.id,
           'adeelCode', t.code,
           'name',      t.name,
           'status',    t.status,
           'mine',      t.mine,
           'owed',      t.owed::numeric(12,2)::text,
           'held',      t.held::numeric(12,2)::text)
         ORDER BY t.owed DESC, t.held DESC, t.code), '[]'::jsonb)
    INTO v_out
    FROM (
      SELECT a.id,
             a.adeel_code                  AS code,
             a.full_name                   AS name,
             a.status::text                AS status,
             (a.id = public.my_adeel_id()) AS mine,
             owed.v                        AS owed,
             held.v                        AS held
        FROM public.adeels a
        CROSS JOIN LATERAL (
          SELECT coalesce(sum(r.balance), 0) AS v
            FROM public.receivables r
           WHERE r.adeel_id = a.id AND r.status <> 'ملغي') owed
        CROSS JOIN LATERAL (
          -- الرصيد المقدَّم: ما دُفع ولم يُخصَّم بعد — نفسُ حساب members_held()
          -- لكن لرجلٍ واحد.
          SELECT coalesce(sum(greatest(p.amount - coalesce(al.allocated, 0), 0)), 0) AS v
            FROM public.payments p
            LEFT JOIN LATERAL (
              SELECT sum(x.amount) AS allocated
                FROM public.payment_allocations x
               WHERE x.payment_id = p.id) al ON true
           WHERE p.adeel_id = a.id AND p.status <> 'ملغي') held
       WHERE owed.v > 0 OR held.v > 0
    ) t;

  RETURN v_out;
END $board$;


-- ── §2. الصلاحية: تُضاف إلى القائمة الحيّة، ولا تُكتب من جديد ───────────────
--
-- ⚠ THE LESSON OF 23/08: restating client_callable_functions() from a repo
--   file threw away six live signatures, because the file and the project had
--   drifted. Read the live array, append one entry, rewrite from THAT. And the
--   ::text is load-bearing — text[] || 'x' parses as array||array.
--
-- ⚠ AND NO LOCKDOWN SWEEP. One function is new; sweeping forty endpoints to
--   grant one is the blast radius that caused that incident.
DO $allow$
DECLARE v_list text[];
BEGIN
  v_list := public.client_callable_functions();
  IF NOT ('api_arrears_board()' = ANY (v_list)) THEN
    v_list := v_list || 'api_arrears_board()'::text;
  END IF;
  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.client_callable_functions() '
    'RETURNS text[] LANGUAGE sql IMMUTABLE AS $b$ SELECT %L::text[] $b$',
    v_list);
END $allow$;

REVOKE ALL ON FUNCTION public.api_arrears_board()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_arrears_board() TO authenticated;


-- ── §3. ولا نصدّق ما لم نُشغّله ────────────────────────────────────────────
DO $smoke$
DECLARE v jsonb;
BEGIN
  -- بلا جلسة: يجب أن يُرفض، لا أن يُرجع الجدول.
  BEGIN
    v := public.api_arrears_board();
    RAISE EXCEPTION 'لوحُ المتأخّرات فُتح بلا جلسة';
  EXCEPTION
    WHEN sqlstate 'RUL00' THEN NULL;   -- ✔ رُفض كما يجب
  END;

  IF NOT has_function_privilege('authenticated', 'public.api_arrears_board()',
                                'EXECUTE') THEN
    RAISE EXCEPTION 'اللوح غير مصرّح به للتطبيق';
  END IF;
  IF has_function_privilege('anon', 'public.api_arrears_board()', 'EXECUTE') THEN
    RAISE EXCEPTION 'اللوح مفتوحٌ لغير المسجّلين';
  END IF;
END $smoke$;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
