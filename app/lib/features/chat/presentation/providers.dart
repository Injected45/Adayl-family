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
  static const int revisit = 40;

  // ── THE CADENCE FOLLOWS THE CONVERSATION ─────────────────────────────────
  //
  // A flat four seconds was the wrong shape in both directions: too slow while
  // two men are actually talking — the association reported the delay — and too
  // fast for a room nobody has spoken in since yesterday, which paid for the
  // same fifteen requests a minute to be told nothing fifteen times.
  //
  // So the interval is not a constant. A room that has just moved is polled at
  // ONE SECOND, and one that has been silent for a while falls back to SIX. A
  // reply lands while the exchange is live, which is the only moment anybody
  // measures — and an idle screen is a third of the traffic it used to be.
  //
  // ⚠ NET COST IS LOWER, NOT HIGHER, and that is the point rather than a
  //   consolation: real conversations are short bursts inside long silences.
  //   A five-minute exchange costs about ninety extra requests; the twenty-five
  //   idle minutes around it save two hundred and fifty.
  static const Duration live = Duration(seconds: 1);
  static const Duration idle = Duration(seconds: 6);

  /// How long a room stays on the fast clock after the last thing happened in
  /// it. Long enough to cover the pause while the other man is typing his
  /// answer, short enough that a room left open on a desk goes quiet by itself.
  static const Duration liveFor = Duration(seconds: 40);

  /// Ticks since anything changed. Counted rather than timed so it needs no
  /// clock of its own and cannot drift.
  int _quietTicks = 0;
  Duration _current = live;

  /// ⚠ THE FAST CLOCK WOULD OTHERWISE BE FOUR TIMES THE TRAFFIC.
  ///
  ///   Every poll re-reads a window of revisit messages, because a DELETION
  ///   changes a row that is already on screen and an id cursor cannot see it.
  ///   Forty rows with their bodies, four times a second faster, is a real
  ///   cost on a Libyan mobile connection.
  ///
  ///   So the window is not re-read on every tick. Most ticks ask only for ids
  ///   ABOVE the newest — which in a quiet second is an empty response of a few
  ///   bytes — and every fifth one re-reads the window. A deleted message
  ///   therefore reaches the other handsets within five seconds instead of one,
  ///   which is the right thing to make slower: nobody is waiting on a
  ///   tombstone the way they wait on a reply.
  static const int sweepEvery = 5;
  int _tick = 0;

  @override
  Future<List<ChatMessage>> build(int? threadAdeelId) async {
    // Opening a room IS activity: the first seconds after it appears are when
    // somebody is most likely to be answering what he came to answer.
    _restartAt(live);
    ref.onDispose(() => _timer?.cancel());
    return ref.read(chatRepositoryProvider).messages(threadAdeelId: arg);
  }

  /// Swaps the clock, and only when it actually differs.
  ///
  /// Cancelling and recreating a Timer on every tick would restart the
  /// countdown each time and, at the one-second tier, could starve the poll
  /// entirely on a slow connection.
  void _restartAt(Duration d) {
    if (_timer != null && _current == d) return;
    _current = d;
    _timer?.cancel();
    _timer = Timer.periodic(d, (_) => _poll());
  }

  /// Called whenever the room moved — a message arrived, or one was sent.
  void _wakeUp() {
    _quietTicks = 0;
    _restartAt(live);
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
      _tick++;
      final bool sweep = _tick % sweepEvery == 0;
      // A sweep re-reads the window and catches deletions; every other tick
      // asks only for what is newer than the newest row on screen.
      final int from = sweep
          ? (current.length > revisit
                ? current[current.length - revisit].id
                : current.first.id)
          : current.last.id + 1;

      // ONE request, not two: `refreshFrom` covers both the new messages and the
      // window being revisited, because `id >= from` includes everything after
      // it. Two calls would double the polling traffic to answer one question.
      final List<ChatMessage> tail = await repo.refreshFrom(
        from,
        threadAdeelId: arg,
      );
      if (tail.isEmpty) return;

      // ⚠ TWO SHAPES, ONE MERGE. On a sweep, `from` is inside the list and the
      //   window REPLACES the tail — that is how a deletion propagates. On an
      //   ordinary tick `from` is past the end, so nothing is dropped and the
      //   new rows are simply appended. The same expression covers both,
      //   because `m.id < from` keeps everything when from is past the end.
      final List<ChatMessage> merged = <ChatMessage>[
        ...current.where((ChatMessage m) => m.id < from),
        ...tail,
      ];
      // Only publish when something actually moved. A room where nobody is
      // talking should not rebuild the screen fifteen times a minute — it costs
      // battery and it fights the scroll position.
      if (_sameAs(current, merged)) {
        // Nothing moved. Count the silence, and drop to the slow clock once
        // the room has been quiet for liveFor.
        _quietTicks++;
        if (_quietTicks * _current.inMilliseconds >= liveFor.inMilliseconds) {
          _restartAt(idle);
        }
        return;
      }
      // Something arrived: back to the fast clock, because a message is almost
      // never the last one in an exchange.
      _wakeUp();
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
    // ⚠ SENDING PUTS THE ROOM BACK ON THE FAST CLOCK, and this is the half the
    //   sender actually feels: he has just spoken, so an answer is more likely
    //   in the next twenty seconds than at any other moment. Without it a room
    //   that had gone idle would answer him on the six-second tier.
    _wakeUp();
    await _reload();
  }

  Future<void> remove(int id) async {
    await ref.read(chatRepositoryProvider).delete(id);
    _wakeUp();
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
