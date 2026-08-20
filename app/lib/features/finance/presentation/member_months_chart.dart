import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';

/// حركتك — twelve months of what he paid in and what came back out, at the foot
/// of «الجدوى».
///
/// ── WHY COLUMNS AND NOT LINES ───────────────────────────────────────────────
/// A subscription is a discrete act, not a quantity that flows. A line drawn
/// between January and March asserts a value for February, and February may be
/// a month he paid nothing — which is exactly the fact worth seeing. Columns
/// say «nothing here» by being absent; a line says it by sloping through.
///
/// ── THE TWO COLOURS ARE ALREADY ON THE SCREEN ───────────────────────────────
/// [AppColors.info] is «دفعتَ» and [AppColors.success] is «استلمتَ» in the two
/// figures directly above this chart. Reusing them is what lets a reader match
/// a bar to a figure without consulting anything — colour follows the entity.
///
/// ⚠ AND THE PAIR WAS VALIDATED, NOT EYEBALLED: ΔE 24.8 under deuteranopia and
///   29.2 for normal vision, against this surface. Under tritanopia it drops to
///   6.4, which is the floor band — legal only with a second channel, so the
///   legend, the fixed left-of-right order inside every group, and the gap
///   between them all carry the identity as well.
///
/// ── AND NOTHING HERE ADDS MONEY ─────────────────────────────────────────────
/// Every figure arrives already summed by `api_member_value`. The parse below
/// is a MEASUREMENT — how tall to draw a rectangle — and its result never
/// reaches the screen as a number: the labels print the server's own text.
class MemberMonthsChart extends StatelessWidget {
  const MemberMonthsChart({required this.months, super.key});

  final List<MemberMonth> months;

  /// Nothing to plot is not a chart with twelve empty columns.
  ///
  /// ⚠ A MAN WHO HAS NEVER PAID would otherwise get a full-width graphic that
  ///   says nothing, on the one screen built to answer «ما الجدوى». The credit
  ///   card in the register hides itself for the same reason.
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
              // ⚠ A LEGEND, ALWAYS, FOR TWO SERIES. The figures above are
              //   already in these colours, but a reader who scrolled straight
              //   to the chart has not seen them — and identity must never rest
              //   on colour alone.
              Row(
                children: <Widget>[
                  _Key(tone: AppColors.info, label: l.valuePaid),
                  const SizedBox(width: AppSpacing.md),
                  _Key(tone: AppColors.success, label: l.valueReceived),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 150,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) =>
                      CustomPaint(
                        size: Size(c.maxWidth, 150),
                        painter: _MonthsPainter(
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

/// A dot and a word — the legend entry.
///
/// ⚠ THE WORD IS NOT IN THE SERIES COLOUR. A coloured label reads as data and
///   an 11px indigo word on glass is harder to read than the same word in ink.
///   The dot beside it carries the identity; the text wears a text token.
class _Key extends StatelessWidget {
  const _Key({required this.tone, required this.label});

  final Color tone;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
      ),
    ],
  );
}

class _MonthsPainter extends CustomPainter {
  _MonthsPainter({required this.months, required this.textScale});

  final List<MemberMonth> months;
  final TextScaler textScale;

  /// Room under the plot for the month names.
  static const double _axisHeight = 18;

  /// …and above it, for the one value label that rides the tallest column.
  static const double _capHeight = 14;

  double _v(String s) => double.tryParse(s) ?? 0;

  @override
  void paint(Canvas canvas, Size size) {
    final double top = _capHeight;
    final double base = size.height - _axisHeight;
    final double plot = base - top;
    if (plot <= 0 || months.isEmpty) return;

    // ⚠ ONE SCALE FOR BOTH SERIES, and never two. A second axis is the single
    //   most common way a chart lies: two measures in the same unit drawn to
    //   different scales makes a small bar look like a large one. Both of these
    //   are dinars, so they share a ceiling.
    double peak = 0;
    for (final MemberMonth m in months) {
      peak = math.max(peak, math.max(_v(m.paid), _v(m.received)));
    }
    if (peak <= 0) return;

    final Paint grid = Paint()
      ..color = GlassColors.wellEdge
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, base), Offset(size.width, base), grid);

