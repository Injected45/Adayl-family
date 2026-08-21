import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/chat/presentation/unread_bell.dart';
import '../../l10n/app_localizations.dart';
import '../config/glass.dart';
import '../config/theme.dart';
import '../router/destinations.dart';
import '../state/refresh.dart';
import '../state/restart.dart';
import 'app_background.dart';
import 'nav_pill_bar.dart';
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
    this.leading,
    super.key,
  });

  final String title;

  /// A BUILDER, not a widget, and the difference is load-bearing.
  ///
  /// This scaffold publishes everything that floats over the body — the pill,
  /// the gesture bar, the FAB — as `MediaQuery.padding.bottom`, so a scroll view
  /// can reserve the space by asking [bottomInset]. That only works if the
  /// context doing the asking is BELOW the MediaQuery.
  ///
  /// It was not. A screen builds its own body inside its own `build`, so
  /// `context` there is an ANCESTOR of this scaffold and reads straight past
  /// the override to the raw window padding — zero on most phones. Every list
  /// whose padding was written at screen level therefore reserved NOTHING, and
  /// the code looked right at every single call site: `bottomInset(context)`,
  /// exactly as documented, silently returning 0.
  ///
  /// Taking a builder makes the correct context the only one in scope. A call
  /// site cannot pass the wrong one by accident, and a new screen cannot
  /// reintroduce this by forgetting something — there is nothing to forget.
  final WidgetBuilder body;

  final String currentRoute;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// A control for the far side of the bar, when a screen has somewhere
  /// specific to send the reader.
  ///
  /// ⚠ IT OVERRIDES THE PORTAL HOUSE BELOW, and that is the point: a screen
  ///   that knows its own way out says so, and one that does not gets the
  ///   default. Two rules for one slot, with the screen winning.
  final Widget? leading;

  static const double _railBreakpoint = 600;
  static const double _drawerBreakpoint = 1024;

  /// What an end-floating FAB occupies: the button plus the margin Scaffold
  /// keeps between it and whatever is below it.
  ///
  /// Reserved as bottom padding on the two screens that HAVE one — the register
  /// and the collections list — because `endFloat` puts the button ON TOP of
  /// the scrolling content rather than beside it. The pill was already
  /// published below; the FAB was not, so the last card cleared the pill by
  /// 24dp and then had its NAME ROW covered by the button sitting 16dp above
  /// it. That is the exact complaint: the row is there, it scrolls to the
  /// bottom, and the one thing you need off it is behind a button.
  ///
  /// 56 is the Material 3 height of both a regular and an extended FAB. A
  /// `FloatingActionButton.small` would over-reserve by 16dp of empty space,
  /// which is the harmless direction to be wrong in — this app uses neither.
  static const double _fabBand = 56 + kFloatingActionButtonMargin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AppUser? me = ref.watch(authControllerProvider).user;
    final AppRole role = me?.role ?? AppRole.viewer;

    // ── A MEMBER GETS NO NAVIGATION AT ALL ─────────────────────────────────
    //
    // He reaches exactly one screen through this scaffold — المحادثات — and
    // the router refuses him every other destination. Filtering by ROLE was
    // not enough: a bound portal account carries AppRole.viewer, so the pill
    // offered him the register, the treasury, the receivables and the reports.
    // Tapping any of them bounced him straight back.
    //
    // ⚠ AND THAT IS WORSE THAN AN ERROR. A row of doors that do not open
    //   tells a member the app is keeping something from him and invites him
    //   to wonder what — about an association he belongs to. The honest screen
    //   is the one that never mentions them: he has one destination, so he is
    //   shown none, and «المزيد» with them hidden inside is not a fix either.
    //
    //   The refusal itself stays where it belongs — in the router guard and in
    //   RLS. This hides an invitation, it does not grant or withhold anything.
    final bool portal = me?.isAdeelPortal ?? false;

    final List<AppDestination> visible = portal
        ? const <AppDestination>[]
        : appDestinations
              .where((AppDestination d) => d.isVisibleTo(role))
              .toList();
    final double width = MediaQuery.sizeOf(context).width;

    // The refresh action is on EVERY screen, ahead of whatever the screen adds.
    // Individual screens have pull-to-refresh, but only over their own list, and
    // this app's figures are association-wide: one payment moves the treasury,
    // the register, the dashboard and the alerts at once. One button that
    // reloads all of it is the difference between trusting the numbers and
    // wondering when they were last fetched.
    final List<Widget> barActions = <Widget>[
      // ── The bell, ahead of everything ────────────────────────────────────
      // المحادثات lives behind «المزيد», which is the right weight for the
      // SCREEN and the wrong place for its badge: a count nobody sees until he
      // opens the sheet answers the question exactly when it has stopped being
      // asked. The bar is on every screen, so the answer is where the question
      // is. It is hidden for anyone the room would refuse anyway.
      const ChatBell(),
      const RefreshAction(),
      const RestartAction(),
      ...?actions,
    ];

    // ⚠ AND NEVER THE RAIL FOR HIM. NavigationRail asserts on fewer than two
    //   destinations, so a member on a tablet would not get a tidy screen —
    //   he would get a crash. The phone layout is also the right shape for a
    //   man with one destination, at any width.
    if (width >= _railBreakpoint && !portal) {
      return AppBackground(
        child: _WideLayout(
          title: title,
          body: body,
          actions: barActions,
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

        appBar: _GlassAppBar(
          title: title,
          actions: barActions,
          // ── HIS WAY HOME ────────────────────────────────────────────────
          // He arrived here with `context.go`, which REPLACED the location —
          // so there is nothing on the stack for a back gesture to pop, and
          // on Android the system button would put him out of the app.
          // Without this the room is a one-way door.
          //
          // Only for him: staff have the pill, and a second way back would be
          // a control that does what the bar underneath already does.
          leading: leading ??
              (portal
              ? IconButton(
                  onPressed: () => context.go(AppRoutes.myDues),
                  // A HOUSE, not a back arrow. Two reasons, and the second is
                  // the one that bit: it takes him to his own page rather than
                  // one step back — and the room already uses arrow_forward to
                  // leave a private thread for the inbox, so the same glyph in
                  // the bar above it would be two different journeys drawn
                  // identically. A widget test found that before a member did.
                  icon: const Icon(Icons.home_outlined),
                  tooltip: l.myFamilyTitle,
                )
              : null),
        ),
        // EVERYTHING that floats over the body is added up here, once, and
        // published as one number. A screen asks `bottomInset(context)` and gets
        // the right answer without knowing whether it has a FAB, whether the
        // phone has a gesture bar, or how tall the pill is — which is the only
        // way this stays correct as screens are added.
        body: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: MediaQuery.paddingOf(context).copyWith(
              // ⚠ AND THE SPACE GOES WITH THE PILL. Screens reserve this by
              //   asking bottomInset(); leave the pill's height in it with no
              //   pill drawn and a member reads his room through a band of
              //   nothing, with the message box floating above the floor.
              bottom:
                  (portal ? 0.0 : NavPillBar.totalHeight) +
                  (floatingActionButton == null ? 0.0 : _fabBand) +
                  MediaQuery.viewPaddingOf(context).bottom,
            ),
          ),
          child: Builder(builder: body),
        ),
        floatingActionButton: floatingActionButton,
        // ── ONE CAPSULE, TWO AUDIENCES ─────────────────────────────────
        // The bar moved into core/widgets/nav_pill_bar.dart so the عديل
        // portal can carry the SAME one — the association asked for that in
        // those words, «بنفس المظهر العام». It takes items rather than
        // destinations: staff build them from the destination list, a member
        // builds two by hand, and neither knows how the other is composed.
        bottomNavigationBar: portal
            ? null
            : NavPillBar(
                items: <NavPillItem>[
                  for (int i = 0; i < primary.length; i++)
                    NavPillItem(
                      icon: primary[i].icon,
                      selectedIcon: primary[i].selectedIcon,
                      label: (primary[i].shortLabel ?? primary[i].label)(l),
                      selected: i == selectedIndex,
                      onTap: () => context.go(primary[i].route),
                    ),
                  NavPillItem(
                    icon: Icons.grid_view_outlined,
                    selectedIcon: Icons.grid_view,
                    label: l.navMore,
                    selected: selectedIndex < 0,
                    onTap: () => _showMoreSheet(context, l, overflow),
                  ),
                ],
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

/// Reloads every figure in the app from the database.
///
/// Deliberately a plain, always-enabled button rather than a spinner that
/// disables itself: [refreshAll] only throws caches away, so it returns
/// instantly and the actual refetch is whatever the visible screen asks for on
/// its next build — which already has its own loading state. A second spinner
/// here would report progress it does not know about.
class RefreshAction extends ConsumerWidget {
  const RefreshAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    return IconButton(
      tooltip: l.refreshData,
      icon: const Icon(Icons.refresh),
      onPressed: () {
        refreshAll(ref);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(l.refreshedData),
              duration: const Duration(seconds: 2),
            ),
          );
      },
    );
  }
}

