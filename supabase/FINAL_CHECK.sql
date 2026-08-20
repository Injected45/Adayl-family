-- ============================================================================
--  FINAL_CHECK.sql — هل نزل كل شيء، وهل يعمل فعلاً، وهل البيانات نظيفة؟
--
--  READ-ONLY. لا ينشئ ولا يحذف ولا يعدّل صفاً واحداً. آمنٌ على المشروع الحيّ
--  مهما تكرّر.
--
--  HOW TO USE
--    SQL Editor → New query → الصق هذا كلّه → Run → اقرأ آخر سطر «‹‹ الحكم ››».
--
--  WHY THIS, BESIDE WHICH_STATE.sql
--    WHICH_STATE answers «هل نزل الترقيع» — it probes each patch by one object
--    it adds. That is a question about SCHEMA, and a schema can be complete
--    while the thing it was for does not work: a policy present but scoped
--    wrongly, a function present but carrying the old body, a trigger present
--    but on the wrong event. This asks the second question — «وهل يفعل ما كُتب
--    له» — by reading the POLICY EXPRESSION and the FUNCTION BODY rather than
--    the name.
--
--  ⚠ AND IT ASKS A THIRD QUESTION NOTHING ELSE ASKS: is the DATA clean? A
--    voucher dated in the future and an عديل holding two portal profiles are
--    both invisible to every schema check ever written, and both were found the
--    hard way — a member reporting money missing that was not missing.
--
--  ⚠ ONE STATEMENT, on purpose. The Supabase SQL Editor renders only the LAST
--    result set, so a file of several SELECTs shows one table and hides the
--    rest. Everything below is a single UNION ALL.
--
--  ⚠ AND EVERY COUNT GOES THROUGH query_to_xml(). A plain count is resolved at
--    PARSE time, so on a project missing the table the whole script dies with
--    42P01 — on precisely one of the states it exists to name. CASE does not
--    save it: the branch not taken is parsed too.
-- ============================================================================

