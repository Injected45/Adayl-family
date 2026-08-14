import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/network/api_exception.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/supabase/supabase_failures.dart';
import '../domain/app_user.dart';

/// Authentication, on Supabase Auth (GoTrue).
///
/// ── What GoTrue took over
///
/// Token rotation, reuse detection, expiry, and refresh-on-401 are all gone from
/// this codebase. `supabase_flutter` refreshes in the background and re-attaches
/// the bearer to every PostgREST call, which is why `ApiClient`'s two interceptors
/// and `SessionManager`'s in-flight-refresh de-duplication no longer exist.
///
/// ── What GoTrue does NOT do
///
/// Roles and approval. GoTrue authenticates; it has no opinion about whether this
/// association has let the person in. That lives in `public.profiles`, is read
/// through `api_me()`, and is enforced by RLS on every table — so a signed-in but
/// unapproved user holds a perfectly valid JWT and can still see nothing.
///
/// ── What was LOST
///
/// The old schema stored refresh tokens with a `replaced_by` chain, which is how a
/// stolen token was told apart from an ordinary rotation and how a logout was told
/// apart from a theft. GoTrue rotates and detects reuse, but does not expose that
/// chain, so the association keeps theft DETECTION and loses theft INVESTIGATION.
/// Recorded as residual risk R4 in docs/SUPABASE_MIGRATION_PLAN.md.
class AuthRepository {
  AuthRepository(this._db);

  final sb.SupabaseClient _db;

  sb.GoTrueClient get _auth => _db.auth;

  /// Exchanges a Google ID token for a Supabase session.
  ///
  /// The ID token still comes from `google_sign_in` on the device, so the existing
  /// GoogleAuthService and its token stream are unchanged — only the exchange
  /// moved. Supabase verifies the token against Google itself, which is why no
  /// client secret and no `serverClientId` needs to reach the app any more.
  ///
  /// Throws [ApiException] with `ACCOUNT_PENDING` when the account exists but no
  /// administrator has approved it, and `ACCOUNT_SUSPENDED` when it is blocked.
  /// Both are ordinary outcomes, not faults — the sign-in itself SUCCEEDED, and
  /// the router sends the user to a screen that says so.
  Future<Session> signInWithGoogle(String idToken) =>
      SupabaseFailures.guard(() async {
        final sb.AuthResponse response = await _auth.signInWithIdToken(
          provider: sb.OAuthProvider.google,
          idToken: idToken,
        );
        return _adopt(response.session);
      });

  /// Development sign-in, bypassing Google.
  ///
  /// Unlike the server-side bypass this replaces, it carries NO special privilege:
  /// it is an ordinary email/password sign-in, so the account has to exist and its
  /// role still comes from `public.profiles`. There is no route to leave enabled
  /// by accident in production — the worst case is a button that fails to
  /// authenticate.
  Future<Session> devSignIn(String email) => SupabaseFailures.guard(() async {
    if (SupabaseConfig.devLoginPassword.isEmpty) {
      throw const ApiException(
        kind: ApiFailureKind.server,
        code: 'DEV_LOGIN_NOT_CONFIGURED',
        statusCode: 400,
        details:
            'Rebuild with --dart-define=DEV_LOGIN_PASSWORD=... to use dev '
            'sign-in. The account must already exist in Supabase Auth.',
      );
    }
    final sb.AuthResponse response = await _auth.signInWithPassword(
      email: email,
      password: SupabaseConfig.devLoginPassword,
    );
    return _adopt(response.session);
  });

  /// Binds this signed-in account to the family whose access code it is.
  ///
  /// The one write a signed-in stranger may call. Everything it grants is
  /// read-only sight of a single family, and everything it can be given is a
  /// code the admin generated — so the authorisation is the code itself, which
  /// is why `redeem_family_code` carries no require_role() gate. It refuses
  /// anyone who is already staff, and refuses a code already redeemed by
  /// somebody else.
  Future<void> redeemFamilyCode(String code) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'redeem_family_code',
      params: <String, dynamic>{'p_code': code},
    );
  });

  /// The signed-in user's profile: role and approval state.
  Future<AppUser> me() => SupabaseFailures.guard(() async {
    final dynamic payload = await _db.rpc<dynamic>('api_me');
    if (payload == null) {
      // A valid JWT with no profile row. The trigger on auth.users creates one,
      // so this means the trigger is missing from the project rather than that
      // the user is new — worth being explicit about, because the app would
      // otherwise loop on the sign-in screen with no explanation.
      throw const ApiException(
        kind: ApiFailureKind.server,
        code: 'PROFILE_MISSING',
        statusCode: 500,
        details:
            'Signed in, but public.profiles has no row for this user. Check '
            'trg_auth_user_created exists in the Supabase project.',
      );
    }
    return AppUser.fromJson((payload as Map).cast<String, dynamic>());
  });

  /// Restores a session persisted from a previous launch.
  ///
  /// `supabase_flutter` reads it out of SecureLocalStorage during initialize(),
  /// so by the time this runs the answer is already known and no network call is
  /// needed unless the access token has expired — which the client handles.
  Future<AppUser?> restore() async {
    if (_auth.currentSession == null) return null;
    try {
      final AppUser user = await me();
      // Best effort: a failed last_login_at write must not block a sign-in.
      try {
        await _db.rpc<dynamic>('api_touch_login');
      } on Object {
        // Ignored deliberately.
      }
      return user;
    } on ApiException catch (failure) {
      // An expired or revoked session that could not be refreshed. Clearing it
      // locally sends the user to sign-in, which is recoverable; leaving it in
      // place would retry the same dead token on every launch.
      if (failure.isUnauthorized) {
        await _auth.signOut();
        return null;
      }
      rethrow;
    }
  }

  /// Signing out must always succeed locally, even with no network — otherwise a
  /// user on a bad connection cannot leave a shared device. GoTrue's
  /// SignOutScope.local clears the stored session without needing the server.
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on Object {
      await _auth.signOut(scope: sb.SignOutScope.local);
    }
  }

  /// Fires on every sign-in, sign-out and background token refresh. The
  /// controller listens so a session revoked on another device does not leave
  /// this one showing a dashboard it can no longer load.
  Stream<sb.AuthState> get authStateChanges => _auth.onAuthStateChange;

  Future<Session> _adopt(sb.Session? session) async {
    if (session == null) {
      // Only reachable when email confirmation is switched on for the provider,
      // which this app does not use.
      throw const ApiException(
        kind: ApiFailureKind.server,
        code: 'NO_SESSION',
        statusCode: 401,
      );
    }
    final AppUser user = await me();
    try {
      await _db.rpc<dynamic>('api_touch_login');
    } on Object {
      // Ignored deliberately; see restore().
    }
    return Session(
      accessToken: session.accessToken,
      // GoTrue can issue a session without a refresh token in flows this app
      // does not use; the empty string keeps the model non-nullable rather than
      // pushing a null through every caller.
      refreshToken: session.refreshToken ?? '',
      user: user,
    );
  }
}
