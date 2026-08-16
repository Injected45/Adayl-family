-- 20260811091000_api_surface.sql — the shape the Flutter app actually consumes.
--
-- Column names here are the EXACT keys the Dart models parse. PostgREST returns a
-- view's column names verbatim, so quoting camelCase identifiers means the
-- `fromJson` factories need no mapping layer, and the wire contract stays defined
-- in SQL exactly as it was when the Node API owned it.
--
-- This used to be the SECOND set of views: 20260811090700 defined a snake_case
-- set, and this file dropped all twelve and redefined them. That file is gone.
-- Every view was being written twice, only one of the two was ever reachable, and
-- an edit to the wrong copy was silently a no-op.
--
-- Two mechanisms, chosen per shape:
--
--   VIEWS for flat lists. PostgREST filters, orders and paginates them, so the
--   Dart side needs no query-building RPCs.
--
--   FUNCTIONS returning jsonb for nested shapes — an عديل's detail wraps his row
--   with his dues and receipts; the dashboard wraps stats and top debtors. A flat
--   view cannot express that. They live in 20260811091100.
--
-- The read functions are STABLE and SECURITY INVOKER, deliberately. They run with
-- the caller's rights, so every RLS policy from 20260811090500 still applies. Only
-- the WRITE functions in 20260811090600 are SECURITY DEFINER, because only they
-- need to touch tables the client holds no privilege on.
--
-- MONEY IS TEXT EVERYWHERE. numeric serialises to a bare JSON number and
-- dart:convert turns that into a double. Every amount below is cast.
--
-- And every aggregate is cast to numeric(12,2) BEFORE text. `coalesce(sum(x), 0)`
-- falls back to an INTEGER literal, so an empty bucket serialises as "0" while
-- every other amount on the same screen is "0.00" — which the contract test
-- caught on the treasury's transfer total. Two decimals, always.

