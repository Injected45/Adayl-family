import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notify_text.dart';

/// إشعارات النظام — ما يجعل الرنين يصل والتطبيق في الخلفية.
///
/// ── لماذا هذا وليس Firebase ────────────────────────────────────────────────
/// A real push notification (FCM) is the only thing that wakes an app the OS
/// has KILLED. It also needs a Firebase project, a `google-services.json` the
/// association must download and place in this repository, and something
/// server-side holding a service-account key to send with — none of which this
/// project has, and the last of which it deliberately never will.
///
/// ⚠ WHAT THE ASSOCIATION ACTUALLY ASKED FOR IS NARROWER AND IS BUILDABLE:
///   «اريد التطبيق يشتغل في الخلفية بحيث لما حد يرن يصل الرنين وينتبه». The app
///   RUNNING IN THE BACKGROUND is a foreground service plus a local
///   notification, and neither needs an account, a key or a server.
///
/// ⚠ AND THE LIMIT IS REAL AND MUST BE SAID: this survives the app being
///   backgrounded, the screen being off, and the phone idling. It does NOT
///   survive the user force-stopping the app from the task switcher, nor an
///   aggressive OEM battery manager killing it — Samsung and Xiaomi both do
///   this by default. Only a push service survives those.
/// ⚠ NOT `Notifier` — Riverpod exports a class by that name, and a file that
///   imports both gets an ambiguous_import that names neither cause.
class AppNotifier {
  AppNotifier._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// ⚠ TWO CHANNELS, NOT ONE, and Android will not let this be changed later:
  ///   a channel's importance and sound are fixed at creation, and re-creating
  ///   it with the same id does nothing. A call must be able to interrupt; a
  ///   message must not. One channel would force the same answer on both.
  static AndroidNotificationDetails get _callChannel =>
      AndroidNotificationDetails(
        'calls',
        NotifyText.callChannel,
        channelDescription: NotifyText.callChannelDesc,
        importance: Importance.max,
        priority: Priority.high,
        // A call is the one thing in this app allowed to take over the screen.
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        // ⚠ ONGOING, so a swipe does not dismiss a ringing call. It is
        //   cancelled when the call is answered, declined or expires — see
        //   [clearCall] — and `v_calls` expires a ring after sixty seconds, so
        //   it cannot become a notification nobody can remove.
        ongoing: true,
        autoCancel: false,
        playSound: true,
        enableVibration: true,
      );

  static AndroidNotificationDetails get _chatChannel =>
      AndroidNotificationDetails(
        'chat',
        NotifyText.chatChannel,
        channelDescription: NotifyText.chatChannelDesc,
        importance: Importance.high,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.message,
        playSound: true,
      );

  /// Ids. Fixed, so a second call REPLACES the first rather than stacking —
  /// there is only ever one live call, and two ringing notifications would be
  /// two things to dismiss for one event.
  static const int _callId = 1;
  static const int _chatId = 2;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // @mipmap/ic_launcher: the app icon. A missing icon is not a
          // degraded notification on Android — the notification does not
          // appear at all, silently.
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      // ⚠ ANDROID 13+ REFUSES EVERY NOTIFICATION until this is granted, and
      //   refuses silently. Asked here rather than at launch: the first thing
      //   worth notifying about is a call, and by then the man has already
      //   chosen to use a feature that needs it.
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();

      _ready = true;
    } on Object catch (e) {
      // A phone that will not give notifications still runs the app. Every
      // caller treats this as best-effort.
      debugPrint('notifier init: $e');
    }
  }

  /// «فلان يتصل» — while the app is not in front of him.
  static Future<void> ringing(String caller, String body) async {
    await _show(_callId, caller, body, _callChannel);
  }

  static Future<void> clearCall() async => _cancel(_callId);

  /// A new message, when he is not looking at the room.
  static Future<void> message(String title, String body) async {
    await _show(_chatId, title, body, _chatChannel);
  }

  static Future<void> clearMessages() async => _cancel(_chatId);

  static Future<void> _show(
    int id,
    String title,
    String body,
    AndroidNotificationDetails android,
  ) async {
    if (!_ready) await init();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android),
      );
    } on Object catch (e) {
      debugPrint('notify: $e');
    }
  }

  static Future<void> _cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object catch (e) {
      debugPrint('notify cancel: $e');
    }
  }
}
