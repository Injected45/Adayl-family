# Turning on Google sign-in

Everything below is done once. Total time is about fifteen minutes, most of it
waiting for the Google Cloud console.

## What you are actually setting up

This app does **not** use the browser redirect flow, so nothing here involves a
redirect URL or a deep link. It calls `signInWithIdToken`: `google_sign_in`
obtains an ID token on the device, hands it to Supabase, and Supabase verifies
it against Google directly.

That means three identities have to line up:

| Thing | Where it lives | Why |
|---|---|---|
| **Android OAuth client** | Google Cloud | Google will not issue a token to your app at all unless it recognises the package name + signing certificate |
| **Web OAuth client** | Google Cloud | Names the *audience* of the token — the backend allowed to verify it. This is Supabase |
| **Client ID + secret** | Supabase dashboard | How Supabase proves it is that audience |

The single most common failure: using the **Android** client ID as the server
client ID. The token is issued, the device is happy, and Supabase rejects it —
because the token says "for the Android app" and Supabase is not the Android
app. **Always use the web client ID.**

The client **secret** never leaves the Supabase dashboard. It must not appear in
`run_emulator.bat`, in a `--dart-define`, or anywhere in this repository —
anything there ships inside the APK.

---

## 1. Google Cloud — create the two OAuth clients

<https://console.cloud.google.com/apis/credentials>

Create a project first if you have none.

If the console asks you to configure the **OAuth consent screen** before it will
let you create credentials:

- User type **External**
- App name, your support email, your developer email — that is all that is
  required
- Scopes: leave the defaults. The app asks only for `email` and `profile`
- Test users: while the app is in *Testing*, only addresses listed here can sign
  in. **Add every family-association account that will use the app**, or publish
  the app once you are ready

Now **Create Credentials → OAuth client ID**, twice.

### a. Android

| Field | Value |
|---|---|
| Application type | Android |
| Name | anything, e.g. `family-app-android` |
| Package name | `ly.adayl.family_app` |
| SHA-1 | `58:C5:F7:AB:55:07:55:97:13:FA:02:87:C5:95:6C:E9:87:C0:5E:8A` |

That SHA-1 is **this machine's debug keystore**
(`C:\Users\ahmed\.android\debug.keystore`). It is what debug builds are signed
with, so it is what you need for testing on the emulator.

**Add the release fingerprint too**, and it is the one that matters — the APK in
`apk/` is what people install, and it is signed with `adayl-upload.jks`, not the
debug key:

| Which build | SHA-1 |
|---|---|
| `run_emulator.bat`, `flutter run` | `58:C5:F7:AB:55:07:55:97:13:FA:02:87:C5:95:6C:E9:87:C0:5E:8A` |
| `build_apk.bat` (the distributed APK) | `EC:C6:C8:07:6B:E2:38:6A:DD:4F:9B:86:6E:29:12:A2:22:0C:99:61` |

Both go on the **same** Android client. Confirm either at any time with:

```bash
keytool -list -v -alias <your-alias> -keystore <your-release.keystore>
```

You can add several SHA-1s to one Android client, so debug and release can
coexist. If you ever ship through Google Play with Play App Signing, add the
SHA-1 that Play shows you under *Release → Setup → App signing* as well —
that is the key Play re-signs with, and it is not yours.

You do **not** need to download anything from this client. No
`google-services.json` is required; the app does not use Firebase.

### b. Web

| Field | Value |
|---|---|
| Application type | Web application |
| Name | anything, e.g. `family-app-supabase` |
| Authorised redirect URI | `https://wvryyidbjvvomurvfhpw.supabase.co/auth/v1/callback` |

Copy the **client ID** and the **client secret** from this one.

---

## 2. Supabase — enable the provider

Dashboard → **Authentication → Providers → Google**

- Toggle **Enable Sign in with Google**
- **Client ID** — the *web* client ID from step 1b
- **Client Secret** — the *web* client secret
- Save

Under **Authentication → URL Configuration**, add
`ly.adayl.family_app://login-callback` to *Redirect URLs*. The current flow
never uses it, but it costs nothing and it is what a future browser-based flow
would need.

---

## 3. The app — paste the web client ID

Open `run_emulator.bat` and fill in the line near the top:

```bat
set "GOOGLE_SERVER_CLIENT_ID=123456789-abcdefg.apps.googleusercontent.com"
```

The **web** client ID, on Android too. See the table at the top for why.

Then:

```bat
run_emulator.bat
```

For web builds, pass the same value to `app/run_supabase.sh`:

```bash
flutter run -d chrome \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=... \
  --dart-define=GOOGLE_CLIENT_ID=...          # web needs this one as well
```

---

## 4. First sign-in

Tap **الدخول بحساب Google**. You will land on
**"في انتظار الموافقة"** — awaiting approval. This is correct: every new profile
is created `viewer` / `pending`, and the router sends pending accounts to that
screen.

An existing admin approves the account under **الإشراف → المستخدمون**.

If you have no admin yet, that is the bootstrap problem — the first person has
nobody to approve them. Run `supabase/bootstrap_first_admin.sql` in the SQL
editor with your address. See `docs/SUPABASE_SETUP.md`.

