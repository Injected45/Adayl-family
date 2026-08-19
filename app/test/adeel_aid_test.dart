import 'package:family_app/core/config/glass.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/widgets/app_background.dart';
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
/// So what is pinned here is the presentation: the running total comes off the
/// server rather than being accumulated in Dart, a reversed line stays visible
/// without moving the balance, the search box filters rows without touching a
/// figure, and the page opens on figures rather than on an explanation.

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
  /// Defaulted EMPTY, because that is what most vouchers carry. The prune test
  /// sets it: «المُسلِّم» renders only when recorded, so an assertion that it is
  /// absent proves nothing against a fixture that never had one.
  String handedBy = '',
}) => AidLedgerEntry(
  runningTotal: runningTotal,
  voucher: DisbursementView(
    id: id,
    voucherNo: 'EXP-${id.toString().padLeft(2, '0')}',
    amount: amount,
    kind: 'لمشترك',
    category: category,
    payeeName: 'محمد العدولي',
    payeeAdeelId: 1,
    payeeCode: 'A-01',
    method: 'نقداً',
    status: status,
    spentAt: spentAt,
    note: note,
    handedBy: handedBy,
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


/// Three births, which is the shape the association described: one heading, one
/// figure, and the names only a note can carry.
List<AidLedgerEntry> _threeBirths() => <AidLedgerEntry>[
  _entry(
    id: 1,
    amount: '100.00',
    runningTotal: '100.00',
    category: 'مولود',
    spentAt: '2026-02-10T09:00:00Z',
    note: 'حور',
  ),
  _entry(
    id: 2,
    amount: '150.00',
    runningTotal: '250.00',
    category: 'مولود',
    spentAt: '2026-04-01T09:00:00Z',
    note: 'سند',
  ),
  _entry(
    id: 3,
    amount: '200.00',
    runningTotal: '450.00',
    category: 'مولود',
    spentAt: '2026-07-05T09:00:00Z',
    note: 'ريم',
  ),
];

/// Two headings, so the panel renders at all — it is hidden when there is only
/// one, because a single-row breakdown restates the headline.
List<ExpenseByCategory> _birthsOnly() => const <ExpenseByCategory>[
  ExpenseByCategory(category: 'مولود', total: '450.00', count: 3),
  ExpenseByCategory(category: 'فرح', total: '500.00', count: 1),
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
  adeelCode: 'A-01',
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
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
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
      'adeelCode': 'A-01',
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
          'voucherNo': 'EXP-07',
          'amount': '100.00',
          'kind': 'لمشترك',
          'category': 'مولود',
          'payeeAdeelId': 1,
          'payeeName': 'محمد العدولي',
          'payeeCode': 'A-01',
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
    expect(aid.ledger.single.voucher.voucherNo, 'EXP-07');
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
      'adeelCode': 'A-04',
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
    expect(e.haystack, contains('exp-01'));
  });

  // ── The screen ────────────────────────────────────────────────────────────

  testWidgets('the page opens on figures, not on an explanation', (
    WidgetTester tester,
  ) async {
    // This page carried a paragraph at the top explaining that aid is not
    // deducted from a subscription. The association removed it: that rule was
    // explained to the developer, not to the member, and a man opening his own
    // record wants the figures.
    //
    // Pinned so it does not come back as "a helpful note". The rule itself is
    // untouched and is not this screen's to keep — a voucher writes no
    // receivable and no payment, and supabase/tests/67_disbursement.sql proves
    // the statement cannot show one, as staff and as the member himself.
    await open(tester, _aid(), mine: true);

    expect(find.textContaining('خيرية'), findsNothing);
    expect(find.textContaining('لا يُخصم'), findsNothing);
    // What IS at the top: his total.
  });

  testWidgets('100 then 500 reads 100 then 600', (WidgetTester tester) async {
    // The association's own example, and the reason the ledger exists. Each
    // line carries the total SO FAR, so the answer to "how much has he had from
    // us" is read off the page rather than added up by whoever is looking.
    await open(tester, _aid());

    // ⚠ TWO now, not one: the PANEL is titled «الإجمالي» as well, so the same
    //   string appears twice on this screen with two meanings — the closing
    //   figure above, and the running total in the table. Named here so the
    //   collision is recorded rather than absorbed.
    expect(find.text(l.aidColRunning), findsNWidgets(2));
    expect(find.text(formatMoney('100.00')), findsWidgets);
    // 600 appears twice: on the last ledger line and in the closing total.
    expect(find.text(formatMoney('600.00')), findsWidgets);
  });

  _twoColumnTests();
  _detailPruneTests();
  _accordionTests();
  _detailOrderTests();
  _columnStyleTests();
  _headerTests();
  _headlineTests();
  _wrappingTests();
  _elasticTests();
  _serialTests();

  testWidgets('the DATE is not a column — it opens with the row', (
    WidgetTester tester,
  ) async {
    // It used to lead the table and cost more width than it answered: «19 أغسطس
    // 2026» wraps to two lines on a phone beside a one-word heading, so every
    // row was double height and the two figures the page exists for were
    // squeezed into what was left.
    //
    // The three columns that survive — البند، القيمة، الإجمالي — are what a
    // reader scans down. The date is one of the three facts he opens a single
    // row FOR, beside the voucher number and the note.
    await open(tester, _aid());

    expect(find.text(l.aidColDate), findsNothing);
    expect(find.text('10 فبراير 2026'), findsNothing);

    // .last, not .first: «مولود» is also a heading in the «حسب المناسبة»
    // panel above, and tapping THAT opens the breakdown rather than the
    // ledger row this test is about.
    await tester.tap(find.text('مولود').last);
    await tester.pumpAndSettle();

    expect(find.text(l.aidColDate), findsOneWidget);
    expect(find.text('10 فبراير 2026'), findsOneWidget);
  });

  testWidgets('...and dates still read in Latin digits wherever they appear', (
    WidgetTester tester,
  ) async {
    // formatDate was DateFormat.yMd('ar'), which renders ٢٠٢٦/٠٢/١٠ — and that
    // made the app disagree with ITSELF: every date arriving as a plain string
    // from SQL is already Latin, because Postgres wrote it with to_char. Two
    // dates on one page could be in two scripts.
    await open(tester, _aid());
    await tester.tap(find.text('مولود').last);
    await tester.pumpAndSettle();

    expect(find.text('10 فبراير 2026'), findsOneWidget);
    expect(find.textContaining('٢٠٢٦'), findsNothing);
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
    // Two births, told apart only by WHOSE — which is exactly the case the note
    // exists for, and the reason the box searches it even though it is folded
    // away on screen. One heading, so no breakdown panel to confuse the counts.
    final AdeelAid twoBirths = _aid(
      total: '600.00',
      count: 2,
      byCategory: const <ExpenseByCategory>[
        ExpenseByCategory(category: 'مولود', total: '600.00', count: 2),
      ],
      ledger: <AidLedgerEntry>[
        _entry(
          id: 1,
          amount: '100.00',
          runningTotal: '100.00',
          note: 'حور',
        ),
        _entry(
          id: 2,
          amount: '500.00',
          runningTotal: '600.00',
          note: 'سند',
          spentAt: '2026-06-20T09:00:00Z',
        ),
      ],
    );

    await open(tester, twoBirths);
    expect(find.text(formatMoney('100.00')), findsWidgets);
    expect(find.text(formatMoney('500.00')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'حور');
    await tester.pumpAndSettle();

    // The FOLDED note matched: the line survives although its text is not on
    // screen, which is the whole point of searching the record rather than the
    // pixels.
    expect(find.text(formatMoney('100.00')), findsWidgets);
    expect(find.text(formatMoney('500.00')), findsNothing);
    // And the reader is told the table is narrowed — without it the الإجمالي
    // column, which still belongs to the WHOLE history, looks like it skipped.
    expect(find.text(l.aidShowing(1, 2)), findsOneWidget);
    // The headline total does NOT move: a search hides rows, it does not change
    // what the association gave him.
    expect(find.text(formatMoney('600.00')), findsWidgets);
  });

  testWidgets('a search that matches nothing says so', (
    WidgetTester tester,
  ) async {
    await open(tester, _aid());
    await tester.enterText(find.byType(TextField), 'لا يوجد');
    await tester.pumpAndSettle();

    expect(find.text(l.aidNoMatch), findsOneWidget);
    // ...and the total above it is untouched: a search narrows the table, it
    // does not change what the association gave him.
    expect(find.text(formatMoney('600.00')), findsWidgets);
  });

  testWidgets('a line keeps its note folded away until it is tapped', (
    WidgetTester tester,
  ) async {
    // The table must stay a table. A note is prose of unknown length — «حور» is
    // short, a paragraph about a hospital in Tunis is not — and one long note
    // under every row pushes the rest of a member's years off the screen.
    //
    // So the line is one line, and the detail opens beneath it on a tap:
    // «نوع الصرف: مولود، الملاحظات: حور». The heading says what kind of
    // occasion; the note says WHOSE, and he is the only person who can verify
    // that the record is right.
    final AdeelAid one = _aid(
      ledger: <AidLedgerEntry>[
        _entry(
          id: 1,
          amount: '100.00',
          runningTotal: '100.00',
          note: 'حور',
        ),
      ],
      count: 1,
      total: '100.00',
      // One voucher, one heading — so no breakdown panel, and «مولود» in this
      // test can only be the ledger's own cell.
      byCategory: const <ExpenseByCategory>[
        ExpenseByCategory(category: 'مولود', total: '100.00', count: 1),
      ],
    );

    await open(tester, one, mine: true);

    // Closed: the heading is on the line, the note is nowhere.
    expect(find.text('مولود'), findsOneWidget);
    expect(find.text('حور'), findsNothing);

    await tester.tap(find.text('مولود'));
    await tester.pumpAndSettle();

    // Open: the note, under its own label, with room to wrap.
    expect(find.text('حور'), findsOneWidget);
    expect(find.text(l.aidNoteLabel), findsOneWidget);
    // ...and the rest of what the voucher was.
    expect(find.text('EXP-01'), findsOneWidget);
    expect(find.text(l.expenseCategory), findsOneWidget);

    // Tapping again folds it back.
    await tester.tap(find.text('مولود').first);
    await tester.pumpAndSettle();
    expect(find.text('حور'), findsNothing);
  });

  testWidgets('«حسب المناسبة» is gone, and the ledger answers it instead', (
    WidgetTester tester,
  ) async {
    // It grouped the vouchers by heading above a table that now HAS a heading
    // column — «مولود 450» sat directly above the very rows adding to 450, and
    // the reader had to satisfy himself twice that they were the same money.
    // The association called it duplication, which it was.
    //
    // What it uniquely answered — «كم صُرف لي في العزاء عبر السنين» — the
    // search box answers by typing the word, against the ledger itself rather
    // than beside it. The last two assertions are that half.
    await open(tester, _aid(ledger: _threeBirths(), byCategory: _birthsOnly()));

    expect(find.text('حسب المناسبة'), findsNothing);

    // The headings are on the page — in the table, once per voucher.
    expect(find.text('مولود'), findsNWidgets(3));

    // And the question the panel uniquely answered is answered by typing,
    // against the ledger itself rather than beside it. «حور» is one birth's
    // note, so one row survives.
    await tester.enterText(find.byType(TextField), 'حور');
    await tester.pumpAndSettle();
    expect(find.text('مولود'), findsOneWidget);
  });

  testWidgets('a YEAR opens onto the vouchers it is made of', (
    WidgetTester tester,
  ) async {
    // The same mechanism «حسب المناسبة» used before it was removed as
    // duplication — «حسب السنة» is not the same case, because the date came out
    // of the table and nothing else on this page groups by year.
    //
    // A heading answers «كم صُرف لي في 2026»; the question it raises is WHICH
    // vouchers, and the note on each is where the association wrote the name.
    await open(
      tester,
      _aid(
        byYear: const <AidByYear>[
          AidByYear(year: '2026', total: '100.00', count: 1),
          AidByYear(year: '2025', total: '500.00', count: 1),
        ],
        ledger: <AidLedgerEntry>[
          _entry(
            id: 1,
            amount: '500.00',
            runningTotal: '500.00',
            spentAt: '2025-06-20T09:00:00Z',
            note: 'زواج',
          ),
          _entry(
            id: 2,
            amount: '100.00',
            runningTotal: '600.00',
            spentAt: '2026-02-10T09:00:00Z',
            note: 'حور',
          ),
        ],
      ),
    );

    // Closed: the heading only.
    expect(find.text('EXP-02'), findsNothing);

    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();

    expect(find.text('EXP-02'), findsOneWidget);
    expect(find.text('حور'), findsWidgets);
    // And NOT the other year's voucher, which is the whole point of a heading
    // opening onto its own rows.
    expect(find.text('EXP-01'), findsNothing);
  });

  testWidgets('a REVERSED voucher is left out of what a heading opens onto', (
    WidgetTester tester,
  ) async {
    // ⚠ NOT a display preference. api_adeel_aid computes byYear over a CTE that
    //   excludes 'ملغي', so a heading reading «سند واحد 100.00» is already
    //   counting one. Expanding to the full ledger would list two rows adding
    //   to something else, directly beneath a total that disagrees — and
    //   nothing on screen would tell the reader which is right.
    //
    //   The reversed one is still in the LEDGER, where rule 9 requires it and
    //   where the الإجمالي column shows it moved nothing.
    await open(
      tester,
      _aid(
        byYear: const <AidByYear>[
          AidByYear(year: '2026', total: '100.00', count: 1),
          AidByYear(year: '2025', total: '500.00', count: 1),
        ],
        ledger: <AidLedgerEntry>[
          _entry(
            id: 1,
            amount: '500.00',
            runningTotal: '500.00',
            spentAt: '2025-06-20T09:00:00Z',
            note: 'زواج',
          ),
          _entry(
            id: 2,
            amount: '100.00',
            runningTotal: '600.00',
            spentAt: '2026-02-10T09:00:00Z',
            note: 'حور',
          ),
          _entry(
            id: 9,
            amount: '999.00',
            runningTotal: '600.00',
            status: 'ملغي',
            spentAt: '2026-05-01T09:00:00Z',
            note: 'أُلغي',
          ),
        ],
      ),
    );

    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();

    expect(find.text('EXP-02'), findsOneWidget);
    expect(find.text('أُلغي'), findsNothing);
    // ...and its 999 is in the ledger only, nowhere near the 100 the heading
    // claims.
    expect(find.text(formatMoney('999.00')), findsOneWidget);
  });

  testWidgets('the sentence that explained the grouping is gone', (
    WidgetTester tester,
  ) async {
    // A demonstration the reader performs himself needs no sentence beside it.
    await open(tester, _aid(), mine: true);
    expect(find.textContaining('تجميع للسندات'), findsNothing);
    expect(find.textContaining('عمليات صرف إضافية'), findsNothing);

    // Both readers get the same page. `mine` changes the voice and nothing else.
    await open(tester, _aid());
    // The page still renders for both readers; `mine` changes the voice and
    // nothing else. Asserted on the panel that survives.
    // TWO: the panel title and the running-total column now carry the same
    // word. See the note on `columnOf`.
    expect(find.text(l.aidPanelTitle), findsNWidgets(2));
  });

  testWidgets('the total and the vouchers share ONE container', (
    WidgetTester tester,
  ) async {
    // They were two — a headline card above a ledger panel — and read as two
    // separate things when they are one answer to one question. The search sits
    // above that container and outside it, because it is a control acting on
    // what follows rather than another row of the record.
    await open(tester, _aid(), mine: true);

    final Finder panel = find.ancestor(
      of: find.text(l.aidPanelTitle).first,
      matching: find.byType(GlassPanel),
    );
    expect(panel, findsOneWidget);
    expect(
      // The figure lives in the panel that names it — the label above it is
      // gone, so the figure itself is what proves the two are one container.
      find.descendant(of: panel, matching: find.text(formatMoney('600.00'))),
      // TWO: the headline and the ledger's closing running total, which end at
      // the same figure — that is what the الإجمالي column is for.
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.text(l.aidColCategory)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.byType(TextField)),
      findsNothing,
    );
  });

  testWidgets('the member\'s screen paints the app background', (
    WidgetTester tester,
  ) async {
    // Not decoration. `scaffoldBackgroundColor` is transparent app-wide and
    // every surface here is translucent WHITE, so a bare Scaffold gives them
    // black to composite over: the search box rendered as a dark slab with
    // unreadable text in it, and the panels lost their glass. Staff never saw it
    // because AppScaffold wraps itself in this; the member's branch builds its
    // own Scaffold and has to do it too.
    await open(tester, _aid(), mine: true);
    expect(find.byType(AppBackground), findsOneWidget);
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
    expect(find.text(l.aidPanelTitle), findsNWidgets(2));
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
    // A sentence and nothing else — no empty table, no zero-row ledger, and no
    // search box over nothing.
    expect(find.byType(TextField), findsNothing);
  });
}

