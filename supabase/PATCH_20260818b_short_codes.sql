-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-18 (b).  ترقيم أقصر: A-01، PAY-01، EXP-01.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  WHAT THIS DOES
--    Re-shapes the three generated identifier columns, at the association's
--    request — they read these aloud and write them on paper, and four leading
--    zeros carry nothing:
--
--      adeels.adeel_code        A-0004    → A-04
--      payments.receipt_no      PAY-000008 → PAY-08
--      disbursements.voucher_no EXP-000001 → EXP-01
--
--  ⚠ IT REWRITES EXISTING IDENTIFIERS. Every code and every receipt number
--    already issued changes. Two consequences the association should know:
--
--      • a receipt handed to a member on paper carries the OLD number, and
--        nothing in the app will match it any more;
--      • the audit trail is append-only (rule 12) and its `ref` column holds
--        the code AS IT WAS. Entries written before this patch keep saying
--        A-0001; entries after say A-01. That mismatch is permanent and
--        deliberate — rewriting history to tidy it would be the worse fault.
--
--    No money changes. No row is added or removed. Only the text of three
--    generated columns, which Postgres recomputes from the id it always used.
--
--  ⚠ TWO DIGITS AS A MINIMUM, NEVER AS A WIDTH — and this is the part that
--    would have been a data-loss bug written the obvious way:
--
--        lpad(id::text, 2, '0')
--
--    lpad TRUNCATES when the string is longer than the width, so id 100 becomes
--    '10' — the same code as id 10. `adeel_code` and `receipt_no` are both
--    UNIQUE, so the association's hundredth عديل and its hundredth receipt would
--    simply fail to be recorded, with a constraint violation naming a column
--    nobody typed. The CASE below pads what is short and leaves the rest alone:
--    A-01 … A-09, A-10 … A-99, A-100, A-101.
--
--  ── WHY SIX VIEWS ARE DROPPED AND REBUILT ──────────────────────────────────
--  Postgres cannot alter a generated column's expression: the column has to be
--  dropped and re-added. Six views read these three columns, and a view holds a
--  hard dependency on every column it names — so they block the DROP and have
--  to go first. They are recreated below from the same text that is in
--  supabase/migrations/20260811091000_api_surface.sql, verbatim.
--
--  Dropping a view also drops its grants, so SELECT is re-granted at the end and
--  assert_views_security_invoker() re-proves that none of them came back
--  bypassing RLS. Nothing else about them changes — same columns, same names,
--  same casts.
--
--  Nothing here is destructive to DATA. No DROP TABLE, no TRUNCATE, no DELETE,
--  and no row is touched. assert_signin_intact() runs before COMMIT.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes. Safe to run twice.
--    Requires PATCH_20260817_device_lock.sql — check with WHICH_STATE.sql.
-- ============================================================================

BEGIN;

-- == 0. The prerequisite, stated rather than assumed ========================
DO $prereq$
BEGIN
  IF to_regclass('public.disbursements') IS NULL THEN
    RAISE EXCEPTION
      'PATCH_20260817_device_lock.sql has not been applied here: public.disbursements does not exist. Apply that first — see supabase/WHICH_STATE.sql.';
  END IF;
END $prereq$;

-- == 1. The views that read the three columns ==============================
-- They are recreated in §5, unchanged. Dropped rather than replaced because a
-- CREATE OR REPLACE cannot outlive the column it selects.
DROP VIEW IF EXISTS public.v_users;
DROP VIEW IF EXISTS public.v_disbursements;
DROP VIEW IF EXISTS public.v_cash_movements;
DROP VIEW IF EXISTS public.v_payments;
DROP VIEW IF EXISTS public.v_receivables;
DROP VIEW IF EXISTS public.v_adeels;

-- == 2. A-0004 → A-04 =======================================================
-- The UNIQUE constraint goes with the column and comes back with it. Postgres
-- recomputes the value for every existing row from the id it already had, so
-- the register keeps its order and its identities — only the text changes.
ALTER TABLE public.adeels DROP COLUMN adeel_code;
ALTER TABLE public.adeels
  ADD COLUMN adeel_code text
  GENERATED ALWAYS AS ('A-' || CASE WHEN id < 10 THEN '0' ELSE '' END || id::text)
  STORED;
ALTER TABLE public.adeels ADD CONSTRAINT uq_adeels_code UNIQUE (adeel_code);