WITH have AS (
  SELECT
    -- ── أين نحن ─────────────────────────────────────────────────────────────
    to_regclass('public.adeels')        IS NOT NULL AS has_adeels,
    to_regclass('public.disbursements') IS NOT NULL AS has_disb,

    -- ── PATCH 20/08 (b) — الصرف الجماعي ────────────────────────────────────
    -- ⚠ THE POLICY EXPRESSION, not the policy name. A policy called
    --   read_collective_disbursements that had lost `payee_adeel_id IS NULL`
    --   would hand every member every voucher by name, and a check on the name
    --   alone would report it as correct.
    EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname='public' AND tablename='disbursements'
               AND policyname='read_collective_disbursements'
               AND qual LIKE '%payee_adeel_id IS NULL%')          AS pol_collective,
    EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname='public' AND tablename='disbursements'
               AND policyname='read_all_disbursements_adeel')     AS pol_by_name,
    EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname='public' AND tablename='disbursements'
               AND policyname='read_own_disbursements')           AS pol_own,
    -- ⚠ AND THE FUNCTION BODY. CREATE OR REPLACE leaves the name standing
    --   whatever the body says, so a name proves nothing about the version.
    coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%payee_adeel_id IS NULL%'
                FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='api_aid_others'),
             false)                                               AS fn_collective,
    coalesce((SELECT p.prosecdef
                FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='api_member_value'),
             false)                                               AS fn_value_definer,

    -- ── الختم: التاريخ من ساعة الخادم لا من الجهاز ─────────────────────────
    -- ⚠ A STAMP, NOT A REFUSAL, and the difference is the whole rule. The
    --   20/08 trigger REFUSED a future date, which left a PAST one accepted —
    --   a mistyped year, a phone a week behind, or a voucher pushed back into
    --   a closed month all still went through. 22/08 overwrites spent_at with
    --   now() instead, so the client has no date to be wrong about.
    --
    -- INSERT **and** UPDATE OF the column: without the second half, moving a
    -- date afterwards would walk past a rule that only watched new rows. In
    -- pg_trigger.tgtype, bit 4 is INSERT and bit 16 is UPDATE.
    coalesce((SELECT (t.tgtype & 4) > 0 AND (t.tgtype & 16) > 0
                FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
               WHERE c.relname='disbursements' AND t.tgname='trg_disb_stamp_time'),
             false)                                               AS trg_stamp_disb,
    coalesce((SELECT (t.tgtype & 4) > 0 AND (t.tgtype & 16) > 0
                FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
               WHERE c.relname='payments' AND t.tgname='trg_pay_stamp_time'),
             false)                                               AS trg_stamp_pay,
    -- ⚠ AND THE OLD REFUSE-ONLY GUARD MUST BE GONE, not merely superseded. Two
    --   triggers on one column both fire, and the old one would refuse a stamp
    --   the new one had just written whenever the two crossed a day boundary.
    NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                 WHERE n.nspname='public' AND p.proname='disb_refuse_future')
                                                                  AS old_guard_gone,
    -- The clock everything now depends on, printed rather than assumed.
    to_char(now() AT TIME ZONE 'Africa/Tripoli', 'YYYY-MM-DD HH24:MI')
                                                                  AS server_clock,

    -- ── PATCH 21/08 — ماعدا ────────────────────────────────────────────────
    EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='association_settings'
               AND column_name='fee_exceptions')                  AS col_fee_exc,
    EXISTS (SELECT 1 FROM pg_constraint
             WHERE conname='ck_settings_fee_exceptions')          AS ck_fee_exc,
    -- The three bodies that have to agree, each READ rather than trusted.
    coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%fee_exceptions%'
                FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='generate_period'),
             false)                                               AS gen_reads_exc,
    coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%feeExceptions%'
                FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='update_settings'),
             false)                                               AS upd_takes_exc,
    coalesce((SELECT pg_get_functiondef(p.oid) LIKE '%feeExceptions%'
                FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='api_settings'),
             false)                                               AS api_returns_exc,

    -- ── ولا كتابة على السندات، البتة ───────────────────────────────────────
    NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='disbursements'
                   AND cmd <> 'SELECT')                           AS no_write_policy,

    -- ── الأرقام، لتقارنها بما يظهر في التطبيق ──────────────────────────────
    CASE WHEN to_regclass('public.adeels') IS NULL THEN '—' ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.adeels$q$,
        false, true, '')))[1]::text END                           AS n_adeels,
    CASE WHEN to_regclass('public.disbursements') IS NULL THEN '—' ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*)::text || ' سند، مجموعها '
                || coalesce(sum(amount), 0)::numeric(12,2)::text AS c
             FROM public.disbursements
            WHERE payee_adeel_id IS NULL AND status <> 'ملغي'$q$,
        false, true, '')))[1]::text END                           AS collective,
    -- ⚠ GUARDED BY THE COLUMN, NOT BY THE TABLE, and the first version of this
    --   file got it wrong: it asked whether association_settings existed and
    --   then read fee_exceptions out of it, so on a project one patch behind it
    --   died with 42703 instead of REPORTING that the patch was one behind —
    --   which is the single state this row is here to name.
    --
    --   query_to_xml defers RESOLUTION to run time; it does not make a missing
    --   column stop mattering. Deferral only buys the chance to ask first. So
    --   the guard has to name the exact object the query names.
    CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                           WHERE table_schema='public'
                             AND table_name='association_settings'
                             AND column_name='fee_exceptions')
           THEN 'العمود غير موجود — الترقيع لم ينزل' ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT coalesce(
                    (SELECT fee_exceptions::text
                       FROM public.association_settings WHERE id = 1),
                    'لا يوجد صف إعدادات') AS c$q$,
        false, true, '')))[1]::text END                           AS fee_exc_now,

    -- ── النظافة ────────────────────────────────────────────────────────────
    -- ⚠ THE TRIGGER JUDGES WHAT IS WRITTEN FROM NOW ON; it does not rewrite
    --   history, and rule 9 would not want it to. So a voucher entered BEFORE
    --   it landed is still sitting there with a date that has not happened —
    --   and because the ledger is ordered OLDEST FIRST, it sorts to the BOTTOM
    --   where nobody looking at the top of a screen finds it. That is exactly
    --   how it was reported: «تم الصرف ولم يظهر عند المشترك».
    CASE WHEN to_regclass('public.disbursements') IS NULL THEN '—' ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT coalesce(string_agg(
                    voucher_no || ' — ' ||
                    to_char(spent_at AT TIME ZONE 'Africa/Tripoli', 'YYYY-MM-DD'),
                    '، ' ORDER BY spent_at), 'لا شيء') AS c
             FROM public.disbursements
            WHERE status <> 'ملغي'
              AND (spent_at AT TIME ZONE 'Africa/Tripoli')::date
                > (now()    AT TIME ZONE 'Africa/Tripoli')::date$q$,
        false, true, '')))[1]::text END                           AS future_vouchers,
    -- ⚠ ONE عديل, ONE HANDSET — but nothing stops TWO profile rows pointing at
    --   the same man. my_adeel_id() then answers for whichever row the session
    --   belongs to, so one device is bound and the other silently is not, and
    --   he sees an empty portal on a phone that signed in successfully.
    -- Guarded by the column for the same reason: a schema old enough to have
    -- no adeel_id would otherwise take the whole file down with it.
    CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                           WHERE table_schema='public' AND table_name='profiles'
                             AND column_name='adeel_id')
           THEN 'لا يمكن الفحص' ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT coalesce(string_agg(t, '، '), 'لا شيء') AS c FROM (
             SELECT 'عديل رقم ' || p.adeel_id::text
                    || ' — ' || count(*)::text || ' حسابات' AS t
               FROM public.profiles p
              WHERE p.adeel_id IS NOT NULL
              GROUP BY p.adeel_id
             HAVING count(*) > 1) x$q$,
        false, true, '')))[1]::text END                           AS dup_portals
)
SELECT * FROM (
  SELECT 1 AS ord, 'المشروع' AS "الفحص",
         CASE WHEN NOT has_adeels
                THEN 'لا سجل عدايل — مشروع خاطئ'
              ELSE n_adeels || ' عديل' END AS "النتيجة" FROM have

  UNION ALL SELECT 2, '— أسلاف للغير (الصرف الجماعي) —', '' FROM have
  UNION ALL SELECT 2.1, 'سياسة الصرف الجماعي، وشرطها صحيح',
         CASE WHEN pol_collective THEN 'نعم' ELSE 'لا' END FROM have
  UNION ALL SELECT 2.2, 'ولا يقرأ مشتركٌ سلف مشتركٍ آخر',
         CASE WHEN pol_by_name THEN 'مكشوفة بالأسماء' ELSE 'مصونة' END FROM have
  UNION ALL SELECT 2.3, 'وسياسة «سنداته هو» باقية',
         CASE WHEN pol_own THEN 'نعم' ELSE 'لا' END FROM have
  UNION ALL SELECT 2.4, 'وجسد api_aid_others يفلتر الجماعي',
         CASE WHEN fn_collective THEN 'نعم' ELSE 'جسد قديم' END FROM have
  UNION ALL SELECT 2.5, 'ولا سياسة كتابة على السندات البتة',
         CASE WHEN no_write_policy THEN 'نعم' ELSE 'توجد' END FROM have
  UNION ALL SELECT 2.6, 'ما سيراه المشترك في أسلاف للغير',
         collective FROM have

  UNION ALL SELECT 3, '— الجدوى —', '' FROM have
  UNION ALL SELECT 3.1, 'api_member_value موجودة و SECURITY DEFINER',
         CASE WHEN fn_value_definer THEN 'نعم' ELSE 'لا' END FROM have

  UNION ALL SELECT 4, '— ختم التاريخ بساعة الخادم —', '' FROM have
  UNION ALL SELECT 4.1, 'السند يُختم بساعة الخادم (إدراج وتعديل)',
         CASE WHEN trg_stamp_disb THEN 'نعم' ELSE 'لا' END FROM have
  UNION ALL SELECT 4.2, 'والإيصال كذلك',
         CASE WHEN trg_stamp_pay THEN 'نعم' ELSE 'لا' END FROM have
  UNION ALL SELECT 4.3, 'والحارس القديم أُزيل',
         CASE WHEN old_guard_gone THEN 'نعم' ELSE 'ما زال قائماً' END FROM have
  -- ⚠ COMPARE THIS WITH YOUR OWN WATCH. It is the clock every receipt and
  --   every voucher is now stamped by, and no handset can reach it.
  UNION ALL SELECT 4.4, 'ساعة الخادم بتوقيت طرابلس',
         server_clock FROM have
  UNION ALL SELECT 4.5, 'سندات قائمة بتاريخ لم يأتِ بعد',
         future_vouchers FROM have

  UNION ALL SELECT 5, '— ماعدا (اشتراك الشهر) —', '' FROM have
  UNION ALL SELECT 5.1, 'العمود fee_exceptions',
         CASE WHEN col_fee_exc THEN 'نعم' ELSE 'لا' END FROM have
  UNION ALL SELECT 5.2, 'والقيد الذي يرفض ما ليس «شهر: مبلغ»',
         CASE WHEN ck_fee_exc THEN 'نعم' ELSE 'لا' END FROM have
  UNION ALL SELECT 5.3, 'وإقفال الشهر يقرأ سعر ذلك الشهر',
         CASE WHEN gen_reads_exc THEN 'نعم' ELSE 'جسد قديم' END FROM have
  UNION ALL SELECT 5.4, 'والإعدادات تقبلها وتُعيدها',
         CASE WHEN upd_takes_exc AND api_returns_exc THEN 'نعم'
              ELSE 'جسد قديم' END FROM have
  UNION ALL SELECT 5.5, 'المقرّر الآن',
         fee_exc_now FROM have

  UNION ALL SELECT 6, '— نظافة البيانات —', '' FROM have
  UNION ALL SELECT 6.1, 'عدايل بأكثر من حساب بوابة',
         dup_portals FROM have

  UNION ALL SELECT 9, '‹‹ الحكم ››',
         -- ⚠ SCHEMA FIRST, DATA SECOND, and never the other way round. A wrong
         --   date is corrected from inside the app in a minute; a missing
         --   policy is a wrong answer on a member's screen that nothing on that
         --   screen tells him to doubt.
         CASE WHEN NOT has_adeels
                THEN 'قف — مشروع خاطئ. لا تُشغّل أيّ ترقيع هنا.'
              WHEN NOT has_disb
                THEN 'قف — لا جدول صرف. طبّق PATCH_20260817_device_lock.sql'
              WHEN pol_by_name OR NOT pol_collective OR NOT fn_collective
                THEN 'طبّق supabase/PATCH_20260820b_aid_transparency.sql'
              WHEN NOT (col_fee_exc AND ck_fee_exc AND gen_reads_exc
                        AND upd_takes_exc AND api_returns_exc)
                THEN 'طبّق supabase/PATCH_20260820c_fee_exceptions.sql'
              WHEN NOT (trg_stamp_disb AND trg_stamp_pay AND old_guard_gone)
                THEN 'طبّق supabase/PATCH_20260820d_server_clock.sql'
              WHEN future_vouchers <> 'لا شيء'
                THEN 'القاعدة سليمة — يبقى تصحيح السندات المؤرَّخة في المستقبل،'
                  || ' بإلغاء كلٍّ منها وإعادة تسجيله بتاريخه الصحيح.'
              WHEN dup_portals NOT IN ('لا شيء', 'لا يمكن الفحص')
                THEN 'القاعدة سليمة — يبقى عديلٌ بأكثر من حساب بوابة.'
              ELSE 'كل شيء سليم ونظيف. انتقل.'
         END FROM have
) t ORDER BY ord;
