import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _routesVisibleTo(AppRole role) => appDestinations
    .where((AppDestination d) => d.isVisibleTo(role))
    .map((AppDestination d) => d.route)
    .toList();

void main() {
  group('navigation destinations', () {
    test('cover all thirteen prototype screens plus user management', () {
      // The prototype's sidebar has twelve entries and familyDetail is reached
      // from within Families, so twelve top-level destinations plus the new
      // user-management screen Google Sign-In makes necessary.
      expect(appDestinations.length, 13);
      expect(_routesVisibleTo(AppRole.admin).length, 13);
    });

    test('a viewer cannot see the audit log, settings, or user management', () {
      final List<String> visible = _routesVisibleTo(AppRole.viewer);
      expect(visible, isNot(contains(AppRoutes.audit)));
      expect(visible, isNot(contains(AppRoutes.settings)));
      expect(visible, isNot(contains(AppRoutes.users)));
      expect(visible, contains(AppRoutes.families));
      expect(visible, contains(AppRoutes.cash));
    });

    test('a treasurer still cannot reach the audit log', () {
      expect(
        _routesVisibleTo(AppRole.treasurer),
        isNot(contains(AppRoutes.audit)),
      );
    });

    test('a finance manager sees the audit log but not settings', () {
      final List<String> visible = _routesVisibleTo(AppRole.financeManager);
      expect(visible, contains(AppRoutes.audit));
      expect(visible, isNot(contains(AppRoutes.settings)));
      expect(visible, isNot(contains(AppRoutes.users)));
    });

    test('the phone bottom bar holds exactly four primary destinations', () {
      // Four plus a "More" button; the remaining nine must stay reachable
      // through that sheet, unlike the prototype where seven screens have no
      // phone entry point at all.
      final List<AppDestination> primary = appDestinations
          .where((AppDestination d) => d.primary)
          .toList();
      expect(primary.length, 4);
      expect(primary.first.route, AppRoutes.home);
    });

    test('every route is unique and resolvable', () {
      final Set<String> routes = appDestinations
          .map((AppDestination d) => d.route)
          .toSet();
      expect(routes.length, appDestinations.length);
      for (final String route in routes) {
        expect(destinationForRoute(route), isNotNull);
      }
      expect(destinationForRoute('/not-a-route'), isNull);
    });
  });
}
