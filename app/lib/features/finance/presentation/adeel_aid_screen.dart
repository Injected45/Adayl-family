import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Column shares for the ledger, summing to 100: التاريخ | البند | القيمة |
/// الرصيد التراكمي.
///
/// Shares, not pixels, for the reason the portal's statement table gives: four
/// fixed columns need more width than a 360dp phone has, and proportions fit
/// every screen and every system font size by construction.
///
/// The two money columns are the widest pair because they hold the longest
/// strings — a four-figure amount with separators — and the heading column is
/// given the least, since every value in it is one of six short words.
const int _dateFlex = 26;
const int _categoryFlex = 22;
const int _moneyFlex = 26;

/// The ledger runs a point smaller than the rest of the page, deliberately: a
/// four-column table of figures is a different constraint from prose, and a
/// column where some rows shrank to fit is harder to read down than one that is
/// uniformly small.
const double _ledgerSize = 12;

/// What the association has GIVEN one عديل, as a ledger with a running total.
///
/// ⚠ THIS IS NOT HIS STATEMENT, AND THE TWO MUST NEVER BE ADDED TOGETHER.
/// الجمعية خيرية: aid paid to a man is not deducted from what he owes. A member
/// given something for a bereavement still owes that month's subscription, and
/// his statement goes on showing the full debt.
///
/// The database makes that structural — a voucher writes no receivable, no
/// payment and no allocation, and `api_adeel_statement` merges exactly those two
/// tables — so aid cannot reach the statement however this screen is written. It
/// is a SEPARATE screen for a different reason: the place the rule would
/// actually be broken is a layout that puts «ما استلمه» beside «ما عليه» and
/// invites the eye to subtract. The note at the top says so in words as well.
///
/// ── The running total ───────────────────────────────────────────────────────
/// «صُرف له 100 مولود، ثم بعد أشهر 500 فرح» reads 100 then 600. That column is
/// computed by a window function in `api_adeel_aid`, NOT accumulated here: money
/// crosses the wire as text precisely so nothing on the client adds it, and this
/// is the one screen whose whole purpose is a sum.
///
/// One screen, two readers. Staff open it from an عديل's page and read
/// anybody's; a member reads only his own, because `api_adeel_aid` is SECURITY
/// INVOKER and `read_own_disbursements` is scoped to
/// `payee_adeel_id = my_adeel_id()`. There is no role check here at all —
/// hiding a widget is presentation, and the rows the server returns are the same
/// either way. [mine] changes only the VOICE: «ما صُرف لك» to the man himself,
/// «ما صُرف له» to the association looking at his record.
class AdeelAidScreen extends ConsumerStatefulWidget {
  const AdeelAidScreen({required this.adeelId, this.mine = false, super.key});

  final int adeelId;

  /// True when the reader IS this عديل. Wording only.
  final bool mine;

  @override
  ConsumerState<AdeelAidScreen> createState() => _AdeelAidScreenState();
}

class _AdeelAidScreenState extends ConsumerState<AdeelAidScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AsyncValue<AdeelAid> aid = ref.watch(
      adeelAidProvider(widget.adeelId),
    );
    final String title = widget.mine ? l.myAidTitle : l.aidTitle;

    final Widget body = AsyncView<AdeelAid>(
      value: aid,
      onRetry: () => ref.invalidate(adeelAidProvider(widget.adeelId)),
      builder: (AdeelAid data) => _AidBody(
        aid: data,
        mine: widget.mine,
        query: _query,
        search: _search,
        onQuery: (String q) => setState(() => _query = q),
      ),
    );

    // A member has no navigation bar anywhere in the portal — every destination
    // on it is a screen the router refuses him — so he gets a plain Scaffold
    // with a back button, exactly as the portal itself does. Staff get the
    // normal chrome.
    if (widget.mine) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: body,
      );
    }
    return AppScaffold(
      title: title,
      currentRoute: AppRoutes.adeels,
      body: (BuildContext context) => body,
    );
  }
}

class _AidBody extends StatelessWidget {
  const _AidBody({
    required this.aid,
    required this.mine,
    required this.query,
    required this.search,
    required this.onQuery,
  });

  final AdeelAid aid;
  final bool mine;
  final String query;
  final TextEditingController search;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    // Filtering, never summing. Every figure on this page comes from the server;
    // what the box does is hide rows, which is why the running-total column goes
    // on belonging to the FULL history and the line above the table says so.
    final String needle = query.trim().toLowerCase();
    final List<AidLedgerEntry> rows = needle.isEmpty
        ? aid.ledger
        : aid.ledger
              .where((AidLedgerEntry e) => e.haystack.contains(needle))
              .toList();

