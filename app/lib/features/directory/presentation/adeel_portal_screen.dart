import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Shown in a money column that has no figure on this line. A charge has no
/// credit and a receipt has no debit, and a ledger says so with a rule rather
/// than with `0.00` — a zero is a figure, and reading four of them down a column
/// is how a real balance gets missed.
const String _noFigure = '—';

/// What an عديل sees: his own record and his own money, and nothing of the
/// association's.
///
/// Deliberately NOT an AppScaffold. That widget carries the navigation bar, and
/// every destination on it is a screen he must not reach — the router refuses
/// him anyway, so offering the tabs and then bouncing him back would be a worse
/// interface than not offering them at all.
///
/// It reuses `api_adeel_detail` and `api_adeel_statement` rather than adding
/// portal-only endpoints. Both are SECURITY INVOKER, so the very call an admin
/// makes returns only what RLS allows THIS caller — one عديل. A separate
/// endpoint would be a second place for the scoping to be got wrong, and only
/// one of them would be covered by supabase/tests/45_adeel_portal.sql.
class AdeelPortalScreen extends ConsumerWidget {
  const AdeelPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final int? adeelId = auth.user?.adeelId;

    // The router guarantees this. Without it, the frame between redeeming a
    // code and the redirect landing would be a crash rather than a spinner.
    if (adeelId == null) return const LoadingStateView();

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l.myFamilyTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout),
                      tooltip: l.signOut,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AsyncView<AdeelDetail>(
                  value: ref.watch(adeelDetailProvider(adeelId)),
                  onRetry: () => ref.invalidate(adeelDetailProvider(adeelId)),
                  builder: (AdeelDetail data) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(adeelDetailProvider(adeelId));
                      ref.invalidate(statementProvider(adeelId));
                    },
                    child: _PortalBody(adeelId: adeelId, detail: data),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalBody extends ConsumerWidget {
  const _PortalBody({required this.adeelId, required this.detail});

  final int adeelId;
  final AdeelDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<Statement> statement = ref.watch(
      statementProvider(adeelId),
    );

    return ListView(
      padding: screenPadding(context),
      children: <Widget>[
        _AccountCard(detail: detail),
        const SizedBox(height: AppSpacing.xl),

        // The household roster is gone: there is no household, and the only
        // person on this page is the one reading it. What replaces it is what he
        // actually came for — which months he owes.
        _SectionTitle(l.myDuesTitle),
        for (final ReceivableItem item in detail.receivables)
          _DueTile(item: item),

        const SizedBox(height: AppSpacing.xl),
        statement.when(
          loading: () => const LoadingStateView(),
          error: (Object error, StackTrace _) =>
              ErrorStateView(message: describeApiFailure(l, error)),
          data: (Statement data) => _Ledger(statement: data, detail: detail),
        ),
      ],
    );
  }
}

/// Who he is and what he owes, in one card.
///
/// This used to be a four-up grid of equal stat tiles, which gave the monthly
/// fee the same weight as the balance and answered none of "is this my record".
/// The identity comes first because he has just typed an access code and the
/// first thing he needs is confirmation it bound him to the right man.
class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.detail});

  final AdeelDetail detail;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AdeelView adeel = detail.adeel;

    // A comparison, not arithmetic: money stays text end to end, and the only
    // thing decided here is which colour the figure wears.
    final bool owes = (double.tryParse(detail.debt) ?? 0) > 0;

    final Color statusTone = switch (adeel.membershipStatus) {
      MembershipStatusWire.active => AppColors.success,
      MembershipStatusWire.suspended => AppColors.warning,
      _ => AppColors.muted,
    };

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      adeel.fullName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      adeel.adeelCode,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // The status the database stores, verbatim — what he reads here
              // and what the treasurer reads cannot diverge.
              StatusBadge(label: adeel.membershipStatus, tone: statusTone),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // The one figure he opened the app for. Given a tinted block of its
          // own rather than a tile in a grid, because "what do I owe" is not one
          // fact among four.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: owes ? AppColors.dangerSoft : AppColors.successSoft,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  owes ? l.balanceDueLabel : l.balanceSettledLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: owes ? AppColors.danger : AppColors.success,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    formatMoney(detail.debt),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: owes ? AppColors.danger : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Wrap, not a Row of Expanded: at a large text scale three fixed
          // columns clip, and these wrap onto a second line instead.
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: <Widget>[
              _Field(
                label: l.monthlyFeeLabel,
                value: formatMoney(detail.monthlyExpected),
              ),
              _Field(
                label: l.registeredAt,
                value: formatDate(adeel.registeredAt),
              ),
              if (adeel.phone.isNotEmpty)
                _Field(label: l.phone, value: adeel.phone),
            ],
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

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
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// The statement, as a ledger.
///
/// The data was always right: `api_adeel_statement` already returns a debit, a
/// credit and a RUNNING BALANCE for every movement, computed by a window
/// function in SQL. What was wrong was the reading — the old tile threw the
/// balance away and printed one coloured number per row, so a charge and a
/// receipt looked like the same kind of event and nothing showed how the two of
/// them met. Every figure below is the server's; none is added up here.
class _Ledger extends StatefulWidget {
  const _Ledger({required this.statement, required this.detail});

