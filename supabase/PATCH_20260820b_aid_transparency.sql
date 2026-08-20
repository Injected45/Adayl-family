-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-20 (b).  الصرف الجماعي مكشوف لكل مشترك.
--
--  WHAT THIS DOES
--    A bound عديل may read every COLLECTIVE voucher — فطور رمضان and its like:
--    money the association spent on everybody at once, attributed to nobody.
--    «أسلاف للغير» in his portal lists them, with the occasion, the amount and
--    the date, and a breakdown by وجه الصرف.
--
--  ⚠ AND IT DELIBERATELY DOES NOT SHOW WHAT ANOTHER MAN RECEIVED.
--
--    An earlier draft of this file did: one policy admitting a member to every
--    voucher including the named ones. The association looked at it and chose
--    otherwise — the screen is to carry the COLLECTIVE spending, not other
--    members' aid — so the wide policy is DROPPED here and replaced by one
--    scoped to `payee_adeel_id IS NULL`.
--
--    That is the better rule and not merely the narrower one. A row naming a
--    man who received إعانة for a bereavement is the most private fact this
--    system holds; a row saying the association spent 400 on فطور رمضان names
--    nobody and answers the question a member actually has — «أين يذهب مالي».
--
--  ⚠ THE DROP IS UNCONDITIONAL, so this file is correct whether or not its
--    earlier draft was ever applied. Run it on a project that has the wide
--    policy and it is removed; run it on one that never had it and the DROP
--    finds nothing. Either way the state afterwards is the same, which is the
--    only property that makes a corrective patch safe to hand over.
--
--  ⚠ WHAT ELSE IS IN HERE
--    • api_aid_others  — the collective vouchers and their totals by occasion.
--    • api_member_value — «الجدوى»: what a man paid, what he received, and
--      what the fund did. Aggregates only: no name, no receipt, no row.
--    • A trigger refusing a voucher dated in a day that has not happened.
--
--  ⚠ NO ROW IS TOUCHED AND NO FIGURE MOVES. Policies, two new reads and one
--    trigger. Every existing amount is exactly what it was.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction. Safe to run twice, and safe to run again after the
--    earlier draft.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.disbursements') IS NULL THEN
    RAISE EXCEPTION
      'لا يوجد جدول صرف. طبّق supabase/PATCH_20260817_device_lock.sql أولاً.';
  END IF;
END $prereq$;

-- == 1. كل مشترك يقرأ الصرف الجماعي =========================================
-- ⚠ THE EARLIER DRAFT OF THIS FILE ADMITTED A MEMBER TO EVERY VOUCHER.
--   It is dropped below unconditionally, so applying this after that draft
--   closes it again. Nothing else has to be undone: the wide policy granted
--   only reading, and reading leaves no trace to reverse.

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
--     DROP POLICY read_collective_disbursements ON public.disbursements;

-- ⚠ AND `payee_adeel_id IS NULL` IS THE WHOLE PRIVACY RULE. A collective
--   voucher is attributed to nobody by ck_disb_shape — that is what makes it
--   collective — so this clause admits exactly the rows that name no man, and
--   cannot be widened by accident into the ones that do.
DROP POLICY IF EXISTS read_all_disbursements_adeel ON public.disbursements;
DROP POLICY IF EXISTS read_collective_disbursements ON public.disbursements;
CREATE POLICY read_collective_disbursements ON public.disbursements
  FOR SELECT TO authenticated
  USING (payee_adeel_id IS NULL AND public.my_adeel_id() IS NOT NULL);


