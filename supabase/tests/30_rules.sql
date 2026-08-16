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

-- ═════ Rule 10 — what is LEFT of it: DOB not in the future ═══════════════════
-- The unique national ID was the other half and is gone at the association's
-- request. The check below is not a leftover — it PINS the consequence, so that
-- the day someone reads "rule 10" in a comment and assumes duplicates are still
-- impossible, this file says otherwise in as many words.
SELECT probe.succeeds('rule10', 'a new عديل is accepted', $sql$
  INSERT INTO public.adeels (full_name, dob, registered_at)
  VALUES ('عديل جديد', '2010-01-01', '2026-01-01')
$sql$);

-- ⚠ DUPLICATES ARE NOW POSSIBLE, and this asserts it rather than leaving it to
-- be discovered. The same name, the same date of birth, a second row, billed a
-- second time. Nothing in the schema refuses it; there is no natural key left.
-- If a UNIQUE constraint is ever added back — which now needs a column added
-- first, since subscription_no went too — THIS is the check that will fail and
-- tell you the guarantee returned.
SELECT probe.succeeds('rule10', 'a duplicate عديل is ACCEPTED — no natural key', $sql$
  INSERT INTO public.adeels (full_name, dob, registered_at)
  VALUES ('عديل جديد', '2010-01-01', '2026-01-01')
$sql$);
SELECT probe.eq('rule10', '...and there really are two of him now',
  $sql$ SELECT count(*)::text FROM public.adeels
         WHERE full_name = 'عديل جديد' $sql$, '2');

-- ── An edit must not erase what it was not told about ───────────────────────
-- save_adeel assigned `notes = p_adeel ->> 'notes'` unconditionally, and the
-- عديل form has no notes field, so it never sends the key: ->> returned NULL
-- and every edit silently wiped the note. The save succeeded, so nothing
-- reported it and only whoever wrote the note would ever know.
SELECT probe.succeeds('rule10', 'an عديل is given a note directly', $sql$
  UPDATE public.adeels SET notes = 'ملاحظة يجب أن تبقى'
   WHERE full_name = 'عديل جديد'
$sql$);
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');   -- finance manager
SELECT probe.succeeds('rule10', 'he is edited WITHOUT a notes key', $sql$
  SELECT public.save_adeel(
    (SELECT min(id) FROM public.adeels WHERE full_name = 'عديل جديد'),
    jsonb_build_object('fullName', 'عديل جديد', 'phone', '0910000000'))
$sql$);
SELECT probe.eq('rule10', '...and the note survived the edit',
  $sql$ SELECT notes FROM public.adeels
         WHERE id = (SELECT min(id) FROM public.adeels
                      WHERE full_name = 'عديل جديد') $sql$,
  'ملاحظة يجب أن تبقى');
-- The other direction: a key that IS sent, empty, still clears the field.
SELECT probe.succeeds('rule10', 'sending an empty notes key DOES clear it', $sql$
  SELECT public.save_adeel(
    (SELECT min(id) FROM public.adeels WHERE full_name = 'عديل جديد'),
    jsonb_build_object('fullName', 'عديل جديد', 'notes', ''))
$sql$);
SELECT probe.eq('rule10', '...so an absent key and an empty one differ',
  $sql$ SELECT notes FROM public.adeels
         WHERE id = (SELECT min(id) FROM public.adeels
                      WHERE full_name = 'عديل جديد') $sql$, '');

SELECT probe.raises('rule10', 'future date of birth is refused', $sql$
  INSERT INTO public.adeels (full_name, dob, registered_at)
  VALUES ('مستقبلي', (current_date + 1)::date, '2026-01-01')
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
          (SELECT max(id) FROM public.adeels WHERE full_name = 'عديل جديد')) $sql$);
SELECT probe.succeeds('rule10', '...and so can his duplicate',
  $sql$ SELECT public.delete_adeel(
          (SELECT max(id) FROM public.adeels WHERE full_name = 'عديل جديد')) $sql$);

-- ═════ Rule 15 — a month closes ONCE, IN ORDER, and inside the range ════════
-- The fixture's system_start is 2026-02, so February is the first month the
-- association may close and nothing before it exists to close.
SELECT probe.raises('rule15', 'a month before system_start is refused',
  $sql$ SELECT public.generate_period('2026-01') $sql$, 'RUL15');
