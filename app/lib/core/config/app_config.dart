import 'package:flutter/foundation.dart';

/// Build-time configuration for GOOGLE SIGN-IN only.
///
/// Everything else that used to live here is gone, and it is worth naming what:
///
///   apiBaseUrl                — there is no REST API. See SupabaseConfig.url.
///   connectTimeout/receive    — the Supabase client owns its own timeouts.
///   devLogin*                 — moved to SupabaseConfig, and it is now an
///                               ordinary email/password sign-in with no special
///                               privilege rather than a server route to leave
///                               switched on by accident.
///
/// What remains is needed on the DEVICE, because the Google ID token is obtained
/// there by `google_sign_in` before being handed to Supabase for verification.
/// Supabase then checks it against Google itself, which is why the client SECRET
/// still never appears here — it lives in the Supabase dashboard, under
/// Authentication → Providers → Google.
abstract final class AppConfig {
  /// The WEB client ID, even on Android and iOS: it tells Google which backend
  /// the ID token is destined for. Its absence is the usual reason a token
  /// verifies on the device and is then rejected by Supabase.
  ///
  /// For Supabase this must be the client ID registered in the dashboard's Google
  /// provider settings, not an arbitrary one from the same project.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Platform client ID. Required on web and iOS; Android derives it from the
  /// signing certificate registered in the Google Cloud console.
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );

  static bool get isGoogleConfigured =>
      googleServerClientId.isNotEmpty || googleClientId.isNotEmpty;

  /// Debug-only diagnostics, kept off release builds.
  static bool get verbose => kDebugMode;
}