  final Statement statement;
  final AdeelDetail detail;

  /// How many movements one page holds.
  ///
  /// A statement is read top-down, so the cost of too many rows is not the
  /// scrolling — it is that the reader loses which balance belongs to which
  /// month. Ten is about what stays graspable on a phone without a scroll
  /// gesture between a movement and its balance. One constant, one place to
  /// change it.
  static const int rowsPerPage = 10;

  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  final TextEditingController _search = TextEditingController();

  /// Pages revealed so far. Pages after this exist and are simply not built —
  /// the statement is already in memory, so "loading" more is instant and the
  /// button is about how much is ASKED FOR, not about fetching.
  int _pagesShown = 1;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    // Back to one page on every keystroke. Without this, searching after
    // revealing six pages shows six pages of a two-row result and the "show
    // more" button vanishes with no explanation of what changed.
    setState(() => _pagesShown = 1);
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    if (widget.statement.movements.isEmpty) {
      return Column(
        children: <Widget>[
          _SectionTitle(l.myStatementSection),
          EmptyStateView(icon: Icons.receipt_long, title: l.noMovements),
        ],
      );
    }

    final List<StatementMovement> matches = _filter(
      widget.statement.movements,
      _search.text,
      widget.detail,
    );
    final int total = matches.length;
    final int shown = (_pagesShown * _Ledger.rowsPerPage).clamp(0, total);
    final int remaining = total - shown;

    // Columns are sized in scaled pixels, so the table grows with the reader's
    // text size instead of clipping at it. Below the width that needs, it
    // scrolls sideways inside its own box — the page itself never does.
    final double k = MediaQuery.textScalerOf(context).scale(13) / 13;
    final double money = 84 * k;
    final double particulars = 128 * k;

