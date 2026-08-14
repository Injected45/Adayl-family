import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/app_user.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/forbidden_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/pending_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/auth/presentation/suspended_screen.dart';
import '../../features/directory/presentation/families_screen.dart';
import '../../features/directory/presentation/family_detail_screen.dart';
import '../../features/directory/presentation/family_form_screen.dart';
import '../../features/directory/presentation/family_portal_screen.dart';
import '../../features/directory/presentation/members_screen.dart';
import '../../features/directory/presentation/officials_screen.dart';
import '../../features/directory/presentation/receivables_screen.dart';
import '../../features/directory/presentation/statements_screen.dart';
import '../../features/finance/presentation/cash_screen.dart';
import '../../features/finance/presentation/payments_screen.dart';
import '../../features/home/presentation/placeholder_screen.dart';
import '../../features/oversight/presentation/alerts_screen.dart';
import '../../features/oversight/presentation/audit_screen.dart';
import '../../features/oversight/presentation/dashboard_screen.dart';
import '../../features/oversight/presentation/reports_screen.dart';
import '../../features/oversight/presentation/settings_screen.dart';
import '../../features/oversight/presentation/users_screen.dart';
import 'destinations.dart';

/// Every destination now has a real screen, so the placeholder builder below
/// produces nothing — it is kept only so a future destination cannot 404 before
/// its screen exists.
const Set<String> _implementedRoutes = <String>{
  AppRoutes.home,
  AppRoutes.families,
  AppRoutes.members,
  AppRoutes.receivables,
  AppRoutes.statements,
  AppRoutes.officials,
  AppRoutes.payments,
  AppRoutes.cash,
  AppRoutes.alerts,
  AppRoutes.reports,
  AppRoutes.audit,
  AppRoutes.settings,
  AppRoutes.users,
};

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  // go_router re-evaluates `redirect` whenever this notifies, so a sign-out or
  // a role change is applied to the current location immediately instead of
  // waiting for the next navigation.
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (AuthState? _, AuthState _) {
    refresh.value++;
  });
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (_, GoRouterState state) => _guard(ref, state),
    routes: <RouteBase>[
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.pending,
        builder: (_, _) => const PendingScreen(),
      ),
      GoRoute(
        path: AppRoutes.suspended,
        builder: (_, _) => const SuspendedScreen(),
      ),
      GoRoute(
        path: AppRoutes.forbidden,
        builder: (_, _) => const ForbiddenScreen(),
      ),
      GoRoute(
        path: AppRoutes.myFamily,
        builder: (_, _) => const FamilyPortalScreen(),
      ),
      GoRoute(path: AppRoutes.home, builder: (_, _) => const DashboardScreen()),

      // ── Phase 4: the read-only screens ──────────────────────────────
      GoRoute(
        path: AppRoutes.families,
        builder: (_, _) => const FamiliesScreen(),
        routes: <RouteBase>[
          // Registered BEFORE ':id', which would otherwise capture "new".
          GoRoute(path: 'new', builder: (_, _) => const FamilyFormScreen()),
          GoRoute(
            path: ':id',
            builder: (_, GoRouterState state) {
              final int? id = int.tryParse(state.pathParameters['id'] ?? '');
              // A malformed id is a bad link, not a crash.
              return id == null
                  ? const FamiliesScreen()
                  : FamilyDetailScreen(familyId: id);
            },
            routes: <RouteBase>[
              GoRoute(
                path: 'edit',
                builder: (_, GoRouterState state) => FamilyFormScreen(
                  familyId: int.tryParse(state.pathParameters['id'] ?? ''),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.members,
        builder: (_, _) => const MembersScreen(),
      ),
      GoRoute(
        path: AppRoutes.receivables,
        builder: (_, _) => const ReceivablesScreen(),
      ),
      GoRoute(
        path: AppRoutes.statements,
        builder: (_, _) => const StatementsScreen(),
      ),
      GoRoute(
        path: AppRoutes.officials,
        builder: (_, _) => const OfficialsScreen(),
      ),

      // ── Phase 5: the financial screens ──────────────────────────────
      GoRoute(
        path: AppRoutes.payments,
        builder: (_, _) => const PaymentsScreen(),
      ),
      GoRoute(path: AppRoutes.cash, builder: (_, _) => const CashScreen()),

      // ── Phase 6: reporting and oversight ────────────────────────────
      GoRoute(path: AppRoutes.alerts, builder: (_, _) => const AlertsScreen()),
      GoRoute(
        path: AppRoutes.reports,
        builder: (_, _) => const ReportsScreen(),
      ),
      GoRoute(path: AppRoutes.audit, builder: (_, _) => const AuditScreen()),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
      ),
      GoRoute(path: AppRoutes.users, builder: (_, _) => const UsersScreen()),

      // Everything else stays a placeholder until its phase lands, but the
      // route and its role guard are real so navigation is testable now.
      for (final AppDestination destination in appDestinations)
        if (!_implementedRoutes.contains(destination.route))
          GoRoute(
            path: destination.route,
            builder: (_, _) => PlaceholderScreen(destination: destination),
          ),
    ],
  );
});

