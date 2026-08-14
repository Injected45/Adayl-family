/// Platform-appropriate Google sign-in button.
///
/// On web the sign-in MUST be started by Google's own rendered button, so the
/// two implementations are genuinely different widgets rather than a styling
/// choice.
library;

export 'google_sign_in_button_io.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart';