/// The headline carries the FIGURE and nothing else.
///
/// A «سندان» count badge and a date-range picker sat under it. Both were
/// removed at the association's request, and both deserved to go for the same
/// reason: the table beneath answers them better than a chip above it can. The
/// count is the length of a list the reader is looking at, and a period filter
/// on a ledger of a handful of vouchers is a control operating on a problem
/// nobody has.
void _headlineTests() {
  final L l = LAr();

  testWidgets('no count badge and no period control above the table', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
          adeelAidProvider(1).overrideWith((Ref ref) async => _aid()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: const AdeelAidScreen(adeelId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing pressable above the table at all.
    expect(find.byType(ActionChip), findsNothing);
    // Nor the count that used to sit beside it.
    expect(find.text(l.aidVoucherCount(2)), findsNothing);

    // The figure the page exists for is still there, and still green.
    // .first: the closing running total in the ledger carries the same string,
    // which is the point of that column — it ends at the headline figure.
    final Text total = tester.widget<Text>(
      find.text(formatMoney('600.00')).first,
    );
    expect(total.style?.color, AppColors.danger);
  });
}

/// A cell takes ONE line when the words fit, and TWO when they do not.
///
/// ── THE RULE THIS REPLACED ──────────────────────────────────────────────────
/// It was briefly "always one line", enforced by shrinking anything too wide —
/// so «مناسبة اجتماعية» rendered a point smaller than «مولود» beside it. The
/// association rejected it, and rightly: that is a rule fighting the layout
/// rather than serving it, and it bought a single line at the price of a column
/// with two type sizes in it.
///
/// So this asserts BEHAVIOUR, not a flag. BOTH headings are rendered in ONE
/// ledger and their heights compared, so the comparison is between two cells
/// laid out by the same pass at the same width. A test that read `maxLines`
/// would pass just as happily on text that was being truncated.
void _wrappingTests() {
  /// The short heading and the long one, in that order, in one render.
  ///
  /// One `pumpWidget`, deliberately: a second call in the same test reuses the
  /// tree and does not pick up new overrides — which is how the first version
  /// of this file measured the same widget twice and reported no difference.
  Widget host() => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
      adeelAidProvider(1).overrideWith(
        (Ref ref) async => _aid(
          ledger: <AidLedgerEntry>[
            _entry(
              id: 1,
              amount: '100.00',
              runningTotal: '100.00',
              // Three letters, and that is deliberate: the test font's glyphs
              // are square and far wider than Tajawal's, so «مولود» wraps HERE
              // while fitting comfortably on a real phone — which would have
              // made this test a test of the test font.
              category: 'فرح',
              note: 'حور',
            ),
            _entry(
              id: 2,
              amount: '500.00',
              runningTotal: '600.00',
              // The longest of the six, and the one in the association's own
              // screenshot.
              category: 'مناسبة اجتماعية',
              note: 'سند',
            ),
          ],
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const AdeelAidScreen(adeelId: 1),
    ),
  );

  /// 360dp — the narrow end of what the association actually carries, and where
  /// the wrapping was seen.
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  testWidgets('a long heading opens a SECOND line, and a short one does not', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    final double short = tester.getSize(find.text('فرح').last).height;
    final double long = tester
        .getSize(find.text('مناسبة اجتماعية').last)
        .height;

    // Taller, because it wrapped. This is the whole assertion: a cell that
    // shrank to fit, or one that was cut off, would be the SAME height as the
    // short one — which is exactly how the previous rule passed while looking
    // wrong on the phone.
    expect(long, greaterThan(short));
    // Two lines, not five. A value demanding a third would be one nobody typed,
    // and one row growing without limit pushes the table off the screen.
    expect(long, lessThan(short * 2.5));
  });

  testWidgets('...and every word of it survives', (WidgetTester tester) async {
    // «مناسبة اجتما…» would satisfy the height check above just as well, and
    // would lose the reader the heading — which is this screen's entire
    // vocabulary.
    await pump(tester);
    expect(find.text('مناسبة اجتماعية'), findsWidgets);
  });

  testWidgets('the figures stay level with the row, not with its first line', (
    WidgetTester tester,
  ) async {
    // A wrapped heading makes its cell taller than the two beside it. Left top
    // aligned, the amounts would sit against its FIRST line and the row would
    // read as though the money belonged to the word above it.
    await pump(tester);

    final Offset heading = tester.getCenter(find.text('مناسبة اجتماعية').last);
    final Offset amount = tester.getCenter(find.text('500.00').last);
    expect((heading.dy - amount.dy).abs(), lessThan(1.5));
  });
}

