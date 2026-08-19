import 'package:flutter/material.dart';

import '../../features/auth/domain/app_user.dart';
import '../../l10n/app_localizations.dart';

abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String pending = '/pending';
  static const String suspended = '/suspended';
  static const String forbidden = '/forbidden';

  /// The عديل portal. Not in [destinations] and never in the navigation bar:
  /// it is the ONLY route a portal account may occupy, and the only one he may
  /// not leave. See the guard in app_router.dart.
  static const String myDues = '/my-dues';

  static const String home = '/';

  /// مجلس العدايل. The ONE association screen a portal account may also open —
  /// see the guard in app_router.dart, and the note on [myDues].
  static const String chat = '/chat';

  /// The register. ONE route where there were two — `/families` listed
  /// households and `/members` listed the people inside them, and they describe
  /// the same rows now.
  static const String adeels = '/adeels';
  static const String receivables = '/receivables';
  static const String payments = '/payments';
  static const String cash = '/cash';
  static const String statements = '/statements';
  static const String alerts = '/alerts';
  static const String reports = '/reports';
  static const String officials = '/officials';
  static const String audit = '/audit';
  static const String settings = '/settings';
  static const String users = '/users';
}


/// ── WHICH ROUTES A PORTAL ACCOUNT MAY OCCUPY ────────────────────────────────
/// An عديل is signed in and approved, so he passes every check the router makes
/// of a viewer — and every association screen would render EMPTY for him,
/// because RLS hands him nothing but his own rows. Pinning him is what turns
/// that emptiness into a coherent app.
///
/// ⚠ THE SET IS TWO, and the second was added for a reason that does not
///   generalise. `/chat` is admitted because `read_chat` genuinely admits him:
///   the room is the one table in this schema both kinds of account share, so it
///   is a screen that is FULL for him. Anything else added here without a policy
///   admitting him too is a blank page with no explanation on it.
///
/// A named function rather than a literal inside the guard, so the rule can be
/// asserted directly — the guard around it needs a router, a widget tree and a
/// live session before it will answer anything.
///
/// This is presentation either way. The database refuses him the same rows
/// whether or not this exists; supabase/tests/45_adeel_portal.sql and 46_chat.sql
/// are where that is actually proved.
bool portalMayOpen(String route) =>
    route == AppRoutes.myDues || route == AppRoutes.chat;
class AppDestination {
  const AppDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.shortLabel,
    this.minimumRole = AppRole.viewer,
    this.primary = false,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String Function(L) label;
  final String Function(L)? shortLabel;

  /// Screens below this role are hidden from navigation AND rejected by the
  /// API. Hiding alone would be decoration.
  final AppRole minimumRole;

  /// Shown in the phone's bottom bar rather than behind "المزيد".
  final bool primary;

  bool isVisibleTo(AppRole role) => role.atLeast(minimumRole);
}

/// Mirrors the prototype's twelve sidebar entries, plus user management, which
/// Google Sign-In makes necessary — without it no second person can ever be
/// let in.
const List<AppDestination> appDestinations = <AppDestination>[
  AppDestination(
    route: AppRoutes.home,
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: _homeLabel,
    primary: true,
  ),
  AppDestination(
    route: AppRoutes.adeels,
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    label: _registerLabel,
    primary: true,
  ),
  // The room. `viewer` like the register, because it is not an administrative
  // screen — everyone in the association belongs in it, which is the point.
  //
  // ⚠ NOT `primary`, and that is a decision rather than an oversight. The phone
  //   bar is a four-slot budget and this design spends it on the money path:
  //   الرئيسية، السجل، العمليات، الصندوق. More importantly, the people this
  //   room was built for never see the bar at all — an عديل is on the portal,
  //   and his way in is the button on it, not this list. For staff it is one
  //   tap behind «المزيد», which is the right weight for a screen they visit a
  //   few times a day rather than work in.
  AppDestination(
    route: AppRoutes.chat,
    icon: Icons.forum_outlined,
    selectedIcon: Icons.forum,
    label: _chatLabel,
  ),
  AppDestination(
    route: AppRoutes.payments,
    icon: Icons.payments_outlined,
    selectedIcon: Icons.payments,
    label: _paymentsLabel,
    shortLabel: _paymentsShortLabel,
    primary: true,
  ),
  AppDestination(
    route: AppRoutes.cash,
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet,
    label: _cashLabel,
    primary: true,
  ),
  AppDestination(
    route: AppRoutes.receivables,
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    label: _receivablesLabel,
  ),
  AppDestination(
    route: AppRoutes.statements,
    icon: Icons.description_outlined,
    selectedIcon: Icons.description,
    label: _statementsLabel,
  ),
  AppDestination(
    route: AppRoutes.alerts,
    icon: Icons.notifications_outlined,
    selectedIcon: Icons.notifications,
    label: _alertsLabel,
  ),
  AppDestination(
    route: AppRoutes.reports,
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart,
    label: _reportsLabel,
  ),
  AppDestination(
    route: AppRoutes.officials,
    icon: Icons.badge_outlined,
    selectedIcon: Icons.badge,
    label: _officialsLabel,
  ),
  AppDestination(
    route: AppRoutes.audit,
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    label: _auditLabel,
    minimumRole: AppRole.financeManager,
  ),
  AppDestination(
    route: AppRoutes.users,
    icon: Icons.manage_accounts_outlined,
    selectedIcon: Icons.manage_accounts,
    label: _usersLabel,
    minimumRole: AppRole.admin,
  ),
  AppDestination(
    route: AppRoutes.settings,
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: _settingsLabel,
    minimumRole: AppRole.admin,
  ),
];

// Top-level functions, because a const list cannot hold closures.
String _homeLabel(L l) => l.navHome;
String _chatLabel(L l) => l.navChat;
String _registerLabel(L l) => l.navRegister;
String _receivablesLabel(L l) => l.navReceivables;
String _paymentsLabel(L l) => l.navPayments;
String _paymentsShortLabel(L l) => l.navPaymentsShort;
String _cashLabel(L l) => l.navCash;
String _statementsLabel(L l) => l.navStatements;
String _alertsLabel(L l) => l.navAlerts;
String _reportsLabel(L l) => l.navReports;
String _officialsLabel(L l) => l.navOfficials;
String _auditLabel(L l) => l.navAudit;
String _settingsLabel(L l) => l.navSettings;
String _usersLabel(L l) => l.navUsers;

AppDestination? destinationForRoute(String route) {
  for (final AppDestination destination in appDestinations) {
    if (destination.route == route) return destination;
  }
  return null;
}

/// Resolves nested locations too, so `/adeels/12` is governed by the same
/// role rule as `/adeels`. Without this a child route would slip past the
/// guard entirely.
AppDestination? destinationForLocation(String location) {
  final AppDestination? exact = destinationForRoute(location);
  if (exact != null) return exact;

  for (final AppDestination destination in appDestinations) {
    if (destination.route == AppRoutes.home) continue;
    if (location.startsWith('${destination.route}/')) return destination;
  }
  return null;
}
