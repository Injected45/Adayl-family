import '../../l10n/app_localizations.dart';

/// الكلمات التي تظهر في الإشعارات وفي إعدادات أندرويد.
///
/// ── لماذا هذا الملف موجود أصلاً ────────────────────────────────────────────
/// Notifications are raised from POLLS — a three-second timer with no widget,
/// no `BuildContext` and therefore no `L`. Android's notification CHANNELS are
/// worse: their names are created once, from a `static` declaration, and they
/// are user-facing — they appear in the phone's own settings.
///
/// ⚠ AND ARABIC LITERALS ARE REFUSED EVERYWHERE IN `lib` EXCEPT THE ARB, for
///   the good reason that text the association reads must live in one place
///   they can edit. `tool/rtl_lint.dart` caught this file trying to do
///   otherwise, and it was right to.
///
/// ⚠ SO THE WORDS TRAVEL, RATHER THAN THE LOOKUP — and they are filled from
///   `main()`, BEFORE the first frame. A widget could fill them too, but the
///   foreground service can start from the auth controller before any widget
///   has built, and a channel created with an empty name keeps it: Android
///   fixes a channel at creation and re-creating it changes nothing.
///
/// ⚠ AND IT INSTANTIATES THE ARABIC CLASS DIRECTLY, which is honest rather
///   than a shortcut: this app FORCES the `ar` locale (see app.dart), so
///   there is no other answer to ask for. The strings are still the ARB's.
abstract final class NotifyText {
  /// The body of a ringing-call notification. Its title is the caller name.
  static String incomingCall = '';

  /// The body of a new-message notification. Its title is the count.
  static String newMessages = '';

  /// The permanent notification Android requires while the service runs.
  static String serviceTitle = '';
  static String serviceBody = '';
  static String serviceChannel = '';

  /// Channel names, as they appear in the phone's own notification settings.
  static String callChannel = '';
  static String callChannelDesc = '';
  static String chatChannel = '';
  static String chatChannelDesc = '';

  /// Call once, from main(), before runApp.
  static void fill(L l) {
    incomingCall = l.callIncomingBody;
    newMessages = l.chatNewMessagesBody;
    serviceTitle = l.notifyServiceTitle;
    serviceBody = l.notifyServiceBody;
    serviceChannel = l.notifyServiceChannel;
    callChannel = l.notifyCallChannel;
    callChannelDesc = l.notifyCallChannelDesc;
    chatChannel = l.notifyChatChannel;
    chatChannelDesc = l.notifyChatChannelDesc;
  }
}
