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
  const ChatReadState(this._store);

  final FlutterSecureStorage _store;

  static const String _key = 'chat_last_read_id';

  /// The highest message id this handset has seen, or 0 for a fresh install.
  ///
  /// ⚠ ZERO MEANS "EVERYTHING IS NEW", not "nothing is". On a first run that
  ///   shows the whole room as unread, which is correct and is also exactly what
  ///   a new member should see: the badge says there is a conversation waiting.
  ///   The alternative — seeding it to the newest id — would silently mark as
  ///   read a hundred messages he has never opened.
  Future<int> lastRead() async {
    final String? raw = await _store.read(key: _key);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// ⚠ MONOTONIC. Never moves backwards, because the mark is written from two
  ///   places — the room as it is read, and the badge as it polls — and an older
  ///   value arriving late would resurrect messages the man has already read.
  Future<void> markRead(int id) async {
    if (id <= 0) return;
    if (id <= await lastRead()) return;
    await _store.write(key: _key, value: id.toString());
  }
}
