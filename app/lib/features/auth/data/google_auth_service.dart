import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';

/// Wraps google_sign_in 7.x.
///
/// The 7.0 release replaced the 6.x `signIn()` call with `initialize()` plus
/// `authenticate()`, and made results arrive on a stream. That stream is the
/// unifying detail: on Android and iOS our own button calls `authenticate()`,
/// while on web Google's rendered button starts the flow itself — both surface
/// the same sign-in event, so the rest of the app has one code path.
class GoogleAuthService {
  final StreamController<String> _idTokens =
      StreamController<String>.broadcast();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  bool _initialized = false;

  /// Emits a Google ID token each time a sign-in completes.
  Stream<String> get idTokens => _idTokens.stream;

  bool get isConfigured => AppConfig.isGoogleConfigured;

  /// False on web, where `authenticate()` throws and Google's own button must
  /// be rendered instead.
  bool get supportsInteractiveSignIn =>
      _initialized && GoogleSignIn.instance.supportsAuthenticate();

  Future<void> initialize() async {
    if (_initialized || !isConfigured) return;

    await GoogleSignIn.instance.initialize(
      clientId: AppConfig.googleClientId.isEmpty
          ? null
          : AppConfig.googleClientId,
      serverClientId: AppConfig.googleServerClientId.isEmpty
          ? null
          : AppConfig.googleServerClientId,
    );

    _subscription = GoogleSignIn.instance.authenticationEvents.listen(
      _handleEvent,
      onError: (_) {
        // Stream errors are surfaced through the interactive call instead;
        // an unhandled error here would tear the stream down.
      },
    );
    _initialized = true;

    // attemptLightweightAuthentication() is deliberately NOT called. Session
    // restore is our refresh token's job; asking Google to silently re-auth as
    // well would race two sign-in paths on start-up.
  }

  void _handleEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(
        :final GoogleSignInAccount user,
      ):
        final String? idToken = user.authentication.idToken;
        if (idToken != null && idToken.isNotEmpty) {
          _idTokens.add(idToken);
        }
      case GoogleSignInAuthenticationEventSignOut():
        break;
    }
  }

  /// Starts an interactive sign-in on platforms that support it.
  ///
  /// Returns false when the user dismissed the picker — an ordinary outcome
  /// that must not be shown as an error.
  Future<bool> promptSignIn() async {
    if (!_initialized) await initialize();
    if (!supportsInteractiveSignIn) return false;

    try {
      await GoogleSignIn.instance.authenticate();
      return true;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        // `canceled` does NOT only mean the user dismissed the picker. Google
        // Play Services reports a REFUSAL the same way, and the app then says
        // "تم إلغاء تسجيل الدخول" for what is actually a misconfiguration.
        //
        // Seen for real: an Internal consent screen refusing a personal Gmail
        // with "This client is restricted to users within its organization."
        // The chooser had appeared and an account had been picked, so it looked
        // for all the world like a cancellation, and the true reason existed
        // only in logcat under the Auth tag.
        //
        // WHAT REACHING THIS BRANCH RULES OUT. From google_sign_in_android
        // 7.2.11: an unregistered SHA-1 or a wrong package name arrives as
        // NO_CREDENTIAL, and `authenticate()` passes throwForNoAuth, so it
        // surfaces as unknownError — it is rethrown below, never here. A
        // missing serverClientId is clientConfigurationError, likewise. So if
        // this branch runs, the Android OAuth client MATCHED and the refusal
        // came afterwards, from the consent screen: audience Internal, or
        // Testing with the signing-in account not on the test-user list.
        //
        // The dismissal and the refusal cannot be told apart here. Credential
        // Manager supplies a `description` for an ordinary back-press too, so
        // the earlier "a genuine dismissal has none" is not a safe test — the
        // reason is logged and the outcome is still treated as a dismissal,
        // because showing an error on every back-press is the worse mistake.
        //
        // Logged in release as well, deliberately: the APK people actually run
        // is a release build, so a kDebugMode gate here meant the one
        // occurrence that mattered produced no evidence at all.
        final String? why = error.description;
        if (why != null && why.isNotEmpty) {
          debugPrint('Google sign-in reported "canceled": $why');
        }
        return false;
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    if (!_initialized) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Clearing our own session matters; Google's cached state does not.
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _idTokens.close();
  }
}
