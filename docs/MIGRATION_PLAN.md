# خطة الترحيل — Migration Plan
### `index.html` (React prototype, localStorage) → Flutter client + REST API + MySQL 8

> **Source of truth read:** `index.html`, 734 lines, read in full.
> **Version caveat:** every package version below is a starting constraint, not a verified current release. Re-check each on pub.dev / npm at the start of each phase and pin the actual resolved versions in the lockfiles.

### Implementation status

| Phase | State |
|---|---|
| 1 — Database foundation | ✅ **Complete.** 12 tables, 10 triggers, 3 generated columns in `api/`. `npm run verify:phase1` passes 30/30. |
| 2 — Authentication and users | ✅ **Complete.** 7 endpoints, Google token verification, rotating refresh tokens with reuse detection, role guard. `npm run verify:phase2` passes 38/38. |
| 3 — Flutter shell and sign-in | ✅ **Complete.** Arabic RTL app in `app/`, responsive shell, sign-in / pending / suspended / forbidden screens, transparent token refresh. `flutter analyze` clean, 27 tests, RTL lint clean, release builds for web and Android. |
| 4 — Read-only domain | ✅ **Complete.** 8 read endpoints plus the families, family-detail, members, receivables, statements and officials screens. `npm run verify:phase4` passes 20/20, including 3,470 differential comparisons against the prototype's own extracted code. |
| 5 — Financial engine | ✅ **Complete.** Receivable generation, auto-close, FIFO payment registration, reversal and the treasury ledger, plus the payments, payment-sheet and cash screens. `npm run verify:phase5` passes 22/22, including a 1,000-operation property test and a real concurrency race. |
| 6 — Reporting and oversight | ✅ **Complete.** Dashboard, alerts, reports, audit trail, settings, user management and the family create/edit form, plus the nightly reconciler. `npm run verify:phase6` passes 21/21. |
| 7 — Migration and cutover | 🟡 **Data migration complete** — import, export, validation and round trip, `npm run verify:phase7` passes 15/15. **PDF export outstanding**, blocked on a font (see below). |
| 8 — Hardening and release | ✅ **Complete.** Backup with a proven restore, ledger reconciliation, rate limiting, least-privilege grants, secret scanning, signed release configuration. `npm run verify:phase8` passes 14/14. |

**All thirteen prototype screens are built**, plus user management and the family
form. Every endpoint in §4 is implemented — including **11 (`POST /families`)**
and **13 (`PUT /families`)**, which appeared in the endpoint table but in none of
the eight phases and were folded into Phase 6.

**160 backend verification checks pass** across the six verifiable phases, plus
34 Flutter tests, a clean analyzer, a clean RTL lint, and release builds for web,
Android APK and Android app bundle.

Deployment is documented in [`DEPLOYMENT.md`](DEPLOYMENT.md); day-to-day
operation in [`OPERATIONS.md`](OPERATIONS.md). `npm run preflight` reports
exactly what is not yet production-ready.

**Three things remain, none of them finishable without you:**

1. **Google OAuth client IDs** — nobody can sign in until these exist.
   Walkthrough: [`GOOGLE_SIGNIN.md`](GOOGLE_SIGNIN.md).
2. **Hosting and off-site backups** — open decision D1. Note risk R13: MariaDB
   10.4 is end-of-life and should not be production merely because XAMPP ships it.
3. **PDF export** — blocked on an openly-licensed Arabic font (see Phase 7).

**Blocked on you:** an end-to-end Google sign-in cannot be verified without
OAuth client IDs from the Google Cloud console. Everything either side of the
Google round-trip is built and tested; see `app/README.md` for the setup steps.

**Environment as actually found (2026-08-10), which differs from what §2 assumed:**

| | Planned | Actual on this machine |
|---|---|---|
| Database | MySQL 8 | **MariaDB 10.4.32** (XAMPP), root / no password |
| Node | 20 | 24.15.0 |
| Flutter | — | 3.41.8 stable |

MariaDB was not a free substitution, so before any DDL was written every
construct the schema depends on was probed against the live server: stored
generated columns, a unique index over a generated column that becomes `NULL`,
`CHECK` enforcement on `UPDATE`, `SIGNAL` inside triggers, and Arabic
round-tripping through data, `ENUM` values, and error messages. All passed, so
the schema in §3 is unchanged and remains valid for MySQL 8 as written.

One correction came out of that probe and is now load-bearing: XAMPP's MariaDB
runs with `sql_mode = NO_ZERO_IN_DATE,NO_ZERO_DATE,NO_ENGINE_SUBSTITUTION` —
**no strict mode**, meaning an overlong string silently truncates and a bad
number silently becomes `0`. Every connection therefore sets a strict
`sql_mode` explicitly (`SESSION_SQL_MODE` in `api/src/config/env.ts`). This was
not anticipated in the original plan and would have corrupted money data.

---

## 1. Executive summary

The prototype is a single-file React app holding a **complete and internally consistent family-association accounting engine** in ~150 lines of JavaScript, with every byte of state in one browser's `localStorage`. The accounting engine is the asset; the delivery mechanism is disposable.

**What stays:** the domain model, all twelve business rules, the Arabic RTL language, the `ar-LY` money formatting, and all thirteen screens.
**What changes:** storage moves from `localStorage` to MySQL behind a REST API; the free-text "current user" becomes Google Sign-In plus four real roles; the desktop sidebar becomes a mobile-first navigation shell; the single-device assumption becomes multi-user with concurrent writes.

**The single biggest risk is the money path.** Payment registration performs a FIFO allocation across multiple receivable rows and writes a cash movement, and cancellation reverses all of it. In the prototype this is safe because JavaScript is single-threaded and there is one user. On a server with concurrent treasurers, an unserialised allocation will double-spend a balance. Phase 5 exists to solve exactly this, and nothing in the client can compensate for getting it wrong.

---

## 2. Target architecture

### 2.1 Topology

```
┌──────────────────────────────────────────────────────────┐
│  FLUTTER CLIENT   (Android · iOS · Web)                   │
│  Material 3 · RTL-first · ar primary locale               │
│  Riverpod state · go_router · Dio                         │
│  Holds: access JWT (memory) + refresh token (secure store)│
│  Holds: NO database driver, NO Google client secret       │
└───────────────────────────┬──────────────────────────────┘
                            │  HTTPS · JSON · Bearer JWT
                            ▼
┌──────────────────────────────────────────────────────────┐
│  REST API   Node 20 · Express 4 · TypeScript 5            │
│  ─ auth: verifies Google ID token, issues app JWT         │
│  ─ authorization: role guard per route                    │
│  ─ THE ONLY PLACE the 12 business rules execute           │
│  ─ owns every transaction boundary                        │
└───────────────────────────┬──────────────────────────────┘
                            │  mysql2 pool · TLS · private network
                            ▼
┌──────────────────────────────────────────────────────────┐
│  MySQL 8   utf8mb4_unicode_ci · InnoDB · UTC              │
│  DECIMAL(12,2) money · generated columns · triggers       │
│  Enforces rules 4, 5, 7, 9, 10 at the storage layer       │
└──────────────────────────────────────────────────────────┘
```

**The Flutter client never opens a MySQL connection.** There is no `mysql1`, no `mysql_client`, no direct driver in `pubspec.yaml` at any phase. A mobile binary is a public artifact; database credentials shipped inside one are published credentials, and a raw SQL socket cannot enforce a single one of the twelve business rules. Every read and every write goes through the API tier.

### 2.2 Stack decision — Node 20 + Express + TypeScript

1. The twelve business rules already exist as working JavaScript in `index.html` (`memberStatus`, `monthsUntilBirthdayAge`, `periodsBetween`, `buildReceivable`, `registerPayment`, `receivableStatus`); porting them to TypeScript is near-mechanical transcription, whereas a PHP rewrite is a fresh opportunity to reintroduce money bugs in code that is currently correct.
2. `google-auth-library` is Google's own first-party ID-token verifier and requires no Firebase project, no third-party SDK, and no client secret on the device.
3. The development machine is Windows with an existing Node/JS toolchain and no PHP runtime, so Laravel would add an environment-setup cost that buys nothing the plan needs.

### 2.3 Recommended dependencies

Listed as plan recommendations only — nothing is installed by this document. Anything not on this list requires approval before Phase 1.

**API**

| Package | Constraint | Why |
|---|---|---|
| `express` | `^4.19` | HTTP layer |
| `typescript` | `^5.5` | Type safety on the money path |
| `mysql2` | `^3.11` | Promise pool; returns `DECIMAL` as string, which prevents float drift |
| `zod` | `^3.23` | Request validation, mirrors the prototype's inline guards |
| `jsonwebtoken` | `^9.0` | Signs and verifies the app JWT |
| `google-auth-library` | `^9.14` | Verifies Google ID tokens against Google's rotating public keys |
| `dotenv` | `^16.4` | Config |
| `pino` + `pino-http` | `^9.4` / `^10.3` | Structured logs |
| `helmet`, `cors`, `express-rate-limit` | current | Baseline hardening on `/auth/*` |

Migrations are plain numbered `.sql` files applied by a runner against a `schema_migrations` table. No migration framework, no ORM — the DDL in section 3 is the artifact, and hand-written SQL keeps the triggers and generated columns visible rather than hidden behind an abstraction.

**Revised after Phase 1.** Node 24 runs TypeScript natively via type stripping and reads `.env` through the built-in `--env-file`, so the toolchain is smaller than planned: Phase 1 ships with **`mysql2` as its only runtime dependency**, no `dotenv`, no transpiler, and no build step. `typescript` and `@types/node` are dev-only. The trade-off is that type stripping erases rather than compiles, so `enum`, `namespace`, and constructor parameter properties are unavailable; `tsconfig.json` sets `erasableSyntaxOnly` to fail the typecheck if one is introduced. The remaining API dependencies in the table above are still expected at Phase 2 and have not been installed.

**Flutter**

| Package | Constraint | Why |
|---|---|---|
| `flutter_riverpod` | `^2.5` | Compile-safe DI plus async state; `AsyncValue` gives loading/error/data for free on every screen |
| `go_router` | `^14.2` | Declarative routes with a redirect guard for the auth and approval gates |
| `dio` | `^5.7` | Interceptors for bearer injection and 401 refresh-retry |
| `google_sign_in` | `^7.1` | Google identity on Android, iOS, and Web |
| `flutter_secure_storage` | `^9.2` | Keystore / Keychain for the refresh token |
| `intl` | `^0.19` | `ar-LY` number and date formatting, identical to the prototype's `Intl.NumberFormat` |
| `flutter_localizations` | SDK | ARB-based localization |
| `json_annotation` / `json_serializable` / `build_runner` | `^4.9` / `^6.8` / `^2.4` | Model codegen |

Note for implementation: `google_sign_in` 7.0 replaced the 6.x `signIn()` API with `GoogleSignIn.instance.initialize()` plus `authenticate()`. Most tutorials online still show 6.x. Read the package's own migration guide before writing the auth service.

---

## 3. MySQL schema

Twelve tables. Conventions: `ENGINE=InnoDB`, `CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`, `BIGINT UNSIGNED` surrogate keys, `DECIMAL(12,2)` for all money, `DATETIME` in UTC, and a `legacy_id` column on every entity that exists in the prototype's JSON so the import in section 8 is idempotent and reversible.

### 3.1 Identity and access

