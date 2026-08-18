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

/// The treasury screen: one row per SUBSCRIBER, not one per receipt.
///
/// It used to be one row per movement, so a member who paid five times appeared
/// five times and a year of collections across forty men was hundreds of rows
/// of repeated names. The list is now at most as long as the register.
///
/// Two things here are money-correctness rather than layout, and they are the
/// reason this file exists:
///
///   • the grouping key is `adeelId`, never the NAME. The register has no
///     natural key — a second row for the same man is accepted — so folding on
///     the name would add two people's money together under one heading.
///   • a cancelled receipt stays VISIBLE inside the group and stays OUT of its
///     total. Rule 9 keeps voided history on screen; it must not be counted as
///     money the association holds.

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

CashMovementView _mv({
  required int id,
  required int adeelId,
  required String name,
  required String amount,
  String status = 'معتمد',
  String code = 'A-01',
}) => CashMovementView(
  id: id,
  receiptNo: 'PAY-${id.toString().padLeft(2, '0')}',
  adeelName: name,
  adeelId: adeelId,
  adeelCode: code,
  amount: amount,
  method: 'نقداً',
  movementType: 'تحصيل',
  status: status,
  occurredAt: '2026-08-1${id}T09:00:00Z',
);

void main() {
  final L l = LAr();

  Widget app(
    List<CashMovementView> movements, {
    String outstanding = '0.00',
    List<DisbursementView> vouchers = const <DisbursementView>[],
  }) => ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(_StubAuth.new),
          cashMovementsProvider.overrideWith((Ref ref) async => movements),
          // Overridden even when empty. Without it the real provider runs and
          // reaches for a Supabase client that does not exist in a test — it
          // fails into an error panel rather than crashing, which is worse: the
          // assertions still pass and the screen under test is not the screen
          // that ships.
          disbursementsProvider.overrideWith((Ref ref) async => vouchers),
          cashSummaryProvider.overrideWith(
            (Ref ref) async => CashSummaryView(
              total: '700.00',
              cash: '450.00',
              transfer: '250.00',
              today: '0.00',
              month: '700.00',
              year: '700.00',
              outstanding: outstanding,
            ),
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

  Future<void> pump(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(w);
    await tester.pumpAndSettle();
  }

  testWidgets('a man who paid five times appears ONCE', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      app(<CashMovementView>[
        for (int i = 1; i <= 5; i++)
          _mv(id: i, adeelId: 3, name: 'المهدي عبدالله محمد', amount: '100.00'),
        _mv(id: 6, adeelId: 4, name: 'محمد حمد النانقا', amount: '50.00'),
      ]),
    );

    expect(find.text('المهدي عبدالله محمد'), findsOneWidget);
    expect(find.text('محمد حمد النانقا'), findsOneWidget);
    // His five receipts are folded away until the row is opened.
    expect(find.text('PAY-01'), findsNothing);
    expect(find.textContaining(l.receiptCount(5)), findsOneWidget);
  });

  testWidgets('his total is on the closed row, and opening lists the receipts', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      app(<CashMovementView>[
        for (int i = 1; i <= 3; i++)
          _mv(id: i, adeelId: 3, name: 'المهدي عبدالله محمد', amount: '100.00'),
      ]),
    );

    // Answered without opening anything: what has this man paid in.
    expect(find.text(formatMoney('300.00')), findsOneWidget);

    await tester.tap(find.text('المهدي عبدالله محمد'));
    await tester.pumpAndSettle();

    expect(find.text('PAY-01'), findsOneWidget);
    expect(find.text('PAY-03'), findsOneWidget);
  });

  testWidgets('a cancelled receipt is listed but not counted', (
    WidgetTester tester,
  ) async {
    // Rule 9 keeps a voided receipt on screen for ever — it is history, not an
    // embarrassment — and it must not be added to what the association holds.
    await pump(
      tester,
      app(<CashMovementView>[
        _mv(id: 1, adeelId: 3, name: 'المهدي عبدالله محمد', amount: '100.00'),
        _mv(
          id: 2,
          adeelId: 3,
          name: 'المهدي عبدالله محمد',
          amount: '900.00',
          status: 'ملغي',
        ),
      ]),
    );

    expect(find.text(formatMoney('100.00')), findsOneWidget);
    expect(find.text(formatMoney('1000.00')), findsNothing);
    expect(find.textContaining(l.receiptCount(1)), findsOneWidget);

    await tester.tap(find.text('المهدي عبدالله محمد'));
    await tester.pumpAndSettle();
    expect(find.text('PAY-02'), findsOneWidget); // still visible
  });

  testWidgets('two men with the SAME NAME are not merged', (
    WidgetTester tester,
  ) async {
    // The register has no natural key: CLAUDE.md is explicit that a duplicate
    // row is accepted and billed twice. Grouping on the name would show one
    // heading with both men's money added together — the single mistake a
    // treasury screen must not make.
    await pump(
      tester,
      app(<CashMovementView>[
        _mv(
          id: 1,
          adeelId: 7,
          name: 'عبدالله محمد',
          amount: '111.00',
          code: 'A-07',
        ),
        _mv(
          id: 2,
          adeelId: 8,
          name: 'عبدالله محمد',
          amount: '222.00',
          code: 'A-08',
        ),
      ]),
    );

    expect(find.text('عبدالله محمد'), findsNWidgets(2));
    expect(find.text('A-07 • ${l.receiptCount(1)}'), findsOneWidget);
    expect(find.text('A-08 • ${l.receiptCount(1)}'), findsOneWidget);
    expect(find.text(formatMoney('111.00')), findsOneWidget);
    expect(find.text(formatMoney('222.00')), findsOneWidget);
    expect(find.text(formatMoney('333.00')), findsNothing);
  });

  testWidgets('the page leads with ONE figure, not a grid of four', (
    WidgetTester tester,
  ) async {
    // It used to open on four tiles of equal weight — cash in, transfers in,
    // what is owed, and the balance — and only the last answers the question a
    // treasurer opens the page for. The other three are the arithmetic behind
    // it, which is a different question asked afterwards if at all.
    await pump(tester, app(<CashMovementView>[], outstanding: '4900.00'));

    expect(find.text(l.associationBalance), findsOneWidget);
    // The workings are NOT on the page.
    expect(find.text(l.collectedCash), findsNothing);
    expect(find.text(l.collectedTransfer), findsNothing);
    expect(find.text(l.dueFromMembers), findsNothing);
    expect(find.text(formatMoney('4900.00')), findsNothing);
  });

  testWidgets('...and the workings are one tap behind it', (
    WidgetTester tester,
  ) async {
    // Nothing was dropped in the redesign: every label the association named is
    // still there, under the same words. This is the test that says so — a
    // layout change that quietly loses a figure looks identical to one that
    // moves it.
    await pump(tester, app(<CashMovementView>[], outstanding: '4900.00'));

    await tester.tap(find.text(l.associationBalance));
    await tester.pumpAndSettle();

    expect(find.text(l.totalCollected), findsOneWidget);
    expect(find.text(l.collectedCash), findsOneWidget);
    expect(find.text(l.collectedTransfer), findsOneWidget);
    expect(find.text(l.totalDisbursed), findsWidgets);
    expect(find.text(l.dueFromMembers), findsOneWidget);
    expect(find.text(formatMoney('4900.00')), findsOneWidget);

    // "تحصيل السنة" is still gone: in an association's first year it showed the
    // same figure as the total collected, two figures disagreeing about
    // nothing. Its key is gone from the ARB, so it can only be named literally.
    expect(find.text('تحصيل السنة'), findsNothing);
  });

  test('a database with no outstanding column reports zero, not blank', () {
    // v_cash_summary on an unpatched project sends no `outstanding` key. An
    // empty string would parse to null and the tile would render as a figure
    // that failed to load.
    final CashSummaryView old = CashSummaryView.fromJson(<String, dynamic>{
      'total': '700.00',
      'cash': '450.00',
      'transfer': '250.00',
      'today': '0.00',
      'month': '700.00',
      'year': '700.00',
    });
    expect(old.outstanding, '0.00');
  });

  testWidgets('money OUT is listed on the same page, and it is RED', (
    WidgetTester tester,
  ) async {
    // The treasury is one fund and this is the page that describes it. The
    // balance tile already subtracts what went out; until now nothing here
    // showed WHAT, so the screen answered half its own question.
    //
    // The colour is the load-bearing part. On a page where every other figure
    // is money ARRIVING, an outgoing amount in the same green reads as a second
    // collection — direction has to be legible before the number is.
    await pump(
      tester,
      app(
        <CashMovementView>[
          _mv(id: 1, adeelId: 3, name: 'المهدي عبدالله محمد', amount: '100.00'),
        ],
        vouchers: <DisbursementView>[
          const DisbursementView(
            id: 1,
            voucherNo: 'EXP-01',
            amount: '60.00',
            kind: 'جماعي',
            category: 'فطور رمضان',
            method: 'نقداً',
            status: 'معتمد',
            spentAt: '2026-08-15T09:00:00Z',
          ),
        ],
      ),
    );

    expect(find.text(l.opsCollections), findsOneWidget);
    expect(find.text(l.opsDisbursements), findsOneWidget);
    expect(find.text('EXP-01'), findsOneWidget);
    // The heading it was spent under, so a reader knows what the money was for
    // without opening anything.
    expect(find.textContaining('فطور رمضان'), findsOneWidget);

    final Text out = tester.widget<Text>(find.text(formatMoney('60.00')));
    expect(out.style?.color, AppColors.danger);
  });

  testWidgets('a REVERSED voucher is struck through and no longer red', (
    WidgetTester tester,
  ) async {
    // Rule 9 keeps it on the page. But red says "this left the fund", and a
    // cancelled voucher moved nothing — painting it red would overstate what
    // went out by exactly its amount.
    await pump(
      tester,
      app(
        <CashMovementView>[
          _mv(id: 1, adeelId: 3, name: 'المهدي عبدالله محمد', amount: '100.00'),
        ],
        vouchers: <DisbursementView>[
          const DisbursementView(
            id: 2,
            voucherNo: 'EXP-02',
            amount: '900.00',
            kind: 'جماعي',
            category: 'عزاء',
            method: 'نقداً',
            status: 'ملغي',
            spentAt: '2026-08-15T09:00:00Z',
          ),
        ],
      ),
    );

    final Text struck = tester.widget<Text>(find.text(formatMoney('900.00')));
    expect(struck.style?.decoration, TextDecoration.lineThrough);
    expect(struck.style?.color, isNot(AppColors.danger));
  });
}