/// The columns are MEASURED against their contents, not divided into thirds.
///
/// «500.00» needs about half the room a third gives it; «مناسبة اجتماعية» needs
/// more than one. Thirds spent the table's width on the two columns that had
/// none to spend and starved the one that did.
///
/// ── ASSERTED AS RELATIONS, NOT PIXELS ───────────────────────────────────────
/// Every check below compares two widths INSIDE one render. A threshold in
/// device pixels would be a number fitted to whatever this machine's font
/// happened to produce — and it would pass or fail for reasons that have
/// nothing to do with the rule. Under the old equal-thirds layout every one of
/// these comparisons was an equality, so each of them is exactly the difference
/// the change made.
void _elasticTests() {
  /// The running total is deliberately NOT the amount: with both columns
  /// holding the same string, `find.text(...).last` picks الإجمالي while the
  /// test believes it is looking at القيمة — which is how the first version of
  /// this file reported the heading sitting 95px off its own column.
  Widget host(String amount, String running) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
      adeelAidProvider(1).overrideWith(
        (Ref ref) async => _aid(
          ledger: <AidLedgerEntry>[
            _entry(
              id: 1,
              amount: amount,
              runningTotal: running,
              category: 'مولود',
              note: 'حور',
            ),
          ],
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const AdeelAidScreen(adeelId: 1),
    ),
  );

  /// 360dp — the narrow end of what the association carries.
  Future<void> pump(WidgetTester tester, String amount, String running) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(amount, running));
    await tester.pumpAndSettle();
  }

  /// A header cell's width IS its column's: `_Cell` is a Text under a tight
  /// constraint, so it is sized by the column rather than by its own letters.
  ///
  /// ⚠ `.last` because «الإجمالي» is on this screen TWICE — it is the panel's
  ///   title as well as the running-total column's heading. The title renders
  ///   first, so the column is the later one. Worth stating rather than
  ///   absorbing: one string with two meanings on one screen is a collision the
  ///   reader hits too, and «التراكمي» on the column would end it.
  double columnOf(WidgetTester tester, String heading) =>
      tester.getSize(find.text(heading).last).width;

  testWidgets('every column is sized by ITS OWN heading and values', (
    WidgetTester tester,
  ) async {
    await pump(tester, '5.00', '9.00');

    final double serial = columnOf(tester, LAr().aidColSerial);
    final double amount = columnOf(tester, LAr().aidColAmount);
    final double running = columnOf(tester, LAr().aidColRunning);

    // «تسلسل» < «القيمة» < «الإجمالي», and the figures under them are short, so
    // each column comes out in that order too. Under an equal division these
    // were three identical numbers — the chain below is exactly what
    // measurement buys, and it holds in any font because it compares words to
    // words rather than pixels to a constant.
    expect(serial, lessThan(amount));
    expect(amount, lessThan(running));
  });

  testWidgets('a mis-keyed figure cannot squeeze البند off the table', (
    WidgetTester tester,
  ) async {
    // The other half of the rule. Measuring alone would let one absurd amount —
    // a treasury keyed as 1,234,567 — take the width the headings need, so each
    // column is capped at a share of the table and wraps past it instead.
    await pump(tester, '1234567.00', '7654321.00');

    final double serial = columnOf(tester, LAr().aidColSerial);
    final double category = columnOf(tester, LAr().aidColCategory);
    final double amount = columnOf(tester, LAr().aidColAmount);
    final double running = columnOf(tester, LAr().aidColRunning);
    final double table = serial + category + amount + running;

    // Both money columns are pinned at their cap...
    expect(amount / table, lessThan(0.31));
    expect(running / table, lessThan(0.31));
    // ...and the ordinal at its own, tighter one: it is the least informative
    // of the four and must never be the column that squeezes البند.
    expect(serial / table, lessThan(0.19));
    // ...which leaves البند a floor to stand on. Under an equal division there
    // was no floor at all — one long amount simply took the room.
    expect(category / table, greaterThan(0.21));
  });
  testWidgets('the heading sits centred over its own column', (
    WidgetTester tester,
  ) async {
    // The reason header and rows are laid out from ONE set of measurements. Two
    // independently sized Rows agree only by coincidence, and stop agreeing the
    // first time a value outgrows the word above it.
    await pump(tester, '1234567.00', '7654321.00');

    final double head = tester.getCenter(find.text(LAr().aidColAmount)).dx;
    final double cell = tester.getCenter(find.text('1,234,567.00')).dx;
    expect((head - cell).abs(), lessThan(1.5));

    final double headRun = tester
        .getCenter(find.text(LAr().aidColRunning).last)
        .dx;
    final double cellRun = tester.getCenter(find.text('7,654,321.00')).dx;
    expect((headRun - cellRun).abs(), lessThan(1.5));
  });
}

