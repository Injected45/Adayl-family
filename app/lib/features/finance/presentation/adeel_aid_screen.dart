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
import 'aid_ledger.dart';
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
            color: AppColors.success,
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
                    color: AppColors.success,
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
                  color: AppColors.success,
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
          // ⚠ THE TABLE ITSELF LIVES IN aid_ledger.dart, shared verbatim with
          //   «أسلاف للغير». Every rule inside it was argued once — measured
          //   columns, an ordinal that belongs to the voucher rather than to
          //   the loop, a reversal that keeps its balance, one open row at a
          //   time — and a second copy would be a second place for each of
          //   them to be quietly undone, with nothing failing when it was.
          // ⚠ GREEN, at the association's request: «اريد ان يكون لون القيم
          //   في شاشة اسلافي جميعها باللون الاخضر». And it is the right way
          //   round — this is what the association GAVE him. Red is the
          //   colour of money leaving the treasury, which is true from the
          //   fund's side and false from his: nothing on this page is a debt
          //   of his, and الجمعية خيرية so none of it is owed back.
          AidLedger(
            all: widget.aid.ledger,
            rows: widget.rows,
            tone: AppColors.success,
          ),
        ],
      ),
    );
  }
}
