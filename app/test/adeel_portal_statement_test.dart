import 'package:family_app/core/config/theme.dart';
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

/// The عديل portal's statement: paging and search.
///
/// Both behaviours fail SILENTLY if they are wrong. A search that matches
/// nothing looks exactly like an account with no such movement, and a pager
/// that reveals the wrong slice looks exactly like a shorter statement — so
/// neither is something a screenshot can confirm, which is what
/// adeel_portal_preview_test.dart is for.
///
/// The digit test is the one that matters most. `formatMoney` renders through
/// `ar_LY`, so 20.00 reaches the screen as ٢٠٫٠٠ while the row holds "20.00".
/// A reader types what is in front of them; a reader on a Latin keyboard types
/// 20. Both have to find the same rows, and nothing else in the app would
/// notice if one of them stopped working.

class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000b1',
      email: 'adeel@fam.test',
      displayName: 'عديل',
      role: AppRole.viewer,
      status: AccountStatus.approved,
      adeelId: 1,
      adeelCode: 'A-01',
    ),
  );
}

/// 25 movements, references REF-01 … REF-25, so "is row N on screen" is one
/// find.text away and never ambiguous.
///
/// `note` is deliberately EMPTY. _LedgerRow titles a row with its note and only
/// falls back to the reference when there is none — a real statement always
/// carries a note, so leaving it blank here is what makes the reference the
/// visible, unique handle these tests grab. It costs nothing: the note is one
/// more field in the same haystack, and the type/amount searches below cover
/// that path.
///
/// Alternating charge/payment with two distinct amounts, because a search for
/// an amount must return SOME rows and exclude others — a fixture where every
/// row matched would pass whatever the filter did.
///
/// Balances start at 1001 rather than counting up from 20 so that no running
/// balance accidentally contains "20.00" or "35". Without that the amount
/// searches would match rows through the balance column and the test would be
/// asserting something other than what it claims.
Statement _statement() {
  final List<StatementMovement> movements = <StatementMovement>[];
  for (int i = 1; i <= 25; i++) {
    final bool charge = i.isOdd;
    movements.add(
      StatementMovement(
        date: '2026-01-${i.toString().padLeft(2, '0')}',
        reference: 'REF-${i.toString().padLeft(2, '0')}',
        type: charge ? 'استحقاق' : 'دفعة',
        debit: charge ? '20.00' : null,
        credit: charge ? null : '35.00',
        balance: '${1000 + i}.00',
        note: '',
      ),
    );
  }
  return Statement(movements: movements, closingBalance: '1025.00');
}

AdeelDetail _detail() => AdeelDetail.fromJson(<String, dynamic>{
  'adeel': <String, dynamic>{
    'id': 1,
    'adeelCode': 'A-01',
    'fullName': 'إبراهيم العدولي',
    'phone': '0910000000',
    'notes': '',
    'registeredAt': '2026-01-01',
    'dob': '1980-01-01',
    'age': 46,
    'membershipStatus': 'نشط',
    'debt': '125.00',
    'paid': '0.00',
    'issued': '125.00',
    'monthlyExpected': '20.00',
  },
  'kpis': <String, dynamic>{
    'monthlyExpected': '20.00',
    'issued': '125.00',
    'debt': '125.00',
    'paid': '0.00',
    'openPeriods': 5,
  },
  'receivables': <dynamic>[],
  'payments': <dynamic>[],
});

