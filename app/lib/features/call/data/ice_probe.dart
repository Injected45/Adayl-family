import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// نتيجة فحص مسار الاتصال.
///
/// Three questions, and each answers a DIFFERENT failure — which is the whole
/// reason they are three booleans and not one «it works».
class IceReport {
  const IceReport({
    required this.host,
    required this.srflx,
    required this.relay,
    required this.servers,
    required this.error,
  });

  /// This device found its own address. Fails only if there is no network at
  /// all, or the microphone permission was refused before gathering began.
  final bool host;

  /// A STUN server answered and told this phone its public address.
  ///
  /// ⚠ THIS IS WHAT A CALL NEEDS BETWEEN TWO DIFFERENT NETWORKS **when at
  ///   least one side's NAT is permissive**. Without it, two phones on
  ///   different networks can still connect only through a relay.
  final bool srflx;

  /// A TURN server answered and allocated a relay.
  ///
  /// ⚠ AND THIS IS THE ONE THAT DECIDES THE HARD CASE. Libyan mobile carriers
  ///   run carrier-grade NAT: two subscribers on mobile data usually cannot
  ///   reach each other whatever STUN reports, and the audio has to travel
  ///   through a relay both can reach. No relay candidate means calls will
  ///   work on wifi and fail on mobile data — which is the exact symptom that
  ///   is otherwise impossible to diagnose from inside the app.
  final bool relay;

  /// How many entries the ICE list from `association_settings` carried.
  final int servers;

  /// Set when the probe itself could not run.
  final String error;

  bool get ok => host && relay;
}

/// يفحص مسار الاتصال من هذا الجهاز وحده.
///
/// ── لماذا هذا موجود ────────────────────────────────────────────────────────
/// «هل تنجح المكالمة بين جهازين على شبكتين مختلفتين؟» is a question nobody can
/// answer by reading code — it depends on two carriers, their NAT, and whether
/// a borrowed public TURN server is alive this week. It normally takes two
/// phones, two SIM cards and two people.
///
/// ⚠ IT DOES NOT. Gathering ICE candidates is exactly the part of a call that
///   tests the network, and one phone can do it alone: the peer connection asks
///   every configured STUN and TURN server for an address, and what comes back
///   IS the answer. No second device, no call placed, no other person's time.
///
/// ⚠ AND IT TURNS «الاتصال لا يعمل» INTO A REPAIRABLE SENTENCE. Without it, a
///   failed call on mobile data is indistinguishable from a bug in the app, a
///   wrong policy, an unapplied patch or a dead relay — and every one of those
///   has a different fix. With it, the phone says which.
Future<IceReport> probeIce(List<Map<String, dynamic>> iceServers) async {
  RTCPeerConnection? pc;
  final Completer<void> done = Completer<void>();
  bool host = false;
  bool srflx = false;
  bool relay = false;

  try {
    pc = await createPeerConnection(<String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });

    pc.onIceCandidate = (RTCIceCandidate c) {
      final String s = c.candidate ?? '';
      if (s.contains('typ host')) host = true;
      if (s.contains('typ srflx')) srflx = true;
      if (s.contains('typ relay')) relay = true;
      // ⚠ STOP AT THE FIRST RELAY. It is the last kind to arrive and the only
      //   one that settles the hard case, so once it is in there is nothing
      //   left to wait for — and waiting the full timeout for an answer
      //   already known makes the check feel broken.
      if (relay && !done.isCompleted) done.complete();
    };

    pc.onIceGatheringState = (RTCIceGatheringState s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    };

    // ⚠ A DATA CHANNEL, AND IT IS NOT OPTIONAL. A peer connection with no
    //   track and no channel has nothing to negotiate, so it gathers NO
    //   candidates at all and the probe would report a total failure on a
    //   perfectly good network. A channel is the cheapest thing that makes the
    //   offer non-empty — and unlike an audio track it needs no microphone
    //   permission, so the check can be run before anyone has granted one.
    await pc.createDataChannel('probe', RTCDataChannelInit());

    final RTCSessionDescription offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    // ⚠ TWELVE SECONDS. TURN over TCP/443 on a slow mobile connection is the
    //   slowest candidate there is, and it is precisely the one worth waiting
    //   for: a shorter timeout would report «no relay» on a network where the
    //   relay was merely late, which is the wrong answer in the direction that
    //   costs the most.
    await done.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {},
    );

    return IceReport(
      host: host,
      srflx: srflx,
      relay: relay,
      servers: iceServers.length,
      error: '',
    );
  } on Object catch (e) {
    debugPrint('ice probe: $e');
    return IceReport(
      host: host,
      srflx: srflx,
      relay: relay,
      servers: iceServers.length,
      error: e.toString(),
    );
  } finally {
    await pc?.close();
  }
}
