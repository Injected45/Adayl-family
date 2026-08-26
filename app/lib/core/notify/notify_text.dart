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

  /// «مجلس العدايل · فلان» — the hall needs its NAME in the title, because a
  /// message there is from one of eight men and the room is the context. A
  /// private line and a board thread are already identified by who wrote them.
  static String Function(String) hallFrom = (String who) => who;

  /// «… ورسالة أخرى» — Android replaces a notification by id, so the newest
  /// line is what he sees; without the count he would open the app expecting
  /// one message and find four.
  static String Function(String, int) andMore = (String body, int more) => body;

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
    hallFrom = l.chatNotifyHallFrom;
    andMore = l.chatNotifyAndMore;
    serviceTitle = l.notifyServiceTitle;
    serviceBody = l.notifyServiceBody;
    serviceChannel = l.notifyServiceChannel;
    callChannel = l.notifyCallChannel;
    callChannelDesc = l.notifyCallChannelDesc;
    chatChannel = l.notifyChatChannel;
    chatChannelDesc = l.notifyChatChannelDesc;
  }
}
