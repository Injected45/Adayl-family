# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter app on Supabase for a Libyan family association (جمعية العدايل): a
register of عدايل, monthly subscription receivables, FIFO payment collection
with a prepaid wallet, a treasury ledger with money going OUT as well as in
(نظام الصرف), and an append-only audit trail. **Arabic, right-to-left, forced
locale.** The Flutter project lives in `app/`; the database lives in `supabase/`.

## The عديل is the unit, and the family is gone

Every عديل is billed in his own right, for the same monthly fee, and **age
decides nothing**. There is one `adeels` table where there were `families` +
`members`, one `member_fee` where there were `father_fee` + `son_fee`, and
membership status (نشط / موقوف / متوفى) is the ONLY thing that gates a charge.

What that removed, deliberately and completely:

- the `member_kind` enum, the one-father-per-family index, and the father/sons
  shape of `save_family` (now `save_adeel`, one row per call);
- **the national ID, everywhere** — and with it rule 10's uniqueness half.
  `adeels` now has **no natural key**: nothing refuses a second row for a person
  already on the register, and a duplicate is billed the monthly fee a second
  time. `adeel_code` is GENERATED from the identity, so it does not close that.
  `supabase/tests/30_rules.sql` asserts the duplicate is accepted rather than
  leaving it to be discovered; if a UNIQUE constraint is ever added back
  (`subscription_no` is the ready candidate), that check is the one that fails
  and tells you the guarantee returned;
- `receivable_lines` — a receivable bills one man for one month, so the rate IS
  the total and a line table would always hold exactly one row;
- `eligibility_age` and `warning_months`, and with them the whole
  مستحق / قريب من السن / غير مستحق concept: the eligibility badge, the
  "approaching age" dashboard panel, and the age alert.

`index.html` at the repo root is the original single-file React/localStorage
prototype, kept unmodified. It is **no longer the parity oracle for billing** —
it still encodes father/son fees and the age gate, which the association
abandoned. It remains useful for the rules that did not change (FIFO collection,
cancellation, the treasury, the audit trail); for anything about who is charged
and how much, this file and `supabase/tests/` are the source of truth.

## The one architectural fact everything follows from

**There is no server.** The app talks to Supabase directly. The anon/publishable
key ships inside the APK and the web bundle — it is public by design, not a secret,
and cannot be made one. Therefore **every business rule, role check, and money
invariant is enforced inside PostgreSQL** (RLS policies, CHECK constraints,
triggers, generated columns, `SECURITY DEFINER` functions). Validation in Dart is
UX convenience and counts for nothing.

This dictates the data-access shape — do not deviate from it:

- **Reads** → direct PostgREST against `v_*` views (or `api_*` functions), gated by
  RLS on the caller's role. Never read a base table.
