-- ═════════════════════════════════════════════════════════════════════════════
-- عهد المشتركين — money in the box that is NOT the association's to spend
--
-- A man may pay a year in advance. The cash arrives, rule 8 records it in
-- cash_movements, and the treasury counts it — correctly, because it really is
-- there. What it is NOT is earned: until the month it covers is billed, that
-- sum is a liability owed back to him.
--
-- Left inside the spendable balance it produced this, which is not a
-- presentation quibble but the association spending a member's deposit: he
-- hands over 60 in advance, one month closes so 20 of it is earned, and
-- رصيد الجمعية still reads 60 — so a voucher for 60 is accepted and his
-- remaining 40 is gone. Nothing on any screen said so, because until
-- members_held() existed nothing anywhere distinguished the two kinds of money.
--
-- Every check here is PAIRED: what the rule refuses, and what that same rule
-- still allows the instant the money stops being his. A guard that refused
-- every disbursement would satisfy half of this file on its own, and would be
-- indistinguishable from a correct one without the other half.
--
-- ── WHY THIS FILE RUNS AFTER THE PURGE ──────────────────────────────────────
-- It needs to CLOSE A MONTH, and by the time 67_disbursement runs, the groups
-- before it have closed every month between system_start and last month — so
-- rule 15 has nothing left to offer and the whole story is unrunnable. The
-- purge leaves settings and staff standing and wipes the ledger, which is
-- exactly the blank slate this needs: it builds its own register, its own
-- receipt and its own month, and depends on no fixture at all.
--
-- That also means the figures below are ABSOLUTE rather than differences.
-- Nothing else is in the ledger, so 60.00 means 60.00.
-- ═════════════════════════════════════════════════════════════════════════════
SELECT probe.become('00000000-0000-0000-0000-0000000000a1'::uuid,
                    'authenticated', 'admin');

SELECT public.save_adeel(NULL, jsonb_build_object(
  'fullName', 'مشترك العهدة', 'registeredAt', '2026-02-01', 'status', 'نشط'));

-- ── TAKING MONEY FROM A MAN WHO OWES NOTHING ────────────────────────────────
-- Rule 7 used to refuse this outright. It is the association's normal practice:
-- a member pays for the year when he has the money, not when the month falls.
SELECT probe.eq('held', 'a man who owes NOTHING can still be paid for',
  $sql$ SELECT (public.register_payment(
                  (SELECT id FROM public.adeels WHERE full_name = 'مشترك العهدة'),
                  60.00, 'نقداً', '2026-02-05') ->> 'credit') $sql$,
  '60.00');

SELECT probe.eq('held', '...and every unit of it is عهدة, not association money',
  $sql$ SELECT "heldForMembers" FROM public.v_cash_summary $sql$, '60.00');
SELECT probe.eq('held', '...so رصيد الجمعية did not move at all',
  $sql$ SELECT "balance" FROM public.v_cash_summary $sql$, '0.00');
-- The PAIR to the two above, and the check that stops "simply do not record it"
-- from passing both: the cash DID arrive, and the association's own books have
-- to say so or it is short 60 by its own reckoning.
SELECT probe.eq('held', '...while the cash itself IS recorded as collected',
  $sql$ SELECT "total" FROM public.v_cash_summary $sql$, '60.00');

-- Two independent expressions for one quantity: the treasury's aggregate
-- (members_held) and the register's per-member wallet (v_adeels."credit"),
-- written in different files from different joins. A disagreement between them
-- is a member reading one figure and the treasurer another, with no third
-- number to say which is wrong.
SELECT probe.eq('held', 'the treasury total equals the sum of the member wallets',
  $sql$ SELECT (
    (SELECT "heldForMembers"::numeric FROM public.v_cash_summary)
    = (SELECT coalesce(sum("credit"::numeric), 0) FROM public.v_adeels))::text
  $sql$, 'true');

-- ── THE REFUSAL, AND THE ARITHMETIC IT HAS TO NAME ──────────────────────────
-- The box physically holds 60. An admin who has counted it and is then refused
-- a smaller figure will conclude the app is wrong — he is the one person who
-- can see the cash to check. So the message names both numbers and the reason.
SELECT probe.raises_like('held', 'the association cannot spend what it holds for him',
  $sql$ SELECT public.register_disbursement(
          1.00, 'جماعي', 'نقداً', NULL, 'حالات طارئة') $sql$,
  'RUL17', '%عهد للمشتركين%');
SELECT probe.raises_like('held', '...and the refusal names القابل للصرف, not the box',
  $sql$ SELECT public.register_disbursement(
          1.00, 'جماعي', 'نقداً', NULL, 'حالات طارئة') $sql$,
  'RUL17', '%القابل للصرف 0.00%');

-- ── CLOSING A MONTH IS WHAT EARNS IT ────────────────────────────────────────
-- عهدة is not frozen money. generate_period calls settle_from_credit per عديل
-- the instant it raises his receivable, so the transfer happens with no second
-- receipt and no action by anyone.
SELECT probe.eq('held', 'closing a month settles his عهدة against it',
  $sql$ SELECT (public.generate_period('2026-02') ->> 'creditApplied') $sql$,
  '20.00');