-- == 2. الصرف الجماعي ======================================================
-- ⚠ المجاميع تُحسب هنا ولا تُجمع في Dart. المال نصّ من طرف إلى طرف
--   في هذا المشروع: numeric يصل إلى dart:convert رقماً عائماً، وشاشةٌ تجمع
--   مبالغ الجمعية بنفسها تضع خزينتها على حساب ثنائيّ عائم.
--
-- SECURITY INVOKER مثل api_adeel_aid: السياسة أعلاه هي التي تقرّر، فإن
-- أُسقطت عادت هذه الدالة خاوية من تلقاء نفسها ولا تبقى ثغرة مفتوحة.
-- ⚠ THE ARGUMENT IS UNUSED, AND KEPT ON PURPOSE. It named the man to exclude
--   back when this listed other members' aid. Collective spending belongs to
--   nobody, so there is nobody to exclude — but changing the signature would
--   mean DROP and CREATE, a fresh ACL, and an app in the field calling a
--   function that no longer exists. One unused parameter is the cheaper half
--   of that trade by a wide margin.
CREATE OR REPLACE FUNCTION public.api_aid_others(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $fn$
  -- ⚠ COLLECTIVE ONLY — `payee_adeel_id IS NULL`. That is the same clause the
  --   policy above uses, restated here so the function is honest on its own:
  --   a reader who somehow held a wider policy would still get only these.
  --
  -- ⚠ AND CANCELLED VOUCHERS ARE EXCLUDED. A man's own ledger keeps his
  --   reversals listed and struck through, because rule 9 says his history is
  --   not an embarrassment. A reversal on a communal expense is an
  --   administrative correction and belongs in the audit trail, not on a
  --   screen a member reads to see where the fund went.
  WITH live AS (
    SELECT d.* FROM public.disbursements d
     WHERE d.payee_adeel_id IS NULL
       AND d.status <> 'ملغي'
  )
  SELECT jsonb_build_object(
    'total', (SELECT coalesce(sum(l.amount), 0)::numeric(12,2)::text FROM live l),
    'count', (SELECT count(*) FROM live l),
    -- ── BY OCCASION, largest first ────────────────────────────────────────
    -- «على ماذا أُنفق» is the question this screen is opened with — a member
    -- wants to know where the fund went, and a communal expense has no man to
    -- group under. The وجه is the only grouping it HAS, and it is exactly the
    -- one the association chose an enum for so that عزاء and مصاريف عزاء
    -- could not become two answers to one question.
    --
    -- Only the headings actually spent on, unlike v_expense_by_category which
    -- lists the empty ones too: «صُرف صفر على فرح» is an answer a treasurer
    -- wants and a member does not.
    'byCategory', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'category', g.cat,
               'total',    g.amt::numeric(12,2)::text,
               'count',    g.n)
             ORDER BY g.amt DESC, g.cat)
        FROM (SELECT l.category::text AS cat,
                     sum(l.amount)    AS amt,
                     count(*)         AS n
                FROM live l
               GROUP BY l.category) g), '[]'::jsonb),
    -- And the vouchers themselves, newest first.
    'vouchers', coalesce((
      SELECT jsonb_agg(to_jsonb(v) ORDER BY v."spentAt" DESC, v."id" DESC)
        FROM public.v_disbursements v
        JOIN live l ON l.id = v."id"), '[]'::jsonb)
  )
$fn$;

-- == 2b. جدوى العضوية =====================================================
-- ما دفعه الرجل، وما استلمه، وموقع الجمعية كلها من ذلك — في نداء واحد.
--
-- ⚠ SECURITY DEFINER, AND THAT IS THE WHOLE RISK IN THIS FUNCTION.
--   The association-wide figures — everything collected, everything given to
--   members, how many men were helped — are NOT readable by a member: his RLS
--   on cash_movements is `adeel_id = my_adeel_id()`, so a SECURITY INVOKER
--   version would hand him HIS OWN four figures under headings that say «the
--   association», which is not a leak but something worse: a wrong answer
--   with nothing on screen to doubt. api_association_finance() is DEFINER for
--   exactly this reason and this follows it.
--
--   DEFINER means RLS is bypassed, so the scoping is written HERE, in the
--   first statement of the body: a member may ask about himself and nobody
--   else. Staff may ask about any man, because the register is theirs to read
--   already. Anyone else is refused outright rather than given zeros.
--
-- ⚠ AND IT RETURNS NO NAME, NO RECEIPT AND NO ROW — only sums and counts. A
--   member learns what the fund did, never who did what inside it. Who
--   received what is a separate question, answered by api_aid_others under a
--   policy the association widened on purpose.
CREATE OR REPLACE FUNCTION public.api_member_value(p_adeel_id bigint)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $mv$
DECLARE
  v_me   bigint := public.my_adeel_id();
  v_role app_role := public.my_role();
  v_out  jsonb;
