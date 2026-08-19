import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeels_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// إجمالي المستحق, at the head of the register.
///
/// The list answers "who owes what" one man at a time. The association asked
/// for the other question on the same page: how much is out there altogether.
///
/// ⚠ IT IS THE SERVER'S FIGURE — `v_cash_summary.outstanding`, the same one the
///   treasury screen puts on its balance bar, so the two pages cannot disagree
///   about what the association is owed. Summing the visible rows in Dart would
///   put the receivables on binary floating point and would quietly mean
///   something else the moment the list were paged or filtered.
///
/// Which is why it HIDES while a search is active: it is the whole register's
/// total, and a figure above three filtered rows that does not add up to them is
/// the one disagreement a register must not display.

class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000f1',
      email: 'staff@fam.test',
      displayName: 'المهدي',
      role: AppRole.admin,
      status: AccountStatus.approved,
    ),
  );
}

AdeelListItem _adeel(int id, String name, String debt) =>
    AdeelListItem.fromJson(<String, dynamic>{
      'id': id,
      'adeelCode': 'A-0$id',
      'fullName': name,
      'phone': '',
      'membershipStatus': 'نشط',
      'debt': debt,
      'paid': '0.00',
      'issued': debt,
      'monthlyExpected': '20.00',
    });

void main() {
  final L l = LAr();

  Widget host({String query = ''}) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      adeelSearchProvider.overrideWith((Ref ref) => query),
      adeelsProvider(query).overrideWith(
        (Ref ref) async => <AdeelListItem>[
          _adeel(1, 'المهدي العدولي', '100.00'),
          _adeel(2, 'أيمن صالح', '60.00'),
        ],
      ),
      cashSummaryProvider.overrideWith(
        (Ref ref) async => const CashSummaryView(
          total: '700.00',
          cash: '450.00',
          transfer: '250.00',
          today: '0.00',
          month: '700.00',
          year: '700.00',
          // Deliberately NOT 160.00 — the sum of the two rows below. The bar
          // must show what the SERVER says the association is owed, across the
          // whole register, not what happens to be on screen.
          outstanding: '4900.00',
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const AdeelsScreen(),
    ),
  );

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  testWidgets('the register heads with إجمالي المستحق', (
    WidgetTester tester,
  ) async {
    await pump(tester, host());

    expect(find.text(l.totalOutstanding), findsOneWidget);
    expect(find.text(formatMoney('4900.00')), findsOneWidget);
    // The rows are still there under it.
    expect(find.text('المهدي العدولي'), findsOneWidget);
  });

  testWidgets('...the SERVER\'s figure, not a sum of the rows', (
    WidgetTester tester,
  ) async {
    // The two visible debts add to 160. The bar says 4,900, because that is
    // what the association is owed altogether — and because nothing in this app
    // adds money in Dart.
    await pump(tester, host());

    expect(find.text(formatMoney('4900.00')), findsOneWidget);
    expect(find.text(formatMoney('160.00')), findsNothing);
  });

  testWidgets('and the register carries no search box at all', (
    WidgetTester tester,
  ) async {
    // The bar used to HIDE while a search was active: a whole-register total
    // above three filtered rows is a figure that does not add up to what is
    // under it, which is the one disagreement a register must not display.
    //
    // The association removed the search, so there is nothing to filter and the
    // figure always describes the list beneath it. This is the assertion that
    // keeps the two facts tied together — put the box back without restoring
    // the hide, and this fails.
    await pump(tester, host());

    expect(find.byType(TextField), findsNothing);
    expect(find.text(l.totalOutstanding), findsOneWidget);
    expect(find.text(formatMoney('4900.00')), findsOneWidget);
  });
}