/// التسلسل — the ordinal at the far right.
///
/// ⚠ IT NUMBERS THE FULL HISTORY, not the visible rows. The number belongs to
///   the voucher exactly as the running total does, so a search or a period
///   cannot renumber a man's past. Numbering what happens to be on screen would
///   put a «1» beside a running total of 600 — two columns of the same row
///   disagreeing about which voucher it is.
void _serialTests() {
  final L l = LAr();

  Widget host() => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
      adeelAidProvider(1).overrideWith(
        (Ref ref) async => _aid(ledger: _threeBirths(), byCategory: _birthsOnly()),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const AdeelAidScreen(adeelId: 1),
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
  }

  testWidgets('the ledger is numbered, oldest first', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.text(l.aidColSerial), findsOneWidget);
    for (final String n in <String>['1', '2', '3']) {
      expect(find.text(n), findsOneWidget, reason: 'الترتيب $n');
    }
  });

  testWidgets('it sits at the FAR RIGHT, before the heading', (
    WidgetTester tester,
  ) async {
    // RTL: first in the children list is the right-hand edge. Asserted by
    // position rather than by the order of the code, because the code reads
    // left-to-right and the screen does not.
    await pump(tester);

    final double serial = tester.getCenter(find.text(l.aidColSerial)).dx;
    final double category = tester.getCenter(find.text(l.aidColCategory)).dx;
    final double running = tester.getCenter(find.text(l.aidColRunning).last).dx;

    expect(serial, greaterThan(category));
    expect(category, greaterThan(running));
  });

  testWidgets('a filter does NOT renumber the history', (
    WidgetTester tester,
  ) async {
    // The rule this column would be wrong without. Search for the third birth
    // and it must still be «3» — the number is the voucher's place in his life
    // with the association, not its place in a list somebody just filtered.
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'ريم');
    await tester.pumpAndSettle();

    expect(find.text('ريم'), findsWidgets);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });
}

