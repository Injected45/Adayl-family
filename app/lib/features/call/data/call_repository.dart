import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/domain/wire_values.dart';
import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// المكالمة، على Supabase.
///
/// Reads come from `v_calls` and `v_call_signals`; every write goes through one
/// of the four `SECURITY DEFINER` functions, as everything else in this app
/// does — and here it is load-bearing rather than stylistic. `start_call` takes
/// an advisory lock on the thread before it looks for a live call, and
/// `answer_call` carries `status = 'ترن'` inside its own UPDATE so exactly one
/// person can answer. Neither is expressible as a row policy: a policy judges
/// the row in front of it and knows nothing about the ones beside it.
class CallRepository {
  CallRepository(this._db);

  final SupabaseClient _db;

  /// The STUN and TURN list, from `association_settings`.
  ///
  /// ⚠ FETCHED, NOT COMPILED IN. The day a public TURN host stops answering,
  ///   calls fail on mobile data while working perfectly on wifi — and the fix
  ///   is one UPDATE in the SQL Editor rather than a new APK on every handset.
  ///   That is the whole reason this is a request and not a constant.
  Future<List<Map<String, dynamic>>> iceServers() =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db.rpc<dynamic>('api_ice_servers');
        return (rows as List<dynamic>)
            .map((dynamic e) => (e as Map).cast<String, dynamic>())
            .toList();
      });

  /// The live call in one thread, or null.
  ///
  /// Newest first with a cap of one: `start_call` guarantees at most one live
  /// call per thread, so anything older is history.
  Future<CallView?> liveIn(int? threadAdeelId) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _inThread(
          _db.from('v_calls').select(),
          threadAdeelId,
        ).order('id', ascending: false).limit(1);

        final List<dynamic> list = rows as List<dynamic>;
        if (list.isEmpty) return null;
        final CallView call = CallView.fromJson(
          (list.first as Map).cast<String, dynamic>(),
        );
        // ⚠ THE VIEW ALREADY EXPIRED IT if it was stale, so this is a plain
        //   equality test and not a second clock. See CallView.status.
        return (call.status == CallStatusWire.ringing ||
                call.status == CallStatusWire.active)
            ? call
            : null;
      });

  /// The newest live call in ANY thread this account may see.
  ///
  /// ⚠ NO THREAD FILTER, ON PURPOSE. A call has to be noticed from wherever
  ///   the man is standing — the treasury screen, his own dues, anywhere — and
  ///   RLS already narrows this to the threads he is a side of. Filtering by
  ///   thread in Dart would mean only the chat screen could ever ring, which
  ///   is the one screen where he can already see it.
  Future<CallView?> liveAny() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from('v_calls')
        .select()
        .inFilter('status', <String>[
          CallStatusWire.ringing,
          CallStatusWire.active,
        ])
        .order('id', ascending: false)
        .limit(1);

    final List<dynamic> list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    return CallView.fromJson((list.first as Map).cast<String, dynamic>());
  });

  /// Everything said on this call after [afterId].
  ///
  /// One request per poll, ordered oldest first: an ICE candidate that arrives
  /// before the answer it belongs to is useless, and Postgres ordering is the
  /// cheapest way to guarantee it cannot.
  Future<List<CallSignal>> signalsAfter(int callId, int afterId) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_call_signals')
            .select()
            .eq('callId', callId)
            .gt('id', afterId)
            .order('id', ascending: true);
        return (rows as List<dynamic>)
            .map(
              (dynamic e) => CallSignal.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
      });

  Future<int> start(int? threadAdeelId) => SupabaseFailures.guard(() async {
    final dynamic id = await _db.rpc<dynamic>(
      'start_call',
      params: <String, dynamic>{'p_thread_adeel_id': threadAdeelId},
    );
    return (id as num).toInt();
  });

  /// من على المكالمة الآن — live seats only; the view drops anyone not heard
  /// from in twenty seconds, so a phone that lost signal leaves by itself.
  Future<List<CallParticipant>> participants(int callId) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_call_participants')
            .select()
            .eq('callId', callId)
            .order('id', ascending: true);
        return (rows as List<dynamic>)
            .map(
              (dynamic e) =>
                  CallParticipant.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
      });

  /// Take a seat, and return its id.
  ///
  /// ⚠ THIS REPLACES answer_call FOR THE CLIENT, and it is the same act said
  ///   better. A two-person call is a mesh of two: joining is what puts a man
  ///   on the line, and the first join is what turns «ترن» into «جارية».
  ///   Keeping two verbs would mean two code paths for one thing, and the
  ///   group one is the general case.
  Future<int> join(int callId) => SupabaseFailures.guard(() async {
    final dynamic id = await _db.rpc<dynamic>(
      'join_call',
      params: <String, dynamic>{'p_call_id': callId},
    );
    return (id as num).toInt();
  });

  /// «I am still here.» Silence for twenty seconds is what removes a man from
  /// the call for everybody, without any client having to decide it.
  Future<void> heartbeat(int callId) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'heartbeat_call',
      params: <String, dynamic>{'p_call_id': callId},
    );
  });

  /// ⚠ LEAVING IS NOT ENDING. In المجلس the call goes on without him — the
  ///   server ends it when the LAST seat empties, which is not something the
  ///   handset that happens to hang up first should decide.
  Future<void> leave(int callId) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'leave_call',
      params: <String, dynamic>{'p_call_id': callId},
    );
  });

  /// Hanging up and declining are one act with two names — a call the other
  /// side never answered ended too. [declined] only changes the word recorded.
  Future<void> end(int callId, {bool declined = false}) =>
      SupabaseFailures.guard(() async {
        await _db.rpc<dynamic>(
          'end_call',
          params: <String, dynamic>{
            'p_call_id': callId,
            'p_declined': declined,
          },
        );
      });

  /// [to] is the user this line is addressed to. Null broadcasts, which is
  /// what a two-person call did before the mesh and what any future
  /// call-wide message would use.
  Future<void> signal(
    int callId,
    String kind,
    Map<String, dynamic> payload, {
    String? to,
  }) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'send_signal',
      params: <String, dynamic>{
        'p_call_id': callId,
        'p_kind': kind,
        'p_payload': payload,
        'p_to': to,
      },
    );
  });

  /// `is('threadAdeelId', null)` and not `eq(..., null)`: PostgREST needs IS
  /// NULL, and `eq` with a null filters on the literal string. The same trap
  /// `ChatRepository._inRoom` documents.
  static PostgrestFilterBuilder<dynamic> _inThread(
    PostgrestFilterBuilder<dynamic> query,
    int? threadAdeelId,
  ) => threadAdeelId == null
      ? query.isFilter('threadAdeelId', null)
      : query.eq('threadAdeelId', threadAdeelId);
}
