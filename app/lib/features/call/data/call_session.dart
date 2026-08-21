import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../core/domain/wire_values.dart';
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
  CallSession({required CallRepository repository, required this.callId})
    : _repo = repository;

  final CallRepository _repo;
  final int callId;

  final ValueNotifier<CallPhase> phase = ValueNotifier<CallPhase>(
    CallPhase.connecting,
  );
  final ValueNotifier<bool> muted = ValueNotifier<bool>(false);

  /// Who is on the line, for the screen to name.
  final ValueNotifier<List<CallParticipant>> people =
      ValueNotifier<List<CallParticipant>>(<CallParticipant>[]);

  MediaStream? _local;
  List<Map<String, dynamic>> _ice = <Map<String, dynamic>>[];
  Timer? _poll;
  int _seen = 0;
  int _myId = 0;
  String _me = '';
  bool _closed = false;

  /// One peer connection per other participant, keyed by his user id.
  final Map<String, RTCPeerConnection> _peers = <String, RTCPeerConnection>{};

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

      _poll = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_tick()),
      );
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
  Future<void> _tick() async {
    if (_closed) return;
    try {
      await _repo.heartbeat(callId);

      final List<CallParticipant> now = await _repo.participants(callId);
      people.value = now;
      for (final CallParticipant p in now) {
        if (p.mine) {
          _me = p.userId;
          break;
        }
      }

      // ── Offer to everyone who was here before me ────────────────────────
      for (final CallParticipant p in now) {
        if (p.mine || _peers.containsKey(p.userId)) continue;
        if (p.id < _myId) await _offerTo(p.userId);
      }

      // ── And drop anyone who has gone ────────────────────────────────────
      final Set<String> live = now.map((CallParticipant p) => p.userId).toSet();
      for (final String gone in _peers.keys.toList()) {
        if (live.contains(gone)) continue;
        await _peers.remove(gone)?.close();
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

  Future<void> _drain() async {
    final List<CallSignal> rows = await _repo.signalsAfter(callId, _seen);
    for (final CallSignal s in rows) {
      _seen = s.id;
      // ⚠ SKIP MY OWN, AND SKIP WHAT IS ADDRESSED TO SOMEBODY ELSE. Both are
      //   necessary and they are different: the first stops a handset feeding
      //   its own offer back into itself, the second stops it consuming the
      //   offer that belongs to a third man on the same call.
      if (s.mine) continue;
      if (s.toUserId.isNotEmpty && s.toUserId != _me) continue;
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

  /// ⚠ THE MEDIA GOES BEFORE THE SERVER IS TOLD, and the order is the point: a
  ///   leave that failed to reach the database must still stop the microphone.
  ///   The seat then empties on its own — twenty seconds of silence is what
  ///   removes a man from everyone's list — but a live microphone is not
  ///   something to leave to a retry.
  ///
  /// ⚠ AND LEAVING IS NOT ENDING. In المجلس the call goes on without him; the
  ///   server ends it when the last seat empties, which is not a decision for
  ///   whichever handset hung up first.
  Future<void> close({bool declined = false}) async {
    if (_closed) return;
    _closed = true;
    phase.value = CallPhase.ended;

    _poll?.cancel();
    _poll = null;

    for (final MediaStreamTrack t in _local?.getTracks() ?? const []) {
      await t.stop();
    }
    await _local?.dispose();
    for (final RTCPeerConnection pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _local = null;

    try {
      if (declined) {
        await _repo.end(callId, declined: true);
      } else {
        await _repo.leave(callId);
      }
    } on Object catch (e) {
      debugPrint('call leave: $e');
    }
  }

  void dispose() {
    phase.dispose();
    muted.dispose();
    people.dispose();
  }
}
