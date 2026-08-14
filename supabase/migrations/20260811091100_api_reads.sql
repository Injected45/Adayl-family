-- 20260811091100_api_reads.sql — the nested read shapes.
--
-- Four of the app's screens consume JSON that no flat view can produce: family
-- detail wraps family/father/sons/kpis, the dashboard wraps
-- stats/topDebtors/upcomingSons, the report wraps totals plus a payment list, and
-- the statement is an ordered debit/credit merge with a running balance.
--
-- All STABLE and SECURITY INVOKER. They run as the caller, so the RLS policies
-- from 20260811090500 still decide what is visible — a viewer calling
-- api_dashboard() sees the association's figures, an unapproved user sees zeroes
-- and empty lists, and neither is a special case anyone had to write.
--
-- Money is text in every one of them.

-- ── MemberView, reused by family detail ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.member_json(p_member_id bigint) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', v.id,
    'fullName', v.full_name,
    'nationalId', v.national_id,
    'phone', coalesce(v.phone, ''),
    'subscriptionNo', coalesce(v.subscription_no, ''),
    'dob', coalesce(to_char(v.dob, 'YYYY-MM-DD'), ''),
    'age', v.age_years,
    'nationality', v.nationality,
    'workplace', coalesce(v.workplace, ''),
    'registeredAt', to_char(v.registered_at, 'YYYY-MM-DD'),
    'membershipStatus', v.status::text,
    -- An OBJECT, not a string: MemberView reads eligibility.key AND
    -- eligibility.label, and the Arabic label is server-side on purpose so the
    -- badge can never disagree with what the prototype showed for the same
    -- member. lib/l10n has no eligibility wording to rebuild it from.
    'eligibility', jsonb_build_object(
      'key', v.eligibility,
      'label', CASE v.eligibility
                 WHEN 'eligible' THEN 'مستحق'
                 WHEN 'soon'     THEN 'قريب من السن'
                 WHEN 'under'    THEN 'غير مستحق'
                 ELSE 'موقوف'
               END),
    'currentFee', v.fee::text)
  FROM public.v_member_status v WHERE v.id = p_member_id
$$;

-- ── Endpoint 12 — GET /families/:id (FamilyDetail) ───────────────────────────
CREATE OR REPLACE FUNCTION public.api_family_detail(p_family_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'family', jsonb_build_object(
      'id', f."id",
      'familyCode', f."familyCode"),
    'father', (SELECT public.member_json(m.id) FROM public.members m
                WHERE m.family_id = p_family_id AND m.kind = 'father'),
    'sons', coalesce(
      (SELECT jsonb_agg(public.member_json(m.id) ORDER BY m.dob NULLS LAST, m.id)
         FROM public.members m
        WHERE m.family_id = p_family_id AND m.kind = 'son'),
      '[]'::jsonb),
    'kpis', jsonb_build_object(
      'sonsCount', f."sonsCount",
      'eligibleCount', f."eligibleCount",
      'soonCount', f."soonCount",
      'monthlyExpected', f."monthlyExpected",
      'debt', f."debt",
      'paid', f."paid"))
  FROM public.v_families f WHERE f."id" = p_family_id
$$;

-- ── Endpoint 14 — GET /families/:id/statement (Statement) ────────────────────
-- Rule 11: a chronological merge of charges (debit) and payments (credit) with a
-- running balance. The running total is a window function over the merged set,
-- which is the whole reason this cannot be two separate list queries stitched
-- together in Dart — the order has to be established before the balance is.
CREATE OR REPLACE FUNCTION public.api_family_statement(p_family_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH movements AS (
    SELECT r.created_at AS at,
           r.period      AS reference,
           'استحقاق'::text AS kind,
           r.total       AS debit,
           NULL::numeric AS credit,
           public.period_label(r.period) AS note
      FROM public.receivables r
     WHERE r.family_id = p_family_id AND r.status <> 'ملغي'
    UNION ALL
    SELECT p.paid_at,
           p.receipt_no,
           'دفعة'::text,
           NULL::numeric,
           p.amount,
           coalesce(nullif(p.reference, ''), p.method::text)
      FROM public.payments p
     WHERE p.family_id = p_family_id AND p.status <> 'ملغي'
  ), ordered AS (
    SELECT *,
           sum(coalesce(debit, 0) - coalesce(credit, 0))
             OVER (ORDER BY at, reference
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS balance
      FROM movements
  )
  SELECT jsonb_build_object(
    'movements', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'date', to_char(o.at AT TIME ZONE 'UTC', 'YYYY-MM-DD'),
                  'reference', o.reference,
                  'type', o.kind,
                  'debit', o.debit::text,
                  'credit', o.credit::text,
                  'balance', o.balance::text,
                  'note', o.note)
                ORDER BY o.at, o.reference)
         FROM ordered o),
      '[]'::jsonb),
    'closingBalance',
      coalesce((SELECT o.balance::text FROM ordered o
                 ORDER BY o.at DESC, o.reference DESC LIMIT 1), '0.00'))
