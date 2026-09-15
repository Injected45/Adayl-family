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
  static AndroidNotificationDetails
  get _callChannel => AndroidNotificationDetails(
    'calls',
    NotifyText.callChannel,
    channelDescription: NotifyText.callChannelDesc,
    importance: Importance.max,
    priority: Priority.high,
    // ── ⚠ NO fullScreenIntent, AND IT WAS REMOVED RATHER THAN NEVER ADDED ──
    //
    //   `fullScreenIntent: true` sat here, with the comment «a call is the
    //   one thing allowed to take over the screen». Android took that
    //   literally: with USE_FULL_SCREEN_INTENT granted and NO full-screen
    //   Activity of ours to launch, it inflates the notification's own
    //   layout at full size — so the caller's name filled the screen. The
    //   association saw it on the first real three-handset test: «الاسم
    //   يظهر بشكل كبير جدا … ارجعه مثل واتساب».
    //
    // ⚠ AND IT WAS COSTING THE SOUND TOO — the note in providers.dart said
    //   so before this was understood: Android may drop a channel's tone
    //   for a notification carrying a full-screen intent, because it
    //   expects the screen it takes over to do the ringing. Nothing was.
    //
    // ⚠ NOTHING IS LOST, because this notification only ever fires while
    //   the app is RUNNING — `_ring()` is raised by the call poll and the
    //   doorbell, both of which live in the app. There is no push service
    //   here, so a takeover screen was never reaching a closed phone. The
    //   foreground case already has IncomingCallBanner; what is wanted in
    //   the background case is a heads-up banner, which is exactly what
    //   `importance: max` + `priority: high` + `category.call` produce —
    //   and is the shape WhatsApp shows.
    //
    //   `fullScreenIntent` is a NOTIFICATION property, not a channel one,
    //   so removing it takes effect on the next call. Changing importance
    //   or sound would have needed a new channel id.
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

  /// ⚠ A THIRD CHANNEL, NOT THE CHAT'S. A receipt, a voucher or a closed month
  ///   is the association speaking, not a neighbour — and Android lets a man
  ///   silence one channel from his phone's settings. Sharing the chat's would
  ///   make «mute the room» also mute «your payment was recorded».
  ///
  /// ── عشرون ثانية على الشاشة، ثم في تبويب الإشعارات (15/09) ───────────────
  /// «يظهر على شاشة الهاتف الرئيسية ويضل 20 ثانية … واذا اختفي يكون موجود في
  /// تبويب الاشعارات». [noticeVisibleFor] is `timeoutAfter`: Android removes
  /// the notification by itself at twenty seconds, and the notice goes on
  /// living where it always lived — a row in `notifications`, on the tab.
  ///
  /// ⚠ `timeoutAfter` IS A NOTIFICATION PROPERTY, NOT A CHANNEL ONE, so it
  ///   reaches phones that already created this channel on 13/09. Importance
  ///   IS a channel property and was already HIGH — the level at which Android
  ///   pops a notification over the screen — so the id stays and nothing has
  ///   to be re-created.
  ///
  /// ⚠ HOW LONG THE POP-UP ITSELF STAYS DOWN OVER THE SCREEN IS ANDROID'S
  ///   DECISION, NOT AN APP'S — a few seconds, then it folds into the status
  ///   bar and waits there for the rest of the twenty. The only notifications
  ///   that hold the screen longer carry a `fullScreenIntent`, and the call
  ///   channel's note above records what that did on this app. While the app
  ///   is OPEN the twenty seconds are exact, because the app draws its own
  ///   banner then — see `NoticePeekHost`.
  @visibleForTesting
  static AndroidNotificationDetails get noticeDetails =>
      AndroidNotificationDetails(
        'association_notices',
        NotifyText.noticeChannel,
        channelDescription: NotifyText.noticeChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        playSound: true,
        enableVibration: true,
        timeoutAfter: noticeVisibleFor.inMilliseconds,
        // The whole sentence on the lock screen: «صُرف 400.00 د.ل — فطور
        // رمضان («…»). سند رقم EXP-62.» does not fit one line, and a
        // truncated amount is worse than none.
        styleInformation: const BigTextStyleInformation(''),
      );

  /// How long a notice stays on the phone before it is only on the tab.
  static const Duration noticeVisibleFor = Duration(seconds: 20);

  /// Which notice the member tapped on his phone, waiting to be opened.
  ///
  /// ⚠ A VALUE, NOT AN EVENT. A tap can arrive before anything is listening —
  ///   the app launched BY the tap has not built a widget yet — so it is held
  ///   here until `NoticePeekHost` can open it, and cleared by whoever does.
  static final ValueNotifier<int?> tappedNotice = ValueNotifier<int?>(null);

  /// `notice:<id>` — the payload a notice notification carries.
  @visibleForTesting
  static String noticePayload(int id) => 'notice:$id';

  /// The notice id in a payload, or null for anything else (a call, a
  /// message, a payload from an older build that carried none).
  @visibleForTesting
  static int? noticeIdFromPayload(String? payload) {
    const String prefix = 'notice:';
    if (payload == null || !payload.startsWith(prefix)) return null;
    final int? id = int.tryParse(payload.substring(prefix.length));
    return id != null && id > 0 ? id : null;
  }

  /// A screen the admin's phone notification was tapped for, waiting to be
  /// opened — a new proposal opens «مقترحات المشتركين». A value, for the
  /// reason [tappedNotice] is one.
  static final ValueNotifier<String?> tappedRoute = ValueNotifier<String?>(
    null,
  );

  /// `route:<path>` — the payload of an alert that opens a screen.
  @visibleForTesting
  static String routePayload(String route) => 'route:$route';

  @visibleForTesting
  static String? routeFromPayload(String? payload) {
    const String prefix = 'route:/';
    if (payload == null || !payload.startsWith(prefix)) return null;
    return payload.substring('route:'.length);
  }

  static void _onTap(NotificationResponse response) {
    final int? id = noticeIdFromPayload(response.payload);
    if (id != null) tappedNotice.value = id;
    final String? route = routeFromPayload(response.payload);
    if (route != null) tappedRoute.value = route;
  }

  /// Ids. Fixed, so a second call REPLACES the first rather than stacking —
  /// there is only ever one live call, and two ringing notifications would be
  /// two things to dismiss for one event.
  static const int _callId = 1;
  static const int _chatId = 2;
  static const int _noticeId = 3;

  /// ⚠ ITS OWN ID. The admin receives no member notices today, but a proposal
  ///   alert sharing id 3 would silently replace one the day he does.
  static const int _proposalId = 4;

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
        // A tap on a notice while the process is alive — backgrounded, or
        // behind the lock screen.
        onDidReceiveNotificationResponse: _onTap,
      );

      // …and a tap that STARTED the app. Asked once: the answer does not
      // change for the life of the process.
      final NotificationAppLaunchDetails? launch = await _plugin
          .getNotificationAppLaunchDetails();
      final NotificationResponse? launchedBy = launch?.notificationResponse;
      if ((launch?.didNotificationLaunchApp ?? false) && launchedBy != null) {
        _onTap(launchedBy);
      }

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

  /// إشعارٌ من الجمعية — a receipt, a voucher, a month, or the admin's message.
  /// [noticeId] makes the notification open that notice when tapped.
  static Future<void> notice(String title, String body, {int? noticeId}) async {
    await _show(
      _noticeId,
      title,
      body,
      noticeDetails,
      payload: noticeId == null ? null : noticePayload(noticeId),
    );
  }

  static Future<void> clearNotices() async => _cancel(_noticeId);

  /// «مقترح جديد من فلان» — on the same channel, for the same twenty seconds,
  /// opening [route] when tapped.
  static Future<void> proposal(String title, String body, String route) async {
    await _show(
      _proposalId,
      title,
      body,
      noticeDetails,
      payload: routePayload(route),
    );
  }

  static Future<void> clearProposals() async => _cancel(_proposalId);

  static Future<void> _show(
    int id,
    String title,
    String body,
    AndroidNotificationDetails android, {
    String? payload,
  }) async {
    if (!_ready) await init();
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android),
        payload: payload,
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
