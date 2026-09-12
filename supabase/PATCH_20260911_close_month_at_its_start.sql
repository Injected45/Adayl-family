-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-11.  الشهر يُقفل من أوّل يومٍ فيه، لا بعد انتهائه.
--
--  ما الذي يفعله هذا الملف
--    كان الإقفال لا يقبل إلّا شهرًا انتهى، فبقي سبتمبر — وماله في الخزينة —
--    غيرَ ظاهرٍ في شاشة الإقفال، وأحدثُ ما أمام أمين الصندوق أغسطس. صار الشهر
--    قابلًا للإقفال من أوّل يومٍ فيه: سبتمبر اليوم، وأكتوبر في الأوّل من أكتوبر.
--
--  ⚠ الشهرُ القادم ما زال مرفوضًا، وهذا هو النصف الباقي من القاعدة. التغيير
--    حرفٌ واحد — >= صارت > — والفرق بينهما هو الفرق بين «هذا الشهر» و«أيّ شهرٍ
--    إلى الأبد».
--
--  ⚠ وأربعُ دوالّ تتغيّر لا واحدة، لأنّ أربعةً كانت تجيب عن سؤالٍ واحد:
--      generate_period        — مَن يرفض ومَن يقبل (القاعدة نفسها)
--      api_closable_periods   — ما تعرضه الشاشة
--      auto_close_periods     — «أقفل كلّ ما فات»
--      api_dashboard          — «الشهر الذي يُقفل الآن» في اللوحة
--    لو غُيّرت واحدةٌ وتُركت البواقي، لرفض الزرُّ ما تقبله الدالّة، وهو أسوأ من
--    أن يرفض الاثنان. وapi_dashboard لم يعد يحسب الشهر من التقويم أصلًا — صار
--    يسأل نفسَ السؤال: أقدمُ شهرٍ ما زال مفتوحًا.
--
--  ⚠ لا يُكتب صفٌّ واحد. لا استحقاق، ولا إيصال، ولا إقفال. هذا الملفّ يقرّر ما
--    يُسمح به غدًا فقط، ولا يمسّ دينارًا اليوم.
--
--  ⚠ ولا مسحةَ صلاحيّات هنا وهي ليست سهوًا: الدوالُّ الأربعُ موجودةٌ كلُّها،
--    وCREATE OR REPLACE يُبقي صلاحيّاتِها كما هي. المسحة تلزم دالّةً وُلدت
--    جديدةً فحسب.
--
--  كيفيّة التطبيق
--    SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.generate_period(character)') IS NULL THEN
    RAISE EXCEPTION 'لا توجد generate_period(character) — هذا ليس مشروع الجمعية.';
  END IF;
END $prereq$;

