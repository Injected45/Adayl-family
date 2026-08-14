import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/text_prompt_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../directory/presentation/providers.dart';
import '../domain/models.dart';
import 'payment_sheet.dart';
import 'providers.dart';

class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<PaymentView>> payments = ref.watch(paymentsProvider);
    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navPayments,
      currentRoute: AppRoutes.payments,
      // A treasurer may take money; a viewer may not.
      floatingActionButton: role.atLeast(AppRole.treasurer)
          ? FloatingActionButton.extended(
              onPressed: () => showPaymentSheet(context),
              icon: const Icon(Icons.add),
              label: Text(l.registerPayment),
            )
          : null,
      body: AsyncView<List<PaymentView>>(
        value: payments,
        onRetry: () => ref.invalidate(paymentsProvider),
        builder: (List<PaymentView> items) => ListView(
          padding: screenPadding(context),
          children: <Widget>[
            // The FIFO rule must be visible, not implicit — index.html:597.
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.infoSoft,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Text(
                l.paymentsIntro,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF1E3A8A),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (items.isEmpty)
              EmptyStateView(icon: Icons.payments_outlined, title: l.noPayments)
            else
              for (final PaymentView payment in items)
                _PaymentCard(payment: payment, role: role),
            const SizedBox(height: 72),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends ConsumerWidget {
  const _PaymentCard({required this.payment, required this.role});

  final PaymentView payment;
  final AppRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final bool cancelled = payment.status == ReceivableStatusWire.cancelled;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  payment.method == PaymentMethodWire.cash
                      ? Icons.payments_outlined
                      : Icons.account_balance_outlined,
                  size: 18,
                  color: cancelled ? AppColors.muted : AppColors.brand,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    payment.receiptNo,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      // Voided rows stay legible but visibly struck through;
                      // rule 9 requires them present, not hidden.
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                      color: cancelled ? AppColors.muted : null,
                    ),
                  ),
                ),
                Text(
                  formatMoney(payment.amount),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cancelled ? AppColors.muted : AppColors.success,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  formatDateTime(payment.paidAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                StatusBadge(
                  label: payment.status,
                  tone: cancelled ? AppColors.muted : AppColors.success,
                ),
              ],
            ),
            if (payment.allocations.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              LabelledValue(
                label: l.allocation,
                value: payment.allocations
                    .map(
                      (PaymentAllocationView a) =>
                          '${a.period}: ${formatMoney(a.amount)}',
                    )
                    .join(ArabicPunctuation.listSeparator),
              ),
            ],
            if (!cancelled && role.atLeast(AppRole.financeManager)) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () => _confirmCancel(context, ref, l, payment),
                  icon: const Icon(Icons.undo, size: 16),
                  label: Text(l.cancelAndReverse),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmCancel(
  BuildContext context,
  WidgetRef ref,
  L l,
  PaymentView payment,
) async {
  // Captured before the dialog await, while the context is still valid.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final String? text = await showTextPrompt(
    context,
    title: l.cancelAndReverse,
    message: l.cancelPaymentWarning,
    fieldLabel: l.cancelReason,
    hintText: l.cancelReasonHint,
    confirmLabel: l.confirmCancel,
    cancelLabel: l.cancel,
    destructive: true,
  );

  if (text == null || text.isEmpty) return;

  try {
    await ref
        .read(financeRepositoryProvider)
        .cancelPayment(paymentId: payment.id, reason: text);
    ref.invalidate(paymentsProvider);
    ref.invalidate(cashSummaryProvider);
    ref.invalidate(cashMovementsProvider);
    ref.invalidate(familiesProvider(''));
    ref.invalidate(familyDetailProvider(payment.familyId));
    ref.invalidate(statementProvider(payment.familyId));
    messenger.showSnackBar(SnackBar(content: Text(l.paymentCancelled)));
  } on ApiException catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeApiFailure(l, failure))),
    );
  }
}
