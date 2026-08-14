import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/directory_repository.dart';
import '../domain/models.dart';

final Provider<DirectoryRepository> directoryRepositoryProvider =
    Provider<DirectoryRepository>(
      (Ref ref) => DirectoryRepository(ref.watch(supabaseClientProvider)),
    );

/// Debounced search terms, one per screen, so typing does not fire a request
/// per keystroke.
final StateProvider<String> familySearchProvider = StateProvider<String>(
  (Ref ref) => '',
);
final StateProvider<String> memberSearchProvider = StateProvider<String>(
  (Ref ref) => '',
);

/// Empty string means every period.
final StateProvider<String> receivablePeriodProvider = StateProvider<String>(
  (Ref ref) => '',
);

final StateProvider<int?> selectedStatementFamilyProvider = StateProvider<int?>(
  (Ref ref) => null,
);

final FutureProviderFamily<List<FamilyListItem>, String> familiesProvider =
    FutureProvider.family<List<FamilyListItem>, String>(
      (Ref ref, String query) =>
          ref.watch(directoryRepositoryProvider).families(query: query),
    );

final FutureProviderFamily<FamilyDetail, int> familyDetailProvider =
    FutureProvider.family<FamilyDetail, int>(
      (Ref ref, int id) => ref.watch(directoryRepositoryProvider).family(id),
    );

final FutureProviderFamily<Statement, int> statementProvider =
    FutureProvider.family<Statement, int>(
      (Ref ref, int familyId) =>
          ref.watch(directoryRepositoryProvider).statement(familyId),
    );

final FutureProviderFamily<List<MemberListItem>, String> membersProvider =
    FutureProvider.family<List<MemberListItem>, String>(
      (Ref ref, String query) =>
          ref.watch(directoryRepositoryProvider).members(query: query),
    );

final FutureProviderFamily<ReceivablesPage, String> receivablesProvider =
    FutureProvider.family<ReceivablesPage, String>(
      (Ref ref, String period) =>
          ref.watch(directoryRepositoryProvider).receivables(period: period),
    );

final FutureProvider<AssociationSettingsView> settingsProvider =
    FutureProvider<AssociationSettingsView>(
      (Ref ref) => ref.watch(directoryRepositoryProvider).settings(),
    );

final FutureProvider<List<Official>> officialsProvider =
    FutureProvider<List<Official>>(
      (Ref ref) => ref.watch(directoryRepositoryProvider).officials(),
    );
