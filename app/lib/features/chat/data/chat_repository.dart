import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// The room, on Supabase.
///
/// Reads come from `v_chat_messages`; both writes go through `SECURITY DEFINER`
/// functions, and for this table that is not merely the house style. Sending a
/// message has to count what this author sent in the last minute and snapshot
/// the name the register holds for him — neither of which a row policy can
/// express, because a policy judges the row in front of it and knows nothing
/// about the ones before.
class ChatRepository {
  ChatRepository(this._db);

  final SupabaseClient _db;

  static List<ChatMessage> _rows(dynamic value) => (value as List<dynamic>)
      .map(
        (dynamic e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()),
      )
      .toList();

  /// The tail of one conversation, oldest first.
  ///
  /// [threadAdeelId] picks the room: null is المجلس, an id is that man's private
  /// thread. Filtered here as well as by RLS — not for privacy, which the server
  /// settles and Dart cannot, but because the two are separate lists on screen
  /// and staff can read both.
  ///
  /// Fetched newest-first with a cap and then reversed, which is the only way to
  /// get the LAST [limit] rows out of PostgREST — `ascending: true` with a limit
  /// would return the first two hundred messages the association ever sent.
  Future<List<ChatMessage>> messages({int? threadAdeelId, int limit = 200}) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _inRoom(
          _db.from('v_chat_messages').select(),
          threadAdeelId,
        ).order('id', ascending: false).limit(limit);
        return _rows(rows).reversed.toList();
      });

  /// The state of the visible window, and anything after it.
  ///
  /// This is the poll. A deletion changes a row that is ALREADY on screen and an
  /// `id > lastSeen` cursor cannot see it — its id is not greater than anything
  /// — so the window is re-read rather than only extended. One request answers
  /// both questions, because `id >= from` includes everything after it.
  Future<List<ChatMessage>> refreshFrom(int fromId, {int? threadAdeelId}) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _inRoom(
          _db.from('v_chat_messages').select(),
          threadAdeelId,
        ).gte('id', fromId).order('id', ascending: true);
        return _rows(rows);
      });

  /// `is('threadAdeelId', null)` and not `eq(..., null)`: PostgREST needs IS
  /// NULL, and `eq` with a null would filter on the literal string.
  static PostgrestFilterBuilder<dynamic> _inRoom(
    PostgrestFilterBuilder<dynamic> query,
    int? threadAdeelId,
  ) => threadAdeelId == null
      ? query.isFilter('threadAdeelId', null)
      : query.eq('threadAdeelId', threadAdeelId);

  /// The board's inbox: one row per private conversation, newest first.
  ///
  /// Staff-only, and by the SAME policy as the messages rather than by a rule of
  /// its own — a member reading this view gets his own conversation and never a
  /// list of who else has written to the board.
  Future<List<ChatThread>> threads() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db.from('v_chat_threads').select();
    return (rows as List<dynamic>)
        .map(
          (dynamic e) =>
              ChatThread.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  });

  Future<void> send(String body, {int? threadAdeelId}) =>
      SupabaseFailures.guard(() async {
        await _db.rpc<dynamic>(
          'send_chat_message',
          params: <String, dynamic>{
            'p_body': body,
            'p_thread_adeel_id': threadAdeelId,
          },
        );
      });

  /// Refused server-side for anyone but the author or an admin. The screen hides
  /// the action in the other cases, which is presentation and counts for
  /// nothing — `delete_chat_message` is where the rule lives.
  Future<void> delete(int id) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'delete_chat_message',
      params: <String, dynamic>{'p_id': id},
    );
  });
}

/// How many messages sit above [sinceId], for the badge.
///
/// ── WHY IT IS A SEPARATE, TINY REQUEST ──────────────────────────────────────
/// The badge is wanted on EVERY screen, and the room's own poll only runs while
/// the room is open. This one selects a single column with a cap and no body
/// text, so it stays a few hundred bytes however busy the room has been.
///
/// ⚠ IT COUNTS BOTH ROOMS, AND THAT IS THE ANSWER THE BELL SHOULD GIVE. RLS
///   already decides which rows exist for this caller — المجلس for everyone,
///   plus his own private thread, plus every private thread for staff — so what
///   comes back is exactly "messages waiting for ME", without the client
///   deciding anything about who may see what.
///
/// ⚠ AND IT CANNOT COUNT HIS OWN. A man who has just written does not have an
///   unread message; without the filter the bell would ring at him for the
///   sentence he typed a second ago, which is the fastest way to teach somebody
///   to ignore a badge.
extension ChatUnread on ChatRepository {
  Future<int> unreadSince(int sinceId, {int cap = 99}) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_chat_messages')
            .select('id')
            .gt('id', sinceId)
            .eq('mine', false)
            .limit(cap);
        return (rows as List<dynamic>).length;
      });

  /// The newest id that exists for this caller, or 0 for an empty room.
  ///
  /// Used to mark the room read: the badge must clear against what the SERVER
  /// has, not against the last row the screen happened to render.
  Future<int> newestId() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from('v_chat_messages')
        .select('id')
        .order('id', ascending: false)
        .limit(1);
    final List<dynamic> list = rows as List<dynamic>;
    if (list.isEmpty) return 0;
    return ((list.first as Map)['id'] as num).toInt();
  });
}

/// How many messages are waiting in EACH private conversation.
///
/// ── ONE REQUEST, NOT ONE PER THREAD ─────────────────────────────────────────
/// The board's inbox can hold every member who has ever written. Asking per row
/// would be forty round trips to draw one list — so this asks once for the ids
/// above the LOWEST mark any thread carries, and counts them per thread here.
/// Two integer columns, so the payload stays small however many come back.
///
/// ⚠ NOT MINE. A thread the board has just replied in is not a thread waiting
///   for the board, and counting its own answers would leave a number beside
///   every conversation it had already dealt with — which is the fastest way to
///   make an inbox unreadable.
///
/// The cap is a real limit and is deliberately loud about it: past it the count
/// is a floor, not a total. A board that is 500 messages behind does not need a
/// precise number, it needs to open the app.
extension ChatThreadUnread on ChatRepository {
  Future<Map<int, int>> unreadByThread(Map<int, int> marks, {int cap = 500}) =>
      SupabaseFailures.guard(() async {
        final int floor = marks.isEmpty
            ? 0
            : marks.values.reduce((int a, int b) => a < b ? a : b);

        final dynamic rows = await _db
            .from('v_chat_messages')
            .select('id, threadAdeelId')
            .not('threadAdeelId', 'is', null)
            .gt('id', floor)
            .eq('mine', false)
            .limit(cap);

        final Map<int, int> out = <int, int>{};
        for (final dynamic e in rows as List<dynamic>) {
          final Map<String, dynamic> row = (e as Map).cast<String, dynamic>();
          final int thread = (row['threadAdeelId'] as num).toInt();
          final int id = (row['id'] as num).toInt();
          // Counted against THAT thread's own mark, not against the floor — the
          // floor is only how little had to be fetched.
          if (id <= (marks[thread] ?? 0)) continue;
          out[thread] = (out[thread] ?? 0) + 1;
        }
        return out;
      });
}