/// The single place where authentication, approval, and role are enforced for
/// navigation. Because it runs on every route change, a demotion cannot be
/// outlived by an already-open screen or a stale deep link.
String? _guard(Ref ref, GoRouterState state) {
  final AuthState auth = ref.read(authControllerProvider);
  final String location = state.matchedLocation;

  switch (auth.stage) {
    case AuthStage.initializing:
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case AuthStage.signedOut:
    case AuthStage.signingIn:
      return location == AppRoutes.login ? null : AppRoutes.login;
    case AuthStage.pending:
      return location == AppRoutes.pending ? null : AppRoutes.pending;
    case AuthStage.suspended:
      return location == AppRoutes.suspended ? null : AppRoutes.suspended;
    case AuthStage.signedIn:
      break;
  }

  // ── The family portal, before anything else ────────────────────────────────
  // A head of family is signed in and approved, so he reaches this point like
  // any viewer — but he is not staff, and every association screen would render
  // empty for him because RLS hands him nothing outside his own family. Pinning
  // him to one route is what turns that emptiness into a coherent app.
  //
  // Placed above the pre-auth redirect deliberately: that line sends anyone
  // arriving at /splash or /login to the dashboard, and for him the dashboard
  // is the wrong destination.
  //
  // This is presentation, as always. The database refuses him the same rows
  // whether or not this branch exists — supabase/tests/45_family_portal.sql is
  // where that is actually proved.
  if (auth.user?.isFamilyHead ?? false) {
    return location == AppRoutes.myFamily ? null : AppRoutes.myFamily;
  }

  const Set<String> preAuthRoutes = <String>{
    AppRoutes.splash,
    AppRoutes.login,
    AppRoutes.pending,
    AppRoutes.suspended,
  };
  if (preAuthRoutes.contains(location)) return AppRoutes.home;

  // The reverse: staff have no family scope, so the portal would render nothing
  // for them. Sending them home beats an empty screen with no explanation.
  if (location == AppRoutes.myFamily) return AppRoutes.home;

  final AppDestination? destination = destinationForLocation(location);
  final AppRole role = auth.user?.role ?? AppRole.viewer;
  if (destination != null && !destination.isVisibleTo(role)) {
    return AppRoutes.forbidden;
  }

  // Reading the family list is open to everyone, but entering or amending a
  // family is a finance-manager act. The child write routes therefore need
  // their own check — their parent destination's role is not strict enough.
  final bool isFamilyWrite =
      location == '${AppRoutes.families}/new' ||
      (location.startsWith('${AppRoutes.families}/') &&
          location.endsWith('/edit'));
  if (isFamilyWrite && !role.atLeast(AppRole.financeManager)) {
    return AppRoutes.forbidden;
  }

  return null;
}