-- ── Arabic month label ───────────────────────────────────────────────────────
-- `periodLabel` was produced by the Node API, so the client has no month names of
-- its own and nothing in lib/l10n to build them from. Keeping the label
-- server-side preserves that and keeps one spelling of each month across the
-- receivables list, the dashboard button and the audit trail. IMMUTABLE so it can
-- be used in a view without blocking planning.
CREATE OR REPLACE FUNCTION public.period_label(p_period text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE substring(p_period FROM 6 FOR 2)
           WHEN '01' THEN 'يناير'   WHEN '02' THEN 'فبراير'
           WHEN '03' THEN 'مارس'    WHEN '04' THEN 'أبريل'
           WHEN '05' THEN 'مايو'    WHEN '06' THEN 'يونيو'
           WHEN '07' THEN 'يوليو'   WHEN '08' THEN 'أغسطس'
           WHEN '09' THEN 'سبتمبر'  WHEN '10' THEN 'أكتوبر'
           WHEN '11' THEN 'نوفمبر'  WHEN '12' THEN 'ديسمبر'
           ELSE p_period
         END || ' ' || substring(p_period FROM 1 FOR 4)
$$;

-- ── Settings (AssociationSettingsView) ───────────────────────────────────────
CREATE VIEW public.v_settings WITH (security_invoker = on) AS
SELECT
  association_name        AS "associationName",
  currency                AS "currency",
  member_fee::text        AS "memberFee",
  to_char(system_start, 'YYYY-MM-DD') AS "systemStart",
  auto_close_previous_months          AS "autoClosePreviousMonths",
  -- Where a transfer should be sent. Deliberately on the WIDELY readable view
  -- rather than the admin-only settings shape: an عديل on the portal reads this
  -- view too, and he is the one being asked to transfer.
  bank_account_no                     AS "bankAccountNo",
  bank_account_name                   AS "bankAccountName",
  bank_name                           AS "bankName"
FROM public.association_settings;

-- ── Officials ────────────────────────────────────────────────────────────────
CREATE VIEW public.v_officials WITH (security_invoker = on) AS
SELECT 'treasurer'::text AS "role",
       treasurer_name        AS "name",
       treasurer_phone       AS "phone"
  FROM public.association_settings
UNION ALL
SELECT 'financeManager'::text,
       finance_manager_name,
       finance_manager_phone
  FROM public.association_settings;

-- ── The register (AdeelListItem) ─────────────────────────────────────────────
-- ONE list view where there used to be two — v_families (a household with its
-- father's name and a count of sons) and v_members (every person, with a
-- relation label and the family they hung off). The عديل IS the unit now, so the
-- two collapsed and the LEFT JOIN to find "the father of this family" that both
-- carried disappeared with them.
--
-- `monthlyExpected` is what he WOULD be charged today, from current settings —
-- distinct from any receivable's snapshot, which is frozen at creation. It is the
-- fee when he is نشط and zero otherwise, because status is now the only thing
-- that decides whether a charge is raised.
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
                                          AS "monthlyExpected"
FROM public.adeels a
CROSS JOIN public.association_settings s
LEFT JOIN LATERAL (
  SELECT sum(r.balance) AS debt, sum(r.paid) AS paid, sum(r.total) AS issued
    FROM public.receivables r
   WHERE r.adeel_id = a.id AND r.status <> 'ملغي'
) agg ON true;

-- ── Receivables (ReceivableItem) ─────────────────────────────────────────────
-- `billedSonNames` is gone with the household. A receivable bills one man, and
-- his name is a snapshot column on the row itself rather than a jsonb array
-- assembled from a line table that no longer exists.
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

-- ── Payments (PaymentView, allocations nested) ───────────────────────────────
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

-- ── Treasury (CashMovementView, CashSummaryView) ─────────────────────────────
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

-- Cancelled movements are excluded from every total but stay visible in the list
-- above, struck through — rule 9 requires them shown, never hidden.
CREATE VIEW public.v_cash_summary WITH (security_invoker = on) AS
SELECT
  coalesce(sum(amount), 0)::numeric(12,2)::text AS "total",
  coalesce(sum(amount) FILTER (WHERE method = 'نقداً'), 0)::numeric(12,2)::text        AS "cash",
  coalesce(sum(amount) FILTER (WHERE method = 'تحويل مصرفي'), 0)::numeric(12,2)::text AS "transfer",
  coalesce(sum(amount) FILTER (WHERE occurred_at::date = current_date), 0)::numeric(12,2)::text
    AS "today",
  coalesce(sum(amount) FILTER (WHERE date_trunc('month', occurred_at)
                                  = date_trunc('month', current_date)), 0)::numeric(12,2)::text
    AS "month",
  coalesce(sum(amount) FILTER (WHERE date_trunc('year', occurred_at)
                                  = date_trunc('year', current_date)), 0)::numeric(12,2)::text
    AS "year"
FROM public.cash_movements
WHERE status <> 'ملغي';

-- ── Audit (AuditEntry) ───────────────────────────────────────────────────────
CREATE VIEW public.v_audit WITH (security_invoker = on) AS
SELECT
  a.id                  AS "id",
  a.event_type          AS "eventType",
  a.detail              AS "detail",
  a.ref                 AS "ref",
  a.actor_name          AS "actorName",
  to_char(a.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
                        AS "occurredAt"
FROM public.audit_log a;

-- ── Users (UserAccount) ──────────────────────────────────────────────────────
-- `id` is a uuid string, not a bigint. This is the one place the migration forces
-- a Dart model change: identity now belongs to auth.users, and AppUser.id /
-- UserAccount.id become String.
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

GRANT SELECT ON
  public.v_settings, public.v_officials, public.v_adeels,
  public.v_receivables, public.v_payments,
  public.v_cash_movements, public.v_cash_summary,
  public.v_audit, public.v_users
TO authenticated;
