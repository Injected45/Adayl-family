import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/domain/wire_values.dart';
import '../../../core/realtime/doorbell.dart';
import '../domain/models.dart';
import 'call_repository.dart';

/// أطوار المكالمة كما تراها الشاشة.
///
/// ⚠ micDenied IS SEPARATE FROM failed, and the distinction is the whole value
///   of it. «تعذّر الاتصال» sends a man to check his signal; «لا يمكن الاتصال
///   بدون إذن الميكروفون» sends him to Android settings, which is the only place
///   that one is fixable. One word for both would make the commonest first-time
///   failure look like a network fault.
enum CallPhase { connecting, ringing, talking, ended, failed, micDenied }

/// من أعرض عليه؟
///
/// ⚠ ARITHMETIC, NOT NEGOTIATION, and this one function is the whole of it.
///   The man who joined LATER — the larger participant id — offers to every
///   seat that was taken before his. Both sides compute the same answer from
///   the same two numbers, so there is no round of «you go first» to lose on a
///   bad connection, and no glare: two peers can never both offer, because one
///   id is always the larger.
///
/// ⚠ AND IT MUST NEVER RETURN MY OWN SEAT. A handset that offered to itself
///   would set its own SDP as its own remote description — which fails in a
///   way that looks exactly like the other side never answering.
///
/// Extracted from the session because it is the piece worth a test: the rest
/// of a call needs a microphone, a peer connection and another phone.
List<CallParticipant> peersToOfferTo(
  List<CallParticipant> everyone,
  int mySeat,
) => everyone.where((CallParticipant p) => !p.mine && p.id < mySeat).toList();

/// هل هذه الإشارة لي؟
///
/// Two refusals, and they are different failures:
///
/// ⚠ MINE — both sides read the SAME rows, because the policy is «may you see
///   this call», not «is it addressed to you». Without this a handset feeds
///   its own offer back into its own peer connection.
///
/// ⚠ ADDRESSED TO SOMEBODY ELSE — with two people every signal belongs to the
///   other one, so stage 1 needed no such test. With four, an offer from A to
///   B is read by C and D as well, each sets it as ITS remote description, and
///   the call collapses in a way that looks like a bad network.
///
/// An empty [CallSignal.toUserId] is a broadcast, which every stage-1 row is.
bool signalIsForMe(CallSignal s, String myUserId) {
  if (s.mine) return false;
  if (s.toUserId.isEmpty) return true;
  return s.toUserId == myUserId;
}

/// الجلسة: شبكة متداخلة تربط WebRTC بجدول الإشارة.
///
/// ── لماذا شبكة متداخلة ولا خادم وسائط ──────────────────────────────────────
/// A mesh means every phone sends its own audio to every other one. The
/// arithmetic is what decides whether that is viable, and for VOICE it is:
///
///     Opus ≈ 32 kbps per stream
///     5 in a call → 4 up + 4 down = 128 kbps up
///
/// Video would be roughly twenty times those numbers, which is where «a group
/// call needs an SFU» comes from — and the association asked for صوتي. The cap
/// lives in `association_settings.call_max_participants`, so tuning it is one
/// UPDATE rather than a release.
///
/// ── لماذا الإشارة عبر جدول ─────────────────────────────────────────────────
/// Supabase Realtime is the reflex and it excludes exactly the people this is
/// for. `my_adeel_id()` reads the **`x-device-id` request header** and a
/// websocket carries no headers, so a subscription evaluated for a portal
/// member matches no policy and delivers him nothing — staff would call each
/// other perfectly while no عديل could be reached, and it would look flawless to
/// anyone testing with a staff account.
///
/// ⚠ AND WHO OFFERS WHOM IS ARITHMETIC, NOT NEGOTIATION. The man with the LARGER
///   participant id — the one who joined later — offers to everyone already in.
///   Both sides compute the same answer from the same two numbers, so there is
///   no round of «you go first» to lose, and no glare: two peers can never both
///   offer, because one id is always the larger.
class CallSession {
  /// ⚠ THE DOORBELL IS OPTIONAL AND MUST STAY OPTIONAL. It is an
  ///   already-constructed object here, never built from this class — the rule
  ///   in doorbell.dart is that constructing one must never need a configured
  ///   Supabase, and every test that drives a call builds a session without
  ///   one. What it buys is latency and nothing else: with it the other man
  ///   learns of a hang-up in about a tenth of a second, without it in one
  ///   beat of [steady]. Never a dependency, never awaited, never retried.
  CallSession({
    required CallRepository repository,
    required this.callId,
    Doorbell? doorbell,
  }) : _repo = repository,
       _bell = doorbell;

