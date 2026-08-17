-- 20260811090400_payments_cash_audit.sql
-- Ports api/migrations/008, 009, 010, 011, 012.

-- ─────────────────────────────────────────────────────────────────────────────
-- payments
--
-- receipt_no is GENERATED from the identity value, for the same reason
-- adeels.adeel_code is: MySQL forbade it and needed a follow-up UPDATE inside
-- the transaction, Postgres does not.
--
-- `reference` stays optional even for bank transfers. Requiring it would be a
-- new rule.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.payments (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  receipt_no    text          GENERATED ALWAYS AS ('PAY-' || lpad(id::text, 6, '0')) STORED,
  adeel_id      bigint        NOT NULL REFERENCES public.adeels(id) ON DELETE RESTRICT,
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

  -- ── IMMUTABLE SNAPSHOT of the receiving account ───────────────────────────
  -- Which association bank account this تحويل مصرفي landed in, as it stood at
  -- the moment of collection. Copied here rather than joined to
  -- association_settings for exactly the reason receivables.adeel_name is
  -- copied: the association will change bank one day, and a receipt reprinted
  -- afterwards must still name the account the money actually went to. A join
  -- would silently restate every historical receipt with the new account.
  --
  -- Filled by register_payment FROM SETTINGS, never sent by the client. The
  -- caller does not get to say where the association's money went — and since
  -- the anon key ships in the APK, "the client would not lie" is not a
  -- guarantee available here.
  --
  -- NULL for cash, and NULL for a transfer taken before any account was
  -- configured. Nullable rather than defaulted to '' so those two cases stay
  -- distinguishable from an account that is genuinely blank.
  bank_name         text,
  bank_account_no   text,
  bank_account_name text,

  legacy_id     text,

  CONSTRAINT uq_pay_receipt UNIQUE (receipt_no),
  CONSTRAINT uq_pay_legacy  UNIQUE (legacy_id),
  CONSTRAINT ck_pay_amount  CHECK (amount > 0),
  CONSTRAINT ck_pay_cancel  CHECK (status <> 'ملغي' OR cancelled_at IS NOT NULL)
);

