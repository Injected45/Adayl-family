# Connecting the app to Supabase

**Done.** The schema is applied to project `wvryyidbjvvomurvfhpw` (eu-north-1) and
verified end to end over HTTPS:

```
python supabase/tests/verify_live.py <file-with-the-dev-password>
    → ALL CHECKS PASSED against the live project.   (52 checks)
```

The rest of this file is the runbook — for a second environment, or for rebuilding
this one. §7 lists what is still outstanding.

---

## 1. Create the project

<https://supabase.com/dashboard> → **New project**.

- **Region:** closest to Libya is `eu-central-1` (Frankfurt). Latency matters more than you'd think on a phone.
- **Plan:** Free works, but read the warning in §5 before you rely on it.

Then **Project Settings → API** and copy two values:

| Label in the dashboard | Used as |
|---|---|
| Project URL | `SUPABASE_URL` |
| `anon` / `publishable` key | `SUPABASE_ANON_KEY` |

The **`service_role` key is not needed by the app and must never go near it.** It bypasses RLS entirely. It belongs only to the one-off legacy import in phase 4.

The anon key is *not* a secret — it ships inside the APK and in plain text in the web bundle. That is fine, and it is the premise the whole database design rests on: every rule is enforced by RLS, CHECK constraints, triggers and `SECURITY DEFINER` functions, so a hostile holder of that key can do nothing an honest one could not. §7 of `SUPABASE_MIGRATION_PLAN.md` is the evidence.

---

## 2. Push the schema

The CLI is already vendored via `npx`; **this step does not need Docker**, because `db push` connects straight to the remote database.

```bash
cd D:/forward/rhalla/Family_App
npx supabase@latest login
npx supabase@latest link --project-ref <your-project-ref>
npx supabase@latest db push
```

Eleven migrations, in order. `supabase/tests/` is not pushed — it holds the local harness, including `00_local_shim.sql`, which recreates the `auth` schema and the `anon`/`authenticated` roles that a real project already provides. Pushing it would collide.

### If `db push` fails

**`assert_no_public_execute()` raised an exception.** The most likely first-push failure, and it is the guard working. Something else lives in `public` and is executable by `PUBLIC` — usually an extension installed there rather than in `extensions`. Find it:

```sql
select p.proname, pg_get_function_identity_arguments(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and (p.proacl is null
        or exists (select 1 from aclexplode(p.proacl)
                    where grantee = 0 and privilege_type = 'EXECUTE'));
```

If it's an extension, move it (`alter extension <name> set schema extensions;`). If it's something you added on purpose, add it to the allow-list at the end of `20260811091100_api_reads.sql`. **Do not delete the assertion** — it is what stops a future migration quietly reopening `register_payment` to anonymous callers.

**A trigger on `auth.users` was refused.** `trg_auth_user_created` in `20260811090100_profiles.sql` is what creates a profile row on sign-up. Run that one file from the SQL editor as `postgres` if the push cannot.

---

## 3. Turn on Google sign-in

**Authentication → Providers → Google.** Paste the Client ID and Client Secret from your Google Cloud OAuth client.

The secret goes *here*, in the dashboard — never into the app. This is a straight improvement on the old setup, where the device had to carry three separate Google client IDs; now Supabase verifies the ID token against Google itself.

**Authentication → URL Configuration → Redirect URLs**, add:

```
com.family.app://login-callback
http://localhost:*
```

The first must match `SupabaseConfig.nativeRedirect` and the intent filter in `AndroidManifest.xml`. The second is only for local web development; remove it before you ship.

Keep the Google client IDs in the build too — the device still obtains the ID token itself:

```
--dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>
--dart-define=GOOGLE_CLIENT_ID=<platform client id>
```

`docs/GOOGLE_SIGNIN.md` still describes how to get them; only where the *secret* lives has changed.

---

## 4. Run it

