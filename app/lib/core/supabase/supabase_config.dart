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
  /// Unlike the old server-side bypass, this one has no special privilege: it
  /// signs in with a real email/password against GoTrue, so the account must
  /// actually exist and its role still comes from `public.profiles`. There is no
  /// route to disable and nothing to leave switched on by accident in
  /// production — the worst case is a visible button that fails to authenticate.
  static const bool devLoginEnabled = bool.fromEnvironment(
    'DEV_LOGIN',
    defaultValue: false,
  );

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
