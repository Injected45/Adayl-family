import 'package:family_app/features/chat/domain/models.dart';
import 'package:family_app/features/chat/presentation/providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The room's clock follows the conversation.
///
/// ── WHY NOT ONE CONSTANT ────────────────────────────────────────────────────
/// Four seconds flat was wrong in both directions: too slow while two men are
/// actually talking — which is what the association noticed — and too fast for a
/// room nobody has spoken in since yesterday, which paid for fifteen requests a
/// minute to be told nothing fifteen times.
///
/// ⚠ AND THE NET COST IS LOWER, WHICH IS THE POINT AND NOT A CONSOLATION. Real
///   conversations are short bursts inside long silences: a five-minute exchange
///   costs about ninety extra requests, and the twenty-five idle minutes around
///   it save two hundred and fifty.
void main() {
  // ⚠ THIS FILE USED TO PIN THE BARE NUMBERS — «live is one second, idle is
  //   three» — and that made it a tripwire rather than a rule: it failed on a
  //   deliberate change and said nothing about whether the change was WRONG.
  //   What matters is the arithmetic between them, so that is what is pinned
  //   now, with one bound on each so they cannot drift to nonsense.
  test('a reply is never more than a second and a half away', () {
    // «مافيه تاخير لحظي للرساله، يفترض تكون اسرع بأجزاء من الثانيه». The idle
    // tier is the WORST case any message can hit, so it is the number that
    // decides how fast the room feels — not the live tier, which only applies
    // to a room that has just moved.
    expect(ChatController.idle.inMilliseconds, lessThanOrEqualTo(1500));
    expect(ChatController.live.inMilliseconds, lessThanOrEqualTo(700));
    expect(
      ChatController.live.inMilliseconds,
      lessThan(ChatController.idle.inMilliseconds),
      reason: 'the busy tier must be the faster one',
    );
    // And a floor, because a poll faster than the round trip to Tripoli buys
    // nothing and stacks requests on a slow connection.
    expect(ChatController.live.inMilliseconds, greaterThanOrEqualTo(400));
  });

  test('a room stays live across an ordinary pause, not just a short one', () {
    // ⚠ FORTY SECONDS WAS SHORTER THAN A MAN THINKING. The room fell to the
    //   slow clock in the MIDDLE of an exchange, which meant the message the
    //   demotion delayed was the first one after a pause — precisely the one
    //   somebody is waiting for.
    expect(ChatController.liveFor.inSeconds, greaterThanOrEqualTo(60));
    expect(
      ChatController.liveFor.inMilliseconds,
      greaterThan(ChatController.live.inMilliseconds),
    );
  });

  // ⚠ THE PRODUCT, NOT THE COUNT, AND THIS IS THE ONE THAT WOULD HAVE BEEN
  //   MISSED. `sweepEvery` counts TICKS, so speeding the clock silently speeds
  //   the sweep with it — raising the single expense this whole scheme exists
  //   to control, with nothing in the diff to show it. Pinning the count alone
  //   would have passed a change that made the sweep fire twice as often.
  test('⚠ the deletion sweep stays about five seconds apart, whatever the clock', () {
    final int sweepMs = ChatController.sweepEvery * ChatController.live.inMilliseconds;
    expect(
      sweepMs,
      inInclusiveRange(4000, 6500),
      reason:
          'sweepEvery counts ticks — it must move whenever `live` does, or the '
          'window re-read (forty rows WITH bodies) quietly gets more frequent',
    );
    expect(
      sweepMs,
      lessThanOrEqualTo(ChatController.liveFor.inMilliseconds),
      reason: 'a live room must sweep at least once before it goes idle',
    );
  });

  test('the revisit window is wide enough to be worth sweeping', () {
    // Sweeping a window narrower than a screenful would miss deletions that are
    // still visible, which is the one thing the sweep exists for.
    expect(ChatController.revisit, greaterThanOrEqualTo(20));
  });

  test('a message model still parses the id the cursor depends on', () {
    // The whole cadence rests on ids being monotonic and present: `id > newest`
    // is the cheap tick, and `id >= window` is the sweep.
    final ChatMessage m = ChatMessage.fromJson(<String, dynamic>{
      'id': 42,
      'authorName': 'أيمن',
      'body': 'أهلاً',
      'createdAt': '2026-08-20T09:00:00Z',
      'mine': false,
      'fromStaff': false,
      'deleted': false,
    });
    expect(m.id, 42);
  });
}
