import 'package:flutter/material.dart';

import '../config/glass.dart';
import '../config/theme.dart';

/// The floating capsule the whole app navigates from.
///
/// ── WHY IT LIVES HERE AND NOT INSIDE AppScaffold ────────────────────────────
/// The عديل portal needs the same bar — the association asked for it in those
/// words: «بنفس المظهر العام» — and it is NOT an AppScaffold, because every
/// destination on the staff bar is a screen the router refuses him. Copying the
/// capsule into the portal would have given the app two bars that look alike
/// today and drift apart at the first change to either.
///
/// So it takes ITEMS rather than AppDestinations. The staff scaffold builds them
/// from its destination list; the portal builds two by hand. Neither knows how
/// the other is composed, and both are the same widget.
///
/// ⚠ [totalHeight] is what a screen reserves for it, published through
///   MediaQuery as bottom padding — see AppScaffold and bottomInset(). A screen
///   that reserves it while no bar is drawn reads through a band of nothing;
///   one that draws the bar without reserving it hides its own last row.
class NavPillItem {
  const NavPillItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// A count on the icon, or zero for none.
  ///
  /// The member's bar carries his unread messages here, because his bar is the
  /// only place he ever sees المحادثات named — he has no app bar of his own and
  /// therefore no bell.
  final int badge;
}

class NavPillBar extends StatelessWidget {
  const NavPillBar({required this.items, super.key});

  /// Two on a member’s screen, five plus «المزيد» on the association’s.
  final List<NavPillItem> items;

  static const double _pillHeight = 66;
  static const double _bottomGap = 12;

  /// What the pill occupies, published to the body as MediaQuery bottom padding
  /// so screen content can clear it.
  static const double totalHeight = _pillHeight + _bottomGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        _bottomGap + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: GlassSurface(
        blurred: true,
        lifted: true,
        fill: GlassColors.chrome,
        // A true pill: radius is half the height, so the ends are semicircles
        // rather than a rounded rectangle pretending to be one.
        radius: _pillHeight / 2,
        child: SizedBox(
          height: _pillHeight,
          child: Row(
            children: <Widget>[
              for (final NavPillItem item in items)
                Expanded(child: _NavPillItemView(item: item)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavPillItemView extends StatelessWidget {
  const _NavPillItemView({required this.item});

  final NavPillItem item;

  @override
  Widget build(BuildContext context) {
    // Reduced motion collapses the capsule transition to zero rather than
    // skipping it — the end state must still be correct, only instant.
    final Duration duration = prefersReducedMotion(context)
        ? Duration.zero
        : AppMotion.fast;

    return Semantics(
      // The destination is conveyed by label AND by state, not by colour alone.
      selected: item.selected,
      button: true,
      child: InkWell(
        onTap: item.onTap,
        customBorder: const StadiumBorder(),
        // Sized to fill the 66px pill, so the whole column is the target rather
        // than just the icon — comfortably past the 44px minimum.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: duration,
              curve: AppMotion.enter,
              width: 44,
              height: 28,
              decoration: BoxDecoration(
                // Flat: a solid capsule, no gradient, no shadow.
                color: item.selected ? AppColors.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              alignment: Alignment.center,
              // ── THE COUNT RIDES THE ICON ──────────────────────────────
              // A member has no app bar and therefore no bell: this capsule is
              // the only place المحادثات is named for him, so it is the only
              // place a count can reach him. Staff pass zero and the Stack
              // costs them one childless branch.
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: <Widget>[
                  Icon(
                    item.selected ? item.selectedIcon : item.icon,
                    size: 20,
                    color: item.selected
                        ? AppColors.onFill
                        : AppColors.inkMuted,
                  ),
                  if (item.badge > 0)
                    PositionedDirectional(
                      top: -2,
                      end: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        constraints: const BoxConstraints(minWidth: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          item.badge > 99 ? '+99' : '${item.badge}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: AppColors.onFill,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 10.5,
                fontWeight: item.selected ? FontWeight.w800 : FontWeight.w600,
                color: item.selected ? AppColors.brandDeep : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
