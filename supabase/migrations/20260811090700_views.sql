-- 20260811090700_views.sql — the read side of the 22 non-transactional endpoints.
--
-- Every one of these exists for a single reason: MONEY MUST NOT REACH DART AS A
-- NUMBER. PostgREST serialises numeric as an unquoted JSON literal
-- (`"amount":12345678.91`), dart:convert decodes that to double, and this
-- project's entire money discipline rests on never letting a float near a
-- balance. mysql2 handed back DECIMAL as a string and the Dart models are built
-- for strings. `::text` reproduces that exactly.
--
-- Proven, not assumed: supabase/tests/probe.sh compares json_agg output for a
-- raw numeric column against the cast one. PostgREST builds its response body
-- with json_agg inside Postgres, so that comparison is the wire format.
--
-- security_invoker = on is load-bearing. Without it a view runs with its
-- owner's rights and silently bypasses the RLS policies on the tables beneath —
-- an anon caller would read the whole ledger through the view.

-- ── Families list with debt totals (endpoint 10) ─────────────────────────────
CREATE VIEW public.v_families WITH (security_invoker = on) AS
SELECT
  f.id,
  f.family_code,
  f.created_at,
  father.id                        AS father_member_id,
  father.full_name                 AS father_name,
  father.national_id               AS father_national_id,
  father.phone                     AS father_phone,
  father.status                    AS father_status,
  (SELECT count(*) FROM public.members m
    WHERE m.family_id = f.id AND m.kind = 'son')          AS sons_count,
  coalesce(agg.debt, 0)::text      AS debt,
  coalesce(agg.paid, 0)::text      AS paid,
  coalesce(agg.issued, 0)::text    AS issued
FROM public.families f
LEFT JOIN public.members father
       ON father.family_id = f.id AND father.kind = 'father'
LEFT JOIN LATERAL (
  SELECT sum(r.balance) AS debt, sum(r.paid) AS paid, sum(r.total) AS issued
    FROM public.receivables r
   WHERE r.family_id = f.id AND r.status <> 'ملغي'
) agg ON true;

-- ── Members, unified father+son search (endpoint 15) ─────────────────────────
-- Eligibility is derived here rather than stored, matching the prototype's
-- memberStatus(), and computed against TODAY — a receivable's own eligibility
-- lives in its snapshot columns and is a different question.
CREATE VIEW public.v_members WITH (security_invoker = on) AS
SELECT
  m.id, m.family_id, f.family_code, m.kind, m.full_name, m.national_id,
  m.phone, m.subscription_no, m.dob, m.nationality, m.workplace,
  m.registered_at, m.status,
  CASE WHEN m.dob IS NULL THEN NULL
       ELSE extract(year FROM age(current_date, m.dob))::int END AS age,
  CASE
    WHEN m.status <> 'نشط' THEN 'inactive'
    WHEN m.dob IS NULL     THEN 'under'
    WHEN extract(year FROM age(current_date, m.dob)) >= s.eligibility_age
      THEN 'eligible'
    WHEN age(m.dob + make_interval(years => s.eligibility_age::int), current_date)
         <= make_interval(months => s.warning_months::int)
      AND m.dob + make_interval(years => s.eligibility_age::int) >= current_date
      THEN 'soon'
    ELSE 'under'
  END AS eligibility,
  CASE WHEN m.kind = 'father' THEN s.father_fee ELSE s.son_fee END::text
       AS current_fee
FROM public.members m
JOIN public.families f ON f.id = m.family_id
CROSS JOIN public.association_settings s;

-- ── Receivables (endpoints 16, 17) ───────────────────────────────────────────
CREATE VIEW public.v_receivables WITH (security_invoker = on) AS
SELECT
  r.id, r.family_id, f.family_code, r.father_name, r.period, r.period_end,
  r.total::text   AS total,
  r.paid::text    AS paid,
  r.balance::text AS balance,
  r.status, r.created_at, r.cancelled_at, r.cancel_reason,
  r.father_fee::text AS father_fee,
  r.son_fee::text    AS son_fee,
  r.eligibility_age_snapshot, r.warning_months_snapshot
FROM public.receivables r
JOIN public.families f ON f.id = r.family_id;

CREATE VIEW public.v_receivable_lines WITH (security_invoker = on) AS
SELECT l.id, l.receivable_id, l.member_id, l.member_kind, l.member_name,
       l.member_national_id, l.fee_amount::text AS fee_amount
FROM public.receivable_lines l;

-- ── Payments and allocations (endpoints 20, 21) ──────────────────────────────
CREATE VIEW public.v_payments WITH (security_invoker = on) AS
SELECT
  p.id, p.receipt_no, p.family_id, f.family_code,
  father.full_name AS family_name,
  p.amount::text   AS amount,
  p.method, p.reference, p.receiver, p.notes, p.status, p.paid_at,
  p.cancelled_at, p.cancel_reason
FROM public.payments p
JOIN public.families f ON f.id = p.family_id
LEFT JOIN public.members father
       ON father.family_id = p.family_id AND father.kind = 'father';

