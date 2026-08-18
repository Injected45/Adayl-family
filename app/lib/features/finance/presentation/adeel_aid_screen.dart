import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Column shares for the ledger, summing to 100: التاريخ | البند | القيمة |
/// الإجمالي.
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
/// actually be broken is a layout that puts «ما صُرف له» beside «ما عليه» and
/// invites the eye to subtract. Keeping them apart is the whole safeguard —
/// there is deliberately no explanatory notice on the page, at the
/// association's request.
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
    // with a back button. Staff get the normal chrome.
    //
    // ⚠ AppBackground IS NOT DECORATION HERE. `scaffoldBackgroundColor` is
    //   Colors.transparent for the whole app, because every screen is supposed
    //   to be painted over the aurora field; and every surface in this design —
    //   panels, cards, the fill behind a text field — is translucent WHITE. A
    //   bare Scaffold therefore has no canvas at all, so those whites composite
    //   over black: the search box came out a dark slab with unreadable text
    //   inside it, and the panels lost their glass entirely.
    //
    //   AppScaffold wraps itself in this for the same reason. The portal does it
    //   too. Anything in this app that builds its own Scaffold has to.
    if (widget.mine) {
      return AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(title)),
          body: body,
        ),
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
    // what the box does is hide rows — which is why the الإجمالي column goes on
    // belonging to the FULL history, and why the panel says how many rows are
    // showing while a search narrows it.
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

        // ── NO EXPLANATORY NOTICE HERE, and that is deliberate ─────────────
        // This page carried a paragraph at the top saying aid is not deducted
        // from a subscription. The association removed it: that rule was
        // explained to the developer, not to the member, and a man opening his
        // own record wants the figures, not a lecture about how they work.
        //
        // Nothing about the rule changed. It is enforced in the database — a
        // voucher writes no receivable, no payment and no allocation, and
        // api_adeel_statement merges exactly those two tables — and
        // supabase/tests/67_disbursement.sql proves it on both sides. The notice
        // was never what made it true.
        if (aid.isEmpty)
          EmptyStateView(
            icon: Icons.volunteer_activism_outlined,
            title: mine ? l.noMyAid : l.noAid,
          )
        else ...<Widget>[
          // ── The breakdowns show to BOTH readers ─────────────────────────
          // They were briefly staff-only, on the reasoning that with one or two
          // vouchers the panel restates the ledger rather than grouping it and
          // could read as the same 100 counted twice. The association asked for
          // it on the member's screen too, and it is right: «كم صُرف لي في
          // العزاء عبر السنين» is a question a long ledger does not answer by
          // being read row by row, and it is as much his question as theirs.
          //
          // What the worry deserved was a SENTENCE, not a missing panel — the
          // note under it says these are a grouping of the vouchers below, not
          // further disbursements. So `mine` is back to changing only the
          // voice, which is all it was ever meant to change.
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
                      vouchers: _liveUnder(
                        aid,
                        (DisbursementView v) => v.category == c.category,
                      ),
                    ),
                  // ── The sentence that stood here is gone ─────────────────
                  // «هذا تجميع للسندات المدرجة أدناه، وليست عمليات صرف إضافية»
                  // existed because a reader who saw «مولود 450» here and the
                  // same vouchers again in the ledger below had every reason to
                  // suspect they were recorded twice. It answered that in
                  // words, which was the only way while the line was inert.
                  //
                  // Opening the line answers it by SHOWING: the three vouchers
                  // appear under the heading, each with its own number, date
                  // and note, and they are visibly the same three that are in
                  // the ledger. A demonstration the reader performs himself
                  // needs no sentence beside it, and the association asked for
                  // fewer of those.
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Only when there is more than one year to compare: on a member helped
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
                      // The first four characters of `spentAt`, not a parsed
                      // DateTime: api_adeel_aid derives the year with
                      // `AT TIME ZONE 'UTC'` and v_disbursements renders the
                      // date the same way, so the strings agree by
                      // construction. Parsing to local time would disagree with
                      // the heading for a voucher written near midnight.
                      vouchers: _liveUnder(
                        aid,
                        (DisbursementView v) => v.spentAt.startsWith(y.year),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // The search sits ABOVE the panel it filters, and outside it. Inside
          // the panel it would read as one more row of the record; above it, it
          // is plainly a control acting on what follows.
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

          // ONE container for the record: the total and the vouchers it is made
          // of. They were two — a headline card above a ledger panel — and read
          // as two separate things when they are one answer to one question.
          _AidPanel(rows: rows, aid: aid, filtered: needle.isNotEmpty),
        ],
      ],
    );
  }
}

/// The headline figure and the span it covers, at the head of the record.
///
/// A plain Column, NOT a card: it lives inside the one panel now. It used to be
/// a GlassCard of its own above the ledger, and two containers read as two
/// separate things when they are one answer — the total, and the vouchers it is
/// made of.
class _AidTotalBlock extends StatelessWidget {
  const _AidTotalBlock({required this.aid});