SELECT probe.raises('rule15', 'the CURRENT month is refused — it has not ended',
  $sql$ SELECT public.generate_period(to_char(current_date, 'YYYY-MM')) $sql$,
  'RUL15');
-- 15b, before anything is closed: March cannot go first while February is open.
SELECT probe.raises('rule15', 'skipping a month is refused',
  $sql$ SELECT public.generate_period('2026-03') $sql$, 'RUL15');
SELECT probe.eq('rule15', '...and the refused month was NOT recorded as closed',
  $sql$ SELECT count(*)::text FROM public.closed_periods $sql$, '0');

SELECT probe.eq('rule15', 'the earliest open month IS accepted',
  $sql$ SELECT (public.generate_period('2026-02') -> 'created')::text $sql$, '2');
SELECT probe.eq('rule15', '...and is recorded as closed with its count',
  $sql$ SELECT created::text FROM public.closed_periods
         WHERE period = '2026-02' $sql$, '2');

-- ═════ Rule 3 — status gates the charge; total > 0 or skip ═══════════════════
-- Runs as the finance manager, through the RPC, exactly as the app will.
SELECT probe.eq('rule03', 'generate raises 2 receivables',
  $sql$ SELECT (public.generate_period('2026-03') -> 'created')::text $sql$, '2');

SELECT probe.raises('rule03', 're-closing the same month is refused (15a)',
  $sql$ SELECT public.generate_period('2026-03') $sql$, 'RUL15');

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

-- The name is now the ONLY identifying thing a receipt carries.
SELECT probe.eq('rule03', 'the snapshot carries his name',
  $sql$ SELECT adeel_name FROM public.receivables
         WHERE adeel_id = 1 AND period = '2026-03' $sql$,
  'العديل الأول');

-- Rule 3: a zero total must produce no row at all.
SELECT probe.raises('rule03', 'a zero-total receivable is refused', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name,
                                  total)
  VALUES (1, '2030-01', '2030-01-31', 'x', 0)
$sql$, '23514');

-- A fee of zero is a valid configuration and must raise nothing rather than
-- raising rows that ck_recv_total would refuse.
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');   -- admin
SELECT probe.succeeds('rule03', 'the fee can be set to zero',
  $sql$ SELECT public.update_settings('{"memberFee":"0.00"}'::jsonb) $sql$);
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');
SELECT probe.eq('rule03', 'a zero fee creates no receivables at all',
  $sql$ SELECT (public.generate_period('2026-04') -> 'created')::text $sql$, '0');
-- THE case closed_periods exists for. A month that billed nobody is still
-- CLOSED; if it were not, rule 15b would block every month after it forever and
-- the association could never close another period.
SELECT probe.eq('rule03', 'a month that billed nobody is still closed',
  $sql$ SELECT (EXISTS (SELECT 1 FROM public.closed_periods
                         WHERE period = '2026-04'))::text $sql$, 'true');
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');
SELECT probe.succeeds('rule03', 'restore the fee',
  $sql$ SELECT public.update_settings('{"memberFee":"20.00"}'::jsonb) $sql$);
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');

-- ═════ Rule 4 — one LIVE receivable per (عديل, period) ═══════════════════════
SELECT probe.raises_like('rule04', 'a direct duplicate insert is refused', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name,
                                  total)
  VALUES (1, '2026-03', '2026-03-31', 'x', 20)
$sql$, '23505', '%uq_recv_active_period%');

-- Cancelling frees the slot; the row itself stays forever.
SELECT probe.succeeds('rule04', 'cancelling a receivable frees its period slot', $sql$
  UPDATE public.receivables SET status = 'ملغي', cancelled_at = now(),
         cancel_reason = 'probe'
   WHERE adeel_id = 2 AND period = '2026-03'
$sql$);
SELECT probe.succeeds('rule04', 'the freed slot accepts a replacement', $sql$
  INSERT INTO public.receivables (adeel_id, period, period_end, adeel_name,
                                  total)
  VALUES (2, '2026-03', '2026-03-31', 'العديل الصغير', 20)
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

-- The trail has to name the FIGURE. update_settings used to write the bare string
-- 'تحديث إعدادات الجمعية' and no values, so raising the monthly fee — the one
-- number that decides every future charge — left an entry indistinguishable from
-- renaming the association. Both changes above carry both figures, so an entry
-- that names neither fails this.
SELECT probe.eq('rule05', 'the fee change is recorded with its before and after',
  $sql$ SELECT (count(*) >= 2)::text FROM public.audit_log
         WHERE event_type = 'settings.update'
           AND detail LIKE '%999.00%' AND detail LIKE '%20.00%' $sql$, 'true');

-- ═════ Rules 7, 8 — payment bounds, FIFO order, one cash movement ════════════
-- عديل 1 already owes two periods — 2026-02 and 2026-03, closed in that order
-- above — which is exactly the two the FIFO split below needs.
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
          'fullName','العديل الأول',
          'status','موقوف','registeredAt','2026-01-01')) $sql$);
