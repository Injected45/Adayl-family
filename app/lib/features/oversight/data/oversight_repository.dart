import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// Oversight and administration, on Supabase.
class OversightRepository {
  OversightRepository(this._db);

  final SupabaseClient _db;

  static Map<String, dynamic> _obj(dynamic value) =>
      (value as Map).cast<String, dynamic>();

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List<dynamic>).map(_obj).toList();

  Future<DashboardData> dashboard() => SupabaseFailures.guard(() async {
    final dynamic payload = await _db.rpc<dynamic>('api_dashboard');
    return DashboardData.fromJson(_obj(payload));
  });

  Future<List<AlertItem>> alerts({String? type}) => SupabaseFailures.guard(
    () async {
      final dynamic payload = await _db.rpc<dynamic>('api_alerts');
      final List<AlertItem> all = (payload as List<dynamic>)
          .map((dynamic e) => AlertItem.fromJson(_obj(e)))
          .toList();
      // Filtered here rather than in SQL: the whole list is a handful of rows,
      // and a `p_type` parameter would be a second code path to keep in step
      // with the three types the function emits.
      if (type == null || type.isEmpty) return all;
      return all.where((AlertItem a) => a.type == type).toList();
    },
  );

  Future<FinancialReport> report({required String from, required String to}) =>
      SupabaseFailures.guard(() async {
        final dynamic payload = await _db.rpc<dynamic>(
          'api_financial_report',
          params: <String, dynamic>{'p_from': from, 'p_to': to},
        );
        return FinancialReport.fromJson(_obj(payload));
      });

  Future<AuditPage> audit({
    String? type,
    int page = 1,
  }) => SupabaseFailures.guard(() async {
    const int pageSize = 100;
    final int offset = (page - 1) * pageSize;

    final PostgrestFilterBuilder<dynamic> base = _db
        .from('v_audit')
        // count: exact gives the total alongside the page, so the screen can
        // show "showing 100 of 4,213" without a second query.
        .select()
        .setHeader('Prefer', 'count=exact');
    final dynamic rows = (type == null || type.isEmpty)
        ? await base
              .order('occurredAt', ascending: false)
              .range(offset, offset + pageSize - 1)
        : await base
              .eq('eventType', type)
              .order('occurredAt', ascending: false)
              .range(offset, offset + pageSize - 1);

    final List<Map<String, dynamic>> items = _rows(rows);

    // The event-type filter list. Read separately and unpaged, because the
    // types present in page 1 are not the types present in the table.
    final dynamic typeRows = await _db.from('v_audit').select('eventType');
    final List<String> types =
        _rows(typeRows)
            .map((Map<String, dynamic> r) => r['eventType'] as String)
            .toSet()
            .toList()
          ..sort();

    return AuditPage(
      items: items.map(AuditEntry.fromJson).toList(),
      total: items.length,
      eventTypes: types,
    );
  });

  Future<List<UserAccount>> users() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db.from('v_users').select().order('email');
    return _rows(rows).map(UserAccount.fromJson).toList();
  });

  /// `role` and `status` are WIRE strings, matching what the screen's radio
  /// groups hold and what set_user_access expects for its enum parameters.
  Future<void> updateUser({
    required String userId,
    String? role,
    String? status,
  }) => SupabaseFailures.guard(() async {
    // Through the RPC, never a direct UPDATE on profiles: the self-elevation and
    // last-admin guards live in trg_profiles_guard, and `authenticated` holds no
    // UPDATE privilege on the table at all.
    await _db.rpc<dynamic>(
      'set_user_access',
      params: <String, dynamic>{
        'p_user_id': userId,
        'p_role': role,
        'p_status': status,
      },
    );
  });

  Future<EditableSettings> settings() => SupabaseFailures.guard(() async {
    final dynamic payload = await _db.rpc<dynamic>('api_settings');
    return EditableSettings.fromJson(_obj(payload));
  });

  Future<List<String>> saveSettings(
    EditableSettings settings,
  ) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'update_settings',
      params: <String, dynamic>{'p_patch': settings.toJson()},
    );
    // The Node route returned a list of changed field names for the audit
    // toast. Postgres writes its own audit entry instead, and reconstructing
    // the diff on the client would mean reading the old values first — a race
    // for a cosmetic list. The caller treats an empty list as "saved".
    return const <String>[];
  });

  /// Erases every receivable, payment, allocation, cash movement and audit
  /// entry. Families, members, settings and accounts survive.
  ///
  /// `confirm` must be [PurgeWire.confirmPhrase] verbatim — the function checks
  /// it server-side and raises RUL13 otherwise, so the dialog's own check is a
  /// courtesy, not the gate. Same reasoning as every role check in the app.
  Future<PurgeResult> purgeFinancialData({required String confirm}) =>
      SupabaseFailures.guard(() async {
        final dynamic payload = await _db.rpc<dynamic>(
          'purge_financial_data',
          params: <String, dynamic>{'p_confirm': confirm},
        );
        return PurgeResult.fromJson(_obj(payload));
      });

  /// Erases the directory as well: families, members, and — because every
  /// receivable and receipt references a family with ON DELETE RESTRICT — the
  /// financial tables too. A superset of [purgeFinancialData], never a
  /// narrower cousin of it.
  ///
  /// `confirm` must be [PurgeWire.confirmPhraseAll], which the financial
  /// phrase deliberately does not satisfy.
  Future<PurgeResult> purgeAllData({required String confirm}) =>
      SupabaseFailures.guard(() async {
        final dynamic payload = await _db.rpc<dynamic>(
          'purge_all_data',
          params: <String, dynamic>{'p_confirm': confirm},
        );
        return PurgeResult.fromJson(_obj(payload));
      });

  Future<int> createFamily({
    required MemberInput father,
    required List<MemberInput> sons,
  }) => SupabaseFailures.guard(() async {
    final dynamic result = await _db.rpc<dynamic>(
      'save_family',
      params: <String, dynamic>{
        'p_family_id': null,
        'p_father': father.toJson(),
        'p_sons': sons.map((MemberInput s) => s.toJson()).toList(),
      },
    );
    return (_obj(result)['familyId'] as num).toInt();
  });

  Future<void> updateFamily({
    required int familyId,
    required MemberInput father,
    required List<MemberInput> sons,
  }) => SupabaseFailures.guard(() async {
    // One call for the father, every son, and every removal. The remove-then-
    // insert ordering that lets a departed son's national ID be reused lives
    // inside save_family, in the same transaction — which is where it has to be,
    // because doing it as separate client calls is exactly how that bug appeared
    // the first time.
    await _db.rpc<dynamic>(
      'save_family',
      params: <String, dynamic>{
        'p_family_id': familyId,
        'p_father': father.toJson(),
        'p_sons': sons.map((MemberInput s) => s.toJson()).toList(),
      },
    );
  });
}