  final AdeelAid aid;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Column(
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
    );
  }
}

/// One label / count / amount line, used by both breakdowns.

/// The vouchers behind one breakdown line, oldest first.
///
/// ⚠ CANCELLED ONES ARE LEFT OUT, to match the figure they sit under.
///   api_adeel_aid computes `byCategory` and `byYear` over a CTE that excludes
///   'ملغي', so a heading that says «٣ سندات ‎450.00» is already counting three.
///   Expanding to the full ledger would list four rows adding to something
///   else, directly beneath a total that disagrees — and the reader has nothing
///   to tell him which is right. Reversed vouchers stay in the ledger below,
///   where rule 9 requires them and where the الإجمالي column shows they moved
///   nothing.
///
/// Oldest first, matching the ledger. The ledger reads as a running account and
/// these are the same rows under a different heading; flipping the order in one
/// place would make the same voucher look like two different entries.
List<DisbursementView> _liveUnder(
  AdeelAid aid,
  bool Function(DisbursementView) where,
) => aid.ledger
    .map((AidLedgerEntry e) => e.voucher)
    .where((DisbursementView v) => !v.cancelled && where(v))
    .toList();
/// One line of a breakdown — and the vouchers behind it, on a tap.
///
/// «مولود  ٣ سندات  450.00» answers how much went on births and stops there.
/// The question it raises is the next one: WHICH births, and when, and for
/// whom — and the note on each voucher is where the association wrote the
/// child's name. That used to mean scrolling to the ledger below and picking
/// the three rows out of a year of them by eye.
///
/// So the line opens. Nothing new is fetched and no panel is added: the same
/// vouchers already on this screen are shown under the heading they belong to,
/// which is the arrangement that answers the question without another container
/// on the page.
///
/// ⚠ LIVE VOUCHERS ONLY, and this is not a display preference. `byCategory` and
///   `byYear` are computed by api_adeel_aid over a CTE that excludes 'ملغي', so
///   its count and its total already leave reversed vouchers out. Expanding to
///   the full ledger would list four rows under a heading that says three and
///   show amounts that do not add up to the figure above them — a disagreement
///   the reader would have no way to resolve. The reversed ones stay visible in
///   the ledger below, where rule 9 requires them and where the الإجمالي column
///   shows they moved nothing.
class _AidRow extends StatefulWidget {
  const _AidRow({
    required this.label,
    required this.trailing,
    required this.amount,
    required this.vouchers,
  });

  final String label;
  final String trailing;
  final String amount;

  /// Already narrowed to this heading, and already live-only.
  final List<DisbursementView> vouchers;

  @override
  State<_AidRow> createState() => _AidRowState();
}

class _AidRowState extends State<_AidRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // A line with nothing behind it does not pretend to open. That only happens
    // if a heading's vouchers were all reversed, which the filter above cannot
    // produce for a heading that is listed at all — but a chevron that does
    // nothing is worse than no chevron, so the case is handled rather than
    // assumed away.
    final bool openable = widget.vouchers.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: openable ? () => setState(() => _open = !_open) : null,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                if (openable) ...<Widget>[
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    widget.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  widget.trailing,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  formatMoney(widget.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final DisbursementView v in widget.vouchers)
            _AidVoucherBrief(voucher: v),
      ],
    );
  }
}

/// One voucher inside an opened heading: when, how much, and what was written
/// on it.
///
/// Deliberately NOT the full [_LedgerDetail]. Under «مولود» the category is the
/// heading itself and printing it on every row is noise; what is left is the
/// date, the amount and the NOTE — and the note is the whole reason the line
/// opens, because that is where «حور» or «سند» was recorded.
class _AidVoucherBrief extends StatelessWidget {
  const _AidVoucherBrief({required this.voucher});

