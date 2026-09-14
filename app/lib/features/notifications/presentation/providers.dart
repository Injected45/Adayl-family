import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/notify/notifier.dart';
import '../../../core/notify/notify_text.dart';
import '../../../core/realtime/doorbell.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/notice_read_state.dart';
import '../data/notifications_repository.dart';
import '../domain/models.dart';

final Provider<NotificationsRepository> notificationsRepositoryProvider =
    Provider<NotificationsRepository>(
      (Ref ref) => NotificationsRepository(ref.watch(supabaseClientProvider)),
    );

final Provider<NoticeReadState> noticeReadStateProvider =
    Provider<NoticeReadState>(
      (Ref ref) => const NoticeReadState(FlutterSecureStorage()),
    );

/// The list on the screen. Listed in `refreshAll`, and ALSO re-read whenever
/// the badge's count moves — so a notice that arrives while the screen is open
/// appears on it without a pull.
final FutureProvider<List<AppNotice>> noticesProvider =
    FutureProvider<List<AppNotice>>((Ref ref) {
      ref.watch(
        noticesUnreadProvider.select((AsyncValue<int> v) => v.valueOrNull),
      );
      return ref.watch(notificationsRepositoryProvider).list();
    });

/// Whether الإشعارات is the screen in front of him — the chat's rule: a notice
/// arriving while he is looking at the list rings nothing and posts nothing.
final StateProvider<bool> noticesScreenOpenProvider = StateProvider<bool>(
  (Ref ref) => false,
);

/// What the badge does with one reading. Lifted out of the notifier so the
/// four branches can be asserted without a timer, a client or a phone.
enum NoticeAlert {
  /// The first reading after (re)building: it counts what was waiting, and
  /// announcing that would greet every launch with yesterday's notices.
  arm,

  /// He is looking at the list, or nothing is waiting — take the phone's
  /// notification down.
  clear,

  /// More are waiting than were last announced — post one.
  announce,

  /// Same count as before, or fewer: nothing to say.
  none,
}

NoticeAlert decideNoticeAlert({
  required bool armed,
  required int announced,
  required int count,
  required bool onScreen,
}) {
  if (!armed) return NoticeAlert.arm;
  if (onScreen || count == 0) return NoticeAlert.clear;
  if (count > announced) return NoticeAlert.announce;
  return NoticeAlert.none;
}

