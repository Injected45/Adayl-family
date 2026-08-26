import 'dart:io';

import 'package:family_app/core/realtime/doorbell.dart';
import 'package:family_app/features/call/data/call_repository.dart';
import 'package:family_app/features/call/data/call_session.dart';
import 'package:family_app/features/call/domain/models.dart';
import 'package:family_app/features/call/presentation/call_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// من أغلق، أغلق للجميع — والجانب الذي كان يؤخّرها.
///
/// The RULE was already right on both sides. `leave_call` ends a «جارية» call
/// the moment fewer than two live seats remain (PATCH_20260822f), and
/// `CallSession._tick` closes this handset on the same count. And the
/// association still reported it: «عند اغلاق الاتصال يبقي الاتصال مفتوح عند
/// الطرف الاخر الى ان يقفله بنفسه».
///
/// The gap was the ORDER inside close(). It tore down the media FIRST —
/// track.stop(), MediaStream.dispose(), one RTCPeerConnection.close() per peer,
/// all native calls across a platform channel against a live DTLS/ICE session —
/// and only then told the server. So the request that ends the call for the
/// OTHER man waited behind this handset tidying up after itself, and the other
/// side's «fewer than two seats» rule could not fire until it had finished.
///
/// ⚠ AND THE OLD ORDER CARRIED A COMMENT DEFENDING ITSELF, which is why it
///   survived every rewrite around it: «the media goes before the server is
///   told, so a leave that failed still stops the microphone». That is true and
///   is kept — the request is FIRED first and AWAITED last, so the microphone
///   still stops whatever the network does. The two were never in conflict; one
///   sentence made them look as though they were.
class _FakeRepo implements CallRepository {
  final List<String> log = <String>[];
  bool failLeave = false;

  @override
  Future<void> leave(int callId) async {
    log.add('leave');
    if (failLeave) throw StateError('no network');
  }

  @override
  Future<void> end(int callId, {bool declined = false}) async {
    log.add('end');
    if (failLeave) throw StateError('no network');
  }

  @override
  Future<void> heartbeat(int callId) async => log.add('heartbeat');

  @override
  Future<List<CallParticipant>> participants(int callId) async =>
      <CallParticipant>[];

  @override
  Future<List<Map<String, dynamic>>> iceServers() async =>
      <Map<String, dynamic>>[];

  @override
  Future<List<CallSignal>> signalsAfter(int callId, int afterId) async =>
      <CallSignal>[];

  @override
  Future<int> join(int callId) async => 1;

  @override
  Future<void> signal(
    int callId,
    String kind,
    Map<String, dynamic> payload, {
    String? to,
  }) async => log.add('signal');

  /// The call as the SERVER sees it. Null keeps the session alive — see the
  /// note on byId: a missing row is a failed read, never an ending.
  CallView? live;

  @override
  Future<CallView?> byId(int callId) async => live;

  @override
  Future<CallView?> liveIn(int? threadAdeelId) async => null;

  @override
  Future<CallView?> liveAny() async => null;

  @override
  Future<int> start({int? threadAdeelId, int? peerAdeelId}) async => 1;

  @override
  Future<List<CallPeer>> directory() async => <CallPeer>[];
}

