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
import 'disbursement_sheet.dart';
import 'payment_sheet.dart';
import 'providers.dart';

/// Which direction of money the screen is showing.
///
/// The screen was «التحصيل والسداد» and listed one thing: money coming IN. It
/// is becoming «العمليات» — both directions — because the association is adding
/// disbursement, and a treasury app in which money can only arrive is not a
/// treasury app.
enum _Ops { collections, disbursements }

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  _Ops _tab = _Ops.collections;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navPayments,
      currentRoute: AppRoutes.payments,
      // The button belongs to the TAB, not to the screen: "تسجيل سداد" on the
      // disbursement tab would take money in while the reader is looking at
      // money going out, which is the one confusion a two-direction screen
      // exists to prevent.
      //
      // The two directions also carry DIFFERENT ranks. Taking money in is the
      // treasurer's; paying it out was put a rung above even the finance
      // manager, at the association's request. Both are re-checked inside the
      // RPC — hiding a button is the third layer, never the only one.
      floatingActionButton: switch (_tab) {
        // ── THE COLOUR IS THE DIRECTION ─────────────────────────────────────
        // Green takes money in, red pays it out, on the tab AND on its button.
        // The two acts are three taps apart on one screen and are opposite in
        // consequence: an admin who means to record a collection and records a
        // disbursement has emptied the fund instead of filling it. Colour is
        // read before the words are, so it carries the distinction first.
        _Ops.collections when role.atLeast(AppRole.treasurer) =>
          FloatingActionButton.extended(
            onPressed: () => showPaymentSheet(context),
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.south_west),
            label: Text(l.registerPayment),
          ),
        _Ops.disbursements when role.atLeast(AppRole.admin) =>
          FloatingActionButton.extended(
            onPressed: () => showDisbursementSheet(context),
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.north_east),
            label: Text(l.registerDisbursement),
          ),
        _ => null,
      },
      body: (BuildContext context) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: SegmentedButton<_Ops>(
              segments: <ButtonSegment<_Ops>>[
                ButtonSegment<_Ops>(
                  value: _Ops.collections,
                  label: Text(
                    l.opsCollections,
                    style: const TextStyle(color: AppColors.success),
                  ),
                  icon: const Icon(
                    Icons.south_west,
                    size: 18,
                    color: AppColors.success,
                  ),
                ),
                ButtonSegment<_Ops>(
                  value: _Ops.disbursements,
                  label: Text(
                    l.opsDisbursements,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                  icon: const Icon(
                    Icons.north_east,
                    size: 18,
                    color: AppColors.danger,
                  ),
                ),
              ],
              selected: <_Ops>{_tab},
              showSelectedIcon: false,
              onSelectionChanged: (Set<_Ops> v) =>
                  setState(() => _tab = v.first),
            ),
          ),
          Expanded(
            child: _tab == _Ops.collections
                ? const _CollectionsTab()
                : const _DisbursementsTab(),
          ),
        ],
      ),
    );
  }
}

class _CollectionsTab extends ConsumerWidget {
  const _CollectionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<PaymentView>> payments = ref.watch(paymentsProvider);
    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    // No AppScaffold here any more: this is a TAB inside one, and nesting a
    // second scaffold would give the screen two app bars and two navigation
    // pills. The bottom inset still comes from the outer scaffold, which
    // publishes it as MediaQuery padding for exactly this reason.
    return AsyncView<List<PaymentView>>(
      value: payments,
      onRetry: () => ref.invalidate(paymentsProvider),
      builder: (List<PaymentView> items) => ListView(
        padding: screenPadding(context),
        children: <Widget>[
          if (items.isEmpty)
            EmptyStateView(icon: Icons.payments_outlined, title: l.noPayments)
          else
            for (final PaymentView payment in items)
              _PaymentCard(payment: payment, role: role),
        ],
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
    ref.invalidate(adeelsProvider(''));
    ref.invalidate(adeelDetailProvider(payment.adeelId));
    ref.invalidate(statementProvider(payment.adeelId));
    messenger.showSnackBar(SnackBar(content: Text(l.paymentCancelled)));
  } on ApiException catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeApiFailure(l, failure))),
    );
  }
}