$$;

-- ── Endpoint 26 — GET /dashboard (DashboardData) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.api_dashboard() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  WITH period AS (
    -- The PREVIOUS month, not this one. index.html labels the close button with
    -- previousPeriod() (line 452); the current month is not closed until it ends.
    SELECT to_char(date_trunc('month', current_date) - interval '1 month',
                   'YYYY-MM') AS p
  )
  SELECT jsonb_build_object(
    'stats', jsonb_build_object(
      'families', (SELECT count(*) FROM public.families),
      'sons', (SELECT count(*) FROM public.members WHERE kind = 'son'),
      'eligible', (SELECT count(*) FROM public.v_member_status
                    WHERE kind = 'son' AND eligibility = 'eligible'),
      'soon', (SELECT count(*) FROM public.v_member_status
                WHERE kind = 'son' AND eligibility = 'soon'),
      'under', (SELECT count(*) FROM public.v_member_status
                 WHERE kind = 'son' AND eligibility = 'under'),
      'debt', (SELECT coalesce(sum(balance), 0)::numeric(12,2)::text FROM public.receivables
                WHERE status <> 'ملغي'),
      'collected', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                      FROM public.cash_movements WHERE status <> 'ملغي'),
      'cash', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text FROM public.cash_movements
                WHERE status <> 'ملغي' AND method = 'نقداً'),
      'transfer', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                     FROM public.cash_movements
                    WHERE status <> 'ملغي' AND method = 'تحويل مصرفي'),
      'indebtedFamilies', (SELECT count(DISTINCT family_id)
                             FROM public.receivables
                            WHERE status <> 'ملغي' AND balance > 0)),
    'topDebtors', coalesce(
      (SELECT jsonb_agg(d ORDER BY (d ->> 'debt')::numeric DESC)
         FROM (SELECT jsonb_build_object(
                        'familyId', f."id",
                        'familyCode', f."familyCode",
                        'fatherName', f."fatherName",
                        'debt', f."debt") AS d
                 FROM public.v_families f
                WHERE f."debt"::numeric > 0
                ORDER BY f."debt"::numeric DESC
                LIMIT 10) top),
      '[]'::jsonb),
    -- Rule 2: sons approaching the eligibility age, so the treasurer can see the
    -- charge coming before it appears.
    'upcomingSons', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'sonId', v.id,
                  'sonName', v.full_name,
                  'familyId', v.family_id,
                  'fatherName', coalesce(father.full_name, ''))
                ORDER BY v.dob DESC)
         FROM public.v_member_status v
         LEFT JOIN public.members father
                ON father.family_id = v.family_id AND father.kind = 'father'
        WHERE v.kind = 'son' AND v.eligibility = 'soon'),
      '[]'::jsonb),
    'closingPeriod', (SELECT p FROM period),
    'closingPeriodLabel', (SELECT public.period_label(p) FROM period))
$$;

