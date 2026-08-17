-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-17.  The device lock, the wallet, money out.
--
--  GENERATED FILE. Do not edit. Source of truth: supabase/migrations/.
--
--  WHAT THIS DOES — five things, in one transaction
--
--    §1–6  ONE عديل, ONE HANDSET. His access code opens the portal on a single
--          phone; the same Google account on a second phone sees nothing.
--    §7    THE STATEMENT SAYS WHAT, NOT WHICH REF. A transfer now reads
--          «تحويل مصرفي» in the البيان column instead of a bare bank number
--          that looked like a second amount.
--    §8    THE WALLET. A member may pay AHEAD. The cap at "no more than owed"
--          is gone; the surplus is credit, and generate_period() spends it the
--          instant it raises the next month.
--    §9     MONEY OUT — the table. A disbursements table with the two shapes a
--           voucher may take, enforced by ck_disb_shape.
--    §10–11 THE TREASURY, AND A MEMBER'S VIEW OF IT. v_cash_summary gains
--           outstanding/disbursed/balance; api_association_finance() gives an
--           عديل the association's TOTALS — aggregates only, never a row.
--    §12    The register/cancel pair, the reads, and the rule that makes it
--           safe: the association cannot pay out money it does not hold.
--
--  ⚠ §9 COMES BEFORE §10 FOR A REASON, and it did not always.
--     v_cash_summary reads public.disbursements, and a VIEW's body is resolved
--     when the view is created — unlike a plpgsql function, whose table
--     references are looked up only when it RUNS. With the table created after
--     it, §10 aborted the whole patch with
--         42P01: relation "public.disbursements" does not exist
--     while §11's api_association_finance, which reads the same table, was
--     created without complaint and then failed on every call.
--
--     It was not caught because the patch was only ever tested against a
--     database that already had the table — where the order cannot matter. A
--     patch has to be tested against the schema it is FOR.
--
--  Nothing here is destructive. One DROP FUNCTION (see below), no DROP TABLE,
--  no TRUNCATE outside the two purge functions' own bodies, no row touched.
--
--  ── §1–6, in detail ────────────────────────────────────────────────────────
--
--  ⚠ IT IS NOT A MAC ADDRESS, AND NOTHING CAN BE.
--     Android has returned the constant 02:00:00:00:00:00 to every app since
--     API 23 and randomises the real one per network since Android 10; iOS
--     never exposed it. What the app sends is a SHA-256 of ANDROID_ID (or
--     identifierForVendor), which is the closest stable per-device value the
--     platform still gives out. It survives app updates and reinstalls and
--     changes on a factory reset.
--
--  HOW IT IS ENFORCED
--     `my_adeel_id()` — the function EVERY عديل-scoped RLS policy goes through
--     — compares profiles.device_id against the `x-device-id` request header
--     and returns NULL when they differ. Returning NULL is the mechanism: it
--     matches no row, so the wrong handset gets an empty portal. Putting the
--     check in the portal's read functions instead would leave a client talking
--     to PostgREST directly completely unaffected.
--
--     Be clear about the limit: a header is set by the client, and the anon key
--     is public. This stops SHARING — a second handset, a lent Google password
--     — and it is not proof against someone who forges the header. The code
--     remains the authorisation; the device is a constraint on convenience.
--
--  THE THREE STATES, AND WHY THE MIDDLE ONE REFUSES
--     device_id IS NULL   → REFUSED. "Released, not yet claimed."
--     device_id = header  → allowed.
--     device_id <> header → refused.
--
--     Reading NULL as a pass would turn one admin click into an unlock for
--     every device at once, which is the opposite of the feature.
--
--  RELEASING A LOST PHONE
--     `issue_adeel_code` clears device_id. The عديل stays BOUND — clearing
--     adeel_id too would drop him to a plain approved viewer, who reads the
--     WHOLE association, so the unlock would be a privilege escalation with a
--     time window. He is locked out until the handset holding the new code
--     opens the app, and `api_touch_login` claims it. A second handset calling
--     the same function cannot steal a claim that is already held.
--
--  EXISTING عدايل ARE NOT LOCKED OUT.
--     Anyone already bound has device_id NULL after this patch, so the FIRST
--     handset that opens the app claims it — which for a member already using
--     the app is the phone in his hand. No reissue, no retyping.
--
--  ⚠ THIS PATCH CONTAINS ONE DROP, AND IT IS DELIBERATE
--       DROP FUNCTION IF EXISTS public.redeem_adeel_code(text)
--     CREATE OR REPLACE cannot add a parameter, and leaving the one-argument
--     version beside the two-argument one makes every call ambiguous (42725).
--     Dropping a FUNCTION destroys no data and touches no row. Its EXECUTE
--     grant goes with it and is re-issued by the lockdown sweep in section 13.
--
--     Nothing else is dropped. No DROP SCHEMA, no DROP TABLE, no DROP TRIGGER,
--     no TRUNCATE, no DELETE, and nothing touching auth.users or profiles rows.
--     assert_signin_intact() runs before COMMIT.
--
--  HOW TO APPLY
--    Supabase dashboard, SQL Editor, New query, paste all of this, Run.
--    One transaction: if anything fails, nothing changes. Safe to run twice.
-- ============================================================================

BEGIN;

-- == 1. The column =========================================================
-- Nullable, and NULL is a refusal rather than a pass. See the header.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS device_id text;

-- == 2. Which device is asking =============================================
-- Declared before my_adeel_id() uses it: check_function_bodies is on, so a SQL
-- function calling one Postgres has not seen yet fails at CREATE time.
CREATE OR REPLACE FUNCTION public.request_device_id() RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT nullif(
    btrim(coalesce(
      current_setting('request.headers', true)::json ->> 'x-device-id', '')),
    '')
$$;

-- == 3. my_adeel_id — where the rule actually bites ========================
CREATE OR REPLACE FUNCTION public.my_adeel_id() RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT p.adeel_id
    FROM public.profiles p
   WHERE p.id = auth.uid()
     AND p.status = 'approved'
     AND p.device_id IS NOT NULL
     AND p.device_id = public.request_device_id()
$$;

-- == 4. redeem_adeel_code — the moment the lock is established =============
-- The DROP is the only one in this file; see the header.
DROP FUNCTION IF EXISTS public.redeem_adeel_code(text);

