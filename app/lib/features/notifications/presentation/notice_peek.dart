import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/notify/notifier.dart';
import '../../../core/router/destinations.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models.dart';
import 'notice_detail_screen.dart';
import 'notifications_screen.dart';
import 'providers.dart';

/// ما يصل والتطبيق مفتوح، وما يُفتح من إشعار الهاتف (15/09).
///
/// «يظهر على شاشة الهاتف الرئيسية ويضل 20 ثانية على ان يكون بيه ايضاح لمحتوى
/// الرساله واذا تم الضغط على الاشعار قبل ان يختفي يفتح محتوي الرساله».
///
/// Two jobs, both over EVERY screen, which is why this sits in
/// MaterialApp.builder beside the call banner rather than on the portal:
///
/// 1. **The banner.** When a notice arrives while the app is in front of him,
///    `NoticesUnread` hands it to [noticePeekProvider] instead of posting a
///    phone notification. It is drawn here — title, the first lines of the
///    sentence, how many more wait — for exactly twenty seconds. A tap opens
///    [NoticeDetailScreen]; the ✕ puts it away; either way the notice is on
///    the tab, where it always was.
/// 2. **The phone's tap.** A tap on the notification posted while he was away
///    lands in [AppNotifier.tappedNotice]. It is opened here the moment he is
///    standing on his portal — not before: a page pushed over the splash
///    screen would be thrown away by the redirect that follows it.
///
/// ⚠ ABOVE THE NAVIGATOR, SO THE CALL BANNER'S RULES APPLY: no `Tooltip`, no
///   `showDialog`, nothing that looks up an `Overlay`. Pages are pushed through
///   the router's navigator KEY. And it takes no height when silent — it is a
///   layer over the app, never a row above it, so nothing below it moves.
class NoticePeekHost extends ConsumerStatefulWidget {
  const NoticePeekHost({required this.router, required this.child, super.key});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<NoticePeekHost> createState() => _NoticePeekHostState();
}

