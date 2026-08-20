import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// How far this handset has read the room.
///
/// ── WHY THIS IS ON THE DEVICE AND NOT IN POSTGRES ───────────────────────────
/// The obvious shape is a `chat_reads` table keyed by user, and it is the wrong
/// trade here. It would be a THIRD patch on a live project inside one week — the
/// two before it cost a broken portal and an afternoon — for a fact that is not
/// association data: nobody but the reader ever needs to know how far he has
/// read, no figure depends on it, and losing it costs one badge showing zero.
///
/// It also matches the shape the app already has. `my_adeel_id()` reads the
/// `x-device-id` header, so a member IS one handset by design; "read on this
/// phone" and "read by this man" are the same sentence for the people this is
/// for. Staff on two devices would each carry their own mark, which is what a
/// person actually wants from a badge — the one in front of you is about what
/// you have seen on it.
///
/// ⚠ SECURE STORAGE FOR A NUMBER THAT IS NOT A SECRET. It is the only key-value
///   store this app already depends on (the refresh token lives there), and
///   adding shared_preferences for one integer is a package, a platform channel
///   and a second place device state can live. The cost of the wrong store here
///   is nothing; the cost of a new dependency is permanent.
class ChatReadState {
  const ChatReadState(this.store);

  /// Not private, because the per-thread marks live in an extension below and
  /// an extension cannot reach a private field. Same library either way — the
  /// name is the only thing that changes.
  final FlutterSecureStorage store;

  static const String _key = 'chat_last_read_id';

  /// The highest message id this handset has seen, or 0 for a fresh install.
  ///
  /// ⚠ ZERO MEANS "EVERYTHING IS NEW", not "nothing is". On a first run that
  ///   shows the whole room as unread, which is correct and is also exactly what
  ///   a new member should see: the badge says there is a conversation waiting.
  ///   The alternative — seeding it to the newest id — would silently mark as
  ///   read a hundred messages he has never opened.
  Future<int> lastRead() async {
    final String? raw = await store.read(key: _key);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// ⚠ MONOTONIC. Never moves backwards, because the mark is written from two
  ///   places — the room as it is read, and the badge as it polls — and an older
  ///   value arriving late would resurrect messages the man has already read.
  Future<void> markRead(int id) async {
    if (id <= 0) return;
    if (id <= await lastRead()) return;
    await store.write(key: _key, value: id.toString());
  }
}

/// The same mark, kept PER CONVERSATION for the board's inbox.
///
/// ── WHY A SECOND MARK AND NOT A REPLACEMENT ─────────────────────────────────
/// The bell answers «هل هناك جديد» across the whole association — one number, on
/// every screen. The inbox answers a different question: «من منهم ينتظر». One
/// global mark cannot answer the second, and a per-thread map cannot answer the
/// first without summing a map that has no entry for المجلس.
///
/// So there are two, and they are written at different moments: the global one
/// whenever any room is read, the per-thread one only when THAT thread is opened.
extension ChatThreadMarks on ChatReadState {
  static const String _threadKey = 'chat_thread_marks';

  /// thread عديل id → the highest message id read in it.
  ///
  /// Stored as one JSON object rather than a key per thread: secure storage is a
  /// keychain entry per key on iOS and a preference file on Android, and a
  /// hundred members would mean a hundred of them.
  Future<Map<int, int>> threadMarks() async {
    final String? raw = await store.read(key: _threadKey);
    if (raw == null || raw.isEmpty) return <int, int>{};
    try {
      final Map<String, dynamic> j = (jsonDecode(raw) as Map)
          .cast<String, dynamic>();
      return j.map(
        (String k, dynamic v) =>
            MapEntry<int, int>(int.parse(k), (v as num).toInt()),
      );
    } on Object {
      // A corrupt map reads as "nothing has been read", which shows every
      // conversation as waiting — visibly wrong and self-correcting the moment
      // each is opened. The alternative, throwing, would take the inbox down.
      return <int, int>{};
    }
  }

  /// ⚠ MONOTONIC PER THREAD, for the same reason the global mark is: the inbox
  ///   and the thread screen both write it, and an older value arriving late
  ///   would make a conversation the board has just read look unanswered again.
  Future<void> markThreadRead(int threadId, int messageId) async {
    if (threadId <= 0 || messageId <= 0) return;
    final Map<int, int> marks = await threadMarks();
    if ((marks[threadId] ?? 0) >= messageId) return;
    marks[threadId] = messageId;
    await store.write(
      key: _threadKey,
      value: jsonEncode(
        marks.map((int k, int v) => MapEntry<String, int>(k.toString(), v)),
      ),
    );
  }
}
