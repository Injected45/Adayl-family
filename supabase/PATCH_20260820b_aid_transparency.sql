-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-20 (b).  أسلاف الجمعية مكشوفة لكل مشترك.
--
--  WHAT THIS DOES
--    One policy. A bound عديل may read EVERY voucher, not only his own — so
--    «أسلاف للغير» in his portal can list what the association gave each man,
--    with names, occasions and amounts.
--
--  ⚠ THIS IS A DECISION OF THE ASSOCIATION, NOT A TECHNICAL CHANGE, AND IT IS
--    THE MOST PRIVATE FACT THIS SYSTEM HOLDS.
--
--    Until now a member saw his own aid and nothing else, and the comment beside
--    read_own_disbursements said why: a row here records that a NAMED man
--    received إعانة — for a bereavement, a birth, an emergency. After this
--    patch every member of the association can read that about every other
--    member.
--
--    The association asked for exactly this, in those words: «كل شيء
--    بالأسماء». It is consistent with the «شفافية مطلقة» already recorded
--    beside read_disbursements. It is written down here because a policy that
--    widens who may read a private fact should never be found by accident in a
--    diff.
--
--    ⚠ AND IT CANNOT BE UNDONE FOR WHAT IS ALREADY READ. Reversing the policy
--      closes the screen; it does not unsee what was on it. If the association
--      changes its mind, the revert is one DROP POLICY — the file below names
--      it — but the knowledge is out.
--
--  ⚠ WHAT IT DOES NOT DO
--    • It does not let a member WRITE anything. There is no write policy on
--      this table at all — register_disbursement is admin-only and stays so.
--    • It does not touch the money. No row is added, changed or removed, and
--      no figure any screen shows is computed differently.
--    • It does not widen anything else. `adeels`, `payments`, `receivables`,
--      `profiles` and the audit trail are exactly as scoped as they were — a
--      member still cannot read another man's DUES, only what he was GIVEN.
--
--  ⚠ AND THE CODE COLUMN WILL BE BLANK FOR OTHER MEN, which is correct rather
--    than broken. v_disbursements LEFT JOINs `adeels` for the payee's code, and
--    a member's RLS on that table is still his own row only. The NAME comes
--    through because it is SNAPSHOT onto the voucher (`payee_name`) — so the
--    screen reads «أيمن صالح بلها» with no code beside it, and the register
--    itself stays closed.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction. Safe to run twice.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.disbursements') IS NULL THEN
    RAISE EXCEPTION
      'لا يوجد جدول صرف. طبّق supabase/PATCH_20260817_device_lock.sql أولاً.';
  END IF;
END $prereq$;

-- == 1. كل مشترك يقرأ كل سند ================================================
-- ⚠ my_adeel_id() IS NOT NULL, and that clause is doing more than it looks.
--   It is NULL for staff — who are already covered by read_disbursements — and
--   NULL for an عديل whose handset has not claimed his code, and NULL for a
--   pending or suspended account. So «bound member» is exactly the set this
--   admits, and none of the three refusals had to be restated here.
--
--   A SEPARATE policy rather than a loosened read_own_disbursements: Postgres
--   ORs permissive policies, so the narrow one goes on standing on its own and
--   this one can be read — or DROPPED — without touching it. Reverting the
--   association's decision is then one statement:
--
--     DROP POLICY read_all_disbursements_adeel ON public.disbursements;
DROP POLICY IF EXISTS read_all_disbursements_adeel ON public.disbursements;
CREATE POLICY read_all_disbursements_adeel ON public.disbursements
  FOR SELECT TO authenticated
  USING (public.my_adeel_id() IS NOT NULL);