class _NoticePeekHostState extends ConsumerState<NoticePeekHost> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    AppNotifier.tappedNotice.addListener(_drainSoon);
    AppNotifier.tappedRoute.addListener(_drainSoon);
    widget.router.routerDelegate.addListener(_drainSoon);
    _drainSoon();
  }

  @override
  void didUpdateWidget(NoticePeekHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_drainSoon);
      widget.router.routerDelegate.addListener(_drainSoon);
    }
  }

  @override
  void dispose() {
    AppNotifier.tappedNotice.removeListener(_drainSoon);
    AppNotifier.tappedRoute.removeListener(_drainSoon);
    widget.router.routerDelegate.removeListener(_drainSoon);
    super.dispose();
  }

  NavigatorState? get _navigator =>
      widget.router.routerDelegate.navigatorKey.currentState;

  /// A member, let in, on his own screens — the only reader a notice opens
  /// for. A revoked key is on /pending and is not.
  bool get _atPortal {
    final AppUser? u = ref.read(authControllerProvider).user;
    return u != null &&
        u.isAdeelPortal &&
        u.status == AccountStatus.approved &&
        !u.deviceLocked &&
        portalMayOpen(
          widget.router.routerDelegate.currentConfiguration.uri.path,
        );
  }

  /// After the frame, never inside the notification that announced a move.
  ///
  /// ⚠ THE ROUTER TELLS ITS LISTENERS BEFORE IT REBUILDS THE NAVIGATOR. A page
  ///   pushed from inside that call sits on top of the OLD page — /pending, the
  ///   splash — and is thrown away with it a moment later, when the new
  ///   location's page replaces it. Found by the test that goes /pending →
  ///   /my-dues: the notice opened and vanished in the same frame.
  void _drainSoon() {
    if (AppNotifier.tappedNotice.value == null &&
        AppNotifier.tappedRoute.value == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainRoute();
      unawaited(_drain());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The admin, let in, somewhere past the sign-in screens.
  bool get _adminInside {
    final AppUser? u = ref.read(authControllerProvider).user;
    final String path =
        widget.router.routerDelegate.currentConfiguration.uri.path;
    return u != null &&
        !u.isAdeelPortal &&
        u.status == AccountStatus.approved &&
        u.role.atLeast(AppRole.admin) &&
        path.isNotEmpty &&
        path != AppRoutes.splash &&
        path != AppRoutes.login &&
        path != AppRoutes.pending &&
        path != AppRoutes.suspended;
  }

  /// Open the screen an admin's phone alert was tapped for — a new proposal
  /// opens «مقترحات المشتركين». A ROUTE, not a push: the admin's screens are
  /// locations, and the guard is what decides he may stand on one.
  void _drainRoute() {
    final String? route = AppNotifier.tappedRoute.value;
    if (route == null || !mounted || !_adminInside) return;
    AppNotifier.tappedRoute.value = null;
    widget.router.go(route);
  }

  /// Open the notice his phone notification was tapped for, once he can.
  Future<void> _drain() async {
    final int? id = AppNotifier.tappedNotice.value;
    if (id == null || _opening || !mounted || !_atPortal) return;
    _opening = true;
    AppNotifier.tappedNotice.value = null;
    try {
      AppNotice? notice;
      try {
        notice = await ref.read(notificationsRepositoryProvider).byId(id);
      } on Object {
        notice = null;
      }
      final NavigatorState? nav = _navigator;
      if (!mounted || nav == null) return;
      ref.read(noticePeekProvider.notifier).dismiss();
      if (notice == null) {
        // Not readable any more, or the network failed: the tab, where it
        // lives, rather than nothing at all.
        unawaited(
          nav.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const NotificationsScreen(portal: true),
            ),
          ),
        );
      } else {
        unawaited(ref.read(noticesUnreadProvider.notifier).readOne(notice.id));
        unawaited(nav.push<void>(NoticeDetailScreen.route(notice)));
      }
    } finally {
      _opening = false;
    }
  }

  void _open(NoticePeek peek) {
    ref.read(noticePeekProvider.notifier).dismiss();
    final String? route = peek.route;
    if (route != null) {
      widget.router.go(route);
      return;
    }
    final NavigatorState? nav = _navigator;
    if (nav == null) return;
    unawaited(ref.read(noticesUnreadProvider.notifier).readOne(peek.notice.id));
    unawaited(nav.push<void>(NoticeDetailScreen.route(peek.notice)));
  }

  @override
  Widget build(BuildContext context) {
    // Signing in finishes after a launch from a tap — ask again then.
    ref.listen<AuthState>(authControllerProvider, (_, _) => _drainSoon());
    final NoticePeek? peek = ref.watch(noticePeekProvider);

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        Align(
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: prefersReducedMotion(context)
                ? Duration.zero
                : AppMotion.base,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.3),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
            child: peek == null
                ? const SizedBox.shrink()
                : NoticePeekBanner(
                    key: ValueKey<int>(peek.notice.id),
                    peek: peek,
                    onOpen: () => _open(peek),
                    onDismiss: () =>
                        ref.read(noticePeekProvider.notifier).dismiss(),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The banner itself: what kind, the title, the first three lines.
///
/// ⚠ OPAQUE. It floats over whatever screen he is on — figures, a chat, a
///   form — and a translucent pane would print its sentence on top of theirs.
///   `GlassColors.menu` is the one fully opaque surface in the theme, made for
///   exactly this.
class NoticePeekBanner extends StatelessWidget {
  const NoticePeekBanner({
    required this.peek,
    required this.onOpen,
    required this.onDismiss,
    super.key,
  });

  final NoticePeek peek;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AppNotice n = peek.notice;
    final (IconData icon, Color tone) = NoticeTile.look(n.kind);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassSurface(
            fill: GlassColors.menu,
            borderColor: tone.withValues(alpha: 0.45),
            lifted: true,
            // ⚠ A MATERIAL OF ITS OWN: the ink needs one, and above the
            //   Navigator there is no Scaffold to lend it.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(AppRadius.pane),
                child: Semantics(
                  button: true,
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                          ),
                          child: Icon(icon, size: 20, color: tone),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.4,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                n.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: AppColors.text,
                                ),
                              ),
                              if (peek.more > 0) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  l.noticesMoreWaiting(peek.more),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // ⚠ SEMANTICS, NOT tooltip — no Overlay up here.
                        Semantics(
                          label: l.noticePeekDismiss,
                          button: true,
                          child: ExcludeSemantics(
                            child: IconButton(
                              onPressed: onDismiss,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.close,
                                size: 20,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