void main() {
  _sheetTests();
  _noticingTests();
  _bothSidesCloseTests();
  _ringTimeoutTests();

  test('hanging up tells the server BEFORE tearing the media down', () {
    // WHY THE SOURCE AND NOT THE BEHAVIOUR: the slow part is native —
    // track.stop(), dispose() and RTCPeerConnection.close(). In a test binding
    // there is no microphone and no peer connection, so those lines cost
    // nothing and NO runtime assertion can tell the two orders apart: a
    // behavioural test passes on the broken code exactly as on the fixed one.
    //
    // The decision is what is worth pinning, so it is pinned the way this repo
    // pins its other invisible decisions — read the file, fail with the line.
    final String src = File(
      'lib/features/call/data/call_session.dart',
    ).readAsStringSync();

    final int body = src.indexOf('Future<void> close({bool declined = false})');
    expect(body, greaterThan(-1), reason: 'close() not found');

    final String close = src.substring(body);
    final int told = close.indexOf('_repo.leave(callId)');
    final int stop = close.indexOf('t.stop()');
    final int shut = close.indexOf('pc.close()');

    expect(told, greaterThan(-1), reason: 'close() no longer leaves the call');
    expect(stop, greaterThan(-1), reason: 'close() no longer stops the mic');
    expect(shut, greaterThan(-1), reason: 'close() no longer closes the peers');

    expect(
      told,
      lessThan(stop),
      reason:
          'the leave request must be issued before the microphone teardown. It '
          'is what ends the call for the other man, and the teardown is native '
          'and slow. Fire it first, await it last.',
    );
    expect(
      told,
      lessThan(shut),
      reason:
          'the leave request must be issued before the peer connections are '
          'closed, for the same reason.',
    );

    // And the microphone half of the old rule is still honoured: the request is
    // awaited AFTER the teardown, never instead of it.
    expect(
      close.indexOf('await told'),
      greaterThan(shut),
      reason:
          'a leave that fails must still have stopped the microphone. The '
          'future is awaited after the teardown, never before it.',
    );
  });

  test('and it still leaves, and close() cannot run twice', () async {
    final _FakeRepo repo = _FakeRepo();
    final CallSession s = CallSession(repository: repo, callId: 7);

    await s.close();
    expect(repo.log, contains('leave'), reason: 'the server must be told');
    expect(s.phase.value, CallPhase.ended);

    // The sheet's red button and the «fewer than two seats» rule in _tick can
    // both reach here, and on the man who hung up they very nearly do at once.
    await s.close();
    expect(
      repo.log.where((String e) => e == 'leave').length,
      1,
      reason: 'close() must be idempotent',
    );
  });

  test('a leave that throws does not escape close()', () async {
    // The future is created before the teardown and awaited after it, so its
    // error is raised at a point where nothing else is holding it. Without the
    // catchError attached AT CREATION, that is an unhandled async error — on a
    // handset, a crash while hanging up a call.
    final _FakeRepo repo = _FakeRepo()..failLeave = true;
    final CallSession s = CallSession(repository: repo, callId: 7);

    await expectLater(s.close(), completes);
    expect(s.phase.value, CallPhase.ended);
  });

  test('declining ends the call rather than leaving it', () async {
    final _FakeRepo repo = _FakeRepo();
    final CallSession s = CallSession(repository: repo, callId: 7);

    await s.close(declined: true);
    expect(repo.log, contains('end'));
    expect(repo.log, isNot(contains('leave')));
  });

  // الجرس: تعجيلٌ لا اعتماد.
  //
  // The session must build and close with a doorbell that cannot connect. That
  // is the rule doorbell.dart states and doorbell_test pins for every other
  // entry point: the ring is latency and nothing else, so a handset with no
  // websocket must behave exactly as before, on the poll. A doorbell that threw
  // here would take down hanging up, which is the one moment a call must never
  // fail.
  test('closing rings the bell, and a dead bell changes nothing', () async {
    final Doorbell bell = Doorbell(() => throw StateError('no supabase'));
    final _FakeRepo repo = _FakeRepo();
    final CallSession s = CallSession(
      repository: repo,
      callId: 7,
      doorbell: bell,
    );

    await expectLater(s.close(), completes);
    expect(repo.log, contains('leave'));
  });

  test('and the bell stays optional, so every other caller is unaffected', () {
    final String src = File(
      'lib/features/call/data/call_session.dart',
    ).readAsStringSync();
    expect(
      src,
      contains('Doorbell? doorbell'),
      reason:
          'the doorbell must stay a nullable parameter. Constructing one is not '
          'allowed to need a configured Supabase, and every other call test '
          'builds a session without it.',
    );
  });
}

