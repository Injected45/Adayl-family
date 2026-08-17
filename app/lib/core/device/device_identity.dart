import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Which handset is asking.
///
/// ── Why this is not a MAC address
///
/// The association asked for the access code to be tied to a phone's MAC
/// address. No app can read one any more: Android has returned the constant
/// `02:00:00:00:00:00` to every caller since API 23, randomises the real one per
/// network since Android 10, and iOS never exposed it. A MAC-based lock cannot
/// be built by anybody, on any platform, today.
///
/// What the platform still gives out is a per-install/per-device identifier,
/// and that is what this returns:
///
///   Android → `ANDROID_ID`. Unique per device+app-signing-key, survives app
///             updates AND reinstalls, changes only on a factory reset. The
///             closest thing left to what was asked for.
///   iOS     → `identifierForVendor`. Stable while any app from this vendor is
///             installed.
///   other   → a random UUID minted once and kept in the keystore, which is the
///             best available and is at least stable for that install.
///
/// ── Why it is hashed
///
/// The raw value never leaves the phone. `profiles.device_id` holds a SHA-256
/// of it, so the association's database stores an opaque token rather than a
/// device fingerprint it has no use for and no business keeping. Comparison is
/// all the server ever does with it, and a hash compares exactly as well.
///
/// ── What this is and is not
///
/// It travels as the `x-device-id` header on every request, and `my_adeel_id()`
/// refuses to answer when it does not match. That stops an عديل opening his
/// account on a second handset, or handing his Google password to someone — the
/// thing the association actually asked to prevent. It is NOT proof against
/// someone who sets the header himself with the public anon key; nothing sent
/// by a client ever could be. The code remains the authorisation.
abstract final class DeviceIdentity {
  static const FlutterSecureStorage _keystore = FlutterSecureStorage(
    // Same accessibility as the session store beside it: survives a device
    // migration, because losing it silently locks a member out.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Where the fallback UUID lives. Namespaced like the session keys beside it.
  static const String _fallbackKey = 'adayl.device.id';

  static String? _cached;

  /// The value to send, resolved once per launch.
  ///
  /// Never throws and never returns empty: a platform channel that fails — a
  /// stripped-down ROM, an emulator with no Settings provider — falls through
  /// to the keystore UUID rather than leaving the header off, because a missing
  /// header reads to the server as "unknown device" and would lock the member
  /// out of his own account for a reason he cannot act on.
  static Future<String> resolve() async {
    final String? cached = _cached;
    if (cached != null) return cached;

    String? raw;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        raw = (await DeviceInfoPlugin().androidInfo).id;
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        raw = (await DeviceInfoPlugin().iosInfo).identifierForVendor;
      }
    } on Object {
      // Deliberately swallowed — the fallback below is the whole contingency.
      raw = null;
    }

    raw = (raw == null || raw.trim().isEmpty) ? await _fallbackId() : raw.trim();

    final String hashed = sha256.convert(utf8.encode(raw)).toString();
    _cached = hashed;
    return hashed;
  }

  /// A UUID minted on first launch and kept in the platform keystore.
  ///
  /// Weaker than ANDROID_ID — a reinstall loses it and the member has to be
  /// released by an admin — but it is only reached on web and on devices whose
  /// platform id is unreadable, and a lock that sometimes needs an admin beats
  /// no lock at all.
  static Future<String> _fallbackId() async {
    try {
      final String? stored = await _keystore.read(key: _fallbackKey);
      if (stored != null && stored.isNotEmpty) return stored;
      final String minted = _randomId();
      await _keystore.write(key: _fallbackKey, value: minted);
      return minted;
    } on Object {
      // No keystore either. A per-launch value is useless as a lock, so say so
      // in the value itself rather than pretending: the server will refuse it
      // on the next launch and the member will be told to see the association,
      // which is the honest outcome.
      return 'volatile-${_randomId()}';
    }
  }

  static String _randomId() {
    // Random.secure() rather than Random(): this is the value that decides
    // whether two installs look like the same device.
    final List<int> bytes = List<int>.generate(
      16,
      (_) => _rng.nextInt(256),
    );
    return base64Url.encode(bytes);
  }

  static final Random _rng = Random.secure();
}
