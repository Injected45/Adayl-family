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
  }

  final String? fromServer = state.serverMessage;
  if (fromServer != null && fromServer.isNotEmpty) return fromServer;

  return switch (state.failureKind) {
    ApiFailureKind.network => l.errorNetworkBody,
    ApiFailureKind.timeout => l.errorTimeout,
    _ => l.errorGeneric,
  };
}