---

## Letting anyone sign in, without collecting their keys

Google mints an ID token only for a registered **package name + signing SHA-1**
pair. A teammate who builds from source therefore cannot sign in: their machine
has its own debug keystore, so the app they built is, to Google, a different app.

**It shows as "تم إلغاء تسجيل الدخول", not as an error.** Play Services reports
a refusal through the same `canceled` code the user's own back-press produces,
with the real reason only in `GoogleSignInException.description` — observed
values include `[16] Account reauth failed` and, for a signature Google does not
recognise, an equally uninformative cancellation. That is why
`google_auth_service.dart` logs the description on every occurrence, release
builds included: the code alone cannot tell a refusal from a dismissal, and the
description is the only thing that can.

So a cancellation you did not perform is worth reading the log for before
assuming anyone cancelled anything:

```bash
adb logcat | grep 'reported "canceled"'
```

Registering every developer's debug fingerprint does not scale and is not the
fix. **Distribute a signed APK instead.** The signature travels inside the file,
so one registered fingerprint covers every person who installs it — they never
generate a key at all.

```bat
build_apk.bat                 release APK, signed, into apk\
build_apk.bat --split         one per ABI, ~20 MB each
```

Signing is already wired: `app/android/app/build.gradle.kts` reads
`app/android/key.properties`, and falls back to the debug key only when that
file is absent. Neither the properties file nor the keystore is committed —
both are gitignored, and the keystore lives outside the repository entirely.

**Create the key once:**

```bash
keytool -genkeypair -v -alias upload -keyalg RSA -keysize 2048 -validity 10000 -keystore /path/outside/the/repo/upload.jks
```

Then `app/android/key.properties`:

```properties
storePassword=...
keyPassword=...
keyAlias=upload
storeFile=/absolute/path/to/upload.jks
```

**Register its fingerprint** on the Android OAuth client, alongside the debug
one so local `run_emulator.bat` runs keep working:

```bash
keytool -list -v -keystore /path/to/upload.jks -alias upload
```

**Back the keystore up somewhere that is not the build machine.** It is the
app's identity: Android refuses to install an update signed by a different key,
so losing it means every installed copy must be uninstalled before a new build
will go on, and the OAuth client needs a new fingerprint.

Verify what a built APK is actually signed with — the fallback to the debug key
is silent, and a debug-signed "release" fails sign-in on every machine but the
one that built it:

```bash
apksigner verify --print-certs apk/adayl-release.apk
```

---

## When it does not work

**"لم يتم إعداد الدخول بحساب Google على الخادم بعد."**
`GOOGLE_SERVER_CLIENT_ID` is empty, so `AppConfig.isGoogleConfigured` is false
and `auth_controller.dart` refuses before it ever reaches Google. Step 3.

**`ApiException: Unacceptable audience in id_token`** — or Supabase returns 400
after the account chooser closes.
You used the Android client ID. Use the web one.

**"تم إلغاء تسجيل الدخول" when you did not cancel anything.**
Read the log line above before anything else — `description` names the cause and
the three below are not otherwise distinguishable.

**`[16] ...` on a machine other than the one that built the APK.** The build is
signed with that machine's own debug key. This is the common one, and the
section above is the fix: install the distributed APK, do not build.

**`[16] Account reauth failed`.** The Google account on the DEVICE needs
re-authenticating and the attempt failed — frequently because the device has no
screen lock, which Google's reauth step requires. Set a lock, or remove and
re-add the account. Nothing server-side is involved; the token never left the
device.

**Otherwise, the consent screen may be refusing the account:**

- **Audience = Internal**, and the account is outside the organisation. A
  personal Gmail is always outside.
- **Publishing status = Testing**, and the account is not on the test-user list.
  This is the default for a new Cloud project, so it is what a freshly created
  project does to everyone except the addresses you list. It is the likely
  answer whenever sign-in works for you and fails for the family.

Fix at <https://console.cloud.google.com/auth/audience> for project
`891008495666`: add every association address under **Test users**, or set the
app to **In production**. Publishing needs no Google verification here — the app
requests only `email` and `profile`, which are not sensitive scopes.

Google's own wording for the refusal is written to logcat on every occurrence,
release builds included:

```bash
adb logcat -s flutter | findstr "canceled"
```

**`PlatformException(sign_in_failed, ... 10: )`**
Error 10 is `DEVELOPER_ERROR`, and it means Google does not recognise the
package name + SHA-1 pair. Either the Android OAuth client is missing, the SHA-1
is from a different keystore than the build you are running, or the package name
is not exactly `ly.adayl.family_app`. This is the `google_sign_in` 6.x shape; on
7.x the same cause reads as the app's generic error instead.

**`Error 403: access_denied`.**
The consent screen is in *Testing* and this address is not on the test-user
list.

**Sign-in succeeds and the app sits on "awaiting approval".**
Working as designed. Approve the account (step 4).

**It worked yesterday and not today.**
Check whether the debug keystore was regenerated — it expires, and Android
Studio silently creates a new one, which changes the SHA-1. Re-run the `keytool`
command above and compare.
