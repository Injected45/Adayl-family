import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
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
      state = const AuthState(stage: AuthStage.signedOut);
      return;
    }
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
    } catch (_) {
      state = const AuthState(
        stage: AuthStage.signedOut,
        errorCode: LocalAuthError.googleFailed,
      );
    }
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