BEGIN
  IF v_role IS NULL AND v_me IS DISTINCT FROM p_adeel_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;
  IF v_role IS NULL AND v_me IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  SELECT jsonb_build_object(
    -- ── HIS SIDE ────────────────────────────────────────────────────────
    -- What he has actually PAID, not what he was billed: the question is
    -- what left his hand.
    'paid', (SELECT coalesce(sum(p.amount), 0)::numeric(12,2)::text
               FROM public.payments p
              WHERE p.adeel_id = p_adeel_id AND p.status <> 'ملغي'),
    'received', (SELECT coalesce(sum(d.amount), 0)::numeric(12,2)::text
                   FROM public.disbursements d
                  WHERE d.payee_adeel_id = p_adeel_id
                    AND d.status <> 'ملغي'),

    -- ── THE FUND ────────────────────────────────────────────────────────
    'collected', (SELECT coalesce(sum(c.amount), 0)::numeric(12,2)::text
                    FROM public.cash_movements c WHERE c.status <> 'ملغي'),
    -- Everything given to NAMED members. Collective spending (فطور رمضان) is
    -- excluded on purpose: this figure answers «how much of the fund comes
    -- back to a man», and a shared meal comes back to everyone at once.
    'toMembers', (SELECT coalesce(sum(d.amount), 0)::numeric(12,2)::text
                    FROM public.disbursements d
                   WHERE d.payee_adeel_id IS NOT NULL
                     AND d.status <> 'ملغي'),

    -- ── THE STATISTICS THAT ANSWER «ما الجدوى» ──────────────────────────
    -- How many men the fund has actually stood behind, out of how many pay
    -- into it. One ratio, no prose.
    'helped', (SELECT count(DISTINCT d.payee_adeel_id)
                 FROM public.disbursements d
                WHERE d.payee_adeel_id IS NOT NULL AND d.status <> 'ملغي'),
    'members', (SELECT count(*) FROM public.adeels),
    -- ⚠ THE INSURANCE FIGURE, and the most useful number on the screen: the
    --   largest single voucher the association has ever written to one man.
    --   «هذا ما تقف خلفه الجمعية إن نزلت بك نازلة» is what a member is
    --   actually buying, and no average says it.
    'largest', (SELECT coalesce(max(d.amount), 0)::numeric(12,2)::text
                  FROM public.disbursements d
                 WHERE d.payee_adeel_id IS NOT NULL AND d.status <> 'ملغي')
  ) INTO v_out;

  RETURN v_out;
END $mv$;

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
    -- الصرف الجماعي. SECURITY INVOKER، فالسياسة هي التي تقرّر ماذا يرى
    -- المستدعي، وإسقاط read_collective_disbursements يعيدها خاوية وحدها.
    'api_aid_others(bigint)',
    -- جدوى العضوية. SECURITY DEFINER لأن أرقام الجمعية ليست في متناول
    -- المشترك، والنطاق مكتوب في أوّل جسدها: يسأل عن نفسه لا عن غيره.
    'api_member_value(bigint)'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- == 3. لا صرف بتاريخ لم يأتِ بعد =========================================
-- ⚠ THE ASSOCIATION FOUND THIS, and the way it showed itself is worth
--   recording: a voucher was entered dated TOMORROW, and the member reported
--   it as missing from his ledger. It was not missing. The ledger is ordered
--   OLDEST FIRST — that is what makes its running-total column mean anything —
--   so a voucher dated tomorrow sorts LAST and sits at the bottom of the list,
--   below everything, where nobody looking at the top of a screen finds it.
--
--   The date is also simply wrong. Money cannot leave a treasury on a day
--   that has not happened, and every figure derived from spent_at — the
--   yearly breakdown, the running total, the report ranges — inherits the
--   error quietly.
--
-- ⚠ A TRIGGER RATHER THAN A CHECK CONSTRAINT, and not by preference:
--   Postgres refuses a CHECK that calls now(), because a constraint must be
--   immutable and «today» is not. A BEFORE trigger is the only form that can
--   ask what day it is — and it guards EVERY path into the table, not just
--   register_disbursement.
--
-- ⚠ AND THE DAY IS LIBYA’S, NOT UTC. Supabase runs its sessions in UTC, and
--   Tripoli is two hours ahead — so between 22:00 and midnight local, UTC is
--   still on yesterday. Comparing against a UTC date would refuse a voucher
--   dated correctly for TODAY, every night, for two hours. The association
--   would meet that as «التطبيق يرفض التاريخ الصحيح» and nobody would connect
--   it to a timezone.
CREATE OR REPLACE FUNCTION public.disb_refuse_future()
RETURNS trigger LANGUAGE plpgsql AS $future$
BEGIN
  IF (NEW.spent_at AT TIME ZONE 'Africa/Tripoli')::date
     > (now() AT TIME ZONE 'Africa/Tripoli')::date THEN
    RAISE EXCEPTION 'لا يمكن تسجيل صرف بتاريخ لم يأتِ بعد'
      USING ERRCODE = 'RUL17';
  END IF;
  RETURN NEW;
