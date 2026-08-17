import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/domain/wire_values.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart'
    show AdeelListItem;
import 'package:family_app/features/directory/presentation/providers.dart'
    as directory;
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/disbursement_sheet.dart';
import 'package:family_app/features/finance/presentation/payments_screen.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// الصرف — money leaving the treasury, from the app's side.
///
/// The RULES are all in `register_disbursement`: admin only, no overdraft, a
/// payee taken from the register's own row rather than from the client. None of
/// them is enforced here, and none of these tests pretends otherwise. What they
/// pin is the three places where the SCREEN can quietly contradict the server:
///
///   • the overdraft refusal must be visible BEFORE the round trip, and it must
///     name the balance. A form that lets an admin fill in nine fields and then
///     reports RUL17 has taught him nothing about how much he may spend.
///   • the payee switch must CLEAR what the other mode held. A free name left
///     behind a register pick is a voucher whose two halves disagree, and the
///     server would silently prefer the register — so the screen would be
///     showing one payee and recording another.
///   • the rank on the button. Taking money in is the treasurer's; paying it
///     out was put a rung above even the finance manager, so the disbursement
///     tab must not offer a button the server will refuse.
///
/// And rule 9, outgoing: a cancelled voucher stays on the screen, struck
/// through. It is history, not an embarrassment.

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

CashSummaryView _cash({String balance = '640.00'}) => CashSummaryView(
  total: '700.00',
  cash: '450.00',
  transfer: '250.00',
  today: '0.00',
  month: '700.00',
  year: '700.00',
  outstanding: '4900.00',
  disbursed: '60.00',
  balance: balance,
);

DisbursementView _voucher({
  int id = 1,
  String amount = '60.00',
  String status = 'معتمد',
  // Defaults to a COLLECTIVE voucher, which is the shape with no payee — so a
  // test that forgets to say which kind it means cannot accidentally assert
  // against a name it never set.
  String kind = 'جماعي',
  String category = 'عزاء',
  String payeeName = '',
  String method = 'نقداً',
  int? payeeAdeelId,
  String bankName = '',
  String bankAccountName = '',
  String bankAccountNo = '',
}) => DisbursementView(
  id: id,
  voucherNo: 'EXP-${id.toString().padLeft(6, '0')}',
  amount: amount,
  kind: kind,
  category: category,
  payeeName: payeeName,
  payeeAdeelId: payeeAdeelId,
  method: method,
  status: status,
  spentAt: '2026-08-15T09:00:00Z',
  bankName: bankName,
  bankAccountName: bankAccountName,
  bankAccountNo: bankAccountNo,
);

