-- ============================================================================
--  PROBE_21000.sql — أيّ خطوةٍ بالضبط ترفع 21000، وما سياقها؟
--
--  ⚠⚠ لا يحذف شيئاً. اقرأ الفقرة التالية قبل التشغيل.
--
--  WHAT IT DOES, AND WHY IT IS SAFE
--    It runs purge_all_data's three statements in the real order, catches
--    whatever they raise, and then RAISES UNCONDITIONALLY — including when
--    everything succeeded. A DO block that ends in an exception aborts its
--    transaction, and every statement here is transactional (TRUNCATE included,
--    which it is in PostgreSQL). So the database is left exactly as it was,
--    on every path through this file. There is no branch that commits.
--
--  ⚠ AND IT DELIBERATELY OMITS ONE STATEMENT: the
--    `ALTER TABLE adeels ALTER COLUMN id RESTART WITH 1` that ends the real
--    function. That is the single line whose rollback is not worth relying on,
--    and it cannot be the source of a cardinality_violation anyway — it is DDL
--    on a sequence, not a query.
--
--  WHAT COMES BACK
--    An ERROR, on purpose. Read it — it names the STEP, the SQLSTATE, the
--    message and the CONTEXT. The context is the part no amount of reading the
--    repo could produce: it prints the function and the line the error actually
--    came from.
--
--  ⚠ WHY THE REPO COULD NOT ANSWER THIS
--    21000 has exactly three sources: a scalar subquery returning more than one
--    row, `SELECT INTO STRICT` matching more than one, and `ON CONFLICT DO
--    UPDATE` touching a row twice. The schema contains no INTO STRICT at all,
--    its only ON CONFLICT DO UPDATE is inside issue_adeel_code — which this
--    path never calls — and every trigger that the two DELETEs can fire was
--    read line by line and holds no subquery but a `count(*)`. So the answer is
--    not in the files, and guessing further would only cost you another round
--    trip.
--
--  HOW TO USE
--    SQL Editor → New query → paste → Run → send me the whole red message.
-- ============================================================================

DO $probe$
DECLARE
  v_step  text := 'قبل البداية';
  v_state text;
  v_msg   text;
  v_ctx   text;
  v_admin uuid;
BEGIN
  BEGIN
    -- Impersonate the admin, so auth.uid() answers exactly as it does when the
    -- app calls this. The profile triggers branch on `NEW.id = auth.uid()`, and
    -- a probe running with a NULL uid would take a different path from the one
    -- that failed.
    SELECT id INTO v_admin FROM public.profiles
     WHERE role = 'admin' AND status = 'approved' LIMIT 1;
    PERFORM set_config('request.jwt.claims',
                       json_build_object('sub', v_admin)::text, true);

    -- ── The real order, statement for statement ───────────────────────────
    v_step := '1 — TRUNCATE الجداول المالية';
    TRUNCATE public.payment_allocations,
             public.cash_movements,
             public.payments,
             public.receivables,
             public.closed_periods,
             public.disbursements,
             public.chat_messages,
             public.audit_log
      RESTART IDENTITY;

    v_step := '2 — DELETE حسابات المشتركين';
    DELETE FROM public.profiles WHERE adeel_id IS NOT NULL;

    v_step := '3 — DELETE سجل العدايل';
    DELETE FROM public.adeels;

    v_step := '⇒ الخطوات الثلاث مرّت كلها بلا خطأ';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_ctx = PG_EXCEPTION_CONTEXT;
    v_state := SQLSTATE;
    v_msg   := SQLERRM;
  END;

  -- ⚠ ALWAYS. This is what guarantees the rollback — including on the happy
  --   path, where the three statements succeeded and their work must still be
  --   thrown away. A probe that committed when it happened to work would be a
  --   purge with extra steps.
  RAISE EXCEPTION E'\n\n=== نتيجة الفحص (لم يُحذف شيء) ===\nالخطوة: %\nالرمز: %\nالرسالة: %\n\nالسياق:\n%\n',
    v_step,
    coalesce(v_state, 'لا خطأ'),
    coalesce(v_msg,   'لا خطأ'),
    coalesce(v_ctx,   '—');
END $probe$;
