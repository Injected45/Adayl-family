import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Lays cards out in rows of [columns], sized to their content.
///
/// Uses `Wrap` with an explicit width per cell instead of `GridView.count`,
/// because Wrap lets each row take the height its tallest child needs. Nothing
/// here can overflow.
class StatCardGrid extends StatelessWidget {
  const StatCardGrid({
    required this.children,
    this.columns = 2,
    this.wideColumns = 4,
    this.wideBreakpoint = 720,
    this.spacing = AppSpacing.md,
    super.key,
  });

  final List<Widget> children;
  final int columns;
  final int wideColumns;
  final double wideBreakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int count = constraints.maxWidth >= wideBreakpoint
            ? wideColumns
            : columns;
        final double cell =
            (constraints.maxWidth - spacing * (count - 1)) / count;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final Widget child in children)
              SizedBox(
                width: cell > 0 ? cell : constraints.maxWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}
