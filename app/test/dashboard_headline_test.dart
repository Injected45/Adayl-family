import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/oversight/domain/models.dart';
import 'package:family_app/features/oversight/presentation/dashboard_screen.dart';
import 'package:family_app/features/oversight/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The home screen leads with ONE figure.
///
/// It opened on four tiles of equal weight: how many عدايل, how many are NOT
/// billed, what is owed, what has been collected. Four figures presented as
/// equals are four questions asked at once, and on a phone they pushed the
/// debtor list — the part of the page that names someone to act on — below the
/// fold.
///
/// What the association asked for: إجمالي المحصل across the width, and a tap
/// gives عدد المشتركين and المديونية. The distinction this file protects is
/// between MOVED and LOST — those two outcomes look identical on the page and
/// completely different a month later, when a figure someone relied on is
/// simply not there any more.
///
/// The «غير المحاسَبين / متوفى» tile is the one exception: it was deleted
/// outright at the association's request, so the test asserts it is nowhere —
/// including inside the sheet.

class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000f1',
      email: 'admin@fam.test',
      displayName: 'المهدي',
      role: AppRole.admin,
      status: AccountStatus.approved,
    ),
  );
}

/// Every figure distinct, so a widget found by text can only have come from the
/// row that is supposed to carry it.
const DashboardStats _stats = DashboardStats(
  adeels: 42,
  active: 37,
  suspended: 3,
  deceased: 2,
  debt: '4900.00',
  collected: '8100.00',
  cash: '5100.00',
  transfer: '3000.00',
  indebtedAdeels: 11,
);

void main() {
  final L l = LAr();

  Widget host() => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      dashboardProvider.overrideWith(
        (Ref ref) async => const DashboardData(
          stats: _stats,
          topDebtors: <DebtorRow>[
            DebtorRow(
              adeelId: 7,
              adeelCode: 'A-07',
              adeelName: 'عبدالله محمد',
              debt: '600.00',
            ),
          ],
          closingPeriod: '',
          closingPeriodLabel: '',
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const DashboardScreen(),
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  testWidgets('the page leads with إجمالي المحصل and nothing beside it', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.text(l.statTotalCollected), findsOneWidget);
    expect(find.text(formatMoney('8100.00')), findsOneWidget);

    // The workings are NOT on the page any more.
    expect(find.text(l.statAdeels), findsNothing);
    expect(find.text(l.statTotalDebt), findsNothing);
    expect(find.text('42'), findsNothing);

    // The debtor list — the reason to open this page after reading the figure —
    // is on it.
    expect(find.text('عبدالله محمد'), findsOneWidget);
  });

  testWidgets('...and a tap gives عدد المشتركين and قيمة المديونية', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(l.statTotalCollected));
    await tester.pumpAndSettle();

    expect(find.text(l.statAdeels), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text(l.subActive(37)), findsOneWidget);

    expect(find.text(l.statTotalDebt), findsOneWidget);
    expect(find.text(formatMoney('4900.00')), findsOneWidget);
    expect(find.text(l.subIndebtedAdeels(11)), findsOneWidget);
  });

  testWidgets('the split between cash and transfer survives on the bar', (
    WidgetTester tester,
  ) async {
    // Not in the sheet: it is the one part of the workings that changes how the
    // headline is read — money in hand versus money in a bank account — so it
    // stays where the headline is.
    await pump(tester);

    expect(
      find.text(
        l.subCashTransfer(formatMoney('5100.00'), formatMoney('3000.00')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('«غير المحاسَبين / متوفى» is gone from the page AND the sheet', (
    WidgetTester tester,
  ) async {
    // Deleted at the association's request, not relocated. Its ARB keys went
    // with it, so it can only be named literally here — which is the point: if
    // anyone reinstates the strings, this is what refuses them.
    await pump(tester);
    await tester.tap(find.text(l.statTotalCollected));
    await tester.pumpAndSettle();

    expect(find.text('غير المحاسَبين'), findsNothing);
    expect(find.text('2 متوفى'), findsNothing);
    // 3 موقوف + 2 متوفى — the figure the deleted tile carried.
    expect(find.text('5'), findsNothing);
  });
}
