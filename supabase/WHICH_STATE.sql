-- ============================================================================
--  WHICH_STATE.sql — which schema, and which patches, does this project hold?
--
--  READ-ONLY. It creates nothing, drops nothing and writes nothing. Safe to run
--  on the live project as often as you like.
--
--  HOW TO USE
--    Supabase dashboard → SQL Editor → New query → paste all of this → Run.
--    Read the last row, ‹‹ VERDICT ››. It says what to do next.
--
--  WHY THIS EXISTS, BESIDE VERIFY_INSTALL.sql
--    VERIFY_INSTALL answers "did the BUNDLE land" — it holds a fixed list of the
--    tables, views and functions the 16/08 schema was supposed to contain, and
--    every row must say OK. It cannot answer the question a PATCH raises, which
--    is a different one: "how far along is this project?" A database that is one
--    patch behind passes VERIFY_INSTALL completely — nothing on its list is
--    missing — and is still the wrong place to paste the next patch into.
--
--    That distinction is not theoretical here. PATCH_20260817 was written
--    against a database that already had public.disbursements, so the ordering
--    bug in it (a VIEW resolves its table references at CREATE time, a plpgsql
--    function does not) could not fire during testing and appeared only on a
--    database that really was one patch behind. The lesson recorded in that
--    file's header — "a patch has to be tested against the schema it is FOR" —
--    starts with knowing which schema that is, and the app cannot tell you: an
--    old schema, a missing patch and a missing bootstrap all present the same
--    way, as a login screen that goes nowhere.
--
--  ⚠ WHY EVERY COUNT GOES THROUGH query_to_xml() INSTEAD OF BEING WRITTEN OUT
--    A plain `SELECT count(*) FROM public.adeels` is resolved when the statement
--    is PARSED, so on a project that does not have that table the whole script
--    dies with 42P01 — on precisely one of the states it exists to name. CASE
--    does not save it: the branch not taken is parsed too. query_to_xml takes
--    its query as a STRING, so nothing is resolved until it runs, and the CASE
--    around it means it never runs unless to_regclass() just proved the table is
--    there. Ugly, and the only form that survives every state.
--
--  THE ORDER OF THE CHECKS IS THE ORDER OF THE DEPENDENCIES.
--    Each patch assumes the one before it. The VERDICT stops at the FIRST thing
--    missing rather than listing everything, because applying a later patch to a
--    database missing an earlier one is the failure this is here to prevent.
-- ============================================================================

