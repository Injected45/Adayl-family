import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/cash_screen.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A member's treasury card holds BOTH directions, told apart by eye.
///
/// What he paid the association and what the association gave him are the two
/// halves of his relationship with the fund, and until now they lived on
/// different parts of the screen — his receipts under his name, his vouchers in
/// an ungrouped list at the foot. Answering «كم دفع وكم صُرف له» meant reading
/// two places and holding one in your head.
///
/// Now one card, and the row itself carries the direction twice over:
///
///   • COLOUR — green in, red out;
///   • ARROW  — south_west in, north_east out, the same two icons the التحصيل
///     and الصرف tabs carry, so the vocabulary is one across the app.
///
/// Two signals rather than one because colour alone fails for a reader who
/// cannot separate red from green, and this is the distinction the whole card
/// exists to make.
///
/// ⚠ AND THEY ARE NEVER NETTED. الجمعية خيرية: aid is not a credit against a
///   subscription. The card's figure is what he PAID, alone; the vouchers are
///   announced by a COUNT, not an amount, precisely so no two money figures sit
///   on one row inviting the reader to subtract. The database makes this
///   structural — a voucher writes no receivable, no payment and no allocation
///   — and this file keeps the screen from implying otherwise.
///
/// ⚠ AND NO VOUCHER APPEARS TWICE. One made out to a member is in his card and
///   NOT in the collective list; فطور رمضان has no payee, so it is only ever in
///   the collective list. Duplication would let one payment be counted twice by
///   eye on a single screen.

class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000f1',
      email: 'admin@fam.test',
      displayName: 'المهدي',
      role: AppRole.admin,
      status: AccountStatus.approved,
    ),
  );
}

CashMovementView _receipt({
  required int id,
  required String amount,
  String status = 'معتمد',
}) => CashMovementView(
  id: id,
  receiptNo: 'PAY-0$id',
  adeelName: 'المهدي عبدالله',
  adeelId: 7,
  adeelCode: 'A-07',
  amount: amount,
  method: 'نقداً',
  movementType: 'تحصيل',
  status: status,
  occurredAt: '2026-08-15T09:00:00Z',
);

DisbursementView _voucher({
  required int id,
  required String amount,
  int? payee = 7,
  String status = 'معتمد',
  String category = 'مولود',
}) => DisbursementView(
  id: id,
  voucherNo: 'EXP-0$id',
  amount: amount,
  kind: payee == null ? 'جماعي' : 'لمشترك',
  category: category,
  method: 'نقداً',
  status: status,
  spentAt: '2026-08-16T09:00:00Z',
  payeeName: payee == null ? '' : 'المهدي عبدالله',
  payeeAdeelId: payee,
  payeeCode: payee == null ? '' : 'A-07',
);

/// What `v_member_net` returns for this data — every member who appears, his
/// live receipts minus the live vouchers made out to him, and the total. Test
/// arithmetic in whole hundredths, standing in for the server.
List<MemberNet> _netFor(
  List<CashMovementView> receipts,
  List<DisbursementView> vouchers,
) {
  int cents(String a) => (double.parse(a) * 100).round();
  String money(int c) =>
      '${c < 0 ? '-' : ''}${c.abs() ~/ 100}.${(c.abs() % 100).toString().padLeft(2, '0')}';
  final Map<int, (String, String)> who = <int, (String, String)>{};
  final Map<int, int> net = <int, int>{};
  for (final CashMovementView m in receipts) {
    who[m.adeelId] = (m.adeelCode, m.adeelName);
    net[m.adeelId] =
        (net[m.adeelId] ?? 0) + (m.status == 'ملغي' ? 0 : cents(m.amount));
  }
  for (final DisbursementView v in vouchers) {
    final int? id = v.payeeAdeelId;
    if (id == null) continue;
    who.putIfAbsent(id, () => (v.payeeCode, v.payeeName));
    net[id] = (net[id] ?? 0) - (v.cancelled ? 0 : cents(v.amount));
  }
  final int total = net.values.fold<int>(0, (int a, int b) => a + b);
  final List<int> ids = who.keys.toList()
    ..sort((int a, int b) => who[a]!.$1.compareTo(who[b]!.$1));
  return <MemberNet>[
    for (final int id in ids)
      MemberNet(
        adeelId: id,
        adeelCode: who[id]!.$1,
        adeelName: who[id]!.$2,
        paid: '0.00',
        received: '0.00',
        net: money(net[id] ?? 0),
        totalNet: money(total),
      ),
  ];
}

/// «حركة العدايل» is folded since 15/09; every card is inside it.
Future<void> _openMembers(WidgetTester tester) async {
  await tester.tap(find.text(LAr().membersMovementTitle));
  await tester.pumpAndSettle();
}

