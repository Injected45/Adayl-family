# Operations runbook — جمعية العائلة

Everything an administrator needs to run the system day to day. See
[`MIGRATION_PLAN.md`](MIGRATION_PLAN.md) for the architecture and
[`../api/README.md`](../api/README.md) for development setup.

All commands run from `api/`. For first-time deployment see
[`DEPLOYMENT.md`](DEPLOYMENT.md).

---

## Daily

| | |
|---|---|
| `npm run backup` | Dump the database and prune old dumps |
| `npm run reconcile` | Check the ledger adds up; exits non-zero on any breach |

Both are safe to schedule and both exit non-zero on failure, so a scheduler can
alert on them.

**Windows Task Scheduler** — one task per command, daily:

```
Program:   C:\Program Files\nodejs\npm.cmd
Arguments: run backup
Start in:  D:\forward\rhalla\Family_App\api
```

**cron**, if the server is Linux:

```cron
15 2 * * *  cd /srv/family-app/api && npm run backup   >> /var/log/family-backup.log 2>&1
30 2 * * *  cd /srv/family-app/api && npm run reconcile >> /var/log/family-reconcile.log 2>&1
```

### What the reconciler checks

Ten invariants the schema cannot express on its own — that each receivable's
`paid` equals its live allocations, that lines sum to the total, that every
approved payment has exactly one approved cash movement, that a cancelled
payment leaves no live cash, that no family has two live receivables for one
period, that statuses agree with amounts, and that the treasury equals
collections. If it ever fails, **stop and investigate before taking more
payments** — something has diverged and further activity makes it harder to
unwind.

---

## Weekly: prove the backups work

```bash
npm run restore-test
```

A backup nobody has restored is not a backup. This restores the newest dump into
a throwaway database, checks the row counts came back, checks all **10 triggers**
and **3 generated columns** survived, confirms a `DELETE` on the restored copy is
still refused, runs the reconciler against it, and drops it. The live database is
never touched.

The trigger check matters more than it looks: triggers carry business rules 5
(receivables are immutable) and 9 (nothing financial is deleted). A dump that
restored the data but not the triggers would give a database that silently
permits what this one forbids — a successful-looking restore that has quietly
lost the rules.

Retention defaults to 14 dumps (`BACKUP_RETENTION`). **Copy them somewhere other
than the server**; a backup on the same disk as the database protects against
almost nothing.

---

## Hardening the database account

Development runs as `root` with no password, which is XAMPP's default and fine on
a laptop. Before this touches real data, create a least-privilege account:

```bash
npm run print-grants
```

It prints ready-to-paste SQL with a freshly generated password. It **prints
rather than executes** — creating a MySQL user changes the whole server, not just
this database, and on a shared instance that should be deliberate.

The grants deliberately withhold two things:

- **No blanket `DELETE`.** Rule 9 says nothing financial is ever hard-deleted.
  Triggers enforce that against anyone with a SQL console, but the application
  account should not even hold the privilege, so a bug cannot reach for it.
  `DELETE` is granted only on `members` (removing a son, which the prototype also
  does — the financial history survives in the snapshotted receivable lines) and
  `refresh_tokens` (pruning expired sessions).
- **No `DROP`,** so `TRUNCATE` is impossible. This means the *forced re-import*
  path cannot run as the application user — which is intended. Cutover is a CLI
  operation run once with administrator credentials, not something the running
  app can do.

Verify afterwards that this fails:

```sql
DELETE FROM family_app.payments LIMIT 1;
```

---

## Cutover: importing the association's existing data

Full detail in [`../api/README.md`](../api/README.md). In short:

```bash
npm run backup                                        # first, always
npm run import-legacy -- ../backup.json --dry-run     # validates, writes nothing
npm run import-legacy -- ../backup.json
```

Then **compare the treasury total it prints against what `index.html` shows on
its الصندوق screen**. If they differ the migration has failed whatever else
succeeded — restore and investigate.

Keep `index.html` untouched and available read-only until the new system has run
a full billing month.

---

## Release builds

```bash
cd ../app
flutter build web --release
flutter build appbundle --release          # what you upload to Google Play
flutter build apk --release --split-per-abi # for direct install
```

Current sizes: web bundle ~3.5 MB, app bundle ~43 MB, per-ABI APKs 17–20 MB
(a device downloads one of those, not the 53 MB fat APK).

### Signing

Release signing reads `android/key.properties`, which is gitignored along with
the keystore. Copy `android/key.properties.example` and follow the instructions
in it. Without that file the release build falls back to debug keys so
`flutter run --release` still works — but a store upload needs the real keystore.

**Keep the keystore backed up and outside the repository.** If it is lost, the
app can never be updated on Google Play under the same identity.

**Register the release certificate's SHA-1 with your Google OAuth client** as
well as the debug one, or sign-in works in development and fails in the store
build. This is the single most common cause of "it worked yesterday".

---

## Configuration worth reviewing before production

| Setting | Default | Change it when |
|---|---|---|
| `TRUST_PROXY` | `0` | The API sits behind nginx/Cloudflare. Leave at 0 otherwise — trusting a forwarded header nothing sets lets a caller spoof their address and bypass rate limiting |
| `CORS_ORIGINS` | `*` | Always, in production: list the web app's real origin |
| `AUTH_RATE_LIMIT` | 20/min | Rarely |
| `WRITE_RATE_LIMIT` | 120/min | If a legitimate burst of payments is being throttled |
| `NODE_ENV` | `development` | Set to `production`: it enables HSTS and blocks `db:reset` |
| `JWT_SECRET` | — | Rotate it and every session ends. That is the emergency "sign everyone out" lever |

---

## Still outstanding

Three things are not done, and none of them can be finished without a decision or
a file from the association:

1. **Google OAuth client IDs.** Nobody can sign in until these exist.
   Walkthrough: [`GOOGLE_SIGNIN.md`](GOOGLE_SIGNIN.md).
2. **Hosting and off-site backups** — open decision D1 in the plan. Every
   realistic option implies a paid service, which was left to the association.
   Note that **MariaDB 10.4 is end-of-life** (risk R13) and should not be what
   production runs on merely because XAMPP ships it.
3. **PDF export** for statements, receipts and reports. Blocked on an
   openly-licensed Arabic font in `app/assets/fonts/` — Noto Naskh Arabic, Amiri
   or Cairo. The `pdf` package ships no Arabic glyphs, and Tahoma (which the
   prototype's CSS names) is a Microsoft font that cannot be redistributed.
