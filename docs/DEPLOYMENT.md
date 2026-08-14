# Deployment — جمعية العائلة

Two paths. **Path A** publishes from the machine you already have, in about an
hour, with no static IP and no port forwarding. **Path B** is a proper server,
better long-term, more setup.

Either way, the API serves the built web app from the **same origin**. That means
one hostname, one process, no CORS, and one thing exposed to the internet.

Before you start: `npm run preflight` in `api/` lists exactly what is not ready.
Run it again at the end; it exits non-zero while any blocker remains.

---

## Path A — Cloudflare Tunnel from your existing machine

You need a domain on Cloudflare (a free plan is enough). Cloudflare terminates
TLS and reaches your machine through an outbound tunnel, so nothing is exposed
directly and no firewall change is needed.

### 1. Replace MariaDB 10.4

It reached end of life in June 2024 and receives no security patches. Install
**MySQL 8** alongside XAMPP (it can use port 3307 to avoid a clash) or upgrade to
a supported MariaDB. The schema needs no changes — every construct it relies on
was verified against both.

Create the database, then the least-privilege account:

```sql
CREATE DATABASE family_app CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

```bash
cd api
npm run print-grants     # prints SQL with a generated password — paste it
```

### 2. Build the web app

```bash
cd app
flutter build web --release \
  --dart-define=API_BASE_URL=/api/v1 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<your WEB client id> \
  --dart-define=GOOGLE_CLIENT_ID=<your WEB client id>
```

`API_BASE_URL=/api/v1` is the point of single-origin: a relative path, so the app
calls whatever host it was served from and there is nothing to reconfigure if the
hostname changes.

### 3. Configure the API

```bash
cd api
cp .env.production.example .env
```

Fill in: the database account from step 1, a fresh `JWT_SECRET`, your Google web
client ID, and:

```
TRUST_PROXY=1
WEB_ROOT=../app/build/web
CORS_ORIGINS=https://jamiya.example.ly
MYSQLDUMP_PATH=C:/Program Files/MySQL/MySQL Server 8.0/bin/mysqldump.exe
MYSQL_CLIENT_PATH=C:/Program Files/MySQL/MySQL Server 8.0/bin/mysql.exe
```

`TRUST_PROXY=1` matters: Cloudflare forwards the real client address in a header,
and without this every visitor shares one rate-limit bucket.

### 4. Migrate and import

```bash
npm run migrate
npm run import-legacy -- ../your-backup.json --dry-run
npm run import-legacy -- ../your-backup.json
```

**Compare the treasury figure it prints against what `index.html` shows on its
الصندوق screen.** If they differ, stop and investigate.

### 5. Install the tunnel

```powershell
winget install --id Cloudflare.cloudflared
cloudflared tunnel login
cloudflared tunnel create family-app
cloudflared tunnel route dns family-app jamiya.example.ly
```

Copy `ops/cloudflared/config.example.yml` to
`%USERPROFILE%\.cloudflared\config.yml`, fill in the tunnel UUID and hostname,
then install it as a service so it survives a reboot:

```powershell
cloudflared service install
```

### 6. Register the scheduled tasks

```powershell
cd ops\windows
.\install-tasks.ps1              # dry run — prints what it would create
.\install-tasks.ps1 -Execute     # from an elevated prompt
```

That creates three tasks: the API at boot with restart-on-failure, a nightly
backup, and a nightly reconciliation.

### 7. Point Google at the real origin

In the Google Cloud console, add `https://jamiya.example.ly` to your web client's
**Authorised JavaScript origins**. Sign-in fails until you do.
Full walkthrough: [`GOOGLE_SIGNIN.md`](GOOGLE_SIGNIN.md).

### 8. Verify

```bash
cd api
npm run preflight        # must exit 0
npm run restore-test     # prove the backups restore
```

Then open the site, sign in — **the first sign-in becomes the administrator** —
and approve everyone else from the المستخدمون screen.

---

## Path B — A small VPS

€4–6/month at Hetzner or Contabo. Ubuntu 24.04, Node 22+, MySQL 8, Caddy for
automatic TLS.

```bash
sudo adduser --system --group --home /srv/family-app familyapp
# copy the project to /srv/family-app, then:
cd /srv/family-app/api && npm ci --omit=dev
```

`.env` as in Path A, but with `TRUST_PROXY=1` (Caddy), `WEB_ROOT=../app/build/web`
and the Linux binary paths (`mysqldump`, `mysql` are on PATH).

Caddyfile — two lines get you TLS:

```
jamiya.example.ly {
    reverse_proxy localhost:3000
}
```

Then the units from `ops/linux/`:

```bash
sudo cp ops/linux/family-app-*.service ops/linux/family-app-*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now family-app-api
sudo systemctl enable --now family-app-backup.timer family-app-reconcile.timer
systemctl list-timers 'family-app-*'
```

Build the web app on your machine and copy `app/build/web` across — a VPS that
small should not be running the Flutter toolchain.

---

## Updating later

```bash
cd app && flutter build web --release --dart-define=...   # rebuild
cd ../api && npm run backup && npm run migrate            # backup, then migrate
# Windows:  Restart-ScheduledTask -TaskName FamilyApp-API
# Linux:    sudo systemctl restart family-app-api
```

Back up **before** migrating, never after. `index.html` never gets no-cache
wrong, so browsers pick up a new build on the next load.

---

## If something goes wrong

| Symptom | Look at |
|---|---|
| Sign-in fails on the real site | The origin is missing from the Google client's authorised list |
| Sign-in works on localhost only | Same — plus Google refuses non-HTTPS origins |
| Everyone is rate limited at once | `TRUST_PROXY` is 0 behind a proxy, so all clients share one bucket |
| A caller seems to bypass rate limits | `TRUST_PROXY` is too high; the forwarded header is being spoofed |
| Nobody can be made administrator | A placeholder user occupies `users`. `npm run preflight` names it |
| `reconcile` exits non-zero | **Stop taking payments** and investigate. Continuing makes it harder to unwind |
| The app shows stale data after a deploy | Hard-refresh once; `index.html` is `no-cache` but a proxy may have cached it |

Day-to-day operations, backups and the grants are in
[`OPERATIONS.md`](OPERATIONS.md).
