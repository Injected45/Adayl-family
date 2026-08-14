-- 20260811091000_api_surface.sql — the shape the Flutter app actually consumes.
--
-- This file replaces the snake_case views from 20260811090700 with ones whose
-- column names are the EXACT keys the Dart models parse. PostgREST returns a
-- view's column names verbatim, so quoting camelCase identifiers here means the
-- existing `fromJson` factories work untouched — no mapping layer, no model
-- rewrites, and the wire contract stays defined in SQL exactly as it was when the
-- Node API owned it.
--
-- Two mechanisms, chosen per shape:
--
--   VIEWS for flat lists. PostgREST filters, orders and paginates them, so the
--   Dart side needs no query-building RPCs.
--
--   FUNCTIONS returning jsonb for nested shapes — family detail wraps
--   family/father/sons/kpis, the dashboard wraps stats/topDebtors/upcomingSons.
--   A flat view cannot express that.
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

DROP VIEW IF EXISTS public.v_top_debtors;
DROP VIEW IF EXISTS public.v_dashboard_stats;
DROP VIEW IF EXISTS public.v_cash_summary;
DROP VIEW IF EXISTS public.v_cash_movements;
DROP VIEW IF EXISTS public.v_payment_allocations;
DROP VIEW IF EXISTS public.v_payments;
DROP VIEW IF EXISTS public.v_receivable_lines;
DROP VIEW IF EXISTS public.v_receivables;
DROP VIEW IF EXISTS public.v_members;
DROP VIEW IF EXISTS public.v_families;
DROP VIEW IF EXISTS public.v_officials;
DROP VIEW IF EXISTS public.v_settings;

-- ── Eligibility, derived once ────────────────────────────────────────────────
-- Rule 1 and rule 2 in one place. Every view and function that needs a member's
-- status reads it from here rather than repeating the arithmetic, which is how
-- the prototype's memberStatus() ended up disagreeing with itself.
CREATE VIEW public.v_member_status WITH (security_invoker = on) AS
SELECT
  m.id,
  m.family_id,
  m.kind,
  m.full_name,
  m.national_id,
  m.phone,
  m.subscription_no,
  m.dob,
  m.nationality,
  m.workplace,
  m.registered_at,
  m.status,
  CASE
    WHEN m.dob IS NULL THEN NULL
    ELSE extract(year FROM age(current_date, m.dob))::int
  END AS age_years,
  CASE
    WHEN m.status <> 'نشط' THEN 'inactive'
    WHEN m.dob IS NULL THEN 'under'
    WHEN extract(year FROM age(current_date, m.dob)) >= s.eligibility_age
      THEN 'eligible'
    -- "قريب من السن": the eligibility birthday is in the future but within
    -- warning_months of today.
    WHEN (m.dob + make_interval(years => s.eligibility_age::int)) > current_date
     AND (m.dob + make_interval(years => s.eligibility_age::int))
         <= (current_date + make_interval(months => s.warning_months::int))
      THEN 'soon'
    ELSE 'under'
  END AS eligibility,
  CASE WHEN m.kind = 'father' THEN s.father_fee ELSE s.son_fee END AS fee
FROM public.members m
CROSS JOIN public.association_settings s;

-- ── Settings (AssociationSettingsView) ───────────────────────────────────────
CREATE VIEW public.v_settings WITH (security_invoker = on) AS
SELECT
  association_name        AS "associationName",
  currency                AS "currency",
  father_fee::text        AS "fatherFee",
  son_fee::text           AS "sonFee",
  eligibility_age::int    AS "eligibilityAge",
  warning_months::int     AS "warningMonths",
  to_char(system_start, 'YYYY-MM-DD') AS "systemStart",
  auto_close_previous_months          AS "autoClosePreviousMonths"
FROM public.association_settings;

-- ── Officials ────────────────────────────────────────────────────────────────
CREATE VIEW public.v_officials WITH (security_invoker = on) AS
SELECT 'treasurer'::text AS "role",
       treasurer_name        AS "name",
       treasurer_national_id AS "nationalId",
       treasurer_phone       AS "phone"
  FROM public.association_settings
UNION ALL
SELECT 'financeManager'::text,
       finance_manager_name,
       finance_manager_national_id,
       finance_manager_phone
  FROM public.association_settings;

-- ── Families list (FamilyListItem) ───────────────────────────────────────────
CREATE VIEW public.v_families WITH (security_invoker = on) AS
SELECT
  f.id                                   AS "id",
  f.family_code                          AS "familyCode",
  coalesce(father.full_name, '')          AS "fatherName",
  -- Kept out of the model but needed for search: PostgREST filters on columns,
  -- so anything the app searches by has to be selectable.
  coalesce(father.national_id, '')        AS "fatherNationalId",
  (SELECT count(*) FROM public.members m
    WHERE m.family_id = f.id AND m.kind = 'son')::int AS "sonsCount",
  (SELECT count(*) FROM public.v_member_status v
    WHERE v.family_id = f.id AND v.kind = 'son'
      AND v.eligibility = 'eligible')::int            AS "eligibleCount",
  (SELECT count(*) FROM public.v_member_status v
    WHERE v.family_id = f.id AND v.kind = 'son'
      AND v.eligibility = 'soon')::int                AS "soonCount",
  coalesce(agg.debt, 0)::numeric(12,2)::text            AS "debt",
  coalesce(agg.paid, 0)::numeric(12,2)::text            AS "paid",
  coalesce(agg.issued, 0)::numeric(12,2)::text          AS "issued",
  -- What the family WOULD be charged today, from current settings — distinct
  -- from any receivable's snapshot. index.html shows both side by side.
  (
    coalesce((SELECT v.fee FROM public.v_member_status v
               WHERE v.family_id = f.id AND v.kind = 'father'
                 AND v.status = 'نشط'), 0)
    + coalesce((SELECT sum(v.fee) FROM public.v_member_status v
                 WHERE v.family_id = f.id AND v.kind = 'son'
                   AND v.eligibility = 'eligible'), 0)
  )::text                                AS "monthlyExpected"