-- == 3. PAY-000008 → PAY-08 =================================================
ALTER TABLE public.payments DROP COLUMN receipt_no;
ALTER TABLE public.payments
  ADD COLUMN receipt_no text
  GENERATED ALWAYS AS ('PAY-' || CASE WHEN id < 10 THEN '0' ELSE '' END || id::text)
  STORED;
ALTER TABLE public.payments ADD CONSTRAINT uq_pay_receipt UNIQUE (receipt_no);

-- == 4. EXP-000001 → EXP-01 =================================================
-- No UNIQUE constraint here and none is added: the value is derived from the
-- primary key, so two vouchers cannot share one by construction.
ALTER TABLE public.disbursements DROP COLUMN voucher_no;
ALTER TABLE public.disbursements
  ADD COLUMN voucher_no text
  GENERATED ALWAYS AS ('EXP-' || CASE WHEN id < 10 THEN '0' ELSE '' END || id::text)
  STORED;

-- == 5. The views, back exactly as they were ================================

CREATE VIEW public.v_adeels WITH (security_invoker = on) AS
SELECT
  a.id                                    AS "id",
  a.adeel_code                            AS "adeelCode",
  a.full_name                             AS "fullName",
  coalesce(a.phone, '')                   AS "phone",
  coalesce(a.notes, '')                   AS "notes",
  to_char(a.registered_at, 'YYYY-MM-DD')  AS "registeredAt",
  to_char(a.dob, 'YYYY-MM-DD')            AS "dob",
  CASE WHEN a.dob IS NULL THEN NULL
       ELSE extract(year FROM age(current_date, a.dob))::int END AS "age",
  a.status::text                          AS "membershipStatus",
  coalesce(agg.debt,   0)::numeric(12,2)::text AS "debt",
  coalesce(agg.paid,   0)::numeric(12,2)::text AS "paid",
  coalesce(agg.issued, 0)::numeric(12,2)::text AS "issued",
  (CASE WHEN a.status = 'نشط' THEN s.member_fee ELSE 0 END)::numeric(12,2)::text
                                          AS "monthlyExpected",
  -- ── The wallet: money received that no month has claimed yet ──────────────
  -- DERIVED, never stored. Σ what he handed over, minus Σ what the allocations
  -- assigned to a receivable. A column would be a second place the truth could
  -- live, and the first time it disagreed with the allocations there would be
  -- no way to tell which was right.
  --
  -- Cancelled payments are excluded on the way in; their allocations were
  -- already reversed by cancel_payment, so counting the payment would resurrect
  -- money the association gave back.
  --
  -- GREATEST(...,0) is a floor, not a fix: allocations can never exceed their
  -- payment (register_payment refuses a negative remainder, settle_from_credit
  -- takes the least of the two), so a negative here would be a bug — and a
  -- NEGATIVE wallet displayed as a debt would hide it. The floor keeps the
  -- screen honest while `debt` goes on showing what is actually owed.
  greatest(coalesce(wallet.credit, 0), 0)::numeric(12,2)::text AS "credit",
  -- What he is, in one signed figure: positive owes, negative in hand. The
  -- portal paints it red or green off the sign, so the two states are one
  -- reading rather than two panels the member has to reconcile himself.
  (coalesce(agg.debt, 0) - greatest(coalesce(wallet.credit, 0), 0))
    ::numeric(12,2)::text                 AS "netBalance"
FROM public.adeels a
CROSS JOIN public.association_settings s
LEFT JOIN LATERAL (
  SELECT sum(r.balance) AS debt, sum(r.paid) AS paid, sum(r.total) AS issued
    FROM public.receivables r
   WHERE r.adeel_id = a.id AND r.status <> 'ملغي'
) agg ON true
LEFT JOIN LATERAL (
  SELECT sum(p.amount) - coalesce(sum(al.allocated), 0) AS credit
    FROM public.payments p
    LEFT JOIN LATERAL (
      SELECT sum(a2.amount) AS allocated
        FROM public.payment_allocations a2
       WHERE a2.payment_id = p.id
    ) al ON true
   WHERE p.adeel_id = a.id AND p.status <> 'ملغي'
) wallet ON true;

