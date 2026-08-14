-- 20260811090300_receivables.sql — the immutable financial core.
-- Ports api/migrations/006 and 007.
--
-- Three business rules are made structurally impossible to violate rather than
-- merely checked in code:
--
--   Rule 4  one live receivable per (family, period)
--           → uq_recv_active_period, a PARTIAL unique index. MySQL needed a
--             generated `active_period` column that produced NULL for cancelled
--             rows; Postgres indexes `WHERE status <> 'ملغي'` directly.
--             Cancelling frees the slot while the row survives forever.
--
--   Rule 5  receivables are immutable snapshots
--           → trg_recv_snapshot_immutable rejects any UPDATE touching a
--             snapshot column, so editing association_settings CANNOT alter a
--             historical receivable regardless of application correctness.
--
--   Rule 7  a payment can never exceed what is owed
--           → ck_recv_paid. Even if an allocation bug slips past the balance
--             check, the storage engine refuses the write.
--
-- `balance` is generated, not maintained, so it cannot drift from total - paid.

CREATE TABLE public.receivables (
  id                       bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  family_id                bigint        NOT NULL REFERENCES public.families(id) ON DELETE RESTRICT,
  period                   char(7)       NOT NULL,
  period_end               date          NOT NULL,

  -- ── IMMUTABLE SNAPSHOT ────────────────────────────────────────────────────
  father_fee               numeric(12,2) NOT NULL,
  son_fee                  numeric(12,2) NOT NULL,
  father_member_id         bigint        REFERENCES public.members(id) ON DELETE SET NULL,
  father_name              text          NOT NULL,
  eligibility_age_snapshot smallint      NOT NULL,
  warning_months_snapshot  smallint      NOT NULL,
  total                    numeric(12,2) NOT NULL,
  -- ──────────────────────────────────────────────────────────────────────────

  paid                     numeric(12,2) NOT NULL DEFAULT 0.00,
  balance                  numeric(12,2) GENERATED ALWAYS AS (total - paid) STORED,
  status                   recv_status   NOT NULL DEFAULT 'غير مسدد',

  created_at               timestamptz   NOT NULL DEFAULT now(),
  created_by               uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancelled_at             timestamptz,
  cancelled_by             uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancel_reason            text,
  legacy_id                text,

  CONSTRAINT uq_recv_legacy UNIQUE (legacy_id),
  CONSTRAINT ck_recv_total  CHECK (total > 0),
  CONSTRAINT ck_recv_paid   CHECK (paid >= 0 AND paid <= total),
  CONSTRAINT ck_recv_period CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT ck_recv_fees   CHECK (father_fee >= 0 AND son_fee >= 0),
  CONSTRAINT ck_recv_cancel CHECK (status <> 'ملغي' OR cancelled_at IS NOT NULL)
);

-- Rule 4.
CREATE UNIQUE INDEX uq_recv_active_period
  ON public.receivables (family_id, period) WHERE status <> 'ملغي';

CREATE INDEX ix_recv_period      ON public.receivables (period, status);
CREATE INDEX ix_recv_family_open ON public.receivables (family_id, status, period);
CREATE INDEX ix_recv_created     ON public.receivables (created_at);

-- Rule 5. The only columns an UPDATE may legitimately touch are paid, status,
-- and the three cancellation columns. IS DISTINCT FROM is the NULL-safe
-- comparison — it replaces MySQL's `<=>` and catches a change to or from NULL.
CREATE OR REPLACE FUNCTION public.guard_recv_snapshot() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF  NEW.family_id                IS DISTINCT FROM OLD.family_id
   OR NEW.period                   IS DISTINCT FROM OLD.period
   OR NEW.period_end               IS DISTINCT FROM OLD.period_end
   OR NEW.father_fee               IS DISTINCT FROM OLD.father_fee
   OR NEW.son_fee                  IS DISTINCT FROM OLD.son_fee
   OR NEW.father_member_id         IS DISTINCT FROM OLD.father_member_id
   OR NEW.father_name              IS DISTINCT FROM OLD.father_name
   OR NEW.eligibility_age_snapshot IS DISTINCT FROM OLD.eligibility_age_snapshot
   OR NEW.warning_months_snapshot  IS DISTINCT FROM OLD.warning_months_snapshot
   OR NEW.total                    IS DISTINCT FROM OLD.total
   OR NEW.created_at               IS DISTINCT FROM OLD.created_at
   OR NEW.created_by               IS DISTINCT FROM OLD.created_by
   OR NEW.legacy_id                IS DISTINCT FROM OLD.legacy_id
  THEN
    RAISE EXCEPTION 'Rule 5: receivable snapshot columns are immutable'
      USING ERRCODE = 'RUL05';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_recv_snapshot_immutable
  BEFORE UPDATE ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.guard_recv_snapshot();

-- Keeps `status` in agreement with the money instead of trusting the caller to
-- pass the right label. index.html derived it (receivableStatus); deriving it in
-- a trigger means a hostile client cannot mark an unpaid charge as settled.
CREATE OR REPLACE FUNCTION public.derive_recv_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'ملغي' THEN
    RETURN NEW;                              -- cancellation is explicit
  END IF;
  NEW.status := CASE
    WHEN NEW.paid <= 0        THEN 'غير مسدد'::recv_status
    WHEN NEW.paid >= NEW.total THEN 'مسدد بالكامل'::recv_status
    ELSE 'مسدد جزئياً'::recv_status
  END;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_recv_status
  BEFORE INSERT OR UPDATE ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.derive_recv_status();

-- ─────────────────────────────────────────────────────────────────────────────
-- receivable_lines — which members were actually billed, snapshotted.
--
-- Replaces the prototype's parallel eligibleSonIds[] / eligibleSonNames[]
-- arrays with real rows. Name and national ID are duplicated rather than
-- joined, so a receipt printed years later still shows the details as they
-- stood when the charge was raised.
--
-- Invariant asserted by generate_period() and the reconciler:
--   SUM(receivable_lines.fee_amount) = receivables.total
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.receivable_lines (
  id                 bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receivable_id      bigint        NOT NULL REFERENCES public.receivables(id) ON DELETE RESTRICT,
  -- SET NULL, not RESTRICT: losing the member link must never destroy financial
  -- history, and the snapshot columns keep the line readable without it.
  member_id          bigint        REFERENCES public.members(id) ON DELETE SET NULL,
  member_kind        member_kind   NOT NULL,
  member_name        text          NOT NULL,
  member_national_id text          NOT NULL,
  fee_amount         numeric(12,2) NOT NULL,

  CONSTRAINT uq_line_recv_member UNIQUE (receivable_id, member_id),
  CONSTRAINT ck_line_fee CHECK (fee_amount >= 0)
);

CREATE INDEX ix_line_member ON public.receivable_lines (member_id);
