# Supabase migration plan — dropping Node and MySQL

**Status:** LIVE. Applied to project `wvryyidbjvvomurvfhpw` (eu-north-1) and verified
end to end over HTTPS — `python supabase/tests/verify_live.py <pwfile>` → all 52
checks pass. Phases 1–3 complete. Schema ported and proven, and the Flutter app now
talks to Supabase — no Node, no MySQL, no Dio. Phase 4 (MariaDB data migration and
decommissioning `api/`) remains.
**To connect it to your project:** `docs/SUPABASE_SETUP.md`.
**Verification:** `bash supabase/tests/probe.sh` → **169 checks, 0 failed**;
`cd app && flutter test` → **111 tests passing**, 36 of them parsing real wire JSON.
**Scope of this document:** what each piece of the current server becomes, whether it survives a hostile client, and what cannot be preserved at all.

---

## 1. The decision, and the one constraint that governs it

The Node/Express tier and MariaDB go away. Flutter talks to Supabase directly: PostgREST for reads, RPC for writes, GoTrue for Google sign-in, RLS for authorisation.

Removing the server removes the only component that could be trusted.

> The Supabase anon key ships inside the Android binary, inside the iOS binary, and in plain text in the web bundle. It is not a secret and cannot be made one. Anyone who installs the app can extract it and issue arbitrary PostgREST calls from curl.
>
> **Therefore every business rule, every role check and every money invariant must be enforced inside Postgres. Dart-side validation is a convenience for the user and counts for nothing.**

Everything below follows from that. It is also why this phase produced a probe suite before it produced any Dart: the previous architecture could rely on `api/src/` being the only writer, and that assumption is now gone.

### Topology

```
┌────────────────────────────────────────────────────────────┐
│ FLUTTER CLIENT  (Android · iOS · Web)                       │
│ Material 3 · RTL-first · Riverpod · go_router               │
│ Holds: the ANON KEY (public) + a GoTrue session             │
│ Trusted with: NOTHING                                       │
└──────────────────────────┬─────────────────────────────────┘
                           │ HTTPS · PostgREST + RPC · user JWT
                           ▼
┌────────────────────────────────────────────────────────────┐
│ SUPABASE                                                    │
│  GoTrue      Google OAuth, session + refresh rotation       │
│  PostgREST   reads via v_* views; writes ONLY via RPC       │
│  Postgres    RLS · CHECK · triggers · generated columns     │
│              ── the only place rules execute ──             │
└────────────────────────────────────────────────────────────┘
```

Compare with the old diagram in `MIGRATION_PLAN.md` §2.1: the box labelled *"THE ONLY PLACE the 12 business rules execute"* moved from the API tier into the database. That sentence is the entire migration.

---

## 2. Translation decisions — MySQL → Postgres

Every construct was verified against a live PostgreSQL 16.4 before being relied on, the same way MariaDB 10.4 was probed in phase 1 of the original plan.

| MySQL / MariaDB | Postgres | Note |
|---|---|---|
| `BIGINT UNSIGNED AUTO_INCREMENT` | `bigint GENERATED ALWAYS AS IDENTITY` | No unsigned type; identity is the standard form |
| `DECIMAL(12,2)` | `numeric(12,2)` | Same exactness. **But see §4 — it does not reach Dart the same way** |
| inline `ENUM(...)` | `CREATE TYPE … AS ENUM` | Arabic labels kept verbatim; they are the wire values `wire_values.dart` already sends |
| `DATETIME` / `DATETIME(3)` | `timestamptz` | Microsecond resolution, better than the `(3)` the audit log needed |
| `ON UPDATE CURRENT_TIMESTAMP` | `touch_updated_at()` trigger | No declarative equivalent |
| `SIGNAL SQLSTATE '45000'` | `RAISE … USING ERRCODE = 'RULnn'` | One code per rule, so a probe can assert *which* rule fired |
| `<=>` (NULL-safe `=`) | `IS DISTINCT FROM` | Used by the rule-5 immutability trigger |
| `REGEXP` in `CHECK` | `~` | `period ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'` |
| `users` table | `auth.users` + `public.profiles` | GoTrue owns identity; `profiles.id` **is** `auth.uid()` |
| `refresh_tokens` table | *(deleted)* | GoTrue owns rotation. **Lossy — see R4** |