SELECT probe.eq('rule09', 'his existing debt survives the retirement',
  $sql$ SELECT sum(balance)::text FROM public.receivables
         WHERE adeel_id = 1 AND status <> 'ملغي' $sql$, '40.00');
SELECT probe.succeeds('rule09', 'reactivate him',
  $sql$ SELECT public.save_adeel(1, jsonb_build_object(
          'fullName','العديل الأول',
          'status','نشط','registeredAt','2026-01-01')) $sql$);

-- ═════ Rule 6 — auto-close backfills system_start → previous month ═══════════
SELECT probe.succeeds('rule06', 'auto-close runs', $sql$
  SELECT public.auto_close_periods()
$sql$);
-- Counted from closed_periods, not from DISTINCT receivable periods: 2026-04 was
-- closed with a zero fee and billed nobody, so it has no receivable to be
-- distinct about. Counting the charges would report a month short and blame
-- auto-close for a gap that is not there.
SELECT probe.eq('rule06', 'it covered every month from system_start to last month',
  $sql$ SELECT count(*)::text FROM public.closed_periods $sql$,
  (SELECT (extract(year FROM age(date_trunc('month', current_date)
                                 - interval '1 month', date '2026-02-01')) * 12
         + extract(month FROM age(date_trunc('month', current_date)
                                 - interval '1 month', date '2026-02-01')) + 1)::int::text));
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
SELECT probe.eq('rule12', 'both عديل deletions are logged',
  $sql$ SELECT count(*)::text FROM public.audit_log
         WHERE event_type = 'adeel.delete' $sql$, '2');
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

-- ═════ The close-month picker's month list ═══════════════════════════════════
-- Not a business rule, but it feeds a button that raises money, and the range it
-- offers is a decision the database owns: system_start is a setting, and the
-- current month is excluded because it is not closed until it ends.
SELECT probe.eq('periods', 'the current month is NEVER offered for closing',
  $sql$ SELECT count(*)::text FROM jsonb_array_elements(public.api_closable_periods()) e
         WHERE e ->> 'period' = to_char(current_date, 'YYYY-MM') $sql$, '0');
SELECT probe.eq('periods', 'nothing earlier than system_start is offered',
  $sql$ SELECT count(*)::text FROM jsonb_array_elements(public.api_closable_periods()) e
         WHERE e ->> 'period'
             < to_char((SELECT system_start FROM public.association_settings
                         WHERE id = 1), 'YYYY-MM') $sql$, '0');
SELECT probe.eq('periods', 'every month carries an Arabic label, not a raw period',
  $sql$ SELECT count(*)::text FROM jsonb_array_elements(public.api_closable_periods()) e
         WHERE e ->> 'label' = e ->> 'period' $sql$, '0');
-- The two flags the picker turns into behaviour. By this point auto_close has
-- closed everything, so every month reads closed and NOTHING is selectable —
-- which is the correct state for a fully closed year and is what the screen
-- renders as "no month left to close".
SELECT probe.eq('periods', 'a closed month is flagged closed',
  $sql$ SELECT (e ->> 'closed') FROM jsonb_array_elements(public.api_closable_periods()) e
         WHERE e ->> 'period' = '2026-03' $sql$, 'true');
SELECT probe.eq('periods', 'with every month closed, none is selectable',
  $sql$ SELECT count(*)::text FROM jsonb_array_elements(public.api_closable_periods()) e
         WHERE (e ->> 'selectable')::boolean $sql$, '0');
-- And the rule the picker exists to express: at most ONE month is ever
-- selectable, because rule 15b accepts only the earliest open one. Proved by
-- reopening a gap — cancelling every receivable does NOT reopen a month, since
-- closure is an event, so the marker has to go for the month to be open again.
SELECT probe.succeeds('periods', 'clear one month back open',
  $sql$ ALTER TABLE public.closed_periods DISABLE TRIGGER trg_closed_no_delete $sql$);
