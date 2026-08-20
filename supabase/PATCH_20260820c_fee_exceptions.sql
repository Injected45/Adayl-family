-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-20 (c).  اشتراك يختلف باختلاف الشهر.
--
--  WHAT THIS DOES
--    The association agreed that some calendar months carry a different
--    subscription: يناير and يونيو at 200 while every other month stays at 100.
--    Settings gains a list of exceptions, and generate_period raises each
--    receivable at the figure THAT month carries.
--
--  ⚠ KEYED BY CALENDAR MONTH, NOT BY PERIOD, and that is the association's rule
--    rather than a shortcut. The agreement is «January is 200», not «January
--    2026 is 200» — so '01' holds every year until the association changes it,
--    and nobody has to remember to set it again each December.
--
--  ⚠ AND IT CHANGES NO RECEIVABLE ALREADY RAISED. Rule 5 snapshots the amount
--    onto the receivable when the month is closed, and the snapshot trigger
--    refuses to let it move afterwards. So adding an exception in March does
--    not reprice January — which is the same guarantee the settings screen
--    already states about the monthly fee, and for the same reason: a closed
--    month is a fact, not a formula.
--
--  ⚠ NO ROW IS TOUCHED. One column with a default and three function bodies
--    replaced. No view changes. Every existing figure is exactly what it was.
--
--  ⚠ AND THE THREE BODIES ARE THE LIVE ONES, VERIFIED. generate_period was
--    last restated in PATCH_20260817 and update_settings/api_settings in
--    PATCH_20260816; all three were compared character for character against
--    the copies this patch carries before it was written. Lifting a body from
--    an older file is how a patch silently REVERTS the fix before it — the
--    check that matters is not «does it compile» but «is this the version
--    that is actually running».
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction. Safe to run twice.
--    Apply PATCH_20260820b_aid_transparency.sql first — see WHICH_STATE.sql.
-- ============================================================================

BEGIN;

-- == 1. أين تُحفظ الاستثناءات ===============================================
-- jsonb and not a table, and the reason is the shape of the fact: it is at most
-- twelve keys, it is read on one screen and written on the same one, and it is
-- settings — a single row the whole association shares. A table would buy
-- referential integrity over a set of twelve constants and cost a join on every
-- close.
ALTER TABLE public.association_settings
  ADD COLUMN IF NOT EXISTS fee_exceptions jsonb NOT NULL DEFAULT '{}'::jsonb;