    return GlassPanel(
      title: l.myStatementSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // OUTSIDE the horizontal scroller below on purpose: the table may be
          // wider than the panel and scroll sideways, and a search box that
          // slid away with it would be unreachable exactly when the table is
          // at its most crowded.
          TextField(
            controller: _search,
            onChanged: (_) => _onQueryChanged(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: l.statementSearchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: l.clearSearch,
                      onPressed: () {
                        _search.clear();
                        _onQueryChanged();
                      },
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                l.noSearchResults,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            )
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double needed = particulars + money * 3;
                final double width = constraints.maxWidth > needed
                    ? constraints.maxWidth
                    : needed;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: <Widget>[
                        _LedgerHead(money: money),
                        for (int i = 0; i < shown; i++)
                          _LedgerRow(
                            movement: matches[i],
                            money: money,
                            // Zebra striping. A four-column table of
                            // near-identical numbers is where the eye slips a
                            // line, and the stripe is what keeps a balance
                            // attached to its own movement.
                            shaded: i.isOdd,
                          ),
                        // The totals stay the ACCOUNT's, never the filtered
                        // set's: closingBalance is the server's window
                        // function over every movement, and a bank statement
                        // narrowed by a search still states what the account
                        // stands at. Summing the visible rows here would
                        // invent a second, disagreeing figure.
                        _LedgerTotals(
                          detail: widget.detail,
                          statement: widget.statement,
                          money: money,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          if (total > 0) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _LedgerPager(
              shown: shown,
              total: total,
              remaining: remaining,
              pageSize: _Ledger.rowsPerPage,
              onMore: () => setState(() => _pagesShown++),
              onAll: () => setState(
                () => _pagesShown =
                    (total / _Ledger.rowsPerPage).ceil().clamp(1, 1 << 30),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Free-text search over a statement, matching ANY part of ANY movement.
///
/// ── Why this cannot be a plain `contains` ───────────────────────────────────
/// What the reader SEES and what the row HOLDS are different strings.
/// `formatMoney` renders through `ar_LY`, so 20.00 appears as ٢٠٫٠٠, and
/// `formatDate` renders 2026-03-15 as ١٥‏/٣‏/٢٠٢٦. A search box that matched
/// the raw values would fail for anyone typing what is on their screen, and one
/// that matched only the formatted values would fail for anyone typing on a
/// Latin keyboard. Both forms go into the haystack, and the query is folded to
/// one digit system, so either way of typing the same number finds the row.
///
/// The عديل's own name and phone are searchable too, as asked. They are the
/// same on every row of his statement, so typing his name matches everything —
/// which is the honest answer to "search by any part", not a bug.
List<StatementMovement> _filter(
  List<StatementMovement> movements,
  String query,
  AdeelDetail detail,
) {
  final String needle = _fold(query);
  if (needle.isEmpty) return movements;

  // Every term must match, in any field and in any order: "دفعة ٢٠" finds the
  // 20.00 payments without the reader having to know which column is which.
  final List<String> terms = needle.split(RegExp(r'\s+'))
    ..removeWhere((String t) => t.isEmpty);

  return <StatementMovement>[
    for (final StatementMovement m in movements)
      if (terms.every(_haystack(m, detail).contains)) m,
  ];
}

String _haystack(StatementMovement m, AdeelDetail detail) => _fold(
  <String>[
    m.date, formatDate(m.date),
    m.reference,
    m.type,
    m.debit ?? '', formatMoney(m.debit),
    m.credit ?? '', formatMoney(m.credit),
    m.balance, formatMoney(m.balance),
    m.note,
    detail.adeel.fullName,
    detail.adeel.phone,
    detail.adeel.adeelCode,
  ].join(' '),
);

/// Folds a string to one comparable form: Arabic-Indic digits become Latin,
/// the Arabic letters that are typed interchangeably are unified, and the marks
/// a reader never types are dropped.
///
/// Without the letter folding, someone searching for إبراهيم by typing ابراهيم
/// gets nothing — the two differ only in a hamza most keyboards make awkward.
/// Without the digit folding, no amount on screen is findable by typing it.
String _fold(String input) {
  final StringBuffer out = StringBuffer();
  for (final int rune in input.toLowerCase().runes) {
    // Arabic-Indic ٠-٩ (U+0660) and Extended Arabic-Indic ۰-۹ (U+06F0).
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + rune - 0x0660);
      continue;
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + rune - 0x06F0);
      continue;
    }
    switch (rune) {
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
        out.writeCharCode(0x0627); // ا
      case 0x0649: // ى
        out.writeCharCode(0x064A); // ي
      case 0x0629: // ة
        out.writeCharCode(0x0647); // ه
      // The Arabic decimal separator ٫ and thousands separator ٬ that
      // NumberFormat emits, plus the bidi marks it wraps dates in. A reader
      // types '.' or nothing at all for these.
      case 0x066B:
        out.writeCharCode(0x2E); // .
      case 0x066C:
      case 0x200E:
      case 0x200F:
      case 0x061C:
        break;
      // Arabic diacritics: never typed, always noise.
      default:
        if (rune >= 0x064B && rune <= 0x0652) break;
        out.writeCharCode(rune);
    }
  }
  return out.toString().trim();
}

/// "Showing 10 of 47", and the button that reveals the next page.
///
/// Progressive rather than numbered: a statement is read in order, so page 4 of
/// a ledger means nothing on its own — what the reader wants is more of the
/// same list, continuing from where it stopped. `عرض الكل` is there for the
/// reader who wants to scan or search the lot at once.
class _LedgerPager extends StatelessWidget {
  const _LedgerPager({
    required this.shown,
    required this.total,
    required this.remaining,
    required this.pageSize,
    required this.onMore,
    required this.onAll,
  });

  final int shown;
  final int total;
  final int remaining;
  final int pageSize;
  final VoidCallback onMore;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    // Column over Wrap, not a single Row: the count and two Arabic labels do not
    // fit one line on a narrow phone at a large text size, and a Row would
    // overflow rather than reflow.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.statementShowing(shown, total),
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        if (remaining > 0)
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              TextButton(
                onPressed: onMore,
                child: Text(
                  l.statementShowMore(
                    remaining < pageSize ? remaining : pageSize,
                  ),
                ),
              ),
              TextButton(onPressed: onAll, child: Text(l.statementShowAll)),
            ],
          ),
      ],
    );
  }
}

