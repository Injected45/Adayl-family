-- 20260811091100_api_reads.sql — the nested read shapes.
--
-- Four of the app's screens consume JSON that no flat view can produce: an
-- عديل's detail wraps his row with his KPIs, the dashboard wraps stats and top
-- debtors, the report wraps totals plus a payment list, and the statement is an
-- ordered debit/credit merge with a running balance.
--
-- All STABLE and SECURITY INVOKER. They run as the caller, so the RLS policies
-- from 20260811090500 still decide what is visible — a viewer calling
-- api_dashboard() sees the association's figures, an unapproved user sees zeroes
-- and empty lists, and neither is a special case anyone had to write.
--
-- Money is text in every one of them.

-- ── AdeelView, reused by detail and the portal ───────────────────────────────
-- to_jsonb over the view rather than a hand-built object: v_adeels already names
-- every column exactly as the Dart model reads it, and building the same keys
-- twice is how the two drift apart.
--
-- The `eligibility` object the old member_json carried is gone. It reported
-- مستحق / قريب من السن / غير مستحق for a son against the age gate, and there is
-- no age gate — an عديل is billed on `membershipStatus` alone.
CREATE OR REPLACE FUNCTION public.adeel_json(p_adeel_id bigint) RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT to_jsonb(v) FROM public.v_adeels v WHERE v."id" = p_adeel_id
$$;

-- ── GET /adeels/:id (AdeelDetail) ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.api_adeel_detail(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'adeel', public.adeel_json(p_adeel_id),
    'kpis', jsonb_build_object(
      'monthlyExpected', v."monthlyExpected",
      'issued', v."issued",
      'debt', v."debt",
      'paid', v."paid",
      'openPeriods', (SELECT count(*) FROM public.receivables r
                       WHERE r.adeel_id = p_adeel_id
                         AND r.status <> 'ملغي' AND r.balance > 0)),
    'receivables', coalesce(
      (SELECT jsonb_agg(to_jsonb(r) ORDER BY r."period" DESC)
         FROM public.v_receivables r WHERE r."adeelId" = p_adeel_id),
      '[]'::jsonb),
    'payments', coalesce(
      (SELECT jsonb_agg(to_jsonb(p) ORDER BY p."paidAt" DESC)
         FROM public.v_payments p WHERE p."adeelId" = p_adeel_id),
      '[]'::jsonb))
  FROM public.v_adeels v WHERE v."id" = p_adeel_id
$$;