/// The header: his name, and his code FACING it across the same line.
///
/// The code sat under the name in a small muted style, which read as a caption
/// — a footnote to the heading rather than the other half of it. It is not a
/// footnote: «A-01» is how the association refers to him on every receipt and
/// voucher, and it is what a reader checks when two men share a spelling.
void _headerTests() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
          adeelAidProvider(1).overrideWith((Ref ref) async => _aid()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: const AdeelAidScreen(adeelId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the code sits on the far side of the name, not beneath it', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    // ⚠ TOPS, not centres. The two are aligned on their BASELINE, and a long
    //   name wraps to a second line while the code never does — so their
    //   centres sit half a line apart while their first lines are perfectly
    //   level, which is what a reader sees. Comparing centres would have failed
    //   on a correct layout, and passed on one where the code floated.
    final Offset name = tester.getTopLeft(find.text('محمد العدولي'));
    final Offset code = tester.getTopLeft(find.text('A-01'));
    expect((name.dy - code.dy).abs(), lessThan(1.5));

    // And the code is to the LEFT, which in RTL is the far side. Asserted by
    // coordinate rather than by the order of the code, because the code reads
    // left-to-right and the screen does not.
    expect(code.dx, lessThan(name.dx));
  });

  testWidgets('...and it is the SAME size as the name', (
    WidgetTester tester,
  ) async {
    // Matching the size is what makes the two read as one line rather than as a
    // heading with a caption. Only the colour separates them, which is what
    // keeps the name the thing read first.
    await pump(tester);

    final Text name = tester.widget<Text>(find.text('محمد العدولي'));
    final Text code = tester.widget<Text>(find.text('A-01'));

    expect(code.style?.fontSize, name.style?.fontSize);
    expect(code.style?.color, isNot(name.style?.color));
  });
}

