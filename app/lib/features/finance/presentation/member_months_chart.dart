import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';

/// «الجدوى» عبر الزمن — كم دفعتَ تراكمياً، وكم عاد إليك، شهراً بعد شهر.
///
/// ── لماذا أُعيد بناؤه ───────────────────────────────────────────────────────
/// The first version drew a column per month for each series, side by side, and
/// the association rejected it in the right words: «الخطان يعبّران عن إجمالي
/// قيمة، وفي الأسفل أشهر — وهذا اختلاف كبير جداً ولا يؤدي الغرض … اجعل الأسلاف
/// كرسم بياني لا كمؤشر عمودي متجمد».
///
/// ⚠ AND THE REAL DEFECT WAS THE TWO SERIES HAVING DIFFERENT RHYTHMS ON ONE
///   SCALE. Subscriptions arrive every month and are small; aid arrives once in
///   two years and is large. Drawn as sibling columns, the aid became a single
///   lone spike — a «مؤشر عمودي متجمد» exactly as he said — and beside it every
///   subscription column was flattened to a few pixels. One scale is the right
///   rule; two series that cannot share one are the wrong SHAPE for it.
///
/// ── الشكل الصحيح: خطّان تراكميّان ───────────────────────────────────────────
/// Cumulative totals are comparable, and they answer the question the screen
/// exists for. What «الجدوى» asks is «ما الذي دفعتُه مقابل ما أخذتُه» — and on a
/// cumulative chart the answer is not a number to compute, it is **the vertical
/// gap between the two lines**, readable at any month without arithmetic.
///
/// - A month of aid becomes a STEP in the green line rather than a lone spike.
/// - Steady subscriptions become a steady climb in the blue.
/// - A month with nothing is a FLAT segment, which is truthful: the cumulative
///   value really is unchanged.
///
/// ⚠ STEPS, NOT A SLOPE BETWEEN POINTS. The old note here objected to lines on
///   the grounds that «a line from January to March asserts a value for
///   February». That objection is right for a per-month series and disappears
///   for a cumulative one — but only if the line is drawn as a STEP. A diagonal
///   would still invent a gradual payment across a month in which nothing was
///   paid at all.
///
/// ── ولا شيء هنا يجمع مالاً ─────────────────────────────────────────────────
/// Every figure arrives already summed by `api_member_value`. The running total
/// below is a MEASUREMENT — how high to put a pixel — and it never reaches the
/// screen as a number: the end labels print the server's own text for the last
/// month, which is the same total the two figures above the chart show.
class MemberMonthsChart extends StatelessWidget {
  const MemberMonthsChart({required this.months, super.key});

  final List<MemberMonth> months;

  /// Nothing to plot is not a chart with twelve flat lines.
  ///
  /// ⚠ A MAN WHO HAS NEVER PAID would otherwise get a full-width graphic that
  ///   says nothing, on the one screen built to answer «ما الجدوى».
  bool get _hasMovement => months.any(
    (MemberMonth m) =>
        (double.tryParse(m.paid) ?? 0) > 0 ||
        (double.tryParse(m.received) ?? 0) > 0,
  );

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty || !_hasMovement) return const SizedBox.shrink();
    final L l = L.of(context);

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
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ⚠ A LEGEND, ALWAYS, FOR TWO SERIES — identity must never rest on
              //   colour alone. It carries the LINE STYLE too, because the pair
              //   validates at ΔE 6.4 under tritanopia, which is the floor band
              //   and legal only with a second channel. The dash IS that
              //   channel, and it is drawn here exactly as it is on the chart.
              Row(
                children: <Widget>[
                  _Key(tone: AppColors.info, label: l.valuePaid, dashed: false),
                  const SizedBox(width: AppSpacing.md),
                  _Key(
                    tone: AppColors.success,
                    label: l.valueReceived,
                    dashed: true,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 168,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) =>
                      CustomPaint(
                        size: Size(c.maxWidth, 168),
                        painter: _CumulativePainter(
                          months: months,
                          textScale: MediaQuery.textScalerOf(context),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A mark and a word — the legend entry.
///
/// ⚠ THE WORD IS NOT IN THE SERIES COLOUR. A coloured label reads as data, and
///   an 11px indigo word on glass is harder to read than the same word in ink.
///   The mark beside it carries the identity; the text wears a text token.
class _Key extends StatelessWidget {
  const _Key({required this.tone, required this.label, required this.dashed});

  final Color tone;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      CustomPaint(size: const Size(16, 8), painter: _KeyMark(tone, dashed)),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.muted),
      ),
    ],
  );
}

class _KeyMark extends CustomPainter {
  const _KeyMark(this.tone, this.dashed);

  final Color tone;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = tone
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final double y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
      return;
    }
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 3.5, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_KeyMark old) =>
      old.tone != tone || old.dashed != dashed;
}

/// خطّان تراكميّان، والفجوة بينهما هي الجواب.
class _CumulativePainter extends CustomPainter {
  _CumulativePainter({required this.months, required this.textScale});

  final List<MemberMonth> months;
  final TextScaler textScale;

  /// Room for the month labels under the plot.
  static const double _axis = 18;

  double _v(String s) => double.tryParse(s) ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;

