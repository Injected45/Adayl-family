import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';

/// «دفعتَ واستلمتَ سنةً بسنة» — ما دفعه المشترك وما استلمه، لكلّ سنة.
///
/// ── لماذا حلّ محلّ الموجتين ─────────────────────────────────────────────────
/// The chart before this drew two smooth waves across January→December of the
/// current year, and the association called it «غير منطقي وغير واضح». It was
/// both, for reasons worth keeping:
///
/// 1. **A curve invents values.** It rose through months that held nothing.
/// 2. **One year cannot answer the question.** A member's aid came in 2018,
///    2020, 2022 — the current year held only his 100s, so the «استلمتَ» wave
///    was a flat line on the one screen asking what came back to him.
/// 3. **Monthly amounts on one scale drown each other.** A 100 subscription
///    beside a 2,000 voucher is a line on the floor.
///
/// ── WHAT IT DRAWS INSTEAD ───────────────────────────────────────────────────
/// A PAIRED HORIZONTAL BAR per year, newest first: «دفعتَ» above «استلمتَ»,
/// both on ONE scale shared by every year, each with its word and its exact
/// figure on the same line. Horizontal because the labels are Arabic words and
/// the figures are thousands — a phone holds both across, not up. Tap a year
/// and its months (only the ones with movement) open beneath it as a table,
/// one year at a time.
///
/// ⚠ «حتى 2024» IS ONE ROW ON PURPOSE. His subscriptions before the app are a
///   single opening receipt; his aid is spread over a decade. Split by year,
///   2018 would read «استلمتَ 250، دفعتَ 0» — a man who took before he gave,
///   which the ledger never said. The server folds those years together
///   (`opening`) and the row opens onto the years inside it.
///
/// ⚠ NOTHING HERE ADDS MONEY. Every figure is summed by `api_member_value`;
///   parsing a string is a MEASUREMENT of how long to draw a bar and never
///   reaches the screen as a number.
///
/// ⚠ COLOUR IS NOT THE ONLY CHANNEL. The pair measures CVD ΔE 13.1 (light) and
///   8.3 (dark) — see AppColors.chartPaid — and still every bar carries its
///   word, «دفعتَ» is always the upper one, and a legend sits above.
class MemberYearsChart extends StatefulWidget {
  const MemberYearsChart({required this.years, super.key});

  final List<MemberYear> years;

  @override
  State<MemberYearsChart> createState() => _MemberYearsChartState();
}

class _MemberYearsChartState extends State<MemberYearsChart> {
  /// The one year whose detail is open, or null. Opening another closes it.
  String? _open;

  static double _v(String s) => double.tryParse(s) ?? 0;

  @override
  Widget build(BuildContext context) {
    final List<MemberYear> years = widget.years;
    if (years.isEmpty) return const SizedBox.shrink();
    final L l = L.of(context);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    // ⚠ ONE SCALE FOR EVERY BAR ON THE CARD. A scale per year would draw a 100
    //   and a 5,000 at the same length, and the whole point is the comparison.
    final double top = years.fold<double>(
      0,
      (double m, MemberYear y) =>
          math.max(m, math.max(_v(y.paid), _v(y.received))),
    );

    // ⚠ MEASURED, SO EVERY TRACK IS THE SAME LENGTH. If the figure took its
    //   own width, «5,415.00» would shorten its row's track and bars of equal
    //   value would end in different places.
    final double wordWidth = _measure(
      <String>[l.valuePaid, l.valueReceived],
      _wordStyle,
      scaler,
    );
    final double amountWidth = _measure(
      <String>[
        for (final MemberYear y in years) ...<String>[
          formatMoney(y.paid),
          formatMoney(y.received),
        ],
      ],
      _amountStyle,
      scaler,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.valueMonths,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  _Key(fill: AppColors.chartPaid, label: l.valuePaid),
                  _Key(fill: AppColors.chartReceived, label: l.valueReceived),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l.valueYearsHint,
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              // ⚠ THE MEASURED COLUMNS ARE CAPPED BY THE CARD, not trusted.
              //   Six-digit figures at a large system font on a 320-wide phone
              //   would otherwise leave the track no room at all.
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final double aw = math.min(amountWidth, c.maxWidth * 0.36);
                  final double ww = math.min(wordWidth, c.maxWidth * 0.22);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (int i = 0; i < years.length; i++) ...<Widget>[
                        if (i > 0)
                          Divider(height: 1, color: GlassColors.wellEdge),
                        _YearBlock(
                          year: years[i],
                          top: top,
                          wordWidth: ww,
                          amountWidth: aw,
                          open: _open == years[i].year,
                          onTap: () => setState(
                            () => _open = _open == years[i].year
                                ? null
                                : years[i].year,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  static final TextStyle _wordStyle = const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
  static final TextStyle _amountStyle = const TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  static double _measure(List<String> texts, TextStyle style, TextScaler s) {
    double w = 0;
    for (final String t in texts) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: t, style: style),
        textDirection: TextDirection.rtl,
        textScaler: s,
        maxLines: 1,
      )..layout();
      w = math.max(w, tp.width);
    }
    return w.ceilToDouble() + 2;
  }
}

/// One year: its name, two bars, and — when open — its months.
class _YearBlock extends StatelessWidget {
  const _YearBlock({
    required this.year,
    required this.top,
    required this.wordWidth,
    required this.amountWidth,
    required this.open,
    required this.onTap,
  });

  final MemberYear year;
  final double top;
  final double wordWidth;
  final double amountWidth;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final String label = year.opening
        ? l.valueOpeningYear(year.year)
        : year.year;
    final bool openable = year.parts.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          button: openable,
          expanded: openable ? open : null,
          label:
              '$label · ${l.valuePaid} ${formatMoney(year.paid)} · '
              '${l.valueReceived} ${formatMoney(year.received)}',
          excludeSemantics: true,
          child: InkWell(
            onTap: openable ? onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (openable)
                        Icon(
                          open ? Icons.expand_less : Icons.expand_more,
                          size: 20,
                          color: AppColors.muted,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _BarLine(
                    label: l.valuePaid,
                    amount: year.paid,
                    top: top,
                    fill: AppColors.chartPaid,
                    tone: AppColors.success,
                    wordWidth: wordWidth,
                    amountWidth: amountWidth,
                  ),
                  const SizedBox(height: 6),
                  _BarLine(
                    label: l.valueReceived,
                    amount: year.received,
                    top: top,
                    fill: AppColors.chartReceived,
                    tone: AppColors.danger,
                    wordWidth: wordWidth,
                    amountWidth: amountWidth,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open && openable)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _PartsTable(parts: year.parts, byYear: year.opening),
          ),
      ],
    );
  }
}