/// Two columns of the same figures, saying two different things.
///
/// القيمة is ONE act of spending — money leaving the treasury, which is red on
/// every screen in this app. الإجمالي is what the man has received over his
/// life with the association, which is his, and green.
///
/// And البند reads from where words begin: start-aligned, flush with «#», so
/// the eye finds every heading in the same place instead of hunting a centred
/// one on each row.
void _columnStyleTests() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
          adeelAidProvider(1).overrideWith(
            (Ref ref) async => _aid(
              ledger: <AidLedgerEntry>[
                _entry(
                  id: 1,
                  amount: '100.00',
                  runningTotal: '250.00',
                  category: 'فرح',
                  note: 'حور',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: const AdeelAidScreen(adeelId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every figure on the page is RED', (WidgetTester tester) async {
    // It was briefly split — القيمة red, الإجمالي green — on the reasoning that
    // one is money leaving the treasury and the other is what the man has
    // received. The association chose one colour, and it is the more consistent
    // reading: this page is «ما صُرف» throughout, and a page about one kind of
    // money should not need two colours to say so.
    await pump(tester);

    final Text amount = tester.widget<Text>(find.text(formatMoney('100.00')));
    final Text running = tester.widget<Text>(
      find.text(formatMoney('250.00')).last,
    );

    expect(amount.style?.color, AppColors.danger);
    expect(running.style?.color, AppColors.danger);
    // Nothing green survives on it.
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .where((Text t) => t.style?.color == AppColors.success),
      isEmpty,
    );
  });

  testWidgets('البند starts at the right, flush with «#»', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    // ⚠ THE BOX CANNOT ANSWER THIS. `_Cell` sits under a tight constraint, so a
    //   centred cell and a start-aligned one occupy the SAME rectangle —
    //   `textAlign` decides where the glyphs land inside it, and nothing about
    //   the geometry changes. The first version of this test measured
    //   getTopRight and passed just as happily on the centred layout it was
    //   written to reject.
    //
    //   So the property is asserted directly, for the header AND the value:
    //   the two must agree, or the heading stops sitting over its own words.
    final Text head = tester.widget<Text>(find.text(LAr().aidColCategory));
    final Text cell = tester.widget<Text>(find.text('فرح'));
    expect(head.textAlign, TextAlign.start);
    expect(cell.textAlign, TextAlign.start);

    // And the two are the same column: same right edge, which is what "flush
    // with «#»" means once the alignment above is settled.
    expect(
      (tester.getTopRight(find.text(LAr().aidColCategory)).dx -
              tester.getTopRight(find.text('فرح')).dx)
          .abs(),
      lessThan(1.5),
    );
  });

  testWidgets('...and the chevron sits at the far END of that column', (
    WidgetTester tester,
  ) async {
    // It used to come BEFORE the word, which put an icon between «#» and the
    // heading — exactly the gap that made the column look ragged. At the end it
    // is out of the reading path and still the only thing on screen saying the
    // row opens.
    await pump(tester);

    final double word = tester.getCenter(find.text('فرح')).dx;
    final double chevron = tester.getCenter(find.byIcon(Icons.expand_more)).dx;
    // LEFT of the word, which in RTL is after it.
    expect(chevron, lessThan(word));
  });
}

