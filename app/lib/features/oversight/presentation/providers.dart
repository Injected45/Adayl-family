import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/oversight_repository.dart';
import '../domain/models.dart';

final Provider<OversightRepository> oversightRepositoryProvider =
    Provider<OversightRepository>(
      (Ref ref) => OversightRepository(ref.watch(supabaseClientProvider)),
    );

final FutureProvider<DashboardData> dashboardProvider =
    FutureProvider<DashboardData>(
      (Ref ref) => ref.watch(oversightRepositoryProvider).dashboard(),
    );

/// Empty string means every type.
final StateProvider<String> alertTypeProvider = StateProvider<String>(
  (Ref ref) => '',
);

final FutureProviderFamily<List<AlertItem>, String> alertsProvider =
    FutureProvider.family<List<AlertItem>, String>(
      (Ref ref, String type) => ref
          .watch(oversightRepositoryProvider)
          .alerts(type: type.isEmpty ? null : type),
    );

typedef ReportRange = ({String from, String to});

final StateProvider<ReportRange> reportRangeProvider =
    StateProvider<ReportRange>((Ref ref) {
      final DateTime now = DateTime.now();
      return (
        from: '${now.year}-01-01',
        to: now.toIso8601String().substring(0, 10),
      );
    });

final FutureProviderFamily<FinancialReport, ReportRange> reportProvider =
    FutureProvider.family<FinancialReport, ReportRange>(
      (Ref ref, ReportRange range) => ref
          .watch(oversightRepositoryProvider)
          .report(from: range.from, to: range.to),
    );

final StateProvider<String> auditTypeProvider = StateProvider<String>(
  (Ref ref) => '',
);

final FutureProviderFamily<AuditPage, String> auditProvider =
    FutureProvider.family<AuditPage, String>(
      (Ref ref, String type) => ref
          .watch(oversightRepositoryProvider)
          .audit(type: type.isEmpty ? null : type),
    );

final FutureProvider<List<UserAccount>> usersProvider =
    FutureProvider<List<UserAccount>>(
      (Ref ref) => ref.watch(oversightRepositoryProvider).users(),
    );

final FutureProvider<EditableSettings> editableSettingsProvider =
    FutureProvider<EditableSettings>(
      (Ref ref) => ref.watch(oversightRepositoryProvider).settings(),
    );