FROM public.families f
LEFT JOIN public.members father
       ON father.family_id = f.id AND father.kind = 'father'
LEFT JOIN LATERAL (
  SELECT sum(r.balance) AS debt, sum(r.paid) AS paid, sum(r.total) AS issued
    FROM public.receivables r
   WHERE r.family_id = f.id AND r.status <> 'ملغي'
) agg ON true;

-- ── Members list (MemberListItem) ────────────────────────────────────────────
CREATE VIEW public.v_members WITH (security_invoker = on) AS
SELECT
  v.id                          AS "id",
  v.family_id                   AS "familyId",
  v.full_name                   AS "fullName",
  CASE WHEN v.kind = 'father' THEN 'الأب' ELSE 'ابن' END AS "relation",
  coalesce(father.full_name, '') AS "familyName",
  v.national_id                 AS "nationalId",
  coalesce(v.phone, '')         AS "phone",
  coalesce(v.workplace, '')     AS "workplace",
  v.age_years                   AS "age",
  v.eligibility                 AS "eligibility",
  v.status::text                AS "membershipStatus"
FROM public.v_member_status v
LEFT JOIN public.members father
       ON father.family_id = v.family_id AND father.kind = 'father';

-- ── Receivables (ReceivableItem) ─────────────────────────────────────────────
CREATE VIEW public.v_receivables WITH (security_invoker = on) AS
SELECT
  r.id                    AS "id",
  r.family_id             AS "familyId",
  r.father_name           AS "familyName",
  f.family_code           AS "familyCode",
  r.period                AS "period",
  public.period_label(r.period) AS "periodLabel",
  r.father_fee::text      AS "fatherFee",
  r.son_fee::text         AS "sonFee",
  -- A JSON ARRAY, not a joined string: ReceivableItem reads billedSonNames as a
  -- List. Joining here would also decide the separator on the client's behalf,
  -- which is a presentation choice the screen should keep.
  coalesce(
    (SELECT jsonb_agg(l.member_name ORDER BY l.id)
       FROM public.receivable_lines l
      WHERE l.receivable_id = r.id AND l.member_kind = 'son'),
    '[]'::jsonb
  )                       AS "billedSonNames",
  r.total::text           AS "total",
  r.paid::text            AS "paid",
  r.balance::text         AS "balance",
  r.status::text          AS "status"
FROM public.receivables r
JOIN public.families f ON f.id = r.family_id;

-- ── Payments (PaymentView, allocations nested) ───────────────────────────────
CREATE VIEW public.v_payments WITH (security_invoker = on) AS
SELECT
  p.id                       AS "id",
  p.receipt_no               AS "receiptNo",
  p.family_id                AS "familyId",
  coalesce(father.full_name, f.family_code) AS "familyName",
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
                'receivableId', a.receivable_id,
                'period', a.period,
                'amount', a.amount::text)
              ORDER BY a.sequence_no)
       FROM public.payment_allocations a
      WHERE a.payment_id = p.id),
    '[]'::jsonb
  )                          AS "allocations"
FROM public.payments p
JOIN public.families f ON f.id = p.family_id
LEFT JOIN public.members father
       ON father.family_id = p.family_id AND father.kind = 'father';

-- ── Treasury (CashMovementView, CashSummaryView) ─────────────────────────────
CREATE VIEW public.v_cash_movements WITH (security_invoker = on) AS
SELECT
  c.id                       AS "id",
  p.receipt_no               AS "receiptNo",
  coalesce(father.full_name, f.family_code) AS "familyName",
  c.family_id                AS "familyId",
  c.amount::text             AS "amount",
  c.method::text             AS "method",
  c.movement_type::text      AS "movementType",
  c.status::text             AS "status",
  to_char(c.occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS "occurredAt"
FROM public.cash_movements c
JOIN public.payments p ON p.id = c.payment_id
JOIN public.families f ON f.id = c.family_id
LEFT JOIN public.members father
       ON father.family_id = c.family_id AND father.kind = 'father';

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
  -- NULL for staff. Non-NULL marks a head of family, who stores `viewer` in
  -- `role` and would otherwise be indistinguishable on the users screen from a
  -- real viewer — while actually seeing far less, and something different.
  fam.family_code       AS "familyCode"
FROM public.profiles p
LEFT JOIN public.profiles approver ON approver.id = p.approved_by
LEFT JOIN public.families fam ON fam.id = p.family_id;

GRANT SELECT ON
  public.v_member_status, public.v_settings, public.v_officials,
  public.v_families, public.v_members, public.v_receivables,
  public.v_payments, public.v_cash_movements, public.v_cash_summary,
  public.v_audit, public.v_users
TO authenticated;
