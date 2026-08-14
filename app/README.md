# Family App — Flutter client

Arabic-first (RTL) Flutter client for **جمعية العائلة**, talking to the REST API
in [`../api`](../api). See [`../docs/MIGRATION_PLAN.md`](../docs/MIGRATION_PLAN.md)
for the whole architecture and phase plan.

**Phase 3 (shell and sign-in) is complete.** The thirteen business screens are
Phases 4–6 and currently render a "coming soon" placeholder.

---

## Running it

The API must be running first:

```bash
cd ../api && npm start        # http://127.0.0.1:3000
```

Then:

```bash
flutter run -d chrome         # web
flutter run                   # a connected Android device or emulator
```

The API base URL defaults per platform, because an Android emulator cannot
reach the host on `127.0.0.1` — that address is the emulator itself:

| Target | Default base URL |
|---|---|
| Web, iOS simulator, desktop | `http://127.0.0.1:3000/api/v1` |
| Android emulator | `http://10.0.2.2:3000/api/v1` |

Override it for a physical device on your LAN:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000/api/v1
```

## Checks

```bash
flutter analyze                 # 0 issues
dart run tool/rtl_lint.dart     # RTL + hard-coded-Arabic checks
flutter test                    # 27 tests
flutter build web --release
flutter build apk --debug
```

---

## Google Sign-In needs setup before it will work

Everything else runs today. Sign-in cannot, because it needs OAuth client IDs
that only you can create. Until they exist the login screen renders and
explains itself rather than failing silently.

**1. Create the client IDs** at
<https://console.cloud.google.com/apis/credentials> — one OAuth 2.0 Client ID
per platform you want to support. These are **public identifiers, not secrets**.
The Google client *secret* belongs only to the server and must never appear in
this app.

- **Web** — add your origin (e.g. `http://localhost:PORT`) to *Authorised
  JavaScript origins*.
- **Android** — register the package name `ly.adayl.family_app` together with
  your signing certificate's SHA-1. Register **both** the debug and the release
  fingerprints, or sign-in works in development and fails in the store build.
  Get the debug one with:
  ```bash
  keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
  ```
- **iOS** — register the bundle ID and add the reversed client ID as a URL
  scheme in `ios/Runner/Info.plist`.

**2. Give the same IDs to both sides.** The server verifies that the token the
app obtained was actually issued for this backend.

In `../api/.env`:
```
GOOGLE_CLIENT_ID_WEB=...apps.googleusercontent.com
GOOGLE_CLIENT_ID_ANDROID=...apps.googleusercontent.com
GOOGLE_CLIENT_ID_IOS=...apps.googleusercontent.com
```

When running the app:
```bash
flutter run \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<the WEB client id> \
  --dart-define=GOOGLE_CLIENT_ID=<this platform's client id>
```

`GOOGLE_SERVER_CLIENT_ID` is the **web** client ID even on Android and iOS — it
tells Google which backend the ID token is destined for. Omitting it is the
usual reason a token works on the device but is rejected by the server.

**3. The first person to sign in becomes the administrator.** Everyone after
that lands on the "awaiting approval" screen until that administrator approves
them. If you have already run `npm run seed`, the users table is not empty and
this bootstrap will not fire — run `npm run db:reset && npm run migrate` first.

---

## Architecture

```
lib/
├── main.dart · app.dart          MaterialApp.router, ar locale, light theme
├── l10n/                         app_ar.arb (source of truth) + app_en.arb
├── core/
│   ├── config/                   API base URL, theme from the prototype's CSS
│   ├── network/                  Dio client, interceptors, session, errors
│   ├── router/                   go_router + auth guard, destination table
│   ├── storage/                  refresh token in Keystore / Keychain
│   └── widgets/                  AppScaffold shell, empty/error/loading states
└── features/
    ├── auth/                     Google service, repository, controller, screens
    └── home/                     placeholder dashboard
```

**Where the rules live.** All twelve business rules execute on the server. The
client duplicates none of them. Role checks here decide only what to *show* —
every one is repeated by the API, because hiding a button is presentation, not
security.

**Token custody.** The access token is a 15-minute JWT held in memory and never
written to disk. The refresh token goes to the platform keystore. A 401 is
caught by an interceptor, which refreshes once — shared across concurrent
failures — and replays the original request, so no screen ever sees a 401.

**Navigation.** The prototype's phone bar has five entries and leaves seven
screens unreachable (`index.html:438`). Here a phone gets four primary
destinations plus "المزيد", which opens the rest, so a phone reaches everything
the desktop sidebar does. Tablets get a rail, desktop an expanded rail.

**RTL.** Arabic is forced rather than following the device, and Flutter derives
text direction from the locale. `tool/rtl_lint.dart` fails the build on physical
`left`/`right` layout (`EdgeInsets.only(left:)`, `Alignment.centerLeft`,
`TextAlign.left`, …) and on Arabic string literals outside `lib/l10n`, neither
of which the Dart analyzer can express.

---

## What is and is not verified

Verified by `flutter test`, `flutter analyze`, `dart run tool/rtl_lint.dart`,
and real release builds for web and Android:

- the app builds for web and Android
- an expired access token refreshes transparently and the request is replayed
- three simultaneous 401s cause exactly **one** refresh
- a rejected refresh ends the session instead of looping
- a network failure during refresh **keeps** the session — losing signal is not
  proof of an invalid session
- a stored refresh token restores a session at start-up
- an unknown role from the server falls back to `viewer`, never to `admin`
- role-based navigation filtering for all four roles
- Arabic renders RTL and every string resolves from the ARB files

**Not yet verified, and cannot be without OAuth client IDs:** an end-to-end
Google sign-in on a real device. Everything up to and after the Google call is
covered; the Google round-trip itself is not.
