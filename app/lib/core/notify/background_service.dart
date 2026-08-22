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

  /// كل كم يوقظ الخادمُ العزلةَ الرئيسيّة.
  ///
  /// ⚠ TEN SECONDS, AND THE NUMBER IS ARITHMETIC RATHER THAN TASTE. A ring
  ///   lives sixty seconds (`v_calls` expires it), so ten gives six chances to
  ///   catch one — a missed call needs six consecutive failures, not one. And a
  ///   message arriving within ten seconds is «بسرعة» by any reading of it.
  ///
  /// ⚠ FASTER WOULD BE PAID FOR IN BATTERY, NOT IN QUOTA. At five seconds a
  ///   phone in a pocket wakes seventeen thousand times a day for an
  ///   association of eight men who are rarely all online. The cost that
  ///   matters here has always been the handset, never the free tier.
  static const Duration heartbeat = Duration(seconds: 10);

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
        // ⚠ IT WAS `nothing()`, AND THAT IS WHY NOTIFICATIONS ARRIVED «مره
        //   بتاخر ومره غير منتظم». The reasoning was that the service only had
        //   to hold the PROCESS open and the polls already running in the main
        //   isolate would keep running. Holding the process is real — but a
        //   backgrounded Flutter engine is paused, and a paused engine does not
        //   dispatch Dart `Timer`s on schedule. They are batched, delayed, and
        //   sometimes not run until the app is opened, which is exactly the
        //   symptom: sometimes on time, sometimes minutes late, never
        //   dependable.
        //
        // ⚠ THE REPEAT EVENT IS NOT A DART TIMER. Look at the plugin's Android
        //   source: it is a Kotlin coroutine `delay()` loop living inside the
        //   foreground Service. A foreground service's own threads are the one
        //   thing Android promises to keep scheduling — that is what the
        //   permanent notification buys.
        //
        // ⚠ AND IT STILL DOES NO SUPABASE WORK, which is the half of the old
        //   reasoning that was right. The handler sends a bare heartbeat to the
        //   main isolate and the main isolate polls with the client and session
        //   it already has. A second client here would mean a second session,
        //   two writers to the same refresh token in the keystore, and a
        //   sign-out nobody could explain.
        eventAction: ForegroundTaskEventAction.repeat(heartbeat.inMilliseconds),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _configured = true;
  }

  /// هل تعمل الخدمة فعلاً؟ يُقرأ بعد [start].
  ///
  /// ⚠ IT EXISTS BECAUSE THE FAILURE WAS SILENT FOR THE WHOLE LIFE OF THIS
  ///   FEATURE. start() catches and debugPrints, which is right — a phone that
  ///   refuses the service must still run the app — but «caught» became
  ///   «unnoticed», and the app spent weeks believing it was listening in the
  ///   background while nothing was. A caught exception with nowhere to be seen
  ///   is a bug that reports itself as «sometimes slow».
  static bool running = false;

  /// Start listening. Safe to call repeatedly.
  static Future<void> start() async {
    try {
      _configure();
      if (await FlutterForegroundTask.isRunningService) {
        running = true;
        return;
      }
      await FlutterForegroundTask.startService(
        notificationTitle: NotifyText.serviceTitle,
        notificationText: NotifyText.serviceBody,
        callback: _entry,
      );
      // ⚠ ASKED AGAIN RATHER THAN ASSUMED. startService can return without
      //   throwing and still leave nothing running — an OEM battery manager
      //   refusing it looks exactly like success from here.
      running = await FlutterForegroundTask.isRunningService;
      if (!running) {
        debugPrint('background: startService returned but nothing is running');
      }
    } on Object catch (e) {
      running = false;
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
      running = false;
    } on Object catch (e) {
      debugPrint('background stop: $e');
    }
  }

  /// The word the service isolate sends. Nothing reads its value; it is here so
  /// the two sides cannot drift apart silently.
  static const String tick = 'tick';

  /// استمِع للنبضة — [onBeat] يُنادى في العزلة الرئيسيّة على كل نبضة.
  ///
  /// ⚠ REGISTERED BY WHOEVER OWNS THE POLLS, not by this file. The heartbeat is
  ///   a clock and nothing more; what it drives is a decision that belongs
  ///   where the providers are — see [AutoRefresh].
  static VoidCallback listen(void Function() onBeat) {
    void handler(Object data) {
      if (data == tick) onBeat();
    }

    FlutterForegroundTask.addTaskDataCallback(handler);
    // ⚠ THE UNREGISTER IS RETURNED RATHER THAN LEFT TO THE CALLER TO REMEMBER.
    //   A callback that outlives the widget that made it holds a dead `ref`,
    //   and reading a ref after dispose throws — which is how a previous bug in
    //   this app aborted `dispose` and leaked every timer below it.
    return () => FlutterForegroundTask.removeTaskDataCallback(handler);
  }
}

/// The isolate entry point. Required by the plugin.
@pragma('vm:entry-point')
void _entry() {
  FlutterForegroundTask.setTaskHandler(_Heartbeat());
}

/// ينبض، ولا يعرف شيئاً عن الجمعية.
///
/// ⚠ IT RUNS IN A SEPARATE ISOLATE, and that is why it does nothing but send a
///   word. It has no Supabase client, no session, no localisations and no
///   access to anything the app has loaded — a separate isolate shares no
///   memory at all. Everything it might reach for would have to be built again
///   here, and a second Supabase client is the one thing that must never exist:
///   both would refresh the same token into the same keystore entry, and the
///   loser of that race is signed out with nothing to explain it.
class _Heartbeat extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    // The payload is deliberately meaningless. What carries information is
    // that it arrived — the main isolate knows what to ask and whom to ask.
    FlutterForegroundTask.sendDataToMain(BackgroundService.tick);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