SELECT probe.eq('held', '...so exactly the month fee stopped being held',
  $sql$ SELECT "heldForMembers" FROM public.v_cash_summary $sql$, '40.00');
SELECT probe.eq('held', '...and exactly the month fee became spendable',
  $sql$ SELECT "balance" FROM public.v_cash_summary $sql$, '20.00');
-- He is not billed a second time for a month he had already paid for.
SELECT probe.eq('held', '...while he owes nothing for the month he prepaid',
  $sql$ SELECT balance::text FROM public.receivables
         WHERE period = '2026-02'
           AND adeel_id = (SELECT id FROM public.adeels
                            WHERE full_name = 'مشترك العهدة') $sql$, '0.00');
-- Nothing arrived at the treasury when the month closed — the money was already
-- there. This is the check that would catch a fix that double-counted it.
SELECT probe.eq('held', '...and no new money entered the treasury to do it',
  $sql$ SELECT "total" FROM public.v_cash_summary $sql$, '60.00');

-- ── THE PAIR: WHAT IS EARNED MAY BE SPENT ───────────────────────────────────
SELECT probe.succeeds('held', 'the association may spend what it has earned',
  $sql$ SELECT public.register_disbursement(
          20.00, 'جماعي', 'نقداً', NULL, 'حالات طارئة') $sql$);
SELECT probe.eq('held', '...which empties the spendable half and touches no عهدة',
  $sql$ SELECT ("balance" = '0.00' AND "heldForMembers" = '40.00')::text
          FROM public.v_cash_summary $sql$, 'true');
SELECT probe.raises_like('held', '...and one unit more is refused',
  $sql$ SELECT public.register_disbursement(
          1.00, 'جماعي', 'نقداً', NULL, 'حالات طارئة') $sql$,
  'RUL17', '%القابل للصرف%');

-- ── CANCELLING A RECEIPT READS THE SAME RULE BACKWARDS ──────────────────────
-- register_disbursement refuses to pay out what the association does not own;
-- cancel_payment must refuse to un-collect what has already been spent. Both
-- subtract عهد now, and they have to agree exactly — a gap between the two is
-- where the fund goes negative with nothing having refused anything.
--
-- Here: voiding the receipt removes 60 of cash and releases 40 of عهد, so the
-- spendable side falls by 20 — precisely the 20 already spent.
SELECT probe.raises_like('held', 'un-collecting money already spent is refused',
  $sql$ SELECT public.cancel_payment(
          (SELECT max(id) FROM public.payments), 'خطأ في الإدخال') $sql$,
  'RUL09', '%ألغِ سندات صرف%');
SELECT probe.eq('held', '...and the treasury was left exactly as it was',
  $sql$ SELECT ("total" = '60.00' AND "balance" = '0.00'
                AND "heldForMembers" = '40.00')::text
          FROM public.v_cash_summary $sql$, 'true');
-- The PAIR: reverse the voucher first and the same cancellation goes through.
-- This is the sequence the refusal above actually tells the treasurer to follow,
-- so it is the one that has to work.
SELECT probe.succeeds('held', 'reversing the voucher first clears the way',
  $sql$ SELECT public.cancel_disbursement(
          (SELECT max(id) FROM public.disbursements), 'تصحيح') $sql$);
SELECT probe.succeeds('held', '...and then the receipt cancels',
  $sql$ SELECT public.cancel_payment(
          (SELECT max(id) FROM public.payments), 'خطأ في الإدخال') $sql$);
SELECT probe.eq('held', '...leaving no cash, no عهدة and no negative anywhere',
  $sql$ SELECT ("total" = '0.00' AND "balance" = '0.00'
                AND "heldForMembers" = '0.00')::text
          FROM public.v_cash_summary $sql$, 'true');
-- And his month is owed again: rule 9 reverses the money, it does not forgive
-- the charge. Without this, a cancellation would be a way to clear a debt.
SELECT probe.eq('held', '...and the month he prepaid is owed once more',
  $sql$ SELECT balance::text FROM public.receivables
         WHERE period = '2026-02'
           AND adeel_id = (SELECT id FROM public.adeels
                            WHERE full_name = 'مشترك العهدة') $sql$, '20.00');

-- ── WHAT THE MEMBER IS TOLD ─────────────────────────────────────────────────
-- api_association_finance is SECURITY DEFINER and is the portal's only source
-- for these figures. If it counted عهد, every member would be shown his own
-- deposit — and everyone else's — as money the association holds and may spend.
SELECT probe.eq('held', 'the member-facing balance subtracts عهد the same way',
  $sql$ SELECT ((public.api_association_finance() ->> 'balance')::numeric
              = (public.api_association_finance() ->> 'collected')::numeric
              - (public.api_association_finance() ->> 'disbursed')::numeric
              - (public.api_association_finance() ->> 'heldForMembers')::numeric)::text
  $sql$, 'true');

SELECT probe.become(NULL);