CREATE VIEW public.v_payment_allocations WITH (security_invoker = on) AS
SELECT a.id, a.payment_id, a.receivable_id, a.period,
       a.amount::text AS amount, a.sequence_no
FROM public.payment_allocations a;

-- ── Treasury (endpoints 24, 25) ──────────────────────────────────────────────
CREATE VIEW public.v_cash_movements WITH (security_invoker = on) AS
SELECT
  c.id, c.payment_id, p.receipt_no, c.family_id, f.family_code,
  father.full_name AS family_name,
  c.amount::text   AS amount,
  c.method, c.movement_type, c.status, c.occurred_at
FROM public.cash_movements c
JOIN public.payments p ON p.id = c.payment_id
JOIN public.families f ON f.id = c.family_id
LEFT JOIN public.members father
       ON father.family_id = c.family_id AND father.kind = 'father';

-- Cancelled movements are excluded from every total but stay visible in the
-- list above, struck through — rule 9 requires them shown, not hidden.
CREATE VIEW public.v_cash_summary WITH (security_invoker = on) AS
SELECT
  coalesce(sum(amount), 0)::text AS total,
  coalesce(sum(amount) FILTER (WHERE method = 'نقداً'), 0)::text        AS cash,
  coalesce(sum(amount) FILTER (WHERE method = 'تحويل مصرفي'), 0)::text AS transfer,
  coalesce(sum(amount) FILTER (WHERE occurred_at::date = current_date), 0)::text AS today,
  coalesce(sum(amount) FILTER (WHERE date_trunc('month', occurred_at)
                                    = date_trunc('month', current_date)), 0)::text AS month,
  coalesce(sum(amount) FILTER (WHERE date_trunc('year', occurred_at)
                                    = date_trunc('year', current_date)), 0)::text AS year
FROM public.cash_movements
WHERE status <> 'ملغي';

-- ── Dashboard stat cards (endpoint 26) ───────────────────────────────────────
CREATE VIEW public.v_dashboard_stats WITH (security_invoker = on) AS
SELECT
  (SELECT count(*) FROM public.families)                              AS families,
  (SELECT count(*) FROM public.members WHERE kind = 'son')            AS sons,
  (SELECT count(*) FROM public.v_members
    WHERE kind = 'son' AND eligibility = 'eligible')                  AS eligible,
  (SELECT count(*) FROM public.v_members
    WHERE kind = 'son' AND eligibility = 'soon')                      AS soon,
  (SELECT coalesce(sum(balance), 0)::text FROM public.receivables
    WHERE status <> 'ملغي')                                           AS debt,
  (SELECT count(DISTINCT family_id) FROM public.receivables
    WHERE status <> 'ملغي' AND balance > 0)                           AS indebted_families,
  (SELECT coalesce(sum(amount), 0)::text FROM public.cash_movements
    WHERE status <> 'ملغي')                                           AS collected,
  (SELECT coalesce(sum(amount), 0)::text FROM public.cash_movements
    WHERE status <> 'ملغي' AND method = 'نقداً')                      AS cash,
  (SELECT coalesce(sum(amount), 0)::text FROM public.cash_movements
    WHERE status <> 'ملغي' AND method = 'تحويل مصرفي')                AS transfer;

CREATE VIEW public.v_top_debtors WITH (security_invoker = on) AS
SELECT id AS family_id, family_code, father_name, debt
FROM public.v_families
WHERE debt::numeric > 0
ORDER BY debt::numeric DESC
LIMIT 10;

-- ── Officials (endpoint 9) ───────────────────────────────────────────────────
CREATE VIEW public.v_officials WITH (security_invoker = on) AS
SELECT 'treasurer' AS role, treasurer_name AS name,
       treasurer_national_id AS national_id, treasurer_phone AS phone
  FROM public.association_settings
UNION ALL
SELECT 'financeManager', finance_manager_name,
       finance_manager_national_id, finance_manager_phone
  FROM public.association_settings;

-- ── Settings, money as text (endpoint 7) ─────────────────────────────────────
CREATE VIEW public.v_settings WITH (security_invoker = on) AS
SELECT association_name, currency,
       father_fee::text AS father_fee,
       son_fee::text    AS son_fee,
       eligibility_age, warning_months, system_start, auto_close_previous_months,
       treasurer_name, treasurer_national_id, treasurer_phone,
       finance_manager_name, finance_manager_national_id, finance_manager_phone,
       updated_at
FROM public.association_settings;

-- security_invoker makes each view obey the caller's policies, so a plain SELECT
-- grant is all they need — the underlying table policies still decide.
GRANT SELECT ON
  public.v_families, public.v_members, public.v_receivables,
  public.v_receivable_lines, public.v_payments, public.v_payment_allocations,
  public.v_cash_movements, public.v_cash_summary, public.v_dashboard_stats,
  public.v_top_debtors, public.v_officials, public.v_settings
TO authenticated;