/// Money OUT: what each heading has cost, then the vouchers themselves.
///
/// The summary sits above the list rather than on its own screen because the
/// two answer one question between them — "what are we spending on, and on
/// what" — and a treasurer who has to navigate to find the second half will
/// read the first half alone and act on it.
class _DisbursementsTab extends ConsumerWidget {
  const _DisbursementsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<DisbursementView>> vouchers = ref.watch(
      disbursementsProvider,
    );
    final AsyncValue<List<ExpenseByCategory>> byCategory = ref.watch(
      expenseByCategoryProvider,
    );
    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AsyncView<List<DisbursementView>>(
      value: vouchers,
      onRetry: () => ref.invalidate(disbursementsProvider),
      builder: (List<DisbursementView> items) => ListView(
        padding: screenPadding(context),
        children: <Widget>[
          // ── What each heading has cost ───────────────────────────────────
          // Headings with nothing against them are DROPPED here, unlike in the
          // view behind it: a report page states the zero, a summary strip on a
          // phone that listed nine headings to say eight of them are empty
          // would bury the one that is not.
          byCategory.when(
            loading: () => const SizedBox.shrink(),
            error: (Object e, StackTrace _) => const SizedBox.shrink(),
            data: (List<ExpenseByCategory> rows) {
              final List<ExpenseByCategory> spent = rows
                  .where((ExpenseByCategory r) => !r.isEmpty)
                  .toList();
              if (spent.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  GlassPanel(
                    title: l.expenseByCategory,
                    icon: Icons.donut_small_outlined,
                    child: Column(
                      children: <Widget>[
                        for (final ExpenseByCategory r in spent)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    r.category,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  formatMoney(r.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              );
            },
          ),

          if (items.isEmpty)
            EmptyStateView(
              icon: Icons.north_east,
              title: l.noDisbursements,
            )
          else
            for (final DisbursementView v in items)
              _VoucherCard(voucher: v, role: role),
        ],
      ),
    );
  }
}


/// A voucher: WHO and HOW MUCH on the face of it, the rest on a tap.
///
/// It used to open flat — voucher number, heading, method, payee, date, handed
/// by, reference, bank, note, and a reversal button — eight lines per row on a
/// phone, so four vouchers filled the screen and the list stopped being a list.
///
/// What a reader scans for is «أيمن صالح — 150.00»: to whom, and how much. The
/// rest is what he wants about ONE of them, and it opens under the row he taps.
class _VoucherCard extends ConsumerStatefulWidget {
  const _VoucherCard({required this.voucher, required this.role});

  final DisbursementView voucher;
  final AppRole role;

  @override
  ConsumerState<_VoucherCard> createState() => _VoucherCardState();
}

class _VoucherCardState extends ConsumerState<_VoucherCard> {
  bool _open = false;

  Future<void> _cancel(BuildContext context, L l) async {
    // Resolved BEFORE the await, like the payment card's own cancel: the
    // context may be gone by the time the dialog closes, and a messenger
    // fetched afterwards is the classic use-after-dispose in this codebase.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final String? reason = await showTextPrompt(
      context,
      title: l.cancelDisbursement,
      message: l.cancelDisbursementWarning,
      fieldLabel: l.cancelReason,
      hintText: l.cancelReasonHint,
      confirmLabel: l.confirmCancel,
      cancelLabel: l.cancel,
      destructive: true,
    );
    if (reason == null || reason.trim().isEmpty) return;

    try {
      await ref
          .read(financeRepositoryProvider)
          .cancelDisbursement(widget.voucher.id, reason.trim());
      ref
        ..invalidate(disbursementsProvider)
        ..invalidate(expenseByCategoryProvider)
        ..invalidate(cashSummaryProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.disbursementCancelled)));
    } on ApiException catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiFailure(l, failure))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final DisbursementView v = widget.voucher;
    final bool cancelled = v.cancelled;

    // WHO the money went to. A collective voucher is attributed to nobody by
    // the association's own decision, so its heading stands in that place —
    // «فطور رمضان» is as complete an answer to "who was this for" as a name is.
    final String who = v.payeeName.isNotEmpty ? v.payeeName : v.category;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      who,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        // Rule 9: a voided voucher stays legible and visibly
                        // struck through. Its amount is already out of every
                        // total, because they all filter on status.
                        decoration: cancelled
                            ? TextDecoration.lineThrough
                            : null,
                        color: cancelled ? AppColors.muted : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    formatMoney(v.amount),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: cancelled ? AppColors.muted : AppColors.danger,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),

              if (_open) ...<Widget>[
                const Divider(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    StatusBadge.neutral(label: v.category),
                    StatusBadge(label: v.method, tone: AppColors.info),
                    if (cancelled)
                      StatusBadge(label: l.voided, tone: AppColors.muted),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _VoucherLine(label: l.voucherNo, value: v.voucherNo),
                if (v.payeeName.isNotEmpty)
                  _VoucherLine(label: l.payee, value: v.payeeName),
                if (v.payeeCode.isNotEmpty)
                  _VoucherLine(label: l.receiptNo, value: v.payeeCode),
                _VoucherLine(
                  label: l.disbursementDate,
                  value: formatDateTime(v.spentAt),
                ),
                if (v.handedBy.isNotEmpty)
                  _VoucherLine(label: l.handedBy, value: v.handedBy),
                if (v.reference.isNotEmpty)
                  _VoucherLine(label: l.reference, value: v.reference),
                if (v.bankName.isNotEmpty)
                  _VoucherLine(label: l.bankNameField, value: v.bankName),
                if (v.bankAccountNo.isNotEmpty)
                  _VoucherLine(
                    label: l.bankAccountNoField,
                    value: v.bankAccountNo,
                  ),
                if (v.note.isNotEmpty)
                  _VoucherLine(label: l.notesField, value: v.note),

                if (!cancelled && widget.role.atLeast(AppRole.admin)) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => _cancel(context, l),
                      icon: const Icon(Icons.undo, size: 18),
                      label: Text(l.cancelDisbursement),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _VoucherLine extends StatelessWidget {
  const _VoucherLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    ),
  );
}
