import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notify_text.dart';

/// ما يُبقي التطبيق حيًّا وهو في الخلفية.
///
/// ── لماذا خدمةٌ أماميّة أصلاً ──────────────────────────────────────────────
/// The call poll and the unread poll are ordinary Dart `Timer`s, and on Android
/// they go on firing after the app is backgrounded — right up until the system
/// kills the PROCESS to reclaim memory, which on a phone with a browser and
/// WhatsApp open is a matter of minutes. A foreground service is the one thing
/// that tells Android «this process is doing something the user asked for»,
/// and it is what turns «يعمل حتى تُغلق الشاشة» into «يعمل».
///
/// ⚠ ANDROID REQUIRES THE PERMANENT NOTIFICATION. It is not a design choice and
///   it cannot be hidden: a foreground service without a visible notification
///   is not a thing the platform offers. So it is written to be useful rather
///   than apologetic — it says the association is listening, which is exactly
///   what it is doing.
///
/// ⚠ AND WHAT IT STILL CANNOT DO. Force-stopping the app from the task
///   switcher kills it, and so do the battery managers Samsung and Xiaomi ship
///   enabled by default. Only a real push service (FCM) survives those, and
///   that needs a Firebase project, a google-services.json in this repository
///   and a server-side key — which is a separate decision for the association,
///   not a line of code.
class BackgroundService {
  BackgroundService._();

  static bool _configured = false;

  static void _configure() {
    if (_configured) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'association_service',
        channelName: NotifyText.serviceChannel,
        channelDescription: NotifyText.serviceBody,
        // ⚠ LOW, so the permanent notification makes no sound and does not
        //   push anything aside. The things worth interrupting for get their
        //   own channels — see Notifier.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // ⚠ THE SERVICE DOES NO WORK OF ITS OWN. It exists to hold the process
        //   open so the polls already running in the main isolate keep running.
        //   Doing the polling here instead would mean a second Supabase client,
        //   a second session, and two places that could disagree about who is
        //   signed in.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _configured = true;
  }

  /// Start listening. Safe to call repeatedly.
  static Future<void> start() async {
    try {
      _configure();
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        notificationTitle: NotifyText.serviceTitle,
        notificationText: NotifyText.serviceBody,
        callback: _entry,
      );
    } on Object catch (e) {
      // A phone that refuses the service still runs the app; it simply stops
      // listening when it is put away. Never a reason to fail a screen.
      debugPrint('background start: $e');
    }
  }

  /// ⚠ STOPPED ON SIGN-OUT, and that is not tidiness. A permanent notification
  ///   saying the association is listening, on a phone nobody is signed in on,
  ///   is a lie the user cannot dismiss.
  static Future<void> stop() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.stopService();
    } on Object catch (e) {
      debugPrint('background stop: $e');
    }
  }
}

/// The isolate entry point. Required by the plugin; deliberately empty.
///
/// See the note on `eventAction` above: the service holds the process, the main
/// isolate does the work.
@pragma('vm:entry-point')
void _entry() {
  FlutterForegroundTask.setTaskHandler(_Idle());
}

class _Idle extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
