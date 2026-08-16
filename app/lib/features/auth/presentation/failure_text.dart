import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import 'auth_controller.dart';

/// Resolves an auth failure to text the user can act on.
///
/// The server already sends a display-ready Arabic message with every error, so
/// that is preferred verbatim. Only failures that never reached the server —
/// or that the client generated itself — need a locally localised string.
String describeAuthFailure(L l, AuthState state) {
  switch (state.errorCode) {
    // Matches both the local code and the server's, which share this value on
    // purpose so the two paths present identically.
    case LocalAuthError.notConfigured:
      return l.googleNotConfigured;
    case LocalAuthError.cancelled:
      return l.signInCancelled;
    case LocalAuthError.googleFailed:
      return l.errorGeneric;
    // Raised by AuthRepository.me() when a valid JWT finds no profiles row.
    // That is a real, nameable state — the schema is there and the row is not,
    // which is what re-applying the bundle or skipping bootstrap_first_admin
    // leaves behind — and it used to render as "unexpected error", the one
    // sentence that rules nothing out and invites a pointless retry.
    case 'PROFILE_MISSING':
      return l.errorProfileMissing;
  }

  final String? fromServer = state.serverMessage;
  if (fromServer != null && fromServer.isNotEmpty) return fromServer;

  return switch (state.failureKind) {
    ApiFailureKind.network => l.errorNetworkBody,
    ApiFailureKind.timeout => l.errorTimeout,
    // Same reasoning as PROFILE_MISSING: retrying cannot help, so say so
    // instead of offering the generic sentence that reads like bad luck.
    ApiFailureKind.schemaMismatch => l.errorSchemaMismatch,
    _ => l.errorGeneric,
  };
}
