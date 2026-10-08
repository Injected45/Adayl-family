/// مفتاحُ الدخول كرمز QR — ما يحمله المربّع، ومتى يُقبل.
///
/// ── WHY THIS IS A TRANSPORT AND NOTHING ELSE ────────────────────────────────
/// The QR carries the SAME access code `issue_adeel_code` already returns, and
/// `redeem_adeel_code` is unchanged. Nothing about who may bind a handset moves
/// into the client: the database still decides, still expires the key after
/// seven days, still counts five attempts an hour, and still binds the device
/// and the login that redeemed it. What this removes is DICTATION — a code read
/// out over a Libyan phone line, mistyped twice, and the man locked out for an
/// hour on the day he was being set up.
///
/// ⚠ SO IT IS EXACTLY AS SECRET AS THE SPOKEN CODE, no more and no less. A
///   stranger who photographs the admin's screen holds what a stranger
///   overhearing the call holds. The protections are the ones already in the
///   database, and this file adds none and removes none.
///
/// ⚠ READING THE SQUARE IS `mobile_scanner`'S JOB, not this file's. An earlier
///   build decoded a PHOTOGRAPH here, with `zxing2`, to avoid declaring a
///   camera permission — and the association's first test killed it: «تفتح
///   كاميرا عاديه ولا تلتقط الـQR». Taking a picture of a code and confirming
///   it is not what anyone means by «امسح», so the decoder, its packages and
///   its tests are gone rather than left inert. See `key_scanner_screen.dart`.
library;

/// ⚠ THE PREFIX IS THE WHOLE POINT. Without it any QR code in the world — a
///   receipt, a wifi card, a poster — would be read as an access code and fed
///   to `redeem_adeel_code`, spending one of the five attempts an hour the
///   member is allowed and answering «المفتاح غير صحيح» about something that
///   was never a key.
const String _prefix = 'adayl-key:';

/// What the admin's screen draws.
String keyQrPayload(String code) => '$_prefix${code.trim()}';

/// The key inside a scanned payload, or null when the QR is not one of ours.
String? keyFromQrPayload(String raw) {
  final String text = raw.trim();
  if (!text.startsWith(_prefix)) return null;
  final String code = text.substring(_prefix.length).trim();
  return code.isEmpty ? null : code;
}
