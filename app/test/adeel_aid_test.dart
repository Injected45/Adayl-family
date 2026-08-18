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
    expect(find.text(l.aidGrandTotal), findsWidgets);
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

  testWidgets('dates read in Latin digits, as they do everywhere else', (
    WidgetTester tester,
  ) async {
    // formatDate was DateFormat.yMd('ar'), which renders ٢٠٢٦/٠٢/١٠ — and that
    // made the app disagree with ITSELF: every date arriving as a plain string
    // from SQL (registeredAt, the year inside «يناير 2026») is already Latin,
    // because Postgres wrote it with to_char. Two dates on one page could be in
    // two scripts.
    //
    // `yyyy-MM-dd` is the shape those SQL strings already have, so every date in
    // the app now reads the same wherever it came from. Money keeps its
    // Arabic-Indic digits — that was never the inconsistent part.
    await open(tester, _aid());

    expect(find.text('10 فبراير 2026'), findsOneWidget);
    expect(find.text('20 يونيو 2026'), findsOneWidget);
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
          category: 'مولود',
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

  testWidgets('the breakdown shows to the member too, not just to staff', (
    WidgetTester tester,
  ) async {
    // «كم صُرف لي في العزاء عبر السنين» is a question a long ledger does not
    // answer by being read row by row, and it is as much the member's question
    // as the association's. The panel was briefly staff-only; the association
    // asked for it on his screen as well.
    await open(tester, _aid(), mine: true);
    expect(find.text(l.aidByCategory), findsOneWidget);
  });

  testWidgets('...and a heading OPENS onto the vouchers it is made of', (
    WidgetTester tester,
  ) async {
    // The reason the panel was doubted in the first place: «مولود 450» appears
    // in it and the same vouchers again in the ledger below, which reads as the
    // same money recorded twice. A sentence used to settle that; the line now
    // settles it by SHOWING — the reader opens مولود and sees the very three
    // vouchers, by number, that are in the ledger.
    //
    // And it is the answer to the question the heading raises: WHICH births.
    // The note is where the association wrote the child's name.
    await open(tester, _aid(ledger: _threeBirths(), byCategory: _birthsOnly()));

    // Closed: the heading only.
    expect(find.text('EXP-01'), findsNothing);

    await tester.tap(find.text('مولود').first);
    await tester.pumpAndSettle();

    expect(find.text('EXP-01'), findsOneWidget);
    expect(find.text('EXP-02'), findsOneWidget);
    expect(find.text('EXP-03'), findsOneWidget);
    // Each with what was written on it — the whole reason to open the line.
    expect(find.text('حور'), findsOneWidget);
    expect(find.text('سند'), findsOneWidget);
    expect(find.text('ريم'), findsOneWidget);
  });

  testWidgets('...and it closes again on a second tap', (
    WidgetTester tester,
  ) async {
    await open(tester, _aid(ledger: _threeBirths(), byCategory: _birthsOnly()));

    await tester.tap(find.text('مولود').first);
    await tester.pumpAndSettle();
    expect(find.text('حور'), findsOneWidget);

    await tester.tap(find.text('مولود').first);
    await tester.pumpAndSettle();
    expect(find.text('حور'), findsNothing);
  });

  testWidgets('a REVERSED voucher is left out of what a heading opens onto', (
    WidgetTester tester,
  ) async {
    // ⚠ NOT a display preference. api_adeel_aid computes byCategory over a CTE
    //   that excludes 'ملغي', so a heading reading «سندان 250.00» is already
    //   counting two. Expanding to the full ledger would list three rows adding
    //   to something else, directly beneath a total that disagrees — and
    //   nothing on screen would tell the reader which is right.
    //
    //   The reversed one is still in the LEDGER below, where rule 9 requires it
    //   and where the الإجمالي column shows it moved nothing.
    await open(
      tester,
      _aid(
        ledger: <AidLedgerEntry>[
          ..._threeBirths().take(2),
          _entry(
            id: 9,
            amount: '999.00',
            runningTotal: '250.00',
            category: 'مولود',
            status: 'ملغي',
            spentAt: '2026-05-01T09:00:00Z',
            note: 'أُلغي',
          ),
        ],
        byCategory: const <ExpenseByCategory>[
          ExpenseByCategory(category: 'مولود', total: '250.00', count: 2),
          ExpenseByCategory(category: 'فرح', total: '500.00', count: 1),
        ],
      ),
    );

    await tester.tap(find.text('مولود').first);
    await tester.pumpAndSettle();

    expect(find.text('EXP-01'), findsOneWidget);
    expect(find.text('EXP-02'), findsOneWidget);
    // The reversed one is NOT under the heading...
    expect(find.text('أُلغي'), findsNothing);
    // ...and its 999 is nowhere near the 250 the heading claims.
    expect(find.text(formatMoney('999.00')), findsOneWidget); // ledger only
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
    expect(find.text(l.aidByCategory), findsOneWidget);
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
      of: find.text(l.aidPanelTitle),
      matching: find.byType(GlassPanel),
    );
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.text(l.aidGrandTotal)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text(l.aidColDate)),
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
    // A sentence and nothing else — no empty table, no zero-row ledger, and no
    // search box over nothing.
    expect(find.byType(TextField), findsNothing);
  });
}