/// ── والشاشة: النصف الذي لم يكن أحدٌ يفحصه ──────────────────────────────────
///
/// The rule was enforced on the server AND in the session, and the association
/// still saw the call «مفتوح عند الطرف الاخر الى ان يقفله بنفسه» — because the
/// SHEET never closed itself. Microphone off, call over, screen still there.
///
/// An old comment defended that: a screen that vanishes on its own leaves a man
/// unsure whether he hung up, was hung up on, or lost signal. The concern is
/// kept — «انتهت المكالمة» is shown for a beat first — but the conclusion was
/// overruled by the people using it.
void _sheetTests() {
  test('the sheet closes itself when the call has ENDED', () {
    expect(sheetDismissesItself(CallPhase.ended), isTrue);
  });

  test('and never on anything else', () {
    // ⚠ EACH OF THESE WANTS A DECISION FROM HIM, or is a call still in
    //   progress. A screen that closed itself on «تعذّر الاتصال» would take
    //   away the only thing telling him to check his signal; on «لا يمكن
    //   الاتصال بدون إذن الميكروفون» it would take away the one message that
    //   is fixable, and only in Android settings.
    for (final CallPhase p in <CallPhase>[
      CallPhase.connecting,
      CallPhase.ringing,
      CallPhase.talking,
      CallPhase.failed,
      CallPhase.micDenied,
    ]) {
      expect(
        sheetDismissesItself(p),
        isFalse,
        reason: 'the sheet must stay open on $p',
      );
    }
  });

  test('and every phase is accounted for, so a new one is a decision', () {
    // A phase added later falls to `false` by default, which is the safe side
    // — but silently. This fails instead, so the next person has to choose.
    expect(
      CallPhase.values.length,
      6,
      reason:
          'a new CallPhase was added. Decide whether the call sheet closes '
          'itself on it, then update sheetDismissesItself and this count.',
    );
  });

  test('the red button tells the server before the sheet animates away', () {
    // _open awaits showModalBottomSheet, and that future does not complete
    // until the dismiss ANIMATION has finished — so a red button that only
    // popped left leave_call unsent for the length of the animation, on top of
    // the media teardown behind it.
    final String src = File(
      'lib/features/call/presentation/call_ui.dart',
    ).readAsStringSync();

    final int red = src.indexOf('icon: Icons.call_end,');
    expect(red, greaterThan(-1), reason: 'the hang-up button is gone');

    final String button = src.substring(red, red + 1800);
    final int closed = button.indexOf('widget.session.close()');
    final int popped = button.indexOf('Navigator.of(context).pop()');

    expect(
      closed,
      greaterThan(-1),
      reason: 'the red button must close the session',
    );
    expect(
      popped,
      greaterThan(-1),
      reason: 'the red button must dismiss the sheet',
    );
    expect(
      closed,
      lessThan(popped),
      reason:
          'close() must be called before pop(), so leave_call is on its way '
          'before the dismiss animation begins.',
    );
  });
}

