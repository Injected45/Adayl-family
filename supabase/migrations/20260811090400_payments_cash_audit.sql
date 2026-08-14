-- 20260811090400_payments_cash_audit.sql
-- Ports api/migrations/008, 009, 010, 011, 012.

-- ─────────────────────────────────────────────────────────────────────────────
-- payments
--
-- receipt_no is GENERATED from the identity value, for the same reason
-- families.family_code is: MySQL forbade it and needed a follow-up UPDATE
-- inside the transaction, Postgres does not.
--
-- `reference` stays optional even for bank transfers because index.html leaves
-- it optional (PaymentModal line 620). Requiring it would be a new rule.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.payments (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receipt_no    text          GENERATED ALWAYS AS ('PAY-' || lpad(id::text, 6, '0')) STORED,
  family_id     bigint        NOT NULL REFERENCES public.families(id) ON DELETE RESTRICT,
  amount        numeric(12,2) NOT NULL,
  method        pay_method    NOT NULL,
  reference     text,
  receiver      text,
  notes         text,
  status        pay_status    NOT NULL DEFAULT 'معتمد',
  paid_at       timestamptz   NOT NULL DEFAULT now(),
  created_by    uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancelled_at  timestamptz,
  cancelled_by  uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancel_reason text,
  legacy_id     text,

  CONSTRAINT uq_pay_receipt UNIQUE (receipt_no),
  CONSTRAINT uq_pay_legacy  UNIQUE (legacy_id),
  CONSTRAINT ck_pay_amount  CHECK (amount > 0),
  CONSTRAINT ck_pay_cancel  CHECK (status <> 'ملغي' OR cancelled_at IS NOT NULL)
);

CREATE INDEX ix_pay_family ON public.payments (family_id, paid_at);
CREATE INDEX ix_pay_time   ON public.payments (paid_at);
CREATE INDEX ix_pay_status ON public.payments (status, paid_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- payment_allocations — the FIFO split of one payment across receivables.
--
-- Rows are never deleted, not even on cancellation (rule 9): reversal adjusts
-- receivables.paid and marks the payment 'ملغي' while this record of what was
-- applied where survives. sequence_no records the order the FIFO loop actually
-- applied them, which makes a disputed allocation reconstructable.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.payment_allocations (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id    bigint        NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
  receivable_id bigint        NOT NULL REFERENCES public.receivables(id) ON DELETE RESTRICT,
  period        char(7)       NOT NULL,
  amount        numeric(12,2) NOT NULL,
  sequence_no   smallint      NOT NULL,

  CONSTRAINT uq_alloc_pay_recv UNIQUE (payment_id, receivable_id),
  CONSTRAINT ck_alloc_amount   CHECK (amount > 0)
);

CREATE INDEX ix_alloc_recv ON public.payment_allocations (receivable_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- cash_movements — the treasury mirror of every approved payment.
--
-- uq_cash_payment turns business rule 8 into a schema guarantee: a payment can
-- have exactly one cash movement, so a retried request cannot double-count the
-- treasury. That matters more here than it did behind the API, because a mobile
-- client on a flaky connection retries far more often than a server did.
--
-- movement_type carries only 'تحصيل' because that is the sole value index.html
-- produces (line 353) — the association has no way to record money going OUT.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.cash_movements (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id    bigint        NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
  family_id     bigint        NOT NULL REFERENCES public.families(id) ON DELETE RESTRICT,
  amount        numeric(12,2) NOT NULL,
  method        pay_method    NOT NULL,
  movement_type cash_kind     NOT NULL DEFAULT 'تحصيل',
  status        pay_status    NOT NULL DEFAULT 'معتمد',
  occurred_at   timestamptz   NOT NULL,
  legacy_id     text,

  CONSTRAINT uq_cash_payment UNIQUE (payment_id),
  CONSTRAINT uq_cash_legacy  UNIQUE (legacy_id),
  CONSTRAINT ck_cash_amount  CHECK (amount > 0)
);

CREATE INDEX ix_cash_time   ON public.cash_movements (occurred_at);
CREATE INDEX ix_cash_method ON public.cash_movements (method, status, occurred_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- audit_log — append-only regulatory trail (rule 12).
--
-- timestamptz is microsecond-resolution, which covers what MySQL needed
-- DATETIME(3) for: several entries are written inside one operation and rendered
-- newest-first, so second precision made the display order unstable.
--
-- actor_name is snapshotted alongside actor_id so the trail stays readable after
-- a user is renamed or deleted.
--
-- ip_address has no source any more. PostgREST does not expose the client IP to
-- SQL, so this column will be NULL for every row the app writes. Left in place
-- rather than dropped so imported legacy rows keep theirs — see
-- docs/SUPABASE_MIGRATION_PLAN.md, "what cannot be preserved".
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.audit_log (
  id            bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_type    text        NOT NULL,
  detail        text        NOT NULL,
  ref           text,
  actor_user_id uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  actor_name    text        NOT NULL,
  ip_address    text,
  occurred_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX ix_audit_time ON public.audit_log (occurred_at);
CREATE INDEX ix_audit_type ON public.audit_log (event_type, occurred_at);
CREATE INDEX ix_audit_ref  ON public.audit_log (ref);

-- ─────────────────────────────────────────────────────────────────────────────
-- Rule 9 / rule 12: nothing financial is ever hard-deleted, and the audit trail
-- cannot be rewritten.
--
-- index.html never deletes a payment; it marks it 'ملغي', reverses the
-- allocations and keeps the row (cancelPayment line 361). These triggers make
-- that structural rather than conventional.
--
-- Defence in depth is different now. Previously the app's database user could be
-- granted no DELETE privilege, and the triggers guarded against someone with a
-- SQL console. There is no app database user any more — the client IS the
-- caller, so RLS withholds DELETE and these triggers are the backstop that also
-- binds anything holding the service_role key.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refuse_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Rule 9: % rows cannot be deleted, only cancelled', TG_TABLE_NAME
    USING ERRCODE = 'RUL09';
END $$;

CREATE TRIGGER trg_recv_no_delete       BEFORE DELETE ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_recv_lines_no_delete BEFORE DELETE ON public.receivable_lines
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_pay_no_delete        BEFORE DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_alloc_no_delete      BEFORE DELETE ON public.payment_allocations
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_cash_no_delete       BEFORE DELETE ON public.cash_movements
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();

CREATE OR REPLACE FUNCTION public.refuse_audit_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only: rows cannot be modified or deleted'
    USING ERRCODE = 'RUL12';
END $$;

CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION public.refuse_audit_change();
CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON public.audit_log
  FOR EACH ROW EXECUTE FUNCTION public.refuse_audit_change();
