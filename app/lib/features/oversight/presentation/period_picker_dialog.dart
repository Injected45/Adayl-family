import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../finance/domain/models.dart';
import '../../finance/presentation/providers.dart';

/// «إقفال شهر» — which month, and what has already been closed.
///
/// ── مطويّةٌ على آخر شهرٍ أُقفل (15/09) ─────────────────────────────────────
/// The dialog used to open on EVERY month since system_start — twenty-two rows
/// of «مُقفل» to scroll past for the one fact anyone opens it for. The
/// association asked for one container holding the last closed month, which
/// opens onto the full list on a tap: «اريد عرض حاوية بها اخر شهر تم اقفالة
/// واذا اردت رؤية القائمة اضغط على هذه الحاوية تنسل ويظهر كل الاقفالات».
///
/// ⚠ THE MONTH THAT CAN BE CLOSED STAYS OUTSIDE THE FOLD. It is the one row
///   anyone taps, and hiding it behind a container would put a second tap in
///   front of the only action on this screen — on the first of every month.
///   The full list, once opened, holds every OTHER month, so nothing is
///   listed twice.
///
/// ⚠ EVERY ROW'S STATE IS STILL THE SERVER'S. `closed` and `selectable` are
///   rules 15a and 15b; the dialog only arranges them. «Last closed» is the
///   newest row the server marked closed — the list arrives newest first.
class PeriodPickerDialog extends ConsumerStatefulWidget {
  const PeriodPickerDialog({super.key});

  @override
  ConsumerState<PeriodPickerDialog> createState() => _PeriodPickerDialogState();
}

class _PeriodPickerDialogState extends ConsumerState<PeriodPickerDialog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AsyncValue<List<ClosablePeriod>> periods = ref.watch(
      closablePeriodsProvider,
    );

    return GlassDialog(
      title: Text(l.selectPeriodTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: periods.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace _) =>
              Text(describeApiFailure(l, error)),
          data: (List<ClosablePeriod> items) {
            if (items.isEmpty) return Text(l.noPeriodsToClose);
            return _Body(
              items: items,
              expanded: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.items,
    required this.expanded,
    required this.onToggle,
  });

  /// Newest first, as the server sends them.
  final List<ClosablePeriod> items;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    ClosablePeriod? open;
    ClosablePeriod? lastClosed;
    for (final ClosablePeriod p in items) {
      if (p.selectable) open ??= p;
      if (p.closed) lastClosed ??= p;
    }

    // Everything the fold holds: every month but the one outside it.
    final List<ClosablePeriod> rest = <ClosablePeriod>[
      for (final ClosablePeriod p in items)
        if (!identical(p, open)) p,
    ];

    // ⚠ A CEILING, AND IT WAS MISSING. The list sat unbounded inside the
    //   dialog's column, so twenty-two months at 64px each laid out taller than
    //   the phone. Opened, the list scrolls inside the dialog instead.
    final double ceiling = MediaQuery.sizeOf(context).height * 0.6;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: ceiling),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (open != null) ...<Widget>[
              PeriodRow(period: open),
              const SizedBox(height: AppSpacing.sm),
            ],
            // Nothing closed yet: there is no fold to make, so the months are
            // listed as they always were.
            if (lastClosed == null)
              for (final ClosablePeriod p in rest) PeriodRow(period: p)
            else ...<Widget>[
              _LastClosedHeader(
                period: lastClosed,
                expanded: expanded,
                onTap: onToggle,
              ),
              AnimatedSize(
                duration: prefersReducedMotion(context)
                    ? Duration.zero
                    : AppMotion.base,
                curve: AppMotion.enter,
                alignment: AlignmentDirectional.topStart,
                child: expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const SizedBox(height: AppSpacing.xs),
                          for (int i = 0; i < rest.length; i++) ...<Widget>[
                            if (i > 0) const Divider(height: 1),
                            PeriodRow(period: rest[i]),
                          ],
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// «آخر شهر مُقفل: سبتمبر 2026 — مُقفل ⌄». The whole container is the target.
class _LastClosedHeader extends StatelessWidget {
  const _LastClosedHeader({
    required this.period,
    required this.expanded,
    required this.onTap,
  });

  final ClosablePeriod period;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Semantics(
      button: true,
      expanded: expanded,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: GlassColors.well,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: GlassColors.wellEdge),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        l.periodLastClosed,
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        period.label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        expanded ? l.periodHideAll : l.periodShowAll,
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                StatusBadge(
                  label: l.periodClosedBadge,
                  tone: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One month, painted from its two server flags — exactly as the list always
/// painted it.
///
/// Exactly one row is ever tappable — the earliest open month. The rest stay
/// VISIBLE and inert: someone checking whether March was closed needs to see
/// March, and someone wondering why August is greyed out needs to see the open
/// July above it.
class PeriodRow extends StatelessWidget {
  const PeriodRow({required this.period, super.key});

  final ClosablePeriod period;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final ClosablePeriod p = period;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: p.selectable,
      // ⚠ BLUE ONLY WHILE IT IS THE MONTH THAT CAN BE CLOSED. Grey is what says
      //   «not this one» on this list, and a month is not exempt from it: paint
      //   every row blue and rule 15b stops being visible.
      title: Text(
        p.label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: p.selectable ? AppColors.month : AppColors.muted,
        ),
      ),
      subtitle: Text(
        p.selectable
            ? p.period
            // The reason it is not tappable, in words. "Greyed out with no
            // explanation" is the version of this screen that generates a
            // phone call.
            : p.closed
            ? l.periodClosedNote
            : l.periodBlockedNote,
        style: TextStyle(fontSize: 11, color: AppColors.muted),
      ),
      trailing: p.closed
          ? StatusBadge(label: l.periodClosedBadge, tone: AppColors.success)
          : p.selectable
          ? Icon(Icons.chevron_left, size: 20, color: AppColors.muted)
          : Icon(Icons.lock_outline, size: 18, color: AppColors.muted),
      onTap: p.selectable ? () => Navigator.of(context).pop(p) : null,
    );
  }
}