/// وسرعةُ ملاحظةِ الإغلاق عند الطرف الآخر.
///
/// The RULE ends the call; these two decide how fast the other handset FINDS
/// OUT. Both are invisible at runtime — one lives in a WebRTC callback with no
/// peer connection in a test binding, the other is the shape of two awaits —
/// so both are pinned by reading the file, as this repo pins its other
/// invisible decisions.
void _noticingTests() {
  test('a dropped peer ends the call at once, with no round trip', () {
    final String src = File(
      'lib/features/call/data/call_session.dart',
    ).readAsStringSync();

    final int at = src.indexOf('pc.onConnectionState');
    expect(at, greaterThan(-1), reason: 'the connection-state handler is gone');
    final String handler = src.substring(at, at + 2400);

    // ⚠ THE HANDLER RECORDS AND EVALUATES; it does not list the dead states.
    //   Which states count as ALIVE is _livePeers()' job — one place, so a
    //   fourth state added by the platform cannot be handled in one of them
    //   and forgotten in the other.
    expect(
      handler,
      contains('_peerState[user] = s'),
      reason:
          'WebRTC knows the other man hung up within milliseconds, and '
          'nothing can act on it unless the state is recorded.',
    );

    // ── ⚠ THIS ASSERTION WAS THE OPPOSITE ONE, AND WAS FLIPPED ON PURPOSE ──
    //
    //   It used to require that the handler only ran a BEAT and never closed,
    //   on the reasoning that «disconnected» is also what a mobile handover
    //   produces — so closing here would end a live call every time somebody
    //   walked past a lift, and the server's seat count should decide.
    //
    //   The association weighed that and chose otherwise: «المهم لحظة القفل
    //   يغلق أياً كان السبب ويقفل بسرعة». Asking first costs a round trip on
    //   every hang-up, and hanging up is the common case; a blip that ends a
    //   call is answered by ringing again. The cost is real and is written
    //   down rather than forgotten.
    expect(
      handler,
      contains('close()'),
      reason:
          'the call must END on a dropped peer, not merely ask the server — '
          'asking costs a round trip on every hang-up.',
    );
    expect(
      handler,
      contains('_livePeers() == 0'),
      reason:
          'and it must be «no peer left alive», never «this peer dropped» — '
          'المجلس is a room, and four men must keep talking when one leaves.',
    );
    expect(
      handler,
      contains('_hadCompany'),
      reason:
          'a ringing caller holds a peer connection connected to nobody yet',
    );
  });

  test('and a peer still connecting counts as alive', () {
    // A peer renegotiating is not a peer that hung up. Treating it as one
    // would end the call in the middle of the handshake about to carry it.
    final String src = File(
      'lib/features/call/data/call_session.dart',
    ).readAsStringSync();
    final int at = src.indexOf('int _livePeers()');
    expect(at, greaterThan(-1), reason: '_livePeers is gone');
    final String fn = src.substring(at, at + 700);
    for (final String alive in <String>[
      'RTCPeerConnectionStateNew',
      'RTCPeerConnectionStateConnecting',
      'RTCPeerConnectionStateConnected',
    ]) {
      expect(fn, contains(alive), reason: '$alive must count as alive');
    }
  });

  test('and one beat costs one round trip, not two', () {
    final String src = File(
      'lib/features/call/data/call_session.dart',
    ).readAsStringSync();

    final int at = src.indexOf('Future<void> _tick()');
    expect(at, greaterThan(-1));
    final String tick = src.substring(at, at + 2200);

    expect(
      tick,
      contains('Future.wait'),
      reason:
          'the heartbeat and the participant read depend on nothing in each '
          'other. Sequential awaits made every beat cost two round trips '
          'before it could see the other man had gone.',
    );
    expect(
      tick,
      isNot(contains('await _repo.heartbeat(callId);')),
      reason: 'the sequential heartbeat is what the wait replaced',
    );
  });
}

/// من أغلق، أغلق عند الطرفين — حتى لو لم تتّصل المكالمة أصلاً.
///
/// ⚠ THE OLD RULE COULD NOT COVER THE COMMON CASE. CallSession closed itself
///   when fewer than two LIVE SEATS remained — and only after company had
///   arrived, because a ringing caller is alone by definition. A call that
///   never connected has ONE seat from first ring to last, so the rule never
///   fired and the other man sat on «جارية» until he pressed red himself.
///
///   The association's own log: every call that day carried one seat, one rang
///   for 469 seconds, and «انتهت بعد» was recorded for the presser alone.
///
/// ⚠ SO THE SESSION NOW ASKS THE SERVER WHAT THE CALL IS, not only who is in
///   it. «انتهت», «مرفوضة» and «فائتة» all come from v_calls — the same fact
///   both handsets read, so they cannot disagree about when a call is over.
void _bothSidesCloseTests() {
  CallView view(String status) => CallView.fromJson(<String, dynamic>{
    'id': 7,
    'threadAdeelId': null,
    'callerName': 'هيثم',
    'mine': false,
    'status': status,
    'startedAt': '2026-08-26T10:00:00Z',
    'answeredAt': null,
    'endedAt': null,
  });

  test('⚠ the other side closes when the server says the call ended', () async {
    for (final String over in <String>['انتهت', 'مرفوضة', 'فائتة']) {
      final _FakeRepo repo = _FakeRepo()..live = view(over);
      final CallSession s = CallSession(repository: repo, callId: 7);

      await s.tickForTest();

      expect(
        s.phase.value,
        CallPhase.ended,
        reason:
            'a call the server calls «$over» must not leave a live microphone '
            'and a screen saying «جارية»',
      );
    }
  });

  test('and a RINGING or LIVE call is left alone', () async {
    for (final String on in <String>['ترن', 'جارية']) {
      final _FakeRepo repo = _FakeRepo()..live = view(on);
      final CallSession s = CallSession(repository: repo, callId: 7);

      await s.tickForTest();

      expect(
        s.phase.value,
        isNot(CallPhase.ended),
        reason: 'closing on «$on» would hang up on every call as it is placed',
      );
    }
  });

  test('⚠ and a call the server does not return is NOT an ending', () async {
    // RLS, a dropped request or a slow view all return null. Hanging up on
    // that would end a live conversation over one bad packet — and on a Libyan
    // mobile connection that packet arrives regularly.
    final _FakeRepo repo = _FakeRepo()..live = null;
    final CallSession s = CallSession(repository: repo, callId: 7);

    await s.tickForTest();

    expect(s.phase.value, isNot(CallPhase.ended));
  });
}