-- ── GET /adeels/:id/statement (Statement) ────────────────────────────────────
-- Rule 11: a chronological merge of charges (debit) and payments (credit) with a
-- running balance. The running total is a window function over the merged set,
-- which is the whole reason this cannot be two separate list queries stitched
-- together in Dart — the order has to be established before the balance is.
CREATE OR REPLACE FUNCTION public.api_adeel_statement(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  WITH movements AS (
    SELECT r.created_at AS at,
           r.period      AS reference,
           'استحقاق'::text AS kind,
           r.total       AS debit,
           NULL::numeric AS credit,
           public.period_label(r.period) AS note
      FROM public.receivables r
     WHERE r.adeel_id = p_adeel_id AND r.status <> 'ملغي'
    UNION ALL
    SELECT p.paid_at,
           p.receipt_no,
           'دفعة'::text,
           NULL::numeric,
           p.amount,
           -- ── The METHOD, in words. Not the transfer reference. ────────────
           -- This read `coalesce(nullif(p.reference,''), p.method::text)`, so a
           -- transfer that carried a reference put a bare number in the
           -- statement's البيان column — "34871" against 250.00, which tells a
           -- member nothing about what the line is and reads like a second
           -- amount next to the first.
           --
           -- The reference identifies the transfer to the BANK; it is not what
           -- the movement was. What it was is "تحويل مصرفي" or "نقداً", which is
           -- also the one thing on the line he can check against his own
           -- records. It stays on the payment row and on the collections
           -- screen, where a treasurer reconciling with a bank statement is the
           -- person who actually needs it.
           p.method::text
      FROM public.payments p
     WHERE p.adeel_id = p_adeel_id AND p.status <> 'ملغي'
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

-- ── GET /dashboard (DashboardData) ───────────────────────────────────────────
-- The old stat row counted families, sons, and how many sons were eligible,
-- approaching eligibility, or under age. None of those quantities exist. What
-- replaces them is the register broken down by membership status, which is the
-- only thing that now decides whether someone is billed.
CREATE OR REPLACE FUNCTION public.api_dashboard() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  WITH period AS (
    -- The PREVIOUS month, not this one; the current month is not closed until it
    -- ends.
    SELECT to_char(date_trunc('month', current_date) - interval '1 month',
                   'YYYY-MM') AS p
  )
  SELECT jsonb_build_object(
    'stats', jsonb_build_object(
      'adeels', (SELECT count(*) FROM public.adeels),
      'active', (SELECT count(*) FROM public.adeels WHERE status = 'نشط'),
      'suspended', (SELECT count(*) FROM public.adeels WHERE status = 'موقوف'),
      'deceased', (SELECT count(*) FROM public.adeels WHERE status = 'متوفى'),
      'debt', (SELECT coalesce(sum(balance), 0)::numeric(12,2)::text FROM public.receivables
                WHERE status <> 'ملغي'),
      'collected', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                      FROM public.cash_movements WHERE status <> 'ملغي'),
      'cash', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text FROM public.cash_movements
                WHERE status <> 'ملغي' AND method = 'نقداً'),
      'transfer', (SELECT coalesce(sum(amount), 0)::numeric(12,2)::text
                     FROM public.cash_movements
                    WHERE status <> 'ملغي' AND method = 'تحويل مصرفي'),
      'indebtedAdeels', (SELECT count(DISTINCT adeel_id)
                           FROM public.receivables
                          WHERE status <> 'ملغي' AND balance > 0)),
    'topDebtors', coalesce(
      (SELECT jsonb_agg(d ORDER BY (d ->> 'debt')::numeric DESC)
         FROM (SELECT jsonb_build_object(
                        'adeelId', v."id",
                        'adeelCode', v."adeelCode",
                        'adeelName', v."fullName",
                        'debt', v."debt") AS d
                 FROM public.v_adeels v
                WHERE v."debt"::numeric > 0
                ORDER BY v."debt"::numeric DESC
                LIMIT 10) top),
      '[]'::jsonb),
    'closingPeriod', (SELECT p FROM period),
    'closingPeriodLabel', (SELECT public.period_label(p) FROM period))
$$;

-- ── GET /alerts (AlertItem) ──────────────────────────────────────────────────
-- `text` is display prose, which the Node API also produced. It stays server-side
-- so one wording is used everywhere; the client has no month names or templates
-- of its own to rebuild it from.
--
-- The 'age' alert ("يقترب من سن الاستحقاق") is gone with the age gate. Debt and
-- partial payment are what remain, and they were always the two a treasurer acts
-- on.
CREATE OR REPLACE FUNCTION public.api_alerts() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_agg(a ORDER BY (a ->> 'severity') DESC), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
             'type', 'debt',
             'severity', 'danger',
             'text', v."fullName" || ' — مديونية ' || v."debt",
             'adeelId', v."id") AS a
      FROM public.v_adeels v
     WHERE v."debt"::numeric > 0
    UNION ALL
    SELECT jsonb_build_object(
             'type', 'partial',
             'severity', 'info',
             'text', r."adeelName" || ' — ' || r."periodLabel"
                     || ' مسدد جزئياً (' || r."balance" || ' متبقٍ)',
             'adeelId', r."adeelId")
      FROM public.v_receivables r
     WHERE r."status" = 'مسدد جزئياً'
  ) alerts
