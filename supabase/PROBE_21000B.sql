-- ============================================================================
--  PROBE_21000B.sql — استدعِ الدالة الحقيقية، وامسك سياق خطئها.
--
--  ⚠⚠ لا يحذف شيئاً. اقرأ «لماذا هو آمن» قبل التشغيل.
--
--  WHY A SECOND PROBE
--    The first one ran purge_all_data's three DATA statements — the TRUNCATE
--    and both DELETEs — and all three passed. So the cardinality_violation is
--    not in them. What is left inside that function is six `count(*)` into
--    scalars, `require_role('admin')`, one ALTER on a sequence and a
--    jsonb_build_object over six bigints — and not one of those can raise
--    21000 either, in the version this project has installed.
--
--    Which means the next useful fact is not another guess. It is the CONTEXT
--    line Postgres attaches to the error: the function name and the line number
--    it actually came from. This calls the real function to get it.
--
--  ⚠ WHY IT IS SAFE — three separate reasons, each sufficient
--    1. The block ends in RAISE on EVERY path, including the one where the
--       purge succeeds. A DO block that ends in an exception aborts its
--       transaction, so nothing it did is kept.
--    2. TRUNCATE, DELETE and ALTER TABLE are all transactional in PostgreSQL.
--    3. And the identity sequence is restored EXPLICITLY afterwards anyway —
--       see below. That is belt and braces: if the rollback covers it, the
--       restore is redundant; if it somehow does not, the restore has already
--       put it back.
--
--  WHAT COMES BACK
--    A red ERROR, on purpose. It says either
--      • «الرمز: 21000» plus a CONTEXT naming the function and line — the
--        answer we are after; or
--      • «نجحت» plus the counts it would have deleted — which would mean the
--        database is not the problem at all and the app is, and that is worth
--        just as much.
--
--  HOW TO USE
--    SQL Editor → New query → paste → Run → send me the whole red message.
-- ============================================================================

DO $probe$
DECLARE
  v_state text;
  v_msg   text;
  v_ctx   text;
  v_res   jsonb;
  v_max   bigint;
  v_admin uuid;
BEGIN
  -- Captured BEFORE anything runs, so the restore below has a value to use even
  -- if the purge emptied the table.
  SELECT coalesce(max(id), 0) INTO v_max FROM public.adeels;

  -- Impersonate the admin. require_role('admin') is the function's first line
  -- and reads auth.uid(); a probe with a NULL uid would be refused before
  -- reaching anything, and would prove nothing.
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin' AND status = 'approved' LIMIT 1;
  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_admin)::text, true);

  BEGIN
    v_res := public.purge_all_data('مسح كل البيانات');
  EXCEPTION WHEN OTHERS THEN
    -- ⚠ THIS IS THE WHOLE POINT OF THE FILE. SQLERRM alone says «more than one
    --   row returned by a subquery used as an expression» and nothing about
    --   WHERE. PG_EXCEPTION_CONTEXT names the function and the line.
    GET STACKED DIAGNOSTICS v_ctx = PG_EXCEPTION_CONTEXT;
    v_state := SQLSTATE;
    v_msg   := SQLERRM;
  END;

  -- ⚠ THE IDENTITY, PUT BACK BY HAND. purge_all_data ends with
  --   `ALTER TABLE adeels ALTER COLUMN id RESTART WITH 1`, and a sequence is
  --   the one object whose transactional behaviour is worth not betting on. If
  --   it were left at 1 while ids 3..N still existed, the next عديل saved would
  --   take id 1, then 2, then collide on 3 with a duplicate-key error that
  --   would look like a bug in save_adeel. One line removes the question.
  EXECUTE format('ALTER TABLE public.adeels ALTER COLUMN id RESTART WITH %s',
                 v_max + 1);

  RAISE EXCEPTION
    E'\n\n=== نتيجة الفحص — لم يُحذف شيء ===\nالرمز: %\nالرسالة: %\n\nالسياق:\n%\n\nلو نجحت: %\n',
    coalesce(v_state, '— نجحت بلا خطأ —'),
    coalesce(v_msg,   '—'),
    coalesce(v_ctx,   '—'),
    coalesce(v_res::text, '—');
END $probe$;