```bash
cd app
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

Build with neither define and the app still starts and says so on the sign-in screen, in English, rather than crashing — the audience for that message is whoever built the binary.

### Getting the first administrator in

`handle_new_user()` creates every profile as **viewer / pending**, so signing in with Google grants nothing until an admin approves it. The first person has no admin to approve them, and `set_user_access()` requires the very role it would be granting. Nobody can get in.

That circle is broken by hand, on purpose — an automatic "first user becomes admin" rule would hand the treasury to whoever found the URL first.

1. Sign in with Google once. You will see **awaiting approval**. That is correct: the sign-in worked and your profile row exists.
2. Open `supabase/bootstrap_first_admin.sql`, put your address at the top, run it in the SQL editor.
3. Reload.

From then on, everyone else is approved from **إدارة المستخدمين** inside the app.

### Development sign-in

Skips Google, but carries **no privilege** — it is an ordinary email/password sign-in, so the account must exist and its role still comes from `public.profiles`. Unlike the server route it replaces, there is nothing to leave switched on in production by accident.

Create the user in **Authentication → Users → Add user** (tick *Auto Confirm*), then:

```
--dart-define=DEV_LOGIN=true
--dart-define=DEV_LOGIN_EMAIL=admin@fam.test
--dart-define=DEV_LOGIN_PASSWORD=<the password you set>
```

---

## 5. Before this holds real money

Three things, and the first is the one that will bite.

**Backups (R5).** The **free tier has no backups at all.** Not "limited" — none. Daily backups need Pro; point-in-time recovery is a further paid add-on. The alternative is your own `pg_dump` on a schedule against the connection string in Project Settings → Database. Either way this costs money or costs a cron job, and "we'll sort it later" means a bad afternoon rewrites the association's entire ledger history with no way back.

**Rate limiting (R2).** `express-rate-limit` is gone. GoTrue still rate-limits *auth*, so credential stuffing is covered, but PostgREST and RPC calls are not per-user limited on standard plans — a stolen JWT can hammer `register_payment` until the connection pool starves. Options: Cloudflare in front, or move the two critical RPCs behind an Edge Function that limits them. **Not solved.**

**`api/` is still on disk and still runnable.** Nothing points at it. Deleting it is phase 4, along with migrating the MariaDB data, and it needs its own decision — right now it is the only copy of the old system.

---

## 6. Verification

### The local test database

The probe suite needs a real PostgreSQL. It cannot use `supabase start`, which
needs Docker — Docker Desktop's Linux engine will not start on this machine
because WSL has no distributions installed. So it uses portable Postgres binaries:
no installer, no admin rights, no Windows service.

```
bash supabase/tests/local_pg.sh start    # provisions on first run, then starts
bash supabase/tests/local_pg.sh status
bash supabase/tests/local_pg.sh stop
bash supabase/tests/local_pg.sh reset    # wipe and re-init
```

First run downloads ~340 MB and unpacks to about 1 GB in
`%LOCALAPPDATA%amily_app_localpg` — outside the project tree, stable per user.
Every path is set in `supabase/tests/_env.sh`; override `PG_HOME`, `PGPORT` and so
on from the environment if you already run Postgres somewhere.

This started out living in the session's TEMP directory, which meant the whole
suite worked exactly once, on one machine, until Windows cleaned TEMP. If a script
cannot find a server it now says which command to run instead of failing with
`could not connect to server`.

**Against that database, running the real migrations:**

```
bash supabase/tests/probe.sh                 → 179 checks, 0 failed
cd app && flutter test                       → 111 tests passing
cd app && dart run tool/supabase_lint.dart   → 63 files, no problems
cd app && dart run tool/rtl_lint.dart        → 59 files, no problems
cd app && flutter analyze                    → No issues found!
cd app && flutter build web --release        → succeeds, with and without credentials
```

The 36 tests in `app/test/supabase_contract_test.dart` parse **real wire JSON**,
captured by `supabase/tests/extract_fixtures.sh` from that database as an
authenticated caller with RLS in force. PostgREST builds its response body with
`json_agg` inside Postgres, so those fixtures are the bytes the app receives.

**Against the LIVE project, over HTTPS, as a real authenticated user:**

```
python supabase/tests/verify_live.py <pwfile>   → 52 checks, all passed
```

Reads, the money path (FIFO across two periods), cancellation-reverses-and-preserves,
the audit trail, the hostile client, and money-never-a-float across every view and
every read function.

**Both layers are needed, and this is not belt-and-braces.** The `write_audit`
exposure in §8.4 of `SUPABASE_MIGRATION_PLAN.md` passed every local check and was
only caught over HTTPS, because it came from Supabase's own default privileges —
something the local shim was not reproducing. The shim reproduces them now, so the
same class of bug fails locally in future. But the general point stands: the local
suite proves the SQL, and only the live run proves the platform.

---

## 7. Still outstanding

| | What | Who |
|---|---|---|
| 1 | **Rotate the `service_role` key.** It was pasted into a chat transcript and used once to create the dev user. Project Settings → API → Reset. | you |
| 2 | **Enable the Google provider** and add `com.family.app://login-callback` to the redirect allow-list (§3). Until then only the dev email/password login works. | you |
| 3 | **Backups.** The free tier has none at all (§5, R5). | you |
| 4 | **Rate limiting** on the RPCs (§5, R2). | open |
| 5 | **Phase 4** — migrate the MariaDB data, then decommission `api/`. | next |

### Test data currently in the project

Verification left one demo family behind: `F-0001` (محمد علي الرحالة, two sons),
receivables for 2026-06 and 2026-07, and one cancelled payment. It is real,
consistent data and the app renders it, which is useful for a first look.

To clear it before real data goes in, note that the financial tables are
append-only by trigger (rule 9) — a plain `DELETE` is refused, by design. Removing
it requires disabling those triggers deliberately, as
`supabase/bootstrap_first_admin.sql` does for one row and re-enables immediately.
The honest options are: leave it, or drop and re-apply the schema from
`supabase/APPLY_TO_SUPABASE.sql` for a clean slate before go-live.
