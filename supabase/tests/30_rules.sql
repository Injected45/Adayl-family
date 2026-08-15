-- 30_rules.sql — the business rules, each with a case that satisfies it and a
-- case that VIOLATES it.
--
-- The failing case is the only one that proves anything. A probe that merely
-- inserts a valid row demonstrates the column exists; it does not demonstrate
-- that the rule bites. Every violation below is attempted as a real client
-- action and must be refused by the database.
--
-- TWO RULES ARE GONE, not merely untested. Rule 1 ("eligibility is age at period
-- end") and rule 2 ("قريب من السن within warning_months") described an age gate
-- that no longer exists: every عديل is billed the same fee and age decides
-- nothing. What replaced rule 1 is asserted below under rule03 — membership
-- STATUS is now the only thing that gates a charge — and the group that used to
-- prove the opposite is the group most worth reading if the age gate is ever
-- proposed again.

SET client_min_messages = warning;

-- ═════ Rule 10 — national_id unique across ALL عدايل, DOB not future ═════════
SELECT probe.succeeds('rule10', 'a new unique national id is accepted', $sql$
  INSERT INTO public.adeels (full_name, national_id, dob, registered_at)
  VALUES ('عديل جديد', '1000000000099', '2010-01-01', '2026-01-01')
$sql$);

SELECT probe.raises_like('rule10', 'duplicate national id is refused', $sql$
  INSERT INTO public.adeels (full_name, national_id, dob, registered_at)
  VALUES ('مكرر', '1000000000001', '2010-01-01', '2026-01-01')
$sql$, '23505', '%uq_adeels_national_id%');

SELECT probe.raises('rule10', 'future date of birth is refused', $sql$
  INSERT INTO public.adeels (full_name, national_id, dob, registered_at)
  VALUES ('مستقبلي', '1000000000098', (current_date + 1)::date, '2026-01-01')
$sql$, 'RUL10');

SELECT probe.raises('rule10', 'DOB cannot be edited into the future either', $sql$
  UPDATE public.adeels SET dob = (current_date + 30)::date WHERE id = 2
$sql$, 'RUL10');

-- Remove the extra عديل so the fee arithmetic below stays predictable. Through
-- the RPC, because that is the only route a client has and it is the guard worth
-- exercising: he has no financial history yet, so it must succeed.
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');   -- finance manager
SELECT probe.succeeds('rule10', 'an عديل with no financial history can be deleted',
  $sql$ SELECT public.delete_adeel(
          (SELECT id FROM public.adeels WHERE national_id = '1000000000099')) $sql$);

-- ═════ Rule 3 — status gates the charge; total > 0 or skip ═══════════════════
-- Runs as the finance manager, through the RPC, exactly as the app will.
SELECT probe.eq('rule03', 'generate raises 2 receivables',
  $sql$ SELECT (public.generate_period('2026-03') -> 'created')::text $sql$, '2');

SELECT probe.eq('rule03', '...and skips the موقوف and the متوفى',
  $sql$ SELECT (public.generate_period('2026-03') -> 'skipped')::text $sql$, '4');

SELECT probe.eq('rule03', 'an active عديل is billed the flat member fee',
  $sql$ SELECT total::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-03' $sql$, '20.00');

-- THE replacement for rule 1. A 7-year-old is billed exactly like a 51-year-old,
-- because age is not consulted at all any more. If this ever reads 0 rows, an age
-- gate has been reintroduced somewhere.
SELECT probe.eq('rule03', 'a 7-year-old عديل is billed the same as anyone else',
  $sql$ SELECT total::text FROM public.receivables
         WHERE adeel_id = 2 AND period = '2026-03' $sql$, '20.00');

SELECT probe.eq('rule03', 'a موقوف عديل is not billed at all',
  $sql$ SELECT count(*)::text FROM public.receivables WHERE adeel_id = 3 $sql$, '0');

SELECT probe.eq('rule03', 'a متوفى عديل is not billed at all',
  $sql$ SELECT count(*)::text FROM public.receivables WHERE adeel_id = 4 $sql$, '0');

SELECT probe.eq('rule03', 'the snapshot carries his name and national id',
  $sql$ SELECT adeel_name || '/' || adeel_national_id FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-03' $sql$,
  'العديل الأول/1000000000001');

-- Rule 3: a zero total must produce no row at all.
SELECT probe.raises('rule03', 'a zero-total receivable is refused', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name,
                                  adeel_national_id, total)
  VALUES (1, '2030-01', '2030-01-31', 'x', 'y', 0)
$sql$, '23514');

-- A fee of zero is a valid configuration and must raise nothing rather than
-- raising rows that ck_recv_total would refuse.
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');   -- admin
SELECT probe.succeeds('rule03', 'the fee can be set to zero',
  $sql$ SELECT public.update_settings('{"memberFee":"0.00"}'::jsonb) $sql$);
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');
SELECT probe.eq('rule03', 'a zero fee creates no receivables at all',
  $sql$ SELECT (public.generate_period('2029-09') -> 'created')::text $sql$, '0');
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');
SELECT probe.succeeds('rule03', 'restore the fee',
  $sql$ SELECT public.update_settings('{"memberFee":"20.00"}'::jsonb) $sql$);
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');

-- ═════ Rule 4 — one LIVE receivable per (عديل, period) ═══════════════════════
SELECT probe.eq('rule04', 're-running the same period creates nothing',
  $sql$ SELECT (public.generate_period('2026-03') -> 'created')::text $sql$, '0');

SELECT probe.raises_like('rule04', 'a direct duplicate insert is refused', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name,
                                  adeel_national_id, total)
  VALUES (1, '2026-03', '2026-03-31', 'x', 'y', 20)
$sql$, '23505', '%uq_recv_active_period%');