- **Writes** → only through the fourteen `SECURITY DEFINER` RPC functions below. The
  `authenticated` role holds no INSERT/UPDATE/DELETE on any table and no table has a
  write policy, because a payment is not one row — registering it inserts a payment,
  N allocations, N receivable updates, and a cash movement, all-or-nothing. A
  function body is one transaction; a PostgREST call is not.

  The fourteen RPCs (in `supabase/migrations/…_rpc.sql`): `register_payment`,
  `cancel_payment`, `generate_period`, `auto_close_periods`, `save_adeel`,
  `delete_adeel`, `update_settings`, `set_user_access`, `purge_financial_data`,
  `purge_all_data`, `issue_adeel_code`, `redeem_adeel_code`,
  `register_disbursement`, `cancel_disbursement`. (`write_audit` and
  `settle_from_credit` exist but are called by triggers and by other RPCs, never
  by the client.)
  `20260811091200_function_lockdown.sql` holds the allow-list and asserts it is
  EXACT — a function added without being listed there is unreachable, and one
  listed but ungranted fails the migration.

  **Closing a month is a one-way, in-order act (rule 15).** `generate_period`
  raises one receivable per نشط عديل and then records the month in
  `closed_periods`. Three refusals guard it, all `RUL15`: **15c** the month must
  fall between `system_start` and last month (the future and the pre-history are
  both out); **15a** it must not already be closed; **15b** no earlier month may
  still be open.

  `closed_periods` is a table rather than an inference from the receivables
  because a month that bills nobody — every عديل موقوف, or the register still
  empty — raises zero rows. Read "closed" off the charges and that month looks
  permanently open, and 15b then blocks every month after it forever.

  `api_closable_periods()` returns each month with `closed` and `selectable`,
  where `selectable` is true for exactly one row: the earliest open month. The
  Dart picker only paints those flags — recomputing 15b client-side would be a
  second implementation of a money rule, free to disagree with the one that
  actually decides.

  `delete_adeel` is the escape hatch for a mistyped entry: it refuses the moment
  he has any receivable or payment, because a receipt must never point at
  nobody. Retiring someone with a ledger is a status change, not a deletion.

  The two purges are the other way to hard-delete anything. Both are admin-only,
  both TRUNCATE with `RESTART IDENTITY`, and each refuses without its own typed
  phrase from `PurgeWire` — `مسح نهائي` and `مسح كل البيانات`. Neither phrase
  satisfies the other function, which is the entire reason there are two rather
  than one with a flag, and `supabase/tests/70_purge.sql` asserts that in both
  directions.

  - `purge_financial_data` takes the six financial tables (receivables,
    payments, payment_allocations, cash_movements, `closed_periods` **and
    audit_log**) and leaves adeels, settings and profiles standing.
    `closed_periods` has to go with them: leave it and every month is still
    marked closed while no receivable exists for it, so rule 15a refuses to
    re-raise any of them and the wiped ledger can never be rebuilt.
  - `purge_all_data` is a strict SUPERSET: those six plus `adeels`. It cannot
    be narrower — every receivable and receipt references an عديل
    `ON DELETE RESTRICT`, so the register cannot go while a receipt survives.
    Settings and staff profiles still survive; wiping profiles would strand the
    association outside its own app.

    Order matters inside it: the TRUNCATE runs BEFORE the profile delete,
    because `receivables.created_by` references profiles `ON DELETE SET NULL`
    and that SET NULL is an UPDATE the rule-5 snapshot trigger rejects.

  TRUNCATE rather than DELETE because it fires no `BEFORE DELETE` trigger, so
  the rule-9 guards never have to be disarmed and no code path can leave them
  off. Both are deliberate holes in rules 9 and 12: after either runs, nothing
  in the database records that it ran. Settings → منطقة الخطر is the only
  caller. `70_purge.sql` runs last because it erases the fixture.

  **The wallet — a member may pay AHEAD.** Rule 7 used to refuse both paying an
  عديل who owed nothing and paying more than he owed. Both are now allowed and
  the surplus is CREDIT. There is no wallet column, deliberately: the credit is
  the part of a payment the FIFO loop could not allocate —
  `Σ payments − Σ allocations` — so it is a view over rows that already exist
  and cannot drift from the money. Spending it means WRITING the missing
  allocation, which is also what puts a prepaid month into the statement beside
  the receipt that settled it. `settle_from_credit` is that spend, and
  `generate_period` calls it per عديل the instant it raises his receivable, so a
  man who paid a year ahead never sees the new month appear as a debt he already
  covered. What this RELAXES: a treasurer who means 500 and types 5000 is no
  longer stopped by the database — the audit entry names the surplus
  («منها 4500 رصيد مقدم») so it is visible afterwards rather than only in the
  arithmetic. What survives is that the amount must be positive and that every
  unit is either allocated or counted as credit.

  **Money OUT — نظام الصرف.** `disbursements` is where money leaves the
  treasury: `voucher_no` generated as `EXP-01`, admin-only (a rung above
  even financeManager), recorded directly with no approval queue, and reversed
  rather than deleted. A voucher takes one of TWO shapes and `ck_disb_shape`
  enforces both halves at once: `لمشترك` names a man on the register and may not
  be `فطور رمضان`; `جماعي` names nobody at all and may not be `مولود`. Both
  carry a وجه from a fixed six-value enum, because "how much went on each" is
  the only question that column exists to answer and free text turns
  عزاء / العزاء / مصاريف عزاء into three answers to it.

  Two rules make it safe, and they are the same rule read from each side.
  `register_disbursement` locks the settings row and refuses to pay out more
  than `Σ cash_movements − Σ disbursements`; `cancel_payment` takes the SAME
  lock FIRST and refuses a cancellation that would leave the fund holding less
  than what has already been spent, naming the value of vouchers to reverse
  first. Without the second, collect 100 → spend 100 → cancel the receipt leaves
  رصيد الجمعية at −100 silently, and every later disbursement is then refused
  for a reason nobody was told.

  ⚠ **A disbursement to an عديل is NOT a credit against his subscription.** It
  never touches receivables, payments or his wallet and never appears in his
  statement. The link exists so "how much aid went to this man" can be answered;
  treating it as a payment would let the association's charity cancel its own
  dues. And it is a SEPARATE table rather than a signed row in `cash_movements`,
  because that table is the mirror of an approved payment — rule 8 gives it one
  row per payment, `uq_cash_payment` forbids a duplicate, its `adeel_id` is NOT
  NULL and the عديل portal reads it as "my receipts". Forcing an outflow in
  would mean a nullable `payment_id`, a widened unique constraint, a sign on
  every existing SUM and an RLS policy that must start distinguishing
  directions — on the one table the working collection path depends on.

  An عديل reads **his own vouchers and nobody else's**. Two policies, ORed by
  Postgres and each readable alone: `read_disbursements` (staff, every row) and
  `read_own_disbursements` (`payee_adeel_id = my_adeel_id()`). A COLLECTIVE
  voucher carries no payee, so `NULL = my_adeel_id()` is NULL and it belongs to
  nobody — فطور رمضان appears under no individual, only in the totals. He also
  sees the association's aggregates through `api_association_finance()`, which
  is `SECURITY DEFINER` on purpose: pointing the portal at `v_cash_summary`
  (SECURITY INVOKER) would have shown him HIS OWN figures under headings that
  say "the association's", which is not a leak but something worse — a wrong
  answer with nothing on screen to doubt.

  **`api_adeel_aid(bigint)` — what the association GAVE one man**, and the rule
  it exists to protect: **الجمعية خيرية, so aid is NOT deducted from what he
  owes.** A man given something for a bereavement still owes that month's fee.
  That is structural rather than a display choice — a voucher writes no
  receivable, no payment and no allocation, and `api_adeel_statement` merges
  exactly those two tables, so aid cannot reach a statement however any screen
  is written. What was missing was the ANSWER to "so where IS it recorded", and
  this is it: a lifetime total, a breakdown by occasion and by year, and the
  vouchers beneath them. SECURITY INVOKER, so staff read any man's and an عديل
  reads only his own; asking about someone else returns an empty answer rather
  than a refusal, so no id is confirmed to exist.

  Its breakdowns list only the occasions he actually received something under —
  unlike `v_expense_by_category`, which lists every heading including the empty
  ones. The difference is the question: "the association spent nothing on فرح
  this year" is an answer; "he was never given anything for a wedding" is not
  one he is missing.

  It returns the vouchers as a **LEDGER: oldest first, each line carrying the
  total so far.** «صُرف له 100 مولود، ثم بعد أشهر 500 فرح» reads 100 then 600.
  That column is a window function — `sum(amount) FILTER (WHERE status <> 'ملغي')
  OVER (ORDER BY spent_at, id)` — for the same reason the statement's running
  balance is one: money is text end to end precisely so nothing accumulates it
  in Dart. FILTER rather than WHERE is what keeps a reversed voucher LISTED
  (rule 9) while leaving its running total identical to the line above, which is
  what a ledger shows for an entry that was reversed.

  In Dart it is a SEPARATE SCREEN (`features/finance/presentation/adeel_aid_screen.dart`)
  reached at `/adeels/:id/aid` by staff and by an imperative `Navigator.push`
  from the portal — the route guard pins a portal account to `/my-dues`, and a
  push changes no location for it to redirect. One screen, `mine` switching only
  the voice. It is not a panel on the detail page and not part of the portal's
  balance hero, because the place this rule would actually be broken is a layout
  that puts «ما صُرف له» beside «ما عليه» and invites the eye to subtract; both
  entry points print the rule in words above the figures. The search box filters
  rows and never sums — the running-total column goes on belonging to the whole
  history, and the panel says how many rows are showing so a jumping balance
  reads as a filter rather than a fault.

