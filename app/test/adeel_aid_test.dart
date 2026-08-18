import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/adeel_aid_screen.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ما صُرف له — the aid ledger.
///
/// ⚠ THE RULE THIS SCREEN EXISTS TO KEEP: الجمعية خيرية. Aid paid to a member is
/// NOT deducted from his subscription. His statement stays a record of dues
/// charged and dues paid, and this page is a separate answer to a separate
/// question.
///
/// The database makes that structural — a voucher writes no receivable, no
/// payment and no allocation, and `api_adeel_statement` merges exactly those two
/// tables — and `supabase/tests/67_disbursement.sql` proves it there, as staff
/// and as the member himself. What CANNOT be proved there is the SCREEN: a
/// layout that puts «ما صُرف له» beside «ما عليه» invites the reader to subtract
/// even when the database never does.
///
/// So what is pinned here is the presentation: the page states the rule, the
/// running total comes off the server rather than being accumulated in Dart, a
/// reversed line stays visible without moving the balance, and the search box
/// filters rows without touching a figure.

class _StubAuth extends AuthController {
  _StubAuth(this.role);

  final AppRole role;

  @override
  AuthState build() => AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000f1',
      email: 'staff@fam.test',
      displayName: 'المهدي',
      role: role,
      status: AccountStatus.approved,
    ),
  );
}

AidLedgerEntry _entry({
  required int id,
  required String amount,
  required String runningTotal,
  String category = 'مولود',
  String status = 'معتمد',
  String spentAt = '2026-02-10T09:00:00Z',
  String note = '',
}) => AidLedgerEntry(
  runningTotal: runningTotal,
  voucher: DisbursementView(
    id: id,
    voucherNo: 'EXP-${id.toString().padLeft(6, '0')}',
    amount: amount,
    kind: 'لمشترك',
    category: category,
    payeeName: 'محمد العدولي',
    payeeAdeelId: 1,
    payeeCode: 'A-0001',
    method: 'نقداً',
    status: status,
    spentAt: spentAt,
    note: note,
  ),
);

/// The association's own example: 100 for a birth, then 500 for a wedding
/// months later, which must read 100 then 600.
List<AidLedgerEntry> _hundredThenFiveHundred() => <AidLedgerEntry>[
  _entry(
    id: 1,
    amount: '100.00',
    runningTotal: '100.00',
    category: 'مولود',
    spentAt: '2026-02-10T09:00:00Z',
    note: 'ولادة',
  ),
  _entry(
    id: 2,
    amount: '500.00',
    runningTotal: '600.00',
    category: 'فرح',
    spentAt: '2026-06-20T09:00:00Z',
    note: 'زواج',
  ),
];

AdeelAid _aid({
  String total = '600.00',
  int count = 2,
  String firstAt = '2026-02-10',
  String lastAt = '2026-06-20',
  List<ExpenseByCategory>? byCategory,
  List<AidByYear>? byYear,
  List<AidLedgerEntry>? ledger,
}) => AdeelAid(
  adeelId: 1,
  adeelCode: 'A-0001',
  adeelName: 'محمد العدولي',
  total: total,
  count: count,
  firstAt: firstAt,
  lastAt: lastAt,
  byCategory:
      byCategory ??
      const <ExpenseByCategory>[
        ExpenseByCategory(category: 'فرح', total: '500.00', count: 1),
        ExpenseByCategory(category: 'مولود', total: '100.00', count: 1),
      ],
  byYear:
      byYear ??
      const <AidByYear>[AidByYear(year: '2026', total: '600.00', count: 2)],
  ledger: ledger ?? _hundredThenFiveHundred(),
);