    // The slot each month gets, and the bar inside it. Thin marks: the leftover
    // is air, not more bar.
    final double slot = size.width / months.length;
    final double bar = math.min(9, math.max(3, slot / 3.2));
    const double gap = 2; // the surface gap, doing the separating

    int tallestPaid = 0;
    int tallestGot = 0;
    for (int i = 0; i < months.length; i++) {
      if (_v(months[i].paid) > _v(months[tallestPaid].paid)) tallestPaid = i;
      if (_v(months[i].received) > _v(months[tallestGot].received)) {
        tallestGot = i;
      }
    }

    for (int i = 0; i < months.length; i++) {
      // ⚠ MIRRORED, because the app is right-to-left and time reads with it.
      //   The oldest month sits on the RIGHT and the newest on the left, which
      //   is the direction every date, name and figure on this screen runs.
      final double centre = size.width - (i + 0.5) * slot;
      final double paidX = centre + gap / 2 + bar / 2;
      final double gotX = centre - gap / 2 - bar / 2;

      _column(canvas, paidX, base, plot, _v(months[i].paid) / peak, bar,
          AppColors.info);
      _column(canvas, gotX, base, plot, _v(months[i].received) / peak, bar,
          AppColors.success);
    }

    // ── Labels, selectively ────────────────────────────────────────────────
    // ⚠ NEVER A NUMBER ON EVERY COLUMN. Twenty-four figures on a 150px chart is
    //   noise that goes unread; the extreme of each series is what a reader
    //   actually looks for, and the totals above carry the rest.
    _capLabel(canvas, size, tallestPaid, months[tallestPaid].paid, peak, plot,
        base, slot, 1, AppColors.info);
    if (_v(months[tallestGot].received) > 0) {
      _capLabel(canvas, size, tallestGot, months[tallestGot].received, peak,
          plot, base, slot, -1, AppColors.success);
    }

    // ── The month axis ─────────────────────────────────────────────────────
    // Four names, not twelve: at this width twelve collide into a grey smear.
    for (int i = 0; i < months.length; i += 3) {
      final double centre = size.width - (i + 0.5) * slot;
      _text(
        canvas,
        formatMonthShort(months[i].period),
        Offset(centre, base + 3),
        const TextStyle(fontSize: 9, color: AppColors.inkMuted),
      );
    }
  }

  void _column(Canvas canvas, double cx, double base, double plot, double frac,
      double w, Color tone) {
    if (frac <= 0) return;
    // A hairline minimum, so a month with a small figure is visible as
    // «something» rather than reading as nothing at all.
    final double h = math.max(2, plot * frac);
    final Rect r = Rect.fromLTWH(cx - w / 2, base - h, w, h);
    // Rounded at the data end, square at the baseline — the cap is the value,
    // the foot is the axis.
    final double radius = math.min(4, w / 2);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        r,
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      ),
      Paint()..color = tone,
    );
  }

  void _capLabel(Canvas canvas, Size size, int i, String amount, double peak,
      double plot, double base, double slot, int side, Color tone) {
    if (_v(amount) <= 0) return;
    final double centre = size.width - (i + 0.5) * slot;
    final double h = math.max(2, plot * (_v(amount) / peak));
    _text(
      canvas,
      // ⚠ THE SERVER'S OWN TEXT, formatted the way every other amount in the
      //   app is. The parsed double decided the HEIGHT and never the wording.
      formatMoney(amount),
      Offset(centre + side * (slot / 4), base - h - _capHeight + 2),
      // Ink, not the series colour: a value is text, and text wears a text
      // token. The column beneath it already says which series it belongs to.
      const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      clampTo: size.width,
    );
  }

  void _text(Canvas canvas, String s, Offset centre, TextStyle style,
      {double? clampTo}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.rtl,
      textScaler: textScale,
    )..layout();
    double dx = centre.dx - tp.width / 2;
    if (clampTo != null) dx = dx.clamp(0, math.max(0, clampTo - tp.width));
    tp.paint(canvas, Offset(dx, centre.dy));
  }

  @override
  bool shouldRepaint(_MonthsPainter old) =>
      old.months != months || old.textScale != textScale;
}
