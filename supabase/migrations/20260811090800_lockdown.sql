-- 20260811090800_lockdown.sql — runs LAST, on purpose.
--
-- Postgres grants EXECUTE on every newly created function to PUBLIC. With no API
-- tier, that default is the difference between "only a treasurer can call
-- register_payment" and "anyone holding the anon key can call it and rely on the
-- inner role check being correct".
--
-- 20260811090500_rls.sql tried to fix this with
--     ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
-- and it DOES NOT WORK. Verified on PostgreSQL 16.4: issued as the superuser that
-- owns these objects it is a silent no-op — no pg_default_acl row is recorded and
-- a function created immediately afterwards still comes out PUBLIC-executable.
-- Supabase migrations run as exactly that kind of role, so the pattern cannot be
-- relied on there either. The probe suite is what caught it: `anon` reached
-- register_payment, and a plain viewer successfully called write_audit, which
-- would have let any signed-in user forge audit-trail entries under their own
-- name.
--
-- Hence: an explicit revoke, after every function exists, followed by an
-- assertion. The assertion is the part that matters — it makes the guarantee
-- survive the next person who adds a function without reading this file, because
-- their migration will fail.

-- Revoked function by function, not `ON ALL FUNCTIONS IN SCHEMA public`, so an
-- extension installed in `public` on a real project keeps working. The assertion
-- below exempts extension-owned functions for the same reason.
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

-- Re-state the whole allow-list here rather than trusting the grants made in
-- earlier files, so this one file is the complete answer to "what can a client
-- call?".
GRANT EXECUTE ON FUNCTION
  public.role_rank(app_role), public.my_role(), public.has_role(app_role)
TO authenticated;

GRANT EXECUTE ON FUNCTION
  public.register_payment(bigint, numeric, pay_method, text, text, text),
  public.cancel_payment(bigint, text),
  public.generate_period(char),
  public.auto_close_periods(),
  public.save_family(bigint, jsonb, jsonb),
  public.update_settings(jsonb),
  public.set_user_access(uuid, app_role, app_status)
TO authenticated;

-- Deliberately NOT granted to anyone: write_audit (forgeable trail entries),
-- require_role (pointless alone), touch_updated_at / guard_* / derive_* /
-- refuse_* (trigger bodies — Postgres checks EXECUTE at CREATE TRIGGER time, not
-- when the trigger fires, so withholding it costs nothing).

-- ── The standing guarantee ───────────────────────────────────────────────────
-- Exposed as a function rather than inlined so the probe suite can call it, and
-- so it can be planted with a violation to prove it is capable of failing.
CREATE OR REPLACE FUNCTION public.assert_no_public_execute() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
                    ', ' ORDER BY p.proname)
    INTO v_bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND (
       -- NULL proacl means "built-in default", and the built-in default for a
       -- function includes EXECUTE for PUBLIC.
       p.proacl IS NULL
       OR EXISTS (SELECT 1 FROM aclexplode(p.proacl) a
                   WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
     )
     -- Functions belonging to an EXTENSION are not ours to lock down. A real
     -- Supabase project may have pgcrypto, uuid-ossp or similar installed in
     -- `public` rather than `extensions`, and revoking PUBLIC execute from them
     -- would break unrelated things — gen_random_uuid() among them. The rule is
     -- about the API surface this schema defines, not about every function that
     -- happens to live in the same namespace.
     AND NOT EXISTS (
       SELECT 1 FROM pg_depend d
        WHERE d.objid = p.oid
          AND d.classid = 'pg_proc'::regclass
          AND d.deptype = 'e'
     );

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these public functions are executable by PUBLIC (i.e. by anyone holding the anon key): %',
      v_bad;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_no_public_execute() FROM PUBLIC;

SELECT public.assert_no_public_execute();

-- Views obey the caller's policies only because every one of them was created
-- WITH (security_invoker = on). A view without it runs as its owner and reads
-- straight past RLS, so this is checked too rather than trusted to review.
CREATE OR REPLACE FUNCTION public.assert_views_security_invoker() RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(c.relname, ', ' ORDER BY c.relname) INTO v_bad
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'v'
     -- reloptions stores the literal as written, so this is 'on', not 'true'.
     -- The first version of this check compared against 'true' and reported
     -- every view as unsafe, which is the right way for an assertion to be
     -- wrong: loudly.
     AND NOT coalesce((SELECT lower(option_value) IN ('on','true','1','yes')
                         FROM pg_options_to_table(c.reloptions)
                        WHERE option_name = 'security_invoker'), false);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION
      'LOCKDOWN: these views bypass RLS because security_invoker is not on: %', v_bad;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public.assert_views_security_invoker() FROM PUBLIC;

SELECT public.assert_views_security_invoker();