/// Restarts the app in place — the whole tree, every provider, from scratch.
///
/// Behind a confirmation, unlike the refresh beside it: this throws away
/// whatever the user was in the middle of, and a stray tap on a toolbar icon
/// should not be able to do that silently. The dialog also states the one thing
/// the button cannot do, because "I pressed restart and my change is still not
/// there" is the misunderstanding it would otherwise invite.
class RestartAction extends StatelessWidget {
  const RestartAction({super.key});

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return IconButton(
      tooltip: l.restartApp,
      icon: const Icon(Icons.restart_alt),
      onPressed: () async {
        final bool? go = await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => GlassDialog(
            title: Text(l.restartApp),
            content: Text(
              l.restartAppBody,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l.restartConfirm),
              ),
            ],
          ),
        );
        if (go != true || !context.mounted) return;
        RestartWidget.restart(context);
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
  const _GlassAppBar({
    required this.title,
    required this.actions,
    this.leading,
  });

  final String title;
  final List<Widget>? actions;

  /// Null everywhere but a member's one screen — see where it is passed.
  final Widget? leading;

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
              // The back control takes the place of the leading gap when it is
              // there, so the title starts at the same edge either way.
              if (leading != null)
                leading!
              else
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
  final WidgetBuilder body;
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
                      // There is no pill here, but there is still a FAB, and it
                      // still floats over the body. The SafeArea above has
                      // already consumed the device inset, so this republishes
                      // the one thing left that covers content — and publishes
                      // ZERO when there is no FAB, which keeps screenPadding()
                      // honest instead of it guessing per layout.
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          padding: MediaQuery.paddingOf(context).copyWith(
                            bottom: floatingActionButton == null
                                ? 0.0
                                : AppScaffold._fabBand,
                          ),
                        ),
                        child: Builder(builder: body),
                      ),
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
