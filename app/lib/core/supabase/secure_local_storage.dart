import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Session storage for GoTrue, backed by the platform keystore.
///
/// `supabase_flutter` defaults to `SharedPreferences`, which on Android is a
/// world-readable-to-root XML file and on iOS is an unencrypted plist. The stored
/// value is a refresh token — a long-lived credential that mints access tokens on
/// demand — so the default would be a downgrade from the previous architecture,
/// where the refresh token lived in Keystore/Keychain via `flutter_secure_storage`
/// and only the short-lived access token was ever held in memory.
///
/// This keeps that property. It is the one piece of the auth migration that is not
/// simply "GoTrue does it now".
///
/// On web there is no keystore and `flutter_secure_storage` falls back to
/// localStorage, which is what `supabase_flutter` would have used anyway. Nothing
/// is gained there and nothing is lost; the class is still used so there is one
/// code path rather than a per-platform branch that only one platform exercises.
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // No `encryptedSharedPreferences: true` — flutter_secure_storage 11
            // dropped the flag because encryption is the default on Android now.
            //
            // first_unlock, not first_unlock_this_device: the session should
            // survive a device migration, and it is a refresh token that GoTrue
            // can revoke server-side, not a secret worth pinning to hardware.
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  final FlutterSecureStorage _storage;

  /// The key `supabase_flutter` itself uses, kept identical so an existing session
  /// is not orphaned by this class being introduced.
  static const String _key = 'supabase.auth.token';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: _key);
    } on Object catch (error, stack) {
      // A keystore read can fail for reasons that are not the app's fault: a
      // restored backup carries ciphertext the new device's key cannot open, and
      // some Android OEMs invalidate the key on a fingerprint change. Treating
      // that as "no session" sends the user to the sign-in screen, which is
      // recoverable. Rethrowing would brick the app at startup with no way out.
      debugPrint('SecureLocalStorage.accessToken failed: $error\n$stack');
      return null;
    }
  }

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: _key, value: persistSessionString);
    } on Object catch (error) {
      // Losing persistence is not losing the session: the in-memory one keeps
      // working until the app is killed. Failing the sign-in over it would be
      // worse than the user having to sign in again next launch.
      debugPrint('SecureLocalStorage.persistSession failed: $error');
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: _key);
    } on Object catch (error) {
      debugPrint('SecureLocalStorage.removePersistedSession failed: $error');
    }
  }
}