void main() {
  final L l = LAr();

  Widget host(AdeelAid aid, {bool mine = false}) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
      adeelAidProvider(1).overrideWith((Ref ref) async => aid),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: AdeelAidScreen(adeelId: 1, mine: mine),
    ),
  );

  Future<void> open(
    WidgetTester tester,
    AdeelAid aid, {
    bool mine = false,
  }) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(aid, mine: mine));
    await tester.pumpAndSettle();
  }

  // ── The model ─────────────────────────────────────────────────────────────

  test('the aid page parses the shape api_adeel_aid actually sends', () {
    // Keys copied from the function body, not invented here. Rename one in SQL
    // and this stops parsing before the app ever runs. `runningTotal` rides on
    // the same object as the voucher — the SQL does `to_jsonb(v) || {...}` — so
    // one row parses into both halves of AidLedgerEntry.
    final AdeelAid aid = AdeelAid.fromJson(<String, dynamic>{
      'adeelId': 1,
      'adeelCode': 'A-0001',
      'adeelName': 'محمد العدولي',
      'total': '600.00',
      'count': 2,
      'firstAt': '2026-02-10',
      'lastAt': '2026-06-20',
      'byCategory': <dynamic>[
        <String, dynamic>{'category': 'فرح', 'total': '500.00', 'count': 1},
      ],
      'byYear': <dynamic>[
        <String, dynamic>{'year': '2026', 'total': '600.00', 'count': 2},
      ],
      'vouchers': <dynamic>[
        <String, dynamic>{
          'id': 7,
          'voucherNo': 'EXP-000007',
          'amount': '100.00',
          'kind': 'لمشترك',
          'category': 'مولود',
          'payeeAdeelId': 1,
          'payeeName': 'محمد العدولي',
          'payeeCode': 'A-0001',
          'method': 'نقداً',
          'reference': '',
          'bankName': '',
          'bankAccountNo': '',
          'bankAccountName': '',
          'handedBy': 'أمين الصندوق',
          'note': 'ولادة',
          'status': 'معتمد',
          'spentAt': '2026-02-10T09:00:00Z',
          'runningTotal': '100.00',
        },
      ],
    });

    expect(aid.total, '600.00');
    expect(aid.count, 2);
    expect(aid.byCategory.single.category, 'فرح');
    expect(aid.byYear.single.year, '2026');
    expect(aid.ledger.single.voucher.voucherNo, 'EXP-000007');
    expect(aid.ledger.single.runningTotal, '100.00');
    // Money is the exact decimal STRING the server sent, never a double. It is
    // asserted rather than assumed because a `num` here would round the
    // association's charity on its way to a screen.
    expect(aid.total, isA<String>());
    expect(aid.ledger.single.runningTotal, isA<String>());
  });

  test('a member who has received nothing is a clean zero, not a blank', () {
    final AdeelAid none = AdeelAid.fromJson(<String, dynamic>{
      'adeelId': 4,
      'adeelCode': 'A-0004',
      'adeelName': 'علي العدولي',
      'total': '0.00',
      'count': 0,
      // firstAt/lastAt are NULL for a man with no vouchers. Empty string, not
      // the literal "null", or the screen would print it.
      'firstAt': null,
      'lastAt': null,
      'byCategory': <dynamic>[],
      'byYear': <dynamic>[],
      'vouchers': <dynamic>[],
    });

    expect(none.isEmpty, isTrue);
    expect(none.total, '0.00');
    expect(none.firstAt, '');
    expect(none.ledger, isEmpty);
  });

  test('the search haystack reaches the note, not just the heading', () {
    final AidLedgerEntry e = _entry(
      id: 1,
      amount: '100.00',
      runningTotal: '100.00',
      category: 'مولود',
      note: 'ولادة ابنه',
    );
    expect(e.haystack, contains('مولود'));
    expect(e.haystack, contains('ولادة'));
    expect(e.haystack, contains('exp-000001'));
  });

  // ── The screen ────────────────────────────────────────────────────────────

  testWidgets('the page says aid is NOT deducted from his subscription', (
    WidgetTester tester,
  ) async {
    // The whole reason this is a separate screen. Every other money surface in
    // the app shows a figure that nets against another figure, and a reader
    // arriving with that habit will subtract this total from his debt unless
    // told plainly that the association does not.
    await open(tester, _aid());

    expect(find.text(l.aidNotDeductedNote), findsOneWidget);
    // And the other half of the rule: a collective voucher belongs to nobody,
    // so its absence here is deliberate rather than an omission.
    expect(find.text(l.aidCollectiveNote), findsOneWidget);
  });

  testWidgets('100 then 500 reads 100 then 600', (WidgetTester tester) async {
    // The association's own example, and the reason the ledger exists. Each
    // line carries the total SO FAR, so the answer to "how much has he had from
    // us" is read off the page rather than added up by whoever is looking.
    await open(tester, _aid());

    expect(find.text(l.aidColRunning), findsOneWidget);
    expect(find.text(formatMoney('100.00')), findsWidgets);
    // 600 appears twice: on the last ledger line and in the closing total.
    expect(find.text(formatMoney('600.00')), findsWidgets);
    expect(find.text(l.aidGrandTotal), findsWidgets);
  });

  testWidgets('the running total is the SERVER\'s, never re-added here', (
    WidgetTester tester,
  ) async {
    // The figures deliberately disagree with naive arithmetic: the amounts sum
    // to 1000 while the server says the running total is 600, because it
    // excluded a reversed voucher. Anything that accumulated the column in Dart
    // would print 1000 — which is exactly the class of bug the money-as-text
    // rule exists to prevent.
    await open(
      tester,
      _aid(
        ledger: <AidLedgerEntry>[
          _entry(id: 1, amount: '100.00', runningTotal: '100.00'),
          _entry(
            id: 2,
            amount: '400.00',
            runningTotal: '100.00',
            status: 'ملغي',
            category: 'عزاء',
          ),
          _entry(
            id: 3,
            amount: '500.00',
            runningTotal: '600.00',
            category: 'فرح',
          ),
        ],
      ),
    );

    expect(find.text(formatMoney('600.00')), findsWidgets);
    expect(find.text(formatMoney('1000.00')), findsNothing);
  });

  testWidgets('a reversed line stays listed and moves nothing', (
    WidgetTester tester,
  ) async {
    // Rule 9, outgoing, on the recipient's page: history is not an
    // embarrassment. Its amount is struck through; its running total is NOT,
    // because the balance at that point in the ledger is a real figure — it is
    // simply unchanged from the line above.
    await open(
      tester,
      _aid(
        ledger: <AidLedgerEntry>[
          _entry(id: 1, amount: '100.00', runningTotal: '100.00'),
          _entry(
            id: 2,
            amount: '400.00',
            runningTotal: '100.00',
            status: 'ملغي',
            category: 'عزاء',
          ),
        ],
        total: '100.00',
        count: 1,
      ),
    );

    final Text struckAmount = tester.widget<Text>(
      find.text(formatMoney('400.00')),
    );
    expect(struckAmount.style?.decoration, TextDecoration.lineThrough);

    // ...and NOTHING reading 100.00 is struck through. The reversal struck the
    // AMOUNT; the balance at that point in the ledger is a real figure that
    // simply did not move, and striking it would say the opposite. Asserted
    // over every occurrence rather than by counting them, so the check does not
    // break the next time a panel repeats the same number.
    final Iterable<Text> hundreds = tester.widgetList<Text>(
      find.text(formatMoney('100.00')),
    );
    expect(hundreds, isNotEmpty);
    for (final Text t in hundreds) {
      expect(t.style?.decoration, isNot(TextDecoration.lineThrough));
    }
  });

  testWidgets('the search box filters rows and says how many are shown', (
    WidgetTester tester,
  ) async {
    await open(tester, _aid());
    expect(find.text('مولود'), findsWidgets);
    expect(find.text('فرح'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'زواج');
    await tester.pumpAndSettle();

    // The note matched, so the wedding line survives and the birth is hidden.
    expect(find.text('EXP-000002 • زواج'), findsOneWidget);
    expect(find.textContaining('ولادة'), findsNothing);
    // And the reader is told the table is narrowed — without it the running
    // total, which still belongs to the WHOLE history, looks like it skipped.
    expect(find.text(l.aidShowing(1, 2)), findsOneWidget);
  });

  testWidgets('a search that matches nothing says so', (
    WidgetTester tester,
  ) async {
    await open(tester, _aid());
    await tester.enterText(find.byType(TextField), 'لا يوجد');
    await tester.pumpAndSettle();

    expect(find.text(l.aidNoMatch), findsOneWidget);
    // The rule still shows above it: an empty result is not an empty page.
    expect(find.text(l.aidNotDeductedNote), findsOneWidget);
  });

  testWidgets('the member reads it in his own voice', (
    WidgetTester tester,
  ) async {
    await open(tester, _aid(), mine: true);
    expect(find.text(l.myAidTitle), findsOneWidget);
    expect(find.text(l.aidTitle), findsNothing);
    // His own page does not repeat his name back at him — he knows who he is,
    // and the header is where the staff screen puts whose record this is.
    expect(find.text('محمد العدولي'), findsNothing);
  });

  testWidgets('one year of aid gets no by-year panel', (
    WidgetTester tester,
  ) async {
    // A single-row "by year" restates the headline and says nothing. It earns
    // its place only once there are years to compare.
    await open(tester, _aid());
    expect(find.text(l.aidByYear), findsNothing);
    // The panel that IS expected on the same page, so "found nothing" cannot be
    // "rendered nothing".
    expect(find.text(l.aidByCategory), findsOneWidget);
  });

  testWidgets('a member given nothing sees a sentence, not an empty page', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      _aid(
        total: '0.00',
        count: 0,
        firstAt: '',
        lastAt: '',
        byCategory: const <ExpenseByCategory>[],
        byYear: const <AidByYear>[],
        ledger: <AidLedgerEntry>[],
      ),
    );

    expect(find.text(l.noAid), findsOneWidget);
    // The rule still shows: "nothing yet" is exactly when a reader wonders
    // whether aid would have come off his dues.
    expect(find.text(l.aidNotDeductedNote), findsOneWidget);
  });
}
