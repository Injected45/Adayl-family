import 'package:fake_async/fake_async.dart';
import 'package:family_app/features/chat/data/chat_repository.dart';
import 'package:family_app/features/chat/domain/models.dart';
import 'package:family_app/features/chat/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── لماذا لا تصل الرسائل بسرعة ─────────────────────────────────────────────
///
/// «الرسائل الجديدة في المحادثات لا تظهر بسرعة ولا بد من وقت طويل وأحياناً
/// تستوجب خروج ودخول ليتم التحديث وتصل الرسائل».
///
/// The room polls. The bug was that it could STOP polling while still on
/// screen, and the only cure was the one the association found by itself:
/// leave and come back. These tests are the two halves of that.
///
/// ⚠ THEY DRIVE THE REAL [ChatController], not a stub. Every other chat test
///   overrides `chatProvider` wholesale — which is right for testing a widget
///   and useless here, because the defect was in the controller the override
///   replaces. Nothing in the suite had ever run its timer.
ChatMessage _msg(int id) => ChatMessage.fromJson(<String, dynamic>{
  'id': id,
  'body': 'م$id',
  'authorName': 'فلان',
  'createdAt': '2026-08-21T10:00:00Z',
  'mine': false,
  'deleted': false,
  'fromStaff': true,
  'threadAdeelId': null,
  'authorAdeelId': null,
});

/// A room the test can add to, counting what the controller asks for.
class _Repo implements ChatRepository {
  List<ChatMessage> room = <ChatMessage>[_msg(1), _msg(2)];
  int polls = 0;

  @override
  Future<List<ChatMessage>> messages({int? threadAdeelId, int limit = 200}) async =>
      List<ChatMessage>.of(room);

  @override
  Future<List<ChatMessage>> refreshFrom(int fromId, {int? threadAdeelId}) async {
    polls++;
    return room.where((ChatMessage m) => m.id >= fromId).toList();
  }

  // Nothing else is reached on this path; a call that did would fail loudly
  // rather than return a plausible empty answer.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_Repo repo) => ProviderContainer(
  overrides: <Override>[chatRepositoryProvider.overrideWithValue(repo)],
);

void main() {
  test('the room polls while it is open, and new messages appear', () {
    fakeAsync((FakeAsync async) {
      final _Repo repo = _Repo();
      final ProviderContainer c = _container(repo);
      addTearDown(c.dispose);
      c.listen(chatProvider(null), (_, _) {});

      async.elapse(const Duration(milliseconds: 10));
      expect(c.read(chatProvider(null)).value, hasLength(2));

      repo.room = <ChatMessage>[...repo.room, _msg(3)];
      async.elapse(const Duration(seconds: 2));

      expect(c.read(chatProvider(null)).value, hasLength(3));
    });
  });

  // ══ THE BUG ══════════════════════════════════════════════════════════════
  //
  // ⚠ RIVERPOD RE-RUNS `build()` ON THE SAME NOTIFIER OBJECT after an
  //   invalidate, and it calls the previous build's `onDispose` first. That
  //   cancelled the Timer and left the FIELD holding the dead one — so
  //   `_restartAt` saw a non-null timer of the right length, declined to make
  //   another, and the room never polled again for as long as it stayed open.
  //
  //   Everything else on the screen kept working, which is why it read as
  //   «slow» rather than as broken: the bell still counted, the composer still
  //   sent, and sending called `_reload()` directly. Only messages ARRIVING
  //   from the other side stopped — until you left the screen and came back,
  //   which disposes the notifier for real and builds a fresh one.
  test('⚠ and it goes on polling after the provider is rebuilt', () {
    fakeAsync((FakeAsync async) {
      final _Repo repo = _Repo();
      final ProviderContainer c = _container(repo);
      addTearDown(c.dispose);
      c.listen(chatProvider(null), (_, _) {});

      async.elapse(const Duration(milliseconds: 10));
      expect(c.read(chatProvider(null)).value, hasLength(2));

      // What `refreshAll`, a resume, or any watched dependency does.
      c.invalidate(chatProvider(null));
      async.elapse(const Duration(milliseconds: 10));

      final int before = repo.polls;
      repo.room = <ChatMessage>[...repo.room, _msg(3)];
      async.elapse(const Duration(seconds: 2));

      expect(
        repo.polls,
        greaterThan(before),
        reason: 'the timer died on the rebuild and was never replaced',
      );
      expect(c.read(chatProvider(null)).value, hasLength(3));
    });
  });

  // ── والساعة البطيئة كانت لا تعمل أصلاً ────────────────────────────────────
  //
  // ⚠ THE ADAPTIVE CADENCE WAS WRITTEN, DOCUMENTED, AND NEVER REACHED. The
  //   commonest tick returns an EMPTY tail — nothing newer than the newest row
  //   — and that path returned before counting the silence. So `_quietTicks`
  //   almost never advanced, the demotion never fired, and every open room sat
  //   on the one-second tier all day against the association's free tier.
  //
  //   Counted here in POLLS rather than in seconds: the test does not care what
  //   the two tiers are, only that a silent room ends up asking less often than
  //   a live one. That keeps it true if the durations are ever retuned.
  test('⚠ a silent room falls back to the slow clock', () {
    fakeAsync((FakeAsync async) {
      final _Repo repo = _Repo();
      final ProviderContainer c = _container(repo);
      addTearDown(c.dispose);
      c.listen(chatProvider(null), (_, _) {});
      async.elapse(const Duration(milliseconds: 10));

      // Long enough to pass liveFor with room to spare.
      async.elapse(ChatController.liveFor + const Duration(seconds: 5));
      final int afterQuiet = repo.polls;

      // Ten more seconds of the same silence, now on the slow tier.
      async.elapse(const Duration(seconds: 10));
      final int slow = repo.polls - afterQuiet;

      expect(
        slow,
        lessThan(10),
        reason: 'ten seconds of silence still cost ten polls — the demotion '
            'never fired',
      );

      // ⚠ AND IT COMES BACK. A room that could not return to the fast clock
      //   would be the same complaint one step later.
      repo.room = <ChatMessage>[...repo.room, _msg(3)];
      async.elapse(ChatController.idle + const Duration(milliseconds: 200));
      expect(c.read(chatProvider(null)).value, hasLength(3));

      // The SAME ten-second window as above, so the two numbers are
      // comparable — counting a shorter one and calling it faster would
      // prove nothing at all.
      final int afterWake = repo.polls;
      async.elapse(const Duration(seconds: 10));
      expect(
        repo.polls - afterWake,
        greaterThan(slow),
        reason: 'a message arrived and the room did not speed back up',
      );
    });
  });
}