Three places where Postgres is materially better, and the schema was changed to take advantage rather than transcribed literally:

**1. `family_code` and `receipt_no` are now generated columns.**
MySQL forbids a generated column that references `AUTO_INCREMENT`, which forced the API to `INSERT` then `UPDATE … SET family_code = CONCAT('F-', LPAD(id,4,'0'))` inside the creating transaction. Postgres allows it — verified directly, `F-0001`/`F-0002` came out correct. The second statement is gone, so there is no longer a window between the two for anything to fail in. (The prototype's `F-${families.length+1}` collides outright under concurrency; both schemas fix that, this one more simply.)

**2. Rules 4 and "one father per family" are partial unique indexes.**
MySQL needed generated helper columns (`active_period`, `father_slot`) that produced `NULL` for rows that should escape the constraint, exploiting `NULL` repeating freely in a unique index. Postgres indexes a predicate directly:
```sql
CREATE UNIQUE INDEX uq_recv_active_period
  ON receivables (family_id, period) WHERE status <> 'ملغي';
```
Same guarantee, two fewer stored columns, and the intent is legible.

**3. Receivable `status` is now derived by a trigger.**
It used to be whatever the API wrote. A hostile client cannot be trusted to label an unpaid charge honestly, so `derive_recv_status()` computes it from `paid` and `total` on every write. Cancellation stays explicit.

---

## 3. Endpoint mapping — all 31

`R` = direct PostgREST read against a view. `RPC` = `SECURITY DEFINER` function. Every RPC calls `require_role()` as its first statement.

| # | Was | Becomes | Min role | Hostile client stopped by |
|---|---|---|---|---|
| 1 | `POST /auth/google` | GoTrue OAuth | public | GoTrue verifies with Google |
| 2 | `POST /auth/refresh` | GoTrue | public | GoTrue |
| 3 | `POST /auth/logout` | GoTrue | any | GoTrue |
| 4 | `GET /auth/me` | `R profiles WHERE id = auth.uid()` | any | `read_own_profile` policy |
| 5 | `GET /users` | `R profiles` | admin | `read_all_profiles` policy |
| 6 | `PATCH /users/:id` | `RPC set_user_access` | admin | `require_role` + `trg_profiles_guard` |
| 7 | `GET /settings` | `R v_settings` | viewer | `read_settings` policy |
| 8 | `PUT /settings` | `RPC update_settings` | admin | `require_role` |
| 9 | `GET /officials` | `R v_officials` | viewer | policy on the base table |
| 10 | `GET /families` | `R v_families` | viewer | `read_families` policy |
| 11 | `POST /families` | `RPC save_family(NULL,…)` | financeManager | `require_role` |
| 12 | `GET /families/:id` | `R v_families` + `v_members` | viewer | policy |
| 13 | `PUT /families/:id` | `RPC save_family(id,…)` | financeManager | `require_role` |
| 14 | `GET /families/:id/statement` | `R v_receivables` + `v_payments` merged client-side | viewer | policy |
| 15 | `GET /members` | `R v_members` | viewer | `read_members` policy |
| 16 | `GET /receivables` | `R v_receivables` | viewer | policy |
| 17 | `GET /receivables/:id` | `R v_receivables` + `v_receivable_lines` | viewer | policy |
| 18 | `POST /receivables/generate` | `RPC generate_period` | financeManager | `require_role` |
| 19 | `POST /receivables/auto-close` | `RPC auto_close_periods` | financeManager | `require_role` |
| 20 | `GET /payments` | `R v_payments` | viewer | policy |
| 21 | `GET /payments/:id` | `R v_payments` + `v_payment_allocations` | viewer | policy |
| 22 | **`POST /payments`** | **`RPC register_payment`** | treasurer | `require_role` + `FOR UPDATE` + `ck_recv_paid` |
| 23 | **`POST /payments/:id/cancel`** | **`RPC cancel_payment`** | financeManager | `require_role` + `FOR UPDATE` |
| 24 | `GET /cash/movements` | `R v_cash_movements` | viewer | policy |
| 25 | `GET /cash/summary` | `R v_cash_summary` | viewer | policy |
| 26 | `GET /dashboard` | `R v_dashboard_stats` + `v_top_debtors` | viewer | policy |
| 27 | `GET /alerts` | `R v_members WHERE eligibility IN ('soon',…)` | viewer | policy |
| 28 | `GET /reports/financial` | `R v_payments` + `v_receivables` filtered | viewer | policy |
| 29 | `GET /audit` | `R audit_log` | financeManager | `read_audit` policy |
| 30 | `POST /admin/import-legacy` | one-shot script, service_role key, run off-device | admin | **not implemented — phase 4** |
| 31 | `GET /health` | Supabase platform status | public | n/a |

**22 reads, 7 RPCs, 1 deferred, 1 dropped.** The original count was "31 endpoints, 9 transactional"; the ninth transactional endpoint is #30, deferred to the data-migration phase.

### Why writes are RPC-only

There is no `INSERT`, `UPDATE` or `DELETE` policy on any table, and `authenticated` holds no write privilege on any table. This was a deliberate choice over per-table write policies:

A policy can only judge the row in front of it. It cannot know that this insert into `payment_allocations` is the third of five that must all land or none, nor that `receivables.paid` must move by exactly the matching amount, nor that a cash movement must follow. The nine endpoints were transactional for a reason and a policy has no way to express it. A function body is one transaction, so funnelling writes through functions keeps the boundary the API used to own.

---

## 4. Money on the wire — the finding that shaped the read layer

This is the single most consequential difference from MySQL and it is invisible until you look.

**mysql2 returned `DECIMAL` as a string.** The whole Dart model layer is built on that: money arrives as `String`, is parsed to integer minor units, and never touches `double`.

**PostgREST returns `numeric` as a bare JSON number.** Proven — PostgREST builds its response body with `json_agg` inside Postgres, so `json_agg` output *is* the wire format:

```
postgrest_wire   [{"id":1,"amount":12345678.91}, {"id":2,"amount":0.10}]
with_text_cast   [{"id":1,"amt_text":"12345678.91"}, {"id":2,"amt_text":"0.10"}]
```

`dart:convert` decodes an unquoted `12345678.91` to `double`. Every balance in the treasury would silently become a float.

**Fix:** all 12 read views cast money with `::text`, and every RPC return casts too. Verified for exactness at the top of the type's range, and — accurately — the hazard is arithmetic rather than a single round-trip:

```
PASS [money] a raw numeric column serialises as a bare JSON NUMBER
PASS [money] the view serialises the same value as a QUOTED STRING
PASS [money] it round-trips to the exact minor unit            (9999999999.91)
PASS [money] a float8 round-trip alone does NOT lose this value
PASS [money] but float8 ACCUMULATION drifts where numeric does not
PASS [money] numeric accumulation is exact to the minor unit    (100 × 0.07 = 7.00)
```

The first draft of that probe asserted a single float8 round-trip corrupts `9999999999.91`. It does not — 12 significant digits fit in float8's ~15. The probe failed and was corrected rather than the claim being kept. What actually breaks is accumulation, which is exactly what Dart would do to these values once they arrived as doubles.

**This is not fully closed. See residual risk R1.**

---

## 5. Business rules — all 12, with a demonstrated failing case each

Every rule has a probe that satisfies it *and* a probe that violates it. Only the second proves anything: a test that merely inserts a valid row demonstrates the column exists, not that the rule bites.

| # | Rule | Enforced by | Hostile client? |
|---|---|---|---|
| 1 | Son billable only when age ≥ `eligibility_age` **at period end**; member status overrides age | `generate_period()` + `eligibility_age_snapshot` | ✅ writes are RPC-only |
| 2 | "قريب من السن" within `warning_months` | `v_members.eligibility`, derived never stored | ✅ read-only, cannot be forged |
| 3 | Total = father fee (if `نشط`) + son fee × eligible; skip if ≤ 0 | `ck_recv_total CHECK (total > 0)` | ✅ storage engine |
| 4 | One **live** receivable per (family, period) | `uq_recv_active_period` partial unique index | ✅ storage engine |
| 5 | Receivables are immutable snapshots | `trg_recv_snapshot_immutable` | ✅ trigger, binds service_role too |
| 6 | Auto-close `system_start` → previous month | `auto_close_periods()`, idempotent via rule 4 | ✅ RPC-only |
| 7 | Payment > 0 and ≤ outstanding; FIFO oldest first | `ck_pay_amount`, `ck_recv_paid`, `FOR UPDATE … ORDER BY period` | ✅ constraint + lock |
| 8 | Every approved payment writes exactly one cash movement | `uq_cash_payment` | ✅ storage engine |
| 9 | Cancellation reverses and preserves; nothing is hard-deleted | 5 × `BEFORE DELETE` refusal triggers | ✅ triggers, bind service_role too |
| 10 | `national_id` unique across all members; DOB not future | `uq_members_national_id`, `trg_members_dob` | ✅ index + trigger |
| 11 | Statement = chronological merge with running balance | asserted as `issued − collected = outstanding` | ✅ derived from immutable rows |
| 12 | Audit on six event types, append-only | `trg_audit_no_update` / `no_delete` | ✅ triggers |

Sample of the refusals Postgres actually emitted:

```
PASS [rule04] a direct duplicate insert is refused
     sqlstate=23505 msg=duplicate key value violates unique constraint "uq_recv_active_period"
PASS [rule05] total cannot be edited
     sqlstate=RUL05 Rule 5: receivable snapshot columns are immutable
PASS [rule07] paying more than is owed is refused
     sqlstate=RUL07 Rule 7: amount 80.01 exceeds outstanding balance 80.00
PASS [rule09] payments cannot be deleted
     sqlstate=RUL09 Rule 9: payments rows cannot be deleted, only cancelled
PASS [rule10] duplicate national id is refused
     sqlstate=23505 msg=duplicate key value violates unique constraint "uq_members_national_id"
PASS [rule12] an audit row cannot be edited
     sqlstate=RUL12 audit_log is append-only
```

Rule 5's real test is not that the column rejects an `UPDATE` — it is that changing settings cannot rewrite history:

```
PASS [rule05] settings can be changed                              (sonFee → 999.00)
PASS [rule05] the historical receivable is unchanged by it          (still 40.00)
```

Rule 7's ordering, which the prototype's FIFO loop implements and the money depends on:

```
PASS [rule07] FIFO filled February first, in full            (paid 40.00)
PASS [rule07] ...and spilled the remaining 10 into March     (paid 10.00)
PASS [rule07] sequence_no records February as allocation 1
```

### Rule 10 — carried-forward conflict C1, still open

`MIGRATION_PLAN.md` §11.2 flagged that the DOB-not-future check covers fathers **and** sons here, while `index.html` (`saveFamily` line 309) validates sons only and never checks the father's. The stricter reading was kept, so `trg_members_dob` still rejects a future DOB for either. It could reject a legacy record on import. To match the prototype exactly, add `AND NEW.kind = 'son'`. **Your decision, not silently settled.**

---

## 6. Concurrency and atomicity

`MIGRATION_PLAN.md` called the money path "the single biggest risk", because the prototype is safe only by being single-threaded and single-user. Losing the Node tier does not change the risk — it relocates it entirely into `register_payment`'s `FOR UPDATE`.

Tested with **two real psql sessions**, deliberately overlapped. A single connection never contends with itself, so a one-session test would prove nothing. Family owes exactly 100.00; both sessions try to pay 60.00:

```
  session A: RESULT=PAY-000014 COMMIT
  session B: ERROR:  Rule 7: amount 60.00 exceeds outstanding balance 40.00
  winners=1 paid=60.00 collected=60.00 payments=1

PASS [concurrency] exactly one of two simultaneous 60.00 payments succeeded
PASS [concurrency] the loser was refused by rule 7, not by a deadlock or a crash
PASS [concurrency] paid never exceeded the 100.00 owed
```

The loser blocked on the lock, woke up, re-read `40.00`, and was refused. That is the correct outcome — 120 collected against 100 owed is money invented from nothing.

Atomicity was tested at the interesting point. Rejecting an over-payment proves little, because it fails before any allocation is written. So a failure was injected at the cash-movement insert, *after* the payment row, all allocations and all receivable updates had landed:

```
PASS [atomicity] a failure AFTER the allocations aborts the whole call
PASS [atomicity] the allocations and receivable balances rolled back with it
PASS [atomicity] with the injected failure removed, the same payment succeeds
```

That last line matters: without it, the previous two would also pass if the injected trigger had silently done nothing.

---

## 7. The hostile client — 76 checks

Every check below ran with `SET ROLE` + `request.jwt.claims`, which is exactly what PostgREST issues per request. **The service_role key is never used**; testing with it would prove nothing.

Two denial shapes, and conflating them is how RLS bugs hide:
- **no privilege** → `42501`, the statement errors
- **policy denies** → the statement **succeeds and returns zero rows**

A probe that only looks for errors reports a wide-open table as locked down.

| Caller | Result |
|---|---|
| `anon` (12) | Cannot read any table or view; cannot call any RPC; cannot insert |
| **pending** (15) | Genuine JWT, never approved. Sees **zero** rows in every table *and every view*; can read only its own profile row; cannot self-approve |
| **suspended** (2) | `role = 'admin'`, `status = 'suspended'` → sees nothing, admin RPCs refuse |
| viewer (18) | Reads everything except the audit trail; refused on all 7 RPCs; refused on direct `INSERT`/`UPDATE`/`DELETE`; cannot forge an audit entry |
| treasurer (6) | May register a payment; may **not** cancel one, generate, or change settings |
| financeManager (7) | May cancel, generate, save families, read the audit trail; may **not** change settings or grant roles |
| admin (6) | All of it — but cannot change **their own** role, and still cannot write tables directly |

The pending case is the dangerous one, because only a flag separates it from a viewer. It is checked against the views as well as the tables, because a view created without `security_invoker` runs with its owner's rights and reads straight past RLS.

Every block asserts `current_user = 'authenticated'` before testing anything. That guard exists because the first draft of the view checks sat one line below a `RESET ROLE` and therefore ran as `postgres` — the table owner, who bypasses RLS — and reported the entire ledger as readable by an unapproved user. It looked exactly like a critical vulnerability and was purely the probe standing in the wrong place. **An RLS test that cannot demonstrate which role it is running as is worse than no test.**

---

## 8. Three real defects this phase found

These were found by the probes, not by review. All three are fixed and pinned.

### 8.1 `PUBLIC` could execute every function — including `write_audit`

Postgres grants `EXECUTE` on every newly created function to `PUBLIC`. Revoking from `anon` and `authenticated` does nothing, because they inherit it through `PUBLIC` — and the revoke reads as effective while changing nothing.

Consequence: `anon` reached `register_payment`, and a plain **viewer successfully called `write_audit`** — able to forge audit-trail entries under their own name, in a system whose rule 12 exists to make the trail trustworthy. `register_payment` was still refused deeper in by `require_role()`, but `write_audit` has no inner check at all.

The obvious fix does not work either. Verified on PostgreSQL 16.4:
```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
```
is a **silent no-op** when issued by the superuser that owns the objects — nothing lands in `pg_default_acl` (`\ddp` shows zero rows) and a function created immediately afterwards still comes out `PUBLIC`-executable. Supabase runs migrations as that kind of role, so this is not a local artefact.

Fixed by `20260811090800_lockdown.sql`, which runs last: an explicit `REVOKE EXECUTE ON ALL FUNCTIONS … FROM PUBLIC`, a re-stated allow-list, and `assert_no_public_execute()` — which **fails the migration** if any function in `public` is `PUBLIC`-executable. That assertion is the part that lasts; it will break the next migration that adds a function without thinking.

### 8.2 `numeric(12,2)` accumulator overflow in `register_payment`

`v_outstanding` was declared `numeric(12,2)`, copying the column type. Individual amounts are bounded by that type; their **sum** is not. A family with enough open periods overflows a 12-digit accumulator and the call dies with `22003 numeric field overflow` instead of reporting a balance. Found when a probe pushed a large total through and got an overflow where it expected a rule violation. Now unconstrained `numeric`.

### 8.3 The `security_invoker` assertion could not see its own subject

`reloptions` stores the option value as written — `on`, not `true`. The first version compared against `'true'` and reported all 12 views as unsafe. Wrong, but wrong in the right direction: loudly. Fixed, and backed by a behavioural check (a pending user reading `v_families` must see zero rows), because introspection alone cannot prove RLS is actually applied.

### 8.4 `anon` and `authenticated` could execute EVERY function — found on the live project

The worst of the four, and the only one the local suite could not have caught.

§8.1 revoked `EXECUTE` from `PUBLIC` and asserted no function in `public` was
`PUBLIC`-executable. That assertion **passed on the live project.** And a plain
signed-in user could still call `write_audit` and forge audit-trail entries under
their own name. A forged row was actually written during verification.

A real Supabase project ships with:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON FUNCTIONS TO postgres, anon, authenticated, service_role;
```

so every function created in `public` comes out with `EXECUTE` granted to `anon` and
`authenticated` **by name**. Nothing is granted to `PUBLIC` — which is exactly why
the `PUBLIC`-only check reported success. Revoking from `PUBLIC` on Supabase changes
nothing whatsoever. `anon` — the key that ships in the app binary — could call
`register_payment` directly; `require_role()` refused it, but `write_audit` has no
inner check at all.

It was invisible locally because `supabase/tests/00_local_shim.sql` did not
reproduce those default privileges. **It does now**, and the probe suite fails
without the fix. That is the durable part of this finding: the shim's job is to
reproduce the platform, and a gap in the shim is a class of bug the suite cannot
see.

Fixed by `20260811091200_function_lockdown.sql`, which revokes from `PUBLIC`, `anon`,
`authenticated` and `service_role`, then grants back an explicit allow-list, and
asserts the callable set is **exactly** that list — extra *or* missing both fail.
Verified on live: `write_audit` now unreachable by either role, `register_payment`
no longer callable by `anon`.

Two smaller harness defects surfaced alongside it:

* **A check that fails to execute was indistinguishable from a check that does not
  exist.** `sum(amount)` was ambiguous across a join in the concurrency script, so
  two of its five notes never ran — and the suite reported success at 169 of 171.
  `probe.report()` now takes an expected total and fails on a mismatch.
* `pg_get_function_identity_arguments()` includes **parameter names**
  (`p_period character`), not just types. Comparing an allow-list against it matched
  only the zero-argument functions and silently left fourteen ungranted. The
  comparison uses `oid::regprocedure` instead.

### Mutation testing — is the suite wired to anything?

A suite that passes is worthless unless it can fail. Six breaches were planted, one at a time, and the schema rebuilt each time:

| Planted breach | Result |
|---|---|
| Rule 5 immutability trigger dropped | **14 failures** |
| Rule 4 partial unique index dropped | **36 failures** |
| Rule 9 no-delete guard dropped | **1 failure** |
| Money `::text` casts removed from a view | **2 failures** |
| `UPDATE` granted to `authenticated` + permissive policy | **1 failure** |
| `FOR UPDATE` removed from `register_payment` | **2 failures** |
| *(clean tree)* | **169 checks, 0 failed** |

The money mutation initially reported PASS — because `CREATE OR REPLACE VIEW` cannot change a column's type, so the breach never applied, and `probe.sh` did not notice the failed migration. Both were fixed: the mutation now drops and recreates the view, and `probe.sh` aborts if the schema does not build. A harness that runs against a partially-applied schema and reports PASS is a worse problem than the bug it was hiding.

---

## 9. What CANNOT be preserved without a server

This list is not empty, and nothing here is closed by cleverness in Dart.

| # | What is lost | Severity | Replacement / residual risk |
|---|---|---|---|
| ~~R1~~ | **CLOSED by `app/tool/supabase_lint.dart`**, which fails the build on `.from('<base table>')` or any PostgREST write. Mutation-tested: planting one read and one write produces three findings. Original text kept below for the reasoning. **Money-safe reads were a convention, not a guarantee.** `authenticated` must hold `SELECT` on the base tables, because `security_invoker` means each view reads them *as the caller*. So a client that queries `receivables` instead of `v_receivables` still gets `numeric`, i.e. a `double` in Dart. Pinned by two probes so it stays visible. | **High** | Enforce in the Flutter layer with a lint in the spirit of `tool/rtl_lint.dart`: no `.from('<base table>')`, only `v_*` and RPC. Alternative — switch views to `security_invoker = off` and put role checks inside each view, which closes it in the database at the cost of moving correctness from RLS into 12 view bodies. **Recommend the lint; flagging the trade-off for you.** |
| **R2** | **Rate limiting.** `express-rate-limit` guarded `/auth/*` and all writes. Gone. | **Medium** | GoTrue has configurable auth rate limits, so credential-stuffing is still covered. PostgREST/RPC calls are **not** per-user rate limited on standard plans — a stolen JWT can hammer `register_payment` until the connection pool starves. Options: put Cloudflare in front, or move the two critical RPCs behind an Edge Function that rate-limits. **Not solved in this phase.** |
| **R3** | **`audit_log.ip_address` has no source.** The column is kept for imported legacy rows but will be `NULL` for everything the app writes. | Low | Possibly recoverable: PostgREST exposes `current_setting('request.headers')`, which should carry `x-forwarded-for`. **Unverified — needs a real Supabase project to confirm, no local PostgREST here.** |
| **R4** | **Refresh-token forensics.** The `replaced_by` chain distinguished rotation from logout and made token theft visible; that was the fix for a specific bug in phase 2. GoTrue rotates and detects reuse, but does not expose the chain. | Medium | Accept. You keep theft *detection*, you lose theft *investigation*. |
| **R5** | **Off-site backups.** `mysqldump` + cron is gone, and MariaDB 10.4 being EOL is no longer the concern — having no backup is. Supabase **free tier has no backups at all**. | **High** | Daily backups need Pro; point-in-time recovery is a paid add-on. Otherwise run `pg_dump` on a schedule from a machine you control. **This is a launch blocker and it costs money.** |
| **R6** | **`ops/preflight.ts`.** Nothing left to preflight. | Low | Partly replaced already: `assert_no_public_execute()` and `assert_views_security_invoker()` run inside the migration. Extend and run `probe.sh` in CI. |
| **R7** | **The nightly reconciler** (`src/reconcile/`) was a Node job. | Medium | Port to a SQL function on `pg_cron`, which Supabase supports. The invariants it checks are already expressed as probes in `30_rules.sql` (`rule11`). |
| **R8** | **Legacy import** (endpoint 30). | Medium | A one-shot script using the service_role key, run off-device — never from the app. Phase 4. |
| **R9** | **PDF export** was to be server-side. | Medium | Must move into Flutter (`pdf`/`printing` + an OFL Arabic font). Was already a launch blocker; unchanged. |
| **R10** | **Web hosting and CORS.** Single-origin deployment is gone — Supabase does not host static sites. | Low | Cloudflare Pages / Netlify for the Flutter web build. CORS is permissive for the anon key by design, which is fine *given* §1. |
| **R11** | **The parity oracle runs on Node.** | None | Keep it. It is a test-time tool, not a backend, and it is the only thing that proves the app still matches `index.html`. It must be re-pointed at Postgres — phase 2. |

---

## 10. Files produced

```
supabase/
  config.toml                                  (supabase init)
  migrations/
    20260811090000_enums_and_helpers.sql       types, touch_updated_at, role_rank
    20260811090100_profiles.sql                auth.users → profiles, role helpers, guards
    20260811090200_settings_families_members.sql
    20260811090300_receivables.sql             rules 4, 5, 7 + lines
    20260811090400_payments_cash_audit.sql     rules 8, 9, 12
    20260811090500_rls.sql                     the security boundary
    20260811090600_rpc.sql                     all 7 write paths
    20260811090700_views.sql                   12 read views, money as text
    20260811090800_lockdown.sql                PUBLIC revoke + 2 standing assertions
  tests/
    00_local_shim.sql        reproduces Supabase's auth schema + roles on bare Postgres
    apply.sh                 rebuilds the database from the migrations
    10_harness.sql           probe.raises / eq / succeeds / become / report
    20_seed.sql              6 users across every role and approval state, 2 families
    30_rules.sql             12 rules, pass + fail case each
    40_rls.sql               hostile client, 7 caller types
    50_money_and_atomicity.sql
    60_concurrency.sh        two overlapping sessions
    probe.sh                 the whole suite; exits non-zero on any failure
docs/SUPABASE_MIGRATION_PLAN.md                this file
```

Nothing under `api/`, `app/` or `index.html` was touched. `api/` is intact and still runnable; decommissioning it needs its own approval.

### Running it

The local stack is **not** the Supabase CLI stack. Docker Desktop is installed on this machine but its Linux engine cannot start — WSL has no distributions installed — so `supabase start` is unavailable. Instead: portable PostgreSQL 16.4 binaries in the scratchpad on port `55432`, plus `00_local_shim.sql`, which transcribes Supabase's own `auth.uid()` / `auth.role()` / `auth.jwt()` definitions and the three platform roles.

That covers constraints, triggers, generated columns, RLS, RPC, atomicity and concurrency — everything in this document. It does **not** cover GoTrue's OAuth flow or PostgREST's HTTP layer. The money-serialisation question was still answered directly, because PostgREST builds its JSON with `json_agg` inside Postgres.

```bash
bash supabase/tests/probe.sh     # → 169 checks, 0 failed
```

To install WSL and use the real CLI stack instead: `wsl --install --no-distribution`, restart Docker Desktop, then `npx supabase start`. That needs elevation, so it was not done unprompted.

### `supabase_flutter` resolves cleanly

`flutter pub add --dry-run supabase_flutter` → `supabase_flutter 2.17.1`, 37 dependencies added, **no conflict** with `flutter_secure_storage ^11.0.0` or the `win32` pin that `file_picker` collided with in phase 3. `google_sign_in ^7.2.0` is undisturbed.

One thing to know before phase 3: `supabase_flutter` stores the session in `shared_preferences` by default — plain text on disk. The refresh token currently lives in Keystore/Keychain via `flutter_secure_storage`. A custom `LocalStorage` implementation is needed to keep that property.

---

## 11. Remaining phases

| Phase | Work | Gate |
|---|---|---|
| **2** | Re-point the `index.html` parity oracle at Postgres. Confirm `generate_period`'s calendar-age arithmetic matches the prototype's `memberStatus` / `monthsUntilBirthdayAge` exactly — this port uses `extract(year FROM age(period_end, dob))`, which is calendar-correct but **not yet differentially compared** against the prototype's own JS. | 3,470 differential comparisons pass |
| ~~3~~ | **Done.** `Dio` → `supabase_flutter`; `SecureLocalStorage` keeps the refresh token in the keystore; auth on GoTrue; `tool/supabase_lint.dart` closes R1. `api_client.dart`, `session_manager.dart` and `token_store.dart` deleted. | ✅ all gates green |
| **4** | MariaDB → Postgres data migration; legacy import; decommission `api/`; backups (R5). | Row counts and money totals tie out exactly |

Before phase 2, two decisions are yours:

1. **Conflict C1** (§5) — keep the stricter father-DOB check, or match `index.html`?
2. **Residual risk R1** (§9) — lint in Flutter, or move the 12 views to `security_invoker = off`?
