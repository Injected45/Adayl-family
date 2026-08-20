-- ============================================================================
--  PROBE_21000C.sql — نادِ الدالة بدور «authenticated»، تماماً كما ينادي التطبيق.
--
--  ⚠⚠ لا يحذف شيئاً. الكتلة تنتهي بـ RAISE في كل مسار، فتُجهض معاملتها.
--
--  WHY A THIRD PROBE, AND WHY THIS IS THE LAST ONE
--    B called purge_all_data directly and it SUCCEEDED — it reported the eight
--    عدايل, the fifteen receipts and the fifty-six receivables it would have
--    removed. So the function is not broken, the data is not malformed, and no
--    trigger in its path misbehaves.
--
--    What is left is the only difference that remains between that call and the
--    one the app makes: WHO IS MAKING IT. B ran as `postgres`, the session role
--    the SQL editor gives you — a superuser, who bypasses row-level security on
--    every table without asking. PostgREST runs as `authenticated`.
--
--  ⚠ AND «SECURITY DEFINER MAKES THAT IRRELEVANT» IS NOT QUITE TRUE. The body
--    does run with the owner's privileges. But the session role is still
--    `authenticated` while it runs, and anything in the call tree that depends
--    on the CALLER rather than the owner — a SECURITY INVOKER function, a view
--    without security_invoker off, a policy evaluated on a table the owner does
--    not own — sees a different world. That is a real gap and it is exactly the
--    size of the one bug still unaccounted for.
--
--    This closes it: same role, same JWT, same function.
--
--  WHAT COMES BACK
--    A red ERROR either way.
--      • «الرمز: 21000» + a CONTEXT naming a function and a line → found it.
--      • «نجحت» again → the database is exonerated under the app's own role
--        too, and the fault is in the client: the Flutter call, the headers it
--        sends, or the error it is really reporting.
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
  -- Captured while still privileged, so the restore at the end has a value and
  -- the right to use it.
  SELECT coalesce(max(id), 0) INTO v_max FROM public.adeels;
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin' AND status = 'approved' LIMIT 1;

  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub',  v_admin,
                                       'role', 'authenticated')::text, true);

  -- ⚠ THE WHOLE POINT OF THIS FILE IS THIS ONE LINE. Everything above it has
  --   been tried already and passed.
  EXECUTE 'SET LOCAL ROLE authenticated';

  BEGIN
    v_res := public.purge_all_data('مسح كل البيانات');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_ctx = PG_EXCEPTION_CONTEXT;
    v_state := SQLSTATE;
    v_msg   := SQLERRM;
  END;

  -- Back to the privileged role before touching the sequence: `authenticated`
  -- does not own adeels and the ALTER would fail with 42501, which would then
  -- be the error you saw instead of the one we came for.
  EXECUTE 'RESET ROLE';
  EXECUTE format('ALTER TABLE public.adeels ALTER COLUMN id RESTART WITH %s',
                 v_max + 1);

  RAISE EXCEPTION
    E'\n\n=== بدور authenticated — لم يُحذف شيء ===\nالرمز: %\nالرسالة: %\n\nالسياق:\n%\n\nلو نجحت: %\n',
    coalesce(v_state, '— نجحت بلا خطأ —'),
    coalesce(v_msg,   '—'),
    coalesce(v_ctx,   '—'),
    coalesce(v_res::text, '—');
END $probe$;
