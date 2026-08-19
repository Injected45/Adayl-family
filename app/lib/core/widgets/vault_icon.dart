import 'package:flutter/material.dart';

import '../config/theme.dart';

/// الخزينة — the association's official mark for الصندوق.
///
/// ── WHY IT IS PAINTED AND NOT AN `IconData` ─────────────────────────────────
/// There is no vault glyph in the Material icon set shipped with this Flutter
/// (3.41). The treasury wore `Icons.savings_outlined`, which is a PIGGY BANK —
/// an animal, and a child's one at that, standing for a fund that holds a real
/// association's money and pays out for bereavements. The association asked for
/// a خزينة instead and asked that it be the mark of الصندوق everywhere, so the
/// choice was a drawing or a font.
///
/// A drawing, because the alternative costs more than it looks: a second icon
/// font is another asset in the APK, another licence to track, and a second
/// place where a glyph can go missing at a size nobody tested. Eighty lines of
/// canvas has no such tail.
///
/// ── WHY IT LOOKS LIKE A MATERIAL ICON AND NOT LIKE A PICTURE ────────────────
/// It sits inches from `Icons.north_east`, `Icons.undo` and the rest, so it is
/// built to their rules rather than to its own: a 24-unit box scaled to the
/// caller's [size], strokes of a fixed proportion of that box, round caps, and
/// ONE colour taken from the caller exactly as `Icon` takes it. Nothing is
/// filled and nothing is shaded — the design system fails the build on a
/// gradient or a decorative shadow in a screen, and an icon that painted itself
/// a highlight would be the same mistake at a smaller scale.
///
/// ── WHAT IS DRAWN, AND WHY THAT AND NOT MORE ────────────────────────────────
/// A body, a door line, a dial with four spokes, a handle, and two feet. At 18
/// logical pixels — the size four of the five call sites use — anything finer
/// than that closes up into a smudge. The dial is what makes it read as a safe
/// rather than a box: remove it and this is a package.
class VaultIcon extends StatelessWidget {
  const VaultIcon({this.size = 24, this.color, super.key});

  final double size;

  /// Null takes the ambient `IconTheme`, so this drops into a `Row` beside real
  /// icons and inherits what they inherit — including the muted tone a disabled
  /// row hands down.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VaultPainter(
          color: color ?? IconTheme.of(context).color ?? AppColors.text,
        ),
        // A safe, for a screen reader. Without this the treasury's mark is an
        // unlabelled box to anyone not looking at it.
        isComplex: false,
      ),
    );
  }
}

class _VaultPainter extends CustomPainter {
  const _VaultPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is expressed in a 24-unit box and scaled once, so the
    // proportions hold at 18, at 24 and at the 56-unit medallion.
    final double u = size.width / 24;
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ── The body ────────────────────────────────────────────────────────────
    // Inset by one unit on the sides and stopped short of the bottom so the
    // feet have somewhere to stand.
    final RRect body = RRect.fromLTRBR(
      3 * u,
      3.5 * u,
      21 * u,
      19 * u,
      Radius.circular(2.2 * u),
    );
    canvas.drawRRect(body, stroke);

    // ── The door ────────────────────────────────────────────────────────────
    // One vertical line at the hinge side. It is what turns a rectangle into
    // something that OPENS, and it costs a single stroke.
    canvas.drawLine(Offset(7 * u, 5 * u), Offset(7 * u, 17.5 * u), stroke);

    // ── The dial ────────────────────────────────────────────────────────────
    // The whole reason this reads as a safe. Centred in the door panel rather
    // than in the body, because a dial centred on the box looks like a button.
    final Offset dial = Offset(14 * u, 11.25 * u);
    canvas.drawCircle(dial, 3.4 * u, stroke);

    // Four spokes, at the diagonals rather than at the compass points: on a
    // small glyph the vertical spoke would sit on the door line and the
    // horizontal one on the body edge, and both would disappear into them.
    final Paint spoke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * u
      ..strokeCap = StrokeCap.round;
    const double d = 0.7071; // cos 45°
    for (final List<int> s in <List<int>>[
      <int>[1, 1],
      <int>[1, -1],
      <int>[-1, 1],
      <int>[-1, -1],
    ]) {
      canvas.drawLine(
        dial + Offset(s[0] * 1.4 * u * d, s[1] * 1.4 * u * d),
        dial + Offset(s[0] * 5.2 * u * d, s[1] * 5.2 * u * d),
        spoke,
      );
    }

    // ── The feet ────────────────────────────────────────────────────────────
    // Two short legs. They stop the body reading as a picture frame, which is
    // what an unfooted rounded rectangle looks like at this size.
    canvas.drawLine(Offset(6.5 * u, 19 * u), Offset(6.5 * u, 21 * u), spoke);
    canvas.drawLine(Offset(17.5 * u, 19 * u), Offset(17.5 * u, 21 * u), spoke);
  }

  @override
  bool shouldRepaint(_VaultPainter old) => old.color != color;
}
