-- 20260811090300_receivables.sql — the immutable financial core.
-- Ports api/migrations/006 and 007.
--
-- Three business rules are made structurally impossible to violate rather than
-- merely checked in code:
--
--   Rule 4  one live receivable per (عديل, period)
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
--
-- ── What the عديل model removed here ────────────────────────────────────────
-- `receivable_lines` is GONE, and so is the whole idea of a charge being split
-- across people. A receivable used to bill a household: a father at one rate
-- plus every eligible son at another, with one line per person and the invariant
-- SUM(lines.fee_amount) = total. One عديل is billed for one month at one rate,
-- so that table would hold exactly one row per receivable forever and the
-- invariant would read total = total.
--
-- The snapshot columns absorbed what the line carried. `adeel_name` is
-- duplicated here rather than joined, for the reason the lines duplicated it: a
-- receipt printed years later must show the name as it stood when the charge was
-- raised, even if the عديل was renamed since.
--
-- `adeel_national_id` sat beside it and is gone with the column it copied. The
-- name is now the ONLY identifying thing a historical receipt carries, which is
-- worth stating plainly: two عدايل sharing a name produce receipts that cannot
-- be told apart by reading them — only by their id.
--
-- There is no separate fee column. With one person and one month, the rate IS
-- the total, and carrying both would invite them to disagree.

CREATE TABLE public.receivables (
  id                bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  adeel_id          bigint        NOT NULL REFERENCES public.adeels(id) ON DELETE RESTRICT,
  period            char(7)       NOT NULL,
  period_end        date          NOT NULL,

  -- ── IMMUTABLE SNAPSHOT ────────────────────────────────────────────────────
  adeel_name        text          NOT NULL,
  total             numeric(12,2) NOT NULL,
  -- ──────────────────────────────────────────────────────────────────────────

  paid              numeric(12,2) NOT NULL DEFAULT 0.00,
  balance           numeric(12,2) GENERATED ALWAYS AS (total - paid) STORED,
  status            recv_status   NOT NULL DEFAULT 'غير مسدد',

  created_at        timestamptz   NOT NULL DEFAULT now(),
  created_by        uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancelled_at      timestamptz,
  cancelled_by      uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancel_reason     text,
  legacy_id         text,

  CONSTRAINT uq_recv_legacy UNIQUE (legacy_id),
  CONSTRAINT ck_recv_total  CHECK (total > 0),
  CONSTRAINT ck_recv_paid   CHECK (paid >= 0 AND paid <= total),
  CONSTRAINT ck_recv_period CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT ck_recv_cancel CHECK (status <> 'ملغي' OR cancelled_at IS NOT NULL)
);

-- Rule 4.
CREATE UNIQUE INDEX uq_recv_active_period
  ON public.receivables (adeel_id, period) WHERE status <> 'ملغي';

CREATE INDEX ix_recv_period     ON public.receivables (period, status);
CREATE INDEX ix_recv_adeel_open ON public.receivables (adeel_id, status, period);
CREATE INDEX ix_recv_created    ON public.receivables (created_at);

-- Rule 5. The only columns an UPDATE may legitimately touch are paid, status,
-- and the three cancellation columns. IS DISTINCT FROM is the NULL-safe
-- comparison — it replaces MySQL's `<=>` and catches a change to or from NULL.
CREATE OR REPLACE FUNCTION public.guard_recv_snapshot() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF  NEW.adeel_id          IS DISTINCT FROM OLD.adeel_id
   OR NEW.period            IS DISTINCT FROM OLD.period
   OR NEW.period_end        IS DISTINCT FROM OLD.period_end
   OR NEW.adeel_name        IS DISTINCT FROM OLD.adeel_name
   OR NEW.total             IS DISTINCT FROM OLD.total
   OR NEW.created_at        IS DISTINCT FROM OLD.created_at
   OR NEW.created_by        IS DISTINCT FROM OLD.created_by
   OR NEW.legacy_id         IS DISTINCT FROM OLD.legacy_id
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
-- pass the right label. Deriving it in a trigger means a hostile client cannot
-- mark an unpaid charge as settled.
CREATE OR REPLACE FUNCTION public.derive_recv_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'ملغي' THEN
    RETURN NEW;                              -- cancellation is explicit
  END IF;
  NEW.status := CASE
    WHEN NEW.paid <= 0         THEN 'غير مسدد'::recv_status
    WHEN NEW.paid >= NEW.total THEN 'مسدد بالكامل'::recv_status
    ELSE 'مسدد جزئياً'::recv_status
  END;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_recv_status
  BEFORE INSERT OR UPDATE ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.derive_recv_status();

-- ─────────────────────────────────────────────────────────────────────────────
-- closed_periods — WHICH months have been closed, as an event.
--
-- Rule 4 already stops a month being billed twice PER عديل. This table answers a
-- different question that rule 4 cannot: has this month been closed AT ALL?
--
-- WHY THE RECEIVABLES CANNOT ANSWER IT. "Closed" was inferred from "has live
-- receivables", and that inference is wrong in a case the association will
-- certainly hit: a month in which nobody was نشط produces ZERO receivables, so
-- it would read as never closed, forever — and under the ordering rule below it
-- would then block every month after it permanently. Closing a month is
-- something someone DID; it is not a shape the data happens to have.
--
-- `created` records how many receivables that close produced, which is what
-- makes a legitimate zero distinguishable from a month nobody touched.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.closed_periods (
  period    char(7)     PRIMARY KEY,
  closed_at timestamptz NOT NULL DEFAULT now(),
  closed_by uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created   int         NOT NULL DEFAULT 0,

  CONSTRAINT ck_closed_period  CHECK (period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  CONSTRAINT ck_closed_created CHECK (created >= 0)
);
