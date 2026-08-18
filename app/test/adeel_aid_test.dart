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

/// ما صُرف للمشترك — what the association GAVE one man.
///
/// ⚠ THE RULE THIS SCREEN EXISTS TO KEEP, and the one these tests are really
/// about: الجمعية خيرية. Aid paid to a member is NOT deducted from his
/// subscription. His statement stays a record of dues charged and dues paid,
/// and this page is a separate answer to a separate question.
///
/// The database makes that structural — a voucher writes no receivable, no
/// payment and no allocation, and `api_adeel_statement` merges exactly those two
/// tables — and `supabase/tests/67_disbursement.sql` proves it there, on both
/// sides, as staff and as the member himself. What CANNOT be proved there is the
/// screen: a layout that puts «ما استلمه» beside «ما عليه» invites the reader to
/// subtract even when the database never does. So what is pinned here is that
/// the page states the rule, and that every figure on it comes from the server
/// rather than from arithmetic done in Dart.

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

DisbursementView _voucher({
  int id = 1,
  String amount = '30.00',
  String category = 'مولود',
  String status = 'معتمد',
  String spentAt = '2026-08-15T09:00:00Z',
}) => DisbursementView(
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
);

AdeelAid _aid({
  String total = '45.00',
  int count = 2,
  String firstAt = '2026-03-02',
  String lastAt = '2026-08-15',
  List<ExpenseByCategory>? byCategory,
  List<AidByYear>? byYear,
  List<DisbursementView>? vouchers,
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
        ExpenseByCategory(category: 'مولود', total: '30.00', count: 1),
        ExpenseByCategory(category: 'عزاء', total: '15.00', count: 1),
      ],
  byYear:
      byYear ??
      const <AidByYear>[
        AidByYear(year: '2026', total: '45.00', count: 2),
      ],
  vouchers:
      vouchers ??
      <DisbursementView>[
        _voucher(id: 1, amount: '30.00', category: 'مولود'),
        _voucher(id: 2, amount: '15.00', category: 'عزاء'),
      ],
);

void main() {
  final L l = LAr();

  Widget host(AdeelAid aid) => ProviderScope(
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
      home: const AdeelAidScreen(adeelId: 1),
    ),
  );

  Future<void> open(WidgetTester tester, AdeelAid aid) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(aid));
    await tester.pumpAndSettle();
  }

  // ── The model ─────────────────────────────────────────────────────────────

  test('the aid page parses the shape api_adeel_aid actually sends', () {
    // Keys copied from the function body, not invented here. Rename one in SQL
    // and this stops parsing before the app ever runs.
    final AdeelAid aid = AdeelAid.fromJson(<String, dynamic>{
      'adeelId': 1,
      'adeelCode': 'A-0001',
      'adeelName': 'محمد العدولي',
      'total': '45.00',
      'count': 2,
      'firstAt': '2026-03-02',
      'lastAt': '2026-08-15',
      'byCategory': <dynamic>[
        <String, dynamic>{'category': 'مولود', 'total': '30.00', 'count': 1},
      ],
      'byYear': <dynamic>[
        <String, dynamic>{'year': '2026', 'total': '45.00', 'count': 2},
      ],
      'vouchers': <dynamic>[
        <String, dynamic>{
          'id': 7,
          'voucherNo': 'EXP-000007',
          'amount': '30.00',
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
          'note': '',
          'status': 'معتمد',
          'spentAt': '2026-08-15T09:00:00Z',
        },
      ],
    });

    expect(aid.total, '45.00');
    expect(aid.count, 2);
    expect(aid.byCategory.single.category, 'مولود');
    expect(aid.byYear.single.year, '2026');
    expect(aid.vouchers.single.voucherNo, 'EXP-000007');
    // Money is the exact decimal STRING the server sent, never a double. It is
    // asserted rather than assumed because a `num` here would round the
    // association's charity on its way to a screen.
    expect(aid.total, isA<String>());
    expect(aid.vouchers.single.amount, isA<String>());
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
    expect(none.lastAt, '');
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

  testWidgets('the headline total is the SERVER\'s, not a sum of the rows', (
    WidgetTester tester,
  ) async {
    // The figures deliberately disagree: the vouchers add to 45.00 and the
    // server says 45.00 only because it excluded a cancelled one worth 900.
    // Anything that re-added the list in Dart would print 945.00 here — which
    // is exactly the class of bug the money-as-text rule exists to prevent.
    await open(
      tester,
      _aid(
        vouchers: <DisbursementView>[
          _voucher(id: 1, amount: '30.00', category: 'مولود'),
          _voucher(id: 2, amount: '15.00', category: 'عزاء'),
          _voucher(id: 3, amount: '900.00', status: 'ملغي'),
        ],
      ),
    );

    expect(find.text(formatMoney('45.00')), findsWidgets);
    expect(find.text(formatMoney('945.00')), findsNothing);
  });

  testWidgets('a reversed voucher stays listed, struck through', (
    WidgetTester tester,
  ) async {
    // Rule 9, outgoing, on the recipient's page too: history is not an
    // embarrassment. Its amount is already out of the total above.
    await open(
      tester,
      _aid(
        vouchers: <DisbursementView>[
          _voucher(id: 1, amount: '30.00'),
          _voucher(id: 2, amount: '900.00', status: 'ملغي'),
        ],
      ),
    );

    expect(find.text('EXP-000002'), findsOneWidget);
    expect(find.text(l.voided), findsOneWidget);
    final Text struck = tester.widget<Text>(find.text('EXP-000002'));
    expect(struck.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('the occasions are named, which is what was asked for', (
    WidgetTester tester,
  ) async {
    // «ما هي المناسبات التي صُرفت له» — the register of names cannot answer it,
    // which is why every voucher carries a وجه and why this panel exists.
    await open(tester, _aid());

    expect(find.text(l.aidByCategory), findsOneWidget);
    expect(find.text('مولود'), findsWidgets);
    expect(find.text('عزاء'), findsWidgets);
  });

  testWidgets('one year of aid gets no by-year panel', (
    WidgetTester tester,
  ) async {
    // A single-row "by year" restates the headline and says nothing. It earns
    // its place only once there are years to compare.
    //
    // ONE voucher in both halves, deliberately. A ListView does not build what
    // is off-screen, so on a long page `findsNothing` would pass for a panel
    // that exists and is merely further down — the assertion would be true for
    // the wrong reason, and would go on being true after the feature broke.
    // A page short enough to fit the test viewport removes that entirely.
    await open(tester, _aid(count: 1, vouchers: <DisbursementView>[_voucher()]));
    expect(find.text(l.aidByYear), findsNothing);
    // The panel that IS expected on the same page, so "found nothing" cannot be
    // "rendered nothing".
    expect(find.text(l.aidByCategory), findsOneWidget);
  });

  testWidgets('...and appears once there are years to compare', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      _aid(
        count: 1,
        vouchers: <DisbursementView>[_voucher()],
        byYear: const <AidByYear>[
          AidByYear(year: '2026', total: '30.00', count: 1),
          AidByYear(year: '2025', total: '15.00', count: 1),
        ],
      ),
    );
    expect(find.text(l.aidByYear), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
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
        vouchers: <DisbursementView>[],
      ),
    );

    expect(find.text(l.noAid), findsOneWidget);
    // The rule still shows: "nothing yet" is exactly when a reader wonders
    // whether aid would have come off his dues.
    expect(find.text(l.aidNotDeductedNote), findsOneWidget);
  });
}