-- == 1. القاعدة نفسها ======================================================
CREATE OR REPLACE FUNCTION public.generate_period(p_period character)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  s           record;
  a           record;
  v_end       date;
  -- ⚠ THE FEE FOR THIS MONTH, WHICH IS NOT ALWAYS THE MONTHLY FEE.
  --   The association agreed that some calendar months carry a different
  --   subscription — يناير and يونيو at 200 while the rest stay at 100 — so the
  --   figure a receivable is raised at is looked up per month and only falls
  --   back to member_fee when that month has no exception.
  --
  --   Keyed by CALENDAR month ('01'..'12'), not by period, and deliberately: the
  --   agreement is «January is 200», not «January 2026 is 200». It holds every
  --   year until the association changes it.
  v_fee       numeric(12,2);
  v_recv_id   bigint;
  v_created   int := 0;
  v_skipped   int := 0;
  -- How much prepaid credit this close consumed. Reported so a treasurer can
  -- see that a month billed 800 and settled 300 of it from wallets on the
  -- spot, rather than wondering why the total debt moved less than he expected.
  v_applied   numeric(12,2) := 0;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'BAD_PERIOD: %', p_period USING ERRCODE = 'RUL04';
  END IF;

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_end := (to_date(p_period || '-01', 'YYYY-MM-DD')
            + interval '1 month - 1 day')::date;

  -- ── Rule 15c: only a month inside the association's own range ─────────────
  -- Before system_start the books did not exist, and a month that has not begun
  -- cannot be billed. Both ends were previously unguarded — the picker simply
  -- did not offer them, which protects the button and not the RPC, and the RPC
  -- is what a hostile client calls.
  --
  -- ⚠ THE CURRENT MONTH IS NOW CLOSABLE, AND THAT REVERSES THE OLD RULE.
  --   This used to refuse any month that had not ENDED, on the reasoning that
  --   closing a running month "bills for time nobody has lived through". That
  --   reasoning was borrowed from payroll and it is wrong for this association:
  --   the اشتراك is not earned over the month, it is DUE at its start, and the
  --   منظومة it replaces billed the same way — سبتمبر was raised on 6 September
  --   and four men had paid it before the month was half over.
  --
  --   The cost of the old rule was not theoretical. Every September the
  --   treasurer opened الإقفال, saw أغسطس as the newest month, and had no way
  --   to record a month whose money was already in the safe: «موجود امامي الا
  --   اخر اقفال شهر اغسطس». The charge existed in fact and not in the ledger.
  --
  -- ⚠ A month is now closable ON ITS FIRST DAY. NEXT month is still refused,
  --   and that half is what still matters: > not >=, one character, and the
  --   whole difference between «this month» and «any month forever».
  IF p_period < to_char(s.system_start, 'YYYY-MM') THEN
    RAISE EXCEPTION 'PERIOD_BEFORE_SYSTEM_START: %', p_period
      USING ERRCODE = 'RUL15';
  END IF;
  IF p_period > to_char(current_date, 'YYYY-MM') THEN
    RAISE EXCEPTION 'PERIOD_IN_THE_FUTURE: %', p_period USING ERRCODE = 'RUL15';
  END IF;

  -- ── Rule 15a: a month is closed ONCE ──────────────────────────────────────
  -- Rule 4 already made a SECOND receivable for the same (عديل, period)
  -- impossible, so re-running was harmless — it simply created nothing and
  -- reported "0 created". Harmless is not the same as meaningful: a treasurer
  -- reading "0 created" cannot tell "already done" from "nothing to do", and the
  -- audit trail grew an entry for a close that closed nothing. Refusing says
  -- which it was.
  IF EXISTS (SELECT 1 FROM public.closed_periods WHERE period = p_period) THEN
    RAISE EXCEPTION 'PERIOD_ALREADY_CLOSED: %', p_period USING ERRCODE = 'RUL15';
  END IF;

  -- ── Rule 15b: months close IN ORDER, oldest first ─────────────────────────
  -- Closing August while July was never closed leaves a hole that nothing later
  -- reveals: the register looks complete, every receipt reconciles, and the
  -- association is simply never paid for July. The gap is invisible precisely
  -- because a missing charge produces no row to notice.
  --
  -- Checked against closed_periods rather than against receivables, and that
  -- distinction is the whole reason the table exists: a month in which nobody
  -- was نشط produces zero receivables, so an "are there receivables?" test would
  -- read it as never closed and block every month after it forever.
  --
  -- Nothing before system_start counts. The association's books begin there.
  IF EXISTS (
    SELECT 1
      FROM generate_series(
             date_trunc('month', s.system_start),
             date_trunc('month', to_date(p_period || '-01', 'YYYY-MM-DD'))
               - interval '1 month',
             interval '1 month') d
     WHERE NOT EXISTS (SELECT 1 FROM public.closed_periods c
                        WHERE c.period = to_char(d, 'YYYY-MM'))
  ) THEN
    RAISE EXCEPTION 'EARLIER_PERIOD_OPEN: % cannot be closed while an earlier '
                    'month is still open', p_period USING ERRCODE = 'RUL15';
  END IF;

  -- Rule 3: nothing to charge means no rows at all, not zero rows. A fee of zero
  -- is a valid configuration (the association pausing collection), and it must
  -- produce an empty period rather than a register full of 0.00 charges that
  -- ck_recv_total would refuse anyway.
  --
  -- It still COUNTS AS CLOSED. The month was dealt with; leaving it open would
  -- block every month after it under 15b, which is exactly the trap that made
  -- closed_periods a table rather than an inference.
  -- substr(p_period, 6, 2) is the calendar month out of 'YYYY-MM'.
  v_fee := coalesce(
    nullif(s.fee_exceptions ->> substr(p_period, 6, 2), '')::numeric,
    s.member_fee);

  IF v_fee <= 0 THEN
    SELECT count(*) INTO v_skipped FROM public.adeels WHERE status = 'نشط';
    INSERT INTO public.closed_periods (period, closed_by, created)
    VALUES (p_period, auth.uid(), 0);
    PERFORM public.write_audit('receivables.generate',
      format('إنشاء استحقاقات %s: لا رسم مقرر', p_period), p_period);
    RETURN jsonb_build_object('period', p_period, 'created', 0,
                              'skipped', v_skipped);
  END IF;

  FOR a IN SELECT id, full_name, status
             FROM public.adeels ORDER BY id LOOP
    -- Status overrides everything: a موقوف or متوفى عديل is not billable.
    IF a.status <> 'نشط' THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Rule 4 as idempotency: re-running the same period skips instead of
    -- raising a duplicate. The partial index is what makes this safe under
    -- concurrency, so two admins pressing the button together cannot double-bill.
    INSERT INTO public.receivables (
      adeel_id, period, period_end, adeel_name, total,
      created_by)
    VALUES (
      a.id, p_period, v_end, a.full_name, v_fee,
      auth.uid())
    ON CONFLICT (adeel_id, period) WHERE status <> 'ملغي' DO NOTHING
    RETURNING id INTO v_recv_id;

    IF v_recv_id IS NULL THEN
      v_skipped := v_skipped + 1;
    ELSE
      v_created := v_created + 1;
      -- ── The wallet pays the month it was paid in advance for ──────────────
      -- Immediately, and inside the same transaction as the charge. A member
      -- who handed over a year must never see the new month appear as a debt
      -- he already settled — not even between two statements — and doing it
      -- here means the charge and its settlement are one event or neither.
      --
      -- Called per عديل rather than once at the end so that the credit walks
      -- his OWN receivables in period order. A single sweep would still be
      -- correct arithmetically and would scan the whole register for the
      -- overwhelming majority who have no credit at all.
      v_applied := v_applied + public.settle_from_credit(a.id);
    END IF;
    v_recv_id := NULL;
  END LOOP;

  -- The month is now closed, whatever it produced. Written INSIDE the same
  -- transaction as the receivables it raised, so a failure anywhere above leaves
  -- neither the charges nor the marker — the alternative is a month recorded as
  -- closed with nothing billed in it.
  INSERT INTO public.closed_periods (period, closed_by, created)
  VALUES (p_period, auth.uid(), v_created);

  PERFORM public.write_audit('receivables.generate',
    CASE WHEN v_applied > 0
         THEN format('إنشاء استحقاقات %s: %s سجل، وسُدِّد %s من أرصدة مقدمة',
                     p_period, v_created, v_applied::text)
         ELSE format('إنشاء استحقاقات %s: %s سجل', p_period, v_created)
    END, p_period);

  RETURN jsonb_build_object('period', p_period, 'created', v_created,
                            'skipped', v_skipped,
                            'creditApplied', v_applied::text);