-- ⚠ THE KEYS ARE CHECKED, because a typo here is a wrong charge on every
--   member. '1' instead of '01' would simply never match substr(period,6,2) and
--   the exception would be silently ignored — the worst kind of failure for a
--   money rule: nothing refuses, nothing warns, and the month bills the old fee.
-- ⚠ THROUGH A FUNCTION, BECAUSE A CHECK CANNOT HOLD A SUBQUERY. Postgres
--   refuses one outright, and walking a jsonb object needs jsonb_each_text —
--   a set-returning call. An IMMUTABLE helper is the only form a constraint
--   will accept, and immutability is honest here: the answer depends on the
--   value and on nothing else.
CREATE OR REPLACE FUNCTION public.fee_exceptions_ok(p jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $ok$
  SELECT jsonb_typeof(p) = 'object'
     AND NOT EXISTS (
       SELECT 1 FROM jsonb_each_text(p) AS e(k, v)
        WHERE k !~ '^(0[1-9]|1[0-2])$'
           OR v !~ '^[0-9]+([.][0-9]{1,2})?$')
$ok$;

-- ⚠ NOT CLIENT-CALLABLE, and created FRESH — so Postgres materialises EXECUTE
--   to PUBLIC and Supabase layers anon on top. assert_no_public_execute() would
--   roll this patch back naming the function rather than the missing REVOKE.
REVOKE EXECUTE ON FUNCTION public.fee_exceptions_ok(jsonb)
  FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.association_settings DROP CONSTRAINT IF EXISTS ck_settings_fee_exceptions;
ALTER TABLE public.association_settings
  ADD CONSTRAINT ck_settings_fee_exceptions
  CHECK (public.fee_exceptions_ok(fee_exceptions));

-- == 2. إقفال الشهر بسعر ذلك الشهر ==========================================
CREATE OR REPLACE FUNCTION public.generate_period(p_period char(7))
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
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
  -- Before system_start the books did not exist; the current month and anything
  -- after it has not ended, and closing a month that is still running would bill
  -- for time nobody has lived through. Both ends were previously unguarded — the
  -- picker simply did not offer them, which protects the button and not the RPC,
  -- and the RPC is what a hostile client calls.
  IF p_period < to_char(s.system_start, 'YYYY-MM') THEN
    RAISE EXCEPTION 'PERIOD_BEFORE_SYSTEM_START: %', p_period
      USING ERRCODE = 'RUL15';
  END IF;
  IF p_period >= to_char(current_date, 'YYYY-MM') THEN
    RAISE EXCEPTION 'PERIOD_NOT_ENDED: %', p_period USING ERRCODE = 'RUL15';
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
END $$;

-- == 3. الإعدادات تقبل الاستثناءات ==========================================
CREATE OR REPLACE FUNCTION public.update_settings(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_old     record;
  v_row     record;
  v_changes text[] := '{}';
  v_t_id    bigint;
  v_f_id    bigint;
  -- Scalars, deliberately. See the note beside the lookups: a `record` that is
  -- never assigned makes the UPDATE below unplannable (55000), even in the arm
  -- that does not read it.
  v_t_name  text;
  v_t_phone text;
  v_f_name  text;
  v_f_phone text;
BEGIN
  PERFORM public.require_role('admin');

  SELECT * INTO v_old FROM public.association_settings WHERE id = 1 FOR UPDATE;

  -- ── Who holds each post ───────────────────────────────────────────────────
  -- Both officials are عدايل, chosen from the register rather than typed. The
  -- id is what is being set; the name and phone are copied from his row below,
  -- so the association can never end up with three spellings of one man across
  -- a year of settings edits.
  --
  -- `p_patch ? key` distinguishes "not mentioned" from "explicitly cleared".
  -- Using ->> alone would make a null indistinguishable from an omission, and
  -- vacating a post would become impossible.
  v_t_id := CASE WHEN p_patch ? 'treasurerAdeelId'
                 THEN nullif(p_patch ->> 'treasurerAdeelId', '')::bigint
                 ELSE v_old.treasurer_adeel_id END;
  v_f_id := CASE WHEN p_patch ? 'financeAdeelId'
                 THEN nullif(p_patch ->> 'financeAdeelId', '')::bigint
                 ELSE v_old.finance_manager_adeel_id END;

  -- The overlap the association asked to make impossible. ck_settings_distinct_
  -- officials enforces it in the storage engine too; this exists so the admin
  -- gets a sentence he can act on instead of a constraint name.
  IF v_t_id IS NOT NULL AND v_t_id = v_f_id THEN
    RAISE EXCEPTION 'لا يمكن أن يكون أمين الصندوق والمدير المالي عديلاً واحداً'
      USING ERRCODE = 'RUL16';
  END IF;

  -- ── FOUR SCALARS, NOT TWO RECORDS. This is the second thing that stopped
  --    an official from ever being saved. ───────────────────────────────────
  --
  -- These were `v_t record` / `v_f record`, filled only inside the IF below.
  -- With no post chosen the record is never assigned, and the UPDATE further
  -- down still MENTIONS `v_t.full_name` inside a CASE arm that would not be
  -- taken. PL/pgSQL has to know the record's tuple structure to plan the
  -- statement at all, so the branch never gets a chance to protect it:
  --
  --   55000  record "v_t" is not assigned yet
  --          The tuple structure of a not-yet-assigned record is indeterminate.
  --
  -- So the two failures covered the whole space between them: choosing an
  -- official raised 22P02 on the audit line below, and leaving one vacant
  -- raised 55000 here. There was no input that saved.
  --
  -- A scalar has no tuple structure to be indeterminate about. Unset it is
  -- simply NULL, the CASE arm is planned without complaint, and `SELECT INTO`
  -- still sets FOUND, so the "not on the register" check below is unchanged.
  IF v_t_id IS NOT NULL THEN
    SELECT full_name, phone INTO v_t_name, v_t_phone
      FROM public.adeels WHERE id = v_t_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'أمين الصندوق المختار ليس في سجل العدايل'
        USING ERRCODE = 'RUL16';
    END IF;
  END IF;
  IF v_f_id IS NOT NULL THEN
    SELECT full_name, phone INTO v_f_name, v_f_phone
      FROM public.adeels WHERE id = v_f_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'المدير المالي المختار ليس في سجل العدايل'
        USING ERRCODE = 'RUL16';
    END IF;
  END IF;

  UPDATE public.association_settings SET
    association_name = coalesce(p_patch ->> 'associationName', association_name),
    currency         = coalesce(p_patch ->> 'currency', currency),
    -- nullif BEFORE the cast, and the officials below have always had it while
    -- these two did not. An EMPTY string is not a number and not a date, so
    -- `''::numeric` raises 22P02 — a code with no Arabic text, which the app can
    -- only render as "something went wrong". The whole save fails, including
    -- the two officials the admin was actually trying to set, and nothing on
    -- screen connects the failure to a field he may not even have touched.
    --
    -- An empty box now means "leave it alone", which is the only reading that
    -- makes sense: the fee is NOT NULL, so blank cannot be a value.
    member_fee       = coalesce(nullif(p_patch ->> 'memberFee', '')::numeric,
                                member_fee),
    -- ⚠ REPLACED WHOLE, NOT MERGED. The screen sends the complete set every
    --   time, so removing an exception is sending one fewer — a merge would
    --   make removal impossible without a second verb.
    fee_exceptions   = coalesce(p_patch -> 'feeExceptions', fee_exceptions),
    system_start     = coalesce(nullif(p_patch ->> 'systemStart', '')::date,
                                system_start),
    -- The post, then the snapshot of whoever holds it. When an عديل is chosen
    -- his row IS the name and phone; the free-text keys are still honoured when
    -- no عديل is set, so a project that has not picked anyone yet keeps working
    -- exactly as before.
    treasurer_adeel_id    = v_t_id,
    treasurer_name        = CASE WHEN v_t_id IS NOT NULL THEN v_t_name
                                 ELSE coalesce(p_patch ->> 'treasurerName',
                                               treasurer_name) END,
    treasurer_phone       = CASE WHEN v_t_id IS NOT NULL
                                 THEN coalesce(v_t_phone, '')
                                 ELSE coalesce(p_patch ->> 'treasurerPhone',
                                               treasurer_phone) END,
    finance_manager_adeel_id = v_f_id,
    finance_manager_name  = CASE WHEN v_f_id IS NOT NULL THEN v_f_name
                                 ELSE coalesce(p_patch ->> 'financeName',
                                               finance_manager_name) END,
    finance_manager_phone = CASE WHEN v_f_id IS NOT NULL
                                 THEN coalesce(v_f_phone, '')
                                 ELSE coalesce(p_patch ->> 'financePhone',
                                               finance_manager_phone) END,
    bank_name                   = coalesce(p_patch ->> 'bankName', bank_name),
    bank_account_no             = coalesce(p_patch ->> 'bankAccountNo', bank_account_no),
    bank_account_name           = coalesce(p_patch ->> 'bankAccountName', bank_account_name),
    updated_by = auth.uid()
  WHERE id = 1
  RETURNING * INTO v_row;

  -- The two financially load-bearing fields first, then the rest. IS DISTINCT
  -- FROM so a field the patch omitted (coalesce kept it) records nothing.
  -- Rule 12: a change to what a month costs is a money change, and the trail
  -- has to carry it whichever of the two figures moved.
  IF v_row.fee_exceptions IS DISTINCT FROM v_old.fee_exceptions THEN
    PERFORM public.write_audit('settings.update',
      format('تعديل استثناءات الاشتراك: %s ← %s',
             v_old.fee_exceptions::text, v_row.fee_exceptions::text));
  END IF;

  IF v_row.member_fee IS DISTINCT FROM v_old.member_fee THEN
    v_changes := v_changes || format('الاشتراك الشهري من %s إلى %s',
                                     v_old.member_fee::text, v_row.member_fee::text);
  END IF;
  IF v_row.system_start IS DISTINCT FROM v_old.system_start THEN
    v_changes := v_changes || format('بداية النظام من %s إلى %s',
                                     to_char(v_old.system_start, 'YYYY-MM-DD'),
                                     to_char(v_row.system_start, 'YYYY-MM-DD'));
  END IF;
  IF v_row.currency IS DISTINCT FROM v_old.currency THEN
    v_changes := v_changes || format('العملة من %s إلى %s',
                                     v_old.currency, v_row.currency);
  END IF;
  IF v_row.association_name IS DISTINCT FROM v_old.association_name THEN
    v_changes := v_changes || format('اسم الجمعية من %s إلى %s',
                                     v_old.association_name, v_row.association_name);
  END IF;
  -- The account number is recorded in full, both before and after. It is the
  -- one setting where a single wrong digit sends the association's collections
  -- to a stranger, and "someone changed the bank account" without saying what
  -- it was is not a trail anyone can act on.
  IF v_row.bank_name IS DISTINCT FROM v_old.bank_name THEN
    v_changes := v_changes || format('المصرف من %s إلى %s',
                                     coalesce(nullif(v_old.bank_name, ''), '—'),
                                     coalesce(nullif(v_row.bank_name, ''), '—'));
  END IF;
  IF v_row.bank_account_no IS DISTINCT FROM v_old.bank_account_no THEN
    v_changes := v_changes || format('رقم الحساب المصرفي من %s إلى %s',
                                     coalesce(nullif(v_old.bank_account_no, ''), '—'),
                                     coalesce(nullif(v_row.bank_account_no, ''), '—'));
  END IF;
  IF v_row.bank_account_name IS DISTINCT FROM v_old.bank_account_name THEN
    v_changes := v_changes || format('اسم صاحب الحساب من %s إلى %s',
                                     coalesce(nullif(v_old.bank_account_name, ''), '—'),
                                     coalesce(nullif(v_row.bank_account_name, ''), '—'));
  END IF;
  -- ── `::text` IS NOT DECORATION. Without it this function cannot save an
  --    official at all. ──────────────────────────────────────────────────────
  --
  -- `v_changes` is text[]. Every append above passes format(), which RETURNS
  -- text, so `text[] || text` resolves to array_append and works. These two
  -- passed a bare quoted literal, which Postgres types as `unknown` — and given
  -- the choice between `anyarray || anyelement` and `anyarray || anyarray` it
  -- picks the array form and casts the literal to text[]:
  --
  --   22P02  malformed array literal: "بيانات أمين الصندوق"
  --          Array value must start with "{" or dimension information.
  --
  -- The branch fires on exactly one condition — the treasurer or the finance
  -- manager CHANGED — so the failure is perfectly targeted at the one action
  -- the admin was performing, and invisible for every other settings save. And
  -- 22P02 carries no Arabic, so the app could only say "حدث خطأ غير متوقع"
  -- about a save that looked, from the screen, like it had simply not worked.
  --
  -- It is not a rule, a permission or a constraint. It is a type resolution,
  -- three lines below the officials it was silently refusing to record.
  IF v_row.treasurer_name  IS DISTINCT FROM v_old.treasurer_name
  OR v_row.treasurer_phone IS DISTINCT FROM v_old.treasurer_phone THEN
    v_changes := v_changes || 'بيانات أمين الصندوق'::text;
  END IF;
  IF v_row.finance_manager_name  IS DISTINCT FROM v_old.finance_manager_name
  OR v_row.finance_manager_phone IS DISTINCT FROM v_old.finance_manager_phone THEN
    v_changes := v_changes || 'بيانات المدير المالي'::text;
  END IF;

  -- A no-op save still writes an entry. "An admin opened settings and saved
  -- without changing anything" is itself worth being able to see, and a silent
  -- write would make the trail's gaps ambiguous.
  PERFORM public.write_audit('settings.update',
    CASE WHEN cardinality(v_changes) = 0
         THEN 'تحديث إعدادات الجمعية: لا تغيير'
         ELSE 'تحديث إعدادات الجمعية: ' || array_to_string(v_changes, '، ')
    END,
    'settings');

  RETURN jsonb_build_object(
    'associationName', v_row.association_name, 'currency', v_row.currency,
    'memberFee', v_row.member_fee::text,
    'feeExceptions', v_row.fee_exceptions,
    'systemStart', v_row.system_start);
END $$;

-- == 4. وتقرأها الشاشة ======================================================
CREATE OR REPLACE FUNCTION public.api_settings() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'associationName', s.association_name,
    'currency', s.currency,
    'memberFee', s.member_fee::text,
    -- {"01":"200.00"} — calendar month to the fee that month carries.
    'feeExceptions', s.fee_exceptions,
    'systemStart', to_char(s.system_start, 'YYYY-MM-DD'),
    'autoClosePreviousMonths', s.auto_close_previous_months,
    'bankName', s.bank_name,
    'bankAccountNo', s.bank_account_no,
    'bankAccountName', s.bank_account_name,
    -- adeelId is what the settings screen preselects in its dropdown; the name
    -- and phone travel with it so the screen can render the current holder
    -- without a second read. NULL means the post is vacant, or was filled by a
    -- typed name before the two posts were tied to the register.
    'treasurer', jsonb_build_object(
      'adeelId', s.treasurer_adeel_id,
      'name', s.treasurer_name,
      'phone', s.treasurer_phone),
    'financeManager', jsonb_build_object(
      'adeelId', s.finance_manager_adeel_id,
      'name', s.finance_manager_name,
      'phone', s.finance_manager_phone))
  FROM public.association_settings s WHERE s.id = 1
$$;

-- == 5. Confirmation ========================================================
-- Read-only. Every row must say true.
SELECT 'عمود الاستثناءات موجود' AS "الفحص",
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='association_settings'
                  AND column_name='fee_exceptions') AS "النتيجة"
