import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
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
      adeelCode: 'A-01',
      deviceLocked: locked,
    ),
  );
}

AdeelDetail _detail() => AdeelDetail.fromJson(<String, dynamic>{
  'adeel': <String, dynamic>{
    'id': 1,
    'adeelCode': 'A-01',
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
  _moreSheetTests();

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
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
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

    expect(find.text('A-01'), findsOneWidget);
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
      'adeelCode': 'A-01',
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
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
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

/// The المزيد sheet: everything about him that is not a figure, plus the
/// association's treasury for transparency.
///
/// The security-relevant test is the last one. `v_cash_summary` is SECURITY
/// INVOKER and an عديل's RLS scopes cash_movements to his own receipts, so
/// pointing this sheet at the admin's treasury source would have shown him HIS
/// four figures under headings that say "the association's" — not a leak,
/// something worse: a wrong answer he had no way to doubt. It must come from
/// api_association_finance(), which is SECURITY DEFINER and aggregates only.
void _moreSheetTests() {
  final L l = LAr();

  Widget app({
    AssociationSettingsView? settings,
    List<Official>? officials,
    AssociationFinance? finance,
  }) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _Auth(false)),
      adeelDetailProvider(1).overrideWith((Ref ref) async => _detail()),
      statementProvider(1).overrideWith(
        (Ref ref) async => const Statement(
          movements: <StatementMovement>[],
          closingBalance: '20.00',
        ),
      ),
      settingsProvider.overrideWith(
        (Ref ref) async =>
            settings ??
            const AssociationSettingsView(
              associationName: 'جمعية العدايل',
              currency: 'د.ل',
              memberFee: '100.00',
              bankName: 'التجاري الوطني',
              bankAccountNo: '0021-000-1234',
              bankAccountName: 'جمعية العدايل',
            ),
      ),
      officialsProvider.overrideWith(
        (Ref ref) async =>
            officials ??
            const <Official>[
              Official(
                role: 'treasurer',
                name: 'المهدي عبدالله محمد',
                phone: '0925093709',
              ),
            ],
      ),
      associationFinanceProvider.overrideWith(
        (Ref ref) async =>
            finance ??
            // collected 700, disbursed 60, so the association HOLDS 640. The
            // three differ on purpose: a transparency panel that showed only
            // what came in would overstate the fund by every voucher written.
            const AssociationFinance(
              balance: '640.00',
              collected: '700.00',
              disbursed: '60.00',
              cash: '450.00',
              transfer: '250.00',
              issued: '5600.00',
              outstanding: '4900.00',
              members: 8,
              activeMembers: 8,
            ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const AdeelPortalScreen(),
    ),
  );

  Future<void> openSheet(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(LAr().navMore));
    await tester.pumpAndSettle();
  }

  testWidgets('المزيد opens, and the page itself carries no logout button', (
    WidgetTester tester,
  ) async {
    // Signing out moved INTO the sheet: it is the least used control on the
    // screen and it was holding the header's only action slot.
    //
    // Sized like the other sheet tests — the sheet is capped at 75% of the
    // viewport, and on the tester's default 800x600 the last item falls below
    // the fold and is simply never built.
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byTooltip(l.signOut), findsNothing);
    expect(find.byTooltip(l.navMore), findsOneWidget);

    await tester.tap(find.byTooltip(l.navMore));
    await tester.pumpAndSettle();
    expect(find.text(l.signOut), findsOneWidget);
  });

  /// Opens المزيد and then ONE of its four sections.
  ///
  /// The sheet used to be the destination; it is now a menu, and each section is
  /// a page of its own. Two taps rather than one, and the second is what these
  /// tests are actually about — «بخصوصية لكل جزء» means the bank account is not
  /// on screen while the officials are being read.
  Future<void> openSection(WidgetTester tester, Widget w, String title) async {
    await openSheet(tester, w);
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  testWidgets('it tells him where to send a transfer', (
    WidgetTester tester,
  ) async {
    // He is the man being asked to pay and the app never told him where. RLS
    // already allowed it — read_settings_adeel exists for this reason.
    await openSection(tester, app(), l.bankAccountSection);

    expect(find.text('التجاري الوطني'), findsOneWidget);
    expect(find.text('0021-000-1234'), findsOneWidget);
    // And nothing else is on the page with it.
    expect(find.text(l.navOfficials), findsNothing);
    expect(find.text(l.navCash), findsNothing);
  });

  testWidgets('and who to ring, by post', (WidgetTester tester) async {
    await openSection(tester, app(), l.navOfficials);

    expect(find.text(l.treasurerSection), findsOneWidget);
    expect(find.text('المهدي عبدالله محمد'), findsWidgets);
    expect(find.text('0925093709'), findsOneWidget);
    // The wire value must not reach the screen. It is ASCII, so the
    // Arabic-literal lint cannot see it.
    expect(find.text('treasurer'), findsNothing);
  });

  testWidgets('an unset bank account says so instead of showing blanks', (
    WidgetTester tester,
  ) async {
    await openSection(
      tester,
      app(
        settings: const AssociationSettingsView(
          associationName: 'جمعية العدايل',
          currency: 'د.ل',
          memberFee: '100.00',
          bankName: '',
          bankAccountNo: '',
          bankAccountName: '',
        ),
      ),
      l.bankAccountSection,
    );

    expect(find.text(l.bankAccountNotSetYet), findsOneWidget);
  });

  testWidgets('the treasury is the ASSOCIATION\'s figures, and says it is read-only', (
    WidgetTester tester,
  ) async {
    // The one that matters. His own balance is 20.00; the association's is
    // 700.00 with 4,900.00 outstanding. If this page ever showed his own
    // numbers — which is exactly what v_cash_summary would return for him,
    // because it is SECURITY INVOKER — the headings would be lying and nothing
    // on screen would betray it.
    await openSection(tester, app(), l.navCash);

    expect(find.text(formatMoney('640.00')), findsOneWidget);
    expect(find.text(formatMoney('60.00')), findsOneWidget);
    expect(find.text(formatMoney('450.00')), findsOneWidget);
    expect(find.text(formatMoney('4900.00')), findsOneWidget);

    // Read-only, said out loud: a member seeing the treasury for the first
    // time will look for something to do about it.
    expect(find.text(l.treasuryReadOnlyNote), findsOneWidget);

    // And nothing on it is an action.
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('the MENU itself carries no figures, only doors', (
    WidgetTester tester,
  ) async {
    // The change, stated as a test. Four unrelated answers in one scrolling
    // column is one long thing a reader scrolls past looking for the part he
    // came for — and the part he came for is different every time.
    await openSheet(tester, app());

    expect(find.text(l.myDetailsTitle), findsOneWidget);
    expect(find.text(l.bankAccountSection), findsOneWidget);
    expect(find.text(l.navOfficials), findsOneWidget);
    expect(find.text(l.navCash), findsOneWidget);

    // None of their contents.
    expect(find.text('التجاري الوطني'), findsNothing);
    expect(find.text('0925093709'), findsNothing);
    expect(find.text(formatMoney('640.00')), findsNothing);

    // Sign-out stays in the sheet: it belongs to no section and has nowhere
    // else to live. It is still the ONLY button there.
    final Iterable<Widget> buttons = tester.widgetList(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(buttons.length, 1);
  });
}
