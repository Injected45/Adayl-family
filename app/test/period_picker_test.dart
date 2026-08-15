import 'dart:convert';
import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/features/oversight/domain/models.dart';
import 'package:family_app/features/oversight/presentation/dashboard_screen.dart';
import 'package:family_app/features/oversight/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rule 15b, in the widget layer.
///
/// `generate_period` refuses an out-of-order month with RUL15, so the money is
/// never actually at risk — but a picker that lets the row be tapped turns a
/// rule into an error dialog, and a treasurer cannot tell a rule he broke from a
/// server that is down. The one closable month has to be the one that is
/// tappable, and the rest have to say why they are not.
///
/// The list is the REAL wire fixture, so this test and
/// supabase_contract_test.dart cannot drift into disagreeing about what the
/// server sends.

/// Pins a signed-in financeManager: the close-month button is behind
/// `role.atLeast(AppRole.financeManager)` and a viewer never sees it.
class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000a2',
      email: 'fm@fam.test',
      displayName: 'المدير المالي',
      role: AppRole.financeManager,
      status: AccountStatus.approved,
    ),
  );
}

const DashboardData _emptyDashboard = DashboardData(
  stats: DashboardStats(
    adeels: 0,
    active: 0,
    suspended: 0,
    deceased: 0,
    debt: '0.00',
    collected: '0.00',
    cash: '0.00',
    transfer: '0.00',
    indebtedAdeels: 0,
  ),
  topDebtors: <DebtorRow>[],
  closingPeriod: '2026-04',
  closingPeriodLabel: 'أبريل 2026',
);

List<ClosablePeriod> _fixturePeriods() =>
    (jsonDecode(
              File('test/fixtures/supabase/closable_periods.json')
                  .readAsStringSync(),
            )
            as List<dynamic>)
        .map(
          (dynamic e) =>
              ClosablePeriod.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();

void main() {
  final List<ClosablePeriod> periods = _fixturePeriods();

  Widget app() => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      dashboardProvider.overrideWith(
        (Ref ref) async => _emptyDashboard,
      ),
      closablePeriodsProvider.overrideWith(
        (Ref ref) async => periods,
      ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: const DashboardScreen(),
    ),
  );

  Future<void> openPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.event_available));
    await tester.pumpAndSettle();
  }

  testWidgets('exactly one month in the picker is enabled', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    final List<ListTile> tiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .toList();
    // Every month is listed — a treasurer checking whether March was closed has
    // to be able to SEE March, so blocked rows are greyed, never hidden.
    expect(tiles, hasLength(periods.length));
    expect(tiles.where((ListTile t) => t.onTap != null), hasLength(1));
  });

  testWidgets('tapping a blocked month does nothing at all', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    // يوليو is open but three months too early to close: يونيو، مايو، أبريل are
    // still open before it. Tapping it must not dismiss the picker — the failure
    // mode being guarded against is a dialog that closes and then reports RUL15.
    await tester.tap(find.text('يوليو 2026'));
    await tester.pumpAndSettle();
    expect(find.text('يوليو 2026'), findsOneWidget);

    // مارس is closed. Same outcome, different reason, and the badge says which.
    await tester.tap(find.text('مارس 2026'));
    await tester.pumpAndSettle();
    expect(find.text('مارس 2026'), findsOneWidget);
  });

  testWidgets('the earliest open month is the one that goes through', (
    WidgetTester tester,
  ) async {
    await openPicker(tester);

    // أبريل: the first month after مارس, which is the last closed one. Tapping
    // it closes the picker and raises the confirm dialog naming that same month
    // — proof the choice travelled, not just that something was dismissed.
    await tester.tap(find.text('أبريل 2026'));
    await tester.pumpAndSettle();
    expect(find.text('أبريل 2026'), findsNothing);
    expect(find.textContaining('أبريل 2026'), findsOneWidget);
  });
}
