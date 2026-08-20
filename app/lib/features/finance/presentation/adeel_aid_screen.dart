import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/state/refresh.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// THREE columns: البند | القيمة | الإجمالي.
///
/// ── THE DATE CAME OUT ───────────────────────────────────────────────────────
/// It was the leading column and it was the widest, and on a phone it cost more
/// than it answered: «19 أغسطس 2026» wraps beside a one-word heading, so every
/// row was double height and the two figures — which are what the page is
/// opened for — were squeezed into the remaining half. The date is now inside
/// the row's own detail, one tap down, beside the note and the voucher number
/// it belongs with.
///
/// ── THE WIDTHS ARE MEASURED, NOT DIVIDED ────────────────────────────────────
/// They were equal thirds, and equal thirds are the wrong answer to an unequal
/// question: «500.00» needs about half the room a third gives it while «مناسبة
/// اجتماعية» needs more than one and wrapped. The table spent its width on the
/// two columns with none to spend and starved the one that had.
///
/// So [_columnWidth] measures the two money columns against the values they
/// will actually hold, and البند takes everything left over — small figures
/// leave a wide heading column and no wrapping at all. See _LedgerMetrics.
///
/// ── CENTRED, AND WRAPPING WHEN IT MUST ──────────────────────────────────────
/// A three-column table on a 360dp phone reads as three stacks, and a stack is
/// only legible if its heading sits over its values rather than beside them.
/// The heading is centred over its OWN column because header and rows are laid
/// out from one set of measurements — two independently sized Rows agree only
/// by coincidence, and stop agreeing the first time a value outgrows the word
/// above it.
///
/// A cell that fits takes one line; one that does not opens a second and
/// finishes there at the same size. See [_Cell].

/// The ledger runs a point smaller than the rest of the page, deliberately: a
/// table of figures is a different constraint from prose, and a column where
/// some rows shrank to fit is harder to read down than one that is uniformly
/// small.
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

    // ⚠ THIS SCREEN HAD NO REFRESH AT ALL, and it is the one that showed a
    //   member a stale ledger for hours. A member has no app bar and therefore
    //   no ⟳ button; the portal behind him refreshed two providers and not this
    //   one; and nothing else in the app touched it. The only thing that ever
    //   cleared it was killing the app.
    final Widget body = RefreshIndicator(
      onRefresh: () async => refreshAll(ref),
      child: AsyncView<AdeelAid>(
        value: aid,
        onRetry: () => ref.invalidate(adeelAidProvider(widget.adeelId)),
        builder: (AdeelAid data) => _AidBody(
          aid: data,
          mine: widget.mine,
          query: _query,
          search: _search,
          onQuery: (String q) => setState(() => _query = q),
        ),
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
          // ── The name, and his code FACING it across the line ──────────────
          // The code sat under the name in a small muted style, which read as a
          // caption — a footnote to the heading rather than the other half of
          // it. It is not a footnote: «A-06» is how the association refers to
          // him on every receipt and voucher, and it is what a reader checks
          // when two men share a spelling.
          //
          // So it moves to the far side of the same line and takes the same
          // size. `end` rather than left: in Arabic that is the left edge, and
          // the same widget puts it on the right in English — the rtl_lint
          // exists because a physical `left:` here would silently mirror the
          // header the first time anyone ran the app in another language.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Expanded(
                child: Text(
                  aid.adeelName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                aid.adeelCode,
                // The SAME size as the name, and muted rather than smaller:
                // matching the size is what makes the two read as one line;
                // the colour is what keeps the name the thing read first.
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
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
          // ── «حسب المناسبة» IS GONE ────────────────────────────────────────
          // It grouped the vouchers by heading above a table that now HAS a
          // heading column — so «مولود 450» sat above the very rows adding to
          // 450, and the reader had to satisfy himself twice that they were the
          // same money. The association called it duplication, which it was.
          //
          // What it uniquely answered — «كم صُرف لي في العزاء عبر السنين» — the
          // search box answers by typing the word, and it answers it against
          // the ledger itself rather than beside it.
          //
          // «حسب السنة» below is NOT the same case: the date came out of the
          // table, so nothing else on this page groups by year.

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
            // ── SHORTER, and one word inside it ─────────────────────────────
            // «ابحث بالبند أو الملاحظة أو رقم السند» described the mechanism to
            // somebody who had not asked how it worked, and a full-height field
            // gave a control the presence of a record. `isDense` with a tight
            // vertical padding takes roughly a third off it; the box is still
            // comfortably above the 48dp a thumb needs.
            //
            // The hint stays a hint: what it searches is discovered by typing,
            // which costs nothing and is how everyone uses a search box anyway.
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              hintText: l.aidSearchHint,
              prefixIcon: const Icon(Icons.search, size: 18),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 32,
              ),
              suffixIcon: needle.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        search.clear();
                        onQuery('');
                      },
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 32,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ONE container for the record: the total and the vouchers it is made
          // as two separate things when they are one answer to one question.
          // of. They were two — a headline card above a ledger panel — and read
          _AidPanel(rows: rows, aid: aid, filtered: needle.isNotEmpty),
        ],
      ],
    );
  }
}

