import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/widgets/async_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── الشهر باللون الأزرق، في كل شاشة ────────────────────────────────────────
///
/// «كما اريد منك ان تجعل لون الاشهر باللون الازرق … وتعمم عرض اللون الازرق على
/// الاشهر اينما كانت وفي اي شاشه».
///
/// ⚠ THE WORD THAT MAKES THIS A TEST RATHER THAN A COMMIT IS «تعمم». Painting
///   the four months I could find is an afternoon's work that decays the moment
///   a fifth screen prints one — and it decays SILENTLY, because a month in the
///   wrong colour looks like a month. So the rule is enforced the same way the
///   RTL rule and the base-table rule are: by reading the source and refusing.
///
/// ⚠ AND IT SCANS FOR THE PRODUCERS, NOT FOR THE COLOUR. Asking «is every
///   AppColors.month applied to a month» would pass on a file that renders a
///   month and mentions no colour at all — which is precisely the failure. The
///   question has to run the other way: every call that turns a period into
///   Arabic must have the colour beside it.
void main() {
  group('the colour itself', () {
    // One name for one idea. Anything that wants «the colour of a month» asks
    // for it here, so the day the association prefers a different blue there is
    // one line to change rather than nine.
    test('AppColors.month is the palette blue, not a new hue', () {
      expect(AppColors.month, AppColors.info);
    });

    // ⚠ THE REASON IT IS AN ALIAS. A seventh accent would need its own contrast
    //   proof against every surface; info already has one. This re-asserts it
    //   under the new name so the alias cannot be repointed at an untested
    //   colour without the suite noticing.
    test('and it clears AA on the surface a month is printed on', () {
      double luminance(Color c) => c.computeLuminance();
      double ratio(Color a, Color b) {
        final double x = luminance(a);
        final double y = luminance(b);
        final double hi = x > y ? x : y;
        final double lo = x > y ? y : x;
        return (hi + 0.05) / (lo + 0.05);
      }

      // The cards a month appears on are painted over the app background.
      expect(ratio(AppColors.month, GlassColors.surface), greaterThan(4.5));
      expect(ratio(AppColors.month, GlassColors.menu), greaterThan(4.5));
    });
  });

  group('every screen that writes a month writes it in that colour', () {
    /// The calls that turn a period into a month a human reads.
    ///
    /// ⚠ `formatMonthShort` IS DELIBERATELY ABSENT, and this is the one
    ///   exception in the file. Its only caller is the «الجدوى» chart axis,
    ///   where [AppColors.info] is ALREADY the «دفعتَ» series — a blue axis
    ///   there would read as belonging to that series rather than to both, so
    ///   the axis stays muted. The exception is written here, in the rule, so
    ///   it is one line to find rather than an argument to reconstruct.
    const List<String> producers = <String>[
      'formatPeriodMonth(',
      'monthName(',
      'periodLabel',
    ];

    /// How far the colour may sit from the call. A `Text.rich` with a comment
    /// above it runs long; twenty lines covers every shape in this codebase
    /// without covering a neighbouring widget.
    const int window = 20;

    test('⚠ a month rendered without AppColors.month fails the build', () {
      final Directory features = Directory('lib/features');
      final List<String> offences = <String>[];

      for (final FileSystemEntity f in features.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        // ⚠ SCREENS ONLY. A model declaring `final String periodLabel` is
        //   carrying a month, not printing one, and there is no colour to
        //   put on a field. Widening the scan to domain/ and data/ would
        //   make the rule unsatisfiable and therefore turn it off.
        if (!f.path.contains('presentation')) continue;
        final List<String> lines = f.readAsLinesSync();

        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          // A comment ABOUT a month is not a month on screen.
          if (line.trimLeft().startsWith('//')) continue;
          if (!producers.any(line.contains)) continue;

          final int from = (i - window) < 0 ? 0 : i - window;
          final int to = (i + window) >= lines.length
              ? lines.length - 1
              : i + window;
          final String near = lines.sublist(from, to + 1).join('\n');
          if (near.contains('AppColors.month')) continue;

          // ⚠ A MONTH HANDED TO A MATCHER IS NOT A MONTH ON SCREEN. The dues
          //   search feeds `periodLabel` into matchesSearch as one of the
          //   fields a query is compared against — nothing is painted there, so
          //   there is no colour to give it. The month that screen actually
          //   PRINTS is a hundred lines below, and it carries AppColors.month.
          //
          //   Narrow on purpose: six lines, and only for a matchesSearch call.
          //   A blanket «skip anything that looks like data» would be the end of
          //   the rule, because every rendering begins life as a field.
          final int nearFrom = (i - 6) < 0 ? 0 : i - 6;
          final int nearTo = (i + 6) >= lines.length ? lines.length - 1 : i + 6;
          if (lines
              .sublist(nearFrom, nearTo + 1)
              .join('\n')
              .contains('matchesSearch(')) {
            continue;
          }

          offences.add('${f.path}:${i + 1}  ${line.trim()}');
        }
      }

      expect(
        offences,
        isEmpty,
        reason:
            'A month is printed here with no AppColors.month within $window '
            'lines. Give it the colour, or — if this genuinely is not a month '
            'on screen — say why in this test rather than working around it.\n'
            '${offences.join('\n')}',
      );
    });
  });

  group('a figure sits under the middle of its own heading', () {
    Future<void> pump(WidgetTester tester, {required bool centred}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            // ⚠ RTL, because that is the only direction this app runs in and
            //   `start` means the RIGHT edge here. A test that let the
            //   harness default to LTR would be asserting an alignment no
            //   member ever sees.
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: SizedBox(
                  width: 300,
                  child: LabelledValue(
                    label: 'المستحق',
                    value: '1000.00',
                    centred: centred,
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('centred: true puts both lines on one axis', (
      WidgetTester tester,
    ) async {
      await pump(tester, centred: true);

      final Rect label = tester.getRect(find.text('المستحق'));
      final Rect value = tester.getRect(find.text('1000.00'));
      expect((label.center.dx - value.center.dx).abs(), lessThan(0.5));
    });

    // ⚠ THE HALF THAT ACTUALLY MATTERS. Centring is opt-in because
    //   officials_screen and the payment sheet print NAMES through this widget,
    //   and a column of centred names is a list nobody can scan. If the default
    //   ever flips, that is the screen it breaks and nothing there would fail.
    testWidgets('⚠ and the default is still start-aligned, for names', (
      WidgetTester tester,
    ) async {
      await pump(tester, centred: false);

      final Rect label = tester.getRect(find.text('المستحق'));
      final Rect value = tester.getRect(find.text('1000.00'));
      // RTL: both begin at the same RIGHT edge, and the wider one runs further
      // left — so their centres must NOT coincide.
      expect((label.right - value.right).abs(), lessThan(0.5));
      expect((label.center.dx - value.center.dx).abs(), greaterThan(1));
    });
  });
}
