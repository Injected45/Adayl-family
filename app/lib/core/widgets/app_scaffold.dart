import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../l10n/app_localizations.dart';
import '../config/glass.dart';
import '../config/theme.dart';
import '../router/destinations.dart';
import 'app_background.dart';
import 'stat_card.dart';

/// The navigation shell.
///
/// The prototype has a 280px sidebar with twelve entries and a phone bar with
/// five, which leaves seven screens unreachable on a phone (index.html:438).
/// Here the phone keeps four primary destinations plus "المزيد", which opens
/// the rest — so a phone reaches everything the desktop sidebar does. That is
/// parity with the existing product, not new capability.
///
/// ── Where the blur lives
///
/// This file owns most of the app's [BackdropFilter] instances: the app bar, the
/// bottom navigation, and the wide-layout rail. That is deliberate. They are
/// fixed in number, they float over scrolling content, and content sliding
/// beneath them is what makes frosted glass read as glass at all. Everything
/// that repeats — cards, rows, tiles — uses the unblurred [GlassCard]. See the
/// budget note in core/config/glass.dart; test/design_system_test.dart enforces
/// it.
class AppScaffold extends ConsumerWidget {
  const AppScaffold({
    required this.title,
    required this.body,
    required this.currentRoute,
    this.actions,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final Widget body;
  final String currentRoute;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  static const double _railBreakpoint = 600;
  static const double _drawerBreakpoint = 1024;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;
    final List<AppDestination> visible = appDestinations
        .where((AppDestination d) => d.isVisibleTo(role))
        .toList();
    final double width = MediaQuery.sizeOf(context).width;

    if (width >= _railBreakpoint) {
      return AppBackground(
        child: _WideLayout(
          title: title,
          body: body,
          actions: actions,
          destinations: visible,
          currentRoute: currentRoute,
          expanded: width >= _drawerBreakpoint,
          floatingActionButton: floatingActionButton,
        ),
      );
    }

    final List<AppDestination> primary = visible
        .where((AppDestination d) => d.primary)
        .toList();
    final List<AppDestination> overflow = visible
        .where((AppDestination d) => !d.primary)
        .toList();
    final int selectedIndex = primary.indexWhere(
      (AppDestination d) => d.route == currentRoute,
    );

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,

        // extendBodyBehindAppBar is deliberately FALSE. It was true, which put
        // the first row of every screen underneath the app bar where it could
        // not be read or tapped. Letting content slide under a frosted bar looks
        // good in a mockup and is a bug in a form.
        extendBodyBehindAppBar: false,

        // extendBody stays TRUE: the bottom navigation is a floating pill, so
        // the content must fill the space around and behind it or there would be
        // a dead strip below the pill. The pill's height is published as
        // MediaQuery.padding.bottom just below, and screenPadding() in
        // core/config/glass.dart reads it so nothing ends up unreachable.
        extendBody: true,

        appBar: _GlassAppBar(title: title, actions: actions),
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: MediaQuery.paddingOf(context).copyWith(
              bottom:
                  _PillNavBar.totalHeight +
                  MediaQuery.viewPaddingOf(context).bottom,
            ),
          ),
          child: body,
        ),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: _PillNavBar(
          primary: primary,
          selectedIndex: selectedIndex >= 0 ? selectedIndex : primary.length,
          moreLabel: l.navMore,
          onSelected: (int index) {
            if (index < primary.length) {
              context.go(primary[index].route);
            } else {
              _showMoreSheet(context, l, overflow);
            }
          },
        ),
      ),
    );
  }

  void _showMoreSheet(
    BuildContext context,
    L l,
    List<AppDestination> destinations,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // The content behind needs dimming, or the frost has nothing to separate
      // it from and the tap-to-dismiss area reads as inert.
      barrierColor: AppColors.ink.withValues(alpha: 0.22),
      builder: (BuildContext sheetContext) {
        // Not blurred: see GlassDialog. A BackdropFilter inside an overlay route
        // paints nothing on Android/Impeller.
        return GlassSurface(
          lifted: true,
          fill: GlassColors.overlay,
          margin: const EdgeInsets.all(AppSpacing.md),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
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
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 12),
                    child: Text(
                      l.navMore,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  StatCardGrid(
                    columns: 3,
                    wideColumns: 3,
                    spacing: AppSpacing.sm,
                    children: <Widget>[
                      for (final AppDestination destination in destinations)
                        _MoreTile(
                          destination: destination,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            context.go(destination.route);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.destination, required this.onTap});

  final AppDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        // Minimum touch target stated rather than assumed.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    destination.icon,
                    size: 22,
                    color: AppColors.brandDeep,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  destination.label(L.of(context)),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted app bar. One [BackdropFilter] — the topmost chrome layer.
class _GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassAppBar({required this.title, required this.actions});

  final String title;
  final List<Widget>? actions;

  static const double _height = 60;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    // viewPadding, not padding: `padding` is zeroed once something above has
    // consumed it, and the bar would then sit under the notch.
    final double top = MediaQuery.viewPaddingOf(context).top;
    return SizedBox(
      height: _height + top,
      child: GlassSurface(
        blurred: true,
        lifted: true,
        fill: GlassColors.chrome,
        // Square corners: this pane is flush to the screen edges, and rounding
        // it would leave two slivers of raw field beside it.
        radius: 0,
        child: Padding(
          padding: EdgeInsetsDirectional.only(top: top),
          child: Row(
            children: <Widget>[
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).appBarTheme.titleTextStyle,
                ),
              ),
              ...?actions,
              const _AccountMenu(),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom navigation: a floating frosted pill.
///
/// Not a Material [NavigationBar]. That widget is a full-width slab with its own
/// fixed height and indicator geometry, and it fights every attempt to inset it
/// from the screen edges — which is the whole point of a floating pill.
///
/// The guidance is explicit that floating chrome needs breathing room from the
/// edge rather than being stuck to it, so the pill sits 16px in from the sides
/// and clears the safe area at the bottom. Content scrolls behind it.
///
/// This is the second of the three [BackdropFilter]s in the shell.
class _PillNavBar extends StatelessWidget {
  const _PillNavBar({
    required this.primary,
    required this.selectedIndex,
    required this.moreLabel,
    required this.onSelected,
  });

  final List<AppDestination> primary;
  final int selectedIndex;
  final String moreLabel;
  final ValueChanged<int> onSelected;

  static const double _pillHeight = 66;
  static const double _bottomGap = 12;

  /// What the pill occupies, published to the body as MediaQuery bottom padding
  /// so screen content can clear it.
  static const double totalHeight = _pillHeight + _bottomGap;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final List<({IconData icon, IconData selected, String label})> items =
        <({IconData icon, IconData selected, String label})>[
          for (final AppDestination d in primary)
            (
              icon: d.icon,
              selected: d.selectedIcon,
              label: (d.shortLabel ?? d.label)(l),
            ),
          (
            icon: Icons.grid_view_outlined,
            selected: Icons.grid_view,
            label: moreLabel,
          ),
        ];

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
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: _PillItem(
                    icon: items[i].icon,
                    selectedIcon: items[i].selected,
                    label: items[i].label,
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Reduced motion collapses the capsule transition to zero rather than
    // skipping it — the end state must still be correct, only instant.
    final Duration duration = prefersReducedMotion(context)
        ? Duration.zero
        : AppMotion.fast;

    return Semantics(
      // The destination is conveyed by label AND by state, not by colour alone.
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
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
                color: selected ? AppColors.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              alignment: Alignment.center,
              child: Icon(
                selected ? selectedIcon : icon,
                size: 20,
                color: selected ? AppColors.onFill : AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.body,
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.brandDeep : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.title,
    required this.body,
    required this.actions,
    required this.destinations,
    required this.currentRoute,
    required this.expanded,
    required this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final List<AppDestination> destinations;
  final String currentRoute;
  final bool expanded;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    int selectedIndex = destinations.indexWhere(
      (AppDestination d) => d.route == currentRoute,
    );
    if (selectedIndex < 0) selectedIndex = 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Row(
          children: <Widget>[
            // Third and last BackdropFilter in the shell. The rail floats inset
            // from the edges rather than being a full-height slab: floating
            // chrome needs breathing room from the screen edge, and the gap lets
            // the field show around it.
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: GlassSurface(
                blurred: true,
                lifted: true,
                fill: GlassColors.chrome,
                // LayoutBuilder + ConstrainedBox + IntrinsicHeight, not a bare
                // SingleChildScrollView. NavigationRail lays its destinations out
                // in a Column with flex children, so an unbounded height throws
                // "RenderFlex children have non-zero flex but incoming height
                // constraints are unbounded" and the whole rail fails to paint.
                // The scroll view is still needed: thirteen destinations do not
                // fit a short window.
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) =>
                      SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: NavigationRail(
                              extended: expanded,
                              minExtendedWidth: 232,
                              backgroundColor: Colors.transparent,
                              selectedIndex: selectedIndex,
                              onDestinationSelected: (int index) =>
                                  context.go(destinations[index].route),
                              leading: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  top: 12,
                                  bottom: 16,
                                ),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.brand,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.chip,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.diversity_3,
                                    color: AppColors.onFill,
                                    size: 22,
                                  ),
                                ),
                              ),
                              destinations: <NavigationRailDestination>[
                                for (final AppDestination destination
                                    in destinations)
                                  NavigationRailDestination(
                                    icon: Icon(destination.icon),
                                    selectedIcon: Icon(
                                      destination.selectedIcon,
                                    ),
                                    label: Text(destination.label(l)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  // The header is a floating pane too, inset to match the rail,
                  // so the two read as one chrome layer. Not blurred: it does not
                  // overlap the scrolling body, so there is nothing behind it to
                  // frost, and a blur here would cost a layer for no effect.
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 12, 0),
                    child: GlassSurface(
                      lifted: true,
                      fill: GlassColors.chrome,
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        20,
                        10,
                        8,
                        10,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          ...?actions,
                          const _AccountMenu(),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        0,
                        0,
                        12,
                        0,
                      ),
                      child: body,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AppUser? user = ref.watch(authControllerProvider).user;
    if (user == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: user.displayName,
      offset: const Offset(0, 48),
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        side: const BorderSide(color: GlassColors.hairline),
      ),
      icon: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        alignment: Alignment.center,
        child: Text(
          user.displayName.characters.take(1).toString(),
          style: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 15,
            color: AppColors.onFill,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                user.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 2),
              Text(user.email, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              _RoleChip(role: user.role),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'signOut',
          child: Row(
            children: <Widget>[
              const Icon(Icons.logout, size: 18, color: AppColors.danger),
              const SizedBox(width: 10),
              Text(
                l.signOut,
                style: const TextStyle(
                  fontFamily: AppFonts.body,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (String value) {
        if (value == 'signOut') {
          unawaitedSignOut(ref);
        }
      },
    );
  }

  static void unawaitedSignOut(WidgetRef ref) {
    ref.read(authControllerProvider.notifier).signOut();
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final String label = switch (role) {
      AppRole.admin => l.roleAdmin,
      AppRole.financeManager => l.roleFinanceManager,
      AppRole.treasurer => l.roleTreasurer,
      AppRole.viewer => l.roleViewer,
    };
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.infoSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.info,
        ),
      ),
    );
  }
}