$$;

-- ── GET /reports/financial (FinancialReport) ─────────────────────────────────
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
    -- a smaller debt for a shorter report.
    'debt', (SELECT coalesce(sum(r.balance), 0)::numeric(12,2)::text FROM public.receivables r
              WHERE r.status <> 'ملغي'),
    'partialCount', (SELECT count(*) FROM public.receivables r
                      WHERE r.status = 'مسدد جزئياً'),
    'payments', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  'receiptNo', p."receiptNo",
                  'adeelName', p."adeelName",
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

-- ── GET /periods/closable — what the dashboard's close-month button offers ───
--
-- Every month from system_start to LAST month, newest first, each with its
-- Arabic label and whether it has already been raised.
--
-- WHY THIS IS A SERVER CALL AND NOT A CLIENT-SIDE DATE PICKER: the client has no
-- month names. `period_label` lives here precisely so one spelling of each month
-- is used across the receivables list, the dashboard button and the audit trail,
-- and a picker that built its own would be a second spelling waiting to
-- disagree. The range is the association's own — system_start is a setting, not
-- a calendar fact — and only the database knows it.
--
-- Each month carries the two flags rules 15a and 15b turn into:
--
--   closed      — it is in closed_periods. Rule 15a refuses it outright.
--   selectable  — it is the EARLIEST month not yet closed, and therefore the
--                 only one rule 15b will accept. Everything after it is blocked
--                 until this one is done.
--
-- So the list is exhaustive but exactly one row is ever tappable. Showing the
-- others rather than hiding them is the point: a treasurer checking whether
-- March was closed needs to SEE March, and one who wonders why August is greyed
-- out needs to see the open July above it.
--
-- `selectable` is computed here rather than in Dart because it IS rule 15b, and
-- a client that worked it out for itself would be a second implementation of a
-- money rule — free to disagree with the one that actually decides.
--
-- The CURRENT month is deliberately absent: it is not closed until it ends,
-- which is the same rule auto_close_periods() walks.
CREATE OR REPLACE FUNCTION public.api_closable_periods() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  WITH months AS (
    SELECT to_char(d, 'YYYY-MM') AS period
      FROM public.association_settings s,
           generate_series(
             date_trunc('month', s.system_start),
             date_trunc('month', current_date) - interval '1 month',
             interval '1 month') d
     WHERE s.id = 1
  ), flagged AS (
    SELECT m.period,
           EXISTS (SELECT 1 FROM public.closed_periods c
                    WHERE c.period = m.period) AS closed
      FROM months m
  ), next_open AS (
    SELECT min(period) AS period FROM flagged WHERE NOT closed
  )
  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period', f.period,
        'label',  public.period_label(f.period),
        'closed', f.closed,
        'selectable', f.period = (SELECT period FROM next_open))
      ORDER BY f.period DESC),
    '[]'::jsonb)
  FROM flagged f
$$;

-- ── GET /receivables (ReceivablesPage) ───────────────────────────────────────
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

-- ── GET /settings, full editable shape (EditableSettings) ────────────────────
CREATE OR REPLACE FUNCTION public.api_settings() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'associationName', s.association_name,
    'currency', s.currency,
    'memberFee', s.member_fee::text,
    'systemStart', to_char(s.system_start, 'YYYY-MM-DD'),
    'autoClosePreviousMonths', s.auto_close_previous_months,
    'bankName', s.bank_name,
    'bankAccountNo', s.bank_account_no,
    'bankAccountName', s.bank_account_name,
    -- adeelId is what the settings screen preselects in its dropdown; the name
    -- and phone travel with it so the screen can render the current holder
    -- without a second read. NULL means the post is vacant, or was filled by a
    -- typed name before the two posts were tied to the register.
    'treasurer', jsonb_build_object(
      'adeelId', s.treasurer_adeel_id,
      'name', s.treasurer_name,
      'phone', s.treasurer_phone),
    'financeManager', jsonb_build_object(
      'adeelId', s.finance_manager_adeel_id,
      'name', s.finance_manager_name,
      'phone', s.finance_manager_phone))
  FROM public.association_settings s WHERE s.id = 1
