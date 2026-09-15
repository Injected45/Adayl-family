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

/// The two containers a member's «أسلافي» folds.
enum _AidSection { byYear, total }

class _AdeelAidScreenState extends ConsumerState<AdeelAidScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Which container is open on the member's page — at most one, and none
  /// until he taps. See [_FoldingPanel].
  _AidSection? _open;

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
          open: _open,
          onToggle: (_AidSection s) =>
              setState(() => _open = _open == s ? null : s),
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
    required this.open,
    required this.onToggle,
  });

  final AdeelAid aid;
  final bool mine;
  final String query;
  final TextEditingController search;
  final ValueChanged<String> onQuery;

  /// ── مطويّتان على صفحة المشترك، وواحدةٌ مفتوحة على الأكثر ─────────────
  ///
  /// ⚠ BOTH PAGES NOW. It began on the member's page only — «في واجهة المشترك
  ///   … اجعل الحاويتين مطوية ولا تفتح الا بامر المستخدم وعند فتح الثانية
  ///   تقفل الاولي» — on the reasoning that staff come to WORK a record and a
  ///   fold puts a tap in front of it. On 15/09 the association asked for the
  ///   same on the admin's «سجل الأسلاف»: «اجعلهما منسدلتان». One rule, one
  ///   layout, for both readers.
  final _AidSection? open;
  final ValueChanged<_AidSection> onToggle;

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

    final Widget yearRows = Column(
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
    );

    final Widget searchField = TextField(
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
    );

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
            _FoldingPanel(
              title: l.aidByYear,
              icon: Icons.calendar_month_outlined,
              open: open == _AidSection.byYear,
              onTap: () => onToggle(_AidSection.byYear),
              child: yearRows,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── الإجمالي، مطويّاً ─────────────────────────────────────────
          // ⚠ THE FIGURE RIDES THE HEADING WHILE IT IS CLOSED. Two closed
          //   headings and no number would be a page that answers nothing
          //   until tapped; the total is the one figure this page exists
          //   for, so it stays in sight and the ledger is what folds.
          //
          // ⚠ AND THE SEARCH FOLDS WITH THE TABLE IT FILTERS. A search box
          //   above a closed container searches nothing the reader can see.
          _FoldingPanel(
            title: l.aidPanelTitle,
            icon: Icons.receipt_long_outlined,
            open: open == _AidSection.total,
            onTap: () => onToggle(_AidSection.total),
            trailing: Text(
              formatMoney(aid.total),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.success,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                searchField,
                if (needle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l.aidShowing(rows.length, aid.ledger.length),
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                AidLedger(all: aid.ledger, rows: rows, tone: AppColors.success),
              ],
            ),
          ),
        ],
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
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  formatMoney(widget.amount),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    // Red like every other figure here: one kind of money on
                    // one page needs one colour.
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  formatDate(voucher.spentAt),
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
              Text(
                formatMoney(voucher.amount),
                style: TextStyle(
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

/// A container that shows only its heading until it is tapped.
///
/// ── WHY NOT ExpansionTile ───────────────────────────────────────────────────
/// ExpansionTile keeps its own open state, and this page needs the OPPOSITE of
/// independent tiles: «عند فتح الثانية تقفل الاولي». The state lives in the
/// screen (`_open`), and each panel is told whether it is the open one — the
/// only arrangement in which two panels cannot both be open by accident.
///
/// ⚠ THE WHOLE HEADING IS THE TARGET, not the chevron. A 20px icon is a
///   precision tap on a moving phone; the heading row is the width of the card.
class _FoldingPanel extends StatelessWidget {
  const _FoldingPanel({
    required this.title,
    required this.icon,
    required this.open,
    required this.onTap,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final bool open;
  final VoidCallback onTap;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            button: true,
            expanded: open,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Row(
                children: <Widget>[
                  // The same tile GlassPanel draws, so a folded panel and an
                  // open one are recognisably the same container.
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 18, color: AppColors.brandDeep),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    // ⚠ A CAP, NOT A Flexible. Flexible beside the Expanded
                    //   title split the row in half and left the chevron in
                    //   the middle of the card instead of at its edge.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: trailing,
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...<Widget>[const SizedBox(height: AppSpacing.lg), child],
        ],
      ),
    );
  }
}
