import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/chat/presentation/unread_bell.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeel_portal_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// How the عديل portal is ARRANGED, not what it contains.
///
/// The screen used to be one scroll — identity, then every receivable he had
/// ever had, then the whole ledger — three blocks of equal weight, none of them
/// answering the question he opened the app to ask. Layout decisions rot
/// silently: nothing fails when a settled month creeps back into "your dues",
/// or when the balance stops being the first thing on the page. These pin the
/// decisions that make it a statement rather than a pile of figures.

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

AdeelDetail _detail({
  required String debt,
  required List<Map<String, dynamic>> receivables,
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
    'paid': '20.00',
    'issued': '140.00',
    'monthlyExpected': '20.00',
  },
  'kpis': <String, dynamic>{
    'monthlyExpected': '20.00',
    'issued': '140.00',
    'debt': debt,
    'paid': '20.00',
    'openPeriods': receivables.length,
  },
  'receivables': receivables,
  'payments': <dynamic>[],
});

Map<String, dynamic> _due(String period, String status, String balance) =>
    <String, dynamic>{
      'id': period.hashCode & 0xffff,
      'adeelId': 1,
      'adeelName': 'المهدي العدولي',
      'adeelCode': 'A-01',
      'period': period,
      'periodLabel': 'شهر $period',
      'periodEnd': '$period-28',
      'total': '20.00',
      'paid': status == 'مسدد بالكامل' ? '20.00' : '0.00',
      'balance': balance,
      'status': status,
    };