$$;

-- ── The caller's own profile ─────────────────────────────────────────────────
-- Readable by a pending or suspended account, because the app has to be able to
-- render "awaiting approval" for exactly those users. Reads through the
-- read_own_profile policy, not around it.
-- `adeelId` is what makes the app branch. NULL means association staff and the
-- normal interface; non-NULL means a portal account, and the router sends him to
-- his own page instead. It is the same column my_role() consults, so the screen
-- he gets and the rows RLS will give him can never disagree.
CREATE OR REPLACE FUNCTION public.api_me() RETURNS jsonb
LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'id', p.id::text,
    'email', p.email,
    'displayName', p.display_name,
    'pictureUrl', p.picture_url,
    'role', p.role::text,
    'status', p.status::text,
    'adeelId', p.adeel_id,
    'adeelCode', (SELECT a.adeel_code FROM public.adeels a WHERE a.id = p.adeel_id),
    -- ── Why the portal is empty, said out loud ──────────────────────────────
    -- my_adeel_id() enforces the one-device rule by returning NULL, so a عديل
    -- on the wrong handset gets a portal with no dues, no ledger and no
    -- explanation — which reads as a broken app, not as a rule.
    --
    -- This flag is the explanation, and it is deliberately NOT the enforcement:
    -- it is computed from the same three states my_adeel_id() decides on, but
    -- nothing depends on the client honouring it. Hiding the message would
    -- change what he is told, never what he can read.
    'deviceLocked', (p.adeel_id IS NOT NULL
                     AND p.device_id IS DISTINCT FROM public.request_device_id()))
  FROM public.profiles p WHERE p.id = auth.uid()
$$;

-- Records the sign-in. SECURITY DEFINER because `last_login_at` lives on a table
-- the client cannot write — and must not be able to, or it could rewrite anyone's.
-- The WHERE clause pins it to the caller's own row regardless.
-- It also CLAIMS an unclaimed device, which is how a released lock is taken up
-- again — and how the عدايل who were already bound before the rule existed keep
-- working instead of all being locked out by the migration that introduced it.
--
-- `device_id IS NULL` is the only case it writes. It never REPLACES a claim, so
-- a second handset calling this cannot steal the binding: it writes nothing and
-- my_adeel_id() goes on refusing it. Releasing is an admin act — reissue the
-- code — and this is the other half of it.
--
-- Staff are excluded by `adeel_id IS NOT NULL`. Stamping a device on an admin
-- would lock the association out of its own app the first time a phone was
-- replaced, and nothing would read the column anyway.
CREATE OR REPLACE FUNCTION public.api_touch_login() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public, auth AS $$
  UPDATE public.profiles
     SET last_login_at = now(),
         device_id = CASE
           WHEN adeel_id IS NOT NULL AND device_id IS NULL
             THEN public.request_device_id()
           ELSE device_id END
   WHERE id = auth.uid()
$$;

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
  public.my_adeel_id(),
  public.register_payment(bigint, numeric, pay_method, text, text, text,
                          text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_adeel(bigint, jsonb),
  public.delete_adeel(bigint),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status),
  public.purge_financial_data(text),
  public.purge_all_data(text),
  public.issue_adeel_code(bigint),
  public.redeem_adeel_code(text, text),
  public.period_label(text),
  public.adeel_json(bigint),
  public.api_adeel_detail(bigint),
  public.api_adeel_statement(bigint),
  public.api_dashboard(),
  public.api_alerts(),
  public.api_financial_report(date, date),
  public.api_receivables(text),
  public.api_closable_periods(),
  public.api_settings(),
  public.api_me(),
  public.api_touch_login()
TO authenticated;

SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
