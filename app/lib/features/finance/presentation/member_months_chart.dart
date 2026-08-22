import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';

/// حركتك خلال السنة — يناير إلى ديسمبر، موجتان: ما دفعتَ وما استلمتَ.
///
/// ── ما طُلب بالحرف ─────────────────────────────────────────────────────────
/// «اريدها من يناير الى ديسمبر وخطين واضحين بمنحنيات نزولاً وطلوعاً مثل الأمواج
///  حسب الدفع والاستلام».
///
/// ── والشكل تغيّر مرّتين قبل هذا، والسببان يستحقّان البقاء ───────────────────
/// 1. **Grouped columns.** Aid became one lone spike beside twelve flattened
///    subscription bars — two series with different rhythms on one scale.
/// 2. **Cumulative step lines.** Correct, and useless on data that lives in a
///    single month: eleven flat months meeting a vertical jump. «لا يفيدني
///    بشيء», and it did not.
///
/// What survives from both is the RATIO, which moved to [MemberValueBar] and is
/// answerable from the first receipt. This chart is the SHAPE of a year.
///
/// ⚠ AND A CURVE BETWEEN TWO MONTHS ASSERTS VALUES THAT DO NOT EXIST — a smooth
///   rise through February when February was empty. That is a real cost, and it
///   was accepted deliberately: what a wave communicates is where the year was
///   busy and where it was quiet. Anyone reading an exact figure off a curve is
///   reading the wrong instrument; the exact figures are printed above it.
///
/// ⚠ AND NOTHING HERE ADDS MONEY. Every value arrives summed by
///   `api_member_value`. Parsing is a MEASUREMENT — how high to put a pixel —
///   and it never reaches the screen as a number.
class MemberMonthsChart extends StatelessWidget {
  const MemberMonthsChart({required this.months, super.key});

  final List<MemberMonth> months;

  @override
  Widget build(BuildContext context) {
    if (months.isEmpty) return const SizedBox.shrink();
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
              //   channel, drawn here exactly as it is on the chart.
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
                height: 178,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) =>
                      CustomPaint(
                        size: Size(c.maxWidth, 178),
                        painter: _WavePainter(
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
///   The mark carries the identity; the text wears a text token.
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
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
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
  bool shouldRepaint(_KeyMark old) => old.tone != tone || old.dashed != dashed;
}

/// موجتان عبر اثني عشر شهراً.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.months, required this.textScale});

  final List<MemberMonth> months;
  final TextScaler textScale;

  /// Room for the month names under the plot.
  static const double _axis = 20;

  /// ⚠ FOUR, EVENLY SPREAD, AND MEASURED RATHER THAN CHOSEN. Twelve Arabic
  ///   month names across a phone collide into a grey smear; two would leave
  ///   the middle of the year unlabelled, and the association asked to see
  ///   «يناير إلى ديسمبر» rather than two ends.
  ///
  ///   [0, 3, 6, 9, 11] was tried first and RENDERED WRONG: 9 and 11 are one
  ///   step apart at the left edge, where December has to be pulled inside the
  ///   plot — so the two ran into each other and printed as one long smudge. A
  ///   golden render caught it; no test of the DATA could have.
  static const List<int> _labelled = <int>[0, 4, 8, 11];

  double _v(String s) => double.tryParse(s) ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;

    final List<double> paid = months
        .map((MemberMonth m) => _v(m.paid))
        .toList();
    final List<double> got = months
        .map((MemberMonth m) => _v(m.received))
        .toList();

    // ⚠ ONE SCALE FOR BOTH, never one each. Two y-axes on one chart is the
    //   commonest way to make two series look related when they are not — and
    //   these are in the same unit, so a second scale would be a distortion
    //   with no upside at all.
    final double top = math.max(
      paid.fold<double>(0, math.max),
      got.fold<double>(0, math.max),
    );

    final double h = size.height - _axis;
    final int n = months.length;
    final double step = n <= 1 ? size.width : size.width / (n - 1);

    // ⚠ RTL: يناير on the RIGHT, ديسمبر on the LEFT. Time runs the way the
    //   reader's eye does in this app.
    double x(int i) => size.width - i * step;
    // A year with nothing in it still draws its baseline rather than dividing
    // by zero.
    double y(double v) => top <= 0 ? h - 6 : h - (v / top) * (h - 14);

    canvas.drawLine(
      Offset(0, h),
      Offset(size.width, h),
      Paint()
        ..color = GlassColors.wellEdge
        ..strokeWidth = 1,
    );

    _wave(canvas, paid, x, y, AppColors.info, dashed: false);
    _wave(canvas, got, x, y, AppColors.success, dashed: true);

    // ── The months ─────────────────────────────────────────────────────────
    // ⚠ MUTED, and this is the one written exception to «a month is blue» —
    //   see AppColors.month. On this chart AppColors.info is ALREADY the
    //   «دفعتَ» series, so a blue axis would read as belonging to it.
    for (final int i in _labelled) {
      if (i >= n) continue;
      _text(
        canvas,
        formatMonthShort(months[i].period),
        x(i),
        h + 4,
        size,
        atStart: i == 0,
        atEnd: i == n - 1,
      );
    }
  }

