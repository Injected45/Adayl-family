import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/domain/wire_values.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/directory/domain/models.dart'
    show AdeelListItem, Official;
import 'package:family_app/features/directory/presentation/providers.dart'
    as directory;
import 'package:family_app/features/finance/data/finance_repository.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/disbursement_sheet.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// «المُسلِّم» في تسجيل الصرف = أمين الصندوق، تلقائيًّا (15/09).
///
/// «يظهر اسم امين الصندوق بشكل الي لانه هو المخول بالعملية». The name comes
/// from the officials in settings; the field is shown, not typed, and the
/// voucher is saved with exactly that name.
class _FakeFinance implements FinanceRepository {
  String? handedBy;
  bool called = false;

  @override
  Future<Map<String, dynamic>> registerDisbursement({
    required String amount,
    required String kind,
    required String method,
    String? category,
    int? payeeAdeelId,
    String? reference,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNo,
    String? handedBy,
    String? note,
  }) async {
    called = true;
    this.handedBy = handedBy;
    return <String, dynamic>{'voucherNo': 'EXP-62', 'balanceAfter': '600.00'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_FakeFinance repo, {required String treasurer}) => ProviderScope(
  overrides: <Override>[
    financeRepositoryProvider.overrideWithValue(repo),
    cashSummaryProvider.overrideWith(
      (Ref ref) async => const CashSummaryView(
        total: '700.00',
        cash: '700.00',
        transfer: '0.00',
        today: '0.00',
        month: '0.00',
        year: '0.00',
        balance: '640.00',
      ),
    ),
    disbursementsProvider.overrideWith((Ref ref) async => <DisbursementView>[]),
    expenseByCategoryProvider.overrideWith(
      (Ref ref) async => <ExpenseByCategory>[],
    ),
    directory
        .adeelsProvider('')
        .overrideWith((Ref ref) async => <AdeelListItem>[]),
    directory.officialsProvider.overrideWith(
      (Ref ref) async => <Official>[
        Official(role: OfficialRoleWire.treasurer, name: treasurer, phone: ''),
        const Official(
          role: OfficialRoleWire.financeManager,
          name: 'مدير المالية',
          phone: '',
        ),
      ],
    ),
  ],
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('ar'),
    localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
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

Future<void> _open(WidgetTester tester, Widget host) async {
  tester.view.physicalSize = const Size(411, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host);
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  final L l = LAr();

  testWidgets('the treasurer\'s name is shown, and there is nothing to type', (
    WidgetTester tester,
  ) async {
    await _open(tester, _host(_FakeFinance(), treasurer: 'محمد حمد المانجا'));

    expect(find.text('محمد حمد المانجا'), findsOneWidget);
    expect(find.text(l.handedBy), findsOneWidget);
    expect(find.widgetWithText(TextField, l.handedBy), findsNothing);
    // The finance manager is not the one handing money over.
    expect(find.text('مدير المالية'), findsNothing);
  });

  testWidgets('⚠ the voucher is saved with the treasurer as المُسلِّم', (
    WidgetTester tester,
  ) async {
    final _FakeFinance repo = _FakeFinance();
    await _open(tester, _host(repo, treasurer: '  محمد حمد المانجا  '));

    await tester.enterText(find.widgetWithText(TextField, l.amount), '40.00');
    await tester.tap(find.text(l.kindCollectiveForm));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ExpenseCategoryWire.emergency).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l.confirmDisbursement));
    await tester.pumpAndSettle();

    expect(repo.called, isTrue);
    expect(repo.handedBy, 'محمد حمد المانجا');
  });

  testWidgets('with no treasurer set, المُسلِّم stays a box to type into', (
    WidgetTester tester,
  ) async {
    await _open(tester, _host(_FakeFinance(), treasurer: ''));
    expect(find.widgetWithText(TextField, l.handedBy), findsOneWidget);
  });
}