```sql
CREATE TABLE users (
  id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  google_sub     VARCHAR(255)    NOT NULL,
  email          VARCHAR(320)    NOT NULL,
  display_name   VARCHAR(255)    NOT NULL,
  picture_url    VARCHAR(1024)   NULL,
  role           ENUM('admin','financeManager','treasurer','viewer')
                                 NOT NULL DEFAULT 'viewer',
  status         ENUM('pending','approved','suspended')
                                 NOT NULL DEFAULT 'pending',
  approved_by    BIGINT UNSIGNED NULL,
  approved_at    DATETIME        NULL,
  last_login_at  DATETIME        NULL,
  created_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_google_sub (google_sub),
  UNIQUE KEY uq_users_email (email),
  CONSTRAINT fk_users_approved_by
    FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

`google_sub`, not email, is the identity key — Google's `sub` claim is immutable while an email can be reassigned inside a Workspace domain. Email is stored for display and kept unique to block duplicate rows.

**Bootstrap rule:** if `SELECT COUNT(*) FROM users` is zero, the first successful Google sign-in is written as `role='admin', status='approved'`. Every subsequent new account lands as `pending`/`viewer` and must be approved by an admin.

```sql
CREATE TABLE refresh_tokens (
  id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id      BIGINT UNSIGNED NOT NULL,
  token_hash   CHAR(64)        NOT NULL,   -- SHA-256 of the opaque token
  expires_at   DATETIME        NOT NULL,
  revoked_at   DATETIME        NULL,
  replaced_by  BIGINT UNSIGNED NULL,
  user_agent   VARCHAR(255)    NULL,
  created_at   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_refresh_hash (token_hash),
  KEY ix_refresh_user (user_id, expires_at),
  CONSTRAINT fk_refresh_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Only the hash is stored, so a database leak does not yield usable sessions.

### 3.2 Association settings — singleton

```sql
CREATE TABLE association_settings (
  id                          TINYINT UNSIGNED NOT NULL DEFAULT 1,
  association_name            VARCHAR(255)  NOT NULL DEFAULT 'جمعية العائلة',
  currency                    VARCHAR(10)   NOT NULL DEFAULT 'د.ل',
  father_fee                  DECIMAL(12,2) NOT NULL DEFAULT 20.00,
  son_fee                     DECIMAL(12,2) NOT NULL DEFAULT 10.00,
  eligibility_age             TINYINT UNSIGNED NOT NULL DEFAULT 16,
  warning_months              TINYINT UNSIGNED NOT NULL DEFAULT 3,
  system_start                DATE          NOT NULL,
  auto_close_previous_months  TINYINT(1)    NOT NULL DEFAULT 1,
  treasurer_name              VARCHAR(255)  NOT NULL DEFAULT '',
  treasurer_national_id       VARCHAR(50)   NOT NULL DEFAULT '',
  treasurer_phone             VARCHAR(50)   NOT NULL DEFAULT '',
  finance_manager_name        VARCHAR(255)  NOT NULL DEFAULT '',
  finance_manager_national_id VARCHAR(50)   NOT NULL DEFAULT '',
  finance_manager_phone       VARCHAR(50)   NOT NULL DEFAULT '',
  updated_by                  BIGINT UNSIGNED NULL,
  updated_at                  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                            ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT ck_settings_singleton CHECK (id = 1),
  CONSTRAINT ck_settings_fees      CHECK (father_fee >= 0 AND son_fee >= 0),
  CONSTRAINT ck_settings_age       CHECK (eligibility_age >= 0),
  CONSTRAINT fk_settings_updated_by
    FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

`CHECK (id = 1)` makes a second settings row impossible, which mirrors the prototype where `settings` is one object. The `currentUser` and `currentRole` fields from the prototype are deliberately **not** carried over — they are replaced by the `users` table.

### 3.3 Families and members

```sql
CREATE TABLE families (
  id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  family_code VARCHAR(10)     NULL,        -- 'F-0001', assigned in-transaction
  legacy_id   VARCHAR(40)     NULL,
  notes       TEXT            NULL,
  created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by  BIGINT UNSIGNED NULL,
  updated_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                              ON UPDATE CURRENT_TIMESTAMP,
  updated_by  BIGINT UNSIGNED NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_families_code   (family_code),
  UNIQUE KEY uq_families_legacy (legacy_id),
  CONSTRAINT fk_families_created_by
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_families_updated_by
    FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

**Family code generation must change.** The prototype uses `F-${db.families.length + 1}` (line 318), which collides the moment two users create a family at the same time and would also collide after any deletion. Replacement: inside the creating transaction, `INSERT` the row, then `UPDATE families SET family_code = CONCAT('F-', LPAD(id, 4, '0')) WHERE id = LAST_INSERT_ID()`. The value derives from an `AUTO_INCREMENT` id, so it is collision-free under concurrency. (A generated column cannot be used here — MySQL forbids generated columns that reference an `AUTO_INCREMENT` column.)

```sql
CREATE TABLE members (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  family_id       BIGINT UNSIGNED NOT NULL,
  kind            ENUM('father','son') NOT NULL,
  full_name       VARCHAR(255)    NOT NULL,
  national_id     VARCHAR(50)     NOT NULL,
  phone           VARCHAR(50)     NULL,
  subscription_no VARCHAR(50)     NULL,     -- father only in the prototype
  dob             DATE            NULL,
  nationality     VARCHAR(100)    NOT NULL DEFAULT 'ليبي',
  workplace       VARCHAR(255)    NULL,
  registered_at   DATE            NOT NULL,
  status          ENUM('نشط','موقوف','متوفى') NOT NULL DEFAULT 'نشط',
  notes           TEXT            NULL,
  legacy_id       VARCHAR(40)     NULL,
  created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                  ON UPDATE CURRENT_TIMESTAMP,
  -- exactly one father per family: NULL repeats freely in a MySQL unique index
  father_slot     TINYINT UNSIGNED
                  GENERATED ALWAYS AS (IF(kind = 'father', 1, NULL)) STORED,
  PRIMARY KEY (id),
  UNIQUE KEY uq_members_national_id (national_id),          -- RULE 10
  UNIQUE KEY uq_members_legacy      (legacy_id),
  UNIQUE KEY uq_members_one_father  (family_id, father_slot),
  KEY ix_members_family (family_id, kind),
  KEY ix_members_dob    (dob),
  KEY ix_members_name   (full_name),
  CONSTRAINT fk_members_family
    FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Flattening `father{}` + `sons[]` into one `members` table with a `kind` discriminator is what makes **rule 10** a single-column `UNIQUE` index instead of the prototype's O(n) `nationalExists` scan across `flatMap([father, ...sons])`.

Date-of-birth-not-in-the-future cannot be a `CHECK` constraint: MySQL 8 rejects non-deterministic functions such as `CURRENT_DATE` inside `CHECK`. It is enforced by a trigger plus a `zod` rule in the API.

```sql
DELIMITER $$
CREATE TRIGGER trg_members_dob_bi BEFORE INSERT ON members
FOR EACH ROW
BEGIN
  IF NEW.dob IS NOT NULL AND NEW.dob > CURRENT_DATE() THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'تاريخ الميلاد لا يمكن أن يكون مستقبلياً';
  END IF;
END$$
CREATE TRIGGER trg_members_dob_bu BEFORE UPDATE ON members
FOR EACH ROW
BEGIN
  IF NEW.dob IS NOT NULL AND NEW.dob > CURRENT_DATE() THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'تاريخ الميلاد لا يمكن أن يكون مستقبلياً';
  END IF;
END$$
DELIMITER ;
```

> ⚠ This trigger applies to fathers as well as sons, which is **stricter than the prototype**. See conflict C1 in section 11.2 — this is flagged for your decision, not silently resolved.

### 3.4 Receivables — the immutable core

```sql
CREATE TABLE receivables (
  id                       BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  family_id                BIGINT UNSIGNED NOT NULL,
  period                   CHAR(7)         NOT NULL,   -- 'YYYY-MM'
  period_end               DATE            NOT NULL,   -- last day of period

  -- ── IMMUTABLE SNAPSHOT (rule 5) ──────────────────────────────
  father_fee               DECIMAL(12,2)   NOT NULL,
  son_fee                  DECIMAL(12,2)   NOT NULL,
  father_member_id         BIGINT UNSIGNED NULL,
  father_name              VARCHAR(255)    NOT NULL,
  eligibility_age_snapshot TINYINT UNSIGNED NOT NULL,
  warning_months_snapshot  TINYINT UNSIGNED NOT NULL,
  total                    DECIMAL(12,2)   NOT NULL,
  -- ─────────────────────────────────────────────────────────────

  paid                     DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
  balance                  DECIMAL(12,2)
                           GENERATED ALWAYS AS (total - paid) STORED,
  status                   ENUM('غير مسدد','مسدد جزئياً','مسدد بالكامل','ملغي')
                           NOT NULL DEFAULT 'غير مسدد',

  -- rule 4: a cancelled row releases its slot by generating NULL
  active_period            CHAR(7)
                           GENERATED ALWAYS AS
                           (IF(status = 'ملغي', NULL, period)) STORED,

  created_at               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by               BIGINT UNSIGNED NULL,
  cancelled_at             DATETIME        NULL,
  cancelled_by             BIGINT UNSIGNED NULL,
  cancel_reason            VARCHAR(255)    NULL,
  legacy_id                VARCHAR(40)     NULL,

  PRIMARY KEY (id),
  UNIQUE KEY uq_recv_active_period (family_id, active_period),   -- RULE 4
  UNIQUE KEY uq_recv_legacy        (legacy_id),
  KEY ix_recv_period      (period, status),
  KEY ix_recv_family_open (family_id, status, period),
  CONSTRAINT ck_recv_total CHECK (total > 0),                    -- RULE 3
  CONSTRAINT ck_recv_paid  CHECK (paid >= 0 AND paid <= total),  -- RULE 7
  CONSTRAINT fk_recv_family
    FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE RESTRICT,
  CONSTRAINT fk_recv_father
    FOREIGN KEY (father_member_id) REFERENCES members(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

Three rules are made structurally impossible to violate here:

- **Rule 4** — `uq_recv_active_period` on the generated `active_period`. A live row occupies `(family_id, 'YYYY-MM')`; cancelling it flips `active_period` to `NULL`, and MySQL permits unlimited `NULL`s in a unique index, so the slot frees up for a replacement while the cancelled row stays on disk forever.
- **Rule 7** — `CHECK (paid <= total)` means an over-allocation is rejected by the storage engine even if an application bug slips past the balance check.
- **Balance drift** — `balance` is a generated column, not a stored value the application maintains. It cannot disagree with `total - paid`, which removes an entire class of reconciliation bug that the prototype avoids only by recomputing on every write (line 341).

**Rule 5 is enforced by a trigger that rejects any change to a snapshot column:**

```sql
DELIMITER $$
CREATE TRIGGER trg_recv_snapshot_immutable BEFORE UPDATE ON receivables
FOR EACH ROW
BEGIN
  IF  NEW.family_id                <=> OLD.family_id                = 0
   OR NEW.period                   <=> OLD.period                   = 0
   OR NEW.period_end               <=> OLD.period_end               = 0
   OR NEW.father_fee               <=> OLD.father_fee               = 0
   OR NEW.son_fee                  <=> OLD.son_fee                  = 0
   OR NEW.total                    <=> OLD.total                    = 0
   OR NEW.eligibility_age_snapshot <=> OLD.eligibility_age_snapshot = 0
   OR NEW.warning_months_snapshot  <=> OLD.warning_months_snapshot  = 0
   OR NEW.created_at               <=> OLD.created_at               = 0
  THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Rule 5: receivable snapshot columns are immutable';
  END IF;
END$$
DELIMITER ;
```

(`<=>` is the NULL-safe equality operator; `= 0` means "not equal", so the trigger fires on any change including to or from `NULL`.) The only columns an `UPDATE` may touch are `paid`, `status`, and the four cancellation columns. Editing `association_settings` therefore *cannot* alter a historical receivable — the database will refuse the write, independently of application correctness.

```sql
-- snapshot of exactly which members were billed, replacing the prototype's
-- eligibleSonIds[] / eligibleSonNames[] JSON arrays
CREATE TABLE receivable_lines (
  id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  receivable_id      BIGINT UNSIGNED NOT NULL,
  member_id          BIGINT UNSIGNED NULL,
  member_kind        ENUM('father','son') NOT NULL,
  member_name        VARCHAR(255)    NOT NULL,   -- snapshot, survives renames
  member_national_id VARCHAR(50)     NOT NULL,   -- snapshot
  fee_amount         DECIMAL(12,2)   NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_line_recv_member (receivable_id, member_id),
  KEY ix_line_member (member_id),
  CONSTRAINT ck_line_fee CHECK (fee_amount >= 0),
  CONSTRAINT fk_line_recv
    FOREIGN KEY (receivable_id) REFERENCES receivables(id) ON DELETE RESTRICT,
  CONSTRAINT fk_line_member
    FOREIGN KEY (member_id) REFERENCES members(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

The name and national ID are duplicated into the line rather than joined, so a receipt printed in 2027 still shows the name as it stood when the charge was raised. `SUM(fee_amount)` per receivable must equal `receivables.total`; that invariant is asserted in the generate transaction and re-checked by the nightly reconciliation job in Phase 6.

### 3.5 Payments, allocations, cash

```sql
CREATE TABLE payments (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  receipt_no    VARCHAR(20)     NULL,       -- 'PAY-000123', set in-transaction
  family_id     BIGINT UNSIGNED NOT NULL,
  amount        DECIMAL(12,2)   NOT NULL,
  method        ENUM('نقداً','تحويل مصرفي') NOT NULL,
  reference     VARCHAR(100)    NULL,
  receiver      VARCHAR(255)    NULL,
  notes         TEXT            NULL,
  status        ENUM('معتمد','ملغي') NOT NULL DEFAULT 'معتمد',
  paid_at       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_by    BIGINT UNSIGNED NULL,
  cancelled_at  DATETIME        NULL,
  cancelled_by  BIGINT UNSIGNED NULL,
  cancel_reason VARCHAR(255)    NULL,
  legacy_id     VARCHAR(40)     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pay_receipt (receipt_no),
  UNIQUE KEY uq_pay_legacy  (legacy_id),
  KEY ix_pay_family (family_id, paid_at),
  KEY ix_pay_time   (paid_at),
  CONSTRAINT ck_pay_amount CHECK (amount > 0),                    -- RULE 7
  CONSTRAINT ck_pay_cancel
    CHECK (status <> 'ملغي' OR cancelled_at IS NOT NULL),
  CONSTRAINT fk_pay_family
    FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE payment_allocations (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  payment_id    BIGINT UNSIGNED NOT NULL,
  receivable_id BIGINT UNSIGNED NOT NULL,
  period        CHAR(7)         NOT NULL,   -- snapshot for display
  amount        DECIMAL(12,2)   NOT NULL,
  sequence_no   SMALLINT UNSIGNED NOT NULL, -- FIFO order actually applied
  PRIMARY KEY (id),
  UNIQUE KEY uq_alloc_pay_recv (payment_id, receivable_id),
  KEY ix_alloc_recv (receivable_id),
  CONSTRAINT ck_alloc_amount CHECK (amount > 0),
  CONSTRAINT fk_alloc_pay
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE RESTRICT,
  CONSTRAINT fk_alloc_recv
    FOREIGN KEY (receivable_id) REFERENCES receivables(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE cash_movements (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  payment_id    BIGINT UNSIGNED NOT NULL,
  family_id     BIGINT UNSIGNED NOT NULL,
  amount        DECIMAL(12,2)   NOT NULL,
  method        ENUM('نقداً','تحويل مصرفي') NOT NULL,
  movement_type ENUM('تحصيل')   NOT NULL DEFAULT 'تحصيل',
  status        ENUM('معتمد','ملغي') NOT NULL DEFAULT 'معتمد',
  occurred_at   DATETIME        NOT NULL,
  legacy_id     VARCHAR(40)     NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_cash_payment (payment_id),   -- RULE 8: exactly one per payment
  UNIQUE KEY uq_cash_legacy  (legacy_id),
  KEY ix_cash_time   (occurred_at),
  KEY ix_cash_method (method, status, occurred_at),
  CONSTRAINT fk_cash_pay
    FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE RESTRICT,
  CONSTRAINT fk_cash_family
    FOREIGN KEY (family_id) REFERENCES families(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

`uq_cash_payment` turns **rule 8** into a schema guarantee: a payment can have exactly one cash movement, so a retried request cannot double-count the treasury. `movement_type` carries only `تحصيل` because that is the only value the prototype produces — disbursements are section 12 material.

### 3.6 Audit log — append-only

```sql
CREATE TABLE audit_log (
  id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  event_type    VARCHAR(60)     NOT NULL,
  detail        TEXT            NOT NULL,
  ref           VARCHAR(60)     NULL,
  actor_user_id BIGINT UNSIGNED NULL,
  actor_name    VARCHAR(255)    NOT NULL,   -- snapshot, survives user renames
  ip_address    VARCHAR(45)     NULL,
  occurred_at   DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  KEY ix_audit_time (occurred_at),
  KEY ix_audit_type (event_type, occurred_at),
  KEY ix_audit_ref  (ref),
  CONSTRAINT fk_audit_actor
    FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

`DATETIME(3)` because the prototype writes several audit entries inside one operation and displays them newest-first; millisecond precision keeps that ordering stable.

**Rule 9's "nothing is ever hard-deleted" is enforced by refusal triggers** on all five financial tables:

```sql
DELIMITER $$
CREATE TRIGGER trg_audit_no_update BEFORE UPDATE ON audit_log
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'audit_log is append-only';
END$$
CREATE TRIGGER trg_audit_no_delete BEFORE DELETE ON audit_log
FOR EACH ROW BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'audit_log is append-only';
END$$
-- repeat the DELETE guard verbatim for:
--   receivables, receivable_lines, payments, payment_allocations, cash_movements
DELIMITER ;
```

The application account is additionally granted no `DELETE` privilege on these tables; the triggers are the second line of defence for anyone with a SQL console.

### 3.7 Infrastructure

```sql
CREATE TABLE schema_migrations (
  version    VARCHAR(20)  NOT NULL,
  name       VARCHAR(255) NOT NULL,
  applied_at DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  checksum   CHAR(64)     NOT NULL,
  PRIMARY KEY (version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 3.8 Rule-to-enforcement traceability

| # | Rule | Enforced by |
|---|---|---|
| 1 | Son billable only when age ≥ `eligibility_age` **at period end** | `POST /receivables/generate` uses `receivables.period_end` as the evaluation date; snapshot stored in `eligibility_age_snapshot` |
| 2 | "قريب من السن" within `warning_months` | `GET /alerts`, `GET /dashboard`, `GET /families/:id` — derived, never stored |
| 3 | Total = father fee (if `نشط`) + son fee × eligible; skip if ≤ 0 | `ck_recv_total CHECK (total > 0)` + generate transaction |
| 4 | One live receivable per (family, period) | `uq_recv_active_period` on generated `active_period` |
| 5 | Receivables are immutable snapshots | `trg_recv_snapshot_immutable` + `receivable_lines` |
| 6 | Auto-close from `system_start` to previous month | `POST /receivables/auto-close`, idempotent via rule 4's index |
| 7 | Payment > 0 and ≤ outstanding; FIFO oldest-first | `ck_pay_amount`, `ck_recv_paid`, `SELECT … FOR UPDATE` ordered by `period ASC` |
| 8 | Every approved payment writes one cash movement | `uq_cash_payment` + same transaction |
| 9 | Cancellation reverses and preserves | status columns + `BEFORE DELETE` refusal triggers |
| 10 | `national_id` unique; DOB not future | `uq_members_national_id`; `trg_members_dob_bi/bu` (see conflict C1) |
| 11 | Statement = chronological debit/credit merge with running balance | `GET /families/:id/statement`, computed |
| 12 | Audit on six event types | `audit_log` written inside each mutating transaction |

---

## 4. API surface

Base path `/api/v1`. All responses `application/json; charset=utf-8`. Errors use a single envelope: `{ "error": { "code": "STRING_CODE", "message": "رسالة بالعربية", "details": [...] } }` — the message is display-ready Arabic because the client must never build error text from a status code.

Roles are cumulative in reading power: `admin` ⊇ `financeManager` ⊇ `treasurer` ⊇ `viewer`. **TX** marks endpoints that must run inside a single `START TRANSACTION` … `COMMIT`.

| # | Method | Path | Purpose | Role | Request body | Response | TX |
|---|---|---|---|---|---|---|---|
| 1 | POST | `/auth/google` | Exchange Google ID token for app tokens | public | `{idToken}` | `{accessToken, refreshToken, expiresIn, user}` | ✅ |
| 2 | POST | `/auth/refresh` | Rotate refresh token | public | `{refreshToken}` | `{accessToken, refreshToken, expiresIn}` | ✅ |
| 3 | POST | `/auth/logout` | Revoke refresh token | any | `{refreshToken}` | `204` | — |
| 4 | GET | `/auth/me` | Current user, role, status | any | — | `{user}` | — |
| 5 | GET | `/users` | List accounts and approval state | admin | — | `{users[]}` | — |
| 6 | PATCH | `/users/:id` | Set role / approve / suspend | admin | `{role?, status?}` | `{user}` | ✅ |
| 7 | GET | `/settings` | Association settings | viewer | — | `{settings}` | — |
| 8 | PUT | `/settings` | Update settings | admin | full settings object | `{settings}` | ✅ |
| 9 | GET | `/officials` | Treasurer + finance manager | viewer | — | `{officials[2]}` | — |
| 10 | GET | `/families` | Search + paginate families with debt totals | viewer | `?q=&page=&pageSize=` | `{items[], total, page}` | — |
| 11 | POST | `/families` | Create family with father and sons | financeManager | `{father, sons[]}` | `{family}` | ✅ |
| 12 | GET | `/families/:id` | Detail with members, KPIs, statuses | viewer | — | `{family, members[], kpis}` | — |
| 13 | PUT | `/families/:id` | Update family, add/edit/remove sons | financeManager | `{father, sons[]}` | `{family}` | ✅ |
| 14 | GET | `/families/:id/statement` | Ledger with running balance | viewer | `?from=&to=` | `{movements[], closingBalance}` | — |
| 15 | GET | `/members` | Unified father+son search | viewer | `?q=&page=` | `{items[], total}` | — |
| 16 | GET | `/receivables` | List with filters | viewer | `?period=&status=&familyId=&page=` | `{items[], total, summary}` | — |
| 17 | GET | `/receivables/:id` | One receivable with its lines | viewer | — | `{receivable, lines[]}` | — |
| 18 | POST | `/receivables/generate` | Raise receivables for one period | financeManager | `{period}` | `{created, skipped, period}` | ✅ |
| 19 | POST | `/receivables/auto-close` | Backfill `system_start` → previous month | financeManager | — | `{created, periods[]}` | ✅ |
| 20 | GET | `/payments` | Payment list with allocations | viewer | `?familyId=&from=&to=&page=` | `{items[], total}` | — |
| 21 | GET | `/payments/:id` | One payment, printable receipt shape | viewer | — | `{payment, allocations[]}` | — |
| 22 | POST | `/payments` | **Register payment, FIFO-allocate, post to cash** | treasurer | `{familyId, amount, method, reference?, receiver?, notes?}` | `{payment, allocations[]}` | ✅ **critical** |
| 23 | POST | `/payments/:id/cancel` | **Reverse allocations, void cash movement** | financeManager | `{reason}` | `{payment}` | ✅ **critical** |
| 24 | GET | `/cash/movements` | Treasury ledger | viewer | `?from=&to=&method=&page=` | `{items[], total}` | — |
| 25 | GET | `/cash/summary` | Day / month / year / lifetime totals | viewer | — | `{total, cash, transfer, day, month, year}` | — |
| 26 | GET | `/dashboard` | The four stat cards + top debtors + upcoming | viewer | — | `{stats, topDebtors[], upcomingSons[]}` | — |
| 27 | GET | `/alerts` | Age, debt, and partial-payment alerts | viewer | `?type=` | `{alerts[]}` | — |
| 28 | GET | `/reports/financial` | Period report | viewer | `?from=&to=` | `{issued, collected, debt, partialCount, payments[]}` | — |
| 29 | GET | `/audit` | Audit trail | financeManager | `?type=&from=&to=&page=` | `{items[], total}` | — |
| 30 | POST | `/admin/import-legacy` | One-shot localStorage JSON import | admin | backup JSON | `{imported{...}, warnings[]}` | ✅ |
| 31 | GET | `/health` | Liveness + DB ping | public | — | `{ok, dbLatencyMs}` | — |

**31 endpoints, 9 transactional.**

### 4.1 The two critical transactions

**`POST /payments` — endpoint 22.** This is the one place where getting concurrency wrong loses money.

```
BEGIN
  SELECT id, total, paid, balance
    FROM receivables
   WHERE family_id = ? AND status <> 'ملغي' AND (total - paid) > 0
   ORDER BY period ASC
     FOR UPDATE                       ← row locks, FIFO order, deadlock-stable
  outstanding := SUM(balance)
  IF amount <= 0 OR amount > outstanding  → ROLLBACK, 422
  remaining := amount                  ← integer minor units, never float
  FOR each receivable IN period order:
      take := MIN(remaining, balance)
      UPDATE receivables SET paid = paid + take,
             status = (paid+take = total ? 'مسدد بالكامل' : 'مسدد جزئياً')
      INSERT payment_allocations(...)
      remaining -= take
  INSERT payments(...)  → UPDATE receipt_no = CONCAT('PAY-', LPAD(id,6,'0'))
  INSERT cash_movements(...)
  INSERT audit_log('تسجيل سداد', ...)
COMMIT
```

`FOR UPDATE` in a fixed `period ASC` order is what makes this safe: two treasurers paying the same family serialise on the first receivable row, and because every transaction locks in the same order, they cannot deadlock against each other. The second transaction re-reads the balance the first one committed, so the "amount ≤ outstanding" check is evaluated against fresh data rather than a stale read.

All arithmetic is performed in **integer minor units** (value × 100). `mysql2` returns `DECIMAL` as a JavaScript string precisely so it never passes through a float; parse to integer, allocate, and format back on the way out. The prototype's `Math.abs(r.balance) < 0.0001` epsilon fudge (line 342) disappears, because integers do not need one.

**`POST /payments/:id/cancel` — endpoint 23.**

```
BEGIN
  SELECT * FROM payments WHERE id = ? FOR UPDATE
  IF status = 'ملغي' → ROLLBACK, 409 (idempotent guard)
  SELECT * FROM payment_allocations WHERE payment_id = ? FOR UPDATE
  FOR each allocation:
      UPDATE receivables
         SET paid = paid - allocation.amount,
             status = recompute(paid, total)
       WHERE id = allocation.receivable_id
  UPDATE payments      SET status='ملغي', cancelled_at=NOW(), cancelled_by=?, cancel_reason=?
  UPDATE cash_movements SET status='ملغي' WHERE payment_id = ?
  INSERT audit_log('إلغاء دفعة', ...)
COMMIT
```

Allocation rows are **kept, not deleted** — the `BEFORE DELETE` trigger would refuse anyway. `status` recomputation follows the prototype's `receivableStatus`: balance ≤ 0 → `مسدد بالكامل`, paid > 0 → `مسدد جزئياً`, otherwise `غير مسدد`.

### 4.2 Role permission matrix

| Screen | viewer | treasurer | financeManager | admin |
|---|:--:|:--:|:--:|:--:|
| لوحة التحكم `dashboard` | read | read | read | read |
| العائلات `families` | read | read | read + write | read + write |
| تفاصيل العائلة `familyDetail` | read | read | read + write | read + write |
| الأعضاء `members` | read | read | read | read |
| الاستحقاقات `receivables` | read | read | read + generate | read + generate |
| التحصيل والسداد `payments` | read | read + **register** | read + register + **cancel** | full |
| الصندوق `cash` | read | read | read | read |
| كشوف الحساب `statements` | read | read | read | read |
| التنبيهات `alerts` | read | read | read | read |
| التقارير `reports` | read | read | read | read |
| المسؤولون `officials` | read | read | read | read |
| سجل العمليات `audit` | ✗ hidden | ✗ hidden | read | read |
| الإعدادات `settings` | ✗ hidden | ✗ hidden | ✗ hidden | read + write |
| إدارة المستخدمين *(new)* | ✗ hidden | ✗ hidden | ✗ hidden | full |

The split that matters: a treasurer may **take** money but may not **unwind** it. Cancellation is a finance-manager act. This is a genuine segregation of duties and is the main reason the four roles exist rather than a single admin flag.

Hidden screens are removed from navigation *and* rejected at the API. Client-side hiding is presentation, never security.

---

## 5. Authentication and authorization flow

### 5.1 Sequence

```mermaid
sequenceDiagram
    autonumber
    participant U as المستخدم
    participant F as Flutter Client
    participant G as Google Identity
    participant A as REST API
    participant D as MySQL

    U->>F: يضغط "الدخول بحساب Google"
    F->>G: GoogleSignIn.instance.authenticate()
    G->>U: اختيار الحساب والموافقة
    G-->>F: Google ID token (JWT, ~1h)
    Note over F: العميل لا يثق بهذا الرمز<br/>ولا يحتوي على client secret
    F->>A: POST /api/v1/auth/google {idToken}
    A->>G: fetch Google public keys (cached)
    A->>A: verify signature, iss, aud, exp, email_verified
    alt التوقيع غير صالح
        A-->>F: 401 INVALID_GOOGLE_TOKEN
        F-->>U: رسالة خطأ وإعادة المحاولة
    end
    A->>D: SELECT * FROM users WHERE google_sub = ?
    alt مستخدم جديد وقاعدة المستخدمين فارغة
        A->>D: INSERT user (role=admin, status=approved)
    else مستخدم جديد
        A->>D: INSERT user (role=viewer, status=pending)
        A->>D: INSERT audit_log('طلب دخول جديد')
        A-->>F: 403 ACCOUNT_PENDING
        F-->>U: شاشة "بانتظار موافقة المسؤول"
    else الحساب موقوف
        A-->>F: 403 ACCOUNT_SUSPENDED
    end
    A->>D: UPDATE last_login_at; INSERT refresh_tokens(hash)
    A-->>F: {accessToken (15m), refreshToken (30d), user}
    F->>F: access → memory · refresh → flutter_secure_storage
    F-->>U: التوجيه إلى لوحة التحكم حسب الدور

    Note over F,A: لاحقاً — انتهاء صلاحية الرمز
    F->>A: GET /api/v1/families  (Bearer access)
    A-->>F: 401 TOKEN_EXPIRED
    F->>A: POST /api/v1/auth/refresh {refreshToken}
    A->>D: verify hash, not revoked, not expired → rotate
    A-->>F: {accessToken, refreshToken}
    F->>A: إعادة إرسال الطلب الأصلي تلقائياً
```

### 5.2 Token handling

| Concern | Decision |
|---|---|
| Access token | App-signed JWT, HS256, **15 minutes**, claims `sub`, `role`, `status`, `iat`, `exp`, `jti`. Kept in memory only — never written to disk, never to `SharedPreferences`. |
| Refresh token | Opaque 32-byte random string, **30 days**, stored client-side in `flutter_secure_storage` (Keystore / Keychain) and server-side only as SHA-256. |
| Rotation | Every refresh issues a new refresh token and marks the old one `revoked_at` with `replaced_by`. Reuse of a revoked token revokes the entire chain for that user and writes an audit entry — this detects a stolen token. |
| Refresh concurrency | Dio interceptor holds a single-flight `Completer`; parallel 401s wait on one refresh rather than firing a stampede that rotates the token out from under each other. |
| Logout | Revokes the refresh row server-side and clears secure storage. A still-valid access token dies within 15 minutes; that window is accepted. |
| Role changes | Carried in the JWT, so a demotion takes effect within 15 minutes. Suspension is immediate: the auth middleware re-checks `users.status` on every request, which is one indexed primary-key lookup. |
| Web | `google_sign_in_web` requires the OAuth client ID in a `<meta name="google-signin-client_id">` tag in `web/index.html`. That is a public identifier, not a secret. |
| Secrets | The Google **client secret** lives only in the API's environment. It is never in `pubspec.yaml`, never in the Flutter bundle, never in the repository. |

### 5.3 Not-yet-approved flow

A pending user is a first-class state, not an error. `POST /auth/google` returns `403 ACCOUNT_PENDING` with the user's name and email; `go_router` redirects to a dedicated `/pending` screen showing "تم إرسال طلبك إلى مسؤول النظام" with the signed-in identity and a sign-out button. The app must not crash, must not show an empty dashboard, and must not retry in a loop. An admin approves from the new user-management screen, and the next sign-in succeeds.

---

## 6. Flutter application architecture

### 6.1 Folder tree

```
lib/
├── main.dart
├── app.dart                          # MaterialApp.router, RTL, theme, locale
├── core/
│   ├── config/
│   │   ├── env.dart                  # API base URL per flavor
│   │   └── theme.dart                # Material 3 from the prototype's CSS vars
│   ├── network/
│   │   ├── api_client.dart           # Dio instance + base options
│   │   ├── auth_interceptor.dart     # bearer injection
│   │   ├── refresh_interceptor.dart  # single-flight 401 → refresh → retry
│   │   └── api_exception.dart        # maps the error envelope to typed failures
│   ├── router/
│   │   ├── app_router.dart           # go_router, all 14 routes
│   │   └── auth_guard.dart           # redirect: unauthenticated → /login
│   │                                 #           pending        → /pending
│   │                                 #           role-forbidden → /forbidden
│   ├── format/
│   │   ├── money.dart                # ar-LY, 2 decimals — mirrors money()
│   │   └── hijri_gregorian.dart      # ar date formatting
│   └── widgets/                      # AppScaffold, StatCard, StatusBadge,
│                                     # DataTableCard, EmptyState, ErrorState,
│                                     # LoadingState, ConfirmSheet
├── features/
│   ├── auth/          { data/ domain/ presentation/ }
│   ├── dashboard/     { … }
│   ├── families/      { … }   # list, detail, edit form
│   ├── members/       { … }
│   ├── receivables/   { … }
│   ├── payments/      { … }   # list, register sheet, cancel
│   ├── cash/          { … }
│   ├── statements/    { … }
│   ├── alerts/        { … }
│   ├── reports/       { … }
│   ├── officials/     { … }
│   ├── audit/         { … }
│   ├── settings/      { … }
│   └── users/         { … }   # new: approval + role management
└── l10n/
    ├── app_ar.arb                    # primary — every string originates here
    └── app_en.arb                    # secondary, for developer readability
```

Each feature folder is `data/` (DTOs + repository implementation), `domain/` (entities + repository interface), `presentation/` (screen + widgets + Riverpod providers). Uniform structure means a new screen is a copy of an existing folder rather than a design decision.

### 6.2 Key choices

**State — `flutter_riverpod`.** `AsyncValue` models loading, error, and data as one sealed type, so every screen's three required states in section 7 fall out of a single `.when()` rather than three hand-managed booleans.

**Routing — `go_router` with a redirect guard.** Auth, approval, and role checks are one function evaluated on every navigation, so no screen can be reached by a stale deep link after a demotion.

**Networking — `dio` with two interceptors.** `auth_interceptor` attaches the bearer; `refresh_interceptor` catches 401, refreshes once (single-flight), and replays the original request. Screens never see a 401.

**Errors.** `api_exception.dart` maps the envelope's `code` to a typed failure, and the shared `ErrorState` widget renders the Arabic `message` plus a retry button. No screen builds error text from a status code.

**Where the business rules live.** All twelve execute **on the server**. The client duplicates exactly three, purely for instant feedback, and each is safe because the server independently rejects the same input:

| Duplicated client-side | Why it is safe |
|---|---|
| Payment amount > 0 and ≤ displayed outstanding | Disables the confirm button before a round trip; the server re-reads the balance under `FOR UPDATE`, so a stale client figure produces a clean 422, never an over-payment. |
| Date of birth not in the future | A date-picker `lastDate` is a UX affordance; `trg_members_dob_*` is the enforcement. |
| Required fields (name, national ID) | Inline form validation; `zod` plus `NOT NULL` are the enforcement. |

Eligibility age, fee calculation, FIFO allocation, period generation, and status derivation are **never** computed on the client. The client renders what `GET /families/:id` and `GET /alerts` return. This is deliberate: the prototype computes `memberStatus` in the UI, and reproducing that in Dart would create a second implementation of rule 1 that could silently disagree with the server's.

### 6.3 RTL and localization

`MaterialApp.router` sets `locale: Locale('ar')`, `supportedLocales: [ar, en]`, and `localizationsDelegates` including `GlobalMaterialLocalizations.delegate`. Flutter derives RTL from the locale, so `Directionality` is automatic — but only if no widget hard-codes `EdgeInsets.only(left:)`. **Use `EdgeInsetsDirectional` and `start`/`end` everywhere; `left`/`right` are banned in this codebase.** A lint rule enforces it in Phase 3.

Zero Arabic string literals in widget files. Every visible string comes from `app_ar.arb`, including the status enums, which are stored in MySQL as Arabic values and must be mapped to ARB keys for display rather than printed raw.

---

## 7. Screen-by-screen UX flow

### 7.1 Navigation shell

The prototype has a 280px sidebar with **twelve** entries and a mobile bottom bar with **five** — which leaves seven screens (`members`, `receivables`, `statements`, `alerts`, `reports`, `officials`, `audit`) unreachable on a phone. The Flutter app is mobile-first, so this must be fixed to reach parity with the desktop sidebar, not to add capability.

| Breakpoint | Shell |
|---|---|
| `< 600 dp` (phone) | `NavigationBar`, 5 destinations: الرئيسية · العائلات · السداد · الصندوق · **المزيد**. "المزيد" opens a full-screen grid of the remaining eight, role-filtered. |
| `600–1024 dp` (tablet) | `NavigationRail`, collapsed icons, all destinations |
| `> 1024 dp` (web/desktop) | Permanent `NavigationDrawer` reproducing the sidebar |

One `AppScaffold` switches on `MediaQuery` width so no screen knows which shell it is in. Top bar carries the screen title, the Gregorian Arabic date (`ar-EG` full date, as the prototype does), and an avatar menu with name, role badge, and sign-out.

Route graph:

```
/login  →  /pending          (status = pending)
        →  /forbidden        (role lacks the route)
        →  /                 (dashboard)
              ├── /families              ├── /alerts
              │     └── /families/:id    ├── /reports
              │           └── ?edit=1    ├── /officials
              ├── /members               ├── /audit          [financeManager+]
              ├── /receivables           ├── /settings       [admin]
              ├── /payments              └── /users          [admin]
              ├── /cash
              └── /statements
```

**First run.** Cold start → splash while `flutter_secure_storage` is read → no refresh token, or refresh fails → `/login`. Login screen: association name, a single "الدخول بحساب Google" button, nothing else. After a successful sign-in as the very first user (auto-admin), route to `/settings` with a one-time banner: "أكمل إعدادات الجمعية قبل إنشاء الاستحقاقات" — because `system_start`, `father_fee`, and `son_fee` drive every subsequent calculation and the defaults are placeholders.

### 7.2 The thirteen screens

Every screen shares the same three states unless noted: **loading** = skeleton shapes matching the final layout (never a bare spinner on a list); **error** = `ErrorState` with the Arabic message and a retry button; **offline** = a persistent banner "لا يوجد اتصال بالإنترنت" plus retry, since v1 is online-only (section 9).

---

**1. `dashboard` — لوحة التحكم** · `GET /dashboard`
Purpose: the administrative and financial position at a glance.
Mobile: four stat cards in a 2×2 grid (`عدد العائلات` / `الأبناء المستحقون` / `إجمالي المديونية` / `إجمالي المحصل`), then "أعلى المديونيات" (top 8) and "تنبيهات قريبة" (top 8) as stacked cards. Desktop restores the 4-across row and the 1.3fr/0.7fr split.
Interactions: pull-to-refresh; tapping a debtor opens that family; the primary action "إقفال [الشهر السابق]" calls `POST /receivables/generate` for the previous period behind a confirmation sheet stating how many families will be charged.
Empty: fresh install shows "ابدأ بإضافة أول عائلة" with a direct action.
Role: the generate button is hidden below `financeManager`.

**2. `families` — العائلات** · `GET /families?q=`
Purpose: browse and search every family.
Mobile: search field pinned under the app bar, then a card per family — father's name, `familyCode` chip, sons count, eligible count, and a red debt chip when outstanding > 0. Tap opens detail; long-press offers "تعديل".
Interactions: debounced search (300 ms) across name, national ID, phone, subscription number, and workplace, matching the prototype's filter; infinite scroll at 25 per page; FAB "+ إضافة عائلة".
Empty: no families → illustration + "إضافة عائلة"; search with no hits → "لا توجد نتائج لبحثك" + clear.
Role: FAB and long-press edit hidden below `financeManager`.

**3. `familyDetail` — تفاصيل العائلة** · `GET /families/:id`
Purpose: the full picture for one family plus the entry point to payment.
Mobile: a hero card with five KPIs (sons, eligible, approaching age, current monthly charge, outstanding) as a 2-column grid; then "بيانات الأب"; then a sons list rendered as **cards, not a table** — a phone cannot show eight columns, so each card carries name, age, national ID, a status badge (`مستحق` / `قريب` / `دون السن` / inactive), and the current fee; then a condensed statement with a link to the full one.
Interactions: "تسجيل سداد" primary button, disabled with an explanatory caption when outstanding = 0; "تعديل" opens the family form; "مشاركة / طباعة" exports a PDF (replacing `window.print()`).
Role: payment button requires `treasurer`; edit requires `financeManager`.

**4. Family form (modal route) — إضافة / تعديل عائلة** · `POST` / `PUT /families`
Purpose: create or amend a family and its sons.
Mobile: full-screen route, not a dialog. Two sections — "بيانات الأب" (10 fields) and "الأبناء الذكور" (a repeatable card per son with 8 fields, plus "+ إضافة ابن" and a per-card delete with confirmation). Single-column fields; the prototype's 2-column grid returns above 600 dp.
Validation, mirroring the prototype: father name and national ID required; every son's name and national ID required; no duplicate national ID within the form; date of birth not in the future; server rejects a national ID already used by any other member with a field-level error naming the conflict.
Interactions: unsaved-changes guard on back; the save button shows an inline progress state and disables on submit to prevent a double POST.

**5. `members` — الأعضاء** · `GET /members?q=`
Purpose: one flat searchable index of fathers and sons together.
Mobile: search plus a compact list — name, a صفة chip (أب / ابن), family, age. Tapping jumps to the owning family. Desktop restores the 7-column table.
Empty / offline / error: standard. Read-only for all roles.

**6. `receivables` — الاستحقاقات** · `GET /receivables`
Purpose: review raised charges and raise new ones.
Mobile: a month picker plus status filter chips (`غير مسدد` / `مسدد جزئياً` / `مسدد بالكامل`); a summary strip (count, total, collected, outstanding); then a card per receivable — family, period label, total, paid, remaining, status badge. Tap expands to show the billed members from `receivable_lines`.
Interactions: "إنشاء استحقاقات الشهر" opens a confirmation sheet naming the period and the number of families to be charged, then calls endpoint 18; the result toast reports created and skipped counts. The prototype's permanent warning — "تغيير الإعدادات لاحقاً لا يغيّر هذه السجلات" — is retained as an info banner, because it explains rule 5 to the user.
Empty: "لم يتم إنشاء استحقاقات لهذا الشهر بعد" with the generate action inline.
Role: generate requires `financeManager`.

**7. `payments` — التحصيل والسداد** · `GET /payments`
Purpose: the collection ledger and the act of collecting.
Mobile: filter chips (family, date range, method); a card per payment — receipt number, family, amount, method icon, timestamp, status badge, and the allocation breakdown as `الشهر: المبلغ` rows.
Interactions: FAB "+ تسجيل سداد" opens the payment sheet (below); an approved payment offers "إلغاء وعكس" behind a typed-reason confirmation that restates the prototype's warning — the reversal affects receivables and the treasury while the historical record survives.
Retained banner: "يتم توزيع كل دفعة على أقدم الاستحقاقات أولاً" — the FIFO rule must be visible, not implicit.
Role: register requires `treasurer`; cancel requires `financeManager`.

**8. Payment sheet (modal route) — تسجيل عملية سداد** · `POST /payments`
Purpose: take money against outstanding receivables.
Mobile: full-screen. Family picker (searchable; pre-filled and locked when opened from a family); a read-only "المديونية الحالية" fetched live on family selection; amount field with the outstanding value as `max` and a "سداد كامل" shortcut; method segmented control (`نقداً` / `تحويل مصرفي`); reference field revealed only for transfers; receiver, defaulted to the treasurer name from settings; notes.
Live preview — **an addition to the prototype's flow that the FIFO rule makes necessary**: as the amount changes, show which periods it will settle, so the treasurer sees the allocation before confirming rather than after. This is presentation of a server rule, not a new rule.
Guards: confirm disabled unless a family is chosen, outstanding > 0, and 0 < amount ≤ outstanding; a family with no debt shows the prototype's warning and no confirm path; the button locks during submit; a 409 from a duplicate submit is surfaced as "تم تسجيل هذه الدفعة مسبقاً" rather than a retry.
Success: dismiss, toast, and offer "عرض الإيصال" → the printable receipt from endpoint 21.

**9. `cash` — الصندوق** · `GET /cash/summary` + `/cash/movements`
Purpose: treasury position and movement history.
Mobile: four stat cards in a 2×2 grid (total collected, cash, transfer, year-to-date, each with its sub-figure); then the movement list as cards — reference, timestamp, family, amount, method, status. Cancelled movements render struck-through and greyed, never hidden, because rule 9 requires them visible.
Interactions: date-range and method filters; export to CSV/PDF.
Empty: "لم تُسجَّل أي حركة صندوق بعد."

**10. `statements` — كشوف الحساب** · `GET /families/:id/statement`
Purpose: a family's chronological ledger.
Mobile: family picker, then rows as cards — date, reference, movement type, debit or credit, running balance, note. A table this wide does not fit a phone; the card carries the running balance as its most prominent figure.
Interactions: optional date range; "طباعة / مشاركة" produces a PDF with the association name, family name, family code, and period as a header — replacing `window.print()`, which does not exist on mobile.
Empty: "اختر عائلة لعرض كشف الحساب"; a family with no movements shows "لا توجد حركات".

**11. `alerts` — التنبيهات** · `GET /alerts`
Purpose: what needs follow-up.
Mobile: filter chips by type (سن الاستحقاق / مديونية / سداد جزئي); a card per alert with type badge, text, and a tap-through to the family.
Content, unchanged from the prototype: sons within `warning_months` of eligibility age; families with an outstanding balance; families holding partially-paid receivables.
Empty: "لا توجد تنبيهات حالية" — a genuinely good state, so present it as reassurance rather than emptiness.

**12. `reports` — التقارير** · `GET /reports/financial`
Purpose: a financial summary for a chosen window.
Mobile: two date fields defaulting to 1 January of the current year through today; four stat cards (raised, collected, current outstanding, partial-payment count); then the collection detail list.
Interactions: quick presets (هذا الشهر / الشهر الماضي / هذه السنة); PDF and CSV export.
Empty: "لا توجد حركات في الفترة المحددة."

**13. `officials` — المسؤولون** · `GET /officials`
Purpose: display the treasurer and finance manager recorded in settings.
Mobile: two stacked cards, each with role, name, national ID, phone; the phone is a `tel:` action.
Empty: an unset official shows "غير محدد" and, for an admin only, a shortcut to settings. Read-only for all roles.

**14. `audit` — سجل العمليات** · `GET /audit`
Purpose: the regulatory trail.
Mobile: type filter and date range; a reverse-chronological card list — timestamp, event type, detail, actor, reference. Infinite scroll, 50 per page, because this table grows without bound.
Role: hidden below `financeManager` and rejected at the API for lower roles.

**15. `settings` — الإعدادات** · `GET`/`PUT /settings` *(admin only)*
Purpose: the values that drive every future calculation.
Mobile: single-column sections — general (name, currency, father fee, son fee, eligibility age, warning months, system start), then treasurer, then finance manager. The prototype's accounting warning stays as a prominent banner: changing a fee or the eligibility age never alters an already-raised receivable.
Interactions: save shows a confirmation sheet listing the changed fields with old → new values, because these values are financially load-bearing; a successful save writes an audit entry.
Backup: the prototype's JSON export/import is replaced by a server-side "تصدير نسخة كاملة (JSON)" download. **Import is not exposed here** — it exists once, as the admin-only migration in section 8, and re-importing over live data would violate rules 4, 5, and 9.

**16. `users` — إدارة المستخدمين** *(new, required by Google Sign-In)* · `GET /users`, `PATCH /users/:id`
Purpose: without it, no second person can ever use the app.
Mobile: two sections — "طلبات معلقة" with approve/reject and a role picker, and "المستخدمون" with the current role, status, and last login. An admin cannot demote or suspend their own account (the API rejects it), which prevents locking the association out of its own system.
Every change writes an audit entry.

---

## 8. Data migration

### 8.1 Source

The prototype already exports its entire state as `family-association-backup-YYYY-MM-DD.json` (line 384), and that file — not the browser's `localStorage` — is the migration input. Have the user click "تصدير نسخة JSON" on the settings screen of the existing `index.html`, then upload the file to `POST /admin/import-legacy`.

### 8.2 ID strategy

The prototype's IDs are timestamp-based strings (`FAM-M3K2P9-A7X2Q`, from `uid()` on line 107) and are unsuitable as primary keys. Every table therefore takes a fresh `BIGINT UNSIGNED AUTO_INCREMENT` primary key and stores the original string in `legacy_id`.

This does three things: it makes the import **idempotent** (`INSERT … ON DUPLICATE KEY UPDATE` on `legacy_id` means a re-run cannot double-insert), it makes cross-references resolvable in a second pass, and it makes the whole thing **auditable** — any imported row can be traced back to its JSON origin forever.

The import runs in two passes inside one transaction: pass 1 inserts settings, families, and members, building an in-memory `legacy_id → new id` map; pass 2 inserts receivables, receivable lines, payments, allocations, cash movements, and audit entries, resolving every foreign key through that map.

### 8.3 Field mapping

| JSON path | Target column | Transform |
|---|---|---|
| `settings.associationName` | `association_settings.association_name` | direct |
| `settings.currency` | `.currency` | direct |
| `settings.fatherFee` / `.sonFee` | `.father_fee` / `.son_fee` | `Number` → `DECIMAL(12,2)` |
| `settings.eligibilityAge` / `.warningMonths` | `.eligibility_age` / `.warning_months` | → `TINYINT` |
| `settings.systemStart` | `.system_start` | `YYYY-MM-DD` → `DATE` |
| `settings.autoClosePreviousMonths` | `.auto_close_previous_months` | bool → `0/1` |
| `settings.treasurer.*` / `.financeManager.*` | `treasurer_*` / `finance_manager_*` | flattened; `.role` dropped (it is a constant label) |
| `settings.currentUser` / `.currentRole` | — | **dropped**; superseded by `users` |
| `families[].id` | `families.legacy_id` | preserved |
| `families[].familyCode` | `families.family_code` | preserved as-is; new families continue from `MAX(id)` |
| `families[].father` | `members` row, `kind='father'` | flattened |
| `families[].sons[]` | `members` rows, `kind='son'` | flattened |
| `member.id` | `members.legacy_id` | preserved |
| `member.name` → `full_name`, `nationalId` → `national_id`, `subscriptionNo` → `subscription_no`, `registeredAt` → `registered_at` | | camelCase → snake_case |
| `member.dob` | `members.dob` | `''` → `NULL` |
| `member.status` | `members.status` | Arabic enum preserved verbatim |
| `receivables[].id` | `receivables.legacy_id` | preserved |
| `receivables[].period` | `.period` + `.period_end` | `period_end` computed as the last day |
| `receivables[].fatherFee/sonFee/total/paid` | same | → `DECIMAL(12,2)` |
| `receivables[].balance` | — | **dropped**; generated as `total - paid` |
| `receivables[].snapshot.eligibilityAge/warningMonths` | `.eligibility_age_snapshot` / `.warning_months_snapshot` | direct |
| `receivables[].eligibleSonIds[]` + `eligibleSonNames[]` | `receivable_lines` rows | zipped pairwise; a length mismatch is a **hard abort**, not a warning |
| `receivables[].fatherId` / `.fatherName` | `.father_member_id` / `.father_name` | id resolved via map; name kept as snapshot |
| `receivables[].status` | `.status` | verbatim; recomputed and compared — a mismatch is a warning |
| `payments[].id` | `payments.legacy_id` | preserved; `receipt_no` assigned fresh |
| `payments[].at` | `.paid_at` | ISO → `DATETIME`, **converted to UTC** |
| `payments[].allocations[]` | `payment_allocations` rows | `receivableId` resolved via map; `sequence_no` from array order |
| `payments[].createdBy` / `cancelledBy` | — | free-text names; written into the audit detail, not `users` |
| `cashMoves[]` | `cash_movements` | `paymentId` resolved; `type` → `movement_type` |
| `audit[]` | `audit_log` | `at` → `occurred_at` (UTC); `user` → `actor_name`; `actor_user_id` `NULL` |

### 8.4 Validation, before commit

Every check runs inside the transaction; any failure rolls the whole import back.

1. `settings` present and `families` is an array (the prototype's own import guard, line 391).
2. No duplicate `national_id` across all members — the prototype permitted a state the new unique index forbids, so a collision must abort with the offending IDs named.
3. Every `receivable.familyId` and `payment.familyId` resolves to an imported family.
4. Every `allocation.receivableId` resolves to an imported receivable.
5. Per receivable: `paid == SUM(allocations.amount)` for non-cancelled payments, and `paid <= total`.
6. Per receivable: `SUM(receivable_lines.fee_amount) == total`.
7. Per payment: `amount == SUM(its allocations)`.
8. Every non-cancelled payment has exactly one cash movement.
9. No two live receivables share `(family_id, period)`.
10. Grand totals: `SUM(payments.amount where معتمد)` equals `SUM(cash_movements.amount where معتمد)` equals the prototype's own computed `collected` figure.

The response returns per-table counts plus a warnings array. **Check 10 is the acceptance gate** — if the imported treasury total does not match the number the old app displayed, the migration failed regardless of what else succeeded.

### 8.5 Rollback

The import is one transaction, so a failure rolls back with nothing written. After a *successful* import that later proves wrong: `mysqldump` is taken immediately before the run and restored to undo; the endpoint refuses to run a second time while any financial table is non-empty unless called with `?force=true&confirmDrop=true` by an admin, which truncates and re-imports. The original JSON file is archived server-side with its SHA-256, so the input is reproducible.

**Cutover:** run the import against staging first and compare every dashboard figure against the live `index.html` side by side. Keep `index.html` untouched and available read-only until the Flutter app has run one full billing month in production.

---

## 9. Offline and sync

**Recommendation: v1 is online-only. No local database, no write queue, no sync engine.**

The justification is the money path. The application's core operation is a FIFO allocation against a balance that other users can change between one device's read and its write. An offline payment queued on a phone would allocate against a balance that may no longer exist by the time it reaches the server — the payment would be rejected on replay, or worse, applied to different receivables than the treasurer saw when they took the cash. Offline write support for this domain requires either server-side reservations or a conflict-resolution UI for money, and both are larger than the rest of the app.

What ships in v1 instead:

| Capability | v1 behaviour |
|---|---|
| Detecting connectivity | Dio catches network errors; a persistent banner appears with a retry action |
| Reads while offline | Last successful response for the current screen stays on screen behind a "البيانات غير محدثة" marker; Riverpod's in-memory cache provides this with no extra dependency |
| Writes while offline | Blocked. The submit button disables and explains: "لا يمكن حفظ العملية بدون اتصال" — a treasurer who takes cash with no signal records it on paper, which is what they do today |
| Recovery | The banner's retry re-fetches; queued navigation is not attempted |
| Timeouts | 15 s connect, 30 s receive; a timeout is an error state, never a silent hang |

Deferred to a later version, with the prerequisite named: read-only offline cache via `drift` (needs a cache-invalidation strategy), and offline payment capture (needs server-side balance reservation).

---

## 10. Delivery phases

Eight milestones. Schema and API precede all client work, so the Flutter app is never written against a moving contract. Each phase is independently shippable and has a check that is either true or false.

**Phase 1 — Database foundation** ✅ **COMPLETE**
Delivered in `api/`: the repository skeleton, the `.env` contract, a
`DELIMITER`-aware migration runner with checksum tamper detection, and all
twelve tables from section 3 with every trigger, generated column, index, and
`CHECK` constraint. Seed fixtures cover two families and seven members spanning
all three eligibility states, three billing periods, and four payments —
including one that spills across two receivables.

*Verified:* `npm run verify` builds a throwaway database from the real
migrations, runs **30 assertions**, and drops it, so it leaves no residue and
can be run at any time. All four originally-specified criteria pass, plus
twenty-six more: migrations apply to an empty database and re-run as a no-op; an
edited applied migration is refused; `UPDATE receivables SET total = 999` is
rejected by the trigger while a legitimate `paid` update succeeds and the
generated `balance` recomputes (12.50 → 17.50); two concurrent inserts of the
same `(family_id, period)` leave exactly one row and one duplicate-key error;
`DELETE` is refused on all five financial tables and `audit_log` rejects both
`UPDATE` and `DELETE`; cancelling a receivable frees its `(family, period)` slot;
overpayment, negative payment, zero-total, and malformed-period are all rejected
by `CHECK` constraints; a second father, a duplicate national ID, a future birth
date, and a second settings row are all refused; Arabic survives the driver
round-trip; and `DECIMAL` reaches the application as a string rather than a
float.

Seed totals reconcile by hand: 210.00 issued, 135.00 collected, 75.00
outstanding, with cash movements summing to exactly the collected figure.

**Phase 2 — Authentication and users** ✅ **COMPLETE**
Endpoints 1–6 and 31, the role middleware, and the first-user-becomes-admin
bootstrap — serialised on the settings singleton row with `FOR UPDATE`, so two
simultaneous first sign-ins cannot both become administrators.

*Verified:* `npm run verify:phase2` runs **38 assertions** against the real
Express app over real HTTP, backed by a throwaway database. Only the Google
signature check is stubbed, through an injected verifier; every other line is
the production path.

Four deviations from this section as originally written, each deliberate:

1. **The database is authoritative for the role, not just the status.** §5.2
   planned for a demotion to take up to fifteen minutes while the JWT aged out.
   Since `authenticate` already reads the user row on every request to catch
   suspensions, using the stored role costs nothing and makes a demotion take
   effect on the very next request. The JWT still carries the role, but the
   database wins where they disagree.
2. **Rate limiting pulled forward from Phase 8.** `/auth/*` is the only
   unauthenticated write surface in the system and it ships in this phase;
   leaving it unguarded until Phase 8 was the worse trade.
3. **Logout is distinguished from token theft.** Revoking a token on sign-out
   and rotating one away both leave `revoked_at` set, so the first
   implementation reported an ordinary sign-out as `REFRESH_TOKEN_REUSED` and
   killed every other device's session. `replaced_by` now separates them: set
   means a rotated token was replayed (an attack, kill the chain), null means an
   ordinary logout or suspension (just an invalid session).
4. **Malformed request bodies return 400, not 500.** `express.json()` raises a
   `SyntaxError` that the first error handler did not recognise, so a truncated
   request from a flaky mobile connection blamed the server and filled the error
   log with false alarms. Found by a live smoke test, not by the suite — the
   suite only ever sent well-formed JSON.

Stack note: **Express 5**, not the 4.19 named in §2.3. Async handler rejections
route to the error middleware automatically, which for an API where every
handler awaits the database removes a class of hung-request bug.

**Phase 3 — Flutter shell and login** ✅ **COMPLETE** (one criterion blocked)
Delivered in `app/`: theme lifted from the prototype's CSS custom properties,
`ar` locale with ARB wiring, the RTL lint, `go_router` with the auth guard, Dio
with both interceptors, the responsive `AppScaffold`, the shared state widgets,
and the splash, login, pending, suspended, and forbidden screens. The other
thirteen routes exist and are role-guarded but render a placeholder, so
navigation and the guard are real and testable rather than theoretical.

*Verified:* `flutter analyze` reports zero issues; `dart run tool/rtl_lint.dart`
scans 28 files clean; **27 tests** pass; release builds succeed for web (3.0 MB
bundle) and Android. Covered by tests: transparent refresh-and-replay, three
concurrent 401s causing exactly one refresh, a rejected refresh ending the
session without looping, a network failure during refresh *keeping* the session,
session restore from the stored token, role filtering for all four roles, and an
unknown server role falling back to `viewer` rather than `admin`.

*Blocked:* "Google sign-in works end to end" cannot be verified without OAuth
client IDs. Everything either side of the Google call is built and tested.

Three notes worth carrying forward:

- **`google_sign_in` 7.x is a different library.** `signIn()` is gone in favour
  of `initialize()` + `authenticate()`, results arrive on a stream, and on web
  `supportsAuthenticate()` is false — the flow can only be started by Google's
  own rendered button. That button lives behind a conditional import; the shared
  authentication-events stream is what lets mobile and web share one code path.
- **Versions moved well past §2.3.** `go_router` 17 (planned 14),
  `flutter_secure_storage` 11 (planned 9.2, and its `encryptedSharedPreferences`
  option is gone because encryption is no longer optional). `intl` must be
  pinned to exactly `0.20.2` or version solving fails against the SDK's
  `flutter_localizations`.
- **The phone navigation had to change to reach parity.** The prototype's phone
  bar has five entries and orphans seven screens (`index.html:438`). Four
  primary destinations plus a "المزيد" sheet now reach everything the desktop
  sidebar does. This restores existing capability rather than adding any.

**Phase 4 — Read-only domain** ✅ **COMPLETE**
Endpoints 7, 9, 10, 12, 14, 15, 16 and 17, plus the six screens: families list,
family detail, members, receivables, statements, officials.

*Verified:* `npm run verify:phase4` — **20 checks**, all passing.

The acceptance bar was "every figure matches index.html", so the harness does not
compare against hand-written expectations, which would only prove the port
matches what I *believed* the prototype did. Instead
`scripts/parity/prototype_oracle.ts` reads `index.html`, slices out its ten pure
functions, and executes them in a `node:vm` sandbox. The port is then compared
against the prototype's own running code:

- **3,470 differential comparisons** — `ageOn` (690), the eligibility
  classifier across all three membership statuses and all four outcome branches
  (2,070), the month countdown including its 30.4375-day month (690), plus
  receivable status and the period helpers. Zero disagreements.
- **Every endpoint figure** against the same figure computed from the
  prototype-shaped JSON: family counts and money, per-son eligibility badges and
  ages, the unified member index, receivable totals and Arabic period labels,
  and the account statement row by row including its running balance and
  closing figure.
- **Sixteen search queries** (ten family, six member) returning byte-identical
  result sets to the prototype's filter.

Both representations come from one fixture module
(`src/fixtures/dev_fixture.ts`), which emits the MySQL rows and the
`family_association_v1` JSON from the same source, so a reported difference is
always a real logic difference and never two fixtures drifting apart. The
harness pins `TZ=UTC` because the prototype builds dates in browser-local time
while the port works in UTC; under UTC the two are identical.

Notes:

- **Derived figures are computed in TypeScript, not SQL.** The "approaching the
  age" branch is elapsed-time arithmetic that SQL cannot reproduce faithfully,
  and an approximation would put the API and the prototype into quiet
  disagreement — exactly what this phase exists to prevent. Listings therefore
  load the association into memory, which is what `index.html` already does.
- **Arabic wire values are contained in one file.** `lib/core/domain/wire_values.dart`
  is the only place the database's Arabic enum strings may appear in the client;
  the RTL lint fails the build on any elsewhere. This is risk R7's mitigation
  made mechanical, and the lint caught five violations while the screens were
  being written.
- A **suspended son of billable age** is covered by a dedicated fixture member
  and check, because rule 1's "status overrides age" clause is precisely what a
  naive age-only implementation gets wrong.

**Phase 5 — The financial engine** ✅ **COMPLETE** ⚠ *highest risk*
Endpoints 18, 19, 22, 23, 24, 25 — plus 20 and 21, which the payments screen
cannot exist without and which no phase had claimed. Screens: payments list,
payment sheet, cash ledger, and generation controls on the receivables screen.

*Verified:* `npm run verify:phase5` — **22 checks**, all passing. Every one of
the five originally-specified criteria holds:

- **1,000 random operations** — 467 payments, 139 over-payments correctly
  refused, 149 reversals, driven by a seeded PRNG so any failure is
  reproducible. The five ledger invariants are asserted after **every single
  operation**, not just at the end: `SUM(receivables.paid)` equals the summed
  allocations of approved payments, no balance is negative, nothing is
  over-paid, approved payments equal approved cash movements, and every payment
  has exactly one cash movement.
- **A genuine concurrency race.** Two simultaneous payments of 60% of the
  balance each — deliberately not 100%, because if both asked for the whole
  balance the loser would see zero debt and the test would pass even against a
  *stale* snapshot. At 60% the loser must see the winner's committed balance, and
  it did: refused with `maxAllowed` equal to the 40% remainder. Exactly one
  payment row was written.
- **Reversal compared against a snapshot** taken before the payment, not
  against a recomputed expectation. Restored to the byte, with the payment and
  cash movement voided and every allocation row kept.
- Generating a period twice creates zero rows the second time; a fee change
  leaves a historical receivable untouched while the next period uses the new
  figures (May stayed 30.00, November raised at 100.00).

Two things the checks pin down that a naive implementation gets wrong:

- **Eligibility is judged at the end of the period, never today.** August raised
  30.00 and September 40.00 for the same family, because a son reaches 16 on
  20 September. Using "now" would bill the wrong months for any receivable
  raised late.
- **Segregation of duties is real.** A treasurer may take money but is refused
  (403) on both cancellation and generation; a finance manager may cancel. This
  is the reason four roles exist rather than one admin flag.

**One deliberate deviation from §7 item 8.** The plan called for a live preview
of which periods a payment would settle *before* confirming. That would mean a
second implementation of the FIFO rule on the client, able to disagree quietly
with the server's. Instead the sheet shows the outstanding balance and validates
against it, and the receipt shown immediately after confirming lists the
allocation the **server actually performed**. The trade is a moment later
feedback in exchange for having exactly one allocation algorithm in the system.

**Phase 6 — Reporting and oversight** ✅ **COMPLETE**
Endpoints 8, 26, 27, 28 and 29, plus **11 and 13** (the family write path, which
no phase had claimed). Screens: dashboard, alerts, reports, audit trail,
settings, user management, and the family create/edit form. The nightly
reconciler is `npm run reconcile`.

*Verified:* `npm run verify:phase6` — **21 checks**, all passing. All three
originally-specified criteria hold, each measured against the prototype's own
extracted code rather than a hand-written expectation:

- The dashboard's ten figures equal the prototype's `stats` object exactly.
- The alert list matches item for item — **type, wording and order**. Ordering is
  part of the behaviour: per family, approaching-age sons first, then the debt,
  then the partially-paid receivables.
- A settings change is audited with `old → new` per field ("20.00 → 35.00",
  "16 → 18"), and a historical receivable is confirmed unmoved by it.

Two details the checks pin down:

- **The eligibility tally deliberately does not add up.** index.html:232 is an
  `else if` chain, so an inactive member lands in none of the
  eligible/soon/under buckets and the three do not sum to the son count. A
  tidier implementation would silently disagree with the association's own
  dashboard, so a dedicated check asserts the discrepancy is exactly one for the
  fixture's suspended son.
- **The reconciler is proved able to fail.** A clean pass proves nothing on its
  own, so two checks plant real inconsistencies — a receivable whose `paid`
  disagrees with its allocations, and a voided payment left with live cash — and
  assert the reconciler catches each, then comes back clean once restored.

**Two bugs found by the suite, both in code written this phase:**

1. **Editing a family reported the father's own national ID as a duplicate.**
   The uniqueness check excluded only the member ids the client echoed back, so
   any client that did not resend every id could never save an edit. Members of
   the family being edited are now excluded wholesale — each is either updated or
   removed by the same request, so none can be a genuine clash, and duplicates
   *within* the submitted form are caught separately.
2. **A new son could not reuse a removed son's national ID.** Inserts ran before
   deletes, so correcting a mistyped identifier by replacing the row collided
   with the unique index. Removals now happen first.

**Phase 7 — Migration and cutover** 🟡 **DATA MIGRATION COMPLETE, PDF OUTSTANDING**
Endpoint 30, a dry-run validator, the export download, and two CLIs.

*Verified:* `npm run verify:phase7` — **15 checks**, all passing.

The strongest available statement about an importer is a **round trip**: import a
file, export it again, and require the result to reproduce the input. That is
check T06, and it catches whole classes of error — a dropped field, a mangled
date, a lost reference — that no list of per-field assertions would think to
look for. The export is then fed back through validation (T07) to prove it is a
real backup rather than a debug dump.

- All twelve §8.4 invariants pass on import, and **each one is separately proved
  able to fail**: eight distinct breaches are planted (duplicate national ID,
  dangling family reference, dangling allocation, fees not summing to the total,
  payment not matching its allocations, a payment with no cash movement, two live
  receivables for one period, misaligned eligible-son arrays) and each must be
  caught by the specific named check. A validator that never fails validates
  nothing.
- A semantically broken file is refused and **writes nothing** — asserted by
  counting rows after the refusal, not by trusting the transaction.
- Re-import over live data needs **both** `--force` and `--confirm-drop`; one
  alone is refused.
- The import is audited with the file's SHA-256, so the exact input stays
  identifiable afterwards.
- Imported history is immutable like any other: the snapshot trigger and delete
  guards apply to it too.

**Deviation: the import is a CLI, not an in-app upload.** `npm run import-legacy
-- backup.json` (with `--dry-run` first). This runs once, at cutover, by an
administrator who has the file on their machine; pushing several megabytes of an
association's history through a phone would be worse in every respect and would
put the riskiest operation in the system behind the least controlled interface.
The HTTP endpoint exists and is tested, so an in-app upload remains possible.

An in-app file picker was attempted and abandoned: `file_picker` 8–11 requires
`win32 ^5.9` while `flutter_secure_storage` 11 requires `win32 ^6.0.1`, and pub
silently resolved to a 2021-era `file_picker` 3.0.4 rather than reporting the
conflict. Taking a beta or downgrading secure storage to satisfy a
convenience feature was the wrong trade.

**⚠ Outstanding: PDF export for statements, receipts and reports.** The code is
not written, and the reason is a font. The `pdf` package ships no Arabic glyphs,
so Arabic renders as blanks without a bundled TTF — and the obvious local
candidate, Tahoma (which the prototype's CSS names), is a Microsoft font that
cannot be redistributed inside an application. This needs an
openly-licensed Arabic face added to `app/assets/fonts/`; **Noto Naskh Arabic**,
**Amiri** or **Cairo** are all OFL and suitable. Once one is in place the
generation itself is straightforward. Writing it against a font that is not
there would produce code that cannot be tested and silently renders empty
Arabic, which is worse than not writing it.

*Not verified:* the association's **real** backup file has not been imported,
because it lives on their machine. The harness uses a file in exactly the
prototype's shape, and the CLI prints the treasury figure specifically so it can
be compared against what `index.html` shows on its الصندوق screen.

**Phase 8 — Hardening and release** ✅ **COMPLETE**
Backup and restore, ledger reconciliation, rate limiting on writes as well as
`/auth/*`, request correlation ids, least-privilege database grants, a secret
scan, Arabic app naming across Android/iOS/web, and signed release
configuration. Operational procedures in [`OPERATIONS.md`](OPERATIONS.md).

*Verified:* `npm run verify:phase8` — **14 checks**, all passing.

The headline criterion holds: **an automated backup restores cleanly into a
scratch database** and the restored copy reconciles. `npm run restore-test` does
this on demand. It checks more than row counts — all 10 triggers and 3 generated
columns must survive, and a `DELETE` on the restored copy must still be refused.
A dump that restored the data but not the triggers would produce a database that
silently permits what this one forbids, which is the most dangerous kind of
successful-looking restore.

Two hardening checks are worth naming because the controls they cover are easy to
configure wrongly and impossible to notice:

- **A spoofed `X-Forwarded-For` cannot reset the rate limit.** `TRUST_PROXY`
  defaults to 0, so eight requests carrying eight different forwarded addresses
  still share one bucket. Had the header been trusted by default, the limiter
  would have been decorative.
- **No secret is committed.** The scan looks for the *live* `JWT_SECRET` value in
  every tracked file type, plus private keys, Google client secrets and
  hard-coded keystore passwords. Matching on the *name* "JWT_SECRET" instead just
  flags every file that mentions it.

Three bugs found and fixed while writing this phase:

1. **Backups taken in the same second overwrote each other.** The filename
   truncated the timestamp to seconds, so the retention test found two files
   where it had created four — exactly the failure a retention policy must not
   have. Milliseconds are now included.
2. **The request-correlation id disappeared when logging was switched off,**
   because it was generated inside the `pino-http` block. Correlation must not
   depend on a logging flag; it is now its own always-on middleware and
   `pino-http` picks up `req.id`.
3. **`config` was shadowed inside `createApp`** by the `AuthConfig` parameter, so
   `config.isProduction` silently referred to the wrong object. Caught by the
   typechecker once HSTS started reading it.

Enabling R8 minification also broke the release build with a wall of
"Missing class" errors: Flutter's engine references the Play Store
deferred-components API unconditionally, but the dependency only ships with
`com.google.android.play:core`. The app has no deferred components, so
`proguard-rules.pro` tells R8 not to fail on genuinely dead references.

*Not verified:* **installing on a physical Android device** and completing
sign-in → payment → cash flow there. The artifacts build (`app-release.aab`
43 MB, per-ABI APKs 17–20 MB) but there is no device here, and sign-in needs the
OAuth client IDs regardless. That end-to-end pass is the association's to run.

---

## 11. Risks and open decisions

### 11.1 Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | Concurrent payments to one family double-spend a balance | **Critical** — the treasury reconciles wrong and trust in the system is lost | `SELECT … FOR UPDATE` in fixed `period ASC` order; `CHECK (paid <= total)`; the 1,000-sequence property test is a Phase 5 gate |
| R2 | Float arithmetic corrupts money | **Critical** — silent drift found only at audit | `DECIMAL(12,2)` in MySQL; `mysql2` returns strings; all arithmetic in integer minor units; a lint ban on `parseFloat` in the money path |
| R3 | Ported business logic silently diverges from the prototype | High — figures no longer match and nobody can say which is right | Port the six functions verbatim; unit tests assert against fixtures generated from the prototype; Phase 4 and 6 acceptance is figure-for-figure equality |
| R4 | Timezone shift moves a payment across a month boundary | High — a payment lands in the wrong report | Store UTC everywhere; convert only at the presentation edge; `period_end` is a stored `DATE`, never derived at query time |
| R5 | RTL breakage from hard-coded `left`/`right` | Medium — visibly broken Arabic layout | `EdgeInsetsDirectional` mandatory; lint rule from Phase 3; golden tests for the four widest screens |
| R6 | Arabic text mangled by wrong charset | Medium — enum values and names corrupt | `utf8mb4_unicode_ci` on schema, tables, columns, and the connection; `charset: 'utf8mb4'` in the pool config; an Arabic round-trip assertion in Phase 1 |
| R7 | Arabic enum values stored in the database | Medium — a spelling change breaks every query | Accepted deliberately, for fidelity to the prototype and a clean import. Contained by mapping every enum to an ARB key for display, and never comparing against a literal outside a single constants module |
| R8 | Family code collision under concurrency | Medium — duplicate codes on receipts | Derived from `AUTO_INCREMENT` id inside the transaction; `UNIQUE` index |
| R9 | Google Cloud OAuth misconfiguration | Medium — nobody can sign in on release builds | Android needs the release SHA-1 registered in addition to debug; iOS needs the reversed client ID URL scheme; Web needs the meta tag. Register all three in Phase 2, not at release |
| R10 | `google_sign_in` 7.x API break vs 6.x tutorials | Low — wasted implementation time | Noted in section 2.3; read the package migration guide first |
| R11 | Audit and receivables tables grow unbounded | Low — slow queries in year three | Indexed by time, paginated at 50; archive strategy revisited when `audit_log` exceeds one million rows |
| R12 | No automated backups | **Critical if it happens** — total data loss | Nightly `mysqldump` with a restore test in Phase 8. See open decision D1 |
| R13 | **MariaDB 10.4 reached end of life in June 2024** — it receives no security patches, and it is the engine the development machine actually runs | High, but deferred — it is a hosting concern, not a schema concern. Every construct the schema uses was probed and works on 10.4 | The schema is engine-portable as written and needs no change to run on MySQL 8 or a supported MariaDB. Fold the production engine choice into open decision D1 rather than treating it as settled by what XAMPP happens to ship |
| R14 | Non-strict `sql_mode` silently corrupts data | **Critical** — truncated national IDs, money coerced to 0 | Found during the Phase 1 probe. Every connection now sets a strict `sql_mode`; assertion T26 in `npm run verify` fails if that regresses |

### 11.2 Conflicts found between the stated rules and `index.html` — unresolved

Per instruction, these are reported and **not** resolved.

**C1 — Rule 10's future-date check is not enforced for fathers.**
Rule 10 states "Date of birth cannot be in the future" for members generally. In `index.html` the check exists only inside the sons loop (`saveFamily`, line 309: `if(s.dob && new Date(s.dob) > new Date())`). The father's `dob` is validated for nothing. The schema in section 3.3 specifies a trigger covering **all** members, which is stricter than current behaviour and could reject a legacy record on import.
*Decision needed:* apply the rule to fathers as written (and risk an import abort on an existing bad row), or replicate the prototype exactly and check sons only? **I have not chosen.** The trigger is written for the strict reading and is flagged here so you can decide before Phase 1.

**C2 — Receivable status `ملغي` is unreachable.**
`ملغي` is filtered on in fifteen places and is central to rule 4's uniqueness semantics, but **no code path ever sets it** — there is no cancel-receivable function anywhere in the file. Only *payments* can be cancelled. The schema and rule 4 index assume the state is reachable.
*Decision needed:* leave receivable cancellation unimplemented (dead state, correct index) or add a cancel-receivable endpoint? Adding one is new functionality, so it sits in section 12 and is **not** in phases 1–8.

**C3 — The dashboard's "close month" button acts on the previous month.**
`Dashboard` binds `const thisMonth = previousPeriod()` (line 452) and labels the button "إقفال {periodLabel(thisMonth)}". The behaviour matches rule 6, so this is a misleading variable name rather than a logic fault — flagged only so the Flutter port copies the *behaviour* (previous month) and not the *identifier*.

### 11.3 Open decisions — blocked on you

| # | Decision | Why I did not choose |
|---|---|---|
| **D1** | **Hosting and backups** — where the API and MySQL run, and where nightly dumps are stored | Every realistic option implies a paid service, and I was instructed to stop before choosing one. Phase 8 cannot complete until this is settled. Constraints to weigh: the association's data should plausibly stay in-region, and MySQL 8 with automated backups is the minimum bar |
| **D2** | C1 above — strict or prototype-faithful DOB validation | A behaviour change either way. **Provisionally implemented strict** (fathers and sons both) in `api/migrations/005_members.sql` so Phase 1 could proceed; reverting to the prototype's sons-only behaviour means adding `AND NEW.kind = 'son'` to both trigger conditions. Still yours to decide — it is marked in the migration and in `api/README.md` |
| **D3** | C2 above — implement receivable cancellation or leave the state dead | Adding it is new functionality |
| **D4** | Google Workspace domain restriction — should sign-in be limited to one email domain (`hd` claim)? | Depends on whether members use personal Gmail accounts. Approval gating covers it either way; the domain check is defence in depth |
| **D5** | Whether `index.html` is retired or kept as a read-only reference after cutover | Operational preference. This plan assumes it is kept untouched and read-only through the first production month |

---

## 12. Proposed additions (out of scope)

None of the following appears in phases 1–8, in the schema of section 3, or in the endpoints of section 4. They are recorded because the migration surfaces them, not because they are planned.

| Addition | Why it comes up | Prerequisite |
|---|---|---|
| **Expenses and disbursements** | `cash_movements.movement_type` has exactly one value, `تحصيل`. The "صندوق" screen therefore reports collections, not a true cash position — money out is invisible | A new movement type, a spending-authority role, and a revised cash summary |
| **Receipt reference required for bank transfers** | A transfer with no reference cannot be reconciled against a bank statement, but the prototype leaves it optional, so no `CHECK` was added | A validation rule change |
| **Family and member deletion** | No delete path exists anywhere; a family created by mistake is permanent | A soft-delete column and a rule for what happens to its receivables |
| **Receivable cancellation** | See conflict C2 — the state exists and is unreachable | Decision D3 |
| **Push notifications for age and debt alerts** | The alerts screen requires someone to open the app and look | FCM, a device-token table, a scheduler |
| **Member self-service portal** | Families can currently only learn their balance by asking an official | A separate lower-privilege auth path and a much narrower API surface |
| **Officials linked to user accounts** | Treasurer and finance manager are free-text strings in settings while `users` holds real identities; the two can disagree | Foreign keys from settings into `users` |
| **Multi-association tenancy** | The settings singleton hard-codes one association | A tenant column on every table |
| **Automated monthly generation** | Auto-close still requires someone to open the app, exactly as the prototype does on mount | A server-side scheduler |
| **Hijri calendar display** | The association is Libyan and the app formats Gregorian dates only | A calendar-conversion library and a user preference |
| **Two-factor for admin accounts** | Google Sign-In inherits whatever 2FA the Google account has, which the association does not control | An app-level TOTP enrolment flow |

---

*End of plan. No application code, project scaffolding, or dependencies were created by this document.*
