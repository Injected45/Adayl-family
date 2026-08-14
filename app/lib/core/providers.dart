import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/google_auth_service.dart';
import 'supabase/supabase_client_provider.dart';

/// Gone from this file, and worth naming so nobody looks for them:
///
///   TokenStore       — GoTrue persists the session, into the platform keystore
///                      via SecureLocalStorage. A second copy of a refresh token
///                      is a second thing to leak.
///   SessionManager   — refresh, expiry and in-flight de-duplication are the
///                      Supabase client's job now.
///   ApiClient        — there is no REST API to call. Reads go to PostgREST views,
///                      writes to RPC.
///
/// `Session` (features/auth/domain/app_user.dart) survives as the return type of
/// a sign-in, because the controller and the router still branch on it.

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => AuthRepository(ref.watch(supabaseClientProvider)),
    );

final Provider<GoogleAuthService> googleAuthServiceProvider =
    Provider<GoogleAuthService>((Ref ref) {
      final GoogleAuthService service = GoogleAuthService();
      ref.onDispose(service.dispose);
      return service;
    });
