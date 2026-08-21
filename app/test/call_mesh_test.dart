import 'package:family_app/core/domain/wire_values.dart';
import 'package:family_app/features/call/data/call_session.dart';
import 'package:family_app/features/call/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── الشبكة المتداخلة: القراران اللذان تنهار المكالمة بدونهما ───────────────
///
/// A voice call needs a microphone, a peer connection and a second phone —
/// none of which a test has. So the two DECISIONS were lifted out of the
/// session, because they are the two places a group call fails silently and
/// they are pure functions.
///
/// ⚠ BOTH FAILURES LOOK LIKE A BAD NETWORK, which is why they are pinned here
///   rather than left to be found on a Libyan mobile connection with four men
///   on the line.
CallParticipant _p(int id, String user, {bool mine = false}) =>
    CallParticipant(id: id, userId: user, displayName: user, mine: mine);

CallSignal _s({
  required String from,
  String to = '',
  bool mine = false,
  String kind = CallSignalWire.offer,
}) => CallSignal(
  id: 1,
  callId: 1,
  kind: kind,
  payload: const <String, dynamic>{},
  mine: mine,
  fromUserId: from,
  toUserId: to,
);

void main() {
  group('من يعرض على من', () {
    // ⚠ THE MAN WHO JOINED LATER OFFERS. Both sides compute this from the same
    //   two numbers, so there is no round of «you go first» to lose — and no
    //   glare, because one id is always the larger.
    test('the later seat offers to every earlier one', () {
      final List<CallParticipant> room = <CallParticipant>[
        _p(1, 'a'),
        _p(2, 'b'),
        _p(3, 'me', mine: true),
      ];
      expect(
        peersToOfferTo(room, 3).map((CallParticipant p) => p.userId),
        <String>['a', 'b'],
      );
    });

    test('...and the earlier seat offers to nobody, it waits', () {
      final List<CallParticipant> room = <CallParticipant>[
        _p(1, 'me', mine: true),
        _p(2, 'b'),
        _p(3, 'c'),
      ];
      expect(peersToOfferTo(room, 1), isEmpty);
    });

    // ⚠ THE PROPERTY THAT MAKES A MESH WORK AT ALL: for any pair, EXACTLY ONE
    //   of them offers. Tested as a pair rather than as a list, because that is
    //   the claim — «two peers can never both offer, and never both wait».
    test('⚠ for every pair, exactly one offers', () {
      for (int a = 1; a <= 6; a++) {
        for (int b = 1; b <= 6; b++) {
          if (a == b) continue;
          final bool aOffers = peersToOfferTo(<CallParticipant>[
            _p(a, 'a', mine: true),
            _p(b, 'b'),
          ], a).isNotEmpty;
          final bool bOffers = peersToOfferTo(<CallParticipant>[
            _p(b, 'b', mine: true),
            _p(a, 'a'),
          ], b).isNotEmpty;
          expect(aOffers != bOffers, isTrue, reason: 'seats $a and $b');
        }
      }
    });

    // ⚠ A HANDSET THAT OFFERED TO ITSELF would set its own SDP as its own
    //   remote description, and the symptom is a call where the other side
    //   «never answers».
    test('⚠ and never to my own seat, whatever its number', () {
      expect(
        peersToOfferTo(<CallParticipant>[_p(9, 'me', mine: true)], 9),
        isEmpty,
      );
      // Even if the server ever handed back a seat id larger than the row's.
      expect(
        peersToOfferTo(<CallParticipant>[_p(1, 'me', mine: true)], 5),
        isEmpty,
      );
    });
  });

  group('لمن هذه الإشارة', () {
    test('one addressed to me is mine', () {
      expect(signalIsForMe(_s(from: 'a', to: 'me'), 'me'), isTrue);
    });

    // ⚠ THE STAGE-2 FAILURE. With two people every signal on a call belongs to
    //   the other one; with four, C reading the offer A sent to B sets it as
    //   ITS remote description and the whole call collapses.
    test('⚠ one addressed to somebody else is NOT', () {
      expect(signalIsForMe(_s(from: 'a', to: 'b'), 'me'), isFalse);
    });

    // ⚠ THE STAGE-1 FAILURE, and it survives into stage 2. Both sides read the
    //   SAME rows — the policy is «may you see this call», not «is it addressed
    //   to you».
    test('⚠ and my own is never mine to apply', () {
      expect(signalIsForMe(_s(from: 'me', to: 'a', mine: true), 'me'), isFalse);
      // Even a broadcast of my own.
      expect(signalIsForMe(_s(from: 'me', mine: true), 'me'), isFalse);
    });

    // Every stage-1 row carries no recipient, and every stage-1 client still
    // sends none — so a broadcast has to keep working after the column exists.
    test('a broadcast from somebody else is mine', () {
      expect(signalIsForMe(_s(from: 'a'), 'me'), isTrue);
    });
  });
}
