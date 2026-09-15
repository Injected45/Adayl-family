import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// قانون الجمعية، على Supabase.
///
/// Reads come from `v_bylaw_pages`; the two writes — a page added, a page
/// removed — go through `add_bylaw_page()` and `delete_bylaw_page()`, both
/// admin-only in the database.
///
/// ⚠ WHO SEES THE PAGES IS NOT DECIDED HERE. `read_bylaw_pages_staff` and
///   `read_bylaw_pages_member` do it, and the member's goes through
///   `my_adeel_id()` — the key, the phone and the login — like every other
///   thing he reads.
class BylawsRepository {
  BylawsRepository(this._db);

  final SupabaseClient _db;

  static const String _view = 'v_bylaw_pages';

  /// The pages in the order they were added — page 1 first.
  Future<List<BylawPage>> list() => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from(_view)
        .select('id,mime,sizeBytes,createdAt')
        .order('id', ascending: true);
    return (rows as List<dynamic>)
        .map(
          (dynamic e) => BylawPage.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
  });

  /// One page's image. The view sends it as base64 with no line breaks.
  Future<Uint8List> image(int id) => SupabaseFailures.guard(() async {
    final dynamic rows = await _db
        .from(_view)
        .select('data')
        .eq('id', id)
        .limit(1);
    final List<dynamic> list = rows as List<dynamic>;
    if (list.isEmpty) return Uint8List(0);
    final String data = (list.first as Map)['data'] as String? ?? '';
    return base64Decode(data);
  });

  Future<void> add(Uint8List bytes, String mime) =>
      SupabaseFailures.guard(() async {
        await _db.rpc<dynamic>(
          'add_bylaw_page',
          params: <String, dynamic>{
            'p_image': base64Encode(bytes),
            'p_mime': mime,
          },
        );
      });

  Future<void> delete(int id) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'delete_bylaw_page',
      params: <String, dynamic>{'p_id': id},
    );
  });
}