-- ── Endpoint 27 — GET /alerts (AlertItem) ────────────────────────────────────
-- `text` is display prose, which the Node API also produced. It stays server-side
-- so one wording is used everywhere; the client has no month names or templates
-- of its own to rebuild it from.
CREATE OR REPLACE FUNCTION public.api_alerts() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_agg(a ORDER BY (a ->> 'severity') DESC), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
             'type', 'age',
             'severity', 'warning',
             'text', v.full_name || ' يقترب من سن الاستحقاق',
             'familyId', v.family_id) AS a
      FROM public.v_member_status v
     WHERE v.kind = 'son' AND v.eligibility = 'soon'
    UNION ALL
    SELECT jsonb_build_object(
             'type', 'debt',
             'severity', 'danger',
             'text', f."fatherName" || ' — مديونية ' || f."debt",
             'familyId', f."id")
      FROM public.v_families f
     WHERE f."debt"::numeric > 0
    UNION ALL
    SELECT jsonb_build_object(
             'type', 'partial',
             'severity', 'info',
             'text', r."familyName" || ' — ' || r."periodLabel"
                     || ' مسدد جزئياً (' || r."balance" || ' متبقٍ)',
             'familyId', r."familyId")
      FROM public.v_receivables r
     WHERE r."status" = 'مسدد جزئياً'
  ) alerts
$$;

-- ── Endpoint 28 — GET /reports/financial (FinancialReport) ───────────────────
CREATE OR REPLACE FUNCTION public.api_financial_report(p_from date, p_to date)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'from', to_char(p_from, 'YYYY-MM-DD'),
    'to', to_char(p_to, 'YYYY-MM-DD'),
    'issued', (SELECT coalesce(sum(r.total), 0)::numeric(12,2)::text FROM public.receivables r
                WHERE r.status <> 'ملغي'
                  AND r.created_at::date BETWEEN p_from AND p_to),
    'issuedCount', (SELECT count(*) FROM public.receivables r
                     WHERE r.status <> 'ملغي'
                       AND r.created_at::date BETWEEN p_from AND p_to),
    'collected', (SELECT coalesce(sum(p.amount), 0)::numeric(12,2)::text FROM public.payments p
                   WHERE p.status <> 'ملغي'
                     AND p.paid_at::date BETWEEN p_from AND p_to),
    'collectedCount', (SELECT count(*) FROM public.payments p
                        WHERE p.status <> 'ملغي'
                          AND p.paid_at::date BETWEEN p_from AND p_to),
    -- Outstanding is a position, not a flow: it is the balance as it stands, not
    -- something that accrued inside the window. Filtering it by date would report
    -- a smaller debt for a shorter report, which is what the prototype did NOT do.
    'debt', (SELECT coalesce(sum(r.balance), 0)::numeric(12,2)::text FROM public.receivables r
              WHERE r.status <> 'ملغي'),
    'partialCount', (SELECT count(*) FROM public.receivables r
                      WHERE r.status = 'مسدد جزئياً'),
    'payments', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'receiptNo', p."receiptNo",
                  'familyName', p."familyName",
                  'amount', p."amount",
                  'method', p."method",
                  'reference', p."reference",
                  'paidAt', p."paidAt")
                ORDER BY p."paidAt" DESC)
         FROM public.v_payments p
        WHERE p."status" <> 'ملغي'
          AND (p."paidAt")::timestamptz::date BETWEEN p_from AND p_to),
      '[]'::jsonb))
$$;