- **Money is text end to end.** Postgres serialises `numeric` as a bare JSON number
  and `dart:convert` decodes that to `double`. Every view casts amounts to text, and
  every RPC amount is sent from Dart as a `String` (not a number). Putting a treasury
  on binary floating point is the bug this prevents.

## Two custom lints enforce the invariants the Dart analyzer can't

Run both from `app/`; they exit non-zero on violation and are part of the build gate.

- **`dart run tool/supabase_lint.dart`** — fails if Dart reads a base table (money
  would come back as `double`) or writes through PostgREST (`.insert/.update/.delete`
  instead of an RPC). The base-table list and the RPC-that-replaces-each-write map
  live at the top of the tool.
- **`dart run tool/rtl_lint.dart`** — fails on physical left/right layout
  (`EdgeInsets.only(left:)`, `Alignment.centerLeft`, `TextAlign.left`, etc. — use the
  `Directional`/`start`/`end` variants) and on Arabic string literals in widget code.

**Arabic strings have exactly two homes.** User-facing text → `app/lib/l10n/app_ar.arb`
(the ARB template; `en` is the translation). Arabic *wire values* the DB stores
(statuses, payment methods, relations) → `app/lib/core/domain/wire_values.dart`, the
only file exempt from the Arabic-literal lint. Never inline an Arabic literal
elsewhere.