void main() {
  final L l = LAr();

  Widget host({
    required List<CashMovementView> receipts,
    required List<DisbursementView> vouchers,
  }) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      cashSummaryProvider.overrideWith(
        (Ref ref) async => const CashSummaryView(
          total: '300.00',
          cash: '300.00',
          transfer: '0.00',
          today: '0.00',
          month: '300.00',
          year: '300.00',
        ),
      ),
      cashMovementsProvider.overrideWith((Ref ref) async => receipts),
      disbursementsProvider.overrideWith((Ref ref) async => vouchers),
      memberNetProvider.overrideWith(
        (Ref ref) async => _netFor(receipts, vouchers),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const CashScreen(),
    ),
  );

  Future<void> open(
    WidgetTester tester, {
    required List<CashMovementView> receipts,
    required List<DisbursementView> vouchers,
  }) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(receipts: receipts, vouchers: vouchers));
    await tester.pumpAndSettle();
    await _openMembers(tester);
    await tester.tap(find.text('المهدي عبدالله').first);
    await tester.pumpAndSettle();
  }

  Color? colourOf(WidgetTester tester, String money) =>
      tester.widget<Text>(find.text(formatMoney(money))).style?.color;

  /// Scoped INSIDE the member's card. `Icons.north_east` is also the empty-state
  /// icon of the collective list at the foot of the page, so an unscoped
  /// `findsOneWidget` would be measuring whichever of the two happened to be on
  /// screen rather than the arrow this file is about.
  Finder iconInCard(IconData icon) => find.descendant(
    of: find.byType(ExpansionTile),
    matching: find.byIcon(icon),
  );

  /// TWO live receipts on purpose, so the card's total (130) equals neither row.
  /// With one receipt the total and the row carry the same string and a finder
  /// cannot say which it matched — the assertion would pass while proving
  /// nothing about the row.
  List<CashMovementView> paid() => <CashMovementView>[
    _receipt(id: 1, amount: '100.00'),
    _receipt(id: 2, amount: '30.00'),
  ];

  testWidgets('what he PAID is green, with an inward arrow', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      receipts: paid(),
      vouchers: <DisbursementView>[_voucher(id: 1, amount: '250.00')],
    );

    expect(colourOf(tester, '100.00'), AppColors.success);
    expect(iconInCard(Icons.south_west), findsNWidgets(2));
  });

  testWidgets('...and what was SPENT ON HIM is red, with an outward arrow', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      receipts: paid(),
      vouchers: <DisbursementView>[_voucher(id: 1, amount: '250.00')],
    );

    expect(find.text('EXP-01'), findsOneWidget);
    expect(colourOf(tester, '250.00'), AppColors.danger);
    expect(iconInCard(Icons.north_east), findsOneWidget);
  });

  testWidgets('a CANCELLED receipt turns red and is struck through', (
    WidgetTester tester,
  ) async {
    // Money that came in and went back out. Grey read as "inactive", which is
    // not what a reversal is — it is an entry that still has to be accounted
    // for, and its direction on the day was outward.
    await open(
      tester,
      receipts: <CashMovementView>[
        _receipt(id: 1, amount: '100.00'),
        _receipt(id: 2, amount: '30.00'),
        _receipt(id: 3, amount: '40.00', status: 'ملغي'),
      ],
      vouchers: <DisbursementView>[],
    );

    final Text voided = tester.widget<Text>(find.text(formatMoney('40.00')));
    expect(voided.style?.color, AppColors.danger);
    expect(voided.style?.decoration, TextDecoration.lineThrough);
    // The live one beside it is untouched — the pair that proves the colour is
    // reading the status and not simply painting the list.
    expect(colourOf(tester, '100.00'), AppColors.success);
  });

  testWidgets('the closed card counts its vouchers and shows his NET', (
    WidgetTester tester,
  ) async {
    // Since 15/09 the card reads the way «الجدوى» reads him: paid − received,
    // with the words saying which way it runs. The figure is the SERVER's net
    // (v_member_net), and it is a ledger reading — no statement, receivable or
    // payment is touched by it.
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        receipts: paid(),
        vouchers: <DisbursementView>[
          _voucher(id: 1, amount: '250.00'),
          _voucher(id: 2, amount: '90.00'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await _openMembers(tester);

    expect(find.textContaining(l.voucherCount(2)), findsOneWidget);
    // Paid 100 + 30, given 250 + 90: «رصيد مستحق عليه 210» — on his row and,
    // with one member, on the heading too. The sign is carried by the words,
    // never printed as a minus.
    expect(find.text(l.memberNetOwedByHim), findsOneWidget);
    expect(find.text(formatMoney('210.00')), findsNWidgets(2));
    expect(find.text(formatMoney('-210.00')), findsNothing);
    expect(find.text(formatMoney('470.00')), findsNothing); // never summed
  });

  testWidgets('a member voucher is in HIS card and NOT in the collective list', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      receipts: paid(),
      vouchers: <DisbursementView>[
        _voucher(id: 1, amount: '250.00'),
        _voucher(id: 2, amount: '75.00', payee: null, category: 'فطور رمضان'),
      ],
    );

    // Exactly once each: the member's under his name, the collective one under
    // its own heading. A voucher on screen twice can be counted twice.
    expect(find.text('EXP-01'), findsOneWidget);
    expect(find.text('EXP-02'), findsOneWidget);
    expect(find.text(l.kindCollective), findsOneWidget);
    expect(colourOf(tester, '75.00'), AppColors.danger);
  });

  testWidgets('a man who was only GIVEN something still gets a card', (
    WidgetTester tester,
  ) async {
    // He has no receipts at all. Leaving him off would make "he received
    // nothing" and "he is not on this screen" look identical.
    await open(
      tester,
      receipts: <CashMovementView>[_receipt(id: 1, amount: '100.00')],
      vouchers: <DisbursementView>[
        _voucher(id: 1, amount: '250.00'),
        DisbursementView(
          id: 3,
          voucherNo: 'EXP-03',
          amount: '500.00',
          kind: 'لمشترك',
          category: 'فرح',
          method: 'نقداً',
          status: 'معتمد',
          spentAt: '2026-08-17T09:00:00Z',
          payeeName: 'سالم أحمد',
          payeeAdeelId: 9,
          payeeCode: 'A-09',
        ),
      ],
    );

    expect(find.text('سالم أحمد'), findsOneWidget);
    // And his card reads zero PAID rather than borrowing anyone else's figure.
    expect(find.text(l.receiptCount(0)), findsNothing);
  });
}
