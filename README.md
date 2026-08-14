# مشروع جمعية العدايل — Adayl Family Association

A Flutter app on Supabase for the Adayl family association: member directory,
monthly subscription receivables, payment collection with FIFO allocation, a
treasury ledger, and an append-only audit trail. Arabic, right-to-left.

It began as `index.html` — a single-file React prototype using `localStorage`.
That file is still in the repository, unmodified, because it remains the
behavioural reference: the twelve business rules were transcribed from it and are
verified against it.

---

## The one thing to understand first

**There is no server.** The app talks to Supabase directly, and the anon key ships
inside the APK and in plain text in the web bundle. It is not a secret and cannot
be made one — anyone who installs the app can extract it and issue their own
PostgREST calls from curl.

So every business rule, every role check and every money invariant is enforced
**inside PostgreSQL** — by RLS policies, CHECK constraints, triggers, generated
columns, and `SECURITY DEFINER` functions. Validation in Dart is a convenience for
the user and counts for nothing.

That single constraint explains most of the design:

| | |
|---|---|
| **Reads** | Direct PostgREST against `v_*` views, gated by RLS on the caller's role |
| **Writes** | Only through eleven `SECURITY DEFINER` functions. `authenticated` holds no INSERT/UPDATE/DELETE on any table, and no table has a write policy |
| **Why** | A policy can only judge the row in front of it. It cannot know that this insert into `payment_allocations` is the third of five that must all land or none. A function body is one transaction |

**Money is text end to end.** Postgres serialises `numeric` as a bare JSON number,
and `dart:convert` decodes that to `double`. Every amount is cast to text in SQL,
and `app/tool/supabase_lint.dart` fails the build if Dart ever reads a base table
directly, because that path returns floats.

---

## This is a fork, and it is not configured yet

It shares a codebase with the الرحالة association's app, and **every credential
has been removed** — the Supabase URL, the anon key, the dev-login password and
the Google client ID. A fresh clone therefore talks to nothing, on purpose: this
association keeps its own books, and pointing two apps at one database would
merge two treasuries into one set of figures.

Before it will run you need, in this order:

1. **Your own Supabase project.** Apply `supabase/APPLY_TO_SUPABASE.sql` — one
   transaction, self-verifying. `docs/SUPABASE_SETUP.md` covers it, including
   getting the first administrator in.
2. **URL + anon key** into `run_emulator.bat` (and `app/run_supabase.sh` for
   web). The script refuses to launch until you do, rather than starting and
   failing every call with a network error.
3. **Google sign-in**, optional at first — `docs/GOOGLE_SIGNIN.md`. Note the
   Android OAuth client must be registered against **this** app's package name,
   `ly.adayl.family_app`, not the original one.

The application ID differs from the original deliberately, so both apps can be
installed on one device and neither can receive the other's sign-in callback.

---

## Running it

```bash
# Android emulator, against Supabase
run_emulator.bat                 # or: run_emulator.bat --list | --release

# Web
cd app && bash run_supabase.sh
```

Both scripts carry the project URL and anon key. Google sign-in needs the provider
enabled in the Supabase dashboard; until then use the dev sign-in button, which is
an ordinary email/password account with **no** special privilege — its role still
comes from `public.profiles` like everyone else's.

Google sign-in: `docs/GOOGLE_SIGNIN.md` walks through it end to end. The short
version is that the app uses `signInWithIdToken`, so you need an Android OAuth
client (package name + signing SHA-1) *and* a web one, and the **web** client ID
is the one the app is built with.

New installs: see `docs/SUPABASE_SETUP.md`. It covers applying the schema
(`supabase/APPLY_TO_SUPABASE.sql`, one transaction, self-verifying), enabling
Google, and getting the first administrator in — which needs a deliberate manual
step, because every profile is created `viewer`/`pending` and the first person has
nobody to approve them.

---

## Verification

Nothing here is asserted without an executable check.

```bash
bash supabase/tests/local_pg.sh start      # provisions a local PostgreSQL
bash supabase/tests/probe.sh               # 257 checks
python supabase/tests/verify_live.py <pw>  # 58 checks over HTTPS; SEE BELOW
cd app && flutter test                     # 121 tests
cd app && dart run tool/rtl_lint.dart
cd app && dart run tool/supabase_lint.dart
cd app && flutter analyze
```

**`probe.sh`** runs every one of the twelve business rules against a real
PostgreSQL with a passing case *and a failing case*. The failing case is the only
one that proves anything — a probe that inserts a valid row shows the column
exists, not that the rule bites. It also races two real psql sessions against one
balance to prove the FIFO allocation cannot double-spend, and injects a failure
after the allocations are written to prove the whole transaction rolls back.

**`verify_live.py`** seeds its own starting state, which means it **erases every
payment, receivable, cash movement and audit entry in the project it points at**.
It refuses once the project holds more than the one fixture family unless you
pass `--reset`. Never point it at a project with real figures in it. It is the
layer the local suite cannot reach: PostgREST's status
codes, GoTrue's JWT, and the actual JSON encoding. A privilege-escalation bug
(`write_audit` callable by any signed-in user) passed every local check and was
caught only here — see §8.4 of `docs/SUPABASE_MIGRATION_PLAN.md`.

**`app/test/supabase_contract_test.dart`** parses real wire JSON captured from
PostgreSQL by `supabase/tests/extract_fixtures.sh`. Rename a view column and the
models stop parsing there, before anyone runs the app.

Both layers are needed. The local suite proves the SQL; only the live run proves
the platform.

---

## Layout

```
index.html                     the original prototype — the parity oracle
app/                           the Flutter app
  lib/core/supabase/           client, secure session storage, error mapping
  lib/core/config/             theme + the glass/flat design system
  lib/features/*/data/         four repositories: views for reads, RPC for writes
  tool/rtl_lint.dart           no physical left/right; no Arabic outside l10n
  tool/supabase_lint.dart      no base-table reads; no PostgREST writes
supabase/
  migrations/                  the schema, in order
  APPLY_TO_SUPABASE.sql        all of it in one transaction, for a fresh project
  bootstrap_first_admin.sql    the first administrator, by hand, on purpose
  tests/                       probe suite, fixtures, live verification
docs/
  SUPABASE_SETUP.md            how to stand up a project
  GOOGLE_SIGNIN.md             enabling Google sign-in, and why it fails
  SUPABASE_MIGRATION_PLAN.md   what each piece became, and what was lost
  MIGRATION_PLAN.md            the original Node/MySQL plan, for history
```

The retired Node/Express + MySQL tier is **not** in this repository. Nothing in the
app points at it — reads go to PostgREST views, writes to RPC, auth to GoTrue — and
it is kept locally only until the MariaDB data is migrated.

---

## Security notes for anyone reading this repository

Deliberately committed, and worth knowing:

- **`run_emulator.bat` and `app/run_supabase.sh` contain the Supabase URL and anon
  key.** Public by design; see the top of this file.
- **`run_emulator.bat` also contains the dev-login password**, and that account is
  an approved **admin** on the live project. **This repository is public, so treat
  that password as compromised and rotate it** — Supabase dashboard →
  Authentication → Users. It is in git history; deleting the line is not enough.
- The **`service_role` key and the database password are NOT in this repository**,
  and must never be. `service_role` bypasses RLS entirely.

Outstanding, tracked in `docs/SUPABASE_SETUP.md` §7: backups (the Supabase free
tier has none at all), and per-user rate limiting on the RPCs.
