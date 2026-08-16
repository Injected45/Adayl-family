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
import 'package:flutter/rendering.dart';
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
      adeelCode: 'A-0001',
    ),
  );
}

AdeelDetail _detail({
  required String debt,
  required List<Map<String, dynamic>> receivables,
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
      'adeelCode': 'A-0001',
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
      localizationsDelegates: L.localizationsDelegates,
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

  testWidgets('the balance is the first thing on the page', (
    WidgetTester tester,
  ) async {
    // Not decoration: the hero exists so he does not have to add tiles to learn
    // what he owes. If the identity card ever climbs back above it, this fails.
    await pump(
      tester,
      _detail(
        debt: '120.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-02', 'غير مسدد', '20.00'),
        ],
      ),
    );

    final double heroY = tester.getTopLeft(find.text(l.myBalanceNow)).dy;
    final double nameY = tester.getTopLeft(find.text('المهدي العدولي')).dy;
    expect(heroY, lessThan(nameY));
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
    expect(find.text(l.movementBalance), findsNothing); // ledger head column

    await tester.tap(find.text(l.myStatementSection).last);
    await tester.pumpAndSettle();

    expect(find.text('شهر 2026-02'), findsNothing);
  });

  testWidgets('identity is collapsed until asked for', (
    WidgetTester tester,
  ) async {
    // His phone number is confirmation, not information — he settled who he is
    // when he redeemed the code. It stays reachable, just not first.
    await pump(
      tester,
      _detail(
        debt: '20.00',
        receivables: <Map<String, dynamic>>[
          _due('2026-02', 'غير مسدد', '20.00'),
        ],
      ),
    );

    expect(find.text('المهدي العدولي'), findsOneWidget); // the tile title
    expect(find.text('0910000000'), findsNothing);

    await tester.tap(find.text('المهدي العدولي'));
    await tester.pumpAndSettle();

    expect(find.text('0910000000'), findsOneWidget);
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
    for (final String heading in <String>[
      l.ledgerParticulars,
      l.ledgerDebitCredit,
      l.ledgerBalance,
    ]) {
      final Offset centre = tester.getCenter(find.text(heading));
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
    final Rect particulars = tester.getRect(find.text(l.ledgerParticulars));
    final Rect balance = tester.getRect(find.text(l.ledgerBalance));
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
    expect(find.text(l.issuedTotal), findsOneWidget);
    expect(find.text(l.collectedTotal), findsOneWidget);
    expect(find.text(l.outstandingTotal), findsOneWidget);
  });

  testWidgets('a four-figure amount fits its column without being shrunk', (
    WidgetTester tester,
  ) async {
    // This is the reason the ledger runs smaller than the rest of the portal.
    //
    // Each money column is 22% of a 360dp screen. If the common case still
    // overflows it, FittedBox rescues the cell — nothing looks broken — but
    // that one cell renders smaller than the ones above and below it, and a
    // column of figures at inconsistent sizes is precisely what is hard to read
    // down. Uniformly a point smaller beats occasionally a point smaller.
    //
    // 9,840.00 is past anything this association will show: 20/month is 240 a
    // year, so four figures covers a lifetime of arrears.
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
      final Finder cell = find.ancestor(
        of: find.text(formatMoney(raw)),
        matching: find.byType(FittedBox),
      );
      expect(cell, findsWidgets, reason: '$raw is not rendered in a money cell');

      final RenderBox box = tester.renderObject<RenderBox>(cell.first);
      final RenderBox child =
          (box as RenderProxyBox).child!;

      // A FittedBox only scales when the child cannot fit. Comparing the two
      // is what distinguishes "it fits" from "it was made to fit" — and the
      // second is what puts one row of a figures column at a different size
      // from its neighbours.
      expect(
        child.size.width,
        lessThanOrEqualTo(box.size.width + 0.5),
        reason:
            '$raw needs ${child.size.width.toStringAsFixed(1)}dp in a '
            '${box.size.width.toStringAsFixed(1)}dp column — the ledger type '
            'is still too large for a four-figure amount',
      );
    }
  });
}
