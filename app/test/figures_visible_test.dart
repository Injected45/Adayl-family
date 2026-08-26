import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/widgets/app_background.dart';
import 'package:family_app/core/widgets/async_view.dart';
import 'package:family_app/features/directory/presentation/portal_sections.dart';
import 'package:family_app/features/finance/presentation/member_value_bar.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «لا تتغطّى ولا تضيع أي أرقام بالتغيير من داكن إلى عادي والعكس.»
///
/// ⚠ THE CONTRAST SUITE PROVES THE PALETTE; THIS PROVES THE SCREENS. Those are
///   not the same claim. design_system_test measures token against token — it
///   never renders a widget, so a figure painted in a tone the suite never
///   thought to pair with the surface it actually sits on would pass every
///   check and still vanish.
///
///   This renders REAL figure-bearing widgets, in both palettes, with every
///   tone the money screens use, and asks two questions of each: is the number
///   still on screen, and can it be READ where it is.
double _lum(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final double x = _lum(a), y = _lum(b);
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

Color _over(Color fg, Color bg) {
  final double a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

/// The worst place a figure can land: the darkest, most saturated point of the
/// field, under a content pane and inside a recessed well.
Color get _worstUnder {
  Color field = AppColors.fieldBase;
  for (final Color wash in <Color>[
    AppColors.auroraViolet,
    AppColors.auroraCyan,
  ]) {
    field = _over(wash.withValues(alpha: 0.22), field);
  }
  return _over(GlassColors.well, _over(GlassColors.surface, field));
}

void main() {
  tearDown(() => applyAppTheme(AppThemeMode.light));

  /// Every tone the money screens actually put a FIGURE in. Not every colour in
  /// the palette — the ones a reader has to read a number through.
  Map<String, Color> figureTones() => <String, Color>{
    'success (دفعتَ، الرصيد، عهدة)': AppColors.success,
    'danger (استلمتَ، المصروفات، متأخرات)': AppColors.danger,
    'info (تحويل مصرفي)': AppColors.info,
    'dues (المستحقات)': AppColors.dues,
    'warning': AppColors.warning,
    'ink (الباقي)': AppColors.ink,
    'muted (مستحق)': AppColors.muted,
    'brandDeep (الكود)': AppColors.brandDeep,
  };

  for (final AppThemeMode mode in AppThemeMode.values) {
    group('palette: ${mode.name}', () {
      setUp(() => applyAppTheme(mode));

      test('⚠ every figure tone is readable where a figure actually sits', () {
        final Color under = _worstUnder;
        final List<String> lost = <String>[];
        figureTones().forEach((String name, Color tone) {
          final double r = _contrast(tone, under);
          if (r < 4.5) lost.add('$name  ${r.toStringAsFixed(2)}:1');
        });
        expect(
          lost,
          isEmpty,
          reason:
              'a figure in this tone would be hard to read on the worst pane '
              'in ${mode.name}:\n  ${lost.join('\n  ')}',
        );
      });

      testWidgets('and the numbers are still on screen after the switch', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(411 * 3, 1200 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            locale: const Locale('ar'),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: AppBackground(
              child: Scaffold(
                body: ListView(
                  children: <Widget>[
                    for (final MapEntry<String, Color> e
                        in figureTones().entries)
                      SectionRow(
                        label: e.key,
                        value: '1,234.00',
                        tone: e.value,
                      ),
                    const LabelledValue(label: 'الرصيد', value: '2,900.00'),
                    StatusBadge(label: 'نشط', tone: AppColors.success),
                    const MemberValueBar(paid: '1200.00', received: '300.00'),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        // ⚠ EIGHT ROWS, EIGHT FIGURES. A palette that swallowed one would still
        //   render the widget — the Text is there with a colour nobody can see
        //   — so the count is asserted as well as the presence.
        expect(find.text('1,234.00'), findsNWidgets(8));
        expect(find.text('2,900.00'), findsOneWidget);
        expect(find.text('نشط'), findsOneWidget);
      });

      testWidgets('⚠ and no figure is painted in its own background', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(411 * 3, 900 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            locale: const Locale('ar'),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: AppBackground(
              child: Scaffold(
                body: SectionRow(
                  label: 'الرصيد',
                  value: '2,900.00',
                  tone: AppColors.success,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Text t = tester.widget<Text>(find.text('2,900.00'));
        final Color c = t.style!.color!;
        // Transparent, or the same colour as the pane, is a number that is
        // present in the widget tree and absent from the screen.
        expect(c.a, 1.0, reason: 'a figure must never be translucent');
        expect(
          _contrast(c, _worstUnder),
          greaterThanOrEqualTo(4.5),
          reason: 'the figure is invisible on the worst pane in ${mode.name}',
        );
      });
    });
  }
}
