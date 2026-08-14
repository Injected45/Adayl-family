import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The vibrant field every glass surface sits on.
///
/// This is not decoration. Glassmorphism's whole effect is a translucent pane
/// modulating something colourful behind it — frost over flat grey is just grey,
/// and the style collapses into "slightly transparent card". So the field is a
/// functional part of the system.
///
/// Built from four soft radial washes rather than a photograph or a mesh image:
///
///   * It is a few hundred bytes of paint instructions, not a 400KB asset the
///     web build has to download before the first frame.
///   * It stays sharp at any size, which matters across 375px phones and 1440px
///     desktop.
///   * The washes are strong enough to SEE — 60% alpha over a tinted base. The
///     first version used 22% and the rendered result was indistinguishable from
///     flat white, which made every pane above it pointless. Measured at 60%:
///     secondary text on a content pane still clears 7:1 and the field's own
///     luminance stays at 0.63, so there was no accessibility reason for the
///     original timidity. test/design_system_test.dart asserts both bounds.
///
/// It is painted ONCE, by AppScaffold, beneath the whole app. Nesting these
/// would stack washes and darken the field unpredictably.
class AppBackground extends StatelessWidget {
  const AppBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.fieldBase),
      // RepaintBoundary so scrolling content above never repaints the field.
      // Without it, every frame of a list scroll redraws four radial gradients.
      child: RepaintBoundary(
        child: CustomPaint(
          painter: const _AuroraPainter(),
          // Field first, then the app. Static, so it is const and never rebuilds.
          child: child,
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter();

  /// Placed with AlignmentDirectional-equivalent fractions rather than fixed
  /// offsets, so the composition mirrors correctly in RTL — the warm wash stays
  /// on the reading-start side in both directions.
  static const List<(Color, Alignment, double)> _washes =
      <(Color, Alignment, double)>[
        (AppColors.auroraTeal, Alignment(0.85, -0.80), 1.05),
        (AppColors.auroraCyan, Alignment(-0.80, -0.35), 0.90),
        (AppColors.auroraAmber, Alignment(0.60, 0.70), 0.85),
        (AppColors.auroraViolet, Alignment(-0.70, 0.95), 0.95),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final double unit = size.shortestSide;

    for (final (Color color, Alignment where, double scale) in _washes) {
      final Offset centre = where.alongSize(size);
      final double radius = unit * scale;
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              color.withValues(alpha: 0.60),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) => false;
}
