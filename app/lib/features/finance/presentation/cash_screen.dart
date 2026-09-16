import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/state/refresh.dart';
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

    return AppScaffold(
      title: l.navCash,
      currentRoute: AppRoutes.cash,
      body: (BuildContext context) => RefreshIndicator(
        // Was three providers, chosen by hand. The argument for naming them —
        // that the balance must not disagree with the vouchers under it — is
        // the argument for refreshAll: the register, the dashboard and a
        // member's own aid ledger move with the same payment.
        onRefresh: () async => refreshAll(ref),
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

            // ── حركة العدايل (15/09) ────────────────────────────────────
            // Was «التحصيل», open, one card per member carrying what he PAID.
            // The association asked for it renamed, folded, and read the way
            // «الجدوى» reads one man: paid − received, with the total of all of
            // them on the heading. See _MembersMovement.
            const _MembersMovement(),

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
            // ⚠ FOLDED, like «حركة العدايل» above it (16/09, at the
            //   association's request). The treasury page is opened to read the
            //   balance, and two open lists pushed it off the first screen.
            const SizedBox(height: AppSpacing.lg),
            const _CollectiveSpending(),
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

  // ⚠ NO TOTAL IS ADDED UP HERE ANY MORE (15/09). The row's figure is the
  //   member's NET from v_member_net, summed by Postgres; a cancelled receipt
  //   is still listed inside, struck through, and is out of that figure
  //   because the view filters on status.

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

/// «حركة العدايل» — folded, with the total on its heading.
///
/// ── WHAT IT SAYS ────────────────────────────────────────────────────────────
/// Closed: the total of (what each member PAID − what he RECEIVED), as
/// «صافي رصيد مستحق لهم» or «رصيد مستحق عليهم». Open: EVERY member on the
/// register, each with his own net on the right — «صافي رصيد مستحق له» or
/// «رصيد مستحق عليه» — and his receipts and vouchers inside his card as before.
///
/// ⚠ THE SAME READING AS «الجدوى», AND THE SAME NUMBERS. v_member_net sums the
///   live receipts and the live vouchers made out to him — the rule
///   api_member_value uses — so a man's figure here and on his own «الجدوى»
///   screen cannot disagree. Nothing is added up in Dart.
///
/// ⚠ AND IT IS A READING, NOT A DEBT. This screen used to refuse to net the two
///   directions at all, so that aid would never look like a credit against a
///   subscription. The association asked for the reading explicitly, as it did
///   on «الجدوى»; the rule survives where it was always enforced — a voucher
///   writes no receivable, no payment and no allocation, and no statement or
///   receivable can ever show this figure.
class _MembersMovement extends ConsumerStatefulWidget {
  const _MembersMovement();

  @override
  ConsumerState<_MembersMovement> createState() => _MembersMovementState();
}

class _MembersMovementState extends ConsumerState<_MembersMovement> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return AsyncView<List<MemberNet>>(
      value: ref.watch(memberNetProvider),
      onRetry: () => ref.invalidate(memberNetProvider),
      builder: (List<MemberNet> rows) {
        if (rows.isEmpty) {
          return EmptyStateView(
            icon: Icons.account_balance_wallet_outlined,
            title: l.noCashMovements,
          );
        }

        final String total = rows.first.totalNet;
        final int sign = moneySign(total);

        // The receipts and vouchers that go INSIDE each card. valueOrNull: the
        // nets are the subject of this list and render the moment they land;
        // each card's contents fill in when their own queries settle.
        final Map<int, _AdeelMovements> groups = <int, _AdeelMovements>{
          for (final _AdeelMovements g in _groupByAdeel(
            ref.watch(cashMovementsProvider).valueOrNull ??
                const <CashMovementView>[],
            ref.watch(disbursementsProvider).valueOrNull ??
                const <DisbursementView>[],
          ))
            g.adeelId: g,
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            GlassCard(
              margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
              onTap: () => setState(() => _open = !_open),
              child: Semantics(
                button: true,
                expanded: _open,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            l.membersMovementTitle,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            sign < 0
                                ? l.membersNetOwedByThem
                                : sign > 0
                                ? l.membersNetOwedToThem
                                : l.memberNetEven,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          formatMoney(moneyMagnitude(total)),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _netTone(sign),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: prefersReducedMotion(context)
                  ? Duration.zero
                  : AppMotion.base,
              curve: AppMotion.enter,
              alignment: AlignmentDirectional.topStart,
              child: _open
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final MemberNet row in rows)
                          _AdeelGroup(net: row, group: groups[row.adeelId]),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }
}

/// «صرف جماعي» — money out that belongs to nobody, behind a heading that opens.
///
/// ⚠ THE HEADING CARRIES A COUNT, NOT AN AMOUNT, and that is deliberate. The
///   fold above it prints a figure because the SERVER computes that figure for
///   exactly the rows underneath (`v_member_net.totalNet`). There is no server
///   total for the collective vouchers alone — `v_cash_summary.disbursed` is
///   ALL money out, individual aid included — so a figure here would be either
///   a sum added up in Dart (money on binary floating point, forbidden) or the
///   wrong number under the right heading, which is worse than no number.
///   `payments_screen`'s «الإنفاق حسب الوجه» is where the outgoing totals live.
class _CollectiveSpending extends ConsumerStatefulWidget {
  const _CollectiveSpending();

  @override
  ConsumerState<_CollectiveSpending> createState() =>
      _CollectiveSpendingState();
}

class _CollectiveSpendingState extends ConsumerState<_CollectiveSpending> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return AsyncView<List<DisbursementView>>(
      value: ref.watch(disbursementsProvider),
      onRetry: () => ref.invalidate(disbursementsProvider),
      builder: (List<DisbursementView> vouchers) {
        final List<DisbursementView> collective = vouchers
            .where((DisbursementView v) => v.payeeAdeelId == null)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            GlassCard(
              margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
              onTap: () => setState(() => _open = !_open),
              child: Semantics(
                button: true,
                expanded: _open,
                child: Row(
                  children: <Widget>[
                    // Red, as every outgoing figure on this page is: on a page
                    // where everything else is money arriving, the colour says
                    // which direction before a word is read.
                    Icon(Icons.north_east, size: 18, color: AppColors.danger),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            l.kindCollective,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.danger,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            l.voucherCount(collective.length),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: prefersReducedMotion(context)
                  ? Duration.zero
                  : AppMotion.base,
              curve: AppMotion.enter,
              alignment: AlignmentDirectional.topStart,
              child: !_open
                  ? const SizedBox(width: double.infinity)
                  : collective.isEmpty
                  ? EmptyStateView(
                      icon: Icons.north_east,
                      title: l.noDisbursements,
                    )
                  : GlassCard(
                      margin: const EdgeInsetsDirectional.only(
                        bottom: AppSpacing.sm,
                      ),
                      child: Column(
                        children: <Widget>[
                          for (final DisbursementView v in collective)
                            _VoucherTile(voucher: v),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Green when the association holds more of his than it gave him, red when it
/// gave him more — the colours «الجدوى» uses for the same two words.
Color _netTone(int sign) => sign < 0
    ? AppColors.danger
    : sign > 0
    ? AppColors.success
    : AppColors.muted;

class _AdeelGroup extends StatelessWidget {
  const _AdeelGroup({required this.net, required this.group});

  final MemberNet net;

  /// His receipts and vouchers, or null while they load or when he has none.
  final _AdeelMovements? group;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final _AdeelMovements? g = group;
    final int sign = moneySign(net.net);

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
            net.adeelName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          // The code, how many receipts are folded in, and — in red — how many
          // vouchers: what tells a reader there is anything to open.
          subtitle: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text:
                      '${net.adeelCode} • ${l.receiptCount(g?.liveCount ?? 0)}',
                ),
                if (g != null && g.vouchers.isNotEmpty)
                  TextSpan(
                    text: ' • ${l.voucherCount(g.vouchers.length)}',
                    style: TextStyle(color: AppColors.danger),
                  ),
              ],
            ),
            style: TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          // ── في مقابل اسمه: صافيه ────────────────────────────────────────
          // «صافي رصيد مستحق له» or «رصيد مستحق عليه», and the figure without
          // its sign — the words already say which way it runs.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    sign < 0
                        ? l.memberNetOwedByHim
                        : sign > 0
                        ? l.memberNetOwedToHim
                        : l.memberNetEven,
                    style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                  ),
                  Text(
                    formatMoney(moneyMagnitude(net.net)),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _netTone(sign),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.expand_more, size: 20, color: AppColors.muted),
            ],
          ),
          // ── HIS RECEIPTS, THEN HIS VOUCHERS ──────────────────────────────
          // In that order, never interleaved by date: what he gave the
          // association and what it gave him are different kinds of fact.
          children: <Widget>[
            if (g != null) ...<Widget>[
              for (final CashMovementView movement in g.movements)
                _MovementTile(movement: movement),
              for (final DisbursementView v in g.vouchers)
                _VoucherTile(voucher: v),
            ],
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
        style: TextStyle(fontSize: 11, color: AppColors.muted),
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
    final Color tone = AppColors.danger;

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
        style: TextStyle(fontSize: 11, color: AppColors.muted),
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
