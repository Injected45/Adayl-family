import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/notify/notifier.dart';
import '../../../core/notify/notify_text.dart';
import '../../../core/realtime/doorbell.dart';
import '../../../core/router/destinations.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/chat_chime.dart';
import '../data/chat_read_state.dart';
import '../data/chat_repository.dart';
import 'providers.dart';

final Provider<ChatReadState> chatReadStateProvider = Provider<ChatReadState>(
  (Ref ref) => const ChatReadState(FlutterSecureStorage()),
);

/// The player, alive for as long as the app is.
///
/// A provider rather than a global so a test can hand in a silent one —
/// and so it is disposed with the container instead of outliving it.
final Provider<ChatChime> chatChimeProvider = Provider<ChatChime>((Ref ref) {
  final ChatChime chime = ChatChime();
  ref.onDispose(chime.dispose);
  return chime;
});

/// Whether المحادثات is the screen in front of him at this moment.
///
/// ⚠ WHATSAPP'S RULE, AND THE ASSOCIATION ASKED FOR IT IN THOSE WORDS:
///   «صوت الجرس لما يكون غير فاتح الرسائل، اما اذا فاتح الرسائل فتصل
///   الرسائل بدون جرس». A sound that fires while you are watching the
///   message land tells you nothing you did not just see, and on a burst of
///   replies it becomes noise you want to mute — which is how a chime ends
///   up switched off for the one case it was built for.
///
/// ⚠ AN EXPLICIT FLAG, NOT «is the count zero». A message arriving while the
///   room is open DOES raise the count for the instant before the screen
///   marks it read, and inferring silence from the number would ring in
///   exactly that window — the one this rule exists to keep quiet.
final StateProvider<bool> chatScreenOpenProvider = StateProvider<bool>(
  (Ref ref) => false,
);