SELECT probe.succeeds('periods', '...by removing two closure markers',
  $sql$ DELETE FROM public.closed_periods WHERE period IN ('2026-05','2026-06') $sql$);
SELECT probe.eq('periods', 'exactly ONE month is selectable, the earliest open one',
  $sql$ SELECT string_agg(e ->> 'period', ',')
          FROM jsonb_array_elements(public.api_closable_periods()) e
         WHERE (e ->> 'selectable')::boolean $sql$, '2026-05');
SELECT probe.raises('periods', 'and the LATER open month is still refused',
  $sql$ SELECT public.generate_period('2026-06') $sql$, 'RUL15');
SELECT probe.succeeds('periods', 'restore the markers',
  $sql$ INSERT INTO public.closed_periods (period, created)
        VALUES ('2026-05', 0), ('2026-06', 0) $sql$);
SELECT probe.succeeds('periods', 'and re-arm the delete guard',
  $sql$ ALTER TABLE public.closed_periods ENABLE TRIGGER trg_closed_no_delete $sql$);

-- ── An empty box must not blow up the whole save ─────────────────────────────
-- update_settings casts memberFee and systemStart. Those two lacked the
-- `nullif(..., '')` the officials beside them always had, so an EMPTY string —
-- which is what an Arabic keyboard left behind when the ASCII-only input filter
-- ate every digit — reached `''::numeric` and raised 22P02. That code carries no
-- Arabic text, so the app could only say "something went wrong", and the whole
-- save failed including the officials the admin was actually setting.
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');   -- admin
SELECT probe.succeeds('rule05', 'an empty memberFee leaves the fee alone', $sql$
  SELECT public.update_settings('{"memberFee":"","systemStart":""}'::jsonb)
$sql$);
SELECT probe.eq('rule05', '...and the fee is exactly what it was',
  $sql$ SELECT member_fee::text FROM public.association_settings WHERE id = 1 $sql$,
  '20.00');

-- ── Saving an official, which for a while was impossible in BOTH directions ──
-- These two are the whole reason to have them: `update_settings` had a defect
-- for each case, and between them they covered every input, so no combination
-- of dropdowns ever saved.
--
--   choosing one → 22P02  malformed array literal: "بيانات أمين الصندوق"
--       `v_changes` is text[] and the audit line appended a BARE literal, which
--       Postgres types as `unknown` and resolves to `anyarray || anyarray`.
--       Every other append goes through format(), which returns text, so only
--       the two officials' lines were affected.
--
--   leaving one vacant → 55000  record "v_t" is not assigned yet
--       `v_t` was a `record` filled only when a post was chosen, and the UPDATE
--       mentions `v_t.full_name` in a CASE arm. PL/pgSQL must know the tuple
--       structure to PLAN the statement, so the untaken branch never protected
--       it. Scalars replaced it: unset is simply NULL.
--
-- Neither is a rule, a permission or a constraint, which is why nothing else in
-- this suite would ever have caught them. They are asserted as plain successes
-- because that is exactly what was missing — the save going through at all.
SELECT probe.succeeds('rule05', 'an official can be appointed from the register',
  $sql$ SELECT public.update_settings(
          jsonb_build_object('treasurerAdeelId',
            (SELECT id FROM public.adeels ORDER BY id LIMIT 1))) $sql$);
SELECT probe.eq('rule05', '...and his name is snapshotted off his own row',
  $sql$ SELECT treasurer_name = (SELECT full_name FROM public.adeels
                                  ORDER BY id LIMIT 1)
          FROM public.association_settings WHERE id = 1 $sql$, 't');
SELECT probe.succeeds('rule05', 'and the post can be vacated again',
  $sql$ SELECT public.update_settings('{"treasurerAdeelId":null}'::jsonb) $sql$);
SELECT probe.eq('rule05', '...leaving the post empty, not the function broken',
  $sql$ SELECT treasurer_adeel_id IS NULL
          FROM public.association_settings WHERE id = 1 $sql$, 't');
-- The overlap rule still bites — the fixes above must not have unhooked it.
SELECT probe.raises('rule05', 'one man still cannot hold both posts',
  $sql$ SELECT public.update_settings(
          jsonb_build_object(
            'treasurerAdeelId', (SELECT id FROM public.adeels ORDER BY id LIMIT 1),
            'financeAdeelId',   (SELECT id FROM public.adeels ORDER BY id LIMIT 1))) $sql$,
  'RUL16');
