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
  test('the live clock is one second and the idle clock is six', () {
    // Pinned so neither can drift without somebody reading the reasoning beside
    // them. One second is the tier a reply lands on; six is what a room left
    // open on a desk costs.
    expect(ChatController.live, const Duration(seconds: 1));
    expect(ChatController.idle, const Duration(seconds: 6));
    expect(
      ChatController.live.inMilliseconds,
      lessThan(ChatController.idle.inMilliseconds),
    );
  });

  test('a room stays live for forty seconds after it last moved', () {
    // Long enough to cover the pause while the other man types his answer,
    // short enough that a forgotten screen goes quiet by itself.
    expect(ChatController.liveFor, const Duration(seconds: 40));
    expect(
      ChatController.liveFor.inMilliseconds,
      greaterThan(ChatController.live.inMilliseconds),
    );
  });

  test('⚠ the deletion sweep is rarer than the poll, on purpose', () {
    // Every poll used to re-read forty messages WITH their bodies, because a
    // deletion changes a row already on screen and an id cursor cannot see it.
    // At one second that is four times the traffic — so the window is swept
    // every fifth tick and the rest ask only for what is newer, which in a quiet
    // second is an empty response.
    //
    // The cost is that a tombstone reaches other handsets in about five seconds
    // rather than one. That is the right thing to make slower: nobody waits on a
    // deletion the way they wait on a reply.
    expect(ChatController.sweepEvery, 5);
    expect(
      ChatController.sweepEvery * ChatController.live.inSeconds,
      lessThanOrEqualTo(ChatController.liveFor.inSeconds),
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