  /// One series, as a smooth wave.
  void _wave(
    Canvas canvas,
    List<double> v,
    double Function(int) x,
    double Function(double) y,
    Color tone, {
    required bool dashed,
  }) {
    if (v.isEmpty) return;

    final Path path = Path()..moveTo(x(0), y(v[0]));
    for (int i = 0; i < v.length - 1; i++) {
      final double x1 = x(i);
      final double x2 = x(i + 1);
      final double y1 = y(v[i]);
      final double y2 = y(v[i + 1]);
      // ⚠ CONTROL POINTS ON THE HORIZONTAL MIDLINE — the cheapest smoothing
      //   that CANNOT OVERSHOOT. A Catmull-Rom spline looks rounder and dips
      //   BELOW the baseline between a busy month and an empty one, drawing
      //   money that was never negative. This cubic stays inside the two
      //   values it joins, always.
      final double mid = (x1 + x2) / 2;
      path.cubicTo(mid, y1, mid, y2, x2, y2);
    }

    canvas.drawPath(
      dashed ? _dash(path) : path,
      Paint()
        ..color = tone
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // ── A dot only where a month actually holds something ─────────────────
    // ⚠ NOT ON ALL TWELVE. A dot on every month is a number on every point by
    //   another name, and it would put twelve markers on a year in which two
    //   things happened. A dot here means «this is a real reading», which on a
    //   curve that invents its in-between values is worth saying.
    for (int i = 0; i < v.length; i++) {
      if (v[i] <= 0) continue;
      canvas.drawCircle(Offset(x(i), y(v[i])), 3.5, Paint()..color = tone);
    }
  }

  /// A dashed copy — the second channel the palette needs.
  Path _dash(Path source) {
    final Path out = Path();
    for (final PathMetric m in source.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        final double next = math.min(d + 6, m.length);
        out.addPath(m.extractPath(d, next), Offset.zero);
        d = next + 4;
      }
    }
    return out;
  }

  void _text(
    Canvas canvas,
    String s,
    double cx,
    double top,
    Size size, {
    required bool atStart,
    required bool atEnd,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: math.min(textScale.scale(9), 12),
          color: AppColors.muted,
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    // ⚠ THE TWO ENDS ARE ALIGNED, NOT CENTRED-THEN-CLAMPED. Clamping moves a
    //   label without moving its neighbour, so the gap between them shrinks by
    //   exactly the amount clamped — which is how December walked into October
    //   and printed as one smudge. Anchoring the first label to the right edge
    //   and the last to the left edge keeps every gap the size the spacing
    //   intended.
    final double dx = atStart
        ? size.width - tp.width
        : atEnd
        ? 0
        : (cx - tp.width / 2).clamp(
            0.0,
            math.max(0.0, size.width - tp.width),
          );
    tp.paint(canvas, Offset(dx, top));
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.months != months;
}
