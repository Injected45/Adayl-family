-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-22.  التاريخ من ساعة الخادم، لا من الجهاز.
--
--  WHAT THIS DOES
--    Every money row is stamped by the DATABASE at the instant it is written,
--    and no client can propose a date any more — not the app, not a tampered
--    handset, not a request sent straight to PostgREST.
--
--  ⚠ WHY A VOUCHER WAS EVER DATED TOMORROW
--    register_disbursement took `p_spent_at date` and the voucher form carried
--    a date picker defaulted to the phone's clock. So the stamp came from the
--    DEVICE, and a device's clock is a setting. Nothing in the schema disagreed
--    with it, because nothing in the schema knew what day it was — a CHECK
--    cannot call now().
--
--    The earlier patch put a trigger in that REFUSED a future date. That closed
--    the dangerous half and left the other one open: a date in the PAST was
--    still accepted, so a mistyped year, a phone a week behind, or somebody who
--    wanted a payment to land in a closed month could all still write one.
--
--  ⚠ SO THIS DOES NOT REFUSE — IT STAMPS. A refusal is a rule about a value the
--    client still supplies; a stamp removes the value from the client's hands.
--    `NEW.spent_at := now()` in a BEFORE INSERT trigger cannot be argued with,
--    cannot be bypassed by a second write path, and needs nobody to remember
--    it. p_spent_at goes on existing and is now inert: whatever it holds is
--    overwritten before the row lands.
--
--  ⚠ AND now() IS THE SUPABASE SERVER'S CLOCK — the machine in the datacentre,
--    NTP-disciplined, that no handset in Libya can reach. That is exactly the
--    «تاريخ عبر الإنترنت» this is for. It is stored as timestamptz, i.e. an
--    absolute instant, and rendered in Africa/Tripoli wherever a day is shown.
--
--  ⚠ WHAT THIS COSTS, AND IT IS A REAL COST
--    A voucher that genuinely left the treasury on TUESDAY and is entered on
--    THURSDAY will be dated THURSDAY. Back-dating is gone, for everyone,
--    including honestly. That is the association's decision and it is the
--    price of «لا احتمالية خطأ في التاريخ» — the same rule cannot both refuse a
--    wrong date and accept a right one it has no way to tell apart.
--
--  ⚠ AND payments ARE GUARDED TOO, though they were never open. paid_at
--    already defaulted to now() and register_payment never took a date — so
--    this changes no behaviour there at all. It is put in so that the guarantee
--    lives in the TABLE rather than in the absence of a parameter, which is a
--    thing one future signature change would quietly undo.
--
--  ⚠ ROWS ALREADY WRITTEN ARE NOT TOUCHED. EXP-09 keeps its wrong date until it
--    is cancelled and recorded again — which is what rule 9 wants, and what the
--    re-recording will now stamp correctly by itself.
--
--  ⚠ AND A WARNING FOR WHOEVER FOLDS THIS INTO supabase/migrations/ ONE DAY.
--    probe.sh rebuilds from the migrations alone, so this trigger is not in the
--    local suite today. The moment it is, every fixture that inserts a payment
--    or a voucher with a CHOSEN date — the ones the reports and the ageing
--    checks depend on — will be silently restamped to the run's own clock, and
--    those tests will fail for a reason that looks nothing like a timestamp.
--    Such a fixture has to insert with the trigger disabled, or stop choosing
--    dates.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste all of this → Run. One transaction, safe to
--    run twice.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.disbursements') IS NULL THEN
    RAISE EXCEPTION
      'لا يوجد جدول صرف. طبّق supabase/PATCH_20260817_device_lock.sql أولاً.';
  END IF;
END $prereq$;

-- == 1. السند يُختم بساعة الخادم ============================================
-- ⚠ AND THE UPDATE HALF IS NOT DECORATION. Without it, a correction that moved
--   spent_at would walk straight past a rule that only watched INSERT — and
--   «correcting» a date in place is precisely what rule 9 forbids: the wrong
--   figure would vanish with nothing recording that it was ever there. A
--   voucher with a bad date is fixed the way every other mistake is, by
--   reversing it and recording it again, which leaves both halves visible.
CREATE OR REPLACE FUNCTION public.disb_stamp_time()
RETURNS trigger LANGUAGE plpgsql AS $stamp$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.spent_at := now();
  ELSIF NEW.spent_at IS DISTINCT FROM OLD.spent_at THEN
    RAISE EXCEPTION 'لا يُعدَّل تاريخ سند بعد تسجيله. ألغِ السند وسجّله من جديد.'
      USING ERRCODE = 'RUL17';
  END IF;
  RETURN NEW;
END $stamp$;

