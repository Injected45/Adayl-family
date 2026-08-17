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
      body: (BuildContext context) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cashSummaryProvider);
          ref.invalidate(cashMovementsProvider);
        },
        child: ListView(
          // The RefreshIndicator above needs a scrollable that always accepts
          // the gesture, or an empty treasury cannot be pulled to refresh.
          physics: const AlwaysScrollableScrollPhysics(),
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
              // ── Money in, then money out there, then where it all stands ───
              // The order is the reading order of the answer: what came in as
              // cash, what came in by transfer, what has NOT come in, and the
              // association's position last, because it is the conclusion of
              // the three above it rather than a fourth fact.
              //
              // "تحصيل السنة" is gone. On an association in its first year it
              // was the SAME NUMBER as the total collected — two tiles side by
              // side showing one figure, with nothing to tell a reader they
              // were not disagreeing. What replaced it is the thing the screen
              // could not answer at all: what is still owed.
              builder: (CashSummaryView data) => StatCardGrid(
                children: <Widget>[
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
                    label: l.dueFromMembers,
                    value: formatMoney(data.outstanding),
                    tone: AppColors.danger,
                  ),
                  // ── COLLECTED is not the same as HELD ────────────────────
                  // This tile showed `total` — everything ever collected —
                  // which was true only while money could not leave. Now that
                  // it can, the two differ by exactly what has been disbursed,
                  // and calling the first one "the association's balance" would
                  // overstate the fund by every voucher ever written.
                  //
                  // The subtitle carries what went out, so the difference is
                  // visible on the same tile rather than inferred from two.
                  _StatCard(
                    label: l.associationBalance,
                    value: formatMoney(data.balance),
                    sub: '${l.totalDisbursed} ${formatMoney(data.disbursed)}',
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
                    for (final _AdeelMovements group in _groupByAdeel(items))
                      _AdeelGroup(group: group),
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

/// One subscriber's receipts, gathered.
///
/// The treasury list used to be one row PER RECEIPT, so a member who paid five
/// times appeared five times, and a register of forty men with a year of
/// collections behind it was hundreds of rows of repeated names. The list is now
/// at most as long as the register, and every receipt lives inside the name it
/// belongs to.
class _AdeelMovements {
  _AdeelMovements(this.adeelId, this.adeelName, this.adeelCode);

  final int adeelId;
  final String adeelName;
  final String adeelCode;
  final List<CashMovementView> movements = <CashMovementView>[];

  /// Cancelled receipts are EXCLUDED from the total and still listed inside.
  ///
  /// Rule 9 keeps a voided receipt visible for ever — it is history, not a
  /// mistake to be hidden — but a struck-through 200 must not be added to the
  /// money the association holds. Summed as text→double at the display edge
  /// only, which is where every other total on this screen is already read.
  String get total {
    double sum = 0;
    for (final CashMovementView m in movements) {
      if (m.status == ReceivableStatusWire.cancelled) continue;
      sum += double.tryParse(m.amount) ?? 0;
    }
    return sum.toStringAsFixed(2);
  }

  int get liveCount => movements
      .where((CashMovementView m) => m.status != ReceivableStatusWire.cancelled)
      .length;
}

/// Grouped by `adeelId`, deliberately NOT by name.
///
/// The register has no natural key — CLAUDE.md is explicit that a second row for
/// the same man is accepted — so two subscribers can carry the same spelling.
/// Folding on the name would put two people's money under one heading and add
/// it up, which is the one mistake a treasury screen must not make.
///
/// Insertion order is preserved, so the man with the most recent receipt stays
/// at the top: the list arrives newest-first from the server and grouping does
/// not re-sort it.
List<_AdeelMovements> _groupByAdeel(List<CashMovementView> items) {
  final Map<int, _AdeelMovements> byAdeel = <int, _AdeelMovements>{};
  for (final CashMovementView m in items) {
    byAdeel
        .putIfAbsent(
          m.adeelId,
          () => _AdeelMovements(m.adeelId, m.adeelName, m.adeelCode),
        )
        .movements
        .add(m);
  }
  return byAdeel.values.toList();
}

class _AdeelGroup extends StatelessWidget {
  const _AdeelGroup({required this.group});

  final _AdeelMovements group;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      padding: EdgeInsets.zero,
      child: Theme(
        // Without this the ExpansionTile's own divider draws inside the card and
        // it reads as two stacked cards.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          title: Text(
            group.adeelName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          // The code, and how many receipts are folded in. The count is what
          // tells a reader there is anything to open at all.
          subtitle: Text(
            '${group.adeelCode} • ${l.receiptCount(group.liveCount)}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          // His total sits on the closed row, so the screen answers "how much
          // has this man paid the association" without being opened.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                formatMoney(group.total),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.expand_more, size: 20, color: AppColors.muted),
            ],
          ),
          children: <Widget>[
            for (final CashMovementView movement in group.movements)
              _MovementTile(movement: movement),
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
      // The RECEIPT leads, not the name — the name is the heading this tile
      // now sits under, and repeating it on every line is exactly the crowding
      // the grouping removed.
      title: Text(
        movement.receiptNo,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          decoration: voided ? TextDecoration.lineThrough : null,
          color: voided ? AppColors.muted : null,
        ),
      ),
      subtitle: Text(
        formatDateTime(movement.occurredAt),
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