CREATE INDEX ix_pay_adeel  ON public.payments (adeel_id, paid_at);
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
-- movement_type carries only 'تحصيل' — the association has no way to record
-- money going OUT.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE public.cash_movements (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payment_id    bigint        NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
  adeel_id      bigint        NOT NULL REFERENCES public.adeels(id) ON DELETE RESTRICT,
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
-- actor_user_id carries NO foreign key, deliberately, and that is a correction
-- rather than an omission. It used to be `REFERENCES profiles(id) ON DELETE SET
-- NULL`, which could never once have fired: SET NULL is an UPDATE on audit_log,
-- and refuse_audit_change below rejects every UPDATE on audit_log. The pair did
-- not degrade gracefully — it made deleting any account that had ever written a
-- trail entry impossible, which is the exact opposite of what snapshotting
-- actor_name was for, and it would have aborted purge_all_data outright the
-- first time a portal account redeemed a code before the purge.
--
-- So the column is a plain uuid: a historical note about who acted, not a live
-- relation. It may point at an account that no longer exists, and actor_name is
-- what keeps the row readable when it does.
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
  actor_user_id uuid,
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
-- A payment is never deleted; it is marked 'ملغي', its allocations are reversed
-- and the row is kept. These triggers make that structural rather than
-- conventional.
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
CREATE TRIGGER trg_pay_no_delete        BEFORE DELETE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_alloc_no_delete      BEFORE DELETE ON public.payment_allocations
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
CREATE TRIGGER trg_cash_no_delete       BEFORE DELETE ON public.cash_movements
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
-- Closing a month is financial history like any other: TRUNCATEd by the purges,
-- never deleted row by row. Declared here rather than beside the table because
-- refuse_delete() is defined in this file, and a trigger cannot reference a
-- function that does not exist yet.
CREATE TRIGGER trg_closed_no_delete     BEFORE DELETE ON public.closed_periods
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

-- ═════════════════════════════════════════════════════════════════════════════
-- disbursements — money going OUT of the treasury.
--
-- Until now the association could only take money in: `cash_kind` carried the
-- single value 'تحصيل' and the comment above says so in as many words. This is
-- the other direction, and the association chose its shape deliberately:
--
--   • recorded DIRECTLY, like a collection. No approval queue, no pending
--     state. A mistake is corrected the way a mistaken receipt is — by an
--     explicit reversal that leaves both rows standing.
--   • ADMIN only. Taking money in is low-risk and belongs to the treasurer;
--     paying it out is the direction that empties a treasury, and it was put a
--     rung above even the finance manager.
--
-- ── Why a separate table, and not a row in cash_movements ────────────────────
-- cash_movements is the mirror of an approved PAYMENT: rule 8 gives it exactly
-- one row per payment, uq_cash_payment makes a duplicate structurally
-- impossible, its adeel_id is NOT NULL, and the عديل portal's RLS reads it as
-- "my receipts". A disbursement has no payment, often no عديل, and belongs to
-- nobody's receipts. Forcing it in would mean a nullable payment_id, a widened
-- unique constraint, a sign on every existing SUM, and an RLS policy that has
-- to start distinguishing directions — on the one table the collection path
-- already depends on and which is now carrying real money.
--
-- So the treasury is an ARITHMETIC of two tables rather than one signed ledger:
--
--     رصيد الجمعية  =  Σ cash_movements(معتمد)  −  Σ disbursements(معتمد)
--
-- v_cash_summary computes it, and nothing about collection had to change.
-- ═════════════════════════════════════════════════════════════════════════════
CREATE TABLE public.disbursements (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- EXP-000001, mirroring PAY-000001. Generated, so no code path can mint one
  -- and no two vouchers can carry the same number.
  voucher_no    text          GENERATED ALWAYS AS ('EXP-' || lpad(id::text, 6, '0')) STORED,
  amount        numeric(12,2) NOT NULL,

  -- ── WHICH OF THE TWO SHAPES THIS ROW IS ────────────────────────────────────
  -- Everything below hangs off this. A voucher is either to a named man on the
  -- register, or on an occasion for everybody — and the columns each kind uses
  -- are disjoint, which is what ck_disb_shape at the foot enforces.
  kind          disbursement_kind NOT NULL,

  -- ── لمشترك: who received it ────────────────────────────────────────────────
  -- Both NULL for a collective voucher. The association asked for it that way:
  -- nobody "receives" فطور رمضان, and a name invented to satisfy a NOT NULL
  -- would be a fact the books assert without knowing it.
  --
  -- `payee_name` is a SNAPSHOT even though the id is right beside it, for the
  -- same reason receivables.adeel_name is: a voucher reprinted after the man is
  -- renamed must still say who was actually paid.
  --
  -- ⚠ A disbursement to an عديل is NOT a credit against his subscription. It
  --   never touches receivables, payments or his wallet, and it does not appear
  --   in his statement. The link exists so "how much aid went to this man" can
  --   be answered, and for no other reason — treating it as a payment would let
  --   the association's charity cancel its own dues.
  payee_adeel_id bigint       REFERENCES public.adeels(id) ON DELETE RESTRICT,
  payee_name    text,

  -- ── وجه الصرف: what the money was for. BOTH kinds carry one ────────────────
  -- The عديل above says WHO was paid, which is a different question: a man may
  -- be given something for a wedding one month and a bereavement the next, and
  -- a register of names cannot tell those apart.
  --
  -- Which of the six are legal depends on the kind — see ck_disb_shape.
  category      expense_category NOT NULL,

  method        pay_method    NOT NULL,
  reference     text,
  -- The account the money was sent TO, as given on the day. Same reasoning as
  -- payments.bank_*: a join to current settings would restate history.
  bank_name         text,
  bank_account_no   text,
  bank_account_name text,
  -- Who physically handed it over. A name, not a user id: the man carrying the
  -- cash to a hospital is not necessarily the one holding the phone.
  handed_by     text,
  note          text,

  status        pay_status    NOT NULL DEFAULT 'معتمد',
  spent_at      timestamptz   NOT NULL DEFAULT now(),
  created_by    uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancelled_at  timestamptz,
  cancelled_by  uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancel_reason text,

  CONSTRAINT ck_disb_amount CHECK (amount > 0),

  -- ── THE TWO SHAPES, and nothing in between ─────────────────────────────────
  -- The kind is not a label on the row, it IS the row's shape, and this is what
  -- makes that true. Two rules at once, and neither can be said by a per-column
  -- constraint:
  --
  --   1. THE PAYEE. لمشترك names a man; جماعي names nobody, by the
  --      association's own decision — nobody receives فطور رمضان the way a
  --      member receives aid. Without this a collective voucher could carry
  --      somebody's name, or a member voucher none.
  --
  --   2. THE VALID وجه FOR THAT KIND. مولود is a family's and only ever goes to
  --      a member; فطور رمضان is one table for everybody and is never one man's.
  --      Written as exclusions rather than as two lists, so a seventh heading
  --      that BOTH kinds may use needs no edit here — only one belonging to a
  --      single kind does.
  --
  -- All of it would otherwise pass every other check here and surface on a
  -- screen months later, filed under a heading it does not belong to.
  CONSTRAINT ck_disb_shape CHECK (
    (kind = 'لمشترك'
       AND payee_adeel_id IS NOT NULL
       AND btrim(coalesce(payee_name, '')) <> ''
       AND category <> 'فطور رمضان')
    OR
    (kind = 'جماعي'
       AND payee_adeel_id IS NULL
       AND payee_name IS NULL
       AND category <> 'مولود')
  ),
  -- A cancelled voucher must say why, exactly as a cancelled receipt must.
  CONSTRAINT ck_disb_cancel CHECK (
    status <> 'ملغي' OR (cancelled_at IS NOT NULL
                     AND btrim(coalesce(cancel_reason, '')) <> ''))
);

CREATE INDEX ix_disb_spent    ON public.disbursements (spent_at DESC);
CREATE INDEX ix_disb_category ON public.disbursements (category);
CREATE INDEX ix_disb_payee    ON public.disbursements (payee_adeel_id);

-- Rule 9 applies here too: reversed, never removed. A voucher that could be
-- deleted is a treasury that can be quietly rebalanced.
CREATE TRIGGER trg_disb_no_delete BEFORE DELETE ON public.disbursements
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();
