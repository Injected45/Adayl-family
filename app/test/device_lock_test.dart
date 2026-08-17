import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeel_portal_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// One عديل, one handset — the part of it the app is responsible for.
///
/// The RULE lives in `my_adeel_id()`, which returns NULL for a device that does
/// not match and therefore hands this screen an empty register, an empty ledger
/// and a zero balance. Nothing here enforces anything; what these pin is that
/// the member is TOLD, because the alternative — a portal that renders
/// perfectly and is simply empty — reads as a broken app rather than a rule the
/// association set, and he would ring about the wrong problem.
///
/// `deviceLocked` defaults to FALSE on purpose, so a build pointed at a
/// database that predates the rule behaves exactly as it did before instead of
/// locking every member out of a screen the server is willing to fill. The last
/// test is that default.

class _Auth extends AuthController {
  _Auth(this.locked);

  final bool locked;

  @override
  AuthState build() => AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000e1',
      email: 'adeel@fam.test',
      displayName: 'عديل',
      role: AppRole.viewer,
      status: AccountStatus.approved,
      adeelId: 1,
      adeelCode: 'A-0001',
      deviceLocked: locked,
    ),
  );
}

AdeelDetail _detail() => AdeelDetail.fromJson(<String, dynamic>{
  'adeel': <String, dynamic>{
    'id': 1,
    'adeelCode': 'A-0001',
    'fullName': 'المهدي العدولي',
    'phone': '0910000000',
    'notes': '',
    'registeredAt': '2026-01-01',
    'dob': '1980-01-01',
    'age': 46,
    'membershipStatus': 'نشط',
    'debt': '20.00',
    'paid': '0.00',
    'issued': '20.00',
    'monthlyExpected': '20.00',
  },
  'kpis': <String, dynamic>{
    'monthlyExpected': '20.00',
    'issued': '20.00',
    'debt': '20.00',
    'paid': '0.00',
    'openPeriods': 1,
  },
  'receivables': <dynamic>[],
  'payments': <dynamic>[],
});

void main() {
  _walletTests();

  final L l = LAr();

  Widget app({required bool locked}) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _Auth(locked)),
      adeelDetailProvider(1).overrideWith((Ref ref) async => _detail()),
      statementProvider(1).overrideWith(
        (Ref ref) async => const Statement(
          movements: <StatementMovement>[],
          closingBalance: '20.00',
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: const AdeelPortalScreen(),
    ),
  );

  testWidgets('the wrong handset is told why, not shown an empty page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(locked: true));
    await tester.pumpAndSettle();

    expect(find.text(l.deviceLockedTitle), findsOneWidget);
    expect(find.text(l.deviceLockedBody), findsOneWidget);

    // Not a blank statement wearing a message: the portal's own furniture must
    // be gone, or he will scroll past the explanation into a page of zeroes.
    expect(find.text(l.myBalanceNow), findsNothing);
    expect(find.text(l.myDetailsTitle), findsNothing);
  });

  testWidgets('he can still sign out of the wrong handset', (
    WidgetTester tester,
  ) async {
    // The only two things he can do are ring the association and get off this
    // screen. Removing the sign-out button would strand a man holding a phone
    // that is not his.
    await tester.pumpWidget(app(locked: true));
    await tester.pumpAndSettle();

    expect(find.text(l.signOut), findsOneWidget);
  });

  testWidgets('his code is quoted, so the association can find him', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(locked: true));
    await tester.pumpAndSettle();

    expect(find.text('A-0001'), findsOneWidget);
  });

  testWidgets('the right handset sees the portal exactly as before', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(locked: false));
    await tester.pumpAndSettle();

    expect(find.text(l.deviceLockedTitle), findsNothing);
    expect(find.text(l.myBalanceNow), findsOneWidget);
    expect(find.text('المهدي العدولي'), findsOneWidget);
  });

  test('a database without the flag does not lock anyone out', () {
    // api_me() on a project that has not had the patch applied returns no
    // `deviceLocked` key at all. Reading a missing key as `true` would black
    // out every portal in the association the moment the app updated ahead of
    // the schema.
    final AppUser parsed = AppUser.fromJson(<String, dynamic>{
      'id': '00000000-0000-0000-0000-0000000000e1',
      'email': 'adeel@fam.test',
      'displayName': 'عديل',
      'role': 'viewer',
      'status': 'approved',
      'adeelId': 1,
    });
    expect(parsed.deviceLocked, isFalse);
  });
}