    // ── The two cumulative series, AS THE SERVER SENT THEM ─────────────────
    // ⚠ READ, NOT ADDED. A Dart loop totalling a year of receipts is the app
    //   doing arithmetic on money — the one thing the text-money rule forbids
    //   — and member_months_chart_test enforces it by reading this source. It
    //   caught exactly that loop here, and PATCH_20260821f moved the running
    //   total into a window function in api_member_value, which is where
    //   api_adeel_aid has always computed its ledger column.
    //
    //   What is left is a MEASUREMENT: how high to put a pixel. It never
    //   reaches the screen as a number.
    final List<double> paid = months
        .map((MemberMonth m) => _v(m.paidTotal))
        .toList();
    final List<double> got = months
        .map((MemberMonth m) => _v(m.receivedTotal))
        .toList();

    final double top = math.max(paid.last, got.last);
    // A flat pair of zero lines is not a chart; _hasMovement already excludes
    // it, and this only guards a divide.
    if (top <= 0) return;

    final double h = size.height - _axis;
    final int n = months.length;
    final double step = n <= 1 ? size.width : size.width / (n - 1);

    // ⚠ RTL: the earliest month is on the RIGHT. Mirroring the x axis is what
    //   makes time run the way the reader's eye does in this app; a chart that
    //   ran left-to-right under Arabic labels would read backwards.
    double x(int i) => size.width - i * step;
    double y(double v) => h - (v / top) * (h - 8);

    // ── The band between the lines: «الجدوى» itself ────────────────────────
    // ⚠ NEUTRAL, NOT A THIRD COLOUR. It is not a series — it is the DIFFERENCE
    //   between two, and giving it a hue of its own would put three things on a
    //   two-colour chart. Muted at 10% reads as shading rather than as data.
    final Path band = Path()..moveTo(x(0), y(paid[0]));
    for (int i = 1; i < n; i++) {
      band
        ..lineTo(x(i), y(paid[i - 1]))
        ..lineTo(x(i), y(paid[i]));
    }
    for (int i = n - 1; i >= 1; i--) {
      band
        ..lineTo(x(i), y(got[i]))
        ..lineTo(x(i), y(got[i - 1]));
    }
    band
      ..lineTo(x(0), y(got[0]))
      ..close();
    canvas.drawPath(
      band,
      Paint()..color = AppColors.muted.withValues(alpha: 0.10),
    );

    // ── The baseline, recessive ────────────────────────────────────────────
    canvas.drawLine(
      Offset(0, h),
      Offset(size.width, h),
      Paint()
        ..color = GlassColors.wellEdge
        ..strokeWidth = 1,
    );

    _series(canvas, paid, x, y, AppColors.info, dashed: false);
    _series(canvas, got, x, y, AppColors.success, dashed: true);

    // ── Month labels on the extremes only ──────────────────────────────────
    // ⚠ TWO, NOT TWELVE. Twelve Arabic month names across a phone collide into
    //   a grey smear; the first and the last say what span the chart covers,
    //   which is the whole job of this axis.
    //
    // ⚠ AND THEY STAY MUTED, which is the one written exception to «a month is
    //   blue» — see AppColors.month. On this chart AppColors.info is ALREADY
    //   the «دفعتَ» series, so a blue axis would read as belonging to it.
    _text(canvas, formatMonthShort(months.first.period), x(0), h + 3, end: true);
    _text(
      canvas,
      formatMonthShort(months.last.period),
      x(n - 1),
      h + 3,
      end: false,
    );
  }

  /// One cumulative line, drawn as steps.
  void _series(
    Canvas canvas,
    List<double> v,
    double Function(int) x,
    double Function(double) y,
    Color tone, {
    required bool dashed,
  }) {
    final Path path = Path()..moveTo(x(0), y(v[0]));
    for (int i = 1; i < v.length; i++) {
      // Across the month at the old height, then up: the rise lands ON the
      // month it belongs to instead of being spread across the one before it.
      path
        ..lineTo(x(i), y(v[i - 1]))
        ..lineTo(x(i), y(v[i]));
    }

    final Paint p = Paint()
      ..color = tone
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(dashed ? _dash(path) : path, p);

    // ⚠ ONE MARKER, AT THE END. A dot on every month is a number on every
    //   point by another name; the end is where the total is, and the total is
    //   what the two figures above the chart already state.
    canvas.drawCircle(
      Offset(x(v.length - 1), y(v.last)),
      3.5,
      Paint()..color = tone,
    );
  }

  /// A dashed copy of [source] — the second channel the palette needs.
  Path _dash(Path source) {
    final Path out = Path();
    for (final PathMetric m in source.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final double next = math.min(d + 5, m.length);
        out.addPath(m.extractPath(d, next), Offset.zero);
        d = next + 3.5;
      }
    }
    return out;
  }

  void _text(
    Canvas canvas,
    String s,
    double cx,
    double top, {
    required bool end,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: textScale.scale(9) > 14
            ? const TextStyle(fontSize: 9, color: AppColors.muted)
            : TextStyle(
                fontSize: textScale.scale(9),
                color: AppColors.muted,
              ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    // Pinned inside the plot at both extremes rather than centred on the point,
    // so neither label hangs off the edge of the card.
    final double dx = end ? cx - tp.width : cx;
    tp.paint(canvas, Offset(dx.clamp(0, math.max(0, cx)), top));
  }

  @override
  bool shouldRepaint(_CumulativePainter old) => old.months != months;
}
