import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/figure_breakdown.dart';
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
                // The vouchers are read here as well, because a member's card
                // has to carry both directions and they arrive from a second
                // provider. `valueOrNull` rather than a nested AsyncView: the
                // collections are the subject of this list and must render the
                // moment they land, with each man's outgoing side filling in
                // when it does. A spinner over the whole register while one
                // secondary query settles would be a worse trade.
                final List<DisbursementView> vouchers =
                    ref.watch(disbursementsProvider).valueOrNull ??
                    const <DisbursementView>[];
                final List<_AdeelMovements> groups = _groupByAdeel(
                  items,
                  vouchers,
                );
                if (groups.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.account_balance_wallet_outlined,
                    title: l.noCashMovements,
                  );
                }
                return Column(
                  children: <Widget>[
                    for (final _AdeelMovements group in groups)
                      _AdeelGroup(group: group),
                  ],
                );
              },
            ),

            // ── MONEY OUT THAT BELONGS TO NOBODY ────────────────────────
            // The treasury is one fund and this is the page that describes it,
            // so leaving the outgoing side on another screen made this one
            // answer half its own question — the balance bar above already
            // subtracts what went out, and until this nothing here showed WHAT.
            //
            // ⚠ ONLY THE COLLECTIVE ONES. A voucher made out to a member now
            //   sits inside HIS card, beside what he paid, which is the one
            //   place a reader can weigh the two against each other. Listing it
            //   here as well would put the same voucher on the screen twice and
            //   invite it to be counted twice by eye.
            //
            //   فطور رمضان belongs to everyone, so it has no card to sit in —
            //   `payee_adeel_id` is NULL by ck_disb_shape, not by omission —
            //   and that is exactly what this section is for.
            //
            // ⚠ RED, THROUGHOUT: on a page where every other figure is money
            //   arriving, an outgoing amount in the same green reads as a
            //   second collection. Colour carries the direction before the
            //   number is read at all.
            const SizedBox(height: AppSpacing.lg),
            Text(
              l.kindCollective,
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
                final List<DisbursementView> collective = vouchers
                    .where((DisbursementView v) => v.payeeAdeelId == null)
                    .toList();
                if (collective.isEmpty) {
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
                      for (final DisbursementView v in collective)
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

  /// What the association GAVE this man, under his own name.
  ///
  /// ⚠ AND IT IS NOT NETTED AGAINST [total], ever. الجمعية خيرية: aid is not a
  ///   credit against a subscription, and a voucher writes no receivable, no
  ///   payment and no allocation — so there is nothing to net even if a screen
  ///   wanted to. The group's figure stays "what he PAID", and the vouchers sit
  ///   below the receipts in red with an outgoing arrow, which is the whole
  ///   reason they can share a card at all: two directions the eye separates
  ///   before it reads a digit.
  ///
  ///   The full account of what he was given is [AdeelAidScreen], reached from
  ///   his page. This is the treasury's view of the same rows — one voucher,
  ///   two places it can be looked up, and no third copy: a voucher listed here
  ///   is left OUT of the collective list at the foot of the screen.
  final List<DisbursementView> vouchers = <DisbursementView>[];

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
List<_AdeelMovements> _groupByAdeel(
  List<CashMovementView> items,
  List<DisbursementView> vouchers,
) {
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
  // Then what went OUT to each of them. A member who was given something but
  // never paid still gets a card — his side of the fund is a real thing to look
  // up, and leaving him out would make "he received nothing" and "he is not on
  // this screen" look identical.
  for (final DisbursementView v in vouchers) {
    final int? payee = v.payeeAdeelId;
    if (payee == null) continue; // collective — belongs to nobody
    byAdeel
        .putIfAbsent(
          payee,
          () => _AdeelMovements(payee, v.payeeName, v.payeeCode),
        )
        .vouchers
        .add(v);
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
          // The code, how many receipts are folded in, and — in red — how many
          // vouchers. The counts are what tell a reader there is anything to
          // open at all, and the red one is what says the card has an OUTGOING
          // side before it is opened.
          //
          // ⚠ A COUNT, never an amount. Two money figures on one row invite the
          //   reader to subtract, and الجمعية خيرية: what a man was given is
          //   not a credit against what he paid, and nothing in this app nets
          //   the two. The trailing figure stays what he PAID, alone.
          subtitle: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text:
                      '${group.adeelCode} • ${l.receiptCount(group.liveCount)}',
                ),
                if (group.vouchers.isNotEmpty)
                  TextSpan(
                    text: ' • ${l.voucherCount(group.vouchers.length)}',
                    style: const TextStyle(color: AppColors.danger),
                  ),
              ],
            ),
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
          // ── HIS RECEIPTS, THEN HIS VOUCHERS ──────────────────────────────
          // In that order, never interleaved by date: the two are different
          // KINDS of fact — what he gave the association and what it gave him —
          // and a single chronological column of green and red numbers is the
          // one arrangement that invites the eye to net them. الجمعية خيرية:
          // aid is not a credit against a subscription, and the arithmetic of
          // this app never subtracts one from the other.
          children: <Widget>[
            for (final CashMovementView movement in group.movements)
              _MovementTile(movement: movement),
            if (group.vouchers.isNotEmpty)
              for (final DisbursementView v in group.vouchers)
                _VoucherTile(voucher: v),
          ],
        ),
      ),
    );
  }
}