void main() {
  final L l = LAr();

  // ── The sheet ─────────────────────────────────────────────────────────────

  Widget sheetHost({
    String balance = '640.00',
    List<DisbursementView> history = const <DisbursementView>[],
  }) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
      cashSummaryProvider.overrideWith(
        (Ref ref) async => _cash(balance: balance),
      ),
      disbursementsProvider.overrideWith((Ref ref) async => history),
      expenseByCategoryProvider.overrideWith(
        (Ref ref) async => <ExpenseByCategory>[],
      ),
      directory.adeelsProvider('').overrideWith(
        (Ref ref) async => <AdeelListItem>[
          const AdeelListItem(
            id: 3,
            adeelCode: 'A-0003',
            fullName: 'المهدي عبدالله محمد',
            phone: '',
            age: 51,
            membershipStatus: 'نشط',
            debt: '0.00',
            issued: '0.00',
            monthlyExpected: '20.00',
          ),
        ],
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDisbursementSheet(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );

  /// The sheet is capped at 90% of the viewport and its own fields run well past
  /// a phone's height, so the surface has to be tall enough for the widgets
  /// under test to be laid out at all — a short view finds nothing and every
  /// expectation fails for a reason that has nothing to do with the code.
  Future<void> openSheet(WidgetTester tester, Widget host) async {
    tester.view.physicalSize = const Size(411, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('the treasury is stated before a figure is typed', (
    WidgetTester tester,
  ) async {
    // The alternative is a form that accepts an amount and then refuses it. An
    // admin standing in front of a supplier needs to know what he has BEFORE he
    // commits to a number, not after.
    await openSheet(tester, sheetHost());

    expect(find.text(l.associationBalance), findsOneWidget);
    expect(find.text(formatMoney('640.00')), findsOneWidget);
  });

  testWidgets('spending more than the treasury holds is refused on the spot', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, sheetHost());

    await tester.enterText(
      find.widgetWithText(TextField, l.amount),
      '640.01',
    );
    await tester.pumpAndSettle();

    // The refusal names the balance. "غير مسموح" alone would leave him
    // guessing at the ceiling one attempt at a time.
    expect(find.text(l.overTreasuryBalance(formatMoney('640.00'))), findsOneWidget);

    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmDisbursement),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('spending exactly the balance is allowed', (
    WidgetTester tester,
  ) async {
    // The boundary is INCLUSIVE on the server — it refuses only what exceeds
    // the balance — and an app that stopped a penny short would make the last
    // voucher of a fund impossible to write.
    await openSheet(tester, sheetHost());

    await tester.enterText(find.widgetWithText(TextField, l.amount), '640.00');
    // A collective voucher, which is the shorter of the two forms to complete:
    // a heading and nothing else. The boundary is the point here, not the kind.
    await tester.tap(find.text(l.kindCollective));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpenseCategoryWire.emergency).last);
    await tester.pumpAndSettle();

    // Matched on the message's own PREFIX, split off around a sentinel. The
    // whole sentence with an EMPTY amount substituted in would carry a double
    // space no rendered refusal ever has, so it would find nothing whether the
    // screen was refusing or not — a check that can only pass.
    final String refusal = l.overTreasuryBalance('#').split('#').first;
    expect(find.textContaining(refusal), findsNothing);

    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmDisbursement),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('an amount with no payee cannot be confirmed', (
    WidgetTester tester,
  ) async {
    await openSheet(tester, sheetHost());

    await tester.enterText(find.widgetWithText(TextField, l.amount), '10');
    await tester.pumpAndSettle();

    expect(find.text(l.payeeRequired), findsOneWidget);
    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmDisbursement),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('the kind adds the member question, and switching clears both', (
    WidgetTester tester,
  ) async {
    // Both kinds ask WHAT FOR; only لمشترك also asks WHO. Switching drops
    // whatever was answered — left behind, a member would be sent with a
    // collective voucher, refused by RUL17 and by ck_disb_shape underneath it,
    // and read as the form being broken rather than as a leftover.
    await openSheet(tester, sheetHost());

    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المهدي عبدالله محمد • A-0003').last);
    await tester.pumpAndSettle();
    expect(find.text('المهدي عبدالله محمد • A-0003'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpenseCategoryWire.newborn).last);
    await tester.pumpAndSettle();

    // جماعي drops the member outright — the question is not asked of it.
    await tester.tap(find.text(l.kindCollective));
    await tester.pumpAndSettle();

    expect(find.text('المهدي عبدالله محمد • A-0003'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    // ...and the وجه with it, because مولود is not one a collective voucher may
    // carry. Left selected it would be sent and refused.
    expect(find.text(ExpenseCategoryWire.newborn), findsNothing);
  });

  testWidgets('a collective voucher cannot be confirmed with no heading', (
    WidgetTester tester,
  ) async {
    // Nothing is preselected. Defaulting to فرح would file an unreviewed
    // voucher under a real occasion, and the report would carry it for ever.
    await openSheet(tester, sheetHost());
    await tester.tap(find.text(l.kindCollective));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, l.amount), '10');
    await tester.pumpAndSettle();

    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmDisbursement),
    );
    expect(confirm.onPressed, isNull);
  });

  testWidgets('bank details appear only for a transfer', (
    WidgetTester tester,
  ) async {
    // Cash has no receiving account. Showing the block for it invites an admin
    // to fill in the association's OWN bank, which on an outgoing voucher would
    // read as the money having gone there.
    await openSheet(tester, sheetHost());

    expect(find.widgetWithText(TextField, l.bankNameField), findsNothing);

    await tester.tap(find.text(l.methodTransfer));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, l.bankNameField), findsOneWidget);
    expect(find.widgetWithText(TextField, l.bankAccountNoField), findsOneWidget);
  });

  testWidgets('the bank a payee was paid through before is offered back', (
    WidgetTester tester,
  ) async {
    // The same remembering the collection side has. The association pays the
    // same landlord and the same supplier month after month, and retyping an
    // account number is where a digit goes missing — a mistyped number is the
    // one thing here that makes a voucher impossible to match against the
    // bank's own statement.
    //
    // Scoped to THIS member. The history below also holds a COLLECTIVE
    // voucher's account, and offering that here would be worse than offering
    // nothing: the two pools answer different questions.
    await openSheet(
      tester,
      sheetHost(
        history: <DisbursementView>[
          _voucher(
            id: 1,
            kind: 'لمشترك',
            category: '',
            payeeAdeelId: 3,
            payeeName: 'المهدي عبدالله محمد',
            method: 'تحويل مصرفي',
            bankName: 'المصرف التجاري الوطني',
            bankAccountName: 'علي المهدي',
            bankAccountNo: '0021547',
          ),
          _voucher(
            id: 2,
            method: 'تحويل مصرفي',
            bankName: 'مصرف الوحدة',
            bankAccountName: 'سالم',
            bankAccountNo: '9999999',
          ),
        ],
      ),
    );

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المهدي عبدالله محمد • A-0003').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.methodTransfer));
    await tester.pumpAndSettle();

    // Only the bank offers history yet: the two fields below it are narrowed by
    // what is chosen above, and nothing is.
    expect(find.byIcon(Icons.history), findsOneWidget);
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('المصرف التجاري الوطني'), findsOneWidget);
    // ★ The other supplier's bank is NOT on offer. Suggesting it here would be
    //   worse than suggesting nothing: it invites paying one man into another
    //   man's account.
    expect(find.text('مصرف الوحدة'), findsNothing);

    await tester.tap(find.text('المصرف التجاري الوطني'));
    await tester.pumpAndSettle();

    // Now the name at THAT bank is offered, and picking it leaves exactly one
    // possible account number...
    await tester.tap(find.byIcon(Icons.history).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('علي المهدي'));
    await tester.pumpAndSettle();

    // ...so it fills itself. This is the digit that would otherwise be retyped
    // every month, and the one a voucher cannot be reconciled without.
    final TextField account = tester.widget<TextField>(
      find.widgetWithText(TextField, l.bankAccountNoField),
    );
    expect(account.controller?.text, '0021547');
  });

  testWidgets('every heading the database defines is offered', (
    WidgetTester tester,
  ) async {
    // The dropdown is built from ExpenseCategoryWire, which must stay in step
    // with the expense_category enum. A heading missing here is a heading no
    // voucher can ever be filed under.
    //
    // Six exist and each kind may use five: مولود is a family's and never
    // collective; فطور رمضان is one table for everybody and never one man's.
    // ck_disb_shape refuses the wrong pairing outright, so a picker that
    // offered it would only be inviting a refusal.
    expect(ExpenseCategoryWire.all.length, 6);

    await openSheet(tester, sheetHost());
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    for (final String c in ExpenseCategoryWire.all) {
      final bool offered = c != ExpenseCategoryWire.ramadanIftar;
      expect(
        find.text(c),
        offered ? findsWidgets : findsNothing,
        reason: 'لمشترك: $c',
      );
    }

    await tester.tap(find.text(ExpenseCategoryWire.condolence).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.kindCollective));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    for (final String c in ExpenseCategoryWire.all) {
      final bool offered = c != ExpenseCategoryWire.newborn;
      expect(
        find.text(c),
        offered ? findsWidgets : findsNothing,
        reason: 'جماعي: $c',
      );
    }
  });

  // ── The tab, and who may spend ────────────────────────────────────────────

  Widget screen(AppRole role, List<DisbursementView> vouchers) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(role)),
      paymentsProvider.overrideWith((Ref ref) async => <PaymentView>[]),
      cashSummaryProvider.overrideWith((Ref ref) async => _cash()),
      disbursementsProvider.overrideWith((Ref ref) async => vouchers),
      expenseByCategoryProvider.overrideWith(
        (Ref ref) async => <ExpenseByCategory>[
          const ExpenseByCategory(
            category: 'عزاء',
            total: '60.00',
            count: 1,
          ),
          const ExpenseByCategory(
            category: 'فرح',
            total: '0.00',
            count: 0,
          ),
        ],
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: const PaymentsScreen(),
    ),
  );

  Future<void> openTab(
    WidgetTester tester,
    AppRole role, {
    List<DisbursementView> vouchers = const <DisbursementView>[],
  }) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen(role, vouchers));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.opsDisbursements));
    await tester.pumpAndSettle();
  }

  testWidgets('the two directions live under one screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(screen(AppRole.admin, <DisbursementView>[]));
    await tester.pumpAndSettle();

    expect(find.text(l.navPayments), findsWidgets);
    expect(find.text(l.opsCollections), findsOneWidget);
    expect(find.text(l.opsDisbursements), findsOneWidget);
    // Collections is what opens: it is the daily act, and the one the treasurer
    // — who cannot use the other tab at all — came for.
    expect(find.text(l.registerPayment), findsOneWidget);
    expect(find.text(l.registerDisbursement), findsNothing);
  });

  testWidgets('the button follows the TAB, not the screen', (
    WidgetTester tester,
  ) async {
    await openTab(tester, AppRole.admin);

    // "تسجيل سداد" on the disbursement tab would take money IN while the reader
    // is looking at money going out — the one confusion a two-direction screen
    // exists to prevent.
    expect(find.text(l.registerPayment), findsNothing);
    expect(find.text(l.registerDisbursement), findsOneWidget);
  });

  testWidgets('a finance manager may collect but may NOT spend', (
    WidgetTester tester,
  ) async {
    // A rung above the treasurer and still not enough: the association put
    // paying out above even this role. The RPC refuses him with RUL00 either
    // way; the button is the third layer, never the only one.
    await openTab(tester, AppRole.financeManager);

    expect(find.text(l.registerDisbursement), findsNothing);
    expect(find.text(l.opsDisbursements), findsOneWidget); // he may still READ

    await tester.tap(find.text(l.opsCollections));
    await tester.pumpAndSettle();
    expect(find.text(l.registerPayment), findsOneWidget);
  });

  testWidgets('a cancelled voucher stays on screen, struck through', (
    WidgetTester tester,
  ) async {
    // Rule 9, outgoing. A voucher that could disappear is a treasury that can
    // be quietly rebalanced; the money is already back in the balance because
    // every total filters on status.
    await openTab(
      tester,
      AppRole.admin,
      vouchers: <DisbursementView>[
        _voucher(id: 1, amount: '60.00'),
        _voucher(id: 2, amount: '900.00', status: 'ملغي'),
      ],
    );

    expect(find.text('EXP-000002'), findsOneWidget);
    expect(find.text(l.voided), findsOneWidget);

    final Text struck = tester.widget<Text>(find.text('EXP-000002'));
    expect(struck.style?.decoration, TextDecoration.lineThrough);

    // ...and it offers no reversal, because it is already reversed.
    expect(find.text(l.cancelDisbursement), findsOneWidget); // only EXP-000001
  });

  testWidgets('a heading nothing was spent on is not listed on the phone', (
    WidgetTester tester,
  ) async {
    // v_expense_by_category returns every heading so a REPORT can state the
    // zero. A summary strip on a phone that listed them all to say most are
    // empty would bury the one that is not.
    await openTab(
      tester,
      AppRole.admin,
      vouchers: <DisbursementView>[_voucher()],
    );

    expect(find.text(l.expenseByCategory), findsOneWidget);
    expect(find.text('عزاء'), findsWidgets);
    expect(find.text('فرح'), findsNothing);
  });

  testWidgets('an empty ledger says so rather than showing a blank page', (
    WidgetTester tester,
  ) async {
    await openTab(tester, AppRole.admin);

    expect(find.text(l.noDisbursements), findsOneWidget);
    expect(find.text(l.disbursementsIntro), findsOneWidget);
  });

  // ── Wire parsing ──────────────────────────────────────────────────────────

  test('a voucher parses from the shape v_disbursements actually sends', () {
    // Money is TEXT end to end. A numeric column serialised as a bare JSON
    // number would arrive as a double and put binary floating point in a
    // treasury; the view casts, and this is the assertion that the model reads
    // what the view writes.
    final DisbursementView v = DisbursementView.fromJson(<String, dynamic>{
      'id': 4,
      'voucherNo': 'EXP-000004',
      'amount': '125.50',
      'category': 'علاج ومرض',
      'payeeAdeelId': 3,
      'payeeName': 'المهدي عبدالله محمد',
      'payeeCode': 'A-0003',
      'method': 'تحويل مصرفي',
      'reference': 'TRF-77',
      'bankName': 'مصرف الجمهورية',
      'bankAccountNo': '0011',
      'bankAccountName': 'المهدي',
      'handedBy': 'أمين الصندوق',
      'note': 'علاج',
      'status': 'معتمد',
      'spentAt': '2026-08-15T09:00:00Z',
    });

    expect(v.amount, '125.50');
    expect(v.amount, isA<String>());
    expect(v.payeeAdeelId, 3);
    expect(v.cancelled, isFalse);
    expect(_voucher(status: 'ملغي').cancelled, isTrue);
  });
}
