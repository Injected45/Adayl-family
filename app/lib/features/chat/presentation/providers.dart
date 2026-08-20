import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/chat_repository.dart';
import '../domain/models.dart';

final Provider<ChatRepository> chatRepositoryProvider =
    Provider<ChatRepository>(
      (Ref ref) => ChatRepository(ref.watch(supabaseClientProvider)),
    );

/// The room, kept current while somebody is looking at it.
///
/// ── WHY A TIMER AND NOT REALTIME ────────────────────────────────────────────
/// Supabase Realtime is the reflex and it excludes exactly the people this
/// feature exists for. `my_adeel_id()` reads the `x-device-id` REQUEST HEADER —
/// one handset per عديل — and a websocket carries no headers, so a
/// postgres_changes subscription evaluated for a portal member matches no policy
/// and delivers him nothing. Staff would watch messages appear live while every
/// member sat on a screen that never moved, with the REST reads working
/// perfectly. That is a failure invisible to anyone testing with a staff
/// account, which is the worst kind to build on.
///
/// So it polls, and the poll is the cheapest question the schema can be asked:
/// `id > lastSeen`, an index-only walk from one key, returning nothing on a
/// quiet room. See the note in supabase/migrations/…_chat.sql.
///
/// AUTO-DISPOSED on purpose: the timer lives and dies with the screen, so a
/// backgrounded app is not holding a four-second heartbeat against the
/// association's free tier.
final AutoDisposeAsyncNotifierProviderFamily<
  ChatController,
  List<ChatMessage>,
  int?
>
chatProvider =
    AutoDisposeAsyncNotifierProviderFamily<
      ChatController,
      List<ChatMessage>,
      int?
    >(ChatController.new);

class ChatController
    extends AutoDisposeFamilyAsyncNotifier<List<ChatMessage>, int?> {
  Timer? _timer;

  /// How much of the tail is re-read on each poll, over and above what is new.
  ///
  /// A deletion changes a row that is ALREADY on screen, and the `id > lastSeen`
  /// cursor cannot see it — its id is not greater than anything. Re-reading a
  /// window of the recent messages is what makes «حُذفت الرسالة» appear on the
  /// other handsets. Bounded rather than a full refresh, because the whole point
  /// of the cursor is not to send the year's conversation every four seconds.
  static const int _revisit = 40;

  static const Duration _interval = Duration(seconds: 4);

  @override
  Future<List<ChatMessage>> build(int? threadAdeelId) async {
    _timer = Timer.periodic(_interval, (_) => _poll());
    ref.onDispose(() => _timer?.cancel());
    return ref.read(chatRepositoryProvider).messages(threadAdeelId: arg);
  }

  Future<void> _poll() async {
    final List<ChatMessage>? current = state.valueOrNull;
    // Nothing loaded yet, or a load in flight. Skipping is right: the build is
    // about to deliver the whole tail anyway, and a poll racing it would append
    // rows to a list that is being replaced.
    if (current == null || current.isEmpty) {
      if (current != null && current.isEmpty) await _reload();
      return;
    }

    try {
      final ChatRepository repo = ref.read(chatRepositoryProvider);
      final int from = current.length > _revisit
          ? current[current.length - _revisit].id
          : current.first.id;

      // ONE request, not two: `refreshFrom` covers both the new messages and the
      // window being revisited, because `id >= from` includes everything after
      // it. Two calls would double the polling traffic to answer one question.
      final List<ChatMessage> tail = await repo.refreshFrom(
        from,
        threadAdeelId: arg,
      );
      if (tail.isEmpty) return;

      final List<ChatMessage> merged = <ChatMessage>[
        ...current.where((ChatMessage m) => m.id < from),
        ...tail,
      ];
      // Only publish when something actually moved. A room where nobody is
      // talking should not rebuild the screen fifteen times a minute — it costs
      // battery and it fights the scroll position.
      if (_sameAs(current, merged)) return;
      state = AsyncValue<List<ChatMessage>>.data(merged);
    } catch (_) {
      // A poll that fails is a poll, not an error state. The screen keeps the
      // messages it has and tries again in four seconds; replacing a readable
      // conversation with an error card because one request timed out on a
      // Libyan mobile connection would be the worse behaviour by far.
    }
  }

  bool _sameAs(List<ChatMessage> a, List<ChatMessage> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      // id AND deleted: a deletion changes nothing else the screen shows, and
      // comparing ids alone would leave a tombstone invisible until the next
      // message arrived.
      if (a[i].id != b[i].id || a[i].deleted != b[i].deleted) return false;
    }
    return true;
  }

  Future<void> _reload() async {
    try {
      state = AsyncValue<List<ChatMessage>>.data(
        await ref.read(chatRepositoryProvider).messages(threadAdeelId: arg),
      );
    } catch (_) {
      // Same reasoning as _poll.
    }
  }

  /// Sends, then reads back immediately rather than waiting for the next tick.
  ///
  /// The delay would only ever be felt by the person who just typed, which is
  /// the one person who must never wonder whether it went.
  Future<void> send(String body) async {
    await ref.read(chatRepositoryProvider).send(body, threadAdeelId: arg);
    await _reload();
  }

  Future<void> remove(int id) async {
    await ref.read(chatRepositoryProvider).delete(id);
    await _reload();
  }

  Future<void> refresh() => _reload();
}

/// The board's inbox — one row per private conversation.
///
/// Staff-only by the SAME policy as the messages themselves, not by a rule of
/// its own: a member reading this gets his own conversation and never a list of
/// who else has written.
///
/// Not polled. An inbox is read, acted on and left; the four-second heartbeat
/// belongs to the conversation you are actually looking at, and running one here
/// as well would double the traffic for a list nobody watches.
final AutoDisposeFutureProvider<List<ChatThread>> chatThreadsProvider =
    AutoDisposeFutureProvider<List<ChatThread>>(
      (Ref ref) => ref.watch(chatRepositoryProvider).threads(),
    );