/// One receipt inside a member's card: money IN, in green, with an arrow that
/// points inward.
///
/// ── THE ICON IS THE DIRECTION, NOT THE METHOD ───────────────────────────────
/// It used to be نقداً-vs-تحويل, which is a real fact about a receipt and the
/// wrong one to spend the leading position on: a card now holds BOTH the money
/// this man paid and the money the association gave him, and telling those two
/// apart at a glance is what the position is for. The method moves into the
/// subtitle, where it is still one line away.
///
/// Icons.south_west is the same arrow the التحصيل tab and its button carry, and
/// _VoucherTile uses the same north_east as الصرف. One vocabulary across the
/// app: inward-and-green is money arriving, outward-and-red is money leaving,
/// wherever it is drawn.
class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final CashMovementView movement;

  @override
  Widget build(BuildContext context) {
    final bool voided = movement.status == ReceivableStatusWire.cancelled;
    // ⚠ A CANCELLED RECEIPT IS RED, not grey. It was money that came in and
    //   went back out again, so it belongs with the outgoing side of the card
    //   at a glance — and grey read as "inactive", which understates a
    //   reversal that a treasurer has to account for. The strike-through is
    //   what separates it from a live disbursement: red-and-struck is money
    //   undone, red-and-plain is money spent.
    final Color tone = voided ? AppColors.danger : AppColors.success;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(voided ? Icons.undo : Icons.south_west, color: tone),
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
        '${movement.method} • ${formatDateTime(movement.occurredAt)}',
        style: const TextStyle(fontSize: 11, color: AppColors.muted),
      ),
      trailing: Text(
        formatMoney(movement.amount),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: tone,
          decoration: voided ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

/// A voucher: money LEAVING, in red, with an arrow that points outward.
///
/// The same shape as [_MovementTile] on purpose — icon, reference, subtitle,
/// amount — so a member's card reads as ONE list whose rows differ by colour
/// and arrow rather than as two layouts stacked. That is the whole mechanism:
/// «صُرف له» and «سدّد» are told apart before a digit is read.
class _VoucherTile extends StatelessWidget {
  const _VoucherTile({required this.voucher});

  final DisbursementView voucher;

  @override
  Widget build(BuildContext context) {
    final bool voided = voucher.cancelled;
    // ⚠ RED WHETHER OR NOT IT WAS REVERSED, and the strike-through is what
    //   distinguishes them. Grey said "inactive", which is not what a reversed
    //   voucher is — it is an entry a treasurer still has to account for, and
    //   rule 9 keeps it on screen for exactly that reason. Its amount is
    //   already out of every total on this page, because they all filter on
    //   status, so the colour costs nothing in correctness.
    const Color tone = AppColors.danger;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(voided ? Icons.undo : Icons.north_east, color: tone),
      title: Text(
        voucher.voucherNo,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          // Rule 9: a reversed voucher stays legible and visibly struck
          // through.
          decoration: voided ? TextDecoration.lineThrough : null,
          color: voided ? AppColors.muted : null,
        ),
      ),
      subtitle: Text(
        // The heading, then whose it was when it belongs to somebody. Inside a
        // member's card the name is the heading above, so it is dropped: this
        // tile is used in both places and the payee is only ever repetition in
        // one of them.
        <String>[
          voucher.category,
          voucher.method,
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
/// The shape is shared with the dashboard: see [FigureBar].
class _BalanceBar extends StatelessWidget {
  const _BalanceBar({required this.summary});

  final CashSummaryView summary;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return FigureBar(
      label: l.associationBalance,
      value: formatMoney(summary.balance),
      sub: '${l.totalDisbursed} ${formatMoney(summary.disbursed)}',
      // ── THE LIABILITY, ON ITS OWN LINE AND IN ITS OWN COLOUR ──────────────
      // عهد shared the subtitle with the disbursed total, one OR the other. So
      // the treasury — the single screen where somebody is holding the actual
      // notes and can see the app disagree with his hands — showed the more
      // urgent of the two in muted grey, and showed it INSTEAD of the outflow
      // rather than beside it.
      //
      // `note` is the slot the home screen already uses for this exact
      // sentence, so the two screens now say the same thing in the same words
      // and the same amber. Shown only when there IS any: «عهد المشتركين 0.00»
      // under every balance is a permanent line explaining a situation that is
      // not happening.
      note: (double.tryParse(summary.heldForMembers) ?? 0) > 0
          ? l.heldOfWhich(formatMoney(summary.heldForMembers))
          : null,
      noteTone: AppColors.warning,
      // The order is the reading order of the answer: what came in, how it came
      // in, what went out, what has NOT come in — then the conclusion, which is
      // the figure on the bar itself.
      rows: <FigureRow>[
        FigureRow(
          label: l.totalCollected,
          value: formatMoney(summary.total),
          tone: AppColors.success,
        ),
        FigureRow(
          label: l.collectedCash,
          value: formatMoney(summary.cash),
          tone: AppColors.success,
        ),
        FigureRow(
          label: l.collectedTransfer,
          value: formatMoney(summary.transfer),
          tone: AppColors.info,
        ),
        // ── The liability, between what came in and what went out ────────────
        // Placed here because that is where it belongs in the sentence the rows
        // read as: 60 arrived, 40 of it is not ours, 20 went out, this is what
        // is left. AMBER, and neither of the tones on either side of it: green
        // would put it on the association's side of the ledger, and red is what
        // the disbursement below it and the debt below that are. This is
        // neither — nothing was lost and nothing is owed BY a member. It is
        // money HELD, and amber is that third answer on every screen it appears
        // on: here, the home headline, and the member's own portal.
        FigureRow(
          label: l.heldForMembers,
          value: formatMoney(summary.heldForMembers),
          tone: AppColors.warning,
        ),
        FigureRow(
          label: l.totalDisbursed,
          value: formatMoney(summary.disbursed),
          tone: AppColors.danger,
        ),
        FigureRow(
          label: l.dueFromMembers,
          value: formatMoney(summary.outstanding),
          tone: AppColors.danger,
        ),
        FigureRow(
          label: l.associationBalance,
          value: formatMoney(summary.balance),
          strong: true,
        ),
      ],
    );
  }
}
