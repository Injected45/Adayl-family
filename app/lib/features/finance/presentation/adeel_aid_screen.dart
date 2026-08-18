import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// What the association has GIVEN one عديل, over his whole time in it.
///
/// ⚠ THIS IS NOT HIS STATEMENT, AND THE TWO MUST NEVER BE ADDED TOGETHER.
/// الجمعية خيرية: aid paid to a man is not deducted from what he owes. A member
/// given something for a bereavement still owes that month's subscription, and
/// his statement goes on showing the full debt.
///
/// The database makes that structural — a voucher writes no receivable, no
/// payment and no allocation, and `api_adeel_statement` merges exactly those two
/// tables, so aid cannot reach the statement however this screen is written. It
/// is a SEPARATE SCREEN rather than a section of the detail page for the same
/// reason it is a separate call: the place this rule would actually be broken is
/// a layout that puts «ما عليه» and «ما استلمه» in one column and invites the
/// eye to subtract. The note at the top says so in words as well.
///
/// One screen, two readers. Staff open it from an عديل's page and read anybody's;
/// a member reads only his own, because `api_adeel_aid` is SECURITY INVOKER and
/// `read_own_disbursements` is scoped to `payee_adeel_id = my_adeel_id()`. There
/// is no role check here at all — hiding a button is presentation, and the row
/// the server returns is the same either way.
class AdeelAidScreen extends ConsumerWidget {
  const AdeelAidScreen({required this.adeelId, super.key});

  final int adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<AdeelAid> aid = ref.watch(adeelAidProvider(adeelId));

    return AppScaffold(
      title: l.aidTitle,
      currentRoute: AppRoutes.adeels,
      body: (BuildContext context) => AsyncView<AdeelAid>(
        value: aid,
        onRetry: () => ref.invalidate(adeelAidProvider(adeelId)),
        builder: (AdeelAid data) => ListView(
          padding: screenPadding(context),
          children: <Widget>[
            if (data.adeelName.isNotEmpty) ...<Widget>[
              Text(
                data.adeelName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                data.adeelCode,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // The rule, stated before the figures rather than after them. A
            // reader who has just seen "استلم 450" is the one who needs to be
            // told it changes nothing about what he owes.
            const _AidNote(),
            const SizedBox(height: AppSpacing.lg),

            if (data.isEmpty)
              EmptyStateView(icon: Icons.volunteer_activism_outlined,
                  title: l.noAid)
            else ...<Widget>[
              _AidHeadline(aid: data),
              const SizedBox(height: AppSpacing.lg),

              GlassPanel(
                title: l.aidByCategory,
                icon: Icons.donut_small_outlined,
                child: Column(
                  children: <Widget>[
                    for (final ExpenseByCategory c in data.byCategory)
                      _AidRow(
                        label: c.category,
                        trailing: l.aidVoucherCount(c.count),
                        amount: c.total,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Only when there is more than one year to compare. On a member
              // helped once, a single-row "by year" panel restates the headline
              // and says nothing.
              if (data.byYear.length > 1) ...<Widget>[
                GlassPanel(
                  title: l.aidByYear,
                  icon: Icons.calendar_month_outlined,
                  child: Column(
                    children: <Widget>[
                      for (final AidByYear y in data.byYear)
                        _AidRow(
                          label: y.year,
                          trailing: l.aidVoucherCount(y.count),
                          amount: y.total,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              Text(
                l.aidVouchers,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final DisbursementView v in data.vouchers)
                _AidVoucherCard(voucher: v),
            ],
          ],
        ),
      ),
    );
  }
}

/// The headline figure, and the span it covers.
class _AidHeadline extends StatelessWidget {
  const _AidHeadline({required this.aid});

  final AdeelAid aid;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l.aidTotal, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatMoney(aid.total),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              // The association's colour for money LEAVING the treasury, which
              // is what this is from the association's side. It is deliberately
              // not the red that means "owed" anywhere else on the member's
              // screens — nothing here is a debt.
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              StatusBadge.neutral(label: l.aidVoucherCount(aid.count)),
              if (aid.firstAt.isNotEmpty && aid.lastAt.isNotEmpty)
                StatusBadge(
                  label: l.aidPeriod(aid.firstAt, aid.lastAt),
                  tone: AppColors.info,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One label / count / amount line, used by both breakdowns.
class _AidRow extends StatelessWidget {
  const _AidRow({
    required this.label,
    required this.trailing,
    required this.amount,
  });

  final String label;
  final String trailing;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            trailing,
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            formatMoney(amount),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

/// A voucher as the recipient's page shows it: what, when, how much, why.
///
/// Read-only, and narrower than the الصرف tab's card on purpose. Reversing a
/// voucher is a treasury act performed where the treasury is managed; offering
/// it here would put an admin action on a screen a member also reads, and the
/// bank details of a transfer belong to the association's reconciliation rather
/// than to this man's history.
class _AidVoucherCard extends StatelessWidget {
  const _AidVoucherCard({required this.voucher});

  final DisbursementView voucher;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool cancelled = voucher.cancelled;

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
                  voucher.method == PaymentMethodWire.cash
                      ? Icons.payments_outlined
                      : Icons.account_balance_outlined,
                  size: 18,
                  color: cancelled ? AppColors.muted : AppColors.danger,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    voucher.voucherNo,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      // Rule 9: a reversed voucher stays legible and visibly
                      // struck through. Its amount is already out of every
                      // total above, which all filter on status.
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                      color: cancelled ? AppColors.muted : null,
                    ),
                  ),
                ),
                Text(
                  formatMoney(voucher.amount),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cancelled ? AppColors.muted : AppColors.danger,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                StatusBadge.neutral(label: voucher.category),
                StatusBadge(label: voucher.method, tone: AppColors.info),
                if (cancelled)
                  StatusBadge(label: l.voided, tone: AppColors.muted),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _AidLine(
              label: l.disbursementDate,
              value: formatDateTime(voucher.spentAt),
            ),
            if (voucher.handedBy.isNotEmpty)
              _AidLine(label: l.handedBy, value: voucher.handedBy),
            if (voucher.note.isNotEmpty)
              _AidLine(label: l.notesField, value: voucher.note),
          ],
        ),
      ),
    );
  }
}

class _AidLine extends StatelessWidget {
  const _AidLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// The rule, in words, above the figures.
///
/// Not decoration. Every other money screen in this app shows a number that
/// nets against another number, and a reader arriving here with that habit will
/// subtract «ما استلمه» from «ما عليه» unless told plainly that the association
/// does not.
class _AidNote extends StatelessWidget {
  const _AidNote();

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.aidNotDeductedNote,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l.aidCollectiveNote,
            style: const TextStyle(
              fontSize: 11,
              height: 1.5,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
