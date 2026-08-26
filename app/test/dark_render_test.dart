import 'dart:io';

import 'package:family_app/core/config/glass.dart';
import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/widgets/app_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// هل يُرسَم الوضعُ الداكن أصلاً؟
///
/// ⚠ EVERY OTHER TEST IN THIS SUITE RENDERS IN THE LIGHT PALETTE. Even
///   design_system_test swaps the tokens and does arithmetic on them — it
///   never puts a pixel on a canvas. So «607 tests pass» said nothing at all
///   about whether the dark palette DRAWS, and the palette change touched the
///   theme, the surfaces, the background painter and 197 const expressions.
///
/// ⚠ AND «no exception» IS THE CLAIM, NOT «it looks right». A screenshot is
///   the only thing that answers the second, and a human is the only thing
///   that can read one. This proves the app builds, lays out and paints in
///   both palettes — which is the half a machine can check.
void main() {
  _literalColourSweep();

  tearDown(() => applyAppTheme(AppThemeMode.light));

  Future<void> pump(WidgetTester tester, AppThemeMode mode) async {
    applyAppTheme(mode);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppBackground(
          child: Scaffold(
            appBar: AppBar(title: const Text('العنوان')),
            body: ListView(
              children: <Widget>[
                GlassCard(
                  child: Column(
                    children: <Widget>[
                      Text('حبر', style: TextStyle(color: AppColors.ink)),
                      Text('هامش', style: TextStyle(color: AppColors.muted)),
                      FilledButton(onPressed: () {}, child: const Text('زر')),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('حدّ'),
                      ),
                      TextField(
                        decoration: const InputDecoration(labelText: 'حقل'),
                      ),
                      DropdownButtonFormField<int>(
                        dropdownColor: GlassColors.menu,
                        items: const <DropdownMenuItem<int>>[
                          DropdownMenuItem<int>(value: 1, child: Text('خيار')),
                        ],
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
                GlassPanel(
                  title: 'لوح',
                  child: Text(
                    'داخل اللوح',
                    style: TextStyle(color: AppColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final AppThemeMode mode in AppThemeMode.values) {
    testWidgets('the app paints in ${mode.name} without throwing', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(411 * 3, 890 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await pump(tester, mode);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the ${mode.name} palette threw while painting',
      );
      expect(find.text('حبر'), findsOneWidget);
      expect(find.text('داخل اللوح'), findsOneWidget);
    });
  }

  testWidgets('⚠ and the two palettes actually differ on screen', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 890 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pump(tester, AppThemeMode.light);
    final Color lightInk = tester.widget<Text>(find.text('حبر')).style!.color!;

    await pump(tester, AppThemeMode.dark);
    final Color darkInk = tester.widget<Text>(find.text('حبر')).style!.color!;

    // ⚠ THE POINT OF THE WHOLE FEATURE, ASSERTED. Everything else here would
    //   pass if applyAppTheme did nothing at all: the app would paint, the
    //   text would be found, and «both palettes work» would be a sentence
    //   about one palette rendered twice.
    expect(
      darkInk,
      isNot(lightInk),
      reason: 'switching the mode changed nothing that reaches a widget',
    );
    expect(
      darkInk.computeLuminance(),
      greaterThan(lightInk.computeLuminance()),
      reason: 'dark-mode ink must be the LIGHT one — it sits on a dark pane',
    );
  });
}

/// ولا لونَ مكتوبٍ بيده في شاشة.
///
/// ⚠ THIS IS THE CHECK THAT WAS MISSING, AND IT FOUND THREE REAL DEFECTS after
///   «610 tests pass» had already been reported:
///
///     • the collection and disbursement buttons wore `Colors.white` over
///       AppColors.success / .danger — which in الوضع الليلي are the LIGHT
///       accents, so the label measured 1.5:1;
///     • the منطقة الخطر warning carried a hand-copied #854D0E on
///       warningSoft — both invert, so it would have been dark amber on dark
///       amber: the one paragraph that must be read, unreadable;
///     • the splash spinner was white@70% on a field that is now dark.
///
///   None of them could fail a test: they are legal colours, correctly typed,
///   on widgets that render perfectly. They are simply BLIND to the palette —
///   which is invisible until somebody switches it.
///
/// ⚠ Colors.transparent AND Colors.black26-style scrims are exempt: they carry
///   no hue and read the same on both palettes.
void _literalColourSweep() {
  test('⚠ no screen hard-codes a colour that cannot follow the palette', () {
    final List<String> offenders = <String>[];

    for (final FileSystemEntity e in Directory(
      'lib/features',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String t = lines[i].trimLeft();
        if (t.startsWith('//') || t.startsWith('///')) continue;

        // ⚠ THE GOOGLE BUTTON IS THE ONE EXEMPTION AND IT IS A BRAND RULE.
        //   Google's sign-in guidelines fix the surface white; following the
        //   app's palette there would be a licensing question, not a design
        //   choice.
        if (e.path.contains('google_sign_in_button')) continue;

        final bool literal =
            RegExp(r'Color\(0x[0-9a-fA-F]{6,8}\)').hasMatch(lines[i]) ||
            lines[i].contains('Colors.white') ||
            lines[i].contains('Colors.black,');
        if (literal) {
          offenders.add('${e.path}:${i + 1}  ${t.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'a literal colour cannot follow الوضع الليلي. Use an AppColors / '
          'GlassColors token, which applyAppTheme swaps:\n  '
          '${offenders.join('\n  ')}',
    );
  });
}
