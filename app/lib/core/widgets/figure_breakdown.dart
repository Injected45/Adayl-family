import 'package:flutter/material.dart';

import '../config/glass.dart';
import '../config/theme.dart';

/// ONE figure across the width, and its workings behind a tap.
///
/// Both the treasury and the dashboard opened on a grid of four tiles — equal
/// in weight and unequal in importance. Each page is opened to learn ONE thing:
/// what the association holds, or what it has collected. The rest is how that
/// number was arrived at, which is a different question, asked afterwards if at
/// all, and on a phone it was crowding the answer off the top of the screen.
///
/// So the answer takes the width and the workings move into a sheet. Nothing is
/// dropped: every label the association named survives under the same words, one
/// tap down.
///
/// Shared rather than copied because it is now the shape of two screens and will
/// be the shape of the next one. Two hand-written copies drift — a tone here, a
/// padding there — and the drift is invisible until someone puts the screens
/// side by side.
class FigureBar extends StatelessWidget {
  const FigureBar({
    required this.label,
    required this.value,
    required this.rows,
    this.sub,
    this.tone,
    super.key,
  });

  /// The heading, in the association's own words.
  final String label;

  /// Already formatted. This widget never touches a number.
  final String value;

  /// What the figure is made of, shown when the bar is tapped.
  final List<FigureRow> rows;

  /// One short line under the figure — the part of the workings that is worth
  /// carrying on the face of it.
  final String? sub;

  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => showFigureBreakdown(context, rows),
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: tone,
                      ),
                    ),
                    if (sub != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        sub!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // The affordance. A card that opens something and does not say so
              // is a feature nobody finds — and this is the only way to the
              // figures that used to be on the page.
              const Icon(Icons.expand_more, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of a breakdown: a label, an already-formatted value, and the tone
/// that says what kind of figure it is.
class FigureRow {
  const FigureRow({
    required this.label,
    required this.value,
    this.trailing,
    this.tone,
    this.strong = false,
  });

  final String label;

  /// Formatted by the caller. Nothing here parses or adds a number — every
  /// total in this app is computed by the server.
  final String value;

  /// A count or a qualifier beside the figure: «12 مشترك مدين», «نقدي … تحويل …».
  final String? trailing;

  final Color? tone;

  /// The conclusion of the rows above it, set apart.
  final bool strong;
}

/// The workings, as a sheet.
///
/// A sheet rather than a second page: it is read for a moment and dismissed, and
/// the screen it was opened from should still be behind it.
void showFigureBreakdown(BuildContext context, List<FigureRow> rows) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.ink.withValues(alpha: 0.22),
    builder: (BuildContext sheetContext) => GlassSheet(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.inkMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final FigureRow row in rows) _BreakdownRow(row: row),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.row});

  final FigureRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(
        bottom: row.strong ? AppSpacing.sm : AppSpacing.md,
        top: row.strong ? AppSpacing.sm : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (row.strong) const Divider(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  // The solid bar the tiles carried. It encodes the tone for a
                  // reader who cannot separate the colours, so hue is never the
                  // only signal.
                  color: row.tone ?? AppColors.brand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  row.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: row.strong
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ),
              Text(
                row.value,
                style: TextStyle(
                  fontSize: row.strong ? 16 : 14,
                  fontWeight: row.strong ? FontWeight.w900 : FontWeight.w800,
                  color: row.tone,
                ),
              ),
            ],
          ),
          if (row.trailing != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 11, top: 2),
              child: Text(
                row.trailing!,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
