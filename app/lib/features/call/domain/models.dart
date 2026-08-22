/// One voice call, as `v_calls` reports it.
///
/// ⚠ THE STATUS IS THE VIEW'S, NOT THE ROW'S. `v_calls` reports a «ترن» older
///   than sixty seconds as «فائتة» — so a phone that died between the invite
///   and the answer cannot leave another handset ringing forever. Nothing here
///   recomputes that, and nothing here should: a second expiry rule in Dart
///   would be free to disagree with the one the database applies, and the two
///   would disagree exactly when a client is misbehaving.
class CallView {
  const CallView({
    required this.id,
    required this.threadAdeelId,
    required this.callerName,
    required this.mine,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.peerAdeelId,
  });

  final int id;
  final int? threadAdeelId;
  final String callerName;

  /// Whether this account is the one that raised it.
  final bool mine;

  final String status;
  final String startedAt;
  final String endedAt;

  /// The عديل being rung directly, when this is a peer call.
  ///
  /// ⚠ NULL FOR BOTH ROOMS, and the three shapes are exclusive by CHECK:
  ///   a thread id means الإدارة, this means one man to one man, and neither
  ///   means المجلس. A row that could be read two ways is a row two policies
  ///   will disagree about.
  final int? peerAdeelId;

  factory CallView.fromJson(Map<String, dynamic> json) => CallView(
    id: (json['id'] as num?)?.toInt() ?? 0,
    threadAdeelId: (json['threadAdeelId'] as num?)?.toInt(),
    callerName: json['callerName']?.toString() ?? '',
    mine: json['mine'] == true,
    status: json['status']?.toString() ?? '',
    startedAt: json['startedAt']?.toString() ?? '',
    endedAt: json['endedAt']?.toString() ?? '',
    peerAdeelId: (json['peerAdeelId'] as num?)?.toInt(),
  );
}

/// One line of the WebRTC handshake: an offer, an answer, or a candidate.
class CallSignal {
  const CallSignal({
    required this.id,
    required this.callId,
    required this.kind,
    required this.payload,
    required this.mine,
    required this.fromUserId,
    required this.toUserId,
  });

  final int id;
  final int callId;
  final String kind;
  final Map<String, dynamic> payload;

  /// ⚠ THE ONLY THING THAT KEEPS A HANDSET FROM ANSWERING ITSELF. Both sides
  ///   read the SAME rows — the policy is «may you see this call», not «is it
  ///   addressed to you» — so a client that did not skip its own offer would
  ///   feed its own SDP back into its own peer connection.
  final bool mine;

  /// Who sent it — the key a mesh peer is filed under.
  final String fromUserId;

  /// Who it is FOR. Empty means «everyone on this call», which is what every
  /// stage-1 row is.
  ///
  /// ⚠ WITHOUT THIS A GROUP CALL COLLAPSES. With two people every signal on a
  ///   call belongs to the other one; with four, an offer from A to B is read
  ///   by C and D as well, each sets it as ITS remote description, and the
  ///   failure looks exactly like a bad network.
  final String toUserId;

  factory CallSignal.fromJson(Map<String, dynamic> json) => CallSignal(
    id: (json['id'] as num?)?.toInt() ?? 0,
    callId: (json['callId'] as num?)?.toInt() ?? 0,
    kind: json['kind']?.toString() ?? '',
    payload: (json['payload'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    mine: json['mine'] == true,
    fromUserId: json['fromUserId']?.toString() ?? '',
    toUserId: json['toUserId']?.toString() ?? '',
  );
}

/// من يمكن الاتصال به — اسمٌ وكودٌ ولا شيء غيرهما.
///
/// ⚠ NO PHONE, NO BALANCE, NO DUES. `api_call_directory` answers «من أتصل
///   به» and every other column would be an answer to a question nobody
///   asked. It also lists only men whose app is actually bound to a handset:
///   offering a call to somebody with no app is offering a call that rings
///   in an empty room.
class CallPeer {
  const CallPeer({
    required this.adeelId,
    required this.name,
    required this.code,
  });

  final int adeelId;
  final String name;
  final String code;

  factory CallPeer.fromJson(Map<String, dynamic> json) => CallPeer(
    adeelId: (json['adeelId'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    code: json['code']?.toString() ?? '',
  );
}

/// من هو على المكالمة الآن.
///
/// ⚠ THE id IS NOT DECORATION — it decides who offers whom. The man who joined
///   LATER has the larger id and makes the offer to everyone already in; both
///   sides compute the same answer from the same two numbers, so there is no
///   round of «you go first» to lose and no glare, because one id is always the
///   larger. It also survives a reconnect: join_call takes back the SAME seat
///   rather than issuing a second one.
class CallParticipant {
  const CallParticipant({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.mine,
  });

  final int id;
  final String userId;
  final String displayName;
  final bool mine;

  factory CallParticipant.fromJson(Map<String, dynamic> json) =>
      CallParticipant(
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: json['userId']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '',
        mine: json['mine'] == true,
      );
}