class _OnResume with WidgetsBindingObserver {
  _OnResume(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// How many notices are waiting for THIS member — the red badge on his bar,
/// and the phone notification when it rises.
///
/// ── WHO GETS A BADGE ────────────────────────────────────────────────────────
/// An عديل only. The admin is where every one of these notices comes FROM —
/// he recorded the receipt, closed the month, wrote the message — so a badge
/// telling him about it is noise. He still has the screen, with everything
/// that was sent and to whom.
///
/// ⚠ NOT AUTO-DISPOSED, AND THAT IS THE POINT. The badge sits on the portal,
///   and the portal leaves the tree the moment he opens المحادثات (a `go`,
///   not a push). An auto-disposed poll would die with it, and a receipt
///   recorded while he was chatting would announce itself only when he came
///   back. This one lives for the session; the background heartbeat reaches it
///   in a pocket, and the doorbell reaches it at once.
///
/// ⚠ AND IT WATCHES ONLY WHO HE IS, NOT THE WHOLE SESSION. `refreshProfile()`
///   runs every forty-five seconds and emits a new AuthState each time; a
///   rebuild re-arms silently, so watching the whole state would swallow any
///   notice that landed in the second before each re-read.
class NoticesUnread extends AsyncNotifier<int> {
  /// ⚠ FIVE SECONDS IN FRONT, and the doorbell under it. A notice is about a
  ///   receipt or a voucher, not a conversation — nobody is waiting on it to the
  ///   second — and the ring already delivers it at once when the socket is up.
  static const Duration interval = Duration(seconds: 5);

  Timer? _timer;
  int _generation = 0;
  String? _userId;
  int _seen = 0;
  int _announced = 0;
  bool _armed = false;
  bool _busy = false;

  @override
  Future<int> build() async {
    _stop();
    final int generation = ++_generation;
    _armed = false;
    _announced = 0;

    final ({String? id, AccountStatus? status, bool portal}) who = ref.watch(
      authControllerProvider.select(
        (AuthState s) => (
          id: s.user?.id,
          status: s.user?.status,
          portal: s.user?.isAdeelPortal ?? false,
        ),
      ),
    );
    _userId = who.id;
    if (who.id == null || who.status != AccountStatus.approved || !who.portal) {
      return 0;
    }

    final _OnResume resume = _OnResume(() => _tick(generation));
    WidgetsBinding.instance.addObserver(resume);
    final VoidCallback deafen = ref.read(doorbellProvider).listen((Ring r) {
      if (r == Ring.notify) unawaited(_tick(generation));
    });
    ref.onDispose(() {
      _stop();
      WidgetsBinding.instance.removeObserver(resume);
      deafen();
    });
    _timer = Timer.periodic(interval, (_) => _tick(generation));

    _seen = await ref.read(noticeReadStateProvider).lastSeen(who.id!);
    final int first = await ref
        .read(notificationsRepositoryProvider)
        .unreadSince(_seen);
    if (generation == _generation) {
      _armed = true;
      _announced = first;
    }
    return first;
  }

  /// ⚠ CANCELS AND NULLS. Riverpod re-runs build() on the SAME notifier; a
  ///   field still holding the dead timer is how the chat's poll once died
  ///   while its screen stayed open.
  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(int generation) async {
    final String? uid = _userId;
    if (uid == null || _busy || generation != _generation) return;
    _busy = true;
    try {
      _seen = await ref.read(noticeReadStateProvider).lastSeen(uid);
      final int n = await ref
          .read(notificationsRepositoryProvider)
          .unreadSince(_seen);
      if (generation != _generation) return;

      final bool onScreen = ref.read(noticesScreenOpenProvider);
      switch (decideNoticeAlert(
        armed: _armed,
        announced: _announced,
        count: n,
        onScreen: onScreen,
      )) {
        case NoticeAlert.arm:
          _armed = true;
        case NoticeAlert.clear:
          unawaited(AppNotifier.clearNotices());
        case NoticeAlert.announce:
          unawaited(_announce(n, generation));
        case NoticeAlert.none:
          break;
      }
      _announced = n;
      state = AsyncValue<int>.data(n);
    } on Object {
      // A failed poll leaves the previous count standing — a badge that
      // flickers to zero on one dropped request cannot be trusted at a glance.
    } finally {
      _busy = false;
    }
  }

  /// The newest notice's own words on the lock screen — the title the server
  /// wrote, and its sentence. «و ٣ إشعارات أخرى» when more are waiting, since
  /// Android replaces by id and shows only the newest.
  Future<void> _announce(int n, int generation) async {
    String title = NotifyText.noticeFallbackTitle;
    String body = NotifyText.noticeFallbackBody;
    try {
      final AppNotice? newest = await ref
          .read(notificationsRepositoryProvider)
          .newestSince(_seen);
      if (newest != null) {
        title = newest.title;
        body = n > 1
            ? NotifyText.noticeAndMore(newest.body, n - 1)
            : newest.body;
      }
    } on Object {
      // Keep the generic alert: a vague notification is recoverable, a
      // missing one is not.
    }
    if (generation != _generation) return;
    unawaited(AppNotifier.notice(title, body));
  }

  /// اسأل الآن — from the background heartbeat and after a send.
  ///
  /// ⚠ NOT an invalidate: a rebuild re-arms silently, so a background reading
  ///   driven that way would never announce anything.
  Future<void> refresh() => _tick(_generation);

  /// Everything up to [newestId] has been seen on this phone.
  Future<void> markSeen(int newestId) async {
    final String? uid = _userId;
    if (uid == null || newestId <= 0) return;
    try {
      await ref.read(noticeReadStateProvider).markSeen(uid, newestId);
      _seen = newestId > _seen ? newestId : _seen;
      _announced = 0;
      state = const AsyncValue<int>.data(0);
      unawaited(AppNotifier.clearNotices());
    } on Object {
      // The next tick corrects the badge.
    }
  }
}

final AsyncNotifierProvider<NoticesUnread, int> noticesUnreadProvider =
    AsyncNotifierProvider<NoticesUnread, int>(NoticesUnread.new);
