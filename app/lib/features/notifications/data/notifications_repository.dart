import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// الإشعارات، على Supabase.
///
/// Reads come from `v_notifications`; the one write — a message from the
/// admin to everyone — goes through `send_broadcast()`. Every other row is
/// written by a trigger on the ledger, so there is nothing else to call.
///
/// ⚠ WHO SEES WHICH ROW IS NOT DECIDED HERE. `read_notifications_member` hands
///   an عديل his own rows and the association's, from after his record was
///   created, on his own handset only; `read_notifications_staff` hands the
///   admin all of them. The same query below returns the right list for both.
class NotificationsRepository {
  NotificationsRepository(this._db);

  final SupabaseClient _db;

  static const String _view = 'v_notifications';

  /// Newest first. Two hundred is months of this association's activity.
  Future<List<AppNotice>> list({int limit = 200}) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from(_view)
            .select()
            .order('id', ascending: false)
            .limit(limit);
        return (rows as List<dynamic>)
            .map(
              (dynamic e) =>
                  AppNotice.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList();
      });

  /// How many arrived after [sinceId] — the red badge.
  ///
  /// ⚠ ONE CAPPED COLUMN, NO BODIES, because this runs on a timer. The bell in
  ///   the chat learned that shape; the same reasoning holds here.
  Future<int> unreadSince(int sinceId, {int cap = 99}) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from(_view)
            .select('id')
            .gt('id', sinceId)
            .limit(cap);
        return (rows as List<dynamic>).length;
      });

  /// The newest unread notice — for the text of the phone notification, and
  /// only on the rise of the count.
  Future<AppNotice?> newestSince(int sinceId) =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from(_view)
            .select()
            .gt('id', sinceId)
            .order('id', ascending: false)
            .limit(1);
        final List<dynamic> list = rows as List<dynamic>;
        if (list.isEmpty) return null;
        return AppNotice.fromJson((list.first as Map).cast<String, dynamic>());
      });

  /// The newest id this caller can see, or 0.
  Future<int> newestId() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from(_view)
        .select('id')
        .order('id', ascending: false)
        .limit(1);
    final List<dynamic> list = rows as List<dynamic>;
    if (list.isEmpty) return 0;
    return ((list.first as Map)['id'] as num).toInt();
  });

  /// رسالة من الإدارة إلى كل المشتركين.
  ///
  /// ⚠ ADMIN-ONLY IN THE DATABASE, not here: `send_broadcast` calls
  ///   `require_role('admin')` first, trims, and refuses an empty or over-long
  ///   text with RUL18 — whose Arabic sentence reaches the screen as it is.
  Future<void> sendBroadcast({required String body, String? title}) =>
      SupabaseFailures.guard(() async {
        await _db.rpc<dynamic>(
          'send_broadcast',
          params: <String, dynamic>{
            'p_title': (title == null || title.trim().isEmpty)
                ? null
                : title.trim(),
            'p_body': body,
          },
        );
      });
}
