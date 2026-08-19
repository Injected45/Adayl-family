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
      .map((dynamic e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()))
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
          (dynamic e) => ChatThread.fromJson((e as Map).cast<String, dynamic>()),
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
