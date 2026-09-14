import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// How far this handset has read the association's notices.
///
/// On the device, for the reasons `ChatReadState` gives: nobody but the reader
/// needs to know it, no figure depends on it, and losing it costs one badge.
///
/// ⚠ KEYED BY ACCOUNT, unlike the chat mark. Notice ids are shared by everyone
///   — the same broadcast is one row for all eight men — so a phone signed in
///   as one man and then another would otherwise carry the first man's mark
///   and show the second a badge of zero over notices he has never seen.
class NoticeReadState {
  const NoticeReadState(this.store);

  final FlutterSecureStorage store;

  static String _key(String userId) => 'notice_last_seen_$userId';

  /// ⚠ ZERO MEANS «EVERYTHING IS NEW», as in the chat: a fresh install shows
  ///   what is waiting rather than silently marking it read.
  Future<int> lastSeen(String userId) async {
    final String? raw = await store.read(key: _key(userId));
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// ⚠ MONOTONIC — the screen and the badge both write it, and an older value
  ///   arriving late must not resurrect notices already read.
  Future<void> markSeen(String userId, int id) async {
    if (id <= 0) return;
    if (id <= await lastSeen(userId)) return;
    await store.write(key: _key(userId), value: id.toString());
  }
}