## Code layout (app/lib)

Feature-first. Each feature under `features/<name>/` has `data/` (repository),
`domain/` (models), `presentation/` (screens + Riverpod providers).

- `features/auth` — Google + dev email/password sign-in, role/approval state.
- `features/directory` — the register (`adeels_screen`), an عديل's detail and
  form, receivables, statements, officials, and the portal.
- `features/finance` — payments, cash/treasury, and الصرف (money out).
  `payments_screen.dart` carries both tabs — التحصيل and الصرف, the latter with
  the voucher list and «الإنفاق حسب الوجه» — and `disbursement_sheet.dart` is
  the voucher form, whose fields switch on the kind. `finance_repository.dart`
  is the canonical example of the read-via-view / write-via-RPC pattern.
- `features/oversight` — dashboard, alerts, reports, audit, settings, users.
- `core/supabase` — client init, secure session storage (refresh token → keystore),
  error mapping (`SupabaseFailures.guard`).
- `core/router` — `go_router` with a single `redirect` guard re-run on every
  navigation, so a demotion/sign-out is applied immediately. `destinations.dart`
  defines routes + per-route `minimumRole`.

**State/routing:** `flutter_riverpod` (screens branch on `AsyncValue.when`) +
`go_router`. **Roles** form a hierarchy `admin ⊇ financeManager ⊇ treasurer ⊇ viewer`
(`features/auth/domain/app_user.dart`); unknown roles fall back to `viewer`. Hiding a
button is presentation — the same check is always re-enforced server-side.

**The عديل portal is a second, disjoint way in.** An عديل signs in with Google,
types the access code an admin issued him, and thereafter sees his own record,
dues, receipts and statement — read-only, nothing of the association's. The
discriminator is `profiles.adeel_id`, deliberately a column rather than a new
`app_role` value (`ALTER TYPE … ADD VALUE` cannot be used in the transaction that
adds it, and the schema applies as one transaction).

The whole separation rests on one clause: **`my_role()` returns NULL once
`adeel_id` is set.** Every staff policy goes through `has_role()`, so an عديل is
excluded from all of them without any being edited; and `my_adeel_id()` is NULL
for staff, so they never match the عديل-scoped policies. Both directions are
asserted in `supabase/tests/45_adeel_portal.sql` — they are silent failure modes,
not visible ones.

**One عديل, one handset.** `profiles.device_id` holds a SHA-256 of the device's
platform id, and `my_adeel_id()` returns NULL unless it equals the
`x-device-id` request header — so the rule sits in the one function every
عديل-scoped policy already goes through, and a client talking to PostgREST
directly is refused by the same clause the app is. NULL is a REFUSAL, not a
pass: "released, not yet claimed" is what an account looks like the instant an
admin reissues a code, and reading it as a pass would make one click an unlock
for every device at once. `api_touch_login` claims an unclaimed device and
never replaces a held one; `api_me` reports `deviceLocked` so the wrong handset
is told why instead of shown an empty portal.