/// الرنينُ لا يدوم إلى ما لا نهاية.
///
/// ⚠ THE SERVER ALREADY EXPIRES A RING AT SIXTY SECONDS — v_calls turns it
///   into «فائتة» and _tick closes on that. But that closure needs an ANSWER
///   FROM THE SERVER, and the one situation where a phone rings for ever is
///   the one where the server cannot be reached: every read returns null, null
///   is deliberately not an ending, and the caller rings until he gives up by
///   hand. The association watched exactly that: «بقي الرنين مستمر لفترة طويلة
///   الى ان فصلته انا».
void _ringTimeoutTests() {
  test('⚠ a ring nobody answered ends itself, with no server at all', () {
    // The reads are pinned in the source rather than driven, because reaching
    // sixty-five seconds in a widget test means a fake clock this session does
    // not own — and the DECISION is what matters: the cap is checked before
    // the seat count, so a call nobody answered ends even when the participant
    // read is the thing failing.
    final String src = File(
      'lib/features/call/data/call_session.dart',
    ).readAsStringSync();

    final int at = src.indexOf('_ringingSince != null');
    expect(at, greaterThan(-1), reason: 'the ring has no cap at all');

    final int seats = src.indexOf('if (now.length >= 2)');
    expect(
      at,
      lessThan(seats),
      reason:
          'the cap must be checked BEFORE the seat count — otherwise a failing '
          'participant read is exactly what keeps the ring alive',
    );

    final String block = src.substring(at, (at + 400).clamp(0, src.length));
    expect(block, contains('CallPhase.ringing'));
    expect(
      block,
      contains('close()'),
      reason: 'it must END the call, not merely report it',
    );
  });

  test('and the cap sits ABOVE the server expiry, never below it', () {
    // ⚠ SIXTY-FIVE, NOT SIXTY. The server's expiry must normally win, because
    //   it is the fact both handsets read; the margin is what keeps this a
    //   fallback rather than a second authority racing the first.
    expect(
      CallSession.ringTimeout.inSeconds,
      greaterThan(60),
      reason: 'below 60 this would beat the server and become the authority',
    );
    expect(
      CallSession.ringTimeout.inSeconds,
      lessThanOrEqualTo(90),
      reason: 'a ring a man has walked away from is not worth a third minute',
    );
  });

  test('⚠ and answering clears the cap, so a long call is never cut', () {
    final String src = File(
      'lib/features/call/data/call_session.dart',
    ).readAsStringSync();
    final int at = src.indexOf('if (now.length >= 2) {');
    expect(at, greaterThan(-1));
    expect(
      src.substring(at, (at + 300).clamp(0, src.length)),
      contains('_ringingSince = null'),
      reason:
          'a man talking in المجلس is «جارية» however long he talks — only a '
          'call nobody has joined is capped',
    );
  });
}
