import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/finance_repository.dart';
import '../domain/models.dart';

final Provider<FinanceRepository> financeRepositoryProvider =
    Provider<FinanceRepository>(
      (Ref ref) => FinanceRepository(ref.watch(supabaseClientProvider)),
    );

final FutureProvider<List<PaymentView>> paymentsProvider =
    FutureProvider<List<PaymentView>>(
      (Ref ref) => ref.watch(financeRepositoryProvider).payments(),
    );

final FutureProvider<CashSummaryView> cashSummaryProvider =
    FutureProvider<CashSummaryView>(
      (Ref ref) => ref.watch(financeRepositoryProvider).cashSummary(),
    );

final FutureProvider<List<CashMovementView>> cashMovementsProvider =
    FutureProvider<List<CashMovementView>>(
      (Ref ref) => ref.watch(financeRepositoryProvider).cashMovements(),
    );

/// The months the close-month button offers. Invalidated after a month is
/// closed, so the picker's `closed`/`selectable` flags stay honest.
final FutureProvider<List<ClosablePeriod>> closablePeriodsProvider =
    FutureProvider<List<ClosablePeriod>>(
      (Ref ref) => ref.watch(financeRepositoryProvider).closablePeriods(),
    );