END $future$;

-- ⚠ NOT CLIENT-CALLABLE, AND THIS REVOKE IS WHY THE PATCH ONCE ROLLED BACK.
--   A trigger function is called by Postgres, never by a client, so it is
--   deliberately absent from the allow-list. But it is created FRESH, and a
--   fresh function gets the built-in default — EXECUTE to PUBLIC — with
--   Supabase's ALTER DEFAULT PRIVILEGES layering anon on top. The first
--   version of this file created it AFTER the lockdown sweep, so the sweep
--   never saw it, and assert_function_grants() refused the whole patch with
--   «callable by anon/authenticated but not on the allow-list:
--   disb_refuse_future()». The guard was right; the ORDER was wrong.
REVOKE EXECUTE ON FUNCTION public.disb_refuse_future()
  FROM PUBLIC, anon, authenticated, service_role;

-- INSERT and UPDATE both: a correction that moved the date forward would
-- otherwise walk straight past a rule that only watched new rows.
DROP TRIGGER IF EXISTS trg_disb_no_future ON public.disbursements;
CREATE TRIGGER trg_disb_no_future
  BEFORE INSERT OR UPDATE OF spent_at ON public.disbursements
  FOR EACH ROW EXECUTE FUNCTION public.disb_refuse_future();

-- ⚠ ROWS ALREADY ENTERED ARE LEFT ALONE. A trigger judges what is written
--   from now on; it does not rewrite history, and rule 9 would not want it to.
--   The association can correct a wrong date by reversing the voucher and
--   recording it again — which is the same path every other correction takes,
--   and leaves both halves visible.

-- == 3b. المسحة، وموضعها ليس اعتباطاً ======================================
-- ⚠ AFTER THE LAST CREATE IN THIS FILE, and that is the whole rule. On a full
--   apply, 20260811091200_function_lockdown.sql runs LAST and normalises every
--   grant in the schema, so nothing else has to think about privileges. A
--   patch gets no such pass — it has to carry the sweep itself, and a sweep
--   that runs before the file has finished creating things is a sweep that
--   missed something.
--
--   It recomputes every grant from the allow-list, so it also fixes the NEXT
--   function anybody adds — provided that function is added above this line.
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

-- == 4. Confirmation ========================================================
-- Read-only. Every row must say true.
SELECT 'سياسة الصرف الجماعي قائمة' AS "الفحص",
       EXISTS (SELECT 1 FROM pg_policies
                WHERE schemaname='public' AND tablename='disbursements'
                  AND policyname='read_collective_disbursements'
                  AND qual LIKE '%payee_adeel_id IS NULL%') AS "النتيجة"
-- ⚠ AND THE WIDE ONE IS GONE. This is the row that matters if the earlier
--   draft of this file was ever applied: it proves the policy that let a
--   member read another man's aid is no longer there.
UNION ALL SELECT 'ولا يقرأ مشتركٌ سلف مشتركٍ آخر',
       NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='disbursements'
                      AND policyname='read_all_disbursements_adeel')
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
UNION ALL SELECT 'ولا يُقبل صرف بتاريخ لم يأتِ بعد',
       EXISTS (SELECT 1 FROM pg_trigger t
                JOIN pg_class c ON c.oid = t.tgrelid
               WHERE c.relname = 'disbursements'
                 AND t.tgname = 'trg_disb_no_future')
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
