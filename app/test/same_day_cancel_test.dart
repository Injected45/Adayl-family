import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/payments_screen.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// «إلغاء وعكس» و«إلغاء الصرف» في يوم العملية فقط (15/09).
///
/// «تجعل هاذين الاجرائين موجودين في نفس تاريخ المعاملة … وبمجرد مايتم تغيير
/// اليوم التالي تختفي … لكي يمنع تغيير اي عملية». The guard is in the database:
/// cancel_payment and cancel_disbursement refuse anything not recorded on
/// today's Tripoli date (RUL09 / RUL17), and the two list views carry
/// `cancellable`, computed by the same test. Proved on a copy of the live
/// ledger: 13 checks, including 23:59 yesterday refused.
///
/// What this file pins is the SCREEN's half: the button follows the server's
/// flag and nothing else.
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

PaymentView _payment({required int id, required bool cancellable}) =>
    PaymentView(
      id: id,
      receiptNo: 'PAY-$id',
      adeelId: 3,
      adeelName: 'هيثم مفتاح',
      adeelCode: 'A-03',
      amount: '100.00',
      method: 'نقداً',
      reference: null,
      receiver: null,
      notes: null,
      bankName: '',
      bankAccountNo: '',
      bankAccountName: '',
      status: 'معتمد',
      paidAt: '2026-09-15T08:00:00Z',
      allocations: const <PaymentAllocationView>[],
      cancellable: cancellable,
    );

DisbursementView _voucher({required int id, required bool cancellable}) =>
    DisbursementView(
      id: id,
      voucherNo: 'EXP-$id',
      amount: '75.00',
      kind: 'جماعي',
      category: 'عزاء',
      method: 'نقداً',
      status: 'معتمد',
      spentAt: '2026-09-15T08:00:00Z',
      cancellable: cancellable,
    );

Future<void> _pump(
  WidgetTester tester, {
  List<PaymentView> payments = const <PaymentView>[],
  List<DisbursementView> vouchers = const <DisbursementView>[],
}) async {
  tester.view.physicalSize = const Size(411, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(_StubAuth.new),
        paymentsProvider.overrideWith((Ref ref) async => payments),
        cashSummaryProvider.overrideWith(
          (Ref ref) async => const CashSummaryView(
            total: '1000.00',
            cash: '1000.00',
            transfer: '0.00',
            today: '0.00',
            month: '0.00',
            year: '0.00',
          ),
        ),
        disbursementsProvider.overrideWith((Ref ref) async => vouchers),
        expenseByCategoryProvider.overrideWith(
          (Ref ref) async => const <ExpenseByCategory>[
            ExpenseByCategory(category: 'عزاء', total: '75.00', count: 1),
          ],
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: const PaymentsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens every folded row on the tab, so a hidden button is hidden by the rule
/// and not merely by a fold.
Future<void> _openRows(WidgetTester tester) async {
  for (final Element e in find.byIcon(Icons.expand_more).evaluate().toList()) {
    await tester.tap(find.byWidget(e.widget).first, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

void main() {
  final L l = LAr();

  group('the wire', () {
    test('cancellable is read from the server, and absent means no', () {
      final Map<String, dynamic> base = <String, dynamic>{
        'id': 1,
        'receiptNo': 'PAY-1',
        'adeelId': 3,
        'amount': '100.00',
        'method': 'نقداً',
        'status': 'معتمد',
        'paidAt': '2026-09-15T08:00:00Z',
      };
      expect(
        PaymentView.fromJson(<String, dynamic>{
          ...base,
          'cancellable': true,
        }).cancellable,
        isTrue,
      );
      expect(PaymentView.fromJson(base).cancellable, isFalse);

      final Map<String, dynamic> v = <String, dynamic>{
        'id': 1,
        'voucherNo': 'EXP-1',
        'amount': '75.00',
        'kind': 'جماعي',
        'category': 'عزاء',
        'method': 'نقداً',
        'status': 'معتمد',
        'spentAt': '2026-09-15T08:00:00Z',
      };
      expect(
        DisbursementView.fromJson(<String, dynamic>{
          ...v,
          'cancellable': true,
        }).cancellable,
        isTrue,
      );
      expect(DisbursementView.fromJson(v).cancellable, isFalse);
    });

    test('⚠ the screen never decides from the handset clock', () {
      final String src = File(
        'lib/features/finance/presentation/payments_screen.dart',
      ).readAsStringSync();
      expect(src, contains('payment.cancellable'));
      expect(src, contains('v.cancellable'));
      expect(src, isNot(contains('DateTime.now()')));
    });
  });

  group('التحصيل', () {
    testWidgets('today\'s receipt offers «إلغاء وعكس»', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        payments: <PaymentView>[_payment(id: 1, cancellable: true)],
      );
      await _openRows(tester);
      expect(find.text(l.cancelAndReverse), findsOneWidget);
    });

    testWidgets('⚠ a receipt from an earlier day does not', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        payments: <PaymentView>[_payment(id: 1, cancellable: false)],
      );
      await _openRows(tester);
      // The card is there — only the reversal is not.
      expect(find.textContaining('هيثم مفتاح'), findsWidgets);
      expect(find.text(l.cancelAndReverse), findsNothing);
    });
  });

  group('الصرف', () {
    Future<void> openTab(WidgetTester tester, bool cancellable) async {
      await _pump(
        tester,
        vouchers: <DisbursementView>[_voucher(id: 1, cancellable: cancellable)],
      );
      await tester.tap(find.text(l.opsDisbursements));
      await tester.pumpAndSettle();
      await _openRows(tester);
    }

    testWidgets('today\'s voucher offers «إلغاء الصرف»', (
      WidgetTester tester,
    ) async {
      await openTab(tester, true);
      expect(find.text('EXP-1'), findsOneWidget);
      expect(find.text(l.cancelDisbursement), findsOneWidget);
    });

    testWidgets('⚠ a voucher from an earlier day does not', (
      WidgetTester tester,
    ) async {
      await openTab(tester, false);
      expect(find.text('EXP-1'), findsOneWidget);
      expect(find.text(l.cancelDisbursement), findsNothing);
    });
  });
}
