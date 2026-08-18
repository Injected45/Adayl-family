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

/// Every voucher, newest first. Invalidated after a disbursement is recorded or
/// cancelled, alongside the treasury summary it moves.
final FutureProvider<List<DisbursementView>> disbursementsProvider =
    FutureProvider<List<DisbursementView>>(
      (Ref ref) => ref.watch(financeRepositoryProvider).disbursements(),
    );

/// What each heading has cost. The reason the category is a fixed enum: this is
/// the question a free-text field could not answer.
final FutureProvider<List<ExpenseByCategory>> expenseByCategoryProvider =
    FutureProvider<List<ExpenseByCategory>>(
      (Ref ref) => ref.watch(financeRepositoryProvider).expenseByCategory(),
    );

/// What the association has given ONE man. A family, keyed by his id, so the
/// staff page and the member's own page are the same provider reading the same
/// RPC — and RLS, not the argument, is what decides who gets an answer.
///
/// Invalidated alongside [disbursementsProvider] wherever a voucher is recorded
/// or reversed: a member's page must not go on showing aid that was cancelled a
/// screen away.
final FutureProviderFamily<AdeelAid, int> adeelAidProvider =
    FutureProvider.family<AdeelAid, int>(
      (Ref ref, int adeelId) =>
          ref.watch(financeRepositoryProvider).adeelAid(adeelId),
    );
