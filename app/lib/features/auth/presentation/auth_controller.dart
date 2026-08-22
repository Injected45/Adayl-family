import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/notify/background_service.dart';
import '../../../core/providers.dart';
import '../../../core/realtime/doorbell.dart';
import '../domain/app_user.dart';

enum AuthStage {
  /// Restoring a stored session; nothing should be decided yet.
  initializing,
  signedOut,
  signingIn,

  /// Authenticated with Google, but the account awaits an administrator.
  pending,
  suspended,
  signedIn,
}

/// Locally-generated codes, distinct from the server's error codes.
abstract final class LocalAuthError {
  static const String cancelled = 'SIGN_IN_CANCELLED';
  static const String googleFailed = 'GOOGLE_SIGN_IN_FAILED';
  static const String notConfigured = 'GOOGLE_NOT_CONFIGURED';
}

class AuthState {
  const AuthState({
    required this.stage,
    this.user,
    this.pendingEmail,
    this.errorCode,
    this.serverMessage,
    this.failureKind,
  });

  final AuthStage stage;
  final AppUser? user;
  final String? pendingEmail;
  final String? errorCode;
  final String? serverMessage;
  final ApiFailureKind? failureKind;

  bool get isBusy =>
      stage == AuthStage.signingIn || stage == AuthStage.initializing;
  bool get hasError => errorCode != null || serverMessage != null;
}