    return ListView(
      padding: screenPadding(context),
      children: <Widget>[
        if (!mine && aid.adeelName.isNotEmpty) ...<Widget>[
          Text(
            aid.adeelName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(aid.adeelCode, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
        ],

        // The rule, stated before the figures rather than after them. A reader
        // who has just seen «استلم 600» is the one who needs to be told it
        // changes nothing about what he owes.
        const _AidNote(),
        const SizedBox(height: AppSpacing.lg),

        if (aid.isEmpty)
          EmptyStateView(
            icon: Icons.volunteer_activism_outlined,
            title: mine ? l.noMyAid : l.noAid,
          )
        else ...<Widget>[
          _AidHeadline(aid: aid),
          const SizedBox(height: AppSpacing.lg),

          if (aid.byCategory.length > 1) ...<Widget>[
            GlassPanel(
              title: l.aidByCategory,
              icon: Icons.donut_small_outlined,
              child: Column(
                children: <Widget>[
                  for (final ExpenseByCategory c in aid.byCategory)
                    _AidRow(
                      label: c.category,
                      trailing: l.aidVoucherCount(c.count),
                      amount: c.total,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Only when there is more than one year to compare. On a member helped
          // once, a single-row "by year" restates the headline and says nothing.
          if (aid.byYear.length > 1) ...<Widget>[
            GlassPanel(
              title: l.aidByYear,
              icon: Icons.calendar_month_outlined,
              child: Column(
                children: <Widget>[
                  for (final AidByYear y in aid.byYear)
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

          TextField(
            controller: search,
            onChanged: onQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: l.aidSearchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: needle.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        search.clear();
                        onQuery('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _AidLedger(rows: rows, aid: aid, filtered: needle.isNotEmpty),
        ],
      ],
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
          Text(l.aidGrandTotal, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatMoney(aid.total),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              // The colour money LEAVING the treasury carries everywhere else in
              // the app, which is what this is from the association's side. It
              // is deliberately not the red that means "owed" on the member's
              // own screens — nothing here is a debt.
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

/// The ledger: one line per voucher, oldest first, with the total so far.
///
/// Read down the الرصيد التراكمي column and it answers the question the
/// association actually asked — «صُرف له 100 ثم 500، فيصبح 600» — without the
/// reader adding anything himself.
class _AidLedger extends StatelessWidget {
  const _AidLedger({
    required this.rows,
    required this.aid,
    required this.filtered,
  });

  final List<AidLedgerEntry> rows;
  final AdeelAid aid;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    if (rows.isEmpty) {
      return GlassPanel(
        title: l.aidVouchers,
        icon: Icons.receipt_long_outlined,
        child: EmptyStateView(icon: Icons.search_off, title: l.aidNoMatch),
      );
    }

    return GlassPanel(
      title: l.aidVouchers,
      icon: Icons.receipt_long_outlined,
      // While a search is narrowing the table, say how much of it is on screen.
      // Without it the running-total column looks broken: it jumps, because it
      // is still the total across the WHOLE history and always should be — a
      // ledger line's balance does not change because a reader filtered the page.
      trailing: filtered
          ? Text(
              l.aidShowing(rows.length, aid.ledger.length),
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            )
          : null,
      child: Column(
        children: <Widget>[
          const _LedgerHead(),
          for (final AidLedgerEntry e in rows) _LedgerLine(entry: e),
          const Divider(height: AppSpacing.lg),
          _LedgerTotal(total: aid.total),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l.aidRunningNote,
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

class _LedgerHead extends StatelessWidget {
  const _LedgerHead();

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    const TextStyle style = TextStyle(
      fontSize: _ledgerSize,
      fontWeight: FontWeight.w800,
      color: AppColors.muted,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(flex: _dateFlex, child: Text(l.aidColDate, style: style)),
          Expanded(
            flex: _categoryFlex,
            child: Text(l.aidColCategory, style: style),
          ),
          Expanded(
            flex: _moneyFlex,
            child: Text(
              l.aidColAmount,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
          Expanded(
            flex: _moneyFlex,
            child: Text(
              l.aidColRunning,
              style: style,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerLine extends StatelessWidget {
  const _LedgerLine({required this.entry});

  final AidLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool cancelled = entry.voucher.cancelled;
    final TextStyle base = TextStyle(
      fontSize: _ledgerSize,
      color: cancelled ? AppColors.muted : null,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                flex: _dateFlex,
                child: Text(formatDate(entry.voucher.spentAt), style: base),
              ),
              Expanded(
                flex: _categoryFlex,
                child: Text(entry.voucher.category, style: base),
              ),
              Expanded(
                flex: _moneyFlex,
                child: Text(
                  formatMoney(entry.voucher.amount),
                  textAlign: TextAlign.end,
                  style: base.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cancelled ? AppColors.muted : AppColors.danger,
                  ),
                ),
              ),
              Expanded(
                flex: _moneyFlex,
                child: Text(
                  formatMoney(entry.runningTotal),
                  textAlign: TextAlign.end,
                  // NEVER struck through, even on a reversed line. The amount
                  // was cancelled; the balance at that point in the ledger was
                  // not — it is simply the same figure as the line above, which
                  // is what a reversal looks like in a running total.
                  style: const TextStyle(
                    fontSize: _ledgerSize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          // The voucher number and anything written on it, under the figures
          // rather than in a fifth column: a note is prose of unpredictable
          // length and would have squeezed the four columns that carry the
          // accounting.
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 2),
            child: Text(
              <String>[
                entry.voucher.voucherNo,
                if (entry.voucher.note.isNotEmpty) entry.voucher.note,
                if (cancelled) l.voided,
              ].join(' • '),
              style: TextStyle(
                fontSize: 10,
                color: cancelled ? AppColors.danger : AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The closing figure, in the column the running total runs down.
class _LedgerTotal extends StatelessWidget {
  const _LedgerTotal({required this.total});

  final String total;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          flex: _dateFlex + _categoryFlex + _moneyFlex,
          child: Text(
            l.aidGrandTotal,
            style: const TextStyle(
              fontSize: _ledgerSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          flex: _moneyFlex,
          child: Text(
            formatMoney(total),
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.danger,
            ),
          ),
        ),
      ],
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