class _LedgerHead extends StatelessWidget {
  const _LedgerHead({required this.money});

  final double money;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    const TextStyle style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: AppColors.inkMuted,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.neutralSoft,
        border: Border(bottom: BorderSide(color: AppColors.inkMuted, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(l.ledgerParticulars, style: style)),
          _Cell(
            width: money,
            child: Text(l.ledgerDebit, style: style),
          ),
          _Cell(
            width: money,
            child: Text(l.ledgerCredit, style: style),
          ),
          _Cell(
            width: money,
            child: Text(l.ledgerBalance, style: style),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.movement,
    required this.money,
    required this.shaded,
  });

  final StatementMovement movement;
  final double money;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final String? debit = movement.debit;
    final String? credit = movement.credit;
    final bool isCharge = debit != null && debit.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: shaded ? AppColors.neutralSoft : null,
        border: const Border(
          bottom: BorderSide(color: AppColors.line, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  movement.note.isEmpty ? movement.reference : movement.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // The kind of movement in words, so the column a figure sits
                  // in is not the only thing that says what it was.
                  '${movement.type} • ${formatDate(movement.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          _Money(
            width: money,
            text: isCharge ? formatMoney(debit) : _noFigure,
            tone: isCharge ? AppColors.danger : AppColors.muted,
          ),
          _Money(
            width: money,
            text: isCharge ? _noFigure : formatMoney(credit),
            tone: isCharge ? AppColors.muted : AppColors.success,
          ),
          _Money(
            width: money,
            text: formatMoney(movement.balance),
            tone: AppColors.ink,
            bold: true,
          ),
        ],
      ),
    );
  }
}

/// The closing line: what was charged, what was received, what is left.
///
/// All three come from the server — `issued` and `paid` off v_adeels, the
/// balance off the statement's own window function. Summing the rows in Dart
/// would put the association's totals on binary floating point, which is the
/// one thing the money-as-text rule exists to prevent.
class _LedgerTotals extends StatelessWidget {
  const _LedgerTotals({
    required this.detail,
    required this.statement,
    required this.money,
  });

  final AdeelDetail detail;
  final Statement statement;
  final double money;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool owes = (double.tryParse(statement.closingBalance) ?? 0) > 0;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.inkMuted, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l.ledgerTotals,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
          _Money(
            width: money,
            text: formatMoney(detail.issued),
            tone: AppColors.danger,
            bold: true,
          ),
          _Money(
            width: money,
            text: formatMoney(detail.paid),
            tone: AppColors.success,
            bold: true,
          ),
          _Money(
            width: money,
            text: formatMoney(statement.closingBalance),
            tone: owes ? AppColors.danger : AppColors.success,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
}

/// A figure in a money column.
///
/// `TextAlign.start` looks wrong for a number until you follow it through: the
/// column is RTL, so start is the RIGHT edge, and digits render left-to-right
/// inside it — which puts the LAST character of every figure on that same edge.
/// With two decimal places on all of them, that is decimal alignment, and it is
/// what lets a column of figures be read down rather than one at a time.
class _Money extends StatelessWidget {
  const _Money({
    required this.width,
    required this.text,
    required this.tone,
    this.bold = false,
  });

  final double width;
  final String text;
  final Color tone;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return _Cell(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.start,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: tone,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({required this.item});

  final ReceivableItem item;

  @override
  Widget build(BuildContext context) {
    final bool settled = item.status == ReceivableStatusWire.fullyPaid;
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.periodLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoney(item.total),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ),
          // The status label is the value the database stores, so what he reads
          // here and what the treasurer reads cannot diverge.
          StatusBadge(
            label: item.status,
            tone: settled ? AppColors.success : AppColors.warning,
          ),
        ],
      ),
    );
  }
}
