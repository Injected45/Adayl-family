import 'package:family_app/features/call/data/call_ringtone.dart';
import 'package:family_app/features/call/domain/models.dart';
import 'package:family_app/features/call/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── الفجوة بين «ردّ» وبين أن يأخذ مقعده ────────────────────────────────────
///
/// ⚠ THE PRE-EMPTIVE SILENCE DEFEATED ITSELF, and the poll was what undid it.
///   Pressing ردّ runs three things in order:
///
///       1. silence the tone            ← instant
///       2. await join_call()           ← a round trip, one or two seconds
///       3. _open() sets activeCall     ← only after (2) returns
///
///   The incoming-call poll fires every two seconds. A tick landing between
///   (1) and (3) sees a call that is still live and an `activeCallProvider`
///   that is still null — the two conditions the ringtone waits for — so it
///   STARTS THE TONE AGAIN, on a call the man has already answered, and
///   re-posts the notification with it.
///
///   On a fast wifi the gap is short enough to miss. On a Libyan mobile
///   connection it is the ordinary case, and the symptom is a phone that rings
///   into the first seconds of the conversation.
///
/// ⚠ THE FIX IS AN ID, NOT A FLAG. A handset-wide «he answered» would silence
///   the NEXT call too. A decision belongs to one call and dies with it.
CallView _call({required int id, String status = 'ترن'}) =>
    CallView.fromJson(<String, dynamic>{
      'id': id,
      'threadAdeelId': null,
      'callerName': 'المهدي',
      'mine': false,
      'status': status,
      'startedAt': '2026-08-21T10:00:00Z',
      'answeredAt': null,
      'endedAt': null,
    });

/// A ringtone that records rather than sounds.
class _Tone extends CallRingtone {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async => stops++;
}

/// ⚠ build() IS SKIPPED, AND THAT IS THE POINT OF THE STUB. The real one
///   watches the session — which needs a configured Supabase — and starts a
///   timer and a doorbell subscription. None of that is the thing under test:
///   what is being pinned is the DECISION inside _notify, which is pure.
class _Poll extends IncomingCall {
  @override
  Future<CallView?> build() async => null;
}

void main() {
  late _Tone tone;
  late ProviderContainer container;

  setUp(() {
    tone = _Tone();
    container = ProviderContainer(
      overrides: <Override>[
        callRingtoneProvider.overrideWithValue(tone),
        incomingCallProvider.overrideWith(_Poll.new),
      ],
    );
    addTearDown(container.dispose);
  });

  test('a ringing call from somebody else sounds the tone', () {
    final IncomingCall n = container.read(incomingCallProvider.notifier);
    n.notifyForTest(_call(id: 7));
    expect(tone.starts, 1);
  });

  // ⚠ THE BUG, REPRODUCED: the tick that lands while join_call is still in
  //   flight. activeCallProvider is null, the call is live, and before the fix
  //   this started the tone for a second time.
  test('⚠ a tick during the join round trip does NOT ring again', () {
    final IncomingCall n = container.read(incomingCallProvider.notifier);
    n.notifyForTest(_call(id: 7));
    expect(tone.starts, 1);

    // He presses ردّ. activeCallProvider is NOT set yet — join_call is still
    // travelling.
    n.decided(7);
    expect(tone.stops, greaterThanOrEqualTo(1));

    // The poll fires. Same call, still live, still no active session.
    n.notifyForTest(_call(id: 7, status: 'جارية'));
    n.notifyForTest(_call(id: 7, status: 'جارية'));

    expect(
      tone.starts,
      1,
      reason: 'the tone restarted on a call he had already answered',
    );
  });

  // ⚠ AND THE DECISION MUST NOT OUTLIVE ITS CALL. A handset-wide flag would
  //   silence every call after the first one answered — a phone that rings once
  //   and never again, which is worse than the bug it fixed.
  test('⚠ but the NEXT call still rings', () {
    final IncomingCall n = container.read(incomingCallProvider.notifier);
    n.notifyForTest(_call(id: 7));
    n.decided(7);

    // The answered call ends.
    n.notifyForTest(null);
    // A different man calls.
    n.notifyForTest(_call(id: 8));

    expect(tone.starts, 2, reason: 'the second call was silenced too');
  });

  // ⚠ AND THE RESET IN THE `!live` BRANCH NEEDED ITS OWN CASE. The test above
  //   passes with or without it — id 8 differs from id 7, so the decision never
  //   applied to it — which means the line was written, commented, and covered
  //   by nothing. A guard no test can fail is a guard nobody will notice
  //   losing.
  //
  //   This is the property it actually holds: a call that was decided, went
  //   away, and CAME BACK must ring. Ids do not repeat in practice, so it is
  //   defensive rather than load-bearing — but it is now stated by a test
  //   instead of by a sentence.
  test('⚠ a decided call that vanishes and returns rings again', () {
    final IncomingCall n = container.read(incomingCallProvider.notifier);
    n.notifyForTest(_call(id: 7));
    n.decided(7);
    n.notifyForTest(null);
    n.notifyForTest(_call(id: 7));

    expect(tone.starts, 2, reason: 'the decision outlived the call it was for');
  });

  test('declining silences it the same way', () {
    final IncomingCall n = container.read(incomingCallProvider.notifier);
    n.notifyForTest(_call(id: 9));
    n.decided(9);
    n.notifyForTest(_call(id: 9));

    expect(tone.starts, 1);
  });

  // The call going away always stops the tone, whatever was decided.
  test('a call that ends stops the tone', () {
    final IncomingCall n = container.read(incomingCallProvider.notifier);
    n.notifyForTest(_call(id: 3));
    n.notifyForTest(null);
    expect(tone.stops, greaterThanOrEqualTo(1));
  });

  // ⚠ AND MY OWN CALL NEVER RINGS AT ME. The caller's poll returns the call he
  //   just raised, with `mine` true.
  test('a call I raised myself is silent', () {
    final IncomingCall n = container.read(incomingCallProvider.notifier);
    n.notifyForTest(
      CallView.fromJson(<String, dynamic>{
        'id': 4,
        'threadAdeelId': null,
        'callerName': 'أنا',
        'mine': true,
        'status': 'ترن',
        'startedAt': '2026-08-21T10:00:00Z',
        'answeredAt': null,
        'endedAt': null,
      }),
    );
    expect(tone.starts, 0);
  });
}