CREATE VIEW public.v_receivables WITH (security_invoker = on) AS
SELECT
  r.id                          AS "id",
  r.adeel_id                    AS "adeelId",
  r.adeel_name                  AS "adeelName",
  a.adeel_code                  AS "adeelCode",
  r.period                      AS "period",
  public.period_label(r.period) AS "periodLabel",
  to_char(r.period_end, 'YYYY-MM-DD') AS "periodEnd",
  r.total::text                 AS "total",
  r.paid::text                  AS "paid",
  r.balance::text               AS "balance",
  r.status::text                AS "status"
FROM public.receivables r
JOIN public.adeels a ON a.id = r.adeel_id;

CREATE VIEW public.v_payments WITH (security_invoker = on) AS
SELECT
  p.id                       AS "id",
  p.receipt_no               AS "receiptNo",
  p.adeel_id                 AS "adeelId",
  a.full_name                AS "adeelName",
  a.adeel_code               AS "adeelCode",
  p.amount::text             AS "amount",
  p.method::text             AS "method",
  coalesce(p.reference, '')  AS "reference",
  coalesce(p.receiver, '')   AS "receiver",
  coalesce(p.notes, '')      AS "notes",
  p.status::text             AS "status",
  to_char(p.paid_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "paidAt",
  coalesce(
    (SELECT jsonb_agg(
              jsonb_build_object(
                'receivableId', al.receivable_id,
                'period', al.period,
                'amount', al.amount::text)
              ORDER BY al.sequence_no)
       FROM public.payment_allocations al
      WHERE al.payment_id = p.id),
    '[]'::jsonb
  )                          AS "allocations",
  -- ── APPENDED, and it has to stay that way ─────────────────────────────────
  -- CREATE OR REPLACE VIEW can add columns to the END of the list and nothing
  -- else: inserting these two after `notes`, where they read more naturally,
  -- makes Postgres try to rename the existing `status` column and refuse with
  -- 42P16. A fresh apply would not notice — the view is created, not replaced —
  -- so it would fail only on the live project, which is the worst place to find
  -- out. Anything added later goes below these, for the same reason.
  --
  -- The PAYER'S account, as he gave it for THIS transfer — recorded on the row
  -- because a member may transfer from more than one account and more than one
  -- bank. Empty string for cash, which has no sending account.
  coalesce(p.bank_account_no, '')   AS "bankAccountNo",
  coalesce(p.bank_account_name, '') AS "bankAccountName",
  coalesce(p.bank_name, '')         AS "bankName"
FROM public.payments p
JOIN public.adeels a ON a.id = p.adeel_id;

CREATE VIEW public.v_cash_movements WITH (security_invoker = on) AS
SELECT
  c.id                       AS "id",
  p.receipt_no               AS "receiptNo",
  a.full_name                AS "adeelName",
  a.adeel_code               AS "adeelCode",
  c.adeel_id                 AS "adeelId",
  c.amount::text             AS "amount",
  c.method::text             AS "method",
  c.movement_type::text      AS "movementType",
  c.status::text             AS "status",
  to_char(c.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "occurredAt"
FROM public.cash_movements c
JOIN public.payments p ON p.id = c.payment_id
JOIN public.adeels a   ON a.id = c.adeel_id;

CREATE VIEW public.v_users WITH (security_invoker = on) AS
SELECT
  p.id::text            AS "id",
  p.email               AS "email",
  p.display_name        AS "displayName",
  p.role::text          AS "role",
  p.status::text        AS "status",
  to_char(p.last_login_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                        AS "lastLoginAt",
  approver.display_name AS "approvedByName",
  -- NULL for staff. Non-NULL marks a portal account, which stores `viewer` in
  -- `role` and would otherwise be indistinguishable on the users screen from a
  -- real viewer — while actually seeing far less, and something different.
  ad.adeel_code         AS "adeelCode"
FROM public.profiles p
LEFT JOIN public.profiles approver ON approver.id = p.approved_by
LEFT JOIN public.adeels ad ON ad.id = p.adeel_id;

CREATE VIEW public.v_disbursements WITH (security_invoker = on) AS
SELECT
  d.id                        AS "id",
  d.voucher_no                AS "voucherNo",
  d.amount::text              AS "amount",
  d.kind::text                AS "kind",
  d.category::text            AS "category",
  -- NULL for a collective voucher, flattened to '' so the client never branches
  -- on null: it branches on `kind`, which is the thing that decides.
  d.payee_adeel_id            AS "payeeAdeelId",
  coalesce(d.payee_name, '')  AS "payeeName",
  coalesce(a.adeel_code, '')  AS "payeeCode",
  d.method::text              AS "method",
  coalesce(d.reference, '')          AS "reference",
  coalesce(d.bank_name, '')          AS "bankName",
  coalesce(d.bank_account_no, '')    AS "bankAccountNo",
  coalesce(d.bank_account_name, '')  AS "bankAccountName",
  coalesce(d.handed_by, '')   AS "handedBy",
  coalesce(d.note, '')        AS "note",
  d.status::text              AS "status",
  to_char(d.spent_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "spentAt"
FROM public.disbursements d
LEFT JOIN public.adeels a ON a.id = d.payee_adeel_id;

GRANT SELECT ON
  public.v_adeels, public.v_receivables, public.v_payments,
  public.v_cash_movements, public.v_users, public.v_disbursements
TO authenticated;

-- == The standing guarantees, re-proven ====================================
-- assert_views_security_invoker() is the one that earns its place here: a view
-- recreated without `WITH (security_invoker = on)` runs as its OWNER and reads
-- straight past RLS, which would hand every عديل the whole association's
-- register the moment this patch committed.
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed.
SELECT 'a member code reads A-01, not A-0001' AS check,
       (SELECT coalesce(min(adeel_code), 'A-01') ~ '^A-[0-9]{2,}$'
          FROM public.adeels)::text AS ok
UNION ALL SELECT '...and it is still generated, not writable',
       (SELECT a.attgenerated = 's' FROM pg_attribute a
         WHERE a.attrelid = 'public.adeels'::regclass
           AND a.attname = 'adeel_code')::text
UNION ALL SELECT '...and still UNIQUE, so no two men share one',
       (SELECT count(*) = 1 FROM pg_constraint
         WHERE conname = 'uq_adeels_code'
           AND conrelid = 'public.adeels'::regclass)::text
UNION ALL SELECT 'a receipt reads PAY-01',
       (SELECT coalesce(min(receipt_no), 'PAY-01') ~ '^PAY-[0-9]{2,}$'
          FROM public.payments)::text
UNION ALL SELECT '...and receipts are still UNIQUE',
       (SELECT count(*) = 1 FROM pg_constraint
         WHERE conname = 'uq_pay_receipt'
           AND conrelid = 'public.payments'::regclass)::text
UNION ALL SELECT 'a voucher reads EXP-01',
       (SELECT coalesce(min(voucher_no), 'EXP-01') ~ '^EXP-[0-9]{2,}$'
          FROM public.disbursements)::text
-- ⚠ The bug the obvious expression would have shipped: with lpad(…, 2, '0') the
-- hundredth row renders the tenth row's code. This proves the arithmetic on the
-- real column rather than trusting the CASE by reading it.
UNION ALL SELECT 'the 100th code is A-100, NOT A-10 (lpad would truncate)',
       (('A-' || CASE WHEN 100 < 10 THEN '0' ELSE '' END || 100::text) = 'A-100'
        AND ('A-' || CASE WHEN 9 < 10 THEN '0' ELSE '' END || 9::text) = 'A-09'
       )::text
UNION ALL SELECT 'the six views are back',
       (SELECT count(*) = 6 FROM pg_views
         WHERE schemaname = 'public'
           AND viewname IN ('v_adeels','v_receivables','v_payments',
                            'v_cash_movements','v_users','v_disbursements'))::text
UNION ALL SELECT '...and every one of them still obeys RLS',
       (SELECT count(*) = 0 FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = 'public' AND c.relkind = 'v'
           AND NOT coalesce((SELECT lower(option_value) IN ('on','true')
                               FROM pg_options_to_table(c.reloptions)
                              WHERE option_name = 'security_invoker'), false))::text
-- Informational: what the register and the receipt book now read.
UNION ALL SELECT 'first and last member code',
       (SELECT coalesce(min(adeel_code) || ' … ' || max(adeel_code), '—')
          FROM public.adeels)
UNION ALL SELECT 'first and last receipt',
       (SELECT coalesce(min(receipt_no) || ' … ' || max(receipt_no), '—')
          FROM public.payments)
UNION ALL SELECT 'Google sign-in trigger is STILL in place',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)::text
UNION ALL SELECT 'staff profiles untouched',
       (EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin'))::text;