void main() {
  final L l = LAr();

  Widget app() => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      adeelDetailProvider(1).overrideWith((Ref ref) async => _detail()),
      statementProvider(1).overrideWith((Ref ref) async => _statement()),
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

  /// The portal body is a ListView, so anything outside the viewport is never
  /// BUILT and find.text would report it missing for the wrong reason. A tall
  /// surface renders the whole page at once, which is what makes "not found"
  /// mean "filtered out".
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // The portal opens on المستحقات — "what do I owe" is why a member opens it,
    // and the ledger is the follow-up question behind a segment. Every test in
    // this file is about the ledger, so each one starts by asking for it. That
    // tap is also the only thing standing between these assertions and the
    // screen a member actually sees, so it is worth performing rather than
    // reaching past.
    await tester.tap(find.text(l.myStatementSection).last);
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pumpAndSettle();
  }

  testWidgets('the first page shows ten movements and no more', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.text('REF-01'), findsOneWidget);
    expect(find.text('REF-10'), findsOneWidget);
    // The eleventh exists in the statement and must not be on screen yet.
    expect(find.text('REF-11'), findsNothing);
    expect(find.text('REF-25'), findsNothing);
  });

  testWidgets('show-more reveals exactly one more page', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(l.statementShowMore(10)));
    await tester.pumpAndSettle();

    expect(find.text('REF-11'), findsOneWidget);
    expect(find.text('REF-20'), findsOneWidget);
    expect(find.text('REF-21'), findsNothing);
  });

  testWidgets('show-all reveals the rest', (WidgetTester tester) async {
    await pump(tester);

    await tester.tap(find.text(l.statementShowAll));
    await tester.pumpAndSettle();

    expect(find.text('REF-01'), findsOneWidget);
    expect(find.text('REF-25'), findsOneWidget);
    // Nothing left to reveal, so the buttons are gone.
    expect(find.text(l.statementShowAll), findsNothing);
  });

  testWidgets('search narrows to one movement by its reference', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await type(
      tester,
      'ref-17',
    ); // lowercase: also proves case-folding, and keeps
    // the field's own text from matching find.text('REF-17') a second time.

    expect(find.text('REF-17'), findsOneWidget);
    expect(find.text('REF-01'), findsNothing);
  });

  testWidgets('searching resets to the first page', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text(l.statementShowAll));
    await tester.pumpAndSettle();
    expect(find.text('REF-25'), findsOneWidget);

    // 13 payments+charges is more than a page, so the reset is observable:
    // without it the previously-revealed pages would still be showing.
    await type(tester, 'استحقاق');
    expect(find.text('REF-01'), findsOneWidget);
    expect(find.text('REF-25'), findsNothing);
  });

  testWidgets(
    'a Latin-typed amount finds rows rendered in Arabic-Indic digits',
    (WidgetTester tester) async {
      await pump(tester);

      // The charges are 20.00 and appear as ٢٠٫٠٠. Nothing on screen reads "20".
      await type(tester, '20.00');

      expect(find.text('REF-01'), findsOneWidget); // a charge
      expect(find.text('REF-02'), findsNothing); // a 35.00 payment
    },
  );

  testWidgets(
    'the same amount typed in Arabic-Indic digits finds the same rows',
    (WidgetTester tester) async {
      await pump(tester);
      await type(tester, '٢٠٫٠٠');

      expect(find.text('REF-01'), findsOneWidget);
      expect(find.text('REF-02'), findsNothing);
    },
  );

  testWidgets('his own name matches, spelled with or without the hamza', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    // The fixture holds إبراهيم; this types ابراهيم. The two differ only in a
    // hamza that most keyboards make awkward, and a reader searching for
    // himself must not have to know which one is stored.
    await type(tester, 'ابراهيم');
    expect(find.text('REF-01'), findsOneWidget);
  });

  testWidgets('every term must match, in any field and any order', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    // 'دفعة' is the type of the even rows; '35' is their credit. Together they
    // must still find them; the charges match neither.
    await type(tester, 'دفعة 35');
    expect(find.text('REF-02'), findsOneWidget);
    expect(find.text('REF-01'), findsNothing);
  });

  testWidgets('a query that matches nothing says so', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await type(tester, 'zzzzz');

    expect(find.text(l.noSearchResults), findsOneWidget);
    expect(find.text('REF-01'), findsNothing);
  });

  testWidgets('clearing the search restores the first page', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await type(
      tester,
      'ref-17',
    ); // lowercase: also proves case-folding, and keeps
    // the field's own text from matching find.text('REF-17') a second time.
    expect(find.text('REF-01'), findsNothing);

    await type(tester, '');
    expect(find.text('REF-01'), findsOneWidget);
    expect(find.text('REF-11'), findsNothing);
  });
}
