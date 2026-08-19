/// The room, as `v_chat_messages` sends it.
library;

String _string(Object? value) => value == null ? '' : value.toString();
int _int(Object? value) => value is num ? value.toInt() : 0;
bool _bool(Object? value) => value == true;

/// One message.
///
/// Note what is NOT here: the author's user id. The view answers [mine]
/// server-side instead, so the client never holds anyone's identity and never
/// decides whose bubble it is looking at — the same reason [deleted] arrives as
/// a flag with an empty [body] rather than as text the app is trusted to hide.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorName,
    required this.body,
    required this.createdAt,
    required this.mine,
    required this.fromStaff,
    required this.deleted,
    this.authorAdeelId,
    this.threadAdeelId,
    this.threadName = '',
  });

  /// Monotonic, and the app leans on that twice: it is the sort key and it is
  /// the polling cursor (`id > lastSeen`). Timestamps could not do either job —
  /// two messages can share a second, and a client clock can disagree with the
  /// server's.
  final int id;

  /// A SNAPSHOT taken when the message was sent, from the REGISTER for a member
  /// and from the profile for staff. It is not a join, which is what lets an
  /// عديل read the room without being able to read anything else about the
  /// people in it.
  final String authorName;

  /// Empty when [deleted] — the words are erased in the database, not merely
  /// withheld from the response.
  final String body;
  final String createdAt;

  /// Computed by the view from `auth.uid()`. Decides which side the bubble sits
  /// on and whether the delete action is offered.
  final bool mine;

  /// Said by someone on the board at the time. Carried so an announcement can be
  /// told from a conversation at a glance.
  final bool fromStaff;

  final bool deleted;

  /// Present when the author was a member, so staff can open his record from the
  /// room. Null for staff messages, and null once that member is deleted.
  final int? authorAdeelId;

  /// WHICH ROOM. Null is المجلس — the open room everyone in the association
  /// reads. An id is that man's private thread with الإدارة, which has exactly
  /// two sides and is invisible to every other member.
  ///
  /// The wall is `read_chat`, not this field: the server never hands a reader a
  /// row from a thread he is not a side of, so nothing in Dart has to filter for
  /// privacy — and nothing in Dart could be trusted to.
  final int? threadAdeelId;

  /// The man the private thread is ABOUT, for the board's inbox heading. Joined
  /// rather than snapshot, so a corrected spelling corrects the heading of a
  /// conversation that is still open. Empty in المجلس.
  final String threadName;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: _int(json['id']),
    authorName: _string(json['authorName']),
    body: _string(json['body']),
    createdAt: _string(json['createdAt']),
    mine: _bool(json['mine']),
    fromStaff: _bool(json['fromStaff']),
    deleted: _bool(json['deleted']),
    threadName: _string(json['threadName']),
    threadAdeelId: json['threadAdeelId'] is num
        ? (json['threadAdeelId'] as num).toInt()
        : null,
    authorAdeelId: json['authorAdeelId'] is num
        ? (json['authorAdeelId'] as num).toInt()
        : null,
  );
}

/// One private conversation, as the board's inbox reads it.
///
/// Built from the MESSAGES, so a man who has never written appears nowhere — an
/// inbox listing every عديل on the register with «لا رسائل» beside him is a
/// register, and the association already has one.
class ChatThread {
  const ChatThread({
    required this.adeelId,
    required this.adeelName,
    required this.adeelCode,
    required this.messages,
    required this.lastBody,
    required this.lastFromStaff,
    required this.lastAt,
  });

  final int adeelId;
  final String adeelName;
  final String adeelCode;
  final int messages;

  /// The last thing either side said. Empty when that message was deleted — the
  /// preview is a second place the words could leak from, and the server empties
  /// it there for the same reason it empties the bubble.
  final String lastBody;

  /// Whether the last word was the board's. It is what answers «من ينتظر رداً»
  /// at a glance, which is the question an inbox is opened with.
  final bool lastFromStaff;

  final String lastAt;

  factory ChatThread.fromJson(Map<String, dynamic> json) => ChatThread(
    adeelId: _int(json['adeelId']),
    adeelName: _string(json['adeelName']),
    adeelCode: _string(json['adeelCode']),
    messages: _int(json['messages']),
    lastBody: _string(json['lastBody']),
    lastFromStaff: _bool(json['lastFromStaff']),
    lastAt: _string(json['lastAt']),
  );
}
