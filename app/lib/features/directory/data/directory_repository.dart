import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// The read side, on Supabase.
///
/// Two mechanisms, and the split is deliberate:
///
///   Flat lists come straight from a `v_*` VIEW. PostgREST filters, orders and
///   limits them, so there is no query-building RPC to keep in step with the UI.
///
///   Nested shapes come from an `api_*` FUNCTION returning jsonb. Family detail
///   wraps family/father/sons/kpis and the statement needs a running balance
///   established over an ordered merge — neither is expressible as a flat row.
///
/// EVERY read goes through a `v_*` view or an `api_*` function and NEVER through a
/// base table. That is not style: the views cast money to text, and a base table
/// returns `numeric`, which `dart:convert` decodes to `double`. Reading
/// `receivables` instead of `v_receivables` would silently put the treasury on
/// binary floating point. `tool/supabase_lint.dart` enforces it.
class DirectoryRepository {
  DirectoryRepository(this._db);

  final SupabaseClient _db;

  static Map<String, dynamic> _obj(dynamic value) =>
      (value as Map).cast<String, dynamic>();

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List<dynamic>).map(_obj).toList();

  Future<AssociationSettingsView> settings() =>
      SupabaseFailures.guard(() async {
        final dynamic row = await _db.from('v_settings').select().single();
        return AssociationSettingsView.fromJson(_obj(row));
      });

  Future<List<Official>> officials() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db.from('v_officials').select();
    return _rows(rows).map(Official.fromJson).toList();
  });

  Future<List<FamilyListItem>> families({
    String query = '',
  }) => SupabaseFailures.guard(() async {
    // The search covers the father's name, his national ID and the family
    // code, which is what the Node route's LIKE clause covered. `or` takes
    // PostgREST filter syntax, so the pattern is interpolated — safe because
    // the value never reaches SQL as code, but commas and parentheses would
    // break the filter grammar, so they are stripped.
    final String safe = query.replaceAll(RegExp(r'[(),*]'), ' ').trim();
    final PostgrestFilterBuilder<dynamic> base = _db
        .from('v_families')
        .select();
    final dynamic rows = safe.isEmpty
        ? await base.order('id')
        : await base
              .or(
                'fatherName.ilike.%$safe%,'
                'fatherNationalId.ilike.%$safe%,'
                'familyCode.ilike.%$safe%',
              )
              .order('id');
    return _rows(rows).map(FamilyListItem.fromJson).toList();
  });

  Future<FamilyDetail> family(int id) => SupabaseFailures.guard(() async {
    final dynamic payload = await _db.rpc<dynamic>(
      'api_family_detail',
      params: <String, dynamic>{'p_family_id': id},
    );
    if (payload == null) {
      // The function returns NULL for a family the caller cannot see, which is
      // what RLS produces for an unapproved account — distinct from an error.
      throw const ApiExceptionNotFound();
    }
    return FamilyDetail.fromJson(_obj(payload));
  });

  Future<Statement> statement(int familyId) => SupabaseFailures.guard(() async {
    final dynamic payload = await _db.rpc<dynamic>(
      'api_family_statement',
      params: <String, dynamic>{'p_family_id': familyId},
    );
    final Map<String, dynamic> body = _obj(payload);
    return Statement(
      movements: (body['movements'] as List<dynamic>)
          .map((dynamic e) => StatementMovement.fromJson(_obj(e)))
          .toList(),
      closingBalance: body['closingBalance'] as String? ?? '0.00',
    );
  });

  Future<List<MemberListItem>> members({String query = ''}) =>
      SupabaseFailures.guard(() async {
        final String safe = query.replaceAll(RegExp(r'[(),*]'), ' ').trim();
        final PostgrestFilterBuilder<dynamic> base = _db
            .from('v_members')
            .select();
        final dynamic rows = safe.isEmpty
            ? await base.order('id')
            : await base
                  .or(
                    'fullName.ilike.%$safe%,'
                    'nationalId.ilike.%$safe%,'
                    'familyName.ilike.%$safe%',
                  )
                  .order('id');
        return _rows(rows).map(MemberListItem.fromJson).toList();
      });

  Future<ReceivablesPage> receivables({String? period}) =>
      SupabaseFailures.guard(() async {
        // One call, not a list read plus a separate SUM: the summary has to be
        // computed over the SAME filter as the items, or a client that filters
        // the list one way and the totals another shows figures that do not add
        // up to the rows beneath them.
        final dynamic payload = await _db.rpc<dynamic>(
          'api_receivables',
          params: <String, dynamic>{'p_period': period},
        );
        final Map<String, dynamic> body = _obj(payload);
        return ReceivablesPage(
          items: (body['items'] as List<dynamic>)
              .map((dynamic e) => ReceivableItem.fromJson(_obj(e)))
              .toList(),
          summary: ReceivablesSummary.fromJson(_obj(body['summary'])),
        );
      });

  /// Generates a fresh access code for a family and returns it in plaintext,
  /// once — the admin then sends it to the head of family himself.
  ///
  /// Admin-only server-side. The screen hides the button for everyone else, so
  /// the refusal never has to be explained to a finance manager who could not
  /// have known.
  ///
  /// Issuing REVOKES the family's previous code — there is one row per family
  /// and it is overwritten — but it does NOT sign out a head of family who has
  /// already redeemed one, because by then the binding lives on his profile.
  /// So an admin can reissue freely when a message is lost.
  Future<String> issueFamilyCode(int familyId) =>
      SupabaseFailures.guard(() async {
        final dynamic payload = await _db.rpc<dynamic>(
          'issue_family_code',
          params: <String, dynamic>{'p_family_id': familyId},
        );
        return _obj(payload)['code'] as String;
      });
}

/// Raised when a read returns nothing for an id the caller asked for by name.
///
/// Distinct from an empty list: a missing family is either gone or invisible to
/// this role, and both should land on the same "not found" screen rather than an
/// empty detail page that looks like a loading bug.
class ApiExceptionNotFound implements Exception {
  const ApiExceptionNotFound();

  @override
  String toString() => 'ApiExceptionNotFound';
}