WITH have AS (
  SELECT
    -- ── Which schema generation this is ─────────────────────────────────────
    -- `families` existing means the project is still on the pre-adeel shape — a
    -- different database for practical purposes, and nothing below applies.
    to_regclass('public.adeels')        IS NOT NULL AS adeel_schema,
    to_regclass('public.families')      IS NOT NULL AS old_family_schema,
    to_regclass('public.profiles')      IS NOT NULL AS has_profiles,

    -- ── PATCH 16/08 — the payer's bank details on a payment ─────────────────
    -- Probed by a COLUMN, not by a function name: CREATE OR REPLACE leaves a
    -- name in place whether or not the body was updated, so a name proves
    -- nothing about which version is installed. A column is added once.
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='payments'
               AND column_name='bank_account_name')                AS patch_0816,

    -- ── PATCH 17/08, probed in FOUR places rather than one ──────────────────
    -- The patch is one transaction, so a partial apply is impossible — but a
    -- project patched by hand, or from an older copy of the file, is not, and
    -- each of these is a separate section of it.
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='profiles'
               AND column_name='device_id')                        AS device_lock,
    to_regclass('public.disbursements') IS NOT NULL                AS money_out,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='register_disbursement')   AS spend_rpc,
    EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='api_association_finance') AS assoc_finance,

    -- ── The three 18/08 patches, each probed by an object it ADDS ───────────
    -- A function NAME proves nothing (every one of these existed before under
    -- the same name), so each probe names something that comes into existence
    -- exactly once: a function signature, a generated column's shape, a view
    -- column.
    to_regprocedure('public.api_adeel_aid(bigint)') IS NOT NULL     AS patch_18a,
    -- A-0004 → A-04. Read off the column's own expression rather than off a
    -- row, so it answers on an empty register too.
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='adeels'
               AND column_name='adeel_code'
               AND generation_expression LIKE '%CASE%')             AS patch_18b,
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='v_cash_summary'
               AND column_name='heldForMembers')                    AS patch_18c,
    -- The room. Probed by the TABLE rather than by a function name: every
    -- function this patch touches already existed under some name, and a table
    -- comes into existence exactly once.
    to_regclass('public.chat_messages') IS NOT NULL                  AS patch_19,
    -- ⚠ AND THE COLUMN THAT MAKES IT TWO ROOMS. The table alone was the probe
    --   once, and a project holding the FIRST shape passed it while the portal
    --   showed 42703. A table name is not a version.
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='chat_messages'
               AND column_name='thread_adeel_id')                     AS patch_20,
    -- الصرف الجماعي. The POLICY, not the function: the function is what a
    --   member calls, the policy is what answers him, and CREATE OR REPLACE
    --   leaves a function's NAME standing whatever its body says.
    --
    -- ⚠ AND THE NAME CHANGED WITH THE RULE. An earlier draft of that patch
    --   created read_all_disbursements_adeel — every voucher, by name. The
    --   association chose the COLLECTIVE spending instead, so the patch now
    --   drops that one and creates read_collective_disbursements. Probing the
    --   old name here answered «NOT applied» for a patch that had just landed
    --   correctly, and the VERDICT then asked for it again, forever. A probe
    --   is a version claim: rewrite the patch and the probe is stale too.
    EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname='public' AND tablename='disbursements'
               AND policyname='read_collective_disbursements')        AS patch_20b,
    -- ⚠ AND THE WIDE ONE MUST BE GONE. This is not a patch level, it is a
    --   privacy guarantee: while that policy stands, every مشترك reads every
    --   other man's إعانة by name. Its own row, because a schema can hold both
    --   policies at once and «applied» would then hide it.
    EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname='public' AND tablename='disbursements'
               AND policyname='read_all_disbursements_adeel')         AS aid_by_name,
    -- حركة المشترك على اثني عشر شهراً. Probed by generate_series in the body of
    -- api_member_value — the month spine, which nothing else in that function
    -- has any reason to contain.
    coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%generate_series%'
                FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname = 'api_member_value'),
             false)                                                AS patch_24,
    -- المسح لا يترك مشتركاً خارج تطبيقه. Probed by the backfill it adds to
    -- purge_all_data, not by the profiles table — that has always been there.
    coalesce((SELECT p.prosrc LIKE '%INSERT INTO public.profiles%'
                FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname = 'purge_all_data'),
             false)                                                AS patch_23,
    -- التاريخ من ساعة الخادم. Probed by the trigger it INSTALLS rather than
    -- by the one it removes: «the old thing is gone» is also true of a project
    -- that never had either.
    EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
             WHERE c.relname='disbursements'
               AND t.tgname='trg_disb_stamp_time')                 AS patch_22,
    -- اشتراك يختلف باختلاف الشهر. Probed by the COLUMN it adds.
    --
    -- ⚠ association_settings, NOT settings. There is no public.settings in
    --   this schema and there never was — so this probe could only ever
    --   answer false, reporting the patch as missing however many times it
    --   was applied. The identical wrong name was in the patch itself, where
    --   it aborted on the first statement; here it said nothing and lied.
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='association_settings'
               AND column_name='fee_exceptions')                     AS patch_21,

    -- ── ACCESS, which is not schema and is lost independently of it ─────────
    -- The 16/08 reset kept auth.users and dropped public.profiles, so signing in
    -- still succeeded and then found no role. Zero approved admins is that state.
    CASE WHEN to_regclass('public.profiles') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.profiles
            WHERE role = 'admin' AND status = 'approved'$q$,
        false, true, '')))[1]::text::bigint END                    AS admins,

    -- ── HOW MUCH IS ACTUALLY AT STAKE ───────────────────────────────────────
    -- The device lock is the one section of PATCH 17/08 with a blast radius, and
    -- this is its size. Every عديل already bound to a portal profile is locked
    -- out until a build that sends the `x-device-id` header opens the app on his
    -- handset — a build made before that header existed never claims the device,
    -- so he sees an empty portal and nothing tells him why. Zero here means the
    -- lock costs nothing today and the patch can go in on its own.
    CASE WHEN to_regclass('public.profiles') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.profiles WHERE adeel_id IS NOT NULL$q$,
        false, true, '')))[1]::text::bigint END                    AS portal_users,

    -- The ledger, for the same reason: it says whether this is a project still
    -- being set up or one the association is already keeping books in.
    CASE WHEN to_regclass('public.adeels') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.adeels$q$, false, true, '')))[1]::text::bigint
      END                                                          AS n_adeels,
    CASE WHEN to_regclass('public.payments') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.payments$q$, false, true, '')))[1]::text::bigint
      END                                                          AS n_payments
)
SELECT * FROM (
  SELECT 1 AS ord, 'المخطط' AS item,
         CASE WHEN old_family_schema
                THEN 'OLD family/member schema — the adeel bundle was never run here'
              WHEN adeel_schema
                THEN 'adeel schema present'
              ELSE 'EMPTY — no schema at all' END AS answer FROM have
  UNION ALL SELECT 2, 'PATCH 16/08 — تفاصيل حساب الدافع',
         CASE WHEN patch_0816    THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 3, 'PATCH 17/08 §1-6 — قفل الجهاز',
         CASE WHEN device_lock   THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 4, 'PATCH 17/08 §9 — جدول الصرف',
         CASE WHEN money_out     THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 5, 'PATCH 17/08 §12 — دالتا الصرف والإلغاء',
         CASE WHEN spend_rpc     THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 6, 'PATCH 17/08 §11 — مالية الجمعية للعديل',
         CASE WHEN assoc_finance THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 7, 'PATCH 18/08 (a) — ما صُرف للمشترك',
         CASE WHEN patch_18a THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 8, 'PATCH 18/08 (b) — الترقيم القصير A-05 / PAY-01',
         CASE WHEN patch_18b THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 9, 'PATCH 18/08 (c) — عهد المشتركين',
         CASE WHEN patch_18c THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 10, 'PATCH 19/08 — مجلس العدايل (الدردشة)',
         CASE WHEN patch_19 THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 10.1, 'PATCH 20/08 — الغرفتان (المحادثة الخاصة)',
         CASE WHEN patch_20 THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 10.2, 'PATCH 20/08 (b) — أسلاف للغير (الصرف الجماعي)',
         CASE WHEN patch_20b THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 10.21, 'خصوصية الأسلاف',
         CASE WHEN aid_by_name
                THEN '⚠ مكشوفة بالأسماء — PATCH_20260820b يُغلقها'
              ELSE 'مصونة — لا يقرأ مشتركٌ سلف مشتركٍ آخر' END FROM have
  UNION ALL SELECT 10.3, 'PATCH 21/08 — اشتراك يختلف باختلاف الشهر',
         CASE WHEN patch_21 THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 10.4, 'PATCH 22/08 — التاريخ بساعة الخادم',
         CASE WHEN patch_22 THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 10.5, 'PATCH 23/08 — المسح يُبقي الدخول ممكناً',
         CASE WHEN patch_23 THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 10.6, 'PATCH 24/08 — حركة المشترك (رسم الجدوى)',
         CASE WHEN patch_24 THEN 'applied' ELSE 'NOT applied' END FROM have
  UNION ALL SELECT 11, 'مدير معتمد',
         CASE WHEN NOT has_profiles THEN 'no profiles table'
              WHEN admins > 0 THEN admins::text || ' — sign-in works'
              ELSE 'NONE — run bootstrap_first_admin.sql' END FROM have
  UNION ALL SELECT 12, 'عدايل مرتبطون بالبوابة (نطاق أثر قفل الجهاز)',
         CASE WHEN NOT has_profiles THEN 'unknown'
              WHEN portal_users = 0
                THEN '0 — the device lock locks nobody out today'
              ELSE portal_users::text ||
                   ' — each needs a build that sends x-device-id, or he sees an empty portal'
         END FROM have
  UNION ALL SELECT 13, 'السجل',
         CASE WHEN NOT adeel_schema THEN 'unknown'
              ELSE coalesce(n_adeels, 0)::text || ' عديل، '
                || coalesce(n_payments, 0)::text || ' إيصال' END FROM have
  UNION ALL SELECT 14, '‹‹ VERDICT ››',
         -- In dependency order, and it names ONE file rather than listing what
         -- is missing — a list invites picking from it. Each patch was tested
         -- against the state the one before it leaves, and only against that
         -- state, so "which is missing" and "which to apply next" are not the
         -- same question.
         CASE WHEN NOT adeel_schema
                THEN 'STOP — this is not the adeel schema. Do NOT apply any patch.'
              WHEN NOT patch_0816
                THEN 'STOP — PATCH_20260816_payer_bank_details.sql is missing. Apply that first.'
              WHEN NOT (device_lock AND money_out AND spend_rpc AND assoc_finance)
                THEN 'READY — apply supabase/PATCH_20260817_device_lock.sql'
              WHEN NOT patch_18a
                THEN 'READY — apply supabase/PATCH_20260818_adeel_aid.sql'
              WHEN NOT patch_18b
                THEN 'READY — apply supabase/PATCH_20260818b_short_codes.sql'
              WHEN NOT patch_18c
                THEN 'READY — apply supabase/PATCH_20260818c_member_holdings.sql'
                  || '  ⚠ رصيد الجمعية سينخفض بمقدار عهد المشتركين — وهو تصحيح لا خلل.'
              WHEN NOT patch_19
                THEN 'READY — apply supabase/PATCH_20260819_chat.sql'
              WHEN NOT patch_20
                THEN 'READY — apply supabase/PATCH_20260820_chat_threads.sql'
              -- OR, not just NOT: a project holding the old wide policy needs
              -- this patch even if the new policy is somehow already there.
              WHEN NOT patch_20b OR aid_by_name
                THEN 'READY — apply supabase/PATCH_20260820b_aid_transparency.sql'
                  || '  ⚠ يعرض الصرف الجماعي للمشترك، ويُغلق كشف أسلاف الآخرين بالأسماء.'
              WHEN NOT patch_21
                THEN 'READY — apply supabase/PATCH_20260821_fee_exceptions.sql'
              WHEN NOT patch_22
                THEN 'READY — apply supabase/PATCH_20260822_server_clock.sql'
                  || '  ⚠ التاريخ يصير من ساعة الخادم، ويسقط الإدخال اليدوي له.'
              -- ⚠ 23/08 BEFORE 24/08 and both after the clock: this one is the
              -- only patch on the chain that un-strands people who are locked
              -- out RIGHT NOW, so it never waits behind a chart.
              WHEN NOT patch_23
                THEN 'READY — apply supabase/PATCH_20260823_purge_keeps_signin.sql'
                  || '  ⚠ يفكّ كل مشترك عَلِق بعد المسح.'
              WHEN NOT patch_24
                THEN 'READY — apply supabase/PATCH_20260824_member_months.sql'
              ELSE 'UP TO DATE — every patch through 24/08 is applied.'
         END FROM have
) t ORDER BY ord;