/// «دفعتَ ▬▬▬▬▬▬▬▬  5,415.00»
class _BarLine extends StatelessWidget {
  const _BarLine({
    required this.label,
    required this.amount,
    required this.top,
    required this.fill,
    required this.tone,
    required this.wordWidth,
    required this.amountWidth,
  });

  final String label;
  final String amount;
  final double top;
  final Color fill;
  final Color tone;
  final double wordWidth;
  final double amountWidth;

  static const double _thickness = 10;

  @override
  Widget build(BuildContext context) {
    final double value = double.tryParse(amount) ?? 0;
    final bool nothing = value <= 0;

    return Row(
      children: <Widget>[
        SizedBox(
          width: wordWidth,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints c) {
              // ⚠ A FLOOR OF 4px FOR ANY REAL AMOUNT. A 100 against a 5,415
              //   scale is two pixels — present in the data and invisible on
              //   the glass. Zero draws no fill at all, so «nothing» and «a
              //   little» never look alike.
              final double w = nothing || top <= 0
                  ? 0
                  : math.max(4, c.maxWidth * (value / top));
              return Stack(
                key: const ValueKey<String>('year-track'),
                alignment: AlignmentDirectional.centerStart,
                children: <Widget>[
                  Container(
                    height: _thickness,
                    decoration: BoxDecoration(
                      color: GlassColors.well,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  Container(
                    width: math.min(w, c.maxWidth),
                    height: _thickness,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: amountWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(
              formatMoney(amount),
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                // A zero is not a figure worth a colour.
                color: nothing ? AppColors.muted : tone,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The months of an opened year — or, under «حتى 2024», the years inside it.
///
/// ⚠ ONLY THE LINES THAT HELD SOMETHING, as the server sends them. Twelve rows
///   of dashes for a year with four receipts would be the empty-month problem
///   of the old chart again, in a table.
class _PartsTable extends StatelessWidget {
  const _PartsTable({required this.parts, required this.byYear});

  final List<MemberYearPart> parts;
  final bool byYear;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final TextStyle head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.muted,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: GlassColors.well,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: GlassColors.wellEdge),
      ),
      child: Column(
        children: <Widget>[
          _PartRow(
            label: Text(byYear ? l.valueColYear : l.valueColMonth, style: head),
            paid: Text(l.valuePaid, style: head),
            received: Text(l.valueReceived, style: head),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final MemberYearPart p in parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: _PartRow(
                label: p.isMonth
                    ? Text(
                        // ⚠ A MONTH IS BLUE, on every screen — AppColors.month.
                        monthName(int.tryParse(p.key.substring(5, 7)) ?? 1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.month,
                        ),
                      )
                    : Text(
                        p.key,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                paid: _figure(p.paid, AppColors.success),
                received: _figure(p.received, AppColors.danger),
              ),
            ),
        ],
      ),
    );
  }

  /// A zero is a dash, not «0.00» in colour: the cell has nothing to say.
  static Widget _figure(String amount, Color tone) {
    final bool nothing = (double.tryParse(amount) ?? 0) <= 0;
    return Text(
      nothing ? '—' : formatMoney(amount),
      maxLines: 1,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: nothing ? AppColors.muted : tone,
      ),
    );
  }
}

class _PartRow extends StatelessWidget {
  const _PartRow({
    required this.label,
    required this.paid,
    required this.received,
  });

  final Widget label;
  final Widget paid;
  final Widget received;

  @override
  Widget build(BuildContext context) {
    // ⚠ PROPORTIONS, NOT THE BAR'S MEASURED WIDTH. Two six-digit figures and
    //   a month name do not fit a 320-wide phone at fixed widths; shares do,
    //   and every row takes the same shares, so the columns still line up.
    Widget cell(Widget child) => Expanded(
      flex: 5,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: child,
      ),
    );
    return Row(
      children: <Widget>[
        Expanded(
          flex: 4,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: label,
          ),
        ),
        cell(paid),
        const SizedBox(width: AppSpacing.sm),
        cell(received),
      ],
    );
  }
}

/// A short bar and a word — the legend entry. The word wears ink, not the
/// series colour; the mark carries the identity.
class _Key extends StatelessWidget {
  const _Key({required this.fill, required this.label});

  final Color fill;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(
        width: 16,
        height: 8,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
    ],
  );
}