/// The wallet, as the portal states it.
///
/// The association opened prepayment: a member may hand over a year at once and
/// the surplus sits against his name. That gives the hero a THIRD state, and
/// the sign of one server-computed figure is what picks it. These pin the two
/// things a member could be misled by — a credit shown as a debt, and a minus
/// sign left on a figure that is his.
void _walletTests() {
  final L l = LAr();

  AdeelDetail detail({
    required String debt,
    required String credit,
    required String netBalance,
  }) => AdeelDetail.fromJson(<String, dynamic>{
    'adeel': <String, dynamic>{
      'id': 1,
      'adeelCode': 'A-0001',
      'fullName': 'المهدي العدولي',
      'phone': '0910000000',
      'notes': '',
      'registeredAt': '2026-01-01',
      'dob': '1980-01-01',
      'age': 46,
      'membershipStatus': 'نشط',
      'debt': debt,
      'paid': '0.00',
      'issued': '20.00',
      'monthlyExpected': '20.00',
    },
    'kpis': <String, dynamic>{
      'monthlyExpected': '20.00',
      'issued': '20.00',
      'debt': debt,
      'paid': '0.00',
      'credit': credit,
      'netBalance': netBalance,
      'openPeriods': 0,
    },
    'receivables': <dynamic>[],
    'payments': <dynamic>[],
  });

  Widget app(AdeelDetail d) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _Auth(false)),
      adeelDetailProvider(1).overrideWith((Ref ref) async => d),
      statementProvider(1).overrideWith(
        (Ref ref) async => const Statement(
          movements: <StatementMovement>[],
          closingBalance: '0.00',
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: const AdeelPortalScreen(),
    ),
  );

  testWidgets('credit reads as HIS money, in green, with no minus sign', (
    WidgetTester tester,
  ) async {
    // netBalance is −30: the server's way of saying the association holds 30
    // for him. Printing that verbatim would put "‑30.00" under a heading about
    // his balance, which is a puzzle. The figure shown is the credit itself.
    await tester.pumpWidget(
      app(detail(debt: '0.00', credit: '30.00', netBalance: '-30.00')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l.myWalletTitle), findsOneWidget);
    expect(find.text(l.myWalletBody), findsOneWidget);
    expect(find.text(formatMoney('30.00')), findsWidgets);
    expect(find.text(formatMoney('-30.00')), findsNothing);

    // Green, and the LABEL changed too — colour is never the only signal.
    final Text figure = tester.widget<Text>(
      find.text(formatMoney('30.00')).first,
    );
    expect(figure.style?.color, AppColors.success);
  });

  testWidgets('a debt still reads red, and says how many months', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      app(detail(debt: '40.00', credit: '0.00', netBalance: '40.00')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l.myBalanceNow), findsOneWidget);
    expect(find.text(l.myWalletTitle), findsNothing);
    final Text figure = tester.widget<Text>(
      find.text(formatMoney('40.00')).first,
    );
    expect(figure.style?.color, AppColors.danger);
  });

  testWidgets('exactly zero is settled up, not a wallet of nothing', (
    WidgetTester tester,
  ) async {
    // The third state is its own sentence. "You have 0.00 in credit" answers
    // nothing; "settled up" is the news he opened the app for.
    await tester.pumpWidget(
      app(detail(debt: '0.00', credit: '0.00', netBalance: '0.00')),
    );
    await tester.pumpAndSettle();

    expect(find.text(l.settledUpTitle), findsWidgets);
    expect(find.text(l.myWalletBody), findsNothing);
  });

  test('a database with no wallet yet reports the debt, not zero', () {
    // api_adeel_detail on an unpatched project sends neither key. Defaulting
    // netBalance to 0 would show every member as settled up while he owed.
    final AdeelDetail old = AdeelDetail.fromJson(<String, dynamic>{
      'adeel': <String, dynamic>{'id': 1, 'fullName': 'x', 'debt': '40.00'},
      'kpis': <String, dynamic>{'debt': '40.00', 'openPeriods': 2},
      'receivables': <dynamic>[],
    });
    expect(old.credit, '0.00');
    expect(old.netBalance, '40.00');
    expect(old.owes, isTrue);
    expect(old.inCredit, isFalse);
  });
}