/// The headline: what the association has given him, and nothing beside it.
///
/// ── WHAT WAS HERE AND IS NOT ────────────────────────────────────────────────
/// A «2 سند» badge and a date-range picker sat under this figure. Both were
/// removed at the association's request, and both deserved to go for the same
/// reason: the table beneath answers them better than a chip above it can. The
/// count is the length of a list the reader is looking at, and a period filter
/// on a ledger of a handful of vouchers is a control operating on a problem
/// nobody has.
///
/// What remains is the one figure the page exists for.
class _AidTotalBlock extends StatelessWidget {
  const _AidTotalBlock({required this.aid});

  final AdeelAid aid;

  @override
  Widget build(BuildContext context) {
    // ── THE FIGURE ALONE ─────────────────────────────────────────────────────
    // «إجمالي ما صُرف» stood over it and said, in four words, what the panel it
    // sits inside already says in one: the container is titled «الإجمالي». A
    // label that repeats its own heading is a line the reader has to read to
    // discover it tells him nothing.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          formatMoney(aid.total),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            // ⚠ RED, and every figure on this screen now is. It was briefly
            //   green on the reasoning that the reader is the man who RECEIVED
            //   it, so to him the money arrived. The association chose the
            //   other reading and it is the more consistent one: this page is
            //   «ما صُرف», one kind of money throughout, and it should not need
            //   two colours to say so. Red is what an outgoing amount carries
            //   on every other screen in the app.
            color: AppColors.danger,
          ),
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
                    // Red like every other figure here: one kind of money on
                    // one page needs one colour. See _AidTotalBlock.
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
class _AidPanel extends StatefulWidget {
  const _AidPanel({
    required this.rows,
    required this.aid,
    required this.filtered,
  });

  final List<AidLedgerEntry> rows;
  final AdeelAid aid;
  final bool filtered;