/// How many messages are waiting, refreshed on its own slow clock.
///
/// ── WHY A SECOND POLL, AND WHY A SLOWER ONE ─────────────────────────────────
/// The room polls every four seconds, and only while the room is on screen. The
/// bell has to ring on every OTHER screen, which is where a member spends almost
/// all of his time — so it needs its own timer, and it must be far cheaper: one
/// column, capped, no message bodies.
///
/// ⚠ TEN SECONDS, AND THE THIRTY IT REPLACED WAS WRONG.
///
///   The argument for thirty was that nobody watches a bell waiting for it to
///   change. People do — it is the first thing anyone does with a new one, and
///   the association reported exactly that: the count only moved after leaving
///   the screen and coming back. Leaving REBUILDS the provider, which fetches
///   at once — so the app looked broken in the one comparison a user can
///   actually make, and the reasoning had been about cost rather than about
///   what somebody holding the phone would see.
///
///   Ten is still slower than the room itself, which polls at four while it is
///   open, and this asks for one capped column with no message bodies.
///
/// ⚠ IT IS NOT A NOTIFICATION. Nothing rings while the app is closed — that
///   needs a push service, a server key and a Firebase project, none of which
///   exist here. This is «هل هناك جديد» answered while the app is open, which is
///   the honest thing to promise with what the app has.
/// Fires when the app returns to the foreground.
///
/// A separate object rather than a mixin on the notifier: a Riverpod notifier
/// is built and disposed on its own schedule, and an observer that outlived one
/// would go on ticking against a dead state.
class _OnResume with WidgetsBindingObserver {
  _OnResume(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// The notification TITLE: how many are waiting.
///
/// ⚠ A BARE NUMERAL, on purpose. There is no BuildContext in a poll, so no
///   L — and inventing an Arabic sentence here would put user-facing text
///   outside the ARB, which is exactly what NotifyText exists to avoid. The
///   BODY carries the words; the title carries the count.
String l10nTitle(int n) => n.toString();

class ChatUnread extends AutoDisposeAsyncNotifier<int> {
  /// How often the bell asks.
  ///
  /// ⚠ FOUR SECONDS, AND IT IS NOW FOUR ANSWERS RATHER THAN ONE. The
  ///   thread counts, the per-room counts and — since the association
  ///   reported messages arriving only after leaving and re-entering — the
  ///   INBOX LIST itself all ride this tick. Ten seconds was a judgement
  ///   about a badge; it is the wrong one for «هل وصلتني رسالة», which is
  ///   what the same tick now answers.
  ///
  ///   The request is one capped column with no message bodies, which is
  ///   what makes a four-second heartbeat affordable on a mobile
  ///   connection. Keep it that shape.
  /// ⚠ TWO SECONDS, DOWN FROM FOUR, BECAUSE THIS IS THE RED BADGE ITSELF.
  ///   «اريد سرعة وصول علامة حمراء تشير لرساله غير مقروءه لانها الان تتاخر».
  ///   Four seconds is not slow for a count; it is slow for the only signal a
  ///   man on any other screen has that somebody wrote to him.
  ///
  /// ⚠ AND IT IS AFFORDABLE ONLY BECAUSE OF THE QUERY'S SHAPE — one capped
  ///   column, no message bodies. Keep it that way: the moment this fetches
  ///   rows, two seconds becomes the wrong number and the bell becomes the
  ///   most expensive thing in the app.
  ///
  /// ⚠ THIS IS THE FOREGROUND CLOCK. In a pocket it is the background
  ///   heartbeat that drives it, at ten seconds — the display is off there and
  ///   the battery arithmetic is the opposite way round.
  static const Duration _interval = Duration(seconds: 2);

  Timer? _timer;
  int _lastRead = 0;
  bool _gone = false;

  /// The count this notifier last announced, so a rise is announced ONCE.
  int _announced = 0;

  @override
  Future<int> build() async {
    // ⚠ NOBODY OUTSIDE THE ASSOCIATION GETS A BELL. A pending applicant, a
    //   suspended account and a signed-out visitor would each get a refused read
    //   every thirty seconds forever — and the badge would be an invitation to a
    //   room the router will not let them open.
    final AppUser? user = ref.watch(authControllerProvider).user;
    // Approved is the whole client-side test, and it is deliberately loose:
    // in_association() on the server is the rule that decides, and a portal
    // account on an unrecognised handset simply reads zero rows. What this
    // stops is the case that is pure waste — a pending or suspended account
    // polling a refusal every thirty seconds for as long as the app is open.
    if (user == null || user.status != AccountStatus.approved) return 0;

    // ⚠ AND ON RETURNING TO THE APP, not only on the clock. A phone that sat
    //   in a pocket comes back to a stale count with the next tick up to ten
    //   seconds away — which is the same «I had to leave and come back» the
    //   interval was already failing at.
    final _OnResume resume = _OnResume(_tick);
    WidgetsBinding.instance.addObserver(resume);

    ref.onDispose(() {
      _gone = true;
      _timer?.cancel();
      WidgetsBinding.instance.removeObserver(resume);
    });
    _timer = Timer.periodic(_interval, (_) => _tick());

    // ── والجرس ────────────────────────────────────────────────────────
    // ⚠ THE RED BADGE IS WHAT THE ASSOCIATION MEASURED — «اريد سرعة وصول
    //   علامة حمراء تشير لرساله غير مقروءه لانها الان تتاخر» — and it is the
    //   one signal a man on any OTHER screen has. The clock above already
    //   answers in two seconds; this answers in the time a websocket takes.
    //
    // ⚠ AND THE COUNT IS WHAT RINGS THE CHIME AND PAINTS THE BADGE, so this
    //   one line makes the sound, the number and the notification all arrive
    //   together. They ride one tick by design — see _tick.
    final VoidCallback deafen = ref.read(doorbellProvider).listen((Ring r) {
      if (r == Ring.chat) _tick();
    });
    ref.onDispose(deafen);

    _lastRead = await ref.read(chatReadStateProvider).lastRead();
    final int first = await ref
        .read(chatRepositoryProvider)
        .unreadSince(_lastRead);
    // Arms the chime WITHOUT ringing: the first reading is «how many were
    // waiting before the app opened», and a sound for those would greet
    // every launch with yesterday's messages. See ChatChime._seen.
    ref.read(chatChimeProvider).onCount(first, suppressed: true);
    return first;
  }

  Future<void> _tick() async {
    try {
      _lastRead = await ref.read(chatReadStateProvider).lastRead();
      final int n = await ref
          .read(chatRepositoryProvider)
          .unreadSince(_lastRead);
      if (_gone) return;
      // ⚠ THE CHIME RIDES THE COUNT, NOT THE MESSAGES. It rings exactly when
      //   the red badge changes, which is what the association asked for —
      //   «يظهر الصوت مع الايقونه الحمره وعدد الارقام» — and it means the
      //   sound can never disagree with what is on screen. A second poll
      //   watching for messages would eventually do both.
      final bool onScreen = ref.read(chatScreenOpenProvider);
      ref.read(chatChimeProvider).onCount(n, suppressed: onScreen);

      // ── والإشعار، لمن التطبيق ليس أمامه ─────────────────────────────
      // ⚠ THE CHIME IS NOT ENOUGH WHILE THE PHONE IS IN A POCKET. A sound
      //   with nothing on the lock screen is a noise he cannot act on and
      //   cannot look up afterwards.
      //
      // ⚠ ON THE RISE ONLY, and cleared when the count reaches zero — which
      //   is what opening the room does. Re-posting on every tick would
      //   re-alert the phone fifteen times a minute for one message; leaving
      //   it up after he has read them would be a badge that lies.
      if (onScreen || n == 0) {
        unawaited(AppNotifier.clearMessages());
      } else if (n > _announced) {
        unawaited(
          AppNotifier.message(l10nTitle(n), NotifyText.newMessages),
        );
      }
      _announced = n;

      state = AsyncValue<int>.data(n);
    } on Object {
      // A failed poll leaves the previous count standing. A bell that flickers
      // to zero on one dropped request is worse than a bell that is a minute
      // stale — the whole point of it is that it can be trusted at a glance.
    }
  }

  /// اسأل الآن — من نبضة الخدمة الأماميّة وهو في الخلفية.
  ///
  /// ⚠ NOT `ref.invalidate`, WHICH WOULD BE THE OBVIOUS THING AND WOULD SILENCE
  ///   THE CHIME. Invalidating rebuilds the notifier, and `build()` deliberately
  ///   arms the chime with `suppressed: true` — «the first count never rings»,
  ///   so a launch is not greeted with yesterday's messages. Driving the
  ///   background from an invalidate would make every background reading a
  ///   first reading, and the sound would never come.
  Future<void> refresh() => _tick();

  /// Called when the room has been read to the bottom.
  ///
  /// Marks against what the SERVER has rather than the last row the list
  /// rendered: the two differ by whatever arrived between the fetch and the
  /// frame, and the difference would sit in the badge forever.
  Future<void> markAllRead() async {
    try {
      final int newest = await ref.read(chatRepositoryProvider).newestId();
      await ref.read(chatReadStateProvider).markRead(newest);
      _lastRead = newest;
      if (_gone) return;
      state = const AsyncValue<int>.data(0);
    } on Object {
      // Nothing to do: the badge stays as it was and the next tick corrects it.
    }
  }

  /// What the room considers already seen, for the «رسائل جديدة» line inside it.
  int get lastReadId => _lastRead;
}

final AutoDisposeAsyncNotifierProvider<ChatUnread, int> chatUnreadProvider =
    AutoDisposeAsyncNotifierProvider<ChatUnread, int>(ChatUnread.new);

/// The bell, in the app bar of every screen.
///
/// ── WHY IN THE BAR AND NOT ON THE DESTINATION ───────────────────────────────
/// المحادثات sits behind «المزيد», one tap down, which is the right weight for a
/// screen people visit a few times a day. A badge THERE would be invisible until
/// the sheet is opened — which is precisely when nobody needs telling. The bar
/// is on every screen, so the answer is where the question is asked.
class ChatBell extends ConsumerWidget {
  const ChatBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final int unread = ref.watch(chatUnreadProvider).valueOrNull ?? 0;

    return IconButton(
      onPressed: () => context.go(AppRoutes.chat),
      tooltip: unread > 0 ? l.chatUnreadCount(unread) : l.navChat,
      icon: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Icon(
            unread > 0
                ? Icons.notifications_active_outlined
                : Icons.notifications_none,
          ),
          if (unread > 0)
            PositionedDirectional(
              top: -4,
              end: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  // ⚠ A CAP, AND IT IS NOT COSMETIC. The count itself is capped
                  //   at 99 by the query, so a room left unread for a month
                  //   still costs one small request — and «99+» is the same
                  //   answer to the reader as any larger number.
                  unread > 99 ? l.chatUnreadMany : '$unread',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onFill,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How many are waiting in each private conversation, for the board's inbox.
///
/// A plain FutureProvider with no clock of its own: the inbox is a screen you
/// are looking at, and `chatThreadsProvider` beside it is already re-read when
/// the screen is. A third timer would be a third request for the same answer.
final FutureProvider<Map<int, int>> threadUnreadProvider =
    FutureProvider<Map<int, int>>((Ref ref) async {
      // ⚠ RE-RUNS WHENEVER THE BELL DOES, and had nothing at all before this.
      //   The numbers beside each name sat frozen until the screen itself was
      //   rebuilt — the same complaint as the bell, one screen deeper. Watching
      //   the bell buys this its cadence for free and costs no second timer,
      //   and the two can never disagree about when they last looked.
      ref.watch(chatUnreadProvider);
      final ChatReadState reads = ref.watch(chatReadStateProvider);
      return ref
          .watch(chatRepositoryProvider)
          .unreadByThread(await reads.threadMarks());
    });

/// The count beside one conversation.
///
/// ⚠ GREEN, AND IT IS THE ONE PLACE IN THIS APP WHERE GREEN IS NOT MONEY.
///   Everywhere else the palette's success tone means «collected». Here it is
///   what every messaging app on these handsets uses for the same thing, and a
///   red count beside a member's name in an inbox would read as a problem with
///   HIM rather than as a message from him.
class ThreadUnreadBadge extends StatelessWidget {
  const ThreadUnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final L l = L.of(context);

    return Semantics(
      label: l.chatUnreadCount(count),
      child: Container(
        margin: const EdgeInsetsDirectional.only(start: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        constraints: const BoxConstraints(minWidth: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.success,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          count > 99 ? l.chatUnreadMany : '$count',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.onFill,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

/// What is waiting in each of the two rooms.
///
/// ── WHY THE SEGMENTS NEED THEIR OWN NUMBERS ─────────────────────────────────
/// A man sitting in الخاص is told nothing when المجلس moves, and the reverse. The
/// bell says «هناك ٣» from the top of the screen and does not say WHERE — which
/// on this screen, where the two rooms are one tap apart, is the only part he
/// needs.
///
/// ⚠ THE ROOM HE IS IN IS ALWAYS ZERO, and that is not special-cased here. It
///   falls out of the marks: the list writes its room's mark as it renders, so
///   by the time this is asked the room in front of him has nothing above its
///   mark. A count that had to be suppressed by the screen would be a second
///   place the rule lives.
typedef RoomUnread = ({int hall, int private});

final FutureProvider<RoomUnread>
roomUnreadProvider = FutureProvider<RoomUnread>((Ref ref) async {
  // Rides the bell's clock, exactly as the inbox counts do: three timers for
  // one question would be three requests where one will do.
  ref.watch(chatUnreadProvider);

  final ChatReadState reads = ref.watch(chatReadStateProvider);
  final ChatRepository repo = ref.watch(chatRepositoryProvider);

  final int hall = await repo.unreadInHall(await reads.hallRead());
  // Summed over every thread this caller can see — which is HIS OWN for a
  // member and all of them for staff, decided by RLS rather than here.
  final Map<int, int> byThread = await repo.unreadByThread(
    await reads.threadMarks(),
  );
  final int private = byThread.values.fold<int>(0, (int a, int b) => a + b);

  return (hall: hall, private: private);
});

/// A count on a segment label.
///
/// Small and inline rather than a floating dot: it sits inside a button whose
/// width is already decided by its text, so anything positioned outside the box
/// would be clipped by the segmented control.
class SegmentCount extends StatelessWidget {
  const SegmentCount({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final L l = L.of(context);

    return Container(
      margin: const EdgeInsetsDirectional.only(start: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        count > 99 ? l.chatUnreadMany : '$count',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: AppColors.onFill,
          height: 1.2,
        ),
      ),
    );
  }
}