UNION ALL SELECT 'وقيده يرفض مفتاحاً غير شهر',
       EXISTS (SELECT 1 FROM pg_constraint
                WHERE conname = 'ck_settings_fee_exceptions')
-- ⚠ THE RULE ITSELF, read off the function body rather than trusted: a patch
--   that added the column and left generate_period reading member_fee would
--   pass every other check here and bill every month at the old figure.
UNION ALL SELECT 'وإقفال الشهر يقرأ سعر ذلك الشهر',
       (SELECT pg_get_functiondef(p.oid) LIKE '%fee_exceptions%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='generate_period')
UNION ALL SELECT 'والإعدادات تقبلها وتعيدها',
       (SELECT pg_get_functiondef(p.oid) LIKE '%feeExceptions%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='update_settings')
UNION ALL SELECT 'وتُقرأ من api_settings',
       (SELECT pg_get_functiondef(p.oid) LIKE '%fee_exceptions%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname='public' AND p.proname='api_settings')
-- ⚠ AND NOT ONE FIGURE MOVED. This patch adds a column with a default and
--   replaces three bodies; every receivable already raised keeps the amount it
--   was snapshot with, because rule 5 refuses to let it change.
UNION ALL SELECT 'ولم يتغيّر أي رقم مالي',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
           AND "outstanding"::numeric = (SELECT coalesce(sum(balance), 0)
                                           FROM public.receivables
                                          WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 6. The four guards =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