It is **not a MAC address** — Android has returned `02:00:00:00:00:00` to every
app since API 23 and randomises it per network since 10, and iOS never exposed
one. And a header is client-set, so this stops SHARING, not forgery; the code
remains the authorisation.

`issue_adeel_code(bigint)` is admin-only and overwrites (one row each, so
regenerating revokes the old code without signing out anyone already bound). It
also clears `device_id`, which is the only release a lost phone has. It
deliberately leaves `adeel_id` alone: clearing that too would drop the man to a
plain approved viewer — who reads the WHOLE association, because `my_role()`
only returns NULL while an `adeel_id` is set — so the unlock would be a
privilege escalation with a time window.
`redeem_adeel_code(text)` is the one write a signed-in stranger may call: until
he redeems, he has no role and no binding, so the code IS the authorisation. It
refuses anyone already on the staff ladder — an admin who redeemed would set his
own `adeel_id`, lose `my_role()`, and lock himself out with no other guard
noticing. In Dart, `AppUser.isAdeelPortal` pins him to `/my-dues` in the router
guard; `AdeelPortalScreen` reuses `api_adeel_detail` / `api_adeel_statement`
rather than adding portal-only endpoints, because those are SECURITY INVOKER and
RLS already scopes them.

**Google sign-in must be enabled in the Supabase dashboard** for any of this to
work — the dev email/password login is a staff-only convenience.

## Commands (run from `app/` unless noted)

```bash
# Run — scripts carry the public URL + anon key (repo root)
run_emulator.bat                 # Android emulator; --list | --release
cd app && bash run_supabase.sh   # web (chrome); pass a device id as arg 1

# Flutter checks
flutter test                     # widget/unit tests
flutter test test/rtl_test.dart  # a single test file
flutter analyze
dart run tool/rtl_lint.dart
dart run tool/supabase_lint.dart

# Database / SQL verification (from repo root)
bash supabase/tests/local_pg.sh start   # provision a local PostgreSQL
bash supabase/tests/probe.sh            # runs every business rule with a PASS and a FAIL case
python supabase/tests/verify_live.py <db-password>   # PostgREST/GoTrue/JSON layer over HTTPS
```

**`RESET_AND_APPLY.sql` IS NOT GENERATED ANY MORE, and must not be recreated
casually.** It was the same bundle behind a `DROP SCHEMA public CASCADE`
preamble, for converting a project that already holds a schema —
`APPLY_TO_SUPABASE.sql` cannot do that, because `CREATE TYPE` has no
`IF NOT EXISTS` and the first enum aborts with 42710.

On 2026-08-16 it was pasted into the LIVE project. Every عديل, receipt and audit
entry went, and so did `public.profiles` — which is not data but ACCESS:
`auth.users` survives, so signing in still succeeds and then finds no row, no
role and no approval. The association was locked out of its own app, and
`bootstrap_first_admin.sql` had to be run again. Its data guard did not fire,
because it counted RECORDS and the ledger had not started yet.

Two things changed. The guard now counts `profiles` FIRST, so an empty ledger is
no longer read as nothing to lose. And `bundle.sh` no longer writes the file at
all — it DELETES any copy it finds, so one generated earlier cannot survive as a
trap. The capability is kept behind `bash supabase/tests/bundle.sh --with-reset`,
which prints what it is about to produce.

Everything the association actually needs is additive: the `PATCH_*.sql` files
replace function bodies and add columns, touch no row, and each calls
`assert_signin_intact()` before `COMMIT` — so a change that would leave sign-in
broken rolls back instead of landing. Prefer a patch; never reach for a rebuild.

**A patch that creates a function must re-run the lockdown sweep.** On a full
apply, `20260811091200_function_lockdown.sql` runs LAST and normalises grants
across the whole schema, so nothing else has to think about privileges. A patch
gets no such pass. `CREATE OR REPLACE` keeps a function's existing ACL, but a
function created *fresh* — which is what `DROP FUNCTION` followed by `CREATE`
produces, the only way to change a signature — has no ACL to keep, so Postgres
materialises the built-in default (**EXECUTE to PUBLIC**) and Supabase's
`ALTER DEFAULT PRIVILEGES` layers `anon` on top. `assert_no_public_execute()`
catches it and rolls the patch back with a message naming the function rather
than the missing REVOKE, which reads like a defect in the file. Copy the
`DO $lockdown$` loop in after the last `CREATE`, as
`PATCH_20260816_payer_bank_details.sql` §11 does: it recomputes every grant from
the allow-list, so it fixes the next such function without anyone remembering.