-- ── Endpoint 16 — GET /receivables (ReceivablesPage) ────────────────────────
-- The list itself is a plain view read, but the summary has to be computed over
-- the SAME filter, so the two travel together rather than risking a client that
-- filters the list one way and the totals another.
CREATE OR REPLACE FUNCTION public.api_receivables(p_period text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH filtered AS (
    SELECT * FROM public.v_receivables r
     WHERE p_period IS NULL OR p_period = '' OR r."period" = p_period
  )
  SELECT jsonb_build_object(
    'items', coalesce(
      (SELECT jsonb_agg(to_jsonb(f) ORDER BY f."period" DESC, f."id" DESC)
         FROM filtered f),
      '[]'::jsonb),
    'summary', jsonb_build_object(
      'issued', (SELECT coalesce(sum(f."total"::numeric), 0)::numeric(12,2)::text FROM filtered f
                  WHERE f."status" <> 'ملغي'),
      'collected', (SELECT coalesce(sum(f."paid"::numeric), 0)::numeric(12,2)::text
                      FROM filtered f WHERE f."status" <> 'ملغي'),
      'outstanding', (SELECT coalesce(sum(f."balance"::numeric), 0)::numeric(12,2)::text
                        FROM filtered f WHERE f."status" <> 'ملغي')))
$$;

-- ── Endpoint 7 — GET /settings, full editable shape (EditableSettings) ───────
CREATE OR REPLACE FUNCTION public.api_settings() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'associationName', s.association_name,
    'currency', s.currency,
    'fatherFee', s.father_fee::text,
    'sonFee', s.son_fee::text,
    'eligibilityAge', s.eligibility_age::int,
    'warningMonths', s.warning_months::int,
    'systemStart', to_char(s.system_start, 'YYYY-MM-DD'),
    'autoClosePreviousMonths', s.auto_close_previous_months,
    'treasurer', jsonb_build_object(
      'name', s.treasurer_name,
      'nationalId', s.treasurer_national_id,
      'phone', s.treasurer_phone),
    'financeManager', jsonb_build_object(
      'name', s.finance_manager_name,
      'nationalId', s.finance_manager_national_id,
      'phone', s.finance_manager_phone))
  FROM public.association_settings s WHERE s.id = 1
$$;

-- ── Endpoint 4 — the caller's own profile ────────────────────────────────────
-- Readable by a pending or suspended account, because the app has to be able to
-- render "awaiting approval" for exactly those users. Reads through the
-- read_own_profile policy, not around it.
-- `familyId` is what makes the app branch. NULL means association staff and the
-- normal interface; non-NULL means a head of family, and the router sends him to
-- the family portal instead. It is the same column my_role() consults, so the
-- screen he gets and the rows RLS will give him can never disagree.
CREATE OR REPLACE FUNCTION public.api_me() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', p.id::text,
    'email', p.email,
    'displayName', p.display_name,
    'pictureUrl', p.picture_url,
    'role', p.role::text,
    'status', p.status::text,
    'familyId', p.family_id,
    'familyCode', (SELECT f.family_code FROM public.families f WHERE f.id = p.family_id))
  FROM public.profiles p WHERE p.id = auth.uid()
$$;

-- Records the sign-in. SECURITY DEFINER because `last_login_at` lives on a table
-- the client cannot write — and must not be able to, or it could rewrite anyone's.
-- The WHERE clause pins it to the caller's own row regardless.
CREATE OR REPLACE FUNCTION public.api_touch_login() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, auth AS $$
  UPDATE public.profiles SET last_login_at = now() WHERE id = auth.uid()
$$;

GRANT EXECUTE ON FUNCTION
  public.period_label(text),
  public.member_json(bigint),
  public.api_family_detail(bigint),
  public.api_family_statement(bigint),
  public.api_dashboard(),
  public.api_alerts(),
  public.api_financial_report(date, date),
  public.api_receivables(text),
  public.api_settings(),
  public.api_me(),
  public.api_touch_login()
TO authenticated;

-- ── Re-run the standing guarantees ───────────────────────────────────────────
-- 20260811090800 revoked PUBLIC execute and asserted it, but every function and
-- view created since then came out PUBLIC-executable again, because Postgres
-- grants that by default and ALTER DEFAULT PRIVILEGES does not work here (see that
-- file's header). So the lockdown has to be the LAST thing that runs, every time
-- the surface grows.
DO $revoke$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
  END LOOP;
END $revoke$;

GRANT EXECUTE ON FUNCTION
  public.role_rank(app_role), public.my_role(), public.has_role(app_role),
  public.register_payment(bigint, numeric, pay_method, text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_family(bigint, jsonb, jsonb),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status),
  public.period_label(text),
  public.member_json(bigint),
  public.api_family_detail(bigint),
  public.api_family_statement(bigint),
  public.api_dashboard(),
  public.api_alerts(),
  public.api_financial_report(date, date),
  public.api_receivables(text),
  public.api_settings(),
  public.api_me(),
  public.api_touch_login()
TO authenticated;

SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
