import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/member_months_chart.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// حركتك خلال 12 شهراً — the chart at the foot of «الجدوى».
///
/// ⚠ THE ONE RULE THIS FILE EXISTS FOR: the chart draws, it does not calculate.
///   Every figure is summed by `api_member_value` and arrives as text; the only
///   thing Dart does with it is decide how tall to make a rectangle. A chart is
///   the most tempting place in the whole app to break «money is text» — «I only
///   need a number to scale a bar» — and the temptation grows every time
///   somebody adds a total, an average or a year-to-date line to it.
List<MemberMonth> _series(List<(String, String, String)> rows) => <MemberMonth>[
  for (final (String p, String paid, String got) in rows)
    MemberMonth(period: p, paid: paid, received: got),
];

/// A full year, mostly quiet, with one payment and one voucher.
List<MemberMonth> _year() => _series(<(String, String, String)>[
  ('2026-01', '100.00', '0.00'),
  ('2026-02', '0.00', '0.00'),
  ('2026-03', '0.00', '0.00'),
  ('2026-04', '200.00', '0.00'),
  ('2026-05', '0.00', '0.00'),
  ('2026-06', '0.00', '500.00'),
  ('2026-07', '0.00', '0.00'),
  ('2026-08', '100.00', '0.00'),
  ('2026-09', '0.00', '0.00'),
  ('2026-10', '0.00', '0.00'),
  ('2026-11', '0.00', '0.00'),
  ('2026-12', '0.00', '0.00'),
]);

Future<void> _pump(WidgetTester tester, List<MemberMonth> months) async {
  tester.view.physicalSize = const Size(411, 900);
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
        body: Directionality(
          textDirection: TextDirection.rtl,
          child: MemberMonthsChart(months: months),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  _preview();
  final L l = LAr();

  testWidgets('a year with movement draws, and names both series', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _year());

    expect(find.byType(CustomPaint), findsWidgets);

    // ⚠ A LEGEND FOR TWO SERIES, ALWAYS. Identity must never rest on colour
    //   alone — and under tritanopia this pair separates by only ΔE 6.4, which
    //   is legal exactly because a second channel carries it.
    expect(find.text(l.valuePaid), findsOneWidget);
    expect(find.text(l.valueReceived), findsOneWidget);
    expect(find.text(l.valueMonths), findsOneWidget);
  });

  // ⚠ THE EMPTY CASE IS NOT AN EMPTY CHART. Twelve blank columns on the one
  //   screen built to answer «ما الجدوى» is a graphic that says nothing, and a
  //   man who has never paid is exactly who opens it first.
  testWidgets('a man with no movement gets no chart at all', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      _series(<(String, String, String)>[
        ('2026-07', '0.00', '0.00'),
        ('2026-08', '0.00', '0.00'),
      ]),
    );

    expect(find.text(l.valueMonths), findsNothing);
  });

  testWidgets('...and neither does a database that never sent the series', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <MemberMonth>[]);
    expect(find.text(l.valueMonths), findsNothing);
  });

  // ── The rule the whole file is here for ────────────────────────────────────
  test('⚠ the chart NEVER sums money — the server does', () {
    final String src = File(
      'lib/features/finance/presentation/member_months_chart.dart',
    ).readAsStringSync();

    // Comments stripped, so prose explaining the rule cannot trip the rule.
    final String code = src
        .split('\n')
        .map((String line) {
          final int i = line.indexOf('//');
          return i == -1 ? line : line.substring(0, i);
        })
        .join('\n');

    // `fold` and `reduce` are how a total arrives in a painter without
    // looking like one.
    for (final String banned in <String>['fold(', 'reduce(']) {
      expect(
        code.contains(banned),
        isFalse,
        reason:
            'A chart that adds its own figures puts the association\'s money on '
            'binary floating point. api_member_value returns them summed.',
      );
    }

    // ⚠ AND `+=` ONLY WHERE MONEY IS. The first version of this check banned
    //   it outright and caught `i += 3` — the loop that steps along the month
    //   axis. A guard that fires on correct code is the kind somebody deletes
    //   rather than fixes, so it is narrowed to the lines that actually touch
    //   a parsed figure: `_v(` is the only place a string becomes a number in
    //   this file.
    final Iterable<String> accumulates = code
        .split('\n')
        .where((String line) => line.contains('+=') && line.contains('_v('));
    expect(
      accumulates,
      isEmpty,
      reason:
          'Every figure this chart draws is already summed by the server. A '
          'running total added here would be the app doing arithmetic on '
          'money, which is the one thing the whole text-money rule forbids.',
    );
  });

  test('the axis label drops the year, so a tick cannot collide', () {
    // formatPeriodMonth appends the year outside the current one — right on a
    // receipt, wrong on a 30px tick. formatMonthShort is the axis version.
    expect(formatMonthShort('2026-08'), isNot(contains('2026')));
    expect(formatMonthShort('2019-12'), isNot(contains('2019')));
    // And nonsense passes through rather than being invented.
    expect(formatMonthShort('nope'), 'nope');
    expect(formatMonthShort(null), '');
  });
}

/// ── The check with eyes ─────────────────────────────────────────────────────
///
/// Every rule the dataviz method imposes — the validated palette, one scale, a
/// legend for two series, labels only on the extremes — can be satisfied while
/// the result is unreadable: ticks colliding, a bar clipped, twelve columns
/// crushed into a smear. No matcher notices any of that.
///
/// Regenerate and LOOK at it:
///   flutter test --update-goldens --dart-define=WRITE_PREVIEW=true \
///     test/member_months_chart_test.dart
///
/// Skipped unless goldens are being written, so font rasterisation differences
/// between machines cannot fail the build.
void _preview() {
  const bool write = bool.fromEnvironment('WRITE_PREVIEW', defaultValue: false);

  testWidgets(
    'preview',
    (WidgetTester tester) async {
      await _pump(tester, _year());
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/member_months_chart.png'),
      );
    },
    skip: !write,
  );
}