  final CallRepository _repo;
  final Doorbell? _bell;
  final int callId;

  final ValueNotifier<CallPhase> phase = ValueNotifier<CallPhase>(
    CallPhase.connecting,
  );
  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);

  /// Who is on the line, for the screen to name.
  final ValueNotifier<List<CallParticipant>> people =
      ValueNotifier<List<CallParticipant>>(<CallParticipant>[]);

  /// النبض المعتاد: أنا هنا، ومن معي، وماذا قالوا.
  static const Duration steady = Duration(seconds: 1);

  /// ⚠ 300 ms WHILE THE CALL IS BEING SET UP, AND ONLY UNTIL IT IS. Each leg of
  ///   the handshake waits a whole poll, and there are three or four legs — so
  ///   the interval IS the connect time. Once audio is flowing nothing is
  ///   blocking on a signal, and the fast clock stops on its own.
  static const Duration setup = Duration(milliseconds: 300);

  MediaStream? _local;
  List<Map<String, dynamic>> _ice = <Map<String, dynamic>>[];
  Timer? _poll;

  /// The fast clock, alive only while connecting. See [setup].
  Timer? _handshake;

  /// كيف نتوقّف عن سماع الجرس. Null while nothing is subscribed.
  VoidCallback? _deafen;

  /// ⚠ ONE DRAIN AT A TIME. At 300 ms a slow request would let a second drain
  ///   start before the first finished, and both would read the same rows and
  ///   set the same remote description twice — which fails in a way that looks
  ///   exactly like the other side never answering.
  bool _draining = false;
  int _seen = 0;
  int _myId = 0;
  String _me = '';
  bool _closed = false;

  /// ── ⚠ الرنينُ لا يدوم — حزامٌ محلّيٌّ لا يعتمد على الشبكة ────────────────
  ///
  ///   v_calls already turns a «ترن» older than sixty seconds into «فائتة»,
  ///   and _tick closes on that. But it closes on an ANSWER FROM THE SERVER,
  ///   and the one situation where a phone rings for ever is the one where the
  ///   server cannot be reached: every byId returns null, null is deliberately
  ///   not an ending, and the caller rings until he gives up by hand. The
  ///   association watched exactly that — «بقي الرنين مستمر لفترة طويلة الى ان
  ///   فصلته انا».
  ///
  /// ⚠ SIXTY-FIVE, NOT SIXTY. The server's expiry must normally win, because
  ///   it is the fact both handsets read; five seconds of margin keeps this a
  ///   FALLBACK rather than a second authority racing the first.
  ///
  /// ⚠ AND IT MEASURES «RINGING», NOT «ON A CALL». A man in المجلس is
  ///   «جارية» however long he talks; only a call nobody has joined is capped.
  static const Duration ringTimeout = Duration(seconds: 65);

  /// متى بدأ الرنين. Null once anybody has joined.
  DateTime? _ringingSince;

  /// ⚠ WHETHER ANYBODY EVER JOINED. Without it the «fewer than two seats»
  ///   rule would fire on the ringing caller, who is alone by definition.
  bool _hadCompany = false;

  /// One peer connection per other participant, keyed by his user id.
  final Map<String, RTCPeerConnection> _peers = <String, RTCPeerConnection>{};

  /// آخرُ حالٍ وصلنا عن كلّ ندّ — من onConnectionState.
  ///
  /// ⚠ THE CALL ENDS OFF THIS MAP AND NOT OFF A COUNT OF SEATS, because the
  ///   association asked for «لحظة القفل يغلق أياً كان السبب ويقفل بسرعة».
  ///   The server's seat count is a round trip away; this is local and arrives
  ///   in milliseconds.
  final Map<String, RTCPeerConnectionState> _peerState =
      <String, RTCPeerConnectionState>{};

  /// Whether that peer's remote description has been set yet.
  final Map<String, bool> _remoteSet = <String, bool>{};

  /// ⚠ CANDIDATES THAT ARRIVE BEFORE THE DESCRIPTION THEY BELONG TO.
  ///
  ///   ICE trickles: a peer starts posting candidates the instant it has any,
  ///   which is often before its offer has been read here. Handing one to a
  ///   connection with no remote description throws, and the symptom is a call
  ///   that works on wifi — where the first candidate is already the right one
  ///   — and fails on mobile data, where it is not.
  final Map<String, List<RTCIceCandidate>> _pending =
      <String, List<RTCIceCandidate>>{};

  Future<void> open() async {
    try {
      _ice = await _repo.iceServers();

      // ⚠ THE MICROPHONE IS ASKED FOR HERE, by getUserMedia itself, at the
      //   moment the handset was pressed. A refusal is caught on its own
      //   because it needs a different answer on screen from a failed
      //   connection — and only one of the two is fixable by trying again.
      try {
        _local = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
          'audio': true,
          'video': false,
        });
      } on Object catch (e) {
        debugPrint('call microphone: $e');
        phase.value = CallPhase.micDenied;
        return;
      }

      _myId = await _repo.join(callId);
      phase.value = CallPhase.ringing;
      _ringingSince = DateTime.now();

      _poll = Timer.periodic(steady, (_) => unawaited(_tick()));

      // ── والجرس، لأنّ «من أغلق أغلق للجميع» يجب أن تُسمع فوراً ─────────────
      // ⚠ THE RULE WAS ALREADY RIGHT AND THE OTHER MAN STILL WAITED. The
      //   server ends a «جارية» call the moment fewer than two live seats
      //   remain, and _tick closes this side on the same count — but only on
      //   the NEXT beat, and a beat is a second plus a Libyan round trip.
      //   «يبقي الاتصال مفتوح عند الطرف الاخر» is that gap, and the doorbell
      //   is already open on this handset for exactly this kind of news.
      //
      // ⚠ IT CARRIES NOTHING AND DECIDES NOTHING. The ring is the word «a
      //   call changed»; what follows is the same authenticated read that
      //   would have run a second later anyway, so RLS settles everything as
      //   before. Worst case the ring never arrives and the poll does the job
      //   it has always done — which is why nothing here retries or reports.
      _deafen = _bell?.listen((Ring r) {
        if (r == Ring.call) unawaited(_tick());
      });

      // ── والمصافحة على ساعةٍ أسرع ────────────────────────────────────────
      // ⚠ CONNECTING A CALL WAS SLOW FOR A REASON THAT HAD NOTHING TO DO WITH
      //   THE NETWORK. A WebRTC handshake is a conversation: B offers, A reads
      //   it and answers, B reads the answer, and ICE candidates trickle both
      //   ways after that. EVERY ONE of those hops waited for the next poll —
      //   so at one second the floor on «hello» was three to five seconds of
      //   pure waiting, and it looked exactly like a bad connection.
      //
      // ⚠ AND IT DRAINS SIGNALS ONLY. The heartbeat has twenty seconds to be
      //   heard and the participant list barely moves, so putting all three on
      //   a 300 ms clock would have tripled the traffic to speed up one of
      //   them. This asks the one question that is actually blocking.
      _handshake = Timer.periodic(setup, (_) => unawaited(_drainOnly()));
      unawaited(_tick());
    } on Object catch (e) {
      debugPrint('call open: $e');
      phase.value = CallPhase.failed;
    }
  }

  /// One beat: say I am here, see who else is, then read what they said.
  ///
  /// ⚠ THE POLL RUNS FOR THE WHOLE CALL HERE, unlike the two-person version
  ///   which stopped once the media was up. It has to: somebody joining ten
  ///   minutes in is a new peer to offer to, and a heartbeat that stopped would
  ///   drop this handset out of everyone else's list after twenty seconds.
  ///   It is three small requests a second against a call, which is nothing
  ///   beside the audio it is carrying.
  /// نبضةٌ واحدة، للاختبار.
  ///
  /// ⚠ @visibleForTesting RATHER THAN PRIVATE, for the same reason
  ///   ChatChime.play() is: driving the real beat needs a live call, a
  ///   microphone and a platform channel no test binding provides — and the
  ///   DECISION this beat makes (close, or stay) is the one that left two
  ///   handsets on a dead call. It is pinned rather than trusted.
  @visibleForTesting
  Future<void> tickForTest() => _tick();

  Future<void> _tick() async {
    if (_closed) return;
    try {
      // ── ⚠ معاً، لا واحدةً بعد الأخرى ──────────────────────────────────
      //
      //   These were two sequential awaits, so every beat cost TWO round trips
      //   before it could see that the other man had gone — and on a Libyan
      //   mobile connection a round trip is not free. They depend on nothing
      //   in each other: one says «I am still here», the other asks «who else
      //   is». Run together, the beat costs one round trip instead of two, and
      //   the end of a call is noticed in half the time.
      //
      // ⚠ Future.wait STILL FAILS THE WHOLE BEAT IF EITHER THROWS, which is
      //   what the sequential version did and what the catch below expects: a
      //   missed beat is a missed beat, and tearing down a live call because
      //   one request timed out would be far worse.
      final List<Object?> three = await Future.wait(<Future<Object?>>[
        _repo.heartbeat(callId),
        _repo.participants(callId),
        _repo.byId(callId),
      ]);
      final List<CallParticipant> now = three[1]! as List<CallParticipant>;
      final CallView? call = three[2] as CallView?;

      // ── ⚠ هل انتهت المكالمة أصلاً؟ ─────────────────────────────────────
      //
      //   THE SEAT COUNT BELOW CANNOT ANSWER THIS, and that is why two
      //   handsets sat on a dead call. «Fewer than two live seats» only fires
      //   after company has ARRIVED — a ringing caller is alone by definition
      //   — so a call that never connected has one seat from first ring to
      //   last and the rule never bites. Pressing red ended it for the presser
      //   and left the other man «شبه متصل» until he pressed too.
      //
      //   The association's log said it plainly: every call that day carried
      //   ONE seat, and one of them rang for 469 seconds.
      //
      // ⚠ AND THE SERVER IS THE AUTHORITY HERE. «انتهت», «مرفوضة» and
      //   «فائتة» are all decided by v_calls — including the sixty-second
      //   expiry of a ring and the twenty-second expiry of a silent seat — so
      //   this closes on the same fact both sides read, and they cannot
      //   disagree about when a call is over.
      //
      // ⚠ A MISSING ROW IS NOT AN ENDING. RLS, a dropped request or a slow
      //   view all return null, and hanging up on that would end a live call
      //   over one bad packet. Only a call the server RETURNS and marks
      //   finished counts.
      if (call != null &&
          call.status != CallStatusWire.ringing &&
          call.status != CallStatusWire.active) {
        await close();
        return;
      }
      people.value = now;
      for (final CallParticipant p in now) {
        if (p.mine) {
          _me = p.userId;
          break;
        }
      }

      // ── وهل بقي أحد؟ ────────────────────────────────────────────────────
      // ⚠ NOTHING HERE EVER ASKED WHETHER THE CALL HAD ENDED, and that is the
      //   other half of «تضل المكالمه مستمرة ولا تنتهي بسرعه». `phase` was set
      //   to ended in exactly one place — close() — which is the man who hangs
      //   up. For the OTHER side the peer connection simply died and the sheet
      //   went on saying «جارية» with a live microphone under it, until he
      //   pressed red himself. From his seat that reads as a call that will not
      //   end.
      //
      // ⚠ IT IS THE SAME COUNT THE SERVER USES — fewer than two live seats is
      //   not a call — so the two cannot disagree about when a call is over.
      //   And it needs no extra request: the participant list is already read
      //   on every beat for the mesh.
      //
      // ⚠ AND ONLY AFTER COMPANY HAS ACTUALLY ARRIVED. While a call is ringing
      //   the caller holds the only seat, which is the normal state and not an
      //   ended call — closing on it would hang up on every call the instant it
      //   was placed.
      // ── الرنينُ له سقف ────────────────────────────────────────────────
      // ⚠ CHECKED BEFORE THE SEAT COUNT, so a call nobody answered ends even
      //   when the participant read is what is failing.
      if (_ringingSince != null &&
          phase.value == CallPhase.ringing &&
          DateTime.now().difference(_ringingSince!) > ringTimeout) {
        await close();
        return;
      }
      if (now.length >= 2) {
        _hadCompany = true;
        // Company has arrived: this is a conversation now, not a ring.
        _ringingSince = null;
      }
      if (_hadCompany && now.length < 2) {
        // close() stops the microphone, tears down the peers, sets the phase
        // and is guarded against running twice. The sheet stays open showing
        // «انتهت» on purpose — see _CallSheet: a screen that vanished on its
        // own would leave him unsure whether he hung up, was hung up on, or
        // lost signal.
        await close();
        return;
      }

      // ── Offer to everyone who was here before me ────────────────────────
      for (final CallParticipant p in peersToOfferTo(now, _myId)) {
        if (_peers.containsKey(p.userId)) continue;
        await _offerTo(p.userId);
      }

      // ── And drop anyone who has gone ────────────────────────────────────
      final Set<String> live = now.map((CallParticipant p) => p.userId).toSet();
      for (final String gone in _peers.keys.toList()) {
        if (live.contains(gone)) continue;
        await _peers.remove(gone)?.close();
        _peerState.remove(gone);
        _remoteSet.remove(gone);
        _pending.remove(gone);
      }

      await _drain();
    } on Object catch (e) {
      // A failed beat is a beat. The call is up or it is not, and the peer
      // states will say so; tearing a live call down because one request timed
      // out on a Libyan mobile connection would be far worse.
      debugPrint('call tick: $e');
    }
  }

  /// كم نِدّاً ما زال الصوتُ يمرّ إليه، أو في طريقه.
  ///
  /// ⚠ «connecting» AND «new» COUNT AS ALIVE. A peer renegotiating is not a
  ///   peer that hung up, and treating it as one would end a call in the
  ///   middle of the handshake that was about to carry it.
  int _livePeers() => _peers.keys
      .where(
        (String u) =>
            _peerState[u] == null ||
            _peerState[u] == RTCPeerConnectionState.RTCPeerConnectionStateNew ||
            _peerState[u] ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnecting ||
            _peerState[u] ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      )
      .length;

  Future<RTCPeerConnection> _peerFor(String user) async {
    final RTCPeerConnection? existing = _peers[user];
    if (existing != null) return existing;

    final RTCPeerConnection pc = await createPeerConnection(<String, dynamic>{
      'iceServers': _ice,
      'sdpSemantics': 'unified-plan',
    });

    for (final MediaStreamTrack t in _local?.getTracks() ?? const []) {
      await pc.addTrack(t, _local!);
    }

    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate == null) return;
      unawaited(
        _repo
            .signal(callId, CallSignalWire.ice, <String, dynamic>{
              'candidate': c.candidate,
              'sdpMid': c.sdpMid,
              'sdpMLineIndex': c.sdpMLineIndex,
            }, to: user)
            .catchError((Object _) {}),
      );
    };

    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (_closed) return;
      // ⚠ ONE CONNECTED PEER IS A CALL. In a mesh the others may still be
      //   negotiating, and showing «يرنّ» while a voice is already audible
      //   would be a screen contradicting the earpiece.
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        phase.value = CallPhase.talking;
      }

      // ── ⚠ لحظةَ ينقطع الصوت، تُغلق — أياً كان السبب ────────────────────
      //
      //   When the other man hangs up, his handset closes its peer connection
      //   and THIS one knows within milliseconds — long before the server
      //   does, and long before the next beat of [steady] could ask. Until now
      //   nothing listened, so the call ended only when _tick counted fewer
      //   than two live seats: a beat plus a round trip on a Libyan
      //   connection, which is «الاتصال يتأخر في القفل».
      //
      // ⚠ IT CLOSES, IT DOES NOT ASK. An earlier version ran a beat here and
      //   left the SERVER's seat count to decide, so that a network blip could
      //   not end a live conversation. The association weighed that and chose
      //   otherwise — «المهم لحظة القفل يغلق أياً كان السبب ويقفل بسرعة» — and
      //   the cost is stated rather than hidden: a tunnel that drops for two
      //   seconds on mobile data now ends the call, and the answer is to ring
      //   again. For a room of eight that is the better trade; asking first
      //   cost a round trip on every hang-up, which is the common case.
      //
      // ⚠ AND IT IS «NO PEER LEFT ALIVE», NOT «THIS PEER DROPPED». المجلس is a
      //   room: four men on a call must keep talking when one leaves. The same
      //   clause answers both, exactly as the server's «fewer than two seats»
      //   does — one leaver of four still leaves three peers connected here.
      //
      // ⚠ AND ONLY AFTER COMPANY ARRIVED. A ringing caller holds a peer
      //   connection that has never been connected to anybody.
      _peerState[user] = s;
      if (_hadCompany && _peers.isNotEmpty && _livePeers() == 0) {
        unawaited(close());
      }
    };

    _peers[user] = pc;
    _remoteSet[user] = false;
    return pc;
  }

  Future<void> _offerTo(String user) async {
    final RTCPeerConnection pc = await _peerFor(user);
    final RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _repo.signal(callId, CallSignalWire.offer, <String, dynamic>{
      'sdp': offer.sdp,
      'type': offer.type,
    }, to: user);
  }

  /// The handshake clock's beat: signals and nothing else.
  ///
  /// ⚠ IT STOPS ITSELF THE MOMENT AUDIO IS FLOWING. Leaving a 300 ms poll
  ///   running for the length of a call would be three times the traffic of the
  ///   whole rest of the session, to answer a question nobody is waiting on any
  ///   more.
  Future<void> _drainOnly() async {
    if (_closed) return;
    if (phase.value == CallPhase.talking) {
      _handshake?.cancel();
      _handshake = null;
      return;
    }
    if (_draining) return;
    _draining = true;
    try {
      await _drain();
    } on Object catch (e) {
      // Same reasoning as the main tick: a failed beat is a beat.
      debugPrint('call handshake: $e');
    } finally {
      _draining = false;
    }
  }

  Future<void> _drain() async {
    final List<CallSignal> rows = await _repo.signalsAfter(callId, _seen);
    for (final CallSignal s in rows) {
      _seen = s.id;
      // Two refusals, and they are different failures — see signalIsForMe.
      if (!signalIsForMe(s, _me)) continue;
      await _apply(s);
    }
  }

  Future<void> _apply(CallSignal s) async {
    final String from = s.fromUserId;
    if (from.isEmpty) return;

    switch (s.kind) {
      case CallSignalWire.offer:
        final RTCPeerConnection pc = await _peerFor(from);
        await pc.setRemoteDescription(
          RTCSessionDescription(s.payload['sdp']?.toString(), 'offer'),
        );
        _remoteSet[from] = true;
        await _flush(from);
        final RTCSessionDescription answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await _repo.signal(callId, CallSignalWire.answer, <String, dynamic>{
          'sdp': answer.sdp,
          'type': answer.type,
        }, to: from);

      case CallSignalWire.answer:
        final RTCPeerConnection? pc = _peers[from];
        if (pc == null || _remoteSet[from] == true) return;
        await pc.setRemoteDescription(
          RTCSessionDescription(s.payload['sdp']?.toString(), 'answer'),
        );
        _remoteSet[from] = true;
        await _flush(from);

      case CallSignalWire.ice:
        final RTCIceCandidate c = RTCIceCandidate(
          s.payload['candidate']?.toString(),
          s.payload['sdpMid']?.toString(),
          (s.payload['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteSet[from] != true) {
          (_pending[from] ??= <RTCIceCandidate>[]).add(c);
          return;
        }
        await _peers[from]?.addCandidate(c);
    }
  }

  Future<void> _flush(String user) async {
    for (final RTCIceCandidate c in _pending[user] ?? const []) {
      try {
        await _peers[user]?.addCandidate(c);
      } on Object catch (e) {
        debugPrint('call candidate: $e');
      }
    }
    _pending.remove(user);
  }

  Future<void> toggleMute() async {
    final MediaStream? s = _local;
    if (s == null) return;
    muted.value = !muted.value;
    for (final MediaStreamTrack t in s.getAudioTracks()) {
      t.enabled = !muted.value;
    }
  }

  /// Route the audio to the loudspeaker instead of the earpiece.
  Future<void> setSpeaker(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } on Object catch (e) {
      debugPrint('call speaker: $e');
    }
  }

  /// ── ⚠ THE SERVER IS TOLD FIRST, AND THIS ORDER IS THE FIX ────────────────
  ///
  ///   It used to be the other way round, with a comment defending it: «the
  ///   media goes before the server is told, so a leave that failed to reach
  ///   the database still stops the microphone». The microphone half of that
  ///   is right and is kept. The ORDER was wrong, and the association paid for
  ///   it: «عند اغلاق الاتصال يبقي الاتصال مفتوح عند الطرف الاخر».
  ///
  ///   `leave_call` is the one thing that ends the call for the OTHER man, and
  ///   it was being sent LAST — behind `track.stop()`, `MediaStream.dispose()`
  ///   and one `RTCPeerConnection.close()` per peer. Those are native calls
  ///   into WebRTC across a platform channel, tearing down an active DTLS/ICE
  ///   session; they are not instant, and on a handset they can take seconds.
  ///   So the other side's «fewer than two seats» rule — which is correct on
  ///   both the server and here — could not fire until this phone had finished
  ///   tidying up after itself.
  ///
  /// ⚠ FIRED FIRST, AWAITED LAST, WHICH GIVES UP NOTHING. The request leaves
  ///   this handset before any teardown begins, and is still awaited at the end
  ///   — so a leave that fails is still caught, and the microphone still stops
  ///   whatever the network does. `catchError` is attached at the moment it is
  ///   created rather than at the await, because an error raised while the
  ///   future sits unawaited across the teardown's own awaits would be reported
  ///   as unhandled.
  ///
  /// ⚠ AND LEAVING IS STILL NOT ENDING. In المجلس the call goes on without him
  ///   — the server ends it only when fewer than two live seats remain, which
  ///   for a pair is the first man to hang up and for a group of four is not.
  ///   That decision stays on the server; this only stops delaying it.
  Future<void> close({bool declined = false}) async {
    if (_closed) return;
    _closed = true;
    phase.value = CallPhase.ended;

    _poll?.cancel();
    _poll = null;
    _handshake?.cancel();
    _handshake = null;
    _deafen?.call();
    _deafen = null;

    // ⚠ BEFORE THE TEARDOWN. See the note above.
    final Future<void> told =
        (declined ? _repo.end(callId, declined: true) : _repo.leave(callId))
            .catchError((Object e) => debugPrint('call leave: $e'));

    // ⚠ AND THE BELL WITH IT, so the other handset asks NOW rather than on its
    //   next beat. It carries no id and no verdict — the other side re-reads
    //   the participant list under its own RLS, exactly as its poll would have.
    _bell?.ring(Ring.call);

    for (final MediaStreamTrack t in _local?.getTracks() ?? const []) {
      await t.stop();
    }
    await _local?.dispose();
    for (final RTCPeerConnection pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _peerState.clear();
    _local = null;

    await told;
  }

  void dispose() {
    phase.dispose();
    muted.dispose();
    people.dispose();
  }
}