  final DisbursementView voucher;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.only(
        bottom: AppSpacing.xs,
        start: AppSpacing.lg,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: GlassColors.well,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: GlassColors.wellEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                voucher.voucherNo,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  formatDate(voucher.spentAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
              Text(
                formatMoney(voucher.amount),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
          // Prose of unknown length, and the answer the reader opened the line
          // for. It wraps freely because nothing sits beside it.
          if (voucher.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              voucher.note,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// THE record, in one container: the total, and the vouchers it is made of.
///
/// It was two — a headline card above a ledger panel — and read as two separate
/// things when they are one answer to one question. The total now heads the
/// panel and the table runs beneath it, so the الإجمالي column's last cell IS
/// the closing figure and nothing is stated twice.
///
/// Read down that column and it answers what the association actually asked:
/// «صُرف له 100 ثم 500، فيصبح 600» — without the reader adding anything himself.
class _AidPanel extends StatelessWidget {
  const _AidPanel({
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

    return GlassPanel(
      title: l.aidPanelTitle,
      icon: Icons.receipt_long_outlined,
      // While a search is narrowing the table, say how much of it is on screen.
      // Without it the الإجمالي column looks broken: it jumps, because it is
      // still the total across the WHOLE history and always should be — a
      // ledger line's balance does not change because a reader filtered the
      // page.
      trailing: filtered
          ? Text(
              l.aidShowing(rows.length, aid.ledger.length),
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            )
          : null,
      child: Column(
        children: <Widget>[
          // The total stays put while a search narrows the table beneath it: it
          // is what the association gave him, not what the box is showing.
          _AidTotalBlock(aid: aid),
          const Divider(height: AppSpacing.lg),
          if (rows.isEmpty)
            EmptyStateView(icon: Icons.search_off, title: l.aidNoMatch)
          else ...<Widget>[
            const _LedgerHead(),
            // Keyed by voucher id: a search rewrites the list, and without a key
            // Flutter would reuse the expanded row's State for whatever voucher
            // lands at that index — so filtering would leave a different
            // voucher's detail hanging open.
            for (final AidLedgerEntry e in rows)
              _LedgerLine(key: ValueKey<int>(e.voucher.id), entry: e),
          ],
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

/// One ledger line, and the detail it hides until it is asked for.
///
/// ── WHY THE DETAIL IS FOLDED AWAY ───────────────────────────────────────────
/// The four columns are the accounting and they must stay readable down the
/// page: a member scanning years of aid is reading a TABLE, and a table stops
/// being one the moment every row grows a paragraph under it. The note is the
/// paragraph — «اسم المولود» is short, but "أعطي له لعلاج والدته في تونس وتم
/// تسليمه بحضور..." is not, and one long note pushes every other line off the
/// screen.
///
/// So the line stays one line, and tapping it opens the rest beneath it. The
/// table keeps its shape, and the detail is one tap away for the one row a
/// reader is actually asking about.
///
/// Expansion state lives HERE rather than in the panel, so only the tapped row
/// rebuilds and a search that rewrites the list cannot leave a stale index
/// pointing at a different voucher.
class _LedgerLine extends StatefulWidget {
  const _LedgerLine({required this.entry, super.key});

  final AidLedgerEntry entry;

  @override
  State<_LedgerLine> createState() => _LedgerLineState();
}

class _LedgerLineState extends State<_LedgerLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final DisbursementView v = widget.entry.voucher;
    final bool cancelled = v.cancelled;
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
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    flex: _dateFlex,
                    child: Row(
                      children: <Widget>[
                        // The affordance. Without it a tappable table row is a
                        // feature nobody discovers, and it doubles as the state:
                        // pointing down means "there is more", turned means
                        // "you are looking at it".
                        Icon(
                          _open ? Icons.expand_less : Icons.expand_more,
                          size: 14,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(formatDate(v.spentAt), style: base),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: _categoryFlex,
                    child: Text(v.category, style: base),
                  ),
                  Expanded(
                    flex: _moneyFlex,
                    child: Text(
                      formatMoney(v.amount),
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
                      formatMoney(widget.entry.runningTotal),
                      textAlign: TextAlign.end,
                      // NEVER struck through, even on a reversed line. The
                      // amount was cancelled; the balance at that point in the
                      // ledger was not — it is simply the same figure as the
                      // line above, which is what a reversal looks like in a
                      // running total.
                      style: const TextStyle(
                        fontSize: _ledgerSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) _LedgerDetail(voucher: v),
        ],
      ),
    );
  }
}

/// What one voucher actually was, opened under its line.
///
/// A recessed well rather than another card: it belongs to the row above it,
/// and a second bordered surface inside a panel reads as a separate record.
class _LedgerDetail extends StatelessWidget {
  const _LedgerDetail({required this.voucher});

  final DisbursementView voucher;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.only(top: 2, bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: GlassColors.well,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: GlassColors.wellEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DetailLine(label: l.voucherNo, value: voucher.voucherNo),
          _DetailLine(label: l.expenseCategory, value: voucher.category),
          _DetailLine(label: l.amount, value: formatMoney(voucher.amount)),
          _DetailLine(label: l.method, value: voucher.method),
          if (voucher.handedBy.isNotEmpty)
            _DetailLine(label: l.handedBy, value: voucher.handedBy),
          if (voucher.cancelled)
            _DetailLine(label: l.statusLabel, value: l.voided),
          // ── The note is LAST and unconstrained ───────────────────────────
          // Everything above is a short value that fits one line; this is prose
          // of unknown length, and it is the reason the row folds at all. It
          // wraps freely here because nothing is beside it to squeeze.
          if (voucher.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.aidNoteLabel,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            const SizedBox(height: 2),
            Text(
              voucher.note,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

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
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