`supabase/VERIFY_INSTALL.sql` is the one to paste into a project's SQL Editor
after applying the bundle. Read-only, and it answers the question the apply
itself cannot: the bundle is one transaction so there is no half-applied state
to find, but a project still holding the OLD family/member schema, one where the
bundle was never run, and one where `bootstrap_first_admin.sql` was skipped all
look identical from the app — a login screen that goes nowhere. It names which.

`supabase/WHICH_STATE.sql` is its counterpart for PATCHES, and also read-only.
VERIFY_INSTALL holds a fixed list and asks "did the bundle land"; a project one
patch behind passes it completely — nothing on its list is missing — and is
still the wrong place to paste the next patch into. WHICH_STATE probes each
patch by an object it ADDS (a column, a table, a function), in dependency order,
and its last row says what to do: `READY`, `ALREADY applied`, or `STOP` naming
the prerequisite that is missing. **Run it before proposing any patch for the
live project, and reconstruct the state it reports locally before claiming the
patch is safe** — a bundle from the matching commit plus `local_pg.sh` does this
in minutes, and on 2026-08-18 it is what revealed the live project sitting on an
OLDER build of `PATCH_20260817` (device lock in, نظام الصرف missing) rather than
on nothing at all. Every count in it goes through `query_to_xml()` so that a
missing table cannot kill the script on one of the states it exists to name.

## Testing model — two layers, both required

- **`supabase/tests/probe.sh`** proves the SQL against a real PostgreSQL — 427
  checks. Each rule runs with a passing case *and a failing case* (the failing
  case is what proves the rule bites). It also races two psql sessions on one
  balance to prove FIFO allocation can't double-spend, races two more on the
  treasury to prove the fund cannot be overdrawn by simultaneous vouchers
  (`68_spend_concurrency.sh`), and injects a mid-transaction failure to prove
  rollback. `EXPECTED_CHECKS` at the top of the script must match, so a check
  whose SQL errors before recording anything cannot hide — and the comment above
  it derives the number from the files rather than from what a run reported,
  because fitting it to a run is exactly how the count once certified a
  duplicated suite.

  Rules 1 and 2 are GONE from it, not merely untested — they described the age
  gate. What replaced rule 1 is asserted under `rule03`: a seven-year-old عديل
  in the fixture is billed exactly like the fifty-one-year-old, which is the
  check that fails first if an age gate is ever reintroduced.
- **`supabase/tests/verify_live.py`** proves the layer the local suite can't reach:
  PostgREST status codes, GoTrue JWTs, actual JSON encoding. A privilege-escalation
  bug once passed every local check and was caught only here.
- **`app/test/supabase_contract_test.dart`** parses real wire JSON captured by
  `supabase/tests/extract_fixtures.sh` into `app/test/fixtures/`. Rename a view column
  and the models stop parsing here, before the app runs.

Local suite proves the SQL; only the live run proves the platform. Don't treat one as
covering the other.

## Database is applied as one transaction

`supabase/migrations/` holds the schema in order; `supabase/APPLY_TO_SUPABASE.sql`
bundles all of it into one self-verifying transaction for a fresh project. The first
admin needs a deliberate manual step (`supabase/bootstrap_first_admin.sql`) because
every profile is created `viewer`/`pending` and the first person has nobody to approve
them. See `docs/SUPABASE_SETUP.md`.

## Security notes (deliberately committed)

- `run_emulator.bat` and `app/run_supabase.sh` contain the Supabase URL + anon key —
  public by design.
- `run_emulator.bat` also contains a dev-login password for an **approved admin** on
  the live project. The repo is public: treat that password as compromised, rotate it,
  and do not rely on removing the line (it's in git history).
- The `service_role` key and DB password are **not** in the repo and must never be —
  `service_role` bypasses RLS entirely.
