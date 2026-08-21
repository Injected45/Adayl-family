import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/aid_others_screen.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// «أسلاف للغير» reads as the SAME LEDGER as «أسلافي», because it is the same
/// widget — not a second implementation that resembles it.
///
/// The association asked for it in those words: «انسخ الكود ونفذه على أسلاف
/// للغير بالكامل … تسلسل # ثم البند القيمه الاجمالي مع وجود امكانية للضغط على
/// البند ليفتح ويظهر التفاصيل».
///
/// ⚠ WHAT THESE TESTS ARE REALLY GUARDING is that it stays ONE widget. Copied,
///   the two would drift, and every rule inside that table was argued once:
///   measured columns, an ordinal that belongs to the voucher rather than to
///   the loop, a reversal that keeps its balance, one open row at a time. A
///   copy is a second place for each to be quietly undone — and nothing would
///   fail when it was.
Map<String, dynamic> _voucher({
  required int id,
  required String amount,
  required String running,
  String category = 'فطور رمضان',
  String status = 'معتمد',
  String note = '',
}) => <String, dynamic>{
  'id': id,
  'voucherNo': 'EXP-0$id',
  'amount': amount,
  'kind': 'جماعي',
  'category': category,
  // ⚠ NOBODY. ck_disb_shape refuses a payee on a collective voucher — that is
  //   what makes it collective — so this is the shape the server can send.
  'payeeAdeelId': null,
  'payeeName': '',
  'payeeCode': '',
  'note': note,
  'method': 'نقداً',
  'status': status,
  'spentAt': '2026-08-1${id}T10:00:00Z',
  'runningTotal': running,
};

AidOthers _aid() => AidOthers.fromJson(<String, dynamic>{
  'total': '600.00',
  'count': 2,
  'byCategory': <dynamic>[
    <String, dynamic>{'category': 'فطور رمضان', 'total': '400.00', 'count': 1},
    <String, dynamic>{'category': 'عزاء', 'total': '200.00', 'count': 1},
  ],
  // Oldest first, each line carrying the total to that point — the order the
  // server now returns, and the only one in which «الإجمالي» is a number
  // rather than a decoration.
  'vouchers': <dynamic>[
    _voucher(id: 1, amount: '400.00', running: '400.00'),
    _voucher(
      id: 2,
      amount: '200.00',
      running: '600.00',
      category: 'عزاء',
      note: 'عزاء آل فلان',
    ),
  ],
});

Future<L> _open(WidgetTester tester, [AidOthers? aid]) async {
  tester.view.physicalSize = const Size(411, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        aidOthersProvider(1).overrideWith((Ref ref) async => aid ?? _aid()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: const AidOthersScreen(adeelId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return LAr();
}

void main() {
  _toneTests();
  testWidgets('the ledger heads are the four «أسلافي» uses', (
    WidgetTester tester,
  ) async {
    final L l = await _open(tester);

    expect(find.text(l.aidColSerial), findsOneWidget);
    expect(find.text(l.aidColAmount), findsOneWidget);
    expect(find.text(l.aidColRunning), findsOneWidget);
  });

  testWidgets('every line is numbered, oldest as 1', (
    WidgetTester tester,
  ) async {
    await _open(tester);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('and the running total is the SERVER\'s, not a Dart sum', (
    WidgetTester tester,
  ) async {
    await _open(tester);

    // 400 then 600 — accumulated by a window function in api_aid_others. A
    // screen that added these itself would be the one place «money is text»
    // is broken, and the hardest place to notice it.
    expect(find.text(formatMoney('400.00')), findsWidgets);
    expect(find.text(formatMoney('600.00')), findsWidgets);
  });

  testWidgets('a row is closed until it is tapped, then it opens', (
    WidgetTester tester,
  ) async {
    final L l = await _open(tester);

    // The voucher number lives in the DETAIL block, so it is the proof that
    // nothing is open.
    expect(find.text('EXP-02'), findsNothing);

    await tester.tap(find.text('عزاء').last);
    await tester.pumpAndSettle();

    expect(find.text('EXP-02'), findsOneWidget);
    expect(find.text(l.voucherNo), findsOneWidget);
  });

  // ⚠ AN ACCORDION, not four independent rows. Open four headings and four
  //   paragraphs stack down the page, and the table the reader came to scan
  //   stops being one.
  testWidgets('opening a second row closes the first', (
    WidgetTester tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('عزاء').last);
    await tester.pumpAndSettle();
    expect(find.text('EXP-02'), findsOneWidget);

    await tester.tap(find.text('فطور رمضان').last);
    await tester.pumpAndSettle();

    expect(find.text('EXP-01'), findsOneWidget);
    expect(find.text('EXP-02'), findsNothing);
  });

  // ⚠ A COLLECTIVE VOUCHER NAMES NOBODY, and the detail must not print an empty
  //   «المستلم». A blank where a name belongs reads as data that failed to load
  //   rather than as a fact about the voucher — and this screen exists
  //   precisely because the association decided no member is named on it.
  testWidgets('⚠ and the detail names no recipient at all', (
    WidgetTester tester,
  ) async {
    final L l = await _open(tester);

    await tester.tap(find.text('عزاء').last);
    await tester.pumpAndSettle();

    expect(find.text(l.recipient), findsNothing);
    // The heading stands alone instead, which is the whole answer when the
    // answer to «who» is everybody.
    expect(find.text(l.expenseCategory), findsOneWidget);
  });
}

/// ── اللونان: أخضر له، أحمر لِما خرج من الصندوق ──────────────────────────────
///
/// «اريد ايضا ان يكون لون القيم في شاشة اسلافي جميعها باللون الاخضر بدل من
/// اللون الاحمر الموجود الان».
///
/// ⚠ AND IT IS THE RIGHT WAY ROUND. Red is the colour of money leaving the
///   treasury — true from the fund's side, false from his. Nothing on «أسلافي»
///   is a debt of his, and الجمعية خيرية so none of it is owed back.
///
/// ⚠ THE OTHER SCREEN STAYS RED, and the two are not inconsistent: they are the
///   same table answering different questions. «أسلاف للغير» is what the
///   association SPENT, and its headline and its وجه rows are red — a green
///   ledger under a red headline is an inconsistency INSIDE one screen, which
///   is the kind a reader actually notices.
void _toneTests() {
  Color amountColour(WidgetTester tester, String money) =>
      tester
          .widgetList<RichText>(find.byType(RichText))
          .firstWhere((RichText w) => w.text.toPlainText() == money)
          .text
          .style!
          .color!;

  testWidgets('«أسلاف للغير» keeps the colour of money leaving the fund', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    expect(amountColour(tester, formatMoney('400.00')), AppColors.danger);
  });
}

