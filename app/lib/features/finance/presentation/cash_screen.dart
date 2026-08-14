import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

class CashScreen extends ConsumerWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<CashSummaryView> summary = ref.watch(cashSummaryProvider);
    final AsyncValue<List<CashMovementView>> movements = ref.watch(
      cashMovementsProvider,
    );

    return AppScaffold(
      title: l.navCash,
      currentRoute: AppRoutes.cash,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cashSummaryProvider);
          ref.invalidate(cashMovementsProvider);
        },
        child: ListView(
          padding: screenPadding(context),
          children: <Widget>[
            Text(
              l.cashIntro,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),

            AsyncView<CashSummaryView>(
              value: summary,
              onRetry: () => ref.invalidate(cashSummaryProvider),
              builder: (CashSummaryView data) => StatCardGrid(
                children: <Widget>[
                  _StatCard(
                    label: l.totalCollected,
                    value: formatMoney(data.total),
                    sub: '${l.todayLabel} ${formatMoney(data.today)}',
                  ),
                  _StatCard(
                    label: l.collectedCash,
                    value: formatMoney(data.cash),
                    sub: '${l.thisMonthLabel} ${formatMoney(data.month)}',
                    tone: AppColors.success,
                  ),
                  _StatCard(
                    label: l.collectedTransfer,
                    value: formatMoney(data.transfer),
                    tone: AppColors.info,
                  ),
                  _StatCard(
                    label: l.collectedThisYear,
                    value: formatMoney(data.year),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            Text(
              l.cashMovements,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),

            AsyncView<List<CashMovementView>>(
              value: movements,
              onRetry: () => ref.invalidate(cashMovementsProvider),
              builder: (List<CashMovementView> items) {
                if (items.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.account_balance_wallet_outlined,
                    title: l.noCashMovements,
                  );
                }
                return Column(
                  children: <Widget>[
                    for (final CashMovementView movement in items)
                      _MovementTile(movement: movement),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.sub,
    this.tone,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final Color accent = tone ?? AppColors.brand;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Flat Design's way of carrying meaning: a solid saturated bar,
              // no gradient, no shadow. It also encodes the tone for anyone who
              // cannot distinguish the value's colour, so hue is not the only
              // signal.
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: tone ?? AppColors.ink,
              ),
            ),
          ),
          if (sub != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final CashMovementView movement;

  @override
  Widget build(BuildContext context) {
    final bool voided = movement.status == ReceivableStatusWire.cancelled;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        movement.method == PaymentMethodWire.cash
            ? Icons.payments_outlined
            : Icons.account_balance_outlined,
        color: voided ? AppColors.muted : AppColors.brand,
      ),
      title: Text(
        movement.familyName,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          decoration: voided ? TextDecoration.lineThrough : null,
          color: voided ? AppColors.muted : null,
        ),
      ),
      subtitle: Text(
        '${movement.receiptNo} • ${formatDateTime(movement.occurredAt)}',
        style: const TextStyle(fontSize: 11, color: AppColors.muted),
      ),
      trailing: Text(
        formatMoney(movement.amount),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: voided ? AppColors.muted : AppColors.success,
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}