CREATE OR REPLACE FUNCTION public.redeem_adeel_code(
  p_code      text,
  p_device_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_norm   text;
  v_device text;
  v_row    record;
  v_me     record;
  v_adeel  record;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول أولاً' USING ERRCODE = 'RUL14';
  END IF;

  SELECT * INTO v_me FROM public.profiles WHERE id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROFILE_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  IF v_me.role <> 'viewer' THEN
    RAISE EXCEPTION 'هذا الحساب حساب إداري ولا يمكن ربطه بعديل'
      USING ERRCODE = 'RUL14';
  END IF;

  -- A SUSPENDED account cannot redeem its way back in.
  --
  -- This is the one status that has to be checked here, and it is easy to miss
  -- because the check that matters is not in this function — it is in
  -- guard_profile_change. That trigger normally refuses any self-change of
  -- `status`, and it makes ONE exception (`v_redeeming`) for the update below,
  -- which sets status = 'approved' on the caller's own row. The exception exists
  -- for pending → approved, which is the whole redemption flow.
  --
  -- Nothing distinguished suspended → approved from it. So an admin could
  -- suspend an account and that account could restore itself to `approved` by
  -- redeeming any unredeemed access code — coming back with read access to one
  -- عديل's dues, receipts and statement. The role never changed, so no other
  -- guard had anything to notice.
  --
  -- `pending` must still pass: a new Google account is created viewer/pending by
  -- handle_new_user, and redeeming is exactly how an عديل turns that into access
  -- without an admin approving him as staff. Only `suspended` is refused.
  IF v_me.status = 'suspended' THEN
    RAISE EXCEPTION 'هذا الحساب موقوف، راجع إدارة الجمعية'
      USING ERRCODE = 'RUL14';
  END IF;

  -- Typed by a person off a phone screen: dashes, spaces and lower case are all
  -- expected and none of them are part of the code.
  v_norm := upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g'));

  SELECT * INTO v_row FROM public.adeel_access_codes WHERE code = v_norm;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رمز الدخول غير صحيح' USING ERRCODE = 'RUL14';
  END IF;

  -- One code, one man. A second person redeeming the same code would get his own
  -- read-only view of someone else's figures — which is a decision for the admin
  -- to make by reissuing, not something a forwarded WhatsApp message should be
  -- able to do.
  IF v_row.redeemed_at IS NOT NULL AND v_row.redeemed_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'هذا الرمز مستعمل بالفعل، اطلب رمزاً جديداً'
      USING ERRCODE = 'RUL14';
  END IF;

  -- The device this code is being spent on. The header is the fallback so a
  -- client that sets it globally does not have to pass it twice, but ONE of the
  -- two must arrive: an unlocked binding is not a weaker version of the
  -- feature, it is the absence of it, and it would be invisible afterwards.
  v_device := coalesce(nullif(btrim(coalesce(p_device_id, '')), ''),
                       public.request_device_id());
  IF v_device IS NULL THEN
    RAISE EXCEPTION 'تعذّر التعرّف على الجهاز، حدِّث التطبيق وأعد المحاولة'
      USING ERRCODE = 'RUL14';
  END IF;

  UPDATE public.profiles
     SET adeel_id  = v_row.adeel_id,
         status    = 'approved',
         role      = 'viewer',
         device_id = v_device
   WHERE id = auth.uid();

  UPDATE public.adeel_access_codes
     SET redeemed_at = now(), redeemed_by = auth.uid()
   WHERE adeel_id = v_row.adeel_id;

  SELECT adeel_code INTO v_adeel FROM public.adeels WHERE id = v_row.adeel_id;

  PERFORM public.write_audit('adeel.code.redeem',
    format('ربط حساب %s بالعديل %s', v_me.email, v_adeel.adeel_code),
    v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', v_row.adeel_id, 'adeelCode', v_adeel.adeel_code);
END $$;

-- == 5. issue_adeel_code — reissuing releases the handset ==================
CREATE OR REPLACE FUNCTION public.issue_adeel_code(p_adeel_id bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_alphabet CONSTANT text := '23456789ABCDEFGHJKMNPQRSTVWXYZ';
  v_code text := '';
  v_code_fmt text;
  v_adeel record;
  i int;
BEGIN
  PERFORM public.require_role('admin');

  SELECT id, adeel_code INTO v_adeel FROM public.adeels WHERE id = p_adeel_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL14';
  END IF;

  FOR i IN 1..12 LOOP
    -- random() is not cryptographic. It does not need to be: the row is written
    -- under a UNIQUE constraint, the code is delivered out of band, and the
    -- worst case for a predicted code is read-only sight of one man's own
    -- figures. gen_random_bytes would drag in pgcrypto for that.
    v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
  END LOOP;

  -- Grouped for reading aloud. redeem_adeel_code strips the dashes back out, so
  -- what the admin sees and what the عديل types are the same thing.
  v_code_fmt := substr(v_code,1,4) || '-' || substr(v_code,5,4) || '-' || substr(v_code,9,4);

  INSERT INTO public.adeel_access_codes (adeel_id, code, issued_by)
  VALUES (p_adeel_id, v_code, auth.uid())
  ON CONFLICT (adeel_id) DO UPDATE SET
    code = excluded.code, issued_at = now(), issued_by = excluded.issued_by,
    -- Cleared: this is a NEW code, and it has not been redeemed.
    redeemed_at = NULL, redeemed_by = NULL;

  -- ── Reissuing IS the way to release a lost phone ──────────────────────────
  -- Clearing device_id here is the only unlock the system has, and it was a
  -- deliberate choice over a second button: an عديل whose handset is stolen,
  -- wiped or replaced is otherwise locked out permanently, and the admin has to
  -- reissue his code in that situation anyway.
  --
  -- The binding itself (`adeel_id`) is deliberately LEFT ALONE. Clearing it too
  -- would drop him back to a plain approved viewer for as long as it took him
  -- to redeem again — and a viewer with no adeel_id reads the WHOLE
  -- association, because my_role() only returns NULL while an adeel_id is set.
  -- The unlock would have been a privilege escalation with a time window.
  --
  -- So he stays bound and stays locked out — my_adeel_id() refuses a NULL
  -- device_id — until the phone holding the new code opens the app and
  -- api_touch_login() claims it.
  UPDATE public.profiles
     SET device_id = NULL
   WHERE adeel_id = p_adeel_id
     AND device_id IS NOT NULL;

  PERFORM public.write_audit('adeel.code.issue',
    format('إصدار رمز دخول للعديل %s', v_adeel.adeel_code), v_adeel.adeel_code);

  RETURN jsonb_build_object(
    'adeelId', p_adeel_id, 'adeelCode', v_adeel.adeel_code, 'code', v_code_fmt);
END $$;

-- == 6. api_me and api_touch_login =========================================
-- api_me gains `deviceLocked`, which EXPLAINS the empty portal without being
-- what enforces it. api_touch_login claims an unclaimed device — the other half
-- of the release, and what keeps already-bound عدايل working after this patch.
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

-- == 7. api_adeel_statement — the البيان column says WHAT, not which ref ====
-- A payment's particulars read `coalesce(nullif(p.reference,''), p.method)`, so
-- a transfer that carried a bank reference put a bare number in the statement —
-- "34871" beside 250.00, which tells a member nothing and reads like a second
-- amount. It now says the method: تحويل مصرفي or نقداً.
--
-- The reference is not lost. It stays on the payment row and on the collections
-- screen, where the treasurer reconciling against a bank statement is the
-- person who actually needs it.
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

-- == 8. THE WALLET ==========================================================
-- register_payment no longer caps the amount at what is owed, and no longer
-- refuses a member who owes nothing. The surplus becomes CREDIT.
--
-- There is no wallet column, and that is the design rather than an economy:
-- the credit is the part of a payment the FIFO loop could not allocate —
-- Σ payments − Σ allocations — so it is a view over rows that already exist and
-- cannot drift from the money. Spending it means WRITING the missing
-- allocation, which is also what puts a prepaid month into the member's
-- statement beside the receipt that settled it, months after the fact.
--
-- settle_from_credit() is that spend, and generate_period() calls it the
-- instant it raises a receivable: a member who paid a year ahead must never see
-- the new month appear as a debt he already covered, not even between two
-- statements.
--
-- ⚠ WHAT THIS RELAXES. Rule 7's cap is gone, so a treasurer who means 500 and
--   types 5000 is no longer stopped by the database. The app states the surplus
--   back to him while the keyboard is still open, and the audit entry names it
--   — "منها 4500 رصيد مقدم" — so it is visible afterwards rather than only in
--   the arithmetic. What survives is that the amount must be positive and that
--   every unit is either allocated or counted as credit.
CREATE OR REPLACE FUNCTION public.settle_from_credit(p_adeel_id bigint)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_applied numeric(12,2) := 0;
  v_take    numeric(12,2);
  v_left    numeric(12,2);
  rcv       record;
  pay       record;
BEGIN
  FOR rcv IN
    SELECT r.id, r.period, r.balance
      FROM public.receivables r
     WHERE r.adeel_id = p_adeel_id
       AND r.status <> 'ملغي'
       AND r.balance > 0
     ORDER BY r.period ASC, r.id ASC
       FOR UPDATE
  LOOP
    v_left := rcv.balance;

    FOR pay IN
      SELECT p.id,
             p.amount - coalesce(
               (SELECT sum(a.amount) FROM public.payment_allocations a
                 WHERE a.payment_id = p.id), 0) AS spare
        FROM public.payments p
       WHERE p.adeel_id = p_adeel_id
         AND p.status <> 'ملغي'
       ORDER BY p.paid_at ASC, p.id ASC
         FOR UPDATE
    LOOP
      EXIT WHEN v_left <= 0;
      CONTINUE WHEN pay.spare <= 0;

      v_take := least(v_left, pay.spare);

      -- sequence_no continues this payment's own numbering rather than
      -- restarting: uq_alloc_pay_recv already stops the same payment paying the
      -- same receivable twice, and a receipt whose allocations read 1,2,1 would
      -- be unreadable on a statement.
      INSERT INTO public.payment_allocations
        (payment_id, receivable_id, period, amount, sequence_no)
      VALUES (
        pay.id, rcv.id, rcv.period, v_take,
        coalesce((SELECT max(a.sequence_no) FROM public.payment_allocations a
                   WHERE a.payment_id = pay.id), 0) + 1);

      UPDATE public.receivables SET paid = paid + v_take WHERE id = rcv.id;

      v_left    := v_left - v_take;
      v_applied := v_applied + v_take;
    END LOOP;
  END LOOP;

  RETURN v_applied;
END $$;

CREATE OR REPLACE FUNCTION public.register_payment(
  p_adeel_id  bigint,
  p_amount    numeric,
  p_method    pay_method,
  p_reference text DEFAULT NULL,
  p_receiver  text DEFAULT NULL,
  p_notes     text DEFAULT NULL,
  p_bank_name         text DEFAULT NULL,
  p_bank_account_name text DEFAULT NULL,
  p_bank_account_no   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  -- Unconstrained numeric, NOT numeric(12,2). Individual amounts are bounded by
  -- the column type, but their SUM is not: an عديل with enough open periods
  -- overflows a 12-digit accumulator and the call dies with 22003 instead of
  -- reporting the balance. Found by the probe suite, which pushed a large total
  -- through and got "numeric field overflow" where it expected a rule violation.
  v_outstanding numeric;
  v_remaining   numeric;
  v_payment_id  bigint;
  v_receipt     text;
  v_take        numeric(12,2);
  v_bank        text;
  v_acct_no     text;
  v_acct_name   text;
  v_seq         smallint := 0;
  r             record;
  v_allocs      jsonb := '[]'::jsonb;
BEGIN
  PERFORM public.require_role('treasurer');

  -- Round to minor units up front. A client can post 10.005; accepting it would
  -- put a third decimal into an allocation and the sums would stop tying out.
  p_amount := round(p_amount, 2);

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Rule 7: payment amount must be greater than zero'
      USING ERRCODE = 'RUL07';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.adeels WHERE id = p_adeel_id) THEN
    RAISE EXCEPTION 'ADEEL_NOT_FOUND' USING ERRCODE = 'RUL07';
  END IF;

  -- Lock every open receivable for this عديل, oldest first. Once locked, no
  -- other transaction can move them for the rest of this one, so the total below
  -- and the loop further down both read the same reality — which is the whole
  -- point. ORDER BY also fixes a consistent lock acquisition order.
  PERFORM 1
    FROM public.receivables r2
   WHERE r2.adeel_id = p_adeel_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0
   ORDER BY r2.period ASC, r2.id ASC
     FOR UPDATE;

  SELECT coalesce(sum(r2.balance), 0) INTO v_outstanding
    FROM public.receivables r2
   WHERE r2.adeel_id = p_adeel_id
     AND r2.status <> 'ملغي'
     AND r2.balance > 0;

  -- ── RULE 7 NO LONGER CAPS THE AMOUNT, and this is a deliberate change ─────
  -- It used to refuse two things: paying an عديل who owed nothing, and paying
  -- more than he owed. Both are now allowed, and what they produce is CREDIT.
  --
  -- The association asked for a wallet: a member may hand over a year at once,
  -- or round his payment up, and the surplus should sit against his name until
  -- the months it belongs to are raised. Refusing the money meant a treasurer
  -- holding cash he could not enter, and the only workarounds were worse than
  -- the feature — a fictitious receivable, or a note in a drawer.
  --
  -- There is no new column and no second source of truth. A payment's surplus
  -- is simply the part of it the FIFO loop below could not allocate:
  --
  --     credit  =  Σ payments.amount  −  Σ payment_allocations.amount
  --
  -- so the wallet is a VIEW over rows that already exist, and it cannot drift
  -- from the money. generate_period() draws it down by writing the allocations
  -- that were missing, which is also what makes a prepaid month appear in the
  -- statement beside the charge it settled.
  --
  -- What survives from rule 7: the amount must be greater than zero, and every
  -- currency unit must end up either allocated or explicitly counted as credit
  -- — checked below, because "unallocated" must be a decision, never a leak.

  -- Kept ONLY for a transfer. A cash collection has no sending account, so
  -- letting the three columns carry anything for it would put data on the row
  -- that cannot be true — and the treasury screen would start showing bank
  -- details beside نقداً. Blanks are normalised to NULL so "not given" and
  -- "given as an empty box" are the same thing on the row.
  IF p_method = 'تحويل مصرفي' THEN
    v_bank      := nullif(btrim(coalesce(p_bank_name, '')), '');
    v_acct_name := nullif(btrim(coalesce(p_bank_account_name, '')), '');
    v_acct_no   := nullif(btrim(coalesce(p_bank_account_no, '')), '');
  END IF;

  INSERT INTO public.payments (adeel_id, amount, method, reference, receiver,
                               notes, created_by,
                               bank_name, bank_account_no, bank_account_name)
  VALUES (p_adeel_id, p_amount, p_method, p_reference, p_receiver, p_notes,
          auth.uid(), v_bank, v_acct_no, v_acct_name)
  RETURNING id, receipt_no INTO v_payment_id, v_receipt;

  v_remaining := p_amount;

  FOR r IN SELECT r2.id, r2.period, r2.balance
             FROM public.receivables r2
            WHERE r2.adeel_id = p_adeel_id
              AND r2.status <> 'ملغي'
              AND r2.balance > 0
            ORDER BY r2.period ASC, r2.id ASC
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := least(v_remaining, r.balance);
    v_seq  := v_seq + 1;

    INSERT INTO public.payment_allocations
      (payment_id, receivable_id, period, amount, sequence_no)
    VALUES (v_payment_id, r.id, r.period, v_take, v_seq);

    -- ck_recv_paid (paid <= total) is the storage-engine backstop: if the maths
    -- above were ever wrong, this UPDATE fails and the whole call rolls back.
    UPDATE public.receivables SET paid = paid + v_take WHERE id = r.id;

    v_remaining := v_remaining - v_take;
    v_allocs := v_allocs || jsonb_build_object(
      'receivableId', r.id, 'period', r.period,
      'amount', v_take::text, 'sequenceNo', v_seq);
  END LOOP;

  -- What the FIFO loop could not place is the wallet. It used to be an
  -- INVARIANT failure — with the amount capped at the outstanding balance,
  -- anything left over meant the arithmetic had gone wrong — and it is now the
  -- feature. The sign check stays: a NEGATIVE remainder would mean the loop
  -- allocated more than was paid, which is still a bug and still unpayable.
  IF v_remaining < 0 THEN
    RAISE EXCEPTION 'INVARIANT: over-allocated by %', -v_remaining
      USING ERRCODE = 'RUL07';
  END IF;

  -- Rule 8. uq_cash_payment makes a duplicate structurally impossible.
  INSERT INTO public.cash_movements
    (payment_id, adeel_id, amount, method, occurred_at)
  SELECT id, adeel_id, amount, method, paid_at
    FROM public.payments WHERE id = v_payment_id;

  -- The surplus is named in the trail. "تحصيل 500" against a man who owed 200
  -- is not the same event as "تحصيل 500" against a man who owed 500, and the
  -- entry has to say which — rule 12 exists so a figure can be reconstructed
  -- from the trail, and a wallet that appears without explanation cannot be.
  PERFORM public.write_audit('payment.register',
    CASE WHEN v_remaining > 0
         THEN format('تحصيل %s من العديل %s، منها %s رصيد مقدم',
                     p_amount::text, p_adeel_id, v_remaining::text)
         ELSE format('تحصيل %s من العديل %s', p_amount::text, p_adeel_id)
    END,
    v_receipt);

  RETURN jsonb_build_object(
    'paymentId', v_payment_id,
    'receiptNo', v_receipt,
    'adeelId',   p_adeel_id,
    'amount',    p_amount::text,
    'method',    p_method,
    -- What went to the wallet rather than to a month. The app states it back
    -- on the confirmation, so a treasurer who typed 5000 for 500 sees it in
    -- the same breath as the receipt number.
    'credit',    v_remaining::text,
    'allocations', v_allocs);
END $$;

CREATE OR REPLACE FUNCTION public.generate_period(p_period char(7))
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  s           record;
  a           record;
  v_end       date;
  v_recv_id   bigint;
  v_created   int := 0;
  v_skipped   int := 0;
  -- How much prepaid credit this close consumed. Reported so a treasurer can
  -- see that a month billed 800 and settled 300 of it from wallets on the
  -- spot, rather than wondering why the total debt moved less than he expected.
  v_applied   numeric(12,2) := 0;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_period !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
    RAISE EXCEPTION 'BAD_PERIOD: %', p_period USING ERRCODE = 'RUL04';
  END IF;

  SELECT * INTO s FROM public.association_settings WHERE id = 1;
  v_end := (to_date(p_period || '-01', 'YYYY-MM-DD')
            + interval '1 month - 1 day')::date;

  -- ── Rule 15c: only a month inside the association's own range ─────────────
  -- Before system_start the books did not exist; the current month and anything
  -- after it has not ended, and closing a month that is still running would bill
  -- for time nobody has lived through. Both ends were previously unguarded — the
  -- picker simply did not offer them, which protects the button and not the RPC,
  -- and the RPC is what a hostile client calls.
  IF p_period < to_char(s.system_start, 'YYYY-MM') THEN
    RAISE EXCEPTION 'PERIOD_BEFORE_SYSTEM_START: %', p_period
      USING ERRCODE = 'RUL15';
  END IF;
  IF p_period >= to_char(current_date, 'YYYY-MM') THEN
    RAISE EXCEPTION 'PERIOD_NOT_ENDED: %', p_period USING ERRCODE = 'RUL15';
  END IF;

  -- ── Rule 15a: a month is closed ONCE ──────────────────────────────────────
  -- Rule 4 already made a SECOND receivable for the same (عديل, period)
  -- impossible, so re-running was harmless — it simply created nothing and
  -- reported "0 created". Harmless is not the same as meaningful: a treasurer
  -- reading "0 created" cannot tell "already done" from "nothing to do", and the
  -- audit trail grew an entry for a close that closed nothing. Refusing says
  -- which it was.
  IF EXISTS (SELECT 1 FROM public.closed_periods WHERE period = p_period) THEN
    RAISE EXCEPTION 'PERIOD_ALREADY_CLOSED: %', p_period USING ERRCODE = 'RUL15';
  END IF;

  -- ── Rule 15b: months close IN ORDER, oldest first ─────────────────────────
  -- Closing August while July was never closed leaves a hole that nothing later
  -- reveals: the register looks complete, every receipt reconciles, and the
  -- association is simply never paid for July. The gap is invisible precisely
  -- because a missing charge produces no row to notice.
  --
  -- Checked against closed_periods rather than against receivables, and that
  -- distinction is the whole reason the table exists: a month in which nobody
  -- was نشط produces zero receivables, so an "are there receivables?" test would
  -- read it as never closed and block every month after it forever.
  --
  -- Nothing before system_start counts. The association's books begin there.
  IF EXISTS (
    SELECT 1
      FROM generate_series(
             date_trunc('month', s.system_start),
             date_trunc('month', to_date(p_period || '-01', 'YYYY-MM-DD'))
               - interval '1 month',
             interval '1 month') d
     WHERE NOT EXISTS (SELECT 1 FROM public.closed_periods c
                        WHERE c.period = to_char(d, 'YYYY-MM'))
  ) THEN
    RAISE EXCEPTION 'EARLIER_PERIOD_OPEN: % cannot be closed while an earlier '
                    'month is still open', p_period USING ERRCODE = 'RUL15';
  END IF;

  -- Rule 3: nothing to charge means no rows at all, not zero rows. A fee of zero
  -- is a valid configuration (the association pausing collection), and it must
  -- produce an empty period rather than a register full of 0.00 charges that
  -- ck_recv_total would refuse anyway.
  --
  -- It still COUNTS AS CLOSED. The month was dealt with; leaving it open would
  -- block every month after it under 15b, which is exactly the trap that made
  -- closed_periods a table rather than an inference.
  IF s.member_fee <= 0 THEN
    SELECT count(*) INTO v_skipped FROM public.adeels WHERE status = 'نشط';
    INSERT INTO public.closed_periods (period, closed_by, created)
    VALUES (p_period, auth.uid(), 0);
    PERFORM public.write_audit('receivables.generate',
      format('إنشاء استحقاقات %s: لا رسم مقرر', p_period), p_period);
    RETURN jsonb_build_object('period', p_period, 'created', 0,
                              'skipped', v_skipped);
  END IF;

  FOR a IN SELECT id, full_name, status
             FROM public.adeels ORDER BY id LOOP
    -- Status overrides everything: a موقوف or متوفى عديل is not billable.
    IF a.status <> 'نشط' THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Rule 4 as idempotency: re-running the same period skips instead of
    -- raising a duplicate. The partial index is what makes this safe under
    -- concurrency, so two admins pressing the button together cannot double-bill.
    INSERT INTO public.receivables (
      adeel_id, period, period_end, adeel_name, total,
      created_by)
    VALUES (
      a.id, p_period, v_end, a.full_name, s.member_fee,
      auth.uid())
    ON CONFLICT (adeel_id, period) WHERE status <> 'ملغي' DO NOTHING
    RETURNING id INTO v_recv_id;

    IF v_recv_id IS NULL THEN
      v_skipped := v_skipped + 1;
    ELSE
      v_created := v_created + 1;
      -- ── The wallet pays the month it was paid in advance for ──────────────
      -- Immediately, and inside the same transaction as the charge. A member
      -- who handed over a year must never see the new month appear as a debt
      -- he already settled — not even between two statements — and doing it
      -- here means the charge and its settlement are one event or neither.
      --
      -- Called per عديل rather than once at the end so that the credit walks
      -- his OWN receivables in period order. A single sweep would still be
      -- correct arithmetically and would scan the whole register for the
      -- overwhelming majority who have no credit at all.
      v_applied := v_applied + public.settle_from_credit(a.id);
    END IF;
    v_recv_id := NULL;
  END LOOP;

  -- The month is now closed, whatever it produced. Written INSIDE the same
  -- transaction as the receivables it raised, so a failure anywhere above leaves
  -- neither the charges nor the marker — the alternative is a month recorded as
  -- closed with nothing billed in it.
  INSERT INTO public.closed_periods (period, closed_by, created)
  VALUES (p_period, auth.uid(), v_created);

  PERFORM public.write_audit('receivables.generate',
    CASE WHEN v_applied > 0
         THEN format('إنشاء استحقاقات %s: %s سجل، وسُدِّد %s من أرصدة مقدمة',
                     p_period, v_created, v_applied::text)
         ELSE format('إنشاء استحقاقات %s: %s سجل', p_period, v_created)
    END, p_period);

  RETURN jsonb_build_object('period', p_period, 'created', v_created,
                            'skipped', v_skipped,
                            'creditApplied', v_applied::text);
END $$;

-- v_adeels gains the wallet and the one signed figure the portal leads with.
-- CREATE OR REPLACE VIEW can only APPEND columns — inserting them mid-list
-- makes Postgres try to rename an existing column and refuse with 42P16 — so
-- both sit at the very end, and anything added later goes below them.
CREATE OR REPLACE VIEW public.v_adeels WITH (security_invoker = on) AS
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

-- api_adeel_detail passes them through rather than recomputing, so the member's
-- screen and the register cannot disagree about what he stands at.
CREATE OR REPLACE FUNCTION public.api_adeel_detail(p_adeel_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'adeel', public.adeel_json(p_adeel_id),
    'kpis', jsonb_build_object(
      'monthlyExpected', v."monthlyExpected",
      'issued', v."issued",
      'debt', v."debt",
      'paid', v."paid",
      -- The wallet, and the one signed figure the portal leads with. Both come
      -- off v_adeels rather than being recomputed here, so the member's screen
      -- and the register cannot disagree about what he stands at.
      'credit', v."credit",
      'netBalance', v."netBalance",
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

-- == 9. MONEY OUT — the table the treasury now depends on =================
-- Until now the association could only take money IN: cash_kind carried the
-- single value 'تحصيل'. This is the other direction, in the shape the
-- association chose:
--
--   • recorded DIRECTLY, like a collection — no approval queue, no pending
--     state. A mistake is corrected by an explicit reversal that leaves both
--     rows standing, exactly as a mistaken receipt is.
--   • ADMIN only. Taking money in belongs to the treasurer; paying it out was
--     put a rung above even the finance manager.
--   • a FIXED list of headings, so "how much went on each" is answerable.
--   • a payee who may be an عديل from the register OR a free name, because the
--     association pays landlords and hospitals as well as its own members.
--
-- ⚠ THE RULE THAT MAKES IT SAFE: the association cannot pay out money it does
--   not hold. register_disbursement refuses an overdraft, serialising on the
--   settings row so two admins cannot both pass the check and leave the fund
--   short by the smaller of the two.
--
-- ⚠ AID TO A MEMBER IS NOT A PAYMENT. A voucher never touches receivables,
--   payments or a member's wallet, and never appears in his statement. The
--   register link exists so "how much aid went to this man" can be answered;
--   treating it as a payment would let the association's charity cancel its
--   own dues.
--
-- A SEPARATE TABLE, not a row in cash_movements. That table is the mirror of an
-- approved payment — rule 8 gives it one row per payment, uq_cash_payment makes
-- a duplicate impossible, its adeel_id is NOT NULL and the عديل portal reads it
-- as "my receipts". Forcing an outflow in would mean a nullable payment_id, a
-- widened unique constraint, a sign on every existing SUM and an RLS policy
-- that has to start distinguishing directions — on the one table the working
-- collection path depends on. So the treasury became arithmetic over two
-- tables, and nothing about collection had to change.
--
-- CREATE TYPE has no IF NOT EXISTS and CREATE TABLE's is not enough on its own,
-- so both are wrapped in a guard that makes a second run a no-op.
-- ── THE TWO KINDS ───────────────────────────────────────────────────────────
-- The association spends on exactly two things and asked for them separated at
-- the top of the form: money to a NAMED man on the register, or money on an
-- OCCASION for everybody. Everything else on the voucher follows — a member
-- voucher carries no heading (the man IS the heading) and a collective one
-- carries no payee at all, because nobody receives فطور رمضان the way a member
-- receives aid.
DO $mkkind$
BEGIN
  CREATE TYPE disbursement_kind AS ENUM ('لمشترك','جماعي');
EXCEPTION WHEN duplicate_object THEN NULL;
END $mkkind$;

-- The five occasions, named by the association. No 'أخرى': a list this narrow
-- describes things it actually holds, and an occasion fitting none of them is a
-- reason to name a sixth rather than to file it under a heading that says
-- nothing.
DO $mkenum$
BEGIN
  CREATE TYPE expense_category AS ENUM (
    'فرح',
    'عزاء',
    'فطور رمضان',
    'مناسبة اجتماعية',
    'مولود',
    'حالات طارئة'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $mkenum$;

CREATE TABLE IF NOT EXISTS public.disbursements (
  id            bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  voucher_no    text          GENERATED ALWAYS AS ('EXP-' || lpad(id::text, 6, '0')) STORED,
  amount        numeric(12,2) NOT NULL,
  kind          disbursement_kind NOT NULL,
  -- Both halves nullable on the column and made exclusive by ck_disb_shape
  -- below: no per-column NOT NULL can say "this one exactly when that one is
  -- not".
  payee_adeel_id bigint       REFERENCES public.adeels(id) ON DELETE RESTRICT,
  payee_name    text,
  -- BOTH kinds carry a وجه. The payee says WHO was paid; this says WHAT FOR,
  -- and a register of names cannot answer the second — a man may be given
  -- something for a wedding one month and a bereavement the next.
  category      expense_category NOT NULL,
  method        pay_method    NOT NULL,
  reference     text,
  bank_name         text,
  bank_account_no   text,
  bank_account_name text,
  handed_by     text,
  note          text,
  status        pay_status    NOT NULL DEFAULT 'معتمد',
  spent_at      timestamptz   NOT NULL DEFAULT now(),
  created_by    uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancelled_at  timestamptz,
  cancelled_by  uuid          REFERENCES public.profiles(id) ON DELETE SET NULL,
  cancel_reason text,

  CONSTRAINT ck_disb_amount CHECK (amount > 0),

  -- THE TWO SHAPES, and nothing in between. Two rules at once, neither of which
  -- a per-column constraint can state:
  --   1. لمشترك names a man; جماعي names nobody.
  --   2. مولود is a family's and only ever goes to a member; فطور رمضان is one
  --      table for everybody and is never one man's.
  -- Written as exclusions, so a seventh heading BOTH kinds may use needs no edit
  -- here. Without it a birth could be filed as a collective expense, or an iftar
  -- against one man, and either would pass every other check and surface on a
  -- screen months later.
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

  CONSTRAINT ck_disb_cancel CHECK (
    status <> 'ملغي' OR (cancelled_at IS NOT NULL
                     AND btrim(coalesce(cancel_reason, '')) <> ''))
);

CREATE INDEX IF NOT EXISTS ix_disb_spent    ON public.disbursements (spent_at DESC);
CREATE INDEX IF NOT EXISTS ix_disb_category ON public.disbursements (category);
CREATE INDEX IF NOT EXISTS ix_disb_payee    ON public.disbursements (payee_adeel_id);

-- Rule 9 applies here too: reversed, never removed. CREATE OR REPLACE TRIGGER
-- rather than a DROP, so a re-run neither duplicates it nor leaves a window in
-- which the guard is off.
CREATE OR REPLACE TRIGGER trg_disb_no_delete BEFORE DELETE ON public.disbursements
  FOR EACH ROW EXECUTE FUNCTION public.refuse_delete();

ALTER TABLE public.disbursements ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.disbursements TO authenticated;

-- STAFF ONLY, and deliberately not extended to an عديل. He already sees the
-- association's TOTAL spend through api_association_finance(); a voucher row
-- says that a NAMED person received إعانة اجتماعية, which in a family
-- association is the most private fact the system holds and belongs to the
-- recipient rather than to the membership.
DO $disbpol$
BEGIN
  CREATE POLICY read_disbursements ON public.disbursements
    FOR SELECT TO authenticated USING (public.has_role('viewer'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $disbpol$;

-- == 10. The treasury screen ==============================================
-- v_cash_summary gains what is still OWED. It is the odd column here — every
-- other figure in that view aggregates cash_movements and this one reaches into
-- receivables — and it is there because the question a treasurer asks of the
-- screen is "where does the association stand", and half that answer is money
-- that has not arrived.
--
-- It replaced "تحصيل السنة", which on an association in its first year was the
-- same number as "إجمالي المحصل": two tiles side by side showing one figure,
-- with nothing to tell a reader they were not disagreeing.
--
-- APPENDED at the end of the select list, like every other column added to a
-- view in this schema — CREATE OR REPLACE VIEW allows nothing else.
CREATE OR REPLACE VIEW public.v_cash_summary WITH (security_invoker = on) AS
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
    AS "year",
  -- ── What is still OWED, on the treasury screen ────────────────────────────
  -- The odd one out: every other figure here aggregates cash_movements, and
  -- this one reaches into receivables. It is here because the question a
  -- treasurer asks of this screen is "where does the association stand", and
  -- half that answer is money that has not arrived.
  --
  -- It replaced "تحصيل السنة", which on an association in its first year was
  -- the same number as "إجمالي المحصل" — two tiles, one figure, and no way to
  -- tell they were not disagreeing with each other.
  --
  -- Cancelled receivables excluded, matching every other debt figure in the
  -- schema. APPENDED at the end because CREATE OR REPLACE VIEW allows nothing
  -- else; anything added later goes below it.
  coalesce((SELECT sum(r.balance) FROM public.receivables r
             WHERE r.status <> 'ملغي'), 0)::numeric(12,2)::text
    AS "outstanding",
  -- ── Money OUT, and what the association actually still holds ──────────────
  -- `total` above is everything ever COLLECTED and keeps that meaning. It was
  -- also what the screen called "رصيد الجمعية", which was true only while money
  -- could not leave — the moment disbursement exists, collected-to-date and
  -- held-today are different numbers and calling the first one "the balance"
  -- makes the screen lie by exactly what has been spent.
  --
  -- Two tables rather than one signed ledger: see the note on the disbursements
  -- table. Nothing about the collection path had to change to make this work.
  coalesce((SELECT sum(x.amount) FROM public.disbursements x
             WHERE x.status <> 'ملغي'), 0)::numeric(12,2)::text
    AS "disbursed",
  (coalesce(sum(amount), 0)
   - coalesce((SELECT sum(x.amount) FROM public.disbursements x
                WHERE x.status <> 'ملغي'), 0))::numeric(12,2)::text
    AS "balance"
FROM public.cash_movements
WHERE status <> 'ملغي';

-- == 11. The treasury, for a MEMBER to read ================================
-- "شفافية مطلقة": the association wanted a member able to see where the
-- collective money stands.
--
-- ⚠ IT CANNOT BE v_cash_summary, AND THE REASON IS A TRAP RATHER THAN A LIMIT.
--   That view is SECURITY INVOKER, and an عديل's RLS on cash_movements is
--   `adeel_id = my_adeel_id()`. Pointing the portal at it would have shown him
--   HIS OWN four figures under headings that say "the association's" — not a
--   leak, something worse: a wrong answer with nothing on screen to doubt.
--
-- So: SECURITY DEFINER, and AGGREGATES ONLY. No name, no receipt, no row
-- belonging to anybody, no argument to abuse, and no write. What the
-- association holds, how it arrived, and what is still owed to it in total —
-- which says nothing about any particular neighbour.
--
-- The gate is approved staff OR an عديل bound to a row, and `my_adeel_id()`
-- carries the one-device rule, so the wrong handset is refused here by the same
-- clause that empties his portal.
CREATE OR REPLACE FUNCTION public.api_association_finance() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_out jsonb;
BEGIN
  IF public.my_role() IS NULL AND public.my_adeel_id() IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  SELECT jsonb_build_object(
    'collected', coalesce(sum(c.amount), 0)::numeric(12,2)::text,
    'cash',      coalesce(sum(c.amount) FILTER (WHERE c.method = 'نقداً'),
                          0)::numeric(12,2)::text,
    'transfer',  coalesce(sum(c.amount) FILTER (WHERE c.method = 'تحويل مصرفي'),
                          0)::numeric(12,2)::text)
    INTO v_out
    FROM public.cash_movements c
   WHERE c.status <> 'ملغي';

  RETURN v_out
    || jsonb_build_object(
         -- ── Spent, and what is left ─────────────────────────────────────────
         -- The member's transparency is not honest without the outgoing side:
         -- showing him only what came in, under a heading that says "the
         -- association's balance", would overstate the fund by everything it
         -- has ever paid out. The TOTAL spent is his to see; who received it is
         -- not — see the note on read_disbursements.
         'disbursed', (SELECT coalesce(sum(x.amount), 0)::numeric(12,2)::text
                         FROM public.disbursements x WHERE x.status <> 'ملغي'),
         'balance', (
           (SELECT coalesce(sum(c2.amount), 0) FROM public.cash_movements c2
             WHERE c2.status <> 'ملغي')
           - (SELECT coalesce(sum(x.amount), 0) FROM public.disbursements x
               WHERE x.status <> 'ملغي'))::numeric(12,2)::text,
         'issued', (SELECT coalesce(sum(r.total), 0)::numeric(12,2)::text
                      FROM public.receivables r WHERE r.status <> 'ملغي'),
         'outstanding', (SELECT coalesce(sum(r.balance), 0)::numeric(12,2)::text
                           FROM public.receivables r WHERE r.status <> 'ملغي'),
         -- Counts, not money, and deliberately only the two a member can already
         -- infer from the register he is part of. No breakdown by person.
         'members', (SELECT count(*) FROM public.adeels),
         'activeMembers', (SELECT count(*) FROM public.adeels
                            WHERE status = 'نشط'));
END $$;
CREATE OR REPLACE FUNCTION public.register_disbursement(
  p_amount            numeric,
  p_kind              disbursement_kind,
  p_method            pay_method,
  p_payee_adeel_id    bigint DEFAULT NULL,
  p_category          expense_category DEFAULT NULL,
  p_reference         text   DEFAULT NULL,
  p_bank_name         text   DEFAULT NULL,
  p_bank_account_name text   DEFAULT NULL,
  p_bank_account_no   text   DEFAULT NULL,
  p_handed_by         text   DEFAULT NULL,
  p_note              text   DEFAULT NULL,
  p_spent_at          date   DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  -- Unconstrained numeric for the same reason register_payment's is: the
  -- individual amounts are bounded by their column, their SUM is not, and an
  -- overflowing accumulator would report 22003 instead of a rule violation.
  v_collected numeric;
  v_spent     numeric;
  v_available numeric;
  v_payee     text;
  v_bank      text;
  v_acct_no   text;
  v_acct_name text;
  v_reference text;
  v_id        bigint;
  v_voucher   text;
BEGIN
  PERFORM public.require_role('admin');

  p_amount := round(p_amount, 2);
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'قيمة الصرف يجب أن تكون أكبر من صفر' USING ERRCODE = 'RUL17';
  END IF;

  -- The treasury mutex. See the note above.
  PERFORM 1 FROM public.association_settings WHERE id = 1 FOR UPDATE;

  SELECT coalesce(sum(amount), 0) INTO v_collected
    FROM public.cash_movements WHERE status <> 'ملغي';
  SELECT coalesce(sum(amount), 0) INTO v_spent
    FROM public.disbursements  WHERE status <> 'ملغي';
  v_available := v_collected - v_spent;

  IF p_amount > v_available THEN
    RAISE EXCEPTION 'الصرف % يتجاوز رصيد الصندوق %',
      p_amount::text, v_available::text USING ERRCODE = 'RUL17';
  END IF;

  -- ── The two shapes, refused here as well as CHECKed on the row ─────────────
  -- ck_disb_shape is the guarantee; this is the message. A constraint violation
  -- arrives as 23514 with a constraint name, which is true and unreadable — the
  -- admin needs to be told he picked a kind and then filled in the other one.
  -- Both kinds carry a وجه: WHO was paid and WHAT FOR are different questions,
  -- and a register of names cannot answer the second.
  IF p_category IS NULL THEN
    RAISE EXCEPTION 'اختر وجه الصرف' USING ERRCODE = 'RUL17';
  END IF;

  IF p_kind = 'لمشترك' THEN
    IF p_payee_adeel_id IS NULL THEN
      RAISE EXCEPTION 'اختر المشترك المستفيد' USING ERRCODE = 'RUL17';
    END IF;
    IF p_category = 'فطور رمضان' THEN
      RAISE EXCEPTION '«فطور رمضان» وجه صرف جماعي — لا يُصرف لمشترك بعينه'
        USING ERRCODE = 'RUL17';
    END IF;
    -- The name comes from HIS ROW, never from the client, so a voucher cannot
    -- name one man while pointing at another.
    SELECT full_name INTO v_payee FROM public.adeels WHERE id = p_payee_adeel_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'المستفيد المختار ليس في سجل العدايل' USING ERRCODE = 'RUL17';
    END IF;
  ELSE
    IF p_payee_adeel_id IS NOT NULL THEN
      RAISE EXCEPTION 'الصرف الجماعي لا يُنسب إلى مشترك' USING ERRCODE = 'RUL17';
    END IF;
    IF p_category = 'مولود' THEN
      RAISE EXCEPTION '«مولود» وجه صرف لمشترك — لا يكون جماعياً'
        USING ERRCODE = 'RUL17';
    END IF;
    -- No payee at all, by the association's own decision: nobody receives
    -- فطور رمضان the way a member receives aid, and a name invented to fill the
    -- column would be a fact the books assert without knowing it.
    v_payee := NULL;
  END IF;

  -- Kept only for a transfer: a cash payout has no receiving account, and
  -- letting the columns carry anything for it would put bank details beside
  -- نقداً on the voucher.
  --
  -- `reference` goes with them, and that is the difference from a COLLECTION.
  -- There it is a receipt-book number a treasurer writes for cash as readily as
  -- for a transfer; here the field is «رقم مرجع التحويل», a number the BANK
  -- issues, so on a cash payout there is nothing it could truthfully hold. The
  -- screen hides it for cash — this is what makes that a rule rather than a
  -- layout choice.
  IF p_method = 'تحويل مصرفي' THEN
    v_bank      := nullif(btrim(coalesce(p_bank_name, '')), '');
    v_acct_name := nullif(btrim(coalesce(p_bank_account_name, '')), '');
    v_acct_no   := nullif(btrim(coalesce(p_bank_account_no, '')), '');
    v_reference := nullif(btrim(coalesce(p_reference, '')), '');
  END IF;

  INSERT INTO public.disbursements (
    amount, kind, category, payee_adeel_id, payee_name, method, reference,
    bank_name, bank_account_no, bank_account_name, handed_by, note,
    spent_at, created_by)
  VALUES (
    p_amount, p_kind, p_category, p_payee_adeel_id, v_payee, p_method,
    v_reference,
    v_bank, v_acct_no, v_acct_name,
    nullif(btrim(coalesce(p_handed_by, '')), ''),
    nullif(btrim(coalesce(p_note, '')), ''),
    -- A back-dated voucher keeps the time of day it was entered, so two
    -- vouchers on the same past date still order deterministically.
    coalesce(p_spent_at + (now()::time), now()),
    auth.uid())
  RETURNING id, voucher_no INTO v_id, v_voucher;

  PERFORM public.write_audit('disbursement.register',
    format('صرف %s — %s', p_amount::text,
           coalesce('إلى ' || v_payee, p_category::text)),
    v_voucher);

  RETURN jsonb_build_object(
    'id', v_id, 'voucherNo', v_voucher,
    'amount', p_amount::text, 'kind', p_kind::text,
    'category', p_category::text,
    'payeeName', v_payee,
    -- What the treasury stands at AFTER this voucher. The screen states it back
    -- so an admin who has just emptied the fund learns it now rather than on
    -- the next attempt.
    'balanceAfter', (v_available - p_amount)::text);
END $$;

CREATE OR REPLACE FUNCTION public.cancel_disbursement(
  p_id     bigint,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE v_row record;
BEGIN
  PERFORM public.require_role('admin');

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED' USING ERRCODE = 'RUL17';
  END IF;

  SELECT * INTO v_row FROM public.disbursements WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DISBURSEMENT_NOT_FOUND' USING ERRCODE = 'RUL17';
  END IF;
  IF v_row.status = 'ملغي' THEN
    RAISE EXCEPTION 'DISBURSEMENT_ALREADY_CANCELLED' USING ERRCODE = 'RUL17';
  END IF;

  UPDATE public.disbursements
     SET status = 'ملغي', cancelled_at = now(),
         cancelled_by = auth.uid(), cancel_reason = p_reason
   WHERE id = p_id;

  PERFORM public.write_audit('disbursement.cancel',
    format('إلغاء %s: %s', v_row.voucher_no, p_reason), v_row.voucher_no);

  RETURN jsonb_build_object(
    'id', p_id, 'voucherNo', v_row.voucher_no,
    'status', 'ملغي', 'amount', v_row.amount::text, 'reason', p_reason);
END $$;

-- ── AND THE SAME RULE FROM THE OTHER SIDE ───────────────────────────────────
-- register_disbursement refuses to pay out money the association does not hold.
-- On its own that is only half a guarantee, because the money can be taken back
-- AFTER it is spent: collect 100, spend 100, then cancel the receipt that funded
-- it, and the fund stands at −100 with nothing having refused anything. Every
-- عديل reads that figure through api_association_finance() as رصيد الجمعية.
--
-- So cancel_payment now takes the SAME settings-row lock — first, so the two
-- paths queue in one order and cannot deadlock — and refuses, naming the value
-- of vouchers that have to be reversed before the receipt can go.
--
-- It MUST come after the disbursements table above: the new body reads it.
-- CREATE OR REPLACE on a function that already exists keeps its ACL, so this one
-- needs no re-grant of its own — unlike the pair above, which are created fresh.
CREATE OR REPLACE FUNCTION public.cancel_payment(
  p_payment_id bigint,
  p_reason     text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_pay       record;
  r           record;
  v_collected numeric;
  v_spent     numeric;
BEGIN
  PERFORM public.require_role('financeManager');

  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'CANCEL_REASON_REQUIRED' USING ERRCODE = 'RUL09';
  END IF;

  -- ── The treasury mutex, taken FIRST ────────────────────────────────────────
  -- Same row register_disbursement locks, and before the payment row rather
  -- than after, so the two money-moving paths queue in ONE order. No cycle can
  -- form: register_disbursement takes this row and nothing else, and
  -- register_payment takes receivables and nothing else.
  PERFORM 1 FROM public.association_settings WHERE id = 1 FOR UPDATE;

  SELECT * INTO v_pay FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND' USING ERRCODE = 'RUL09';
  END IF;
  IF v_pay.status = 'ملغي' THEN
    RAISE EXCEPTION 'PAYMENT_ALREADY_CANCELLED' USING ERRCODE = 'RUL09';
  END IF;

  -- ── AND THE FUND CANNOT BE LEFT HOLDING LESS THAN NOTHING ──────────────────
  -- register_disbursement refuses to pay out money the association does not
  -- hold. Read only from that side the guarantee is half of one: collect 100,
  -- spend 100, then cancel the receipt that funded it and the treasury stands at
  -- −100 with nothing having refused anything. Every عديل reads that figure
  -- through api_association_finance() under the heading رصيد الجمعية.
  --
  -- The arithmetic is not what is wrong — if the receipt was entered by mistake
  -- and the money genuinely left, the fund really IS short. What is wrong is
  -- that it happens SILENTLY, and that every disbursement afterwards is then
  -- refused for a reason nobody was ever told. So the voucher is reversed first
  -- and this cancellation goes through second; the message says which.
  --
  -- This payment's own cash movement is excluded rather than subtracted: it is
  -- about to become 'ملغي', and rule 8 guarantees exactly one live row per live
  -- payment, so excluding it IS the post-cancellation total.
  SELECT coalesce(sum(amount), 0) INTO v_collected
    FROM public.cash_movements
   WHERE status <> 'ملغي' AND payment_id <> p_payment_id;
  SELECT coalesce(sum(amount), 0) INTO v_spent
    FROM public.disbursements WHERE status <> 'ملغي';

  IF v_collected < v_spent THEN
    RAISE EXCEPTION
      'إلغاء الإيصال % يترك الصندوق سالباً — ألغِ سندات صرف بقيمة % أولاً',
      v_pay.receipt_no, (v_spent - v_collected)::text
      USING ERRCODE = 'RUL09';
  END IF;

  -- Same lock order as register_payment: period then id.
  FOR r IN
    SELECT a.receivable_id, a.amount, rc.period
      FROM public.payment_allocations a
      JOIN public.receivables rc ON rc.id = a.receivable_id
     WHERE a.payment_id = p_payment_id
     ORDER BY rc.period ASC, rc.id ASC
       FOR UPDATE OF rc
  LOOP
    -- ck_recv_paid (paid >= 0) catches a double reversal.
    UPDATE public.receivables SET paid = paid - r.amount
     WHERE id = r.receivable_id;
  END LOOP;

  UPDATE public.payments
     SET status = 'ملغي', cancelled_at = now(),
         cancelled_by = auth.uid(), cancel_reason = p_reason
   WHERE id = p_payment_id;

  -- Voided, never deleted — the cash screen renders it struck through.
  UPDATE public.cash_movements SET status = 'ملغي' WHERE payment_id = p_payment_id;

  PERFORM public.write_audit('payment.cancel',
    format('إلغاء %s: %s', v_pay.receipt_no, p_reason), v_pay.receipt_no);

  RETURN jsonb_build_object(
    'paymentId', p_payment_id, 'receiptNo', v_pay.receipt_no,
    'status', 'ملغي', 'amount', v_pay.amount::text, 'reason', p_reason);
END $$;

-- The purges must take the vouchers too. Omitting them would not merely leave
-- data behind: disbursements.payee_adeel_id references adeels ON DELETE
-- RESTRICT, so one surviving voucher would refuse the register's deletion and
-- abort purge_all_data entirely.
CREATE OR REPLACE FUNCTION public.purge_financial_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv  bigint;
  v_pay   bigint;
  v_alloc bigint;
  v_cash  bigint;
  v_audit bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- The typed phrase. Not UX politeness: register_payment and save_adeel are
  -- reachable by anyone who can read the anon key out of the APK, and so is
  -- this. require_role stops a treasurer; the phrase stops an admin's own
  -- mis-click and a replayed request. It must match wire_values.dart exactly.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح نهائي' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  -- Counted before, because TRUNCATE reports no row count. These tables are
  -- small enough that five counts cost nothing next to the truncate itself.
  SELECT count(*) INTO v_recv  FROM public.receivables;
  SELECT count(*) INTO v_pay   FROM public.payments;
  SELECT count(*) INTO v_alloc FROM public.payment_allocations;
  SELECT count(*) INTO v_cash  FROM public.cash_movements;
  SELECT count(*) INTO v_audit FROM public.audit_log;

  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivables,
           public.closed_periods,
           -- Money going OUT is financial data like any other. Omitting it here
           -- would also make purge_all_data IMPOSSIBLE, not merely incomplete:
           -- disbursements.payee_adeel_id references adeels ON DELETE RESTRICT,
           -- so one surviving voucher would refuse the register's deletion and
           -- abort the entire purge with a foreign-key error.
           public.disbursements,
           public.audit_log
    RESTART IDENTITY;

  RETURN jsonb_build_object(
    'receivables',   v_recv,
    'payments',      v_pay,
    'allocations',   v_alloc,
    'cashMovements', v_cash,
    'auditEntries',  v_audit);
END $$;

CREATE OR REPLACE FUNCTION public.purge_all_data(p_confirm text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_recv   bigint;
  v_pay    bigint;
  v_alloc  bigint;
  v_cash   bigint;
  v_audit  bigint;
  v_adeels bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- Distinct from purge_financial_data's phrase ON PURPOSE. See above.
  IF btrim(coalesce(p_confirm, '')) <> 'مسح كل البيانات' THEN
    RAISE EXCEPTION 'عبارة التأكيد غير مطابقة، لم يتم حذف أي شيء'
      USING ERRCODE = 'RUL13';
  END IF;

  SELECT count(*) INTO v_recv   FROM public.receivables;
  SELECT count(*) INTO v_pay    FROM public.payments;
  SELECT count(*) INTO v_alloc  FROM public.payment_allocations;
  SELECT count(*) INTO v_cash   FROM public.cash_movements;
  SELECT count(*) INTO v_audit  FROM public.audit_log;
  SELECT count(*) INTO v_adeels FROM public.adeels;

  -- ── Why adeels is DELETEd while the five financial tables are TRUNCATEd ────
  -- profiles.adeel_id references adeels, and TRUNCATE refuses whenever ANY table
  -- outside its list carries a foreign key into one being truncated — the
  -- constraint's existence is what it checks, not whether rows remain. So
  -- emptying profiles first does not help: it still dies with 0A000 "cannot
  -- truncate a table referenced in a foreign key constraint". Listing profiles
  -- would delete the association's own staff accounts, and CASCADE would do the
  -- same silently.
  --
  -- DELETE has no such rule, and adeels carries no refuse_delete trigger — that
  -- guard is on the financial tables, which keep their TRUNCATE. The identity is
  -- then restarted by hand, because that is the part RESTART IDENTITY was doing
  -- and the reason the next عديل must be A-0001.
  --
  -- ORDER MATTERS, and not for the reason it looks like. The truncate comes
  -- FIRST because receivables.created_by references profiles ON DELETE SET NULL,
  -- and that SET NULL is an UPDATE which trg_recv_snapshot_immutable rejects
  -- (created_by is a snapshot column). Deleting profiles while any receivable
  -- survives would therefore abort the whole purge with RUL05. Emptying the
  -- financial tables first leaves nothing for the cascade to touch.
  TRUNCATE public.payment_allocations,
           public.cash_movements,
           public.payments,
           public.receivables,
           public.closed_periods,
           -- Money going OUT is financial data like any other. Omitting it here
           -- would also make purge_all_data IMPOSSIBLE, not merely incomplete:
           -- disbursements.payee_adeel_id references adeels ON DELETE RESTRICT,
           -- so one surviving voucher would refuse the register's deletion and
           -- abort the entire purge with a foreign-key error.
           public.disbursements,
           public.audit_log
    RESTART IDENTITY;

  -- Portal accounts go entirely: their عديل is being erased, so leaving the
  -- profile would leave a dangling scope and my_adeel_id() would answer with a
  -- dead id. auth.users survives, so the same person can sign in again and redeem
  -- a fresh code later.
  DELETE FROM public.profiles WHERE adeel_id IS NOT NULL;

  DELETE FROM public.adeels;

  ALTER TABLE public.adeels ALTER COLUMN id RESTART WITH 1;

  RETURN jsonb_build_object(
    'receivables',   v_recv,
    'payments',      v_pay,
    'allocations',   v_alloc,
    'cashMovements', v_cash,
    'auditEntries',  v_audit,
    'adeels',        v_adeels);
END $$;

-- The two read surfaces for money out. v_expense_by_category lists EVERY
-- heading, including the ones nothing has been spent on — a report that omits
-- a zero reads as one that forgot it.
CREATE OR REPLACE VIEW public.v_disbursements WITH (security_invoker = on) AS
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

CREATE OR REPLACE VIEW public.v_expense_by_category WITH (security_invoker = on) AS
SELECT
  c.category::text                                AS "category",
  coalesce(sum(d.amount), 0)::numeric(12,2)::text AS "total",
  count(d.id)                                     AS "count"
FROM unnest(enum_range(NULL::expense_category))
       WITH ORDINALITY AS c(category, ord)
LEFT JOIN public.disbursements d
       ON d.category = c.category AND d.status <> 'ملغي'
GROUP BY c.ord, c.category
ORDER BY c.ord;

GRANT SELECT ON public.v_disbursements, public.v_expense_by_category
TO authenticated;

-- == 12. The lockdown allow-list, restated for the new signature ============
-- An EXACT set. It has to name redeem_adeel_code(text,text) and the new
-- request_device_id(), or assert_function_grants() fails in both directions and
-- the whole patch rolls back.
CREATE OR REPLACE FUNCTION public.client_callable_functions()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    -- Role helpers. The RLS policies call these, so they must be executable by
    -- the caller whose policy is being evaluated. They leak nothing beyond that
    -- caller's own role.
    'role_rank(app_role)',
    'my_role()',
    'has_role(app_role)',
    -- Answers only for the caller's own عديل binding, and the عديل-scoped
    -- policies call it, so the caller whose policy is being evaluated must hold
    -- EXECUTE — otherwise every one of those policies ERRORS instead of denying,
    -- and the failure surfaces as "permission denied for function my_adeel_id"
    -- on screens that have nothing to do with the portal.
    'my_adeel_id()',
    -- Echoes the caller's own x-device-id header back. api_me() is SECURITY
    -- INVOKER and calls it, so the caller must hold EXECUTE or every launch
    -- fails with "permission denied for function request_device_id".
    'request_device_id()',

    -- Writes. Each require_role()-gated, each one transaction.
    'register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)',
    'cancel_payment(bigint,text)',
    'generate_period(character)',
    'auto_close_periods()',
    'save_adeel(bigint,jsonb)',
    -- The only hard delete outside the purges, and it refuses any عديل who has
    -- ever been billed or has ever paid. Retiring someone with history is a
    -- status change, not a deletion.
    'delete_adeel(bigint)',
    'update_settings(jsonb)',
    'set_user_access(uuid,app_role,app_status)',
    -- The two destructive ones. admin-only, and each refuses without its OWN
    -- typed phrase, so the phrase that clears the figures cannot clear the
    -- register. They are on the list because Settings calls them directly; the
    -- reason that is safe is the same reason the others are — the gate is inside
    -- the body, not in who can reach it.
    'purge_financial_data(text)',
    'purge_all_data(text)',

    -- The عديل portal. issue_ is admin-gated; redeem_ deliberately is NOT — it
    -- is the one write a signed-in stranger may call, because until he redeems a
    -- code he has no role and no binding, and the code itself is the
    -- authorisation. It refuses anyone who is already staff.
    'issue_adeel_code(bigint)',
    'redeem_adeel_code(text,text)',

    -- Money OUT. Both admin-gated inside their bodies; register_disbursement
    -- also refuses to spend past the treasury balance, which is rule 7 read
    -- backwards and the reason the fund cannot be overdrawn from a phone.
    'register_disbursement(numeric,disbursement_kind,pay_method,bigint,expense_category,text,text,text,text,text,text,date)',
    'cancel_disbursement(bigint,text)',

    -- Reads. STABLE and SECURITY INVOKER, so RLS still decides what they return.
    'period_label(text)',
    'adeel_json(bigint)',
    'api_adeel_detail(bigint)',
    'api_adeel_statement(bigint)',
    'api_dashboard()',
    'api_alerts()',
    'api_financial_report(date,date)',
    'api_receivables(text)',
    'api_closable_periods()',
    'api_settings()',
    'api_me()',
    'api_touch_login()',
    -- Aggregates only, and SECURITY DEFINER on purpose: an عديل's RLS on
    -- cash_movements is `adeel_id = my_adeel_id()`, so a SECURITY INVOKER
    -- version would show him HIS OWN four figures under headings that say
    -- "the association's" — a wrong answer he has no way to doubt. It returns
    -- no name, no receipt and no row, takes no argument, and writes nothing.
    'api_association_finance()'
  ]::text[]
$$;

REVOKE EXECUTE ON FUNCTION public.client_callable_functions()
  FROM PUBLIC, anon, authenticated, service_role;

-- == 13. Re-run the lockdown sweep =========================================
-- Byte-for-byte the loop from 20260811091200_function_lockdown.sql, which runs
-- LAST on a full apply. A patch gets no such sweep for free, and every function
-- it creates FRESH — request_device_id here, redeem_adeel_code after the DROP —
-- comes out with the built-in default ACL, which is EXECUTE to PUBLIC. That is
-- the error that made an earlier patch roll back on every attempt.
DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.full_sig);
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;

-- == The standing guarantees, re-proven ====================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;

-- Confirm what landed.
SELECT 'profiles carries the device binding' AS check,
       (EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'profiles'
                   AND column_name = 'device_id'))::text AS ok
UNION ALL SELECT 'my_adeel_id refuses a device that does not match',
       (pg_get_functiondef('public.my_adeel_id()'::regprocedure)
          LIKE '%request_device_id%')::text
UNION ALL SELECT 'redeem_adeel_code now takes the handset too',
       (SELECT count(*) = 1 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code'
           AND p.pronargs = 2)::text
UNION ALL SELECT 'reissuing a code releases the handset',
       (pg_get_functiondef('public.issue_adeel_code(bigint)'::regprocedure)
          LIKE '%device_id = NULL%')::text
UNION ALL SELECT 'api_me explains the lock',
       (pg_get_functiondef('public.api_me()'::regprocedure)
          LIKE '%deviceLocked%')::text
UNION ALL SELECT 'a first launch claims an unclaimed handset',
       (pg_get_functiondef('public.api_touch_login()'::regprocedure)
          LIKE '%request_device_id%')::text
UNION ALL SELECT 'redeem_adeel_code is NOT callable by the anon key',
       (SELECT count(*) = 0 FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace,
          LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         WHERE n.nspname = 'public' AND p.proname = 'redeem_adeel_code'
           AND a.privilege_type = 'EXECUTE'
           AND (a.grantee = 0 OR a.grantee = 'anon'::regrole))::text
-- Informational, not a pass/fail: right after the patch every bound عديل reads
-- "N / 0", and each one becomes claimed the next time he opens the app. A
-- boolean here would flip to false the moment the feature started working.
UNION ALL SELECT 'عدايل bound / of those, handset already claimed',
       ((SELECT count(*) FROM public.profiles WHERE adeel_id IS NOT NULL)::text
        || ' / ' ||
        (SELECT count(*) FROM public.profiles
          WHERE adeel_id IS NOT NULL AND device_id IS NOT NULL)::text)
-- §8, the wallet. register_payment kept its name AND its signature, so the
-- only evidence the patch landed is inside the body: the surplus is now named
-- in the audit trail and returned as `credit`, neither of which existed while
-- an over-payment was refused.
UNION ALL SELECT 'a member may now pay AHEAD (the surplus becomes credit)',
       (pg_get_functiondef('public.register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)'::regprocedure)
          LIKE '%رصيد مقدم%')::text
UNION ALL SELECT 'raising a month spends the wallet first',
       (pg_get_functiondef('public.generate_period(bpchar)'::regprocedure)
          LIKE '%settle_from_credit%')::text
UNION ALL SELECT 'the register shows what each member holds or owes',
       (EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'v_adeels'
                   AND column_name = 'netBalance'))::text
-- §11, money out.
UNION ALL SELECT 'the disbursements table exists',
       (to_regclass('public.disbursements') IS NOT NULL)::text
UNION ALL SELECT 'the six أوجه الصرف are defined',
       (SELECT count(*) = 6 FROM unnest(enum_range(NULL::expense_category)))::text
UNION ALL SELECT 'and a voucher must be one of the two kinds, never both',
       (SELECT count(*) = 1 FROM pg_constraint
         WHERE conname = 'ck_disb_shape'
           AND conrelid = 'public.disbursements'::regclass)::text
UNION ALL SELECT 'a voucher can be reversed but never deleted',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_disb_no_delete' AND NOT tgisinternal)::text
UNION ALL SELECT 'an عديل cannot read a single voucher row',
       (SELECT count(*) = 1 FROM pg_policies
         WHERE schemaname = 'public' AND tablename = 'disbursements')::text
UNION ALL SELECT 'the treasury reports what went out',
       (EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'v_cash_summary'
                   AND column_name = 'disbursed'))::text
-- Informational. On a live project this is the treasury as it stands the
-- moment the patch commits — collections minus vouchers, which right after
-- this patch is still collections, because no voucher exists yet.
UNION ALL SELECT 'treasury now / of which spent',
       (SELECT "balance" || ' / ' || "disbursed" FROM public.v_cash_summary)
UNION ALL SELECT 'Google sign-in trigger is STILL in place',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_auth_user_created' AND NOT tgisinternal)::text
UNION ALL SELECT 'staff profiles untouched',
       (EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin'))::text;
