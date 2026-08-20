import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/router/destinations.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/chat_read_state.dart';
import '../data/chat_repository.dart';
import 'providers.dart';

final Provider<ChatReadState> chatReadStateProvider = Provider<ChatReadState>(
  (Ref ref) => const ChatReadState(FlutterSecureStorage()),
);

/// How many messages are waiting, refreshed on its own slow clock.
///
/// ── WHY A SECOND POLL, AND WHY A SLOWER ONE ─────────────────────────────────
/// The room polls every four seconds, and only while the room is on screen. The
/// bell has to ring on every OTHER screen, which is where a member spends almost
/// all of his time — so it needs its own timer, and it must be far cheaper: one
/// column, capped, no message bodies.
///
/// Thirty seconds because a badge is not a conversation. Nobody watches a bell
/// waiting for it to change; what matters is that it is right within a minute of
/// opening the phone, and every tick in between is a request the association
/// pays for on a free project.
///
/// ⚠ IT IS NOT A NOTIFICATION. Nothing rings while the app is closed — that
///   needs a push service, a server key and a Firebase project, none of which
///   exist here. This is «هل هناك جديد» answered while the app is open, which is
///   the honest thing to promise with what the app has.
class ChatUnread extends AutoDisposeAsyncNotifier<int> {
  Timer? _timer;
  int _lastRead = 0;
  bool _gone = false;

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

    ref.onDispose(() {
      _gone = true;
      _timer?.cancel();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());

    _lastRead = await ref.read(chatReadStateProvider).lastRead();
    return ref.read(chatRepositoryProvider).unreadSince(_lastRead);
  }

  Future<void> _tick() async {
    try {
      _lastRead = await ref.read(chatReadStateProvider).lastRead();
      final int n = await ref
          .read(chatRepositoryProvider)
          .unreadSince(_lastRead);
      if (_gone) return;
      state = AsyncValue<int>.data(n);
    } on Object {
      // A failed poll leaves the previous count standing. A bell that flickers
      // to zero on one dropped request is worse than a bell that is a minute
      // stale — the whole point of it is that it can be trusted at a glance.
    }
  }

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
