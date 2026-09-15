import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/bylaws_repository.dart';
import '../data/page_picker.dart';
import '../domain/models.dart';

final Provider<BylawsRepository> bylawsRepositoryProvider =
    Provider<BylawsRepository>(
      (Ref ref) => BylawsRepository(ref.watch(supabaseClientProvider)),
    );

final Provider<PagePicker> pagePickerProvider = Provider<PagePicker>(
  (Ref ref) => const PagePicker(),
);

/// The pages, first to last. In `refreshAll`, so a page the admin adds reaches
/// a member's open screen on the next sweep.
final FutureProvider<List<BylawPage>> bylawPagesProvider =
    FutureProvider<List<BylawPage>>(
      (Ref ref) => ref.watch(bylawsRepositoryProvider).list(),
    );

/// One page's image, by id.
///
/// ⚠ KEPT FOR THE SESSION AND NEVER SWEPT, because it cannot go stale: a page
///   is added or deleted, never edited, so the bytes behind an id never
///   change. Sweeping it would re-download every page a member has already
///   read, every forty-five seconds, to learn nothing.
final FutureProviderFamily<Uint8List, int> bylawImageProvider =
    FutureProvider.family<Uint8List, int>(
      (Ref ref, int id) => ref.watch(bylawsRepositoryProvider).image(id),
    );
