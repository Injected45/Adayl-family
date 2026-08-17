import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/directory_repository.dart';
import '../domain/models.dart';

final Provider<DirectoryRepository> directoryRepositoryProvider =
    Provider<DirectoryRepository>(
      (Ref ref) => DirectoryRepository(ref.watch(supabaseClientProvider)),
    );

/// Debounced search term, so typing does not fire a request per keystroke.
///
/// One where there were two. The directory used to be two screens with two
/// searches — families by the father's name, members by their own — and they are
/// the same list now.
final StateProvider<String> adeelSearchProvider = StateProvider<String>(
  (Ref ref) => '',
);

/// Empty string means every period.
final StateProvider<String> receivablePeriodProvider = StateProvider<String>(
  (Ref ref) => '',
);

final StateProvider<int?> selectedStatementAdeelProvider = StateProvider<int?>(
  (Ref ref) => null,
);

final FutureProviderFamily<List<AdeelListItem>, String> adeelsProvider =
    FutureProvider.family<List<AdeelListItem>, String>(
      (Ref ref, String query) =>
          ref.watch(directoryRepositoryProvider).adeels(query: query),
    );

final FutureProviderFamily<AdeelDetail, int> adeelDetailProvider =
    FutureProvider.family<AdeelDetail, int>(
      (Ref ref, int id) => ref.watch(directoryRepositoryProvider).adeel(id),
    );

final FutureProviderFamily<Statement, int> statementProvider =
    FutureProvider.family<Statement, int>(
      (Ref ref, int adeelId) =>
          ref.watch(directoryRepositoryProvider).statement(adeelId),
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

/// The association's treasury totals. Watched by the عديل portal's المزيد sheet
/// and by nothing else — staff read the same figures through v_cash_summary,
/// which their RLS lets them see whole.
final FutureProvider<AssociationFinance> associationFinanceProvider =
    FutureProvider<AssociationFinance>(
      (Ref ref) => ref.watch(directoryRepositoryProvider).associationFinance(),
    );
