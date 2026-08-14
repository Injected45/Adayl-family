import 'package:flutter/material.dart';

import '../../features/auth/domain/app_user.dart';
import '../../l10n/app_localizations.dart';

abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String pending = '/pending';
  static const String suspended = '/suspended';
  static const String forbidden = '/forbidden';

  /// The family portal. Not in [destinations] and never in the navigation bar:
  /// it is the ONLY route a head of family may occupy, and the only one he may
  /// not leave. See the guard in app_router.dart.
  static const String myFamily = '/my-family';

  static const String home = '/';
  static const String families = '/families';
  static const String members = '/members';
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
    route: AppRoutes.families,
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    label: _familiesLabel,
    primary: true,
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
    route: AppRoutes.members,
    icon: Icons.person_search_outlined,
    selectedIcon: Icons.person_search,
    label: _membersLabel,
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
String _familiesLabel(L l) => l.navFamilies;
String _membersLabel(L l) => l.navMembers;
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

/// Resolves nested locations too, so `/families/12` is governed by the same
/// role rule as `/families`. Without this a child route would slip past the
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
