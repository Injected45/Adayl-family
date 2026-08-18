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
          // The outgoing side refreshes with the incoming one. A pull that
          // reloaded half the page would leave the balance tile disagreeing
          // with the vouchers listed under it.
          ref.invalidate(disbursementsProvider);
        },
        child: ListView(
          // The RefreshIndicator above needs a scrollable that always accepts
          // the gesture, or an empty treasury cannot be pulled to refresh.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: screenPadding(context),
          children: <Widget>[
            AsyncView<CashSummaryView>(
              value: summary,
              onRetry: () => ref.invalidate(cashSummaryProvider),
              // ── ONE figure, and the workings a tap away ─────────────────
              // This was a grid of four tiles: cash in, transfers in, what is
              // still owed, and the balance. Four squares of equal weight, on a
              // phone, above a list — and only one of them answers the question
              // the page is opened for. The other three are how that answer was
              // arrived at, which is a different question and is only asked
              // afterwards.
              //
              // So the balance takes the width and the workings move into a
              // sheet behind it. Nothing is lost: every label the association
              // named is still there, under the same words, one tap down.
              builder: (CashSummaryView data) => _BalanceBar(summary: data),
            ),

            const SizedBox(height: AppSpacing.xl),
            Text(
              l.cashMovements,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── MONEY IN ─────────────────────────────────────────────────
            // Unchanged: grouped by عديل, because one man paying five times
            // used to be five rows and a register of forty was hundreds.
            Text(
              l.opsCollections,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
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

            // ── MONEY OUT, on the same screen and in the same shape ──────
            // The treasury is one fund and this is the page that describes it,
            // so leaving the outgoing side on another screen made this one
            // answer half its own question — the balance tile above already
            // subtracts what went out, and until now nothing here showed WHAT.
            //
            // NOT grouped by عديل, and that is not an omission: a collective
            // voucher is attributed to nobody (فطور رمضان belongs to everyone),
            // so the key the collections group on does not exist for half these
            // rows. They run newest-first, which is the order they were entered
            // and the order a treasurer reconciles in.
            //
            // ⚠ RED, THROUGHOUT, and it is the whole point of showing them
            //   here: on a page where every other figure is money arriving, an
            //   outgoing amount in the same green would be read as a second
            //   collection. Colour carries the direction before the number is
            //   read at all.
            const SizedBox(height: AppSpacing.lg),
            Text(
              l.opsDisbursements,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AsyncView<List<DisbursementView>>(
              value: ref.watch(disbursementsProvider),
              onRetry: () => ref.invalidate(disbursementsProvider),
              builder: (List<DisbursementView> vouchers) {
                if (vouchers.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.north_east,
                    title: l.noDisbursements,
                  );
                }
                return GlassCard(
                  margin: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.sm,
                  ),
                  child: Column(
                    children: <Widget>[
                      for (final DisbursementView v in vouchers)
                        _VoucherTile(voucher: v),
                    ],
                  ),
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

/// A voucher on the treasury page: money LEAVING, in red.
///
/// The same shape as [_MovementTile] on purpose — icon, reference, date,
/// amount — so a reader scans one list, not two layouts. What differs is the
/// colour and the subtitle: a receipt is identified by whose it is, and a
/// voucher by what it was FOR, which is the heading the association chose from
/// its own fixed six.
class _VoucherTile extends StatelessWidget {
  const _VoucherTile({required this.voucher});

  final DisbursementView voucher;

  @override
  Widget build(BuildContext context) {
    final bool voided = voucher.cancelled;
    // The colour is the direction. Muted when reversed, because a cancelled
    // voucher moved nothing and reading it as red spending would overstate what
    // left the fund.
    final Color tone = voided ? AppColors.muted : AppColors.danger;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        voucher.method == PaymentMethodWire.cash
            ? Icons.payments_outlined
            : Icons.account_balance_outlined,
        color: tone,
      ),
      title: Text(
        voucher.voucherNo,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          // Rule 9: a reversed voucher stays legible and visibly struck
          // through. Its amount is already out of every total on this page,
          // because they all filter on status.
          decoration: voided ? TextDecoration.lineThrough : null,
          color: voided ? AppColors.muted : null,
        ),
      ),
      subtitle: Text(
        // The heading, then whose it was when it belongs to somebody. A
        // collective voucher carries no payee at all, so the ' — ' is dropped
        // with it rather than left dangling.
        <String>[
          voucher.category,
          if (voucher.payeeName.isNotEmpty) voucher.payeeName,
          formatDateTime(voucher.spentAt),
        ].join(' • '),
        style: const TextStyle(fontSize: 11, color: AppColors.muted),
      ),
      trailing: Text(
        formatMoney(voucher.amount),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: tone,
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

/// رصيد الجمعية, across the width — and the workings behind it.
///
/// The four tiles this replaces were equal in weight and unequal in importance.
/// A treasurer opens this page to learn ONE thing: what the association holds
/// today. What it collected in cash, what came by transfer and what is still
/// owed are the arithmetic behind that figure — read afterwards, if at all, and
/// never at a glance.
///
/// So the answer takes the width and the workings move one tap down. Every label
/// the association named survives, under the same words.
class _BalanceBar extends StatelessWidget {
  const _BalanceBar({required this.summary});

  final CashSummaryView summary;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showTreasuryBreakdown(context, summary),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      l.associationBalance,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      formatMoney(summary.balance),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // ── COLLECTED is not the same as HELD ─────────────────
                    // This figure used to be `total` — everything ever
                    // collected — which was true only while money could not
                    // leave. The two now differ by exactly what has been
                    // disbursed, and the subtitle carries that difference on
                    // the same line rather than leaving it to be inferred from
                    // two tiles.
                    Text(
                      '${l.totalDisbursed} ${formatMoney(summary.disbursed)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              // The affordance. A card that opens something and does not say so
              // is a feature nobody finds — and this is now the only way to the
              // three figures that used to be on the page.
              const Icon(
                Icons.expand_more,
                size: 20,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the balance was arrived at: money in, by method, and money not yet in.
///
/// A sheet rather than a second page: it is read for a moment and dismissed, and
/// the list it was opened from should still be behind it.
void _showTreasuryBreakdown(BuildContext context, CashSummaryView s) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.ink.withValues(alpha: 0.22),
    builder: (BuildContext sheetContext) {
      final L l = L.of(sheetContext);
      return GlassSheet(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.inkMuted.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // The order is the reading order of the answer: what came in,
                // how it came in, what went out, and what has NOT come in —
                // then the conclusion, which is the figure on the bar itself.
                _BreakdownRow(
                  label: l.totalCollected,
                  value: s.total,
                  tone: AppColors.success,
                ),
                _BreakdownRow(
                  label: l.collectedCash,
                  value: s.cash,
                  tone: AppColors.success,
                ),
                _BreakdownRow(
                  label: l.collectedTransfer,
                  value: s.transfer,
                  tone: AppColors.info,
                ),
                _BreakdownRow(
                  label: l.totalDisbursed,
                  value: s.disbursed,
                  tone: AppColors.danger,
                ),
                _BreakdownRow(
                  label: l.dueFromMembers,
                  value: s.outstanding,
                  tone: AppColors.danger,
                ),
                const Divider(height: AppSpacing.xl),
                _BreakdownRow(
                  label: l.associationBalance,
                  value: s.balance,
                  strong: true,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.tone,
    this.strong = false,
  });

  final String label;
  final String value;
  final Color? tone;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Row(
        children: <Widget>[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              // The same solid bar the tiles carried: it encodes the tone for a
              // reader who cannot separate the colours, so hue is never the
              // only signal.
              color: tone ?? AppColors.brand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            formatMoney(value),
            style: TextStyle(
              fontSize: strong ? 16 : 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}
