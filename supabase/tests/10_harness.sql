-- 10_harness.sql — assertion primitives for the probe suite.
--
-- Every check records a row. probe.report() exits non-zero if any row failed,
-- so the suite cannot pass by silently skipping.
--
-- The design point that matters: probe.raises() asserts a specific SQLSTATE, not
-- merely "an error happened". A test that accepts any failure passes when the
-- statement fails for an unrelated reason — a typo'd column name looks identical
-- to a constraint firing. Each business rule raises its own RULnn code so the
-- probe can prove THAT rule bit.

CREATE SCHEMA IF NOT EXISTS probe;

CREATE TABLE probe.result (
  id      serial PRIMARY KEY,
  group_  text NOT NULL,
  name    text NOT NULL,
  ok      boolean NOT NULL,
  detail  text NOT NULL DEFAULT ''
);

CREATE OR REPLACE FUNCTION probe.note(g text, n text, cond boolean, d text DEFAULT '')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO probe.result (group_, name, ok, detail) VALUES (g, n, cond, d);
END $$;

-- Asserts the statement fails with exactly `expect`. SECURITY INVOKER on
-- purpose: the EXECUTE must run with the privileges of whoever is currently SET
-- ROLE'd, or the RLS probes would all run as postgres and prove nothing.
CREATE OR REPLACE FUNCTION probe.raises(g text, n text, stmt text, expect text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE got text; msg text;
BEGIN
  BEGIN
    EXECUTE stmt;
    PERFORM probe.note(g, n, false,
      format('expected %s, but the statement SUCCEEDED', expect));
    RETURN;
  EXCEPTION WHEN OTHERS THEN
    got := SQLSTATE; msg := SQLERRM;
  END;
  PERFORM probe.note(g, n, got = expect,
    format('sqlstate=%s (%s) %s', got, expect, left(msg, 120)));
END $$;

-- Same, but accepts any error whose message matches a pattern. Used only where
-- the error comes from Postgres itself and its SQLSTATE is the generic one —
-- e.g. a unique-index violation is always 23505 regardless of which rule it
-- carries, so the index NAME is what identifies the rule.
CREATE OR REPLACE FUNCTION probe.raises_like(g text, n text, stmt text,
                                             expect text, like_ text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE got text; msg text;
BEGIN
  BEGIN
    EXECUTE stmt;
    PERFORM probe.note(g, n, false,
      format('expected %s/%s, but the statement SUCCEEDED', expect, like_));
    RETURN;
  EXCEPTION WHEN OTHERS THEN
    got := SQLSTATE; msg := SQLERRM;
  END;
  PERFORM probe.note(g, n, got = expect AND msg LIKE like_,
    format('sqlstate=%s msg=%s', got, left(msg, 120)));
END $$;

CREATE OR REPLACE FUNCTION probe.succeeds(g text, n text, stmt text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
    PERFORM probe.note(g, n, true, '');
  EXCEPTION WHEN OTHERS THEN
    PERFORM probe.note(g, n, false,
      format('unexpected %s: %s', SQLSTATE, left(SQLERRM, 160)));
  END;
END $$;

-- Asserts a scalar query returns the expected value.
CREATE OR REPLACE FUNCTION probe.eq(g text, n text, query text, expect text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE got text;
BEGIN
  BEGIN
    EXECUTE query INTO got;
  EXCEPTION WHEN OTHERS THEN
    PERFORM probe.note(g, n, false, format('query failed %s: %s', SQLSTATE, left(SQLERRM,120)));
    RETURN;
  END;
  PERFORM probe.note(g, n, got IS NOT DISTINCT FROM expect,
    format('got=%s expected=%s', coalesce(got,'<null>'), coalesce(expect,'<null>')));
END $$;

-- Impersonation. This is what makes the RLS probes meaningful: PostgREST issues
-- exactly these two statements per request — the role from the JWT's `role`
-- claim, and the claims themselves as a GUC that auth.uid() reads.
CREATE OR REPLACE FUNCTION probe.become(p_uid uuid, p_role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  -- is_local = FALSE deliberately. psql autocommits every statement, so a
  -- transaction-local setting would evaporate before the next probe ran and
  -- every check would silently execute as an anonymous caller.
  IF p_uid IS NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('role', p_role)::text, false);
  ELSE
    PERFORM set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', p_role)::text, false);
  END IF;
END $$;

-- Reports, and fails if any check failed OR if the number of checks is not the
-- number expected.
--
-- The count matters as much as the failures. Two concurrency checks once vanished
-- because the SQL feeding them errored, so the notes were never inserted — and a
-- suite that counts what it recorded cannot tell a missing check from a check that
-- does not exist. It reported success with 169 of 171.
CREATE OR REPLACE FUNCTION probe.report(p_expected int DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE r record; v_fail int; v_total int;
BEGIN
  FOR r IN SELECT group_, name, ok, detail FROM probe.result ORDER BY id LOOP
    RAISE INFO '%  [%] %  %',
      CASE WHEN r.ok THEN 'PASS' ELSE 'FAIL' END, r.group_, r.name,
      CASE WHEN r.ok THEN '' ELSE '<< ' || r.detail END;
  END LOOP;

  SELECT count(*) INTO v_fail  FROM probe.result WHERE NOT ok;
  SELECT count(*) INTO v_total FROM probe.result;
  RAISE INFO '';
  -- plpgsql RAISE has one placeholder form, '%'. '%s' would print a literal 's'.
  RAISE INFO '% checks, % failed', v_total, v_fail;

  IF v_fail > 0 THEN
    RAISE EXCEPTION '% probe check(s) failed', v_fail;
  END IF;

  IF p_expected IS NOT NULL AND v_total <> p_expected THEN
    RAISE EXCEPTION
      'probe suite ran % checks, expected % — a check did not execute (its SQL '
      'errored before the note was recorded), or one was added without updating '
      'EXPECTED_CHECKS in probe.sh',
      v_total, p_expected;
  END IF;
END $$;
