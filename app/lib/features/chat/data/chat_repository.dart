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

  /// ── ⚠ THE ROOM IS ASKED FOR BY NAME, NOT INFERRED ────────────────────────
  ///
  ///   This read `isFilter('threadAdeelId', null)` for المجلس — and a DIRECT
  ///   message has that column NULL too. RLS hands a man his own direct rows
  ///   (it must; that is his conversation), so the hall query swept them up
  ///   and both participants watched a private line appear in the public room.
  ///   Reported in exactly those words: «الرسالة تظهر أيضاً في المحادثة
  ///   العامة». Nobody else ever saw it — read_chat's «peer_a IS NULL» held,
  ///   proven with the app's own role — but the two of them did, and that is
  ///   enough to destroy the promise.
  ///
  /// ⚠ SECOND TIME THIS EXACT AMBIGUITY HAS BITTEN. PATCH_20260823a's own note
  ///   says the read policy «had to be tightened to peer_a IS NULL» for the
  ///   same reason. The policy was fixed; every other reader of that column
  ///   was not. So the view now carries `room` — 'hall' | 'board' | 'direct'
  ///   — and nothing has to remember the rule again.
  ///
  /// ⚠ AND `eq`, NOT `isFilter`: room is never null. The old note here warned
  ///   that `eq(..., null)` filters on the literal string; that trap is gone
  ///   with the nullable column it applied to.
  static PostgrestFilterBuilder<dynamic> _inRoom(
    PostgrestFilterBuilder<dynamic> query,
    int? threadAdeelId,
  ) => threadAdeelId == null
      ? query.eq('room', 'hall')
      : query.eq('room', 'board').eq('threadAdeelId', threadAdeelId);

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

  // ── محادثة بين عديلٍ وعديل ───────────────────────────────────────────────

  /// The tail of a conversation with ONE other man, oldest first.
  ///
  /// ⚠ FILTERED BY «HE IS ONE OF THE TWO», NOT BY THE ORDERED PAIR, and the
  ///   difference is what makes this correct without the client knowing which
  ///   half of the pair it is. The server stores the two ids sorted
  ///   (`peer_a < peer_b`, a CHECK), so asking for «peerA = him OR peerB = him»
  ///   would on its own also match his conversations with OTHER men — and RLS
  ///   then removes every one of those, because a member only ever sees pairs
  ///   he is a side of. The intersection is exactly this pair.
  ///
  /// ⚠ SO THE PRIVACY IS THE SERVER'S HERE TOO. This filter narrows a list the
  ///   database has already narrowed; it decides nothing.
  Future<List<ChatMessage>> directMessages(
    int peerAdeelId, {
    int limit = 200,
  }) => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from('v_chat_messages')
        .select()
        .eq('room', 'direct')
        .or('peerA.eq.$peerAdeelId,peerB.eq.$peerAdeelId')
        .order('id', ascending: false)
        .limit(limit);
    return _rows(rows).reversed.toList();
  });

  /// The poll, for a direct thread. Same shape as [refreshFrom].
  Future<List<ChatMessage>> directRefreshFrom(int fromId, int peerAdeelId) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_chat_messages')
            .select()
            .eq('room', 'direct')
            .or('peerA.eq.$peerAdeelId,peerB.eq.$peerAdeelId')
            .gte('id', fromId)
            .order('id', ascending: true);
        return _rows(rows);
      });

  /// صندوقه: من راسله ومن راسل.
  ///
  /// ⚠ AN RPC RATHER THAN A VIEW, and the first attempt WAS a view. It joined
  ///   `adeels` for the other man's name — and a member sees exactly one row
  ///   there, his own — so the join dropped every thread and the inbox came
  ///   back empty for a man holding a live conversation. `api_direct_threads`
  ///   is SECURITY DEFINER and resolves the name where the pair test lives.
  Future<List<DirectThread>> directThreads() =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db.rpc<dynamic>('api_direct_threads');
        return (rows as List<dynamic>)
            .map(
              (dynamic e) =>
                  DirectThread.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
      });

  /// ⚠ `p_to_adeel_id`, AND NEVER TOGETHER WITH `p_thread_adeel_id`. The server
  ///   refuses the combination outright — a message is in ONE room — and this
  ///   is a separate method rather than a flag on [send] so the two cannot be
  ///   passed together by accident.
  Future<void> sendDirect(String body, {required int toAdeelId}) =>
      SupabaseFailures.guard(() async {
        await _db.rpc<dynamic>(
          'send_chat_message',
          params: <String, dynamic>{'p_body': body, 'p_to_adeel_id': toAdeelId},
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

  /// أحدثُ رسالةٍ لم يقرأها — لنصِّ الإشعار وحده.
  ///
  /// ⚠ ONE ROW, AND ONLY WHEN A NOTIFICATION IS ACTUALLY POSTED. The bell
  ///   ticks every two seconds and deliberately fetches ONE CAPPED COLUMN with
  ///   no bodies — that frugality is the only reason two seconds is
  ///   affordable. This is the opposite request: bodies, an author and a room,
  ///   for a single row. It is affordable because it runs on the RISE of the
  ///   count while the app is in the background, which is a handful of times a
  ///   day, not every tick.
  ///
  /// ⚠ AND THE NOTIFICATION WAS WRONG WITHOUT IT. Its title was the bare
  ///   COUNT — «3» on a lock screen — and its body said «لديك رسائل جديدة في
  ///   مجلس العدايل» for every message, including a private one between two
  ///   عدايل and a thread with the board. A notification that names the wrong
  ///   room is worse than a silent one: it is read, believed, and acted on.
  ///
  /// Returns null when there is nothing to show, so the caller can fall back
  /// to the generic text rather than lose the alert.
  Future<ChatMessage?> newestUnread(int sinceId) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_chat_messages')
            .select()
            .gt('id', sinceId)
            .eq('mine', false)
            .order('id', ascending: false)
            .limit(1);
        // ⚠ QUALIFIED: this sits in an extension, where the class's private
        //   static is not in scope unqualified.
        final List<ChatMessage> list = ChatRepository._rows(rows);
        return list.isEmpty ? null : list.first;
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

/// How many are waiting in المجلس alone.
///
/// The segment badge answers «في أي الغرفتين», and المجلس is the half of that
/// question no other count can reach: the bell sums both rooms, and the
/// per-thread map has no entry for a room attributed to nobody.
///
/// ⚠ NOT MINE, like every other count here. A man reading الخاص is not owed a
///   badge on المجلس for the sentence he typed there ten minutes ago.
extension ChatHallUnread on ChatRepository {
  Future<int> unreadInHall(int sinceId, {int cap = 99}) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_chat_messages')
            .select('id')
            // ⚠ THE SAME BUG WAS HERE. The hall badge counted a man's own
            //   private messages as unread المجلس — so a private conversation
            //   put a number on the public room.
            .eq('room', 'hall')
            .gt('id', sinceId)
            .eq('mine', false)
            .limit(cap);
        return (rows as List<dynamic>).length;
      });
}
