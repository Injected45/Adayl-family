-- 30_rules.sql — the twelve business rules, each with a case that satisfies it
-- and a case that VIOLATES it.
--
-- The failing case is the only one that proves anything. A probe that merely
-- inserts a valid row demonstrates the column exists; it does not demonstrate
-- that the rule bites. Every violation below is attempted as a real client
-- action and must be refused by the database.

SET client_min_messages = warning;

-- ═════ Rule 10 — national_id unique across ALL members, DOB not future ═══════
SELECT probe.succeeds('rule10', 'a new unique national id is accepted', $sql$
  INSERT INTO public.members (family_id, kind, full_name, national_id,
                              dob, registered_at)
  VALUES (1, 'son', 'ابن جديد', '1000000000099', '2010-01-01', '2026-01-01')
$sql$);

-- Cross-FAMILY duplicate: family 2's father's id reused inside family 1. The
-- prototype's nationalExists() scanned an array for this; here it is an index.
SELECT probe.raises_like('rule10', 'duplicate national id is refused', $sql$
  INSERT INTO public.members (family_id, kind, full_name, national_id,
                              dob, registered_at)
  VALUES (1, 'son', 'مكرر', '1000000000005', '2010-01-01', '2026-01-01')
$sql$, '23505', '%uq_members_national_id%');

SELECT probe.raises('rule10', 'future date of birth is refused', $sql$
  INSERT INTO public.members (family_id, kind, full_name, national_id,
                              dob, registered_at)
  VALUES (1, 'son', 'مستقبلي', '1000000000098',
          (current_date + 1)::date, '2026-01-01')
$sql$, 'RUL10');

SELECT probe.raises('rule10', 'DOB cannot be edited into the future either', $sql$
  UPDATE public.members SET dob = (current_date + 30)::date WHERE id = 2
$sql$, 'RUL10');

-- One father per family.
SELECT probe.raises_like('rule10', 'a second father in one family is refused', $sql$
  INSERT INTO public.members (family_id, kind, full_name, national_id,
                              dob, registered_at)
  VALUES (1, 'father', 'أب ثانٍ', '1000000000097', '1980-01-01', '2026-01-01')
$sql$, '23505', '%uq_members_one_father%');

-- Clean up the extra son so the fee maths below stays predictable.
DELETE FROM public.members WHERE national_id = '1000000000099';

-- ═════ Rules 1, 3 — eligibility at period end; total > 0 or skip ═════════════
-- Runs as the finance manager, through the RPC, exactly as the app will.
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');

SELECT probe.eq('rule01_03', 'generate raises 2 receivables, skips none',
  $sql$ SELECT (public.generate_period('2026-03') -> 'created')::text $sql$, '2');