-- == 2. ما أُعطي غيرُك =====================================================
-- ⚠ المجاميع تُحسب هنا ولا تُجمع في Dart. المال نصّ من طرف إلى طرف
--   في هذا المشروع: numeric يصل إلى dart:convert رقماً عائماً، وشاشةٌ تجمع
--   مبالغ الجمعية بنفسها تضع خزينتها على حساب ثنائيّ عائم.
--
-- SECURITY INVOKER مثل api_adeel_aid: السياسة أعلاه هي التي تقرّر، فإن
-- أُسقطت عادت هذه الدالة خاوية من تلقاء نفسها ولا تبقى ثغرة مفتوحة.
CREATE OR REPLACE FUNCTION public.api_aid_others(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
  -- ⚠ CANCELLED VOUCHERS ARE EXCLUDED HERE, unlike a man's own ledger.
  --   His own screen LISTS a reversed voucher struck through, because rule 9
  --   says his history is not an embarrassment and he is entitled to see what
  --   was undone in his name. Another man's reversal is not his business — it
  --   is an administrative correction, and showing it invites the reading that
  --   somebody was given something and had it taken back.
  WITH live AS (
    SELECT d.* FROM public.disbursements d
     WHERE d.payee_adeel_id IS NOT NULL
       AND d.payee_adeel_id IS DISTINCT FROM p_adeel_id
       AND d.status <> 'ملغي'
  )
  SELECT jsonb_build_object(
    'total', (SELECT coalesce(sum(l.amount), 0)::numeric(12,2)::text FROM live l),
    'count', (SELECT count(*) FROM live l),
    -- Per man, largest first: «من أخذ أكثر» is the question a member opens this
    -- with, and a list in date order answers a different one.
    'men', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'adeelId', g.pid,
               'name',    g.nm,
               'total',   g.amt::numeric(12,2)::text,
               'count',   g.n)
             ORDER BY g.amt DESC, g.nm)
        FROM (SELECT l.payee_adeel_id AS pid,
                     coalesce(l.payee_name, '') AS nm,
                     sum(l.amount) AS amt,
                     count(*)      AS n
                FROM live l
               GROUP BY l.payee_adeel_id, l.payee_name) g), '[]'::jsonb),
    -- And the vouchers themselves, newest first.
    'vouchers', coalesce((
      SELECT jsonb_agg(to_jsonb(v) ORDER BY v."spentAt" DESC, v."id" DESC)
        FROM public.v_disbursements v
        JOIN live l ON l.id = v."id"), '[]'::jsonb)
  )
$fn$;

-- ⚠ CREATED FRESH, SO IT HAS NO ACL TO KEEP — Postgres materialises EXECUTE to
--   PUBLIC and Supabase layers anon on top. The allow-list is restated and the
--   sweep re-run below; assert_no_public_execute() would otherwise roll this
--   whole patch back naming a function rather than the missing REVOKE.
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
    -- ما أُعطي الآخرون. SECURITY INVOKER، فالسياسة هي التي تقرّر ماذا يرى
    -- المستدعي، وإسقاط read_all_disbursements_adeel يعيدها خاوية وحدها.
    'api_aid_others(bigint)'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- والمسحة نفسها، حرفاً بحرف من 20260811091200_function_lockdown.sql.
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

-- == 3. Confirmation ========================================================
-- Read-only. Every row must say true.
SELECT 'السياسة الجديدة قائمة' AS "الفحص",
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='disbursements'
                  AND policyname='read_all_disbursements_adeel') AS "النتيجة"
-- ⚠ AND THE OLD ONE SURVIVES. It is what still answers for a member on a
--   handset that has claimed his code but whose session is mid-refresh, and it
--   is what remains if the association ever drops the wide one.
UNION ALL SELECT 'وسياسة «سنداته هو» باقية كما هي',
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='disbursements'
                  AND policyname='read_own_disbursements')
UNION ALL SELECT 'وسياسة الإدارة باقية',
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='disbursements'
                  AND policyname='read_disbursements')
-- ⚠ AND STILL NOT ONE WRITE POLICY. Reading every voucher must not become
--   touching one; register_disbursement stays the only way in, and it is
--   admin-only inside its own body.
UNION ALL SELECT 'ولا سياسة كتابة على السندات البتة',
       NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='disbursements'
                      AND cmd <> 'SELECT')
UNION ALL SELECT 'ولا امتياز كتابة للمشترك',
       NOT has_table_privilege('authenticated', 'public.disbursements', 'INSERT')
        AND NOT has_table_privilege('authenticated','public.disbursements','UPDATE')
        AND NOT has_table_privilege('authenticated','public.disbursements','DELETE')
-- ⚠ AND NOTHING ELSE WIDENED. A member still reads his OWN row of the register
--   and nobody else's — what he can now see is what a man was GIVEN, never what
--   he OWES.
UNION ALL SELECT 'وسجل العدايل ما زال مقصوراً على صاحبه',
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='adeels'
                  AND qual LIKE '%my_adeel_id%')
UNION ALL SELECT 'ولم يتغيّر أي رقم مالي',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 5. The four guards =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
