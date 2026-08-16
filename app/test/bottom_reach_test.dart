import 'package:family_app/core/config/glass.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/core/widgets/app_scaffold.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeels_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nothing on a list may end up under the chrome that floats over it.
///
/// The bottom navigation is a pill that content scrolls BEHIND, which is what
/// makes the frost read as glass, and the price of that is that the last row of
/// every list would be unreachable unless something reserves the space. That
/// part was already handled: AppScaffold publishes the pill's height as
/// `MediaQuery.padding.bottom` and every scroll view adds it.
///
/// The FAB was not. `endFloat` puts it ON TOP of the body, 16dp above the pill,
/// so on the register and the collections list the last card cleared the pill
/// by 24dp and then had its NAME ROW — the one thing you look at — covered by
/// the button. It only shows once the list is long enough to scroll, which is
/// why it survived: a register with four عدايل looks perfect.
///
/// These tests scroll to the true bottom and compare rectangles, because that
/// is the only way to catch it. Nothing throws, nothing overflows, and no
/// golden changes — the row is laid out correctly and painted underneath.

class _StubAuth extends AuthController {
  _StubAuth(this.role);

  final AppRole role;

  @override
  AuthState build() => AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000c1',
      email: 'admin@fam.test',
      displayName: 'المهدي',
      role: role,
      status: AccountStatus.approved,
    ),
  );
}

AdeelListItem _adeel(int n) => AdeelListItem(
  id: n,
  adeelCode: 'A-${n.toString().padLeft(4, '0')}',
  fullName: 'العديل رقم $n',
  phone: '091000$n',
  age: 40,
  membershipStatus: 'نشط',
  debt: '20.00',
  issued: '140.00',
  monthlyExpected: '20.00',
);

void main() {
  // A Galaxy Note 10 in logical pixels. The register has to work on the phone
  // the association actually carries, not on the tester's default 800x600.
  const Size note10 = Size(360, 760);

  Widget host(Widget child, {AppRole role = AppRole.admin}) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(role)),
      adeelsProvider('').overrideWith(
        (Ref ref) async =>
            <AdeelListItem>[for (int i = 1; i <= 30; i++) _adeel(i)],
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: child,
    ),
  );

  Future<void> sized(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = note10;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(child));
    await tester.pumpAndSettle();
  }

  testWidgets('the last عديل in the register is not under the add button', (
    WidgetTester tester,
  ) async {
    await sized(tester, const AdeelsScreen());

    // To the true end of the list. A single large drag is enough — the list
    // clamps at its maximum extent — and settling lets the ballistic scroll
    // finish, which matters because the overlap is only visible at rest.
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    final Finder lastName = find.text('العديل رقم 30');
    expect(lastName, findsOneWidget, reason: 'the list did not reach its end');

    final Rect fab = tester.getRect(find.byType(FloatingActionButton));
    final Rect name = tester.getRect(lastName);

    // The card is full width, so "does the FAB overlap it" is purely vertical.
    expect(
      name.bottom,
      lessThanOrEqualTo(fab.top),
      reason:
          'the last عديل sits under the add button — '
          'AppScaffold is not reserving the FAB band',
    );
  });

  testWidgets('the last عديل clears the navigation pill as well', (
    WidgetTester tester,
  ) async {
    // The FAB check above would still pass if the pill inset were dropped and
    // the FAB one doubled, so the pill is asserted on its own terms: the whole
    // card, not just its name, ends above where the pill starts.
    await sized(tester, const AdeelsScreen());
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    final Rect card = tester.getRect(
      find.ancestor(of: find.text('العديل رقم 30'), matching: find.byType(Card)),
    );
    final Rect fab = tester.getRect(find.byType(FloatingActionButton));

    expect(card.bottom, lessThanOrEqualTo(fab.top));
    expect(card.bottom, lessThan(note10.height));
  });

  testWidgets('a screen with a FAB reserves more than one without', (
    WidgetTester tester,
  ) async {
    // The contract, stated once: whatever floats over the body is added up by
    // AppScaffold and published as a single number, so a screen never has to
    // know which pieces of chrome it happens to have. A screen reading
    // bottomInset() gets the pill either way and the button only when there is
    // one.
    late double withFab;
    late double withoutFab;

    Widget probe(void Function(double) capture) => Builder(
      builder: (BuildContext context) {
        capture(bottomInset(context));
        return const SizedBox.expand();
      },
    );

    await sized(
      tester,
      AppScaffold(
        title: 'x',
        currentRoute: AppRoutes.adeels,
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
        body: (BuildContext context) => probe((double v) => withFab = v),
      ),
    );

    await sized(
      tester,
      AppScaffold(
        title: 'x',
        currentRoute: AppRoutes.adeels,
        body: (BuildContext context) => probe((double v) => withoutFab = v),
      ),
    );

    expect(withoutFab, greaterThan(0), reason: 'the pill must still be paid for');
    // 56 of button plus the 16 Scaffold keeps between it and the pill.
    expect(withFab - withoutFab, 72);
  });
}
