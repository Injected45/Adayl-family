import 'package:flutter/foundation.dart';

/// Where Supabase lives, and how the app behaves when it does not.
///
/// Both values are supplied at build time:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
///
/// The anon key is NOT a secret. It ships inside the Android binary, inside the
/// iOS binary, and in plain text in the web bundle; anyone who installs the app
/// can read it out and issue their own PostgREST calls. That is the premise the
/// whole database design rests on — every rule is enforced by RLS, CHECK
/// constraints, triggers and SECURITY DEFINER functions, so a hostile holder of
/// this key can do nothing an honest one could not.
///
/// The SERVICE ROLE key is the opposite: it bypasses RLS entirely. It must never
/// appear in this file, in a --dart-define, or anywhere else the client can see.
/// It belongs only to the one-shot legacy import script.
abstract final class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True once both values are present. When false the app still builds and runs
  /// and says why on the sign-in screen, rather than crashing at startup with a
  /// stack trace that means nothing to whoever is holding the phone.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  /// A single obvious sentence for the sign-in screen. Deliberately in English
  /// and deliberately not localised: this is a build misconfiguration aimed at
  /// whoever built the binary, not a message for the association's treasurer.
  static String get misconfigurationHint =>
      'Supabase is not configured. Rebuild with '
      '--dart-define=SUPABASE_URL=... and '
      '--dart-define=SUPABASE_ANON_KEY=...';

  /// Google OAuth is configured on the SUPABASE side (Authentication →
  /// Providers → Google), not here. The app only asks GoTrue to start the flow,
  /// so no client ID and certainly no client secret needs to reach the device —
  /// which is a straight improvement on the previous setup, where the app had to
  /// carry three separate Google client IDs.
  ///
  /// On native platforms the flow needs a deep link back into the app.
  ///
  /// The scheme is the APPLICATION ID. It was `com.family.app` here, which this
  /// app has never been called — the applicationId is `ly.adayl.family_app`, so
  /// the callback had nothing registered to receive it and OAuth would have
  /// completed in the browser and never returned.
  ///
  /// Three places must agree, or sign-in hangs after the browser closes:
  ///   1. this constant,
  ///   2. the intent-filter in android/app/src/main/AndroidManifest.xml,
  ///   3. Supabase dashboard → Authentication → URL Configuration → Redirect URLs.
  static const String nativeRedirect = 'ly.adayl.family_app://login-callback';

  /// Shows a development sign-in that skips Google.
  ///
  /// ⚠ THE OLD REASONING HERE WAS «the worst case is a visible button that
  ///   fails to authenticate», and it was wrong in the one way that mattered.
  ///   It assumed the credentials would be a developer's own. `run_emulator.bat`
  ///   passed the password of a REAL APPROVED ADMIN on the live project, and
  ///   this repository is public — so the worst case was a button that
  ///   authenticates perfectly, as the association's owner.
  ///
  /// ⚠ AND A `--dart-define` IS NOT A GUARD, because it is set by whoever runs
  ///   the build. `kReleaseMode` is set by the compiler and cannot be passed in,
  ///   so a release APK carries no dev sign-in whatever anyone types on the
  ///   command line. The define now only decides whether DEBUG builds show it.
  ///
  ///   That is a real restriction and it is the point: `flutter run --release`
  ///   with the defines set no longer offers the shortcut. Sign in with Google.
  ///
  /// ⚠ The credentials being out is a separate matter and this constant cannot
  ///   fix it — GoTrue accepts them from curl with the public anon key, with no
  ///   app involved. Rotate the password or delete the account.
  static const bool devLoginEnabled =
      !kReleaseMode &&
      bool.fromEnvironment('DEV_LOGIN', defaultValue: false);

  static const String devLoginEmail = String.fromEnvironment(
    'DEV_LOGIN_EMAIL',
    defaultValue: 'admin@fam.test',
  );

  static const String devLoginPassword = String.fromEnvironment(
    'DEV_LOGIN_PASSWORD',
    defaultValue: '',
  );

  /// Logs every PostgREST call in debug builds only.
  static bool get verbose => kDebugMode;
}