-- Cancelling frees the slot; the row itself stays forever.
SELECT probe.succeeds('rule04', 'cancelling a receivable frees its period slot', $sql$
  UPDATE public.receivables SET status = 'ملغي', cancelled_at = now(),
         cancel_reason = 'probe'
   WHERE adeel_id = 2 AND period = '2026-03'
$sql$);
SELECT probe.succeeds('rule04', 'the freed slot accepts a replacement', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name,
                                  adeel_national_id, total)
  VALUES (2, '2026-03', '2026-03-31', 'العديل الصغير', '1000000000002', 20)
$sql$);
SELECT probe.eq('rule04', 'both the cancelled and the replacement row survive',
  $sql$ SELECT count(*)::text FROM public.receivables
         WHERE adeel_id = 2 AND period = '2026-03' $sql$, '2');

-- ═════ Rule 5 — receivables are immutable snapshots ══════════════════════════
SELECT probe.raises('rule05', 'total cannot be edited', $sql$
  UPDATE public.receivables SET total = 999 WHERE adeel_id = 1 AND period = '2026-03'
$sql$, 'RUL05');

SELECT probe.raises('rule05', 'the name snapshot cannot be edited', $sql$
  UPDATE public.receivables SET adeel_name = 'x' WHERE adeel_id = 1 AND period = '2026-03'
$sql$, 'RUL05');

SELECT probe.raises('rule05', 'the period cannot be moved', $sql$
  UPDATE public.receivables SET period = '2026-04' WHERE adeel_id = 1 AND period = '2026-03'
$sql$, 'RUL05');

SELECT probe.raises('rule05', 'the charge cannot be moved to another عديل', $sql$
  UPDATE public.receivables SET adeel_id = 2 WHERE adeel_id = 1 AND period = '2026-03'
$sql$, 'RUL05');

