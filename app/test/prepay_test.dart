import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/features/finance/presentation/payment_sheet.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// عهدة: money taken from a member BEFORE he owes anything.
///
/// The association takes a year up front and lets the monthly close eat into
/// it. The database has supported that since rule 7 was relaxed — the surplus
/// is `Σ payments − Σ allocations`, and `generate_period` calls
/// `settle_from_credit` per عديل the instant it raises his receivable.
///
/// The SHEET had not caught up. Three leftovers from the system that could not
/// hold money it had not earned:
///
///   • `canSubmit` required `debt > 0`   → a man who owed nothing was refused;
///   • `canSubmit` required `amount <= debt` → ALL overpayment was refused, which
///     also made `_creditNotice` unreachable: it renders only when the amount
///     exceeds the debt, exactly the case the button was disabled in. The app
///     explained the surplus and refused to record it in the same breath;
///   • the amount field itself was `enabled: … && debt > 0`.
///
/// None of them reported anything. The button was simply grey.
///
/// The fourth was quieter still: this was the ONLY numeric field in the app
/// without [ArabicDigitsFormatter], and a `FilteringTextInputFormatter` above
/// it does not reject ٠١٢٣٤٥٦٧٨٩ — it swallows them. Typing ٦٠ left the box
/// empty with nothing on screen to explain why.

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

AdeelListItem _adeel({required String debt}) =>
    AdeelListItem.fromJson(<String, dynamic>{
      'id': 5,
      'adeelCode': 'A-05',
      'fullName': 'مشترك العهدة',
      'phone': '',
      'membershipStatus': 'نشط',
      'debt': debt,
      'paid': '0.00',
      'issued': debt,
      'monthlyExpected': '20.00',
    });

void main() {
  final L l = LAr();

  Widget host({required String debt}) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      adeelSearchProvider.overrideWith((Ref ref) => ''),
      adeelsProvider('').overrideWith(
        (Ref ref) async => <AdeelListItem>[_adeel(debt: debt)],
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
              onPressed: () => showPaymentSheet(context, adeelId: 5),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, {required String debt}) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(debt: debt));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// The amount box, whatever else is on the sheet.
  Finder amountField() => find.widgetWithText(TextField, l.amount);

  testWidgets('a member who owes NOTHING can still be taken money from', (
    WidgetTester tester,
  ) async {
    await open(tester, debt: '0.00');

    final TextField box = tester.widget<TextField>(amountField());
    expect(box.enabled, isTrue, reason: 'العهدة تُودَع لمن لا التزام عليه');

    await tester.enterText(amountField(), '60');
    await tester.pumpAndSettle();

    // The confirm button is live. This is the assertion that was false before:
    // the sheet opened, accepted nothing, and said nothing.
    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmPayment),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('...and the sheet says where the money is going', (
    WidgetTester tester,
  ) async {
    // `creditNotice` was unreachable code. It renders only when the amount
    // exceeds the debt — which was exactly when submission was blocked.
    await open(tester, debt: '0.00');
    await tester.enterText(amountField(), '60');
    await tester.pumpAndSettle();

    expect(find.text(l.creditNotice(formatMoney('60.00'))), findsOneWidget);
  });

  testWidgets('paying MORE than is owed is allowed, and the surplus is named', (
    WidgetTester tester,
  ) async {
    // 20 owed, 60 handed over: 40 is credit. The old `amount <= debt` refused
    // this outright, so a man settling a year in one visit had to be entered as
    // twelve separate receipts — or turned away.
    await open(tester, debt: '20.00');
    await tester.enterText(amountField(), '60');
    await tester.pumpAndSettle();

    expect(find.text(l.creditNotice(formatMoney('40.00'))), findsOneWidget);

    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmPayment),
    );
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('zero and blank are still refused — the rule that survived', (
    WidgetTester tester,
  ) async {
    await open(tester, debt: '0.00');

    FilledButton confirm() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmPayment),
    );
    expect(confirm().onPressed, isNull, reason: 'فارغ');

    await tester.enterText(amountField(), '0');
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNull, reason: 'صفر ليس مبلغًا');
  });

  testWidgets('the amount box folds ٦٠ to 60 instead of swallowing it', (
    WidgetTester tester,
  ) async {
    // The app forces the `ar` locale, so the keyboard offers ٠١٢٣٤٥٦٧٨٩ however
    // the screen renders them. Order matters: ArabicDigitsFormatter must come
    // FIRST, or the filter below it drops each keystroke and the field never
    // fills.
    await open(tester, debt: '0.00');

    final TextField box = tester.widget<TextField>(amountField());
    expect(
      box.inputFormatters!.first,
      isA<ArabicDigitsFormatter>(),
      reason: 'الترتيب هو القاعدة نفسها، لا تفصيل فيها',
    );

    await tester.enterText(amountField(), '٦٠٫٥');
    await tester.pumpAndSettle();

    expect(find.text('60.5'), findsOneWidget);
    final FilledButton confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.confirmPayment),
    );
    expect(confirm.onPressed, isNotNull);
  });
}