void main() {
  final L l = LAr();
  _portalUnreadTests();

  Widget app(
    AdeelDetail detail, [
    List<StatementMovement> movements = const <StatementMovement>[],
  ]) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      adeelDetailProvider(1).overrideWith((Ref ref) async => detail),
      statementProvider(1).overrideWith(
        (Ref ref) async =>
            Statement(movements: movements, closingBalance: '120.00'),
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

  Future<void> pump(WidgetTester tester, AdeelDetail detail) async {
    tester.view.physicalSize = const Size(411, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(detail));
    await tester.pumpAndSettle();
  }

  testWidgets('a settled month is NOT listed as a due', (
    WidgetTester tester,
  ) async {
    // The old screen listed every receivable he had ever had, so a month he had
    // already paid sat under "اشتراكاتي" reading like an outstanding demand.
    // Settled months belong in the ledger, beside the payment that settled them.
    await pump(
      tester,
      _detail(
        debt: '20.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-01', 'مسدد بالكامل', '0.00'),
          _due('2026-02', 'غير مسدد', '20.00'),
        ],
      ),
    );

    expect(find.text('شهر 2026-02'), findsOneWidget);
    expect(find.text('شهر 2026-01'), findsNothing);
  });

  testWidgets('owing nothing is an answer, not an empty list', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      _detail(
        debt: '0.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-01', 'مسدد بالكامل', '0.00'),
        ],
      ),
    );

    expect(find.text(l.settledUpTitle), findsWidgets);
    expect(find.text(l.noReceivables), findsNothing);
  });

  testWidgets('his name heads the balance card, and appears once', (
    WidgetTester tester,
  ) async {
    // The name used to sit in a collapsed panel at the FOOT of the page, under
    // the dues and the ledger — so the man reading his own statement scrolled
    // past everything to reach his own name, and in practice never saw it.
    //
    // A statement is addressed to somebody, so the two are now one card:
    // name, then the figure, in that order and in the same frame. The earlier
    // version of this test asserted the OPPOSITE order; it was pinning "the
    // balance is answered before anything else", which the hero still does —
    // the dues below it are what the balance now precedes.
    await pump(
      tester,
      _detail(
        debt: '120.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-02', 'غير مسدد', '20.00'),
        ],
      ),
    );

    final double nameY = tester.getTopLeft(find.text('المهدي العدولي')).dy;
    final double heroY = tester.getTopLeft(find.text(l.myBalanceNow)).dy;
    final double duesY = tester.getTopLeft(find.text('شهر 2026-02')).dy;

    expect(nameY, lessThan(heroY), reason: 'the name must head the card');
    expect(heroY, lessThan(duesY), reason: 'the figure still precedes the dues');

    // Once, not twice. The identity panel at the foot kept a copy of the name
    // as its title while the hero grew one, which put the same three facts on
    // one short screen twice over.
    expect(find.text('المهدي العدولي'), findsOneWidget);
    expect(find.text('A-01'), findsOneWidget);
  });

  testWidgets('the dues and the ledger never occupy the screen together', (
    WidgetTester tester,
  ) async {
    // The whole point of the segmented control: one question answered at a
    // time. Both showing at once is the layout this replaced.
    await pump(
      tester,
      _detail(
        debt: '20.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-02', 'غير مسدد', '20.00'),
        ],
      ),
    );

    expect(find.text('شهر 2026-02'), findsOneWidget);
    // البيان, not الرصيد: the totals strip above the tabs now says "الرصيد" too
    // — the member's own word for where he stands — so it is no longer unique
    // to the ledger and cannot be its sentinel.
    expect(find.text(l.ledgerParticulars), findsNothing);

    await tester.tap(find.text(l.myStatementSection).last);
    await tester.pumpAndSettle();

    expect(find.text('شهر 2026-02'), findsNothing);
  });

  testWidgets('his details open from his NAME, through a MENU of four', (
    WidgetTester tester,
  ) async {
    // There was a card at the bottom of the page carrying his phone, his
    // registration date and the monthly fee — every one of which already sat in
    // the المزيد sheet under a heading of that exact name. Two places, one set
    // of facts, and the copy at the foot was the one nobody scrolled to.
    //
    // The name is the right door: a man looking for what the association holds
    // ABOUT HIM reaches for his own name, not for a card below his ledger.
    //
    // ⚠ AND THE DOOR NOW OPENS ONTO A MENU, not onto all four sections stacked.
    //   The facts themselves live one page further in — see portal_sections.dart
    //   — so this asserts the ROUTE to them rather than their contents, and the
    //   test below opens one and reads it.
    await pump(
      tester,
      _detail(
        debt: '20.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-02', 'غير مسدد', '20.00'),
        ],
      ),
    );

    // Nothing at the foot, and his phone nowhere on the page.
    expect(find.text(l.myDetailsTitle), findsNothing);
    expect(find.text('0910000000'), findsNothing);

    await tester.tap(find.text('المهدي العدولي'));
    await tester.pumpAndSettle();

    // The menu: four doors, each named, and none of them opened yet.
    expect(find.text(l.myDetailsTitle), findsOneWidget);
    expect(find.text(l.bankAccountSection), findsOneWidget);
    expect(find.text(l.navOfficials), findsOneWidget);
    expect(find.text(l.navCash), findsOneWidget);
    // The facts are NOT on the menu. That is the whole change: four answers in
    // one column was one long thing to scroll past, not four answers.
    expect(find.text('0910000000'), findsNothing);

    // One tap further, and his own page opens on his own facts.
    await tester.tap(find.text(l.myDetailsTitle));
    await tester.pumpAndSettle();
    expect(find.text('0910000000'), findsOneWidget);
    // And the registration date, which was the old panel's other reason to
    // exist.
    expect(find.text('1 يناير 2026'), findsOneWidget);
    // While the other three are no longer on screen at all — «بخصوصية لكل جزء».
    expect(find.text(l.bankAccountSection), findsNothing);
    expect(find.text(l.navOfficials), findsNothing);
  });

  testWidgets('the ledger fits a Galaxy Note 10 with no sideways scroll', (
    WidgetTester tester,
  ) async {
    // 1080×2280 at 3× = 360×760dp, which is the narrow end of what the
    // association actually carries. The table used to be four FIXED columns
    // needing 448dp, so it scrolled sideways and the balance — the column he
    // opened it for — sat off-screen behind a drag.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(
        _detail(
          debt: '120.00',
          receivables: <Map<String, dynamic>>[
            _due('2026-02', 'غير مسدد', '20.00'),
          ],
        ),
        const <StatementMovement>[
          StatementMovement(
            date: '2026-01-15',
            reference: '2026-01',
            type: 'استحقاق',
            debit: '20.00',
            credit: null,
            balance: '20.00',
            note: 'يناير 2026',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.myStatementSection).last);
    await tester.pumpAndSettle();

    // Every ledger column heading is on screen at once. If any had been pushed
    // outside the viewport by a fixed width, its centre would fall beyond 360.
    // Scoped to the header ROW. "الرصيد" is also the totals strip's third cell
    // now, so an unscoped find.text would match two widgets and getCenter would
    // refuse — and picking one by index would quietly start measuring the wrong
    // one the next time the page grows a card.
    final Finder headRow = find
        .ancestor(
          of: find.text(l.ledgerParticulars),
          matching: find.byType(Row),
        )
        .first;
    Finder head(String label) =>
        find.descendant(of: headRow, matching: find.text(label));

    for (final String heading in <String>[
      l.ledgerParticulars,
      l.ledgerDebit,
      l.ledgerCredit,
      l.ledgerBalance,
    ]) {
      final Offset centre = tester.getCenter(head(heading));
      expect(
        centre.dx,
        inInclusiveRange(0, 360),
        reason: '"$heading" is off a 360dp screen',
      );
    }

    // Centres alone would pass a table hanging half off the edge, so measure
    // the real extent: from the leading edge of the first heading to the
    // trailing edge of the last, the whole header row must lie inside 360dp.
    //
    // (Not "no horizontal Scrollable exists" — a single-line TextField carries
    // one internally for its own cursor, so the search box would fail that
    // check while the table was perfectly fine.)
    final Rect particulars = tester.getRect(head(l.ledgerParticulars));
    final Rect balance = tester.getRect(head(l.ledgerBalance));
    final double left = particulars.left < balance.left
        ? particulars.left
        : balance.left;
    final double right = particulars.right > balance.right
        ? particulars.right
        : balance.right;

    expect(left, greaterThanOrEqualTo(0));
    expect(right, lessThanOrEqualTo(360));
  });

  testWidgets('nothing is stranded under the bottom edge', (
    WidgetTester tester,
  ) async {
    // The portal is not an AppScaffold, so it has no navigation pill — but it
    // does sit above a gesture bar. screenPadding() adds MediaQuery's bottom
    // inset to the scroll padding so the last row can always be scrolled clear
    // of it. On a short screen with a real inset, the final widget must be
    // reachable rather than pinned under the edge.
    tester.view.physicalSize = const Size(1080, 1400);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(
        _detail(
          debt: '20.00',
          receivables: <Map<String, dynamic>>[
            for (int i = 1; i <= 8; i++) _due('2026-0$i', 'غير مسدد', '20.00'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('المهدي العدولي'), 200);
    await tester.pumpAndSettle();

    // The identity panel is the last thing on the page. Fully visible means its
    // bottom edge clears the gesture inset, not merely that it exists.
    final Rect box = tester.getRect(find.text('المهدي العدولي'));
    expect(box.bottom, lessThanOrEqualTo(1400 / 3 - 48));
  });

  testWidgets('the totals strip shows issued − paid = balance', (
    WidgetTester tester,
  ) async {
    // The hero figure is derived, and showing the derivation is what makes it
    // checkable rather than something he has to take on trust.
    await pump(
      tester,
      _detail(
        debt: '120.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-02', 'غير مسدد', '20.00'),
        ],
      ),
    );

    expect(find.text('−'), findsOneWidget);
    expect(find.text('='), findsOneWidget);
    expect(find.text(l.myIssuedTotal), findsOneWidget);
    expect(find.text(l.myPaidTotal), findsOneWidget);
    expect(find.text(l.myRemainingTotal), findsOneWidget);

    // The portal says it in the member's words. "الاستحقاقات المنشأة" is the
    // accounting term and the title of an admin screen; those keys stay, and
    // stay off this page.
    expect(find.text(l.issuedTotal), findsNothing);
    expect(find.text(l.outstandingTotal), findsNothing);
  });

  testWidgets('a short statement carries no search box and no counter', (
    WidgetTester tester,
  ) async {
    // Less on screen, for a reason rather than by taste. A search finds what
    // you cannot see; with three movements all of them are visible, so the box
    // could only ever hide rows the reader is already looking at. The counter
    // is the same argument: "عرض ٣ من ٣" states the obvious and costs a line.
    tester.view.physicalSize = const Size(411, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        _detail(
          debt: '20.00',
          receivables: <Map<String, dynamic>>[
            _due('2026-02', 'غير مسدد', '20.00'),
          ],
        ),
        <StatementMovement>[
          for (int i = 1; i <= 3; i++)
            StatementMovement(
              date: '2026-0$i-15',
              reference: '2026-0$i',
              type: 'استحقاق',
              debit: '20.00',
              credit: null,
              balance: '${i * 20}.00',
              note: 'شهر 2026-0$i',
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.myStatementSection).last);
    await tester.pumpAndSettle();

    expect(find.text(l.ledgerParticulars), findsOneWidget); // the table IS there
    expect(find.byType(TextField), findsNothing);
    expect(find.text(l.statementShowing(3, 3)), findsNothing);
  });

  testWidgets('a four-figure amount stays inside its column', (
    WidgetTester tester,
  ) async {
    // "ولا تجعل البيانات تخرج عن مساحة الشاشة", made mechanical.
    //
    // Four columns on a 360dp phone give each money column about 64dp, and a
    // figure that will not fit has exactly two possible fates: it spills over
    // the column edge, or FittedBox scales it down. Only the second is
    // acceptable on a statement — a clipped amount reads as a DIFFERENT amount.
    //
    // This used to assert the stronger "and it is never scaled at all", which
    // held while مدين and دائن shared one 35% column. Four columns cannot also
    // promise that at a readable size; the arithmetic does not allow it. What
    // is promised instead is what was actually asked for: nothing leaves the
    // screen, and nothing is cut off.
    //
    // 9,840.00 is past anything this association will show: 100/month is 1,200
    // a year, so four figures covers years of arrears.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(
        _detail(
          debt: '9840.00',
          receivables: <Map<String, dynamic>>[
            _due('2026-02', 'غير مسدد', '20.00'),
          ],
        ),
        const <StatementMovement>[
          StatementMovement(
            date: '2026-01-15',
            reference: '2026-01',
            type: 'استحقاق',
            debit: '1025.00',
            credit: null,
            balance: '9840.00',
            note: 'يناير 2026',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.myStatementSection).last);
    await tester.pumpAndSettle();

    // Scoped to the MONEY cells by their own rendered text — the first
    // FittedBox in the tree belongs to a SegmentedButton label, and measuring
    // that instead reports a failure that has nothing to do with the ledger.
    for (final String raw in <String>['1025.00', '9840.00']) {
      // The same figure appears in the hero, the totals strip and the table,
      // so every shrink-to-fit cell carrying it is checked rather than one
      // picked by index — which would silently start measuring a different
      // widget the next time the page gains a card.
      final Finder cells = find.ancestor(
        of: find.text(formatMoney(raw)),
        matching: find.byType(FittedBox),
      );
      expect(cells, findsWidgets, reason: '$raw is not rendered in a money cell');

      for (int i = 0; i < cells.evaluate().length; i++) {
        final Finder cell = cells.at(i);
        final Rect column = tester.getRect(cell);
        // The PAINTED extent, transform and all — which is the thing that
        // either stays inside the column or does not.
        final Rect painted = tester.getRect(
          find.descendant(of: cell, matching: find.text(formatMoney(raw))),
        );

        expect(
          painted.width,
          lessThanOrEqualTo(column.width + 0.5),
          reason:
              '$raw paints ${painted.width.toStringAsFixed(1)}dp inside a '
              '${column.width.toStringAsFixed(1)}dp cell',
        );
        expect(painted.left, greaterThanOrEqualTo(-0.5));
        expect(painted.right, lessThanOrEqualTo(360.5));
      }
    }

    // A RenderFlex that could not fit its children reports through the test
    // framework rather than the console, so an overflow anywhere in the table
    // fails here instead of being a yellow stripe nobody screenshots.
    expect(tester.takeException(), isNull);
  });

  testWidgets('مدين and دائن are separate columns, and only one is filled', (
    WidgetTester tester,
  ) async {
    // The association asked for البيان | مدين | دائن | الرصيد. The two were
    // briefly merged to buy width, with colour carrying the distinction — which
    // works when you read one row across and fails at the thing a statement is
    // for, which is reading a column down.
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      app(
        _detail(
          debt: '100.00',
          receivables: <Map<String, dynamic>>[
            _due('2026-02', 'غير مسدد', '100.00'),
          ],
        ),
        const <StatementMovement>[
          StatementMovement(
            date: '2026-01-15',
            reference: '2026-01',
            type: 'استحقاق',
            debit: '100.00',
            credit: null,
            balance: '100.00',
            note: 'يناير 2026',
          ),
          StatementMovement(
            date: '2026-01-20',
            reference: 'PAY-01',
            type: 'دفعة',
            debit: null,
            credit: '40.00',
            balance: '60.00',
            // What the server now sends for a payment: the METHOD, not the
            // bank's transfer reference, which used to land here as a bare
            // number sitting beside the amount.
            note: 'تحويل مصرفي',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.myStatementSection).last);
    await tester.pumpAndSettle();

    expect(find.text(l.ledgerDebit), findsOneWidget);
    expect(find.text(l.ledgerCredit), findsOneWidget);
    expect(find.text(l.ledgerDebitCredit), findsNothing);

    // A charge fills مدين and leaves دائن ruled, and the receipt does the
    // reverse. Two em dashes and two figures across the two rows.
    expect(find.text('—'), findsNWidgets(2));

    // And the payment line says what it WAS, not the number the bank gave it.
    expect(find.text('تحويل مصرفي'), findsOneWidget);
    expect(find.text('PAY-01'), findsNothing);
  });
}

/// A stub for the unread count, so the portal can be shown with a number on it.
class _StubUnread extends ChatUnread {
  _StubUnread(this._n);
  final int _n;
  @override
  Future<int> build() async => _n;
}

/// ⚠ THE MEMBER HAS NO APP BAR, SO HE HAD NO BELL.
///
/// The portal is deliberately not an AppScaffold — that widget carries the
/// navigation bar and a member has one destination. But the bell rides in that
/// bar, so on the single screen a member ever looks at, the app's only signal
/// that somebody had written to him was invisible: he had to open المحادثات to
/// find out there was a reason to open المحادثات.
///
/// The count therefore rides on the button. Same provider as the staff bell —
/// one source, so a member and the board can never be shown different numbers
/// for the same room.
void _portalUnreadTests() {
  final L l = LAr();

  Widget host(int unread) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      adeelDetailProvider(1).overrideWith(
        (Ref ref) async =>
            _detail(debt: '0.00', receivables: const <Map<String, dynamic>>[]),
      ),
      statementProvider(1).overrideWith(
        (Ref ref) async => const Statement(
          movements: <StatementMovement>[],
          closingBalance: '0.00',
        ),
      ),
      chatUnreadProvider.overrideWith(() => _StubUnread(unread)),
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

  Future<void> open(WidgetTester tester, int unread) async {
    tester.view.physicalSize = const Size(411, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(unread));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing waiting — the button carries no number', (
    WidgetTester tester,
  ) async {
    await open(tester, 0);
    expect(find.text(l.navChat), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('...and three waiting are printed ON the button', (
    WidgetTester tester,
  ) async {
    // A NUMBER and not a dot: «هناك جديد» is half an answer, and the member is
    // the reader least likely to open a room on a hunch.
    await open(tester, 3);
    expect(find.text('3'), findsOneWidget);
  });
}
