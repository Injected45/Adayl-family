import 'dart:io';

import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/member_value_bar.dart';
import 'package:family_app/features/finance/presentation/member_years_chart.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «الجدوى» بعد 14/09: النسبة بمعادلة الجمعية، والرسم سنةً بسنة.
///
/// ── النسبة ──────────────────────────────────────────────────────────────────
/// «قيمة ما استلمه المشترك ÷ ما تم دفعه × 100». The eight rows below are the
/// eight men of the live ledger (paid and received as `api_member_value`
/// returns them on a copy of it), so a change to the rounding shows up as a
/// changed figure beside a real name.
///
/// ── الرسم ───────────────────────────────────────────────────────────────────
/// أيمن's own `years`, copied from the function's output on that copy: 2026,
/// 2025, and «حتى 2024» folding the opening receipt with a decade of aid.
void main() {
  final L l = LAr();
  tearDown(() => applyAppTheme(AppThemeMode.light));

  group('the return ratio is the association\'s formula', () {
    // (code, paid, received, expected)
    const List<(String, String, String, String)> live =
        <(String, String, String, String)>[
          ('A-01', '8315.00', '2320.00', '27.90'),
          ('A-02', '8315.00', '4950.00', '59.53'),
          ('A-03', '8015.00', '4670.00', '58.27'),
          ('A-04', '8015.00', '1950.00', '24.33'),
          ('A-05', '8015.00', '4250.00', '53.03'),
          ('A-06', '6585.00', '3250.00', '49.35'),
          ('A-07', '7155.00', '2200.00', '30.75'),
          ('A-08', '3465.00', '3500.00', '101.01'),
        ];

    for (final (String code, String paid, String got, String want) in live) {
      test('$code: $got ÷ $paid × 100 = $want', () {
        expect(returnPercentOf(paid: paid, received: got), want);
      });
    }

    test('⚠ أيمن is 24.33, not 24.34 and not 24', () {
      // 1950 ÷ 8015 = 0.243293824… → 24.3294 → 24.33 at two places. «24» is
      // what the old integer rounding printed.
      expect(returnPercentOf(paid: '8015.00', received: '1950.00'), '24.33');
    });

    test('half rounds up at the second decimal', () {
      // 1 ÷ 8 = 12.5%; 1 ÷ 3 = 33.333…; 2 ÷ 3 = 66.666… → 66.67
      expect(returnPercentOf(paid: '8.00', received: '1.00'), '12.50');
      expect(returnPercentOf(paid: '3.00', received: '1.00'), '33.33');
      expect(returnPercentOf(paid: '3.00', received: '2.00'), '66.67');
      expect(returnPercentOf(paid: '200.00', received: '0.00'), '0.00');
      expect(returnPercentOf(paid: '100.00', received: '100.00'), '100.00');
    });

    test('nothing paid is no ratio at all, not a zero', () {
      expect(returnPercentOf(paid: '0.00', received: '500.00'), isNull);
      expect(returnPercentOf(paid: '', received: '500.00'), isNull);
    });

    test('⚠ and it is integer arithmetic, not a double', () {
      final String src = File(
        'lib/features/finance/domain/models.dart',
      ).readAsStringSync();
      final String body = src.substring(
        src.indexOf('String? returnPercentOf('),
        src.indexOf('class MemberYear '),
      );
      expect(body, contains('BigInt'));
      expect(body, isNot(contains('double')));
    });

    testWidgets('the card prints the ratio, and no formula under it', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const MemberValueBar(paid: '8015.00', received: '1950.00'),
      );
      expect(find.text(l.valueShareOf('24.33')), findsOneWidget);
      // «يكفي ظهور النسبه بدون اي ايحاء او تلميح» (15/09): nothing on the
      // card spells out how the figure was reached.
      expect(find.textContaining('÷'), findsNothing);
      expect(find.textContaining('× 100'), findsNothing);
    });

    testWidgets('more than paid says so; exactly paid does not', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        const MemberValueBar(paid: '3465.00', received: '3500.00'),
      );
      expect(find.text(l.valueShareOver('101.01')), findsOneWidget);

      await _pump(
        tester,
        const MemberValueBar(paid: '100.00', received: '100.00'),
      );
      expect(find.text(l.valueShareOf('100.00')), findsOneWidget);
    });

    test('⚠ the association-wide line is gone from «الجدوى»', () {
      // «عاد إلى العدايل X% من إجمالي المحصَّل» was one number on every phone,
      // read by every man as his own.
      final String src = File(
        'lib/features/finance/presentation/member_value_screen.dart',
      ).readAsStringSync();
      expect(src, isNot(contains('valueBackToMembers')));
      // And the whole «الجمعية» container with it — heading, the rate and
      // «أكبر ما صُرف لمشترك واحد» (14/09).
      expect(src, isNot(contains('valueFund')));
      expect(src, isNot(contains('valueLargest')));
      expect(src, isNot(contains('value.largest')));
      expect(src, isNot(contains('toMembers')));
    });
  });

  group('year by year', () {
    testWidgets('one row per year, newest first, the opening row named', (
      WidgetTester tester,
    ) async {
      await _pump(tester, MemberYearsChart(years: _ayman()));

      expect(find.text(l.valueMonths), findsOneWidget);
      final double y2026 = tester.getTopLeft(find.text('2026')).dy;
      final double y2025 = tester.getTopLeft(find.text('2025')).dy;
      final double yOpen = tester
          .getTopLeft(find.text(l.valueOpeningYear('2024')))
          .dy;
      expect(y2026 < y2025 && y2025 < yOpen, isTrue);

      // Every figure, exactly as the server sent it.
      expect(find.text(formatMoney('800.00')), findsOneWidget);
      expect(find.text(formatMoney('1800.00')), findsOneWidget);
      expect(find.text(formatMoney('5415.00')), findsOneWidget);
      expect(find.text(formatMoney('1950.00')), findsOneWidget);
      // «دفعتَ» and «استلمتَ» on every row, plus the legend.
      expect(find.text(l.valuePaid), findsNWidgets(4));
      expect(find.text(l.valueReceived), findsNWidgets(4));
    });

    testWidgets('⚠ every track is the same length, whatever the figure', (
      WidgetTester tester,
    ) async {
      // If the figure took its own width, «5,415.00» would shorten its row's
      // track and equal values would end in different places.
      await _pump(tester, MemberYearsChart(years: _ayman()));
      final Finder track = find.byKey(const ValueKey<String>('year-track'));
      expect(track, findsNWidgets(6), reason: 'two bars for each of 3 years');
      final Set<double> widths = <double>{
        for (final Element e in track.evaluate())
          (e.renderObject! as RenderBox).size.width,
      };
      expect(widths, hasLength(1));
    });

    testWidgets('a bar is as long as its share of the largest figure', (
      WidgetTester tester,
    ) async {
      await _pump(tester, MemberYearsChart(years: _ayman()));
      final Iterable<Container> fills = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(MemberYearsChart),
              matching: find.byType(Container),
            ),
          )
          .where(
            (Container c) =>
                (c.decoration as BoxDecoration?)?.color ==
                    AppColors.chartPaid &&
                c.constraints?.maxWidth != null &&
                c.constraints!.maxWidth < 10000,
          );
      final List<double> widths =
          fills.map((Container c) => c.constraints!.maxWidth).toList()..sort();
      // 800, 1800, 5415 of a 5415 scale (the legend mark is 16 wide).
      final double full = widths.last;
      expect(
        widths.where((double w) => (w - full * 800 / 5415).abs() < 1),
        isNotEmpty,
      );
      expect(
        widths.where((double w) => (w - full * 1800 / 5415).abs() < 1),
        isNotEmpty,
      );
    });

    testWidgets('a year opens onto its months, in blue, one year at a time', (
      WidgetTester tester,
    ) async {
      await _pump(tester, MemberYearsChart(years: _ayman()));
      expect(find.text(monthName(4)), findsNothing);

      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      expect(find.text(l.valueColMonth), findsOneWidget);
      final Text april = tester.widget<Text>(find.text(monthName(4)));
      expect(april.style?.color, AppColors.month);
      expect(find.text(formatMoney('300.00')), findsOneWidget);

      await tester.tap(find.text('2025'));
      await tester.pumpAndSettle();
      expect(
        find.text(formatMoney('300.00')),
        findsNothing,
        reason: 'opening 2025 closes 2026',
      );
      expect(find.text(monthName(10)), findsOneWidget);

      await tester.tap(find.text('2025'));
      await tester.pumpAndSettle();
      expect(find.text(l.valueColMonth), findsNothing);
    });

    testWidgets('«حتى 2024» opens onto the YEARS inside it', (
      WidgetTester tester,
    ) async {
      await _pump(tester, MemberYearsChart(years: _ayman()));
      await tester.tap(find.text(l.valueOpeningYear('2024')));
      await tester.pumpAndSettle();
      expect(find.text(l.valueColYear), findsOneWidget);
      expect(find.text('2018'), findsOneWidget);
      expect(find.text('2023'), findsOneWidget);
      expect(find.text(formatMoney('850.00')), findsOneWidget);
    });

    testWidgets('no years, no chart', (WidgetTester tester) async {
      await _pump(tester, const MemberYearsChart(years: <MemberYear>[]));
      expect(find.text(l.valueMonths), findsNothing);
    });

    test('the model parses what api_member_value sends', () {
      final MemberValue v = MemberValue.fromJson(<String, dynamic>{
        'paid': '8015.00',
        'received': '1950.00',
        'years': _aymanJson(),
      });
      expect(v.years, hasLength(3));
      expect(v.years.last.opening, isTrue);
      expect(v.years.last.parts.first.key, '2018');
      expect(v.years.last.parts.first.isMonth, isFalse);
      expect(v.years.first.parts.first.isMonth, isTrue);
      expect(v.returnPercent, '24.33');
      // A database without PATCH_20260914 sends no key: an empty chart, not a
      // failed screen.
      expect(MemberValue.fromJson(<String, dynamic>{}).years, isEmpty);
    });

    // «لا اريد اي حرف يخرج خارج اطار الديزاين» — at 320px, open and closed,
    // in both themes, at the largest figures the ledger holds.
    for (final double width in <double>[320, 360, 411]) {
      for (final AppThemeMode mode in AppThemeMode.values) {
        testWidgets('fits at ${width.toInt()}px in ${mode.name}', (
          WidgetTester tester,
        ) async {
          applyAppTheme(mode);
          await _pump(tester, MemberYearsChart(years: _big()), width: width);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('2026'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(l.valueOpeningYear('2024')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 411,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[child],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<dynamic> _aymanJson() => <dynamic>[
  <String, dynamic>{
    'year': '2026',
    'opening': false,
    'paid': '800.00',
    'received': '0.00',
    'parts': <dynamic>[
      <String, dynamic>{'key': '2026-01', 'paid': '100.00', 'received': '0.00'},
      <String, dynamic>{'key': '2026-02', 'paid': '100.00', 'received': '0.00'},
      <String, dynamic>{'key': '2026-04', 'paid': '300.00', 'received': '0.00'},
      <String, dynamic>{'key': '2026-05', 'paid': '100.00', 'received': '0.00'},
      <String, dynamic>{'key': '2026-06', 'paid': '200.00', 'received': '0.00'},
    ],
  },
  <String, dynamic>{
    'year': '2025',
    'opening': false,
    'paid': '1800.00',
    'received': '0.00',
    'parts': <dynamic>[
      <String, dynamic>{'key': '2025-01', 'paid': '400.00', 'received': '0.00'},
      <String, dynamic>{'key': '2025-05', 'paid': '400.00', 'received': '0.00'},
      <String, dynamic>{'key': '2025-10', 'paid': '200.00', 'received': '0.00'},
    ],
  },
  <String, dynamic>{
    'year': '2024',
    'opening': true,
    'paid': '5415.00',
    'received': '1950.00',
    'parts': <dynamic>[
      <String, dynamic>{'key': '2018', 'paid': '0.00', 'received': '250.00'},
      <String, dynamic>{'key': '2020', 'paid': '0.00', 'received': '350.00'},
      <String, dynamic>{'key': '2022', 'paid': '0.00', 'received': '500.00'},
      <String, dynamic>{'key': '2023', 'paid': '0.00', 'received': '850.00'},
      <String, dynamic>{'key': '2024', 'paid': '5415.00', 'received': '0.00'},
    ],
  },
];

List<MemberYear> _ayman() => <MemberYear>[
  for (final dynamic y in _aymanJson())
    MemberYear.fromJson(y as Map<String, dynamic>),
];

/// The widest figures a phone must hold: six digits with separators.
List<MemberYear> _big() => <MemberYear>[
  for (final MemberYear y in _ayman())
    MemberYear(
      year: y.year,
      opening: y.opening,
      paid: '123456.00',
      received: '98765.00',
      parts: <MemberYearPart>[
        for (final MemberYearPart p in y.parts)
          MemberYearPart(key: p.key, paid: '123456.00', received: '98765.00'),
      ],
    ),
];