-- F-0001: father نشط (20) + 2 sons aged >= 16 at 2026-03-31 (10 each) = 40.
-- The son born 2019 is 6 and must NOT be billed.
SELECT probe.eq('rule01_03', 'family 1 total is 40.00 (father + 2 eligible sons)',
  $sql$ SELECT total::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-03' $sql$, '40.00');

-- F-0002: father موقوف contributes nothing, one eligible son = 10.
SELECT probe.eq('rule01_03', 'suspended father is not billed, only his son',
  $sql$ SELECT total::text FROM public.receivables
         WHERE family_id = 2 AND period = '2026-03' $sql$, '10.00');

SELECT probe.eq('rule01_03', 'lines sum to total (SUM(fee_amount) = total)',
  $sql$ SELECT count(*)::text FROM public.receivables r
         WHERE r.status <> 'ملغي'
           AND r.total <> (SELECT coalesce(sum(l.fee_amount),0)
                             FROM public.receivable_lines l
                            WHERE l.receivable_id = r.id) $sql$, '0');

SELECT probe.eq('rule01_03', 'the under-age son has no receivable line',
  $sql$ SELECT count(*)::text FROM public.receivable_lines
         WHERE member_national_id = '1000000000004' $sql$, '0');

-- Rule 3: a zero total must produce no row at all.
SELECT probe.raises('rule03', 'a zero-total receivable is refused', $sql$
  INSERT INTO public.receivables (family_id, period, period_end, father_fee,
    son_fee, father_name, eligibility_age_snapshot, warning_months_snapshot, total)
  VALUES (1, '2030-01', '2030-01-31', 0, 0, 'x', 16, 3, 0)
$sql$, '23514');

-- ═════ Rule 4 — one LIVE receivable per (family, period) ═════════════════════
SELECT probe.eq('rule04', 're-running the same period creates nothing',
  $sql$ SELECT (public.generate_period('2026-03') -> 'created')::text $sql$, '0');

SELECT probe.eq('rule04', '...and reports both families as skipped',
  $sql$ SELECT (public.generate_period('2026-03') -> 'skipped')::text $sql$, '2');

SELECT probe.raises_like('rule04', 'a direct duplicate insert is refused', $sql$
  INSERT INTO public.receivables (family_id, period, period_end, father_fee,
    son_fee, father_name, eligibility_age_snapshot, warning_months_snapshot, total)
  VALUES (1, '2026-03', '2026-03-31', 20, 10, 'x', 16, 3, 40)
$sql$, '23505', '%uq_recv_active_period%');

-- Cancelling frees the slot; the row itself stays forever.
SELECT probe.succeeds('rule04', 'cancelling a receivable frees its period slot', $sql$
  UPDATE public.receivables SET status = 'ملغي', cancelled_at = now(),
         cancel_reason = 'probe'
   WHERE family_id = 2 AND period = '2026-03'
$sql$);
SELECT probe.succeeds('rule04', 'the freed slot accepts a replacement', $sql$
  INSERT INTO public.receivables (family_id, period, period_end, father_fee,
    son_fee, father_name, eligibility_age_snapshot, warning_months_snapshot, total)
  VALUES (2, '2026-03', '2026-03-31', 20, 10, 'الأب الثاني', 16, 3, 10)
$sql$);
SELECT probe.eq('rule04', 'both the cancelled and the replacement row survive',
  $sql$ SELECT count(*)::text FROM public.receivables
         WHERE family_id = 2 AND period = '2026-03' $sql$, '2');

-- ═════ Rule 5 — receivables are immutable snapshots ══════════════════════════
SELECT probe.raises('rule05', 'total cannot be edited', $sql$
  UPDATE public.receivables SET total = 999 WHERE family_id = 1 AND period = '2026-03'
$sql$, 'RUL05');

SELECT probe.raises('rule05', 'the fee snapshot cannot be edited', $sql$
  UPDATE public.receivables SET son_fee = 1 WHERE family_id = 1 AND period = '2026-03'
$sql$, 'RUL05');

SELECT probe.raises('rule05', 'the period cannot be moved', $sql$
  UPDATE public.receivables SET period = '2026-04' WHERE family_id = 1 AND period = '2026-03'
$sql$, 'RUL05');

-- The point of rule 5: changing settings must not touch history.
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');   -- admin
SELECT probe.succeeds('rule05', 'settings can be changed', $sql$
  SELECT public.update_settings('{"sonFee":"999.00","fatherFee":"888.00"}'::jsonb)
$sql$);
SELECT probe.eq('rule05', 'the historical receivable is unchanged by it',
  $sql$ SELECT total::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-03' $sql$, '40.00');
SELECT probe.succeeds('rule05', 'restore the fees', $sql$
  SELECT public.update_settings('{"sonFee":"10.00","fatherFee":"20.00"}'::jsonb)
$sql$);

-- ═════ Rules 7, 8 — payment bounds, FIFO order, one cash movement ════════════
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');   -- finance manager
SELECT probe.succeeds('rule07', 'raise a second, older period to test FIFO', $sql$
  SELECT public.generate_period('2026-02')
$sql$);

SELECT probe.become('00000000-0000-0000-0000-0000000000a3');   -- treasurer

SELECT probe.raises('rule07', 'a zero payment is refused', $sql$
  SELECT public.register_payment(1, 0, 'نقداً')
$sql$, 'RUL07');

SELECT probe.raises('rule07', 'a negative payment is refused', $sql$
  SELECT public.register_payment(1, -50, 'نقداً')
$sql$, 'RUL07');

-- Family 1 owes 40 (March) + 40 (February) = 80.
SELECT probe.eq('rule07', 'outstanding for family 1 is 80.00',
  $sql$ SELECT sum(balance)::text FROM public.receivables
         WHERE family_id = 1 AND status <> 'ملغي' $sql$, '80.00');

SELECT probe.raises('rule07', 'paying more than is owed is refused', $sql$
  SELECT public.register_payment(1, 80.01, 'نقداً')
$sql$, 'RUL07');

-- 50 must fill February (the OLDER period) first, then spill 10 into March.
SELECT probe.succeeds('rule07', 'a 50.00 payment is accepted', $sql$
  SELECT public.register_payment(1, 50, 'نقداً', 'ref-1', 'أمين الصندوق')
$sql$);

SELECT probe.eq('rule07', 'FIFO filled February first, in full',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-02' $sql$, '40.00');
SELECT probe.eq('rule07', '...and spilled the remaining 10 into March',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-03' $sql$, '10.00');
SELECT probe.eq('rule07', 'sequence_no records February as allocation 1',
  $sql$ SELECT period FROM public.payment_allocations
         WHERE payment_id = 1 AND sequence_no = 1 $sql$, '2026-02');

SELECT probe.eq('rule07', 'February is now مسدد بالكامل',
  $sql$ SELECT status::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-02' $sql$, 'مسدد بالكامل');
SELECT probe.eq('rule07', 'March is now مسدد جزئياً',
  $sql$ SELECT status::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-03' $sql$, 'مسدد جزئياً');

-- The storage-engine backstop, reached directly rather than through the RPC.
SELECT probe.raises('rule07', 'paid > total is refused by the constraint', $sql$
  UPDATE public.receivables SET paid = total + 1
   WHERE family_id = 1 AND period = '2026-03'
$sql$, '23514');
SELECT probe.raises('rule07', 'negative paid is refused by the constraint', $sql$
  UPDATE public.receivables SET paid = -1 WHERE family_id = 1 AND period = '2026-03'
$sql$, '23514');

-- Rule 8.
SELECT probe.eq('rule08', 'the payment wrote exactly one cash movement',
  $sql$ SELECT count(*)::text FROM public.cash_movements WHERE payment_id = 1 $sql$, '1');
SELECT probe.eq('rule08', 'the cash movement mirrors the payment amount',
  $sql$ SELECT amount::text FROM public.cash_movements WHERE payment_id = 1 $sql$, '50.00');
SELECT probe.raises_like('rule08', 'a second cash movement for it is refused', $sql$
  INSERT INTO public.cash_movements (payment_id, family_id, amount, method, occurred_at)
  VALUES (1, 1, 50, 'نقداً', now())
$sql$, '23505', '%uq_cash_payment%');

-- ═════ Rule 9 — cancellation reverses and preserves ══════════════════════════
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');   -- finance manager

SELECT probe.raises('rule09', 'cancelling without a reason is refused', $sql$
  SELECT public.cancel_payment(1, '   ')
$sql$, 'RUL09');

SELECT probe.succeeds('rule09', 'cancelling with a reason succeeds', $sql$
  SELECT public.cancel_payment(1, 'خطأ في الإدخال')
$sql$);

SELECT probe.eq('rule09', 'February is back to unpaid',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-02' $sql$, '0.00');
SELECT probe.eq('rule09', 'March is back to unpaid',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-03' $sql$, '0.00');
SELECT probe.eq('rule09', 'February status reverted to غير مسدد',
  $sql$ SELECT status::text FROM public.receivables
         WHERE family_id = 1 AND period = '2026-02' $sql$, 'غير مسدد');
SELECT probe.eq('rule09', 'the allocation rows were PRESERVED, not deleted',
  $sql$ SELECT count(*)::text FROM public.payment_allocations WHERE payment_id = 1 $sql$, '2');
SELECT probe.eq('rule09', 'the cash movement is voided, not removed',
  $sql$ SELECT status::text FROM public.cash_movements WHERE payment_id = 1 $sql$, 'ملغي');
SELECT probe.eq('rule09', 'the voided movement is out of the treasury total',
  -- '0.00', not '0'. Every money value is two decimal places now: the aggregate
  -- is cast to numeric(12,2) before text, so an empty bucket formats like every
  -- other amount on the same screen instead of standing out as a bare integer.
  $sql$ SELECT "total" FROM public.v_cash_summary $sql$, '0.00');
SELECT probe.raises('rule09', 'double cancellation is refused', $sql$
  SELECT public.cancel_payment(1, 'مرة أخرى')
$sql$, 'RUL09');

-- Nothing financial can be hard-deleted, by anyone.
SELECT probe.raises('rule09', 'payments cannot be deleted',
  'DELETE FROM public.payments WHERE id = 1', 'RUL09');
SELECT probe.raises('rule09', 'allocations cannot be deleted',
  'DELETE FROM public.payment_allocations WHERE payment_id = 1', 'RUL09');
SELECT probe.raises('rule09', 'receivables cannot be deleted',
  'DELETE FROM public.receivables WHERE family_id = 1', 'RUL09');
SELECT probe.raises('rule09', 'receivable lines cannot be deleted',
  'DELETE FROM public.receivable_lines WHERE id = 1', 'RUL09');
SELECT probe.raises('rule09', 'cash movements cannot be deleted',
  'DELETE FROM public.cash_movements WHERE payment_id = 1', 'RUL09');

-- ═════ Rule 6 — auto-close backfills system_start → previous month ═══════════
SELECT probe.succeeds('rule06', 'auto-close runs', $sql$
  SELECT public.auto_close_periods()
$sql$);
SELECT probe.eq('rule06', 'it covered every month from system_start to last month',
  $sql$ SELECT count(DISTINCT period)::text FROM public.receivables $sql$,
  (SELECT (extract(year FROM age(date_trunc('month', current_date)
                                 - interval '1 month', date '2026-01-01')) * 12
         + extract(month FROM age(date_trunc('month', current_date)
                                 - interval '1 month', date '2026-01-01')) + 1)::int::text));
SELECT probe.eq('rule06', 'it did NOT bill the current month',
  $sql$ SELECT count(*)::text FROM public.receivables
         WHERE period = to_char(current_date, 'YYYY-MM') $sql$, '0');
SELECT probe.eq('rule06', 'running it twice creates nothing new',
  $sql$ SELECT (public.auto_close_periods() -> 'created')::text $sql$, '0');

-- ═════ Rule 12 — the audit trail is append-only ══════════════════════════════
SELECT probe.eq('rule12', 'the payment and its cancellation were both logged',
  $sql$ SELECT count(*)::text FROM public.audit_log
         WHERE event_type IN ('payment.register','payment.cancel') $sql$, '2');
SELECT probe.eq('rule12', 'the actor name was snapshotted onto the entry',
  $sql$ SELECT actor_name FROM public.audit_log
         WHERE event_type = 'payment.cancel' $sql$, 'المدير المالي');
SELECT probe.raises('rule12', 'an audit row cannot be edited',
  'UPDATE public.audit_log SET detail = ''tampered'' WHERE id = 1', 'RUL12');
SELECT probe.raises('rule12', 'an audit row cannot be deleted',
  'DELETE FROM public.audit_log WHERE id = 1', 'RUL12');

-- ═════ Rule 2 — "قريب من السن" within warning_months ═════════════════════════
-- Derived, never stored. A son whose 16th birthday is 2 months out must read
-- 'soon' with warning_months = 3, and 'under' once it is 4 months out.
SELECT probe.succeeds('rule02', 'add a son turning 16 in two months', $sql$
  INSERT INTO public.members (family_id, kind, full_name, national_id, dob,
                              registered_at)
  VALUES (1, 'son', 'قريب من السن', '1000000000090',
          (current_date + interval '2 months' - interval '16 years')::date,
          current_date)
$sql$);
SELECT probe.eq('rule02', 'he reads as soon',
  $sql$ SELECT "eligibility" FROM public.v_members
         WHERE "nationalId" = '1000000000090' $sql$, 'soon');
SELECT probe.succeeds('rule02', 'add a son turning 16 in five months', $sql$
  INSERT INTO public.members (family_id, kind, full_name, national_id, dob,
                              registered_at)
  VALUES (1, 'son', 'بعيد عن السن', '1000000000091',
          (current_date + interval '5 months' - interval '16 years')::date,
          current_date)
$sql$);
SELECT probe.eq('rule02', 'he reads as under, not soon',
  $sql$ SELECT "eligibility" FROM public.v_members
         WHERE "nationalId" = '1000000000091' $sql$, 'under');
-- Rule 1's "status overrides age" clause.
SELECT probe.succeeds('rule02', 'suspend an over-age son',
  $sql$ UPDATE public.members SET status = 'موقوف' WHERE national_id = '1000000000002' $sql$);
SELECT probe.eq('rule02', 'a suspended over-age son reads inactive, not eligible',
  $sql$ SELECT "eligibility" FROM public.v_members
         WHERE "nationalId" = '1000000000002' $sql$, 'inactive');
SELECT probe.succeeds('rule02', 'un-suspend him',
  $sql$ UPDATE public.members SET status = 'نشط' WHERE national_id = '1000000000002' $sql$);

-- ═════ Rule 11 — the statement is a chronological merge ══════════════════════
-- Not a stored artefact; asserted as the identity that makes it correct:
-- issued - collected = outstanding, across the whole ledger.
SELECT probe.eq('rule11', 'issued - collected = outstanding, ledger-wide',
  $sql$ SELECT (
      (SELECT coalesce(sum(total),0) FROM public.receivables WHERE status <> 'ملغي')
    - (SELECT coalesce(sum(paid),0)  FROM public.receivables WHERE status <> 'ملغي')
    - (SELECT coalesce(sum(balance),0) FROM public.receivables WHERE status <> 'ملغي')
  )::text $sql$, '0.00');
SELECT probe.eq('rule11', 'every allocation ties to a live receivable',
  $sql$ SELECT count(*)::text FROM public.payment_allocations a
         WHERE NOT EXISTS (SELECT 1 FROM public.receivables r WHERE r.id = a.receivable_id) $sql$, '0');
SELECT probe.eq('rule11', 'approved payments equal their cash movements',
  $sql$ SELECT count(*)::text FROM public.payments p
         WHERE p.status = 'معتمد'
           AND coalesce((SELECT c.amount FROM public.cash_movements c
                          WHERE c.payment_id = p.id), -1) <> p.amount $sql$, '0');