/// The detail block, in the order the association asked for.
///
///   رقم الإيصال + التاريخ   — one line
///   طريقة الدفع + المبلغ    — one line
///   المستلم                 — one line
///   بند الصرف               — one line
///   الملاحظات               — last
///
/// Two facts to a line where they belong together, one where they do not: a
/// voucher is identified by its number and its date TOGETHER — that is how it
/// is found in a folder — and money is described by its amount and how it moved.
/// Split across two lines the reader assembles the pair himself.
void _detailOrderTests() {
  final L l = LAr();

  Future<void> openRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
          adeelAidProvider(1).overrideWith(
            (Ref ref) async => _aid(
              ledger: <AidLedgerEntry>[
                _entry(
                  id: 1,
                  amount: '100.00',
                  runningTotal: '100.00',
                  category: 'فرح',
                  note: 'حور',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: const AdeelAidScreen(adeelId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('فرح'));
    await tester.pumpAndSettle();
  }

  double y(WidgetTester tester, String label) =>
      tester.getCenter(find.text(label)).dy;

  testWidgets('the pairs share a line, and the singles do not', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    // Level with each other: one line each.
    expect((y(tester, l.voucherNo) - y(tester, l.aidColDate)).abs(), lessThan(1.5));
    expect((y(tester, l.method) - y(tester, l.amount)).abs(), lessThan(1.5));

    // And the two pairs are not on the same line as each other.
    expect(y(tester, l.method), greaterThan(y(tester, l.voucherNo)));
  });

  testWidgets('...and they run in the order the association gave', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    // Top to bottom, ONE entry per line — and the line's own two halves are
    // levelled by the test above rather than repeated here. Asserted by
    // coordinate rather than by the order of the widgets in the code, because
    // an order in code is not an order on screen.
    final List<String> down = <String>[
      l.voucherNo,
      l.method,
      l.recipient,
      l.aidNoteLabel,
    ];
    for (int i = 1; i < down.length; i++) {
      expect(
        y(tester, down[i]),
        greaterThan(y(tester, down[i - 1])),
        reason: '«${down[i]}» must sit below «${down[i - 1]}»',
      );
    }
  });

  testWidgets('the note is last, and it is the reason the row folds', (
    WidgetTester tester,
  ) async {
    // Everything above it is a short value on one line; this is prose of
    // unknown length. «حور» is three letters, a paragraph about a hospital in
    // Tunis is not, and one long note under every row would push a member's
    // years off the screen — which is why the row folds at all.
    await openRow(tester);

    expect(find.text('حور'), findsWidgets);
    expect(y(tester, l.aidNoteLabel), greaterThan(y(tester, l.recipient)));
  });
}

/// One detail open at a time.
///
/// Expansion used to live in each row, which made it independent: open four
/// headings and four paragraphs of prose stack down a page whose whole point is
/// a table. Opening a second now closes the first.
///
/// ⚠ THE OPEN ROW IS TRACKED BY VOUCHER ID, never by position. A search rewrites
///   the list, so the row at position 2 after typing is a different voucher from
///   the one before it — an index would leave another man's detail hanging open
///   under a heading that is not his, and nothing on screen would say so.
void _accordionTests() {
  final L l = LAr();

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
          adeelAidProvider(1).overrideWith(
            (Ref ref) async =>
                _aid(ledger: _threeBirths(), byCategory: _birthsOnly()),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: const AdeelAidScreen(adeelId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the row carrying this serial number.
  Future<void> tapRow(WidgetTester tester, String serial) async {
    await tester.tap(find.text(serial));
    await tester.pumpAndSettle();
  }

  testWidgets('opening a second detail closes the first', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tapRow(tester, '1');
    expect(find.text('حور'), findsOneWidget);
    expect(find.text('سند'), findsNothing);

    await tapRow(tester, '2');
    // The second is open...
    expect(find.text('سند'), findsOneWidget);
    // ...and the first closed itself.
    expect(find.text('حور'), findsNothing);
    // Exactly one detail block on the page, whichever it is.
    expect(find.text(l.voucherNo), findsOneWidget);
  });

  testWidgets('tapping the SAME row again closes it', (
    WidgetTester tester,
  ) async {
    // An accordion that cannot be shut leaves the reader no way back to the
    // plain table he was scanning.
    await pump(tester);

    await tapRow(tester, '1');
    expect(find.text(l.voucherNo), findsOneWidget);

    await tapRow(tester, '1');
    expect(find.text(l.voucherNo), findsNothing);
  });

  testWidgets('a search that hides the open row closes it, and opens nothing', (
    WidgetTester tester,
  ) async {
    // The reason the open row is tracked by ID. Filtered out, its id matches
    // nothing and the block shuts — which is the right answer to "the row you
    // were reading is no longer here". By INDEX, position 1 would still exist
    // and a different man's detail would be sitting open under it.
    await pump(tester);

    await tapRow(tester, '1');
    expect(find.text('حور'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ريم');
    await tester.pumpAndSettle();

    expect(find.text(l.voucherNo), findsNothing);
    expect(find.text('حور'), findsNothing);
  });
}

/// The detail block, after the association pruned it.
///
///   • ONE line naming a person — «المستلم», filled from the voucher itself.
///     «المُسلِّم» sat beneath it and is gone: two lines whose Arabic differs by
///     a letter, one of them about someone the member has no reason to look up.
///   • The note sits BESIDE its label, not under it. A detail block is read
///     down its labels, and a value that steps off that rhythm is the one the
///     eye loses.
void _detailPruneTests() {
  final L l = LAr();

  Future<void> openRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
          adeelAidProvider(1).overrideWith(
            (Ref ref) async => _aid(
              ledger: <AidLedgerEntry>[
                _entry(
                  id: 1,
                  amount: '100.00',
                  runningTotal: '100.00',
                  category: 'فرح',
                  note: 'حور',
                  handedBy: 'أمين الصندوق',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: const AdeelAidScreen(adeelId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('فرح'));
    await tester.pumpAndSettle();
  }

  testWidgets('ONE line names a person, and the system fills it', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    expect(find.text(l.recipient), findsOneWidget);
    // «المُسلِّم» is gone — the second, nearly identical, line.
    expect(find.text(l.handedBy), findsNothing);
    // And the name comes from the voucher's own snapshot, not from anything
    // typed on this screen.
    expect(find.text('محمد العدولي'), findsWidgets);
  });

  testWidgets('the note sits BESIDE its label, on one line with it', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    // ⚠ TOPS, not centres. `_DetailLine` aligns its two children on `start`, so
    //   their tops are level while their centres are not — the label is a point
    //   smaller than the value and may take two lines where the value takes one.
    //   Comparing centres failed on a correct layout, which is the wrong way for
    //   a test to be wrong.
    final Offset label = tester.getTopRight(find.text(l.aidNoteLabel));
    final Offset value = tester.getTopRight(find.text('حور'));

    expect((label.dy - value.dy).abs(), lessThan(1.5));
    // And the value is to the LEFT of the label, which in RTL is after it —
    // beside, not beneath.
    expect(value.dx, lessThan(label.dx));
  });
}

/// THREE pairs and a note — and the pairs start on two straight edges.
///
///   رقم الإيصال | التاريخ
///   طريقة الدفع | المبلغ
///   المستلم     | بند الصرف
///   الملاحظات   (alone)
///
/// Each pair is two halves of one question: what identifies the voucher, how
/// the money moved, and who got it for what. The note is alone because it is
/// prose of unknown length — pairing it would give whatever sat beside it a
/// column that shrinks with the sentence.
///
/// The alignment is the point of this file. Equal halves mean the second column
/// starts at the same x on every row, and a block read DOWN its labels is only
/// readable if those labels start in one place.
void _twoColumnTests() {
  final L l = LAr();

  Future<void> openRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
          adeelAidProvider(1).overrideWith(
            (Ref ref) async => _aid(
              ledger: <AidLedgerEntry>[
                _entry(
                  id: 1,
                  amount: '100.00',
                  runningTotal: '100.00',
                  category: 'فرح',
                  note: 'حور',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: const AdeelAidScreen(adeelId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('فرح').last);
    await tester.pumpAndSettle();
  }

  /// The starting edge of a label. RTL, so a line begins on the RIGHT.
  double startOf(WidgetTester tester, String label) =>
      tester.getTopRight(find.text(label)).dx;

  testWidgets('المستلم and بند الصرف share a line', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    final double who = tester.getTopRight(find.text(l.recipient)).dy;
    final double what = tester.getTopRight(find.text(l.expenseCategory)).dy;
    expect((who - what).abs(), lessThan(1.5));
  });

  testWidgets('the three RIGHT-hand labels start on one straight edge', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    final double a = startOf(tester, l.voucherNo);
    final double b = startOf(tester, l.method);
    final double c = startOf(tester, l.recipient);

    expect((a - b).abs(), lessThan(0.5));
    expect((b - c).abs(), lessThan(0.5));
    // And the note, alone, begins on that same edge — the block has ONE left
    // margin, not one per row.
    expect((a - startOf(tester, l.aidNoteLabel)).abs(), lessThan(0.5));
  });

  testWidgets('...and so do the three LEFT-hand ones', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    final double a = startOf(tester, l.aidColDate);
    final double b = startOf(tester, l.amount);
    final double c = startOf(tester, l.expenseCategory);

    expect((a - b).abs(), lessThan(0.5));
    expect((b - c).abs(), lessThan(0.5));
    // And they are genuinely a second column: to the LEFT of the first one.
    expect(a, lessThan(startOf(tester, l.voucherNo)));
  });

  testWidgets('the note is the only line on its own', (
    WidgetTester tester,
  ) async {
    await openRow(tester);

    final double note = tester.getTopRight(find.text(l.aidNoteLabel)).dy;
    // Nothing else sits level with it.
    for (final String other in <String>[
      l.voucherNo,
      l.aidColDate,
      l.method,
      l.amount,
      l.recipient,
      l.expenseCategory,
    ]) {
      expect(
        (tester.getTopRight(find.text(other)).dy - note).abs(),
        greaterThan(1.5),
        reason: '«$other» must not share the note\'s line',
      );
    }
  });
}