final NotifierProvider<AuthController, AuthState> authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  StreamSubscription<String>? _googleTokens;

  @override
  AuthState build() {
    // Both platforms deliver a completed Google sign-in here: mobile via our
    // button calling authenticate(), web via Google's rendered button.
    _googleTokens = ref
        .watch(googleAuthServiceProvider)
        .idTokens
        .listen(_exchangeIdToken);
    ref.onDispose(() => unawaited(_googleTokens?.cancel()));

    scheduleMicrotask(_bootstrap);
    return const AuthState(stage: AuthStage.initializing);
  }

  Future<void> _bootstrap() async {
    await ref.read(googleAuthServiceProvider).initialize();

    // supabase_flutter has already read any persisted session out of the
    // keystore by the time this runs, so restore() is a profile lookup rather
    // than a token exchange.
    final AppUser? user = await ref.read(authRepositoryProvider).restore();

    // restore() returns null for "no stored session", "the stored session was
    // rejected", and "it could not be refreshed" alike. All three mean the same
    // thing to the router: show the sign-in screen.
    if (user == null) {
      state = const AuthState(stage: AuthStage.signedOut);
      return;
    }

    // Signed in with Google is not the same as let in by the association. The
    // role and the approval flag come from public.profiles, and the router sends
    // a pending or suspended account to its own screen rather than a dashboard
    // that RLS would render empty.
    state = switch (user.status) {
      AccountStatus.approved => AuthState(
        stage: AuthStage.signedIn,
        user: user,
      ),
      AccountStatus.pending => AuthState(
        stage: AuthStage.pending,
        user: user,
        pendingEmail: user.email,
      ),
      AccountStatus.suspended => AuthState(
        stage: AuthStage.suspended,
        user: user,
      ),
    };
  }

  /// Re-reads `api_me()` and re-derives the stage from it.
  ///
  /// Exists for one caller: redeeming a family access code. That turns a
  /// pending account with no family into an approved one with a family, without
  /// any sign-in taking place — so nothing else would notice, and the router
  /// would keep the man on the waiting screen he just escaped.
  Future<void> refreshProfile() async {
    final AppUser? user = await ref.read(authRepositoryProvider).restore();
    if (user == null) {
      _followSession(null);
      state = const AuthState(stage: AuthStage.signedOut);
      return;
    }
    _followSession(user);
    state = switch (user.status) {
      AccountStatus.approved => AuthState(
        stage: AuthStage.signedIn,
        user: user,
      ),
      AccountStatus.pending => AuthState(
        stage: AuthStage.pending,
        user: user,
        pendingEmail: user.email,
      ),
      AccountStatus.suspended => AuthState(
        stage: AuthStage.suspended,
        user: user,
      ),
    };
  }

  /// ── الخدمة الخلفية تتبع الجلسة ───────────────────────────────────────
  ///
  /// ⚠ THE SESSION DRIVES IT, and this is the only place that knows. A
  ///   foreground service is what keeps the call poll alive while the phone
  ///   is in a pocket — and a permanent notification saying the association
  ///   is listening, on a handset nobody is signed in on, is a lie the user
  ///   cannot dismiss: Android will not let him swipe away a running
  ///   service's notification.
  ///
  /// ⚠ APPROVED ONLY. A pending applicant and a suspended account are told
  ///   to wait; listening on their behalf would be listening to nothing,
  ///   because every policy refuses them anyway.
  ///
  /// ⚠ ON THE EDGE, so a re-read of api_me every forty-five seconds does not
  ///   restart the service forty-five seconds apart forever.
  bool? _serviceOn;

  void _followSession(AppUser? user) {
    final bool wanted =
        user != null && user.status == AccountStatus.approved;
    if (_serviceOn == wanted) return;
    _serviceOn = wanted;
    unawaited(wanted ? BackgroundService.start() : BackgroundService.stop());

    // ── والجرس معها ────────────────────────────────────────────────────────
    // ⚠ Doorbell.stop() WAS DOCUMENTED AS «STOPPED ON SIGN-OUT» AND CALLED BY
    //   NOBODY. The channel carries the SESSION'S TOKEN and is private — its
    //   policy was evaluated for the man who opened it — so leaving it up
    //   across a sign-out means a socket authenticated as somebody who has
    //   left. Nothing leaks (a ring carries no data), but the file claimed a
    //   guarantee the code did not keep, which this project has already paid
    //   for once: «a comment describing an intention the code does not carry
    //   out is worse than none — the next reader trusts it and hunts the bug
    //   somewhere else».
    //
    // ⚠ AND IT IS NOT STARTED HERE. The bell connects lazily, the first time
    //   something asks to listen — the room, the badge or the call poll — so
    //   starting it on sign-in would open a socket for an account that may
    //   never open a screen that needs one.
    if (!wanted) unawaited(ref.read(doorbellProvider).stop());
  }

  /// Starts an interactive sign-in. A no-op on web, where the flow can only be
  /// started by Google's own rendered button.
  Future<void> signIn() async {
    final googleAuth = ref.read(googleAuthServiceProvider);

    if (!googleAuth.isConfigured) {
      state = const AuthState(
        stage: AuthStage.signedOut,
        errorCode: LocalAuthError.notConfigured,
      );
      return;
    }
    if (!googleAuth.supportsInteractiveSignIn) return;

    state = const AuthState(stage: AuthStage.signingIn);
    try {
      final bool started = await googleAuth.promptSignIn();
      if (!started) {
        // Dismissing the account picker is a normal thing to do, not a fault.
        state = const AuthState(
          stage: AuthStage.signedOut,
          errorCode: LocalAuthError.cancelled,
        );
      }
    } catch (_) {
      state = const AuthState(
        stage: AuthStage.signedOut,
        errorCode: LocalAuthError.googleFailed,
      );
    }
  }

  /// Development-only sign-in. Skips Google but produces the same session, so
  /// approval and role rules still apply exactly as they will in production.
  Future<void> devSignIn(String email) async {
    state = const AuthState(stage: AuthStage.signingIn);
    try {
      final Session session = await ref
          .read(authRepositoryProvider)
          .devSignIn(email);
      state = AuthState(stage: AuthStage.signedIn, user: session.user);
    } on ApiException catch (failure) {
      state = switch (failure.code) {
        'ACCOUNT_PENDING' => AuthState(
          stage: AuthStage.pending,
          pendingEmail: email,
          serverMessage: failure.serverMessage,
        ),
        'ACCOUNT_SUSPENDED' => AuthState(
          stage: AuthStage.suspended,
          serverMessage: failure.serverMessage,
        ),
        _ => AuthState(
          stage: AuthStage.signedOut,
          errorCode: failure.code,
          serverMessage: failure.serverMessage,
          failureKind: failure.kind,
        ),
      };
    }
  }

  Future<void> _exchangeIdToken(String idToken) async {
    state = const AuthState(stage: AuthStage.signingIn);
    try {
      final Session session = await ref
          .read(authRepositoryProvider)
          .signInWithGoogle(idToken);
      state = AuthState(stage: AuthStage.signedIn, user: session.user);
    } on ApiException catch (failure) {
      state = switch (failure.code) {
        'ACCOUNT_PENDING' => AuthState(
          stage: AuthStage.pending,
          pendingEmail: _emailFromDetails(failure.details),
          serverMessage: failure.serverMessage,
        ),
        'ACCOUNT_SUSPENDED' => AuthState(
          stage: AuthStage.suspended,
          serverMessage: failure.serverMessage,
        ),
        _ => AuthState(
          stage: AuthStage.signedOut,
          errorCode: failure.code,
          serverMessage: failure.serverMessage,
          failureKind: failure.kind,
        ),
      };
      // GoTrue's own sentence lives in `details`, because SupabaseFailures
      // deliberately keeps it off the screen — it is English and written for a
      // developer ("Unacceptable audience in id_token", "Database error saving
      // new user"). Off the screen must not mean nowhere: every one of those
      // renders as the same generic Arabic line, so without this the one fact
      // that separates them is destroyed at the moment it arrives.
      _logAuthFailure(failure.code, failure.details ?? failure.serverMessage);
    } catch (error) {
      _logAuthFailure(LocalAuthError.googleFailed, error);
      state = const AuthState(
        stage: AuthStage.signedOut,
        errorCode: LocalAuthError.googleFailed,
      );
    }
  }

  /// Release builds included — the APK the association runs is a release build,
  /// so a kDebugMode gate would silence exactly the occurrence that matters.
  static void _logAuthFailure(String? code, Object? detail) {
    debugPrint('Sign-in failed [${code ?? 'unknown'}]: ${detail ?? '(none)'}');
  }

  static String? _emailFromDetails(Object? details) {
    if (details is Map && details['email'] is String) {
      return details['email'] as String;
    }
    return null;
  }

  Future<void> signOut() async {
    await ref.read(googleAuthServiceProvider).signOut();
    await ref.read(authRepositoryProvider).signOut();
    state = const AuthState(stage: AuthStage.signedOut);
  }

  /// Clears a transient error without changing where the user is.
  void dismissError() {
    if (state.hasError) state = AuthState(stage: state.stage, user: state.user);
  }
}