REVOKE EXECUTE ON FUNCTION public.disb_stamp_time()
  FROM PUBLIC, anon, authenticated, service_role;

-- The old trigger and the old function go, in that order: a trigger depends on
-- its function, so the function cannot be dropped while the trigger points at
-- it. IF EXISTS on both, so this file is correct on a project that never had
-- the 20/08 (b) version.
DROP TRIGGER IF EXISTS trg_disb_no_future ON public.disbursements;
DROP TRIGGER IF EXISTS trg_disb_stamp_time ON public.disbursements;
CREATE TRIGGER trg_disb_stamp_time
  BEFORE INSERT OR UPDATE OF spent_at ON public.disbursements
  FOR EACH ROW EXECUTE FUNCTION public.disb_stamp_time();

DROP FUNCTION IF EXISTS public.disb_refuse_future();

-- == 2. والإيصال كذلك ======================================================
-- ⚠ THIS CHANGES NOTHING TODAY, and that is the point. paid_at already
--   defaults to now() and register_payment has no date parameter — so the
--   guarantee currently rests on a function signature, which is a thing that
--   can be widened by one well-meaning patch. Written as a trigger it rests on
--   the TABLE, and every path into it, forever.
CREATE OR REPLACE FUNCTION public.pay_stamp_time()
RETURNS trigger LANGUAGE plpgsql AS $stamp$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.paid_at := now();
  ELSIF NEW.paid_at IS DISTINCT FROM OLD.paid_at THEN
    RAISE EXCEPTION 'لا يُعدَّل تاريخ إيصال بعد تسجيله. ألغِ الإيصال وسجّله من جديد.'
      USING ERRCODE = 'RUL17';
  END IF;
  RETURN NEW;
END $stamp$;

REVOKE EXECUTE ON FUNCTION public.pay_stamp_time()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_pay_stamp_time ON public.payments;
CREATE TRIGGER trg_pay_stamp_time
  BEFORE INSERT OR UPDATE OF paid_at ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.pay_stamp_time();

-- ⚠ cash_movements NEEDS NOTHING. Rule 8 copies occurred_at straight from the
--   payment it mirrors — `SELECT id, adeel_id, amount, method, paid_at` — so
--   stamping the payment stamps the treasury row with it, and a second trigger
--   here could only ever disagree with the receipt it is supposed to reflect.
--   audit_log defaults to clock_timestamp() and no client writes it at all.

-- == 3. المسحة، بعد آخر CREATE في هذا الملف ================================
-- ⚠ TWO FUNCTIONS ARE CREATED ABOVE, BOTH FRESH, so both take the built-in
--   default of EXECUTE to PUBLIC with Supabase's ALTER DEFAULT PRIVILEGES
--   layering anon on top. The explicit REVOKEs above handle these two; the
--   sweep recomputes every grant in the schema from the allow-list, so it also
--   handles whatever the next patch adds — provided it is added above here.
--   Getting this order wrong is what made 20/08 (b) roll back once.
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
SELECT 'ختم السند بساعة الخادم قائم' AS "الفحص",
       EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                WHERE c.relname='disbursements' AND t.tgname='trg_disb_stamp_time'
                  AND (t.tgtype & 4) > 0 AND (t.tgtype & 16) > 0) AS "النتيجة"
UNION ALL SELECT 'وختم الإيصال كذلك',
       EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                WHERE c.relname='payments' AND t.tgname='trg_pay_stamp_time'
                  AND (t.tgtype & 4) > 0 AND (t.tgtype & 16) > 0)
-- ⚠ AND THE OLD REFUSE-ONLY GUARD IS GONE, not merely superseded. Two triggers
--   on one column would both fire, and the old one would refuse a stamp the new
--   one had just written if the two clocks ever disagreed by a day boundary.
UNION ALL SELECT 'والحارس القديم أُزيل',
       NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='disb_refuse_future')
UNION ALL SELECT 'ولا سياسة كتابة على السندات البتة',
       NOT EXISTS (SELECT 1 FROM pg_policies
                    WHERE schemaname='public' AND tablename='disbursements'
                      AND cmd <> 'SELECT')
-- ⚠ AND NOT ONE FIGURE MOVED. This patch writes no row; it only decides what
--   the NEXT row's timestamp will be.
UNION ALL SELECT 'ولم يتغيّر أي رقم مالي',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- ⚠ THE SERVER CLOCK ITSELF IS NOT PRINTED HERE, and not from carelessness:
--   the Supabase editor renders only the LAST result set, and the four guards
--   below have to be last. FINAL_CHECK.sql carries that row instead, where it
--   can actually be read.

-- == 5. The four guards =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