END $function$;

-- == 2. ما تعرضه شاشة الإقفال ==============================================
CREATE OR REPLACE FUNCTION public.api_closable_periods()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH months AS (
    SELECT to_char(d, 'YYYY-MM') AS period
      FROM public.association_settings s,
           generate_series(
             date_trunc('month', s.system_start),
             -- ⚠ THIS MONTH, not last. The series bound IS the rule the picker
             --   paints, so leaving it a month behind would hide سبتمبر from
             --   the screen while generate_period accepted it — the button
             --   refusing what the RPC allows, which reads as a broken app.
             date_trunc('month', current_date),
             interval '1 month') d
     WHERE s.id = 1
  ), flagged AS (
    SELECT m.period,
           EXISTS (SELECT 1 FROM public.closed_periods c
                    WHERE c.period = m.period) AS closed
      FROM months m
  ), next_open AS (
    SELECT min(period) AS period FROM flagged WHERE NOT closed
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period', f.period,
        'label',  public.period_label(f.period),
        'closed', f.closed,
        'selectable', coalesce(f.period = (SELECT period FROM next_open), false))
      ORDER BY f.period DESC),
    '[]'::jsonb)
  FROM flagged f
$function$;

-- == 3. «أقفل كلّ ما فات» ==================================================
CREATE OR REPLACE FUNCTION public.auto_close_periods()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  s         record;
  v_cursor  date;
  v_last    date;
  v_period  char(7);
  v_created int := 0;
  v_periods jsonb := '[]'::jsonb;
  v_one     jsonb;
BEGIN
  PERFORM public.require_role('financeManager');

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_cursor := date_trunc('month', s.system_start)::date;
  -- THIS month, not the previous one — the اشتراك is due at a month's start.
  -- ⚠ Left at «previous», the backfill would stop one month short of what
  --   generate_period accepts, so «أقفل كل ما فات» would quietly leave the
  --   newest month open and rule 15b would then block nothing and explain
  --   nothing. The three places that answer «which month?» must agree.
  v_last   := date_trunc('month', current_date)::date;

  WHILE v_cursor <= v_last LOOP
    v_period := to_char(v_cursor, 'YYYY-MM');
    -- Skip what is already closed rather than calling and catching. Rule 15a
    -- makes generate_period REFUSE a closed month, so the old "call it and let
    -- rule 4 make it a no-op" pattern would now abort the whole backfill on the
    -- first month that had already been done — which is every month, the second
    -- time anyone presses this.
    --
    -- Walking oldest-first is also what satisfies rule 15b for free: each month
    -- is closed before the one after it is attempted.
    IF NOT EXISTS (SELECT 1 FROM public.closed_periods c WHERE c.period = v_period)
    THEN
      v_one    := public.generate_period(v_period);
      v_created := v_created + (v_one ->> 'created')::int;
      v_periods := v_periods || v_one;
    END IF;
    v_cursor := (v_cursor + interval '1 month')::date;
  END LOOP;

  RETURN jsonb_build_object('created', v_created, 'periods', v_periods);