-- The point of rule 5: changing settings must not touch history.
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');   -- admin
SELECT probe.succeeds('rule05', 'settings can be changed', $sql$
  SELECT public.update_settings('{"memberFee":"999.00"}'::jsonb)
$sql$);
SELECT probe.eq('rule05', 'the historical receivable is unchanged by it',
  $sql$ SELECT total::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-03' $sql$, '20.00');
SELECT probe.succeeds('rule05', 'restore the fee', $sql$
  SELECT public.update_settings('{"memberFee":"20.00"}'::jsonb)
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

-- عديل 1 owes 20 (March) + 20 (February) = 40.
SELECT probe.eq('rule07', 'outstanding for عديل 1 is 40.00',
  $sql$ SELECT sum(balance)::text FROM public.receivables
         WHERE adeel_id = 1 AND status <> 'ملغي' $sql$, '40.00');

SELECT probe.raises('rule07', 'paying more than is owed is refused', $sql$
  SELECT public.register_payment(1, 40.01, 'نقداً')
$sql$, 'RUL07');

-- 30 must fill February (the OLDER period) first, then spill 10 into March.
SELECT probe.succeeds('rule07', 'a 30.00 payment is accepted', $sql$
  SELECT public.register_payment(1, 30, 'نقداً', 'ref-1', 'أمين الصندوق')
$sql$);

SELECT probe.eq('rule07', 'FIFO filled February first, in full',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-02' $sql$, '20.00');
SELECT probe.eq('rule07', '...and spilled the remaining 10 into March',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-03' $sql$, '10.00');
SELECT probe.eq('rule07', 'sequence_no records February as allocation 1',
  $sql$ SELECT period FROM public.payment_allocations
         WHERE payment_id = 1 AND sequence_no = 1 $sql$, '2026-02');

SELECT probe.eq('rule07', 'February is now مسدد بالكامل',
  $sql$ SELECT status::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-02' $sql$, 'مسدد بالكامل');
SELECT probe.eq('rule07', 'March is now مسدد جزئياً',
  $sql$ SELECT status::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-03' $sql$, 'مسدد جزئياً');

-- A payment for one عديل must never touch another's balance.
SELECT probe.eq('rule07', 'the other عديل was untouched by that payment',
  $sql$ SELECT coalesce(sum(paid),0)::text FROM public.receivables
         WHERE adeel_id = 2 AND status <> 'ملغي' $sql$, '0.00');

-- The storage-engine backstop, reached directly rather than through the RPC.
SELECT probe.raises('rule07', 'paid > total is refused by the constraint', $sql$
  UPDATE public.receivables SET paid = total + 1
   WHERE adeel_id = 1 AND period = '2026-03'
$sql$, '23514');
SELECT probe.raises('rule07', 'negative paid is refused by the constraint', $sql$
  UPDATE public.receivables SET paid = -1 WHERE adeel_id = 1 AND period = '2026-03'
$sql$, '23514');

-- Rule 8.
SELECT probe.eq('rule08', 'the payment wrote exactly one cash movement',
  $sql$ SELECT count(*)::text FROM public.cash_movements WHERE payment_id = 1 $sql$, '1');
SELECT probe.eq('rule08', 'the cash movement mirrors the payment amount',
  $sql$ SELECT amount::text FROM public.cash_movements WHERE payment_id = 1 $sql$, '30.00');
SELECT probe.raises_like('rule08', 'a second cash movement for it is refused', $sql$
  INSERT INTO public.cash_movements (payment_id, adeel_id, amount, method, occurred_at)
  VALUES (1, 1, 30, 'نقداً', now())
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
         WHERE adeel_id = 1 AND period = '2026-02' $sql$, '0.00');
SELECT probe.eq('rule09', 'March is back to unpaid',
  $sql$ SELECT paid::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-03' $sql$, '0.00');
SELECT probe.eq('rule09', 'February status reverted to غير مسدد',
  $sql$ SELECT status::text FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-02' $sql$, 'غير مسدد');
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
  'DELETE FROM public.receivables WHERE adeel_id = 1', 'RUL09');
SELECT probe.raises('rule09', 'cash movements cannot be deleted',
  'DELETE FROM public.cash_movements WHERE payment_id = 1', 'RUL09');

-- And an عديل who HAS financial history cannot be deleted either — the escape
-- hatch delete_adeel() opens for a mistyped entry must close the moment money is
-- attached to him, or a receipt would be left pointing at nobody.
SELECT probe.raises('rule09', 'an عديل with a ledger cannot be deleted',
  'SELECT public.delete_adeel(1)', 'RUL10');
SELECT probe.succeeds('rule09', 'retiring him with a status change is the way',
  $sql$ SELECT public.save_adeel(1, jsonb_build_object(
          'fullName','العديل الأول','nationalId','1000000000001',
          'status','موقوف','registeredAt','2026-01-01')) $sql$);
SELECT probe.eq('rule09', 'his existing debt survives the retirement',
  $sql$ SELECT sum(balance)::text FROM public.receivables
         WHERE adeel_id = 1 AND status <> 'ملغي' $sql$, '40.00');
SELECT probe.succeeds('rule09', 'reactivate him',
  $sql$ SELECT public.save_adeel(1, jsonb_build_object(
          'fullName','العديل الأول','nationalId','1000000000001',
          'status','نشط','registeredAt','2026-01-01')) $sql$);

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
SELECT probe.eq('rule12', 'deleting an عديل is logged',
  $sql$ SELECT count(*)::text FROM public.audit_log
         WHERE event_type = 'adeel.delete' $sql$, '1');
SELECT probe.raises('rule12', 'an audit row cannot be edited',
  'UPDATE public.audit_log SET detail = ''tampered'' WHERE id = 1', 'RUL12');
SELECT probe.raises('rule12', 'an audit row cannot be deleted',
  'DELETE FROM public.audit_log WHERE id = 1', 'RUL12');

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
-- Asserted as an identity rather than a literal: auto_close above backfilled
-- every month from system_start, so the figure moves with the calendar. What
-- must hold is that the statement's running balance lands exactly on the
-- outstanding total — a hardcoded number would have to be edited every month and
-- would stop testing anything the day someone edited it wrong.
SELECT probe.eq('rule11', 'the statement closes at the outstanding balance',
  $sql$ SELECT ((public.api_adeel_statement(1) ->> 'closingBalance')::numeric
              = (SELECT coalesce(sum(balance),0) FROM public.receivables
                  WHERE adeel_id = 1 AND status <> 'ملغي'))::text $sql$, 'true');
