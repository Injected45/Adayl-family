import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// مقترحات المشتركين، على Supabase.
///
/// One read — `v_proposals` — and three writes, each a function that decides
/// who may call it: `submit_proposal` (a member with his key), and
/// `accept_proposal` / `reject_proposal` (the admin).
///
/// ⚠ THE SAME QUERY SERVES BOTH READERS. RLS hands a member his own proposals
///   and the admin everybody's; nothing here filters by who is asking.
class ProposalsRepository {
  ProposalsRepository(this._db);

  final SupabaseClient _db;

  /// Newest first.
  Future<List<Proposal>> list() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from('v_proposals')
        .select()
        .order('id', ascending: false);
    return (rows as List<dynamic>)
        .map(
          (dynamic e) => Proposal.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  });

  /// The ids of the proposals still waiting, newest first — for the admin's
  /// badge and alert. ⚠ ONE CAPPED COLUMN, NO BODIES: this runs on a timer.
  Future<List<int>> waitingIds({int cap = 99}) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_proposals')
            .select('id')
            .eq('status', 'pending')
            .order('id', ascending: false)
            .limit(cap);
        return <int>[
          for (final dynamic r in rows as List<dynamic>)
            ((r as Map)['id'] as num).toInt(),
        ];
      });

  /// One proposal, for the text of the alert.
  Future<Proposal?> byId(int id) => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from('v_proposals')
        .select()
        .eq('id', id)
        .limit(1);
    final List<dynamic> list = rows as List<dynamic>;
    if (list.isEmpty) return null;
    return Proposal.fromJson((list.first as Map).cast<String, dynamic>());
  });

  Future<void> submit({required String title, required String body}) =>
      SupabaseFailures.guard(() async {
        await _db.rpc<dynamic>(
          'submit_proposal',
          params: <String, dynamic>{
            'p_title': title.trim(),
            'p_body': body.trim(),
          },
        );
      });

  Future<void> accept(int id) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'accept_proposal',
      params: <String, dynamic>{'p_id': id},
    );
  });

  /// ⚠ DELETES IT, in the database, for everyone.
  Future<void> reject(int id) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'reject_proposal',
      params: <String, dynamic>{'p_id': id},
    );
  });
}