END $function$;

-- == 4. لوحة المعلومات — تسأل ولا تحسب =====================================
CREATE OR REPLACE FUNCTION public.api_dashboard()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  WITH period AS (
    -- ⚠ ONE RULE, ONE ANSWER. This was «last month» computed from the calendar
    --   — a second implementation of rule 15 standing beside
    --   api_closable_periods and free to disagree with it. The moment the
    --   current month became closable it DID disagree: the dashboard would have
    --   named أغسطس while the picker offered سبتمبر.
    --
    --   It now asks the same question the picker asks: the EARLIEST month still
    --   open. NULL when every month is closed, which is the truthful answer to
    --   «أيّ شهرٍ يُقفل الآن؟» when none is, and is what the client already
    --   renders as an empty string.
    SELECT to_char(min(d), 'YYYY-MM') AS p
      FROM public.association_settings s,
           generate_series(date_trunc('month', s.system_start),
                           date_trunc('month', current_date),
                           interval '1 month') d
     WHERE s.id = 1
       AND NOT EXISTS (SELECT 1 FROM public.closed_periods c
                        WHERE c.period = to_char(d, 'YYYY-MM'))
  )
  SELECT jsonb_build_object(
    'stats', jsonb_build_object(
      'adeels', (SELECT count(*) FROM public.adeels),
      'active', (SELECT count(*) FROM public.adeels WHERE status = 'نشط'),
      'suspended', (SELECT count(*) FROM public.adeels WHERE status = 'موقوف'),
      'deceased', (SELECT count(*) FROM public.adeels WHERE status = 'متوفى'),
      'debt', (SELECT coalesce(sum(balance), 0)::numeric(12,2)::text FROM public.receivables
                WHERE status <> 'ملغي'),
      'collected', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                      FROM public.cash_movements WHERE status <> 'ملغي'),
      'cash', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text FROM public.cash_movements
                WHERE status <> 'ملغي' AND method = 'نقداً'),
      'transfer', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                     FROM public.cash_movements
                    WHERE status <> 'ملغي' AND method = 'تحويل مصرفي'),
      'indebtedAdeels', (SELECT count(DISTINCT adeel_id)
                           FROM public.receivables
                          WHERE status <> 'ملغي' AND balance > 0)),
    'topDebtors', coalesce(
      (SELECT jsonb_agg(d ORDER BY (d ->> 'debt')::numeric DESC)
         FROM (SELECT jsonb_build_object(
                        'adeelId', v."id",
                        'adeelCode', v."adeelCode",
                        'adeelName', v."fullName",
                        'debt', v."debt") AS d
                 FROM public.v_adeels v
                WHERE v."debt"::numeric > 0
                ORDER BY v."debt"::numeric DESC
                LIMIT 10) top),
      '[]'::jsonb),
    'closingPeriod', (SELECT p FROM period),
    'closingPeriodLabel', (SELECT public.period_label(p) FROM period))
$function$;

-- == 5. الفحص: للقراءة فقط، وكلُّ صفٍّ يجب أن يقول true ====================
SELECT 'هذا الشهر صار مقبولًا' AS "الفحص",
       (SELECT prosrc LIKE '%PERIOD_IN_THE_FUTURE%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'generate_period') AS "النتيجة"
UNION ALL SELECT 'والشهر القادم ما زال مرفوضًا',
       (SELECT prosrc LIKE '%p_period > to_char(current_date%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'generate_period')
-- ⚠ يُقرأ من الدالّة نفسِها لا من اسمها: دالّةٌ موجودةٌ بجسدٍ قديمٍ تجتاز كلَّ
--   فحصٍ يسأل «هل هي هناك؟»، وهي بالضبط الحالةُ التي يوجد هذا الملفّ لأجلها.
UNION ALL SELECT 'ولم تبقَ دالّةٌ تقف عند الشهر الماضي',
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname = 'public'
                      AND p.proname IN ('api_closable_periods','auto_close_periods','api_dashboard')
                      AND p.prosrc LIKE '%current_date) - interval ''1 month''%')
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 6. الحرّاس الأربعة ====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- بعد الإقفال: ما الذي ستراه الشاشة الآن. للقراءة فقط.
SELECT jsonb_pretty(public.api_closable_periods());