  @override
  State<_AidPanel> createState() => _AidPanelState();
}

class _AidPanelState extends State<_AidPanel> {
  /// The ONE voucher whose detail is open, by id. Null is none.
  ///
  /// ── WHY THE STATE MOVED UP HERE ─────────────────────────────────────────
  /// It used to live in each row, which made expansion independent: open four
  /// headings and four paragraphs of prose stack down the page, and the table
  /// the reader came to scan stops being one. The association asked for an
  /// accordion — opening a second closes the first — and that is a rule about
  /// the SET of rows, which no single row can enforce about its siblings.
  ///
  /// ⚠ BY ID, NEVER BY INDEX. A search rewrites the list, so the row at
  ///   position 2 after typing is a different voucher from the one before it.
  ///   An index would leave a different man's detail hanging open, and the
  ///   reader has no way to notice — the panel underneath simply belongs to
  ///   something else. An id that filters out matches nothing and the block
  ///   closes, which is the right answer to "the row you were reading is gone".
  int? _openId;

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
      trailing: widget.filtered
          ? Text(
              l.aidShowing(widget.rows.length, widget.aid.ledger.length),
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            )
          : null,
      child: Column(
        children: <Widget>[
          // The total stays put while a search narrows the table beneath it: it
          // is what the association gave him, not what the box is showing.
          _AidTotalBlock(aid: widget.aid),
          const Divider(height: AppSpacing.lg),
          if (widget.rows.isEmpty)
            EmptyStateView(icon: Icons.search_off, title: l.aidNoMatch)
          else
            // ── The columns are measured, not divided ────────────────────────
            // LayoutBuilder because the answer depends on the width the panel
            // actually got, which nothing above it knows. Computed once here
            // and handed down, so the header and every row are laid out from
            // the SAME numbers — which is the whole of why the heading sits
            // centred over its own column.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final TextScaler scaler = MediaQuery.textScalerOf(context);
                const TextStyle headStyle = TextStyle(
                  fontSize: _ledgerSize,
                  fontWeight: FontWeight.w800,
                );
                final _LedgerMetrics metrics = _LedgerMetrics(
                  // The ordinal column: at most three digits, and the heading
                  // word is wider than any of them. A tighter cap than the
                  // money columns because it is the least informative of the
                  // four and must never be the one that squeezes البند.
                  serial: _columnWidth(
                    values: <String>[
                      l.aidColSerial,
                      '${widget.aid.ledger.length}',
                    ],
                    style: headStyle,
                    scaler: scaler,
                    available: c.maxWidth,
                    share: 0.18,
                  ),
                  // The heading is measured with the values, not assumed
                  // narrower than them: «الإجمالي» is wider than «600.00».
                  amount: _columnWidth(
                    values: <String>[
                      l.aidColAmount,
                      for (final AidLedgerEntry e in widget.rows)
                        formatMoney(e.voucher.amount),
                    ],
                    style: headStyle,
                    scaler: scaler,
                    available: c.maxWidth,
                  ),
                  running: _columnWidth(
                    values: <String>[
                      l.aidColRunning,
                      for (final AidLedgerEntry e in widget.rows)
                        formatMoney(e.runningTotal),
                    ],
                    style: headStyle,
                    scaler: scaler,
                    available: c.maxWidth,
                  ),
                );

                return Column(
                  children: <Widget>[
                    _LedgerHead(metrics: metrics),
                    // Keyed by voucher id: a search rewrites the list, and
                    // without a key Flutter would reuse a row's element for
                    // whatever voucher lands at that index.
                    //
                    // The serial comes from the FULL ledger, not from this
                    // loop's index: it belongs to the voucher, exactly as the
                    // running total does, so a filter cannot renumber history.
                    //
                    // `open` and `onToggle` come from the PANEL, which is what
                    // makes the rows an accordion: a row cannot know whether a
                    // sibling is open, so no row can close one.
                    for (final AidLedgerEntry e in widget.rows)
                      _LedgerLine(
                        key: ValueKey<int>(e.voucher.id),
                        entry: e,
                        metrics: metrics,
                        serial: widget.aid.ledger.indexOf(e) + 1,
                        open: _openId == e.voucher.id,
                        onToggle: () => setState(
                          () => _openId = _openId == e.voucher.id
                              ? null
                              : e.voucher.id,
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

/// How wide each money column actually needs to be.
///
/// ── WHY THE COLUMNS ARE NOT THIRDS ──────────────────────────────────────────
/// They were, and equal thirds are the wrong answer to an unequal question.
/// «500.00» needs about half the room a third gives it, while «مناسبة اجتماعية»
/// needs more than a third and wrapped — so the table spent its width on the
/// two columns that had none to spend and starved the one that did.
///
/// So the two money columns are MEASURED against the values they will actually
/// hold, and البند is given everything left over. Small figures leave a wide
/// heading column and no wrapping at all; large ones take what they need and
/// the heading wraps only when it genuinely must.
///
/// ── MEASURED, NOT GUESSED ───────────────────────────────────────────────────
/// A TextPainter laid out with the very style and text scale the cell will use,
/// so the answer holds at any system font size. A hard-coded 80dp would be
/// right on one phone and wrong on the next — and wrong in the direction that
/// clips money.
///
/// Computed ONCE per render and handed to both the header and every row, which
/// is what makes the heading sit centred over its own column: two independently
/// sized Rows agree only by coincidence, and stop agreeing the first time a
/// value gets longer than the word above it.
class _LedgerMetrics {
  const _LedgerMetrics({
    required this.serial,
    required this.amount,
    required this.running,
  });

  /// The ordinal column at the far right. Narrow by nature — it holds one to
  /// three digits — and capped tighter than the money columns for the same
  /// reason: it is the least informative of the four and must never be the one
  /// that squeezes البند.
  final double serial;

  final double amount;
  final double running;
}

/// The widest string a column will hold, plus breathing room.
///
/// ⚠ CAPPED at a share of the table. A pathological figure — a treasury
///   mis-keyed as 99,999,999.00 — would otherwise take the width البند needs to
///   stay readable, and the answer to one bad row must not be an unreadable
///   table. Past the cap the money wraps instead, which is the same rule every
///   other cell here follows.
double _columnWidth({
  required Iterable<String> values,
  required TextStyle style,
  required TextScaler scaler,
  required double available,
  double share = 0.30,
}) {
  double widest = 0;
  for (final String v in values) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: v, style: style),
      textDirection: TextDirection.rtl,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = widest > tp.width ? widest : tp.width;
    tp.dispose();
  }
  // AppSpacing.sm each side: a column packed to the exact pixel reads as two
  // figures colliding, not as two columns.
  final double padded = widest + AppSpacing.sm * 2;
  final double cap = available * share;
  return padded > cap ? cap : padded;
}

/// One cell: one line when the words fit, two when they do not.
///
/// ── WHAT THIS IS NOT ────────────────────────────────────────────────────────
/// It was briefly a FittedBox that SHRANK anything too wide, so «مناسبة
/// اجتماعية» rendered a point smaller than «مولود» beside it. That bought a
/// single line at the price of a column with two type sizes in it, which is a
/// rule fighting the layout rather than serving it — and the association was
/// right to reject it. Text on a phone wraps; that is what text does.
///
/// So the cell simply lays out in the width it has. Short values take one line
/// and the row stays tight; a long one opens a second line and finishes the
/// word there, at the SAME size as everything around it.
///
/// ── WHAT MAKES TWO LINES LOOK DELIBERATE ────────────────────────────────────
/// Three things, and without them a wrapped row reads as a mistake:
///
///   • `height: 1.35` — the default leading is set for prose, and two lines of
///     a 12px table cell at it sit almost touching;
///   • the ROW is centred vertically (see _LedgerLine), so a two-line heading
///     does not drag the two figures beside it up to its first line;
///   • `maxLines: 2` with an ellipsis as the backstop. Two is what the widest
///     of the six headings needs; anything demanding a third would be a value
///     nobody typed, and letting one row grow without limit would push the rest
///     of the table off the screen.
class _Cell extends StatelessWidget {
  const _Cell(this.text, {required this.style, this.align = TextAlign.center});

  final String text;
  final TextStyle style;

  /// Centred by default — the two money columns and the ordinal read as stacks
  /// under their headings. البند passes `start`, which in RTL is the RIGHT
  /// edge: it is the column with words in it, and words are read from where
  /// they begin. Centring them left a ragged margin against the «#» beside it
  /// and cost the eye a moment on every row finding where the heading starts.
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: style.copyWith(height: 1.35),
    textAlign: align,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

class _LedgerHead extends StatelessWidget {
  const _LedgerHead({required this.metrics});

  final _LedgerMetrics metrics;

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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // البند takes what the two figures leave. It is the column with words
          // in it, so it is the one that benefits from every pixel the numbers
          // did not need.
          // FIRST in the children list, which in RTL puts it at the FAR RIGHT.
          SizedBox(
            width: metrics.serial,
            child: _Cell(l.aidColSerial, style: style),
          ),
          // Start-aligned, so the heading sits over words that begin in the
          // same place — flush with «#» on its right.
          Expanded(
            child: _Cell(
              l.aidColCategory,
              style: style,
              align: TextAlign.start,
            ),
          ),
          SizedBox(
            width: metrics.amount,
            child: _Cell(l.aidColAmount, style: style),
          ),
          SizedBox(
            width: metrics.running,
            child: _Cell(l.aidColRunning, style: style),
          ),
        ],
      ),
    );
  }
}

/// One ledger line, and the detail it hides until it is asked for.
///
/// ── WHY THE DETAIL IS FOLDED AWAY ───────────────────────────────────────────
/// The columns are the accounting and they must stay readable down the page: a
/// member scanning years of aid is reading a TABLE, and a table stops being one
/// the moment every row grows a paragraph under it. The note is the paragraph —
/// «اسم المولود» is short, but "أعطي له لعلاج والدته في تونس وتم تسليمه
/// بحضور..." is not, and one long note pushes every other line off the screen.
///
/// So the line stays one line, and tapping it opens the rest beneath it.
///
/// ── AND ONLY ONE AT A TIME ──────────────────────────────────────────────────
/// [open] and [onToggle] come from the panel; this widget holds no state of its
/// own. That is the whole mechanism of the accordion the association asked for:
/// a row cannot know whether a sibling is open, so no row can close one. Four
/// open at once put four paragraphs down a page whose point is a table.
class _LedgerLine extends StatelessWidget {
  const _LedgerLine({
    required this.entry,
    required this.metrics,
    required this.serial,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final AidLedgerEntry entry;
  final _LedgerMetrics metrics;

  /// His position in the FULL ledger, oldest as 1 — not in the filtered list.
  /// The number belongs to the voucher, exactly as the running total does, so a
  /// search cannot renumber history.
  final int serial;

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final DisbursementView v = entry.voucher;
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
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                // ── Two lines must not drag the figures up with them ───────
                // A wrapped heading makes its cell taller than the two beside
                // it, and with the default top alignment the two amounts would
                // sit level with its FIRST line — the row would read as though
                // the money belonged to the word above rather than to the row.
                // Centred, the three stay on one optical line whatever any of
                // them does.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  // FIRST in the children list, which in RTL puts it at the FAR
                  // RIGHT — beside the header cell of the same width above it.
                  //
                  // Muted, because it is an index and not a fact about the
                  // money: it should be findable when someone is looking for it
                  // and invisible when they are reading the two figures.
                  SizedBox(
                    width: metrics.serial,
                    child: _Cell(
                      '$serial',
                      style: base.copyWith(color: AppColors.muted),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        // ── The heading FIRST, flush with «#» ───────────────
                        // It used to sit after the chevron and centred, so the
                        // words began at a different place on every row and the
                        // margin against the ordinal was ragged. Now the column
                        // starts where the reader's eye already is.
                        Expanded(
                          child: _Cell(
                            v.category,
                            style: base,
                            align: TextAlign.start,
                          ),
                        ),
                        // The affordance, pinned to the far end of the column.
                        // Without it a tappable table row is a feature nobody
                        // discovers, and it doubles as the state: pointing down
                        // means "there is more", turned means "you are looking
                        // at it".
                        //
                        // At the END rather than before the word, because a
                        // chevron between «#» and the heading is exactly the
                        // gap that made the column look ragged.
                        Icon(
                          open ? Icons.expand_less : Icons.expand_more,
                          size: 14,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: metrics.amount,
                    // ── EACH DISBURSEMENT IS RED; THE TOTAL BESIDE IT IS NOT ──
                    // The association's choice, and it holds together: القيمة is
                    // ONE act of spending — money leaving the treasury, which is
                    // red on every screen in this app — while الإجمالي is what
                    // the man has received over his life with the association,
                    // which is his and is green.
                    //
                    // The two columns therefore say different things about the
                    // same figures, which is exactly what they are for.
                    child: _Cell(
                      formatMoney(v.amount),
                      style: base.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cancelled ? AppColors.muted : AppColors.danger,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: metrics.running,
                    // NEVER struck through, even on a reversed line. The amount
                    // was cancelled; the balance at that point in the ledger
                    // was not — it is simply the same figure as the line above,
                    // which is what a reversal looks like in a running total.
                    child: _Cell(
                      formatMoney(entry.runningTotal),
                      style: const TextStyle(
                        fontSize: _ledgerSize,
                        fontWeight: FontWeight.w800,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open) _LedgerDetail(voucher: v),
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
          // ── The order the association asked for ─────────────────────────────
          // Two facts to a line where they belong together, one to a line where
          // they do not. It is not decoration: «رقم الإيصال» and «التاريخ»
          // together identify the voucher — they are how it is found in a
          // folder — and «طريقة الدفع» with «المبلغ» is how the money moved.
          // Splitting either pair across two lines made the reader assemble it.
          //
          // The date used to lead the TABLE and cost more width than it
          // answered: «19 أغسطس 2026» wraps beside a one-word heading, so every
          // row was double height. Down here it sits with the number it belongs
          // to.
          _DetailPair(
            firstLabel: l.voucherNo,
            firstValue: voucher.voucherNo,
            secondLabel: l.aidColDate,
            secondValue: formatDate(voucher.spentAt),
          ),
          _DetailPair(
            firstLabel: l.method,
            firstValue: voucher.method,
            secondLabel: l.amount,
            secondValue: formatMoney(voucher.amount),
          ),
          // WHO received it, taken from the voucher itself — `payee_name` is a
          // snapshot the database wrote when the money was handed over, and
          // ck_disb_shape guarantees a member voucher carries one. Nothing here
          // is typed or inferred.
          //
          // Paired with the heading: WHO and WHAT FOR are the two halves of one
          // question, and the block now reads as THREE lines of two columns —
          // every label starting on one of two straight edges — with the note
          // alone underneath. «المُسلِّم» was between them and is gone at the
          // association's request: two lines whose Arabic differs by a letter,
          // one of them about a person the member has no reason to look up.
          _DetailPair(
            firstLabel: l.recipient,
            firstValue: voucher.payeeName,
            secondLabel: l.expenseCategory,
            secondValue: voucher.category,
          ),
          // Rule 9: a reversed voucher stays legible and says what it is.
          //
          // The ONE thing that breaks the two-column rhythm, and deliberately:
          // it appears on nothing but a struck-through voucher, so a line of
          // its own is what an exception should look like. On every normal
          // voucher the block is three pairs and a note.
          if (voucher.cancelled)
            _DetailLine(label: l.statusLabel, value: l.voided),
          // ── The note is LAST, alone, and BESIDE its label ─────────────────
          // Alone because it is prose of unknown length: «حور» is three letters
          // and a paragraph about a hospital in Tunis is not, and pairing it
          // would give whatever sat next to it a column that shrinks with the
          // sentence. Beside its label rather than under it, because a detail
          // block is read DOWN its labels and a value that steps off that
          // rhythm is the one the eye loses.
          if (voucher.note.isNotEmpty)
            _DetailLine(label: l.aidNoteLabel, value: voucher.note),
        ],
      ),
    );
  }
}

/// Two facts on one line, each with its label ABOVE it.
///
/// Used where the pair IS the fact: a voucher is identified by its number and
/// its date together — that is how it is found in a folder — and money is
/// described by its amount and how it moved. Split across two lines the reader
/// assembles them himself; side by side they read once.
///
/// ── STACKED, NOT THE 96px LABEL COLUMN [_DetailLine] USES ───────────────────
/// That column is right for a full-width line and wrong for half of one: it
/// would leave «10 فبراير 2026» about seventy pixels to live in, so the value
/// wraps, the two halves come out different heights and the labels stop being
/// level — which is the one thing a detail block is read down.
///
/// Equal halves for the same reason: sizing each to its content would start the
/// second label at a different place on every row.
class _DetailPair extends StatelessWidget {
  const _DetailPair({
    required this.firstLabel,
    required this.firstValue,
    required this.secondLabel,
    required this.secondValue,
  });

  final String firstLabel;
  final String firstValue;
  final String secondLabel;
  final String secondValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _Stacked(label: firstLabel, value: firstValue),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _Stacked(label: secondLabel, value: secondValue),
          ),
        ],
      ),
    );
  }
}

class _Stacked extends StatelessWidget {
  const _Stacked({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
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
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
