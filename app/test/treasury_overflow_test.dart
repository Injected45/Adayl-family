import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/portal_sections.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// «لا اريد اي حرف يخرج خارج اطار الديزاين حتى لا يضيع الشكل ويتشوه.»
///
/// ⚠ ADDING «د.ل» TO EVERY FIGURE MADE EVERY ROW WIDER, and the arrears line
///   carries three things on one line — a name, a note and an amount. On a
///   narrow phone with a long Libyan name that is exactly where a RenderFlex
///   overflows, and an overflow is not a subtle defect: Flutter paints yellow
///   and black stripes across the design.
///
/// ⚠ 320 LOGICAL PIXELS IS THE FLOOR, not a phone anybody owns. A test at 411
///   proves the handset in the room; a test at 320 proves the one somebody
///   buys next, and costs nothing to run.
///
/// ⚠ AND THE NAMES ARE THE WORST CASE ON PURPOSE. «عبدالرحمن محمد عبدالسلام
///   الشيباني» is not a joke name — it is how a Libyan name is written in
///   full, and the register holds them.
List<ArrearsRow> _worst() => <ArrearsRow>[
  ArrearsRow.fromJson(<String, dynamic>{
    'adeelId': 1,
    'adeelCode': 'A-01',
    'name': 'عبدالرحمن محمد عبدالسلام الشيباني',
    'owed': '123456.00',
    'held': '98765.00',
    'status': 'نشط',
    'mine': true,
  }),
  ArrearsRow.fromJson(<String, dynamic>{
    'adeelId': 2,
    'adeelCode': 'A-02',
    'name': 'محمد المبروك عبدالعظيم الشيخي',
    'owed': '0.00',
    'held': '250000.00',
    'status': 'نشط',
    'mine': false,
  }),
];

AssociationFinance _fat() => AssociationFinance.fromJson(<String, dynamic>{
  'balance': '1234567.00',
  'collected': '2345678.00',
  'disbursed': '999999.00',
  'cash': '1111111.00',
  'transfer': '222222.00',
  'issued': '3333333.00',
  'outstanding': '444444.00',
  'heldForMembers': '555555.00',
  'members': 8,
  'activeMembers': 8,
});

void main() {
  tearDown(() => applyAppTheme(AppThemeMode.light));

  for (final double width in <double>[320, 360, 411]) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      testWidgets('الصندوق fits at ${width.toInt()}px in ${mode.name}', (
        WidgetTester tester,
      ) async {
        applyAppTheme(mode);
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              associationFinanceProvider.overrideWith(
                (Ref ref) async => _fat(),
              ),
              arrearsBoardProvider.overrideWith((Ref ref) async => _worst()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              locale: const Locale('ar'),
              localizationsDelegates: latinDigitDelegates(
                L.localizationsDelegates,
              ),
              supportedLocales: L.supportedLocales,
              // ⚠ THE PAGE ON ITS OWN. Wrapping it in a scroll view gave
              //   it unbounded height and the first run failed on THAT, not on
              //   an overflow — a test harness reporting a defect it created.
              home: Builder(
                builder: (BuildContext c) =>
                    portalSectionPage(c, PortalSection.treasury, 1),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // ⚠ THE ONE ASSERTION THAT MATTERS. A RenderFlex overflow arrives as an
        //   exception in a test and as yellow stripes on a handset.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'something overflowed at ${width.toInt()}px in ${mode.name} — '
              'that is the striped bar across the design',
        );
      });
    }
  }
}
