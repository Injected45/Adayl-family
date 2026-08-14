import 'dart:io';
import 'dart:math' as math;

import 'package:family_app/core/config/glass.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/widgets/app_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the three things that go wrong with Glassmorphism + Flat Design, in
/// the order they bite:
///
///   1. CONTRAST. Translucent surfaces make text contrast a function of whatever
///      is behind them. This is the style's documented accessibility failure and
///      the reason a glass UI ships looking beautiful and unreadable.
///   2. PERFORMANCE. BackdropFilter costs a compositor layer each. One per list
///      row is how a glass redesign turns a smooth list into a stuttering one.
///   3. DRIFT. Flat Design forbids gradients and decorative shadows. Nothing
///      stops the next screen from adding one except a check that fails.
///
/// Every threshold here is asserted, not eyeballed.

// ─────────────────────────────────────────────────────────────────────────────
// WCAG 2.1 contrast, implemented rather than trusted to a plugin.
// ─────────────────────────────────────────────────────────────────────────────

double _channel(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

/// Relative luminance per WCAG 2.1.
double luminance(Color c) {
  final double r = _channel(c.r);
  final double g = _channel(c.g);
  final double b = _channel(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Contrast ratio between two OPAQUE colours.
double contrast(Color a, Color b) {
  final double la = luminance(a);
  final double lb = luminance(b);
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Alpha-composite [fg] over [bg]. The whole point of the contrast suite: a
/// glass pane is not a colour, it is a composite, and its effective background
/// depends on what happens to be behind it.
Color over(Color fg, Color bg) {
  final double a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

/// The worst case a glass pane can sit on: the darkest, most saturated point of
/// the aurora field, with two washes overlapping.
Color get worstField {
  Color field = AppColors.fieldBase;
  for (final Color wash in <Color>[
    AppColors.auroraViolet,
    AppColors.auroraCyan,
  ]) {
    field = over(wash.withValues(alpha: 0.22), field);
  }
  return field;
}

Color get contentSurface => over(GlassColors.surface, worstField);
Color get chromeSurface => over(GlassColors.chrome, worstField);
Color get wellSurface => over(GlassColors.well, contentSurface);

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  group('contrast (WCAG AA, 4.5:1)', () {
    test('the ratio maths itself is right', () {
      // Anchors with known answers, so a bug in the helper cannot silently pass
      // every colour below.
      expect(contrast(Colors.black, Colors.white), closeTo(21.0, 0.05));
      expect(contrast(Colors.white, Colors.white), closeTo(1.0, 0.001));
      // #767676 on white is the canonical 4.54:1 boundary case.
      expect(
        contrast(const Color(0xFF767676), Colors.white),
        closeTo(4.54, 0.05),
      );
    });

    test('body and secondary text clear AA on a content pane', () {
      expect(
        contrast(AppColors.ink, contentSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppColors.inkMuted, contentSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('text clears AA on floating chrome, which is more transparent', () {
      expect(contrast(AppColors.ink, chromeSurface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(AppColors.inkMuted, chromeSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('text clears AA inside a recessed well', () {
      expect(contrast(AppColors.ink, wellSurface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(AppColors.inkMuted, wellSurface),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('every accent is legible as text on a pane', () {
      final Map<String, Color> accents = <String, Color>{
        'brand': AppColors.brand,
        'brandDeep': AppColors.brandDeep,
        'danger': AppColors.danger,
        'success': AppColors.success,
        'warning': AppColors.warning,
        'info': AppColors.info,
        'accent': AppColors.accent,
      };
      accents.forEach((String name, Color c) {
        expect(
          contrast(c, contentSurface),
          greaterThanOrEqualTo(4.5),
          reason: '$name on a glass content pane',
        );
      });
    });

    test('badge labels clear AA on their own tinted fill', () {
      // StatusBadge draws the label in `tone` over `tone` at 14% — the pairing
      // most likely to fail, because both sides move together.
      final Map<String, Color> tones = <String, Color>{
        'danger': AppColors.danger,
        'success': AppColors.success,
        'warning': AppColors.warning,
        'info': AppColors.info,
        'inkMuted': AppColors.inkMuted,
        'brandDeep': AppColors.brandDeep,
      };
      tones.forEach((String name, Color tone) {
        final Color fill = over(tone.withValues(alpha: 0.14), contentSurface);
        expect(
          contrast(tone, fill),
          greaterThanOrEqualTo(4.5),
          reason: '$name badge label on its 14% fill',
        );
      });
    });

    test('soft container fills carry their paired text colour', () {
      final List<(String, Color, Color)> pairs = <(String, Color, Color)>[
        ('danger', AppColors.danger, AppColors.dangerSoft),
        ('success', AppColors.success, AppColors.successSoft),
        ('warning', AppColors.warning, AppColors.warningSoft),
        ('info', AppColors.info, AppColors.infoSoft),
        ('brand', AppColors.brandDeep, AppColors.brandSoft),
      ];
      for (final (String name, Color fg, Color bg) in pairs) {
        expect(
          contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$name on its soft fill',
        );
      }
    });

    test('white labels clear AA on every solid flat fill', () {
      for (final Color fill in <Color>[
        AppColors.brand,
        AppColors.brandDeep,
        AppColors.danger,
        AppColors.success,
        AppColors.info,
        AppColors.accent,
        AppColors.ink,
      ]) {
        expect(contrast(AppColors.onFill, fill), greaterThanOrEqualTo(4.5));
      }
    });

    test('the glass fills are opaque enough to be predictable at all', () {
      // The guidance is explicit: a light-mode glass card needs ~80% white, not
      // 10%. Below roughly 70% the effective background — and therefore the
      // contrast ratio — becomes a function of whatever scrolls past.
      expect(GlassColors.surface.a, greaterThanOrEqualTo(0.80));
      expect(GlassColors.chrome.a, greaterThanOrEqualTo(0.70));
    });

    test('the field itself stays pale enough to be a background', () {
      // A saturated backdrop is the usual reason glass UIs fail contrast. If the
      // worst point of the field ever gets dark, this catches it before the text
      // assertions do.
      expect(luminance(worstField), greaterThan(0.6));
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('blur budget', () {
    Widget host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: AppBackground(child: Scaffold(body: child)),
      ),
    );

    testWidgets('GlassSurface does not blur unless asked', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(const GlassSurface(child: Text('x'))));
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('GlassSurface(blurred: true) does blur', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(const GlassSurface(blurred: true, child: Text('x'))),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('a long list of GlassCards adds ZERO blur layers', (
      WidgetTester tester,
    ) async {
      // The whole reason blur is opt-in. Fifty rows each with their own
      // BackdropFilter is fifty save-layers per frame, and the list stutters.
      await tester.pumpWidget(
        host(
          ListView(
            children: <Widget>[
              for (int i = 0; i < 50; i++) GlassCard(child: Text('row $i')),
            ],
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('GlassPanel does not blur either', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(const GlassPanel(title: 'x', child: Text('y'))),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('a screenful of chrome stays inside the budget', (
      WidgetTester tester,
    ) async {
      // Simulates the worst realistic frame: app bar + bottom nav + a hero
      // surface + an open dialog, all blurred at once.
      await tester.pumpWidget(
        host(
          Column(
            children: <Widget>[
              const GlassSurface(blurred: true, child: Text('app bar')),
              const GlassSurface(blurred: true, child: Text('hero')),
              const GlassSurface(blurred: true, child: Text('dialog')),
              const GlassSurface(blurred: true, child: Text('nav')),
              Expanded(
                child: ListView(
                  children: <Widget>[
                    for (int i = 0; i < 20; i++)
                      GlassCard(child: Text('row $i')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        tester.widgetList(find.byType(BackdropFilter)).length,
        lessThanOrEqualTo(kGlassBlurBudget),
      );
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('motion and touch', () {
    testWidgets('reduced motion is detected from either platform signal', (
      WidgetTester tester,
    ) async {
      for (final (bool disable, bool a11yNav, bool expected)
          in <(bool, bool, bool)>[
            (false, false, false),
            (true, false, true),
            (false, true, true),
          ]) {
        late bool seen;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              disableAnimations: disable,
              accessibleNavigation: a11yNav,
            ),
            child: Builder(
              builder: (BuildContext context) {
                seen = prefersReducedMotion(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(seen, expected, reason: 'disable=$disable a11yNav=$a11yNav');
      }
    });

    test('animation durations are inside the 150-300ms guidance', () {
      expect(AppMotion.fast.inMilliseconds, inInclusiveRange(150, 300));
      expect(AppMotion.base.inMilliseconds, inInclusiveRange(150, 300));
    });

    test('interactive controls clear the 44px minimum target', () {
      final ThemeData theme = buildAppTheme();
      final Size? filled = theme.filledButtonTheme.style?.minimumSize?.resolve(
        <WidgetState>{},
      );
      final Size? outlined = theme.outlinedButtonTheme.style?.minimumSize
          ?.resolve(<WidgetState>{});
      final Size? text = theme.textButtonTheme.style?.minimumSize?.resolve(
        <WidgetState>{},
      );
      final Size? icon = theme.iconButtonTheme.style?.minimumSize?.resolve(
        <WidgetState>{},
      );
      expect(filled!.height, greaterThanOrEqualTo(44));
      expect(outlined!.height, greaterThanOrEqualTo(44));
      expect(text!.height, greaterThanOrEqualTo(44));
      expect(icon!.height, greaterThanOrEqualTo(44));
      expect(icon.width, greaterThanOrEqualTo(44));
    });

    test('body text is at least 16px and leads at 1.5 or more', () {
      final TextTheme t = buildAppTheme().textTheme;
      expect(t.bodyLarge!.fontSize, greaterThanOrEqualTo(16));
      expect(t.bodyLarge!.height, greaterThanOrEqualTo(1.5));
      expect(t.bodyMedium!.height, greaterThanOrEqualTo(1.5));
    });

    test('a visible focus ring is defined, not left to the default', () {
      final InputBorder? focused =
          buildAppTheme().inputDecorationTheme.focusedBorder;
      expect(focused, isA<OutlineInputBorder>());
      expect((focused! as OutlineInputBorder).borderSide.width, 2);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('typography', () {
    // Two families, two different correctness conditions.
    //
    // Cairo is VARIABLE: one file, and the `wght` axis has to respond to
    // TextStyle.fontWeight. That is measurable by glyph advance.
    //
    // Tajawal is STATIC: four separate files, and correctness means the pubspec
    // maps each to the right `weight:` key. FontLoader cannot express weight
    // mapping, so the axis trick does not apply — loading one file under the
    // family name would make every weight measure identically and the test would
    // be meaningless. Instead: the declaration is checked, and the files are
    // checked to be genuinely different faces rather than four copies of one.
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final FontLoader cairo = FontLoader(AppFonts.body)
        ..addFont(
          Future<ByteData>.value(
            File(
              'assets/fonts/Cairo-Variable.ttf',
            ).readAsBytesSync().buffer.asByteData(),
          ),
        );
      await cairo.load();

      // Each Tajawal weight under its own probe family, so they can be compared.
      for (final String w in <String>[
        'Regular',
        'Medium',
        'Bold',
        'ExtraBold',
      ]) {
        final FontLoader loader = FontLoader('TajawalProbe$w')
          ..addFont(
            Future<ByteData>.value(
              File(
                'assets/fonts/Tajawal-$w.ttf',
              ).readAsBytesSync().buffer.asByteData(),
            ),
          );
        await loader.load();
      }
    });

    double advance(String family, [FontWeight weight = FontWeight.w400]) {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: 'جمعية العائلة ١٢٣٤',
          style: TextStyle(
            fontFamily: family,
            fontSize: 40,
            fontWeight: weight,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      return painter.width;
    }

    test('Cairo responds to fontWeight (variable wght axis is wired)', () {
      expect(
        advance(AppFonts.body, FontWeight.w800),
        greaterThan(advance(AppFonts.body, FontWeight.w400)),
        reason:
            'Cairo is declared as a single variable file. If the axis is not '
            'driven by fontWeight, every inline w800 in the app renders regular.',
      );
    });

    test('Tajawal ships four genuinely distinct weight files', () {
      // Four copies of one file would satisfy the pubspec and render one weight.
      final Set<double> widths = <double>{
        for (final String w in <String>[
          'Regular',
          'Medium',
          'Bold',
          'ExtraBold',
        ])
          advance('TajawalProbe$w'),
      };
      expect(
        widths.length,
        greaterThan(1),
        reason: 'the four Tajawal files render identically — same face copied?',
      );
      expect(
        advance('TajawalProbeExtraBold'),
        greaterThan(advance('TajawalProbeRegular')),
        reason: 'ExtraBold should set wider than Regular',
      );
    });

    test('every declared font asset exists and is mapped to a weight', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();

      // Tajawal: static, so each weight needs its own asset AND its own key.
      for (final (String file, int weight) in <(String, int)>[
        ('Tajawal-Regular.ttf', 400),
        ('Tajawal-Medium.ttf', 500),
        ('Tajawal-Bold.ttf', 700),
        ('Tajawal-ExtraBold.ttf', 800),
      ]) {
        expect(
          File('assets/fonts/$file').existsSync(),
          isTrue,
          reason: '$file is declared but missing',
        );
        expect(
          pubspec,
          contains('asset: assets/fonts/$file'),
          reason: '$file is not declared',
        );
        expect(
          pubspec,
          contains('weight: $weight'),
          reason: '$file has no weight key, so fontWeight cannot select it',
        );
      }

      expect(File('assets/fonts/Cairo-Variable.ttf').existsSync(), isTrue);
      expect(pubspec, contains('asset: assets/fonts/Cairo-Variable.ttf'));

      // And nothing left behind from the previous pairing.
      expect(pubspec, isNot(contains('Noto')));
      expect(
        Directory('assets/fonts')
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.contains('Noto'))
            .toList(),
        isEmpty,
        reason: 'orphaned font files still ship in the bundle',
      );
    });

    test('the theme actually uses the declared families', () {
      final TextTheme t = buildAppTheme().textTheme;
      expect(t.headlineMedium!.fontFamily, AppFonts.display);
      expect(t.titleLarge!.fontFamily, AppFonts.display);
      expect(t.bodyLarge!.fontFamily, AppFonts.body);
      expect(t.bodySmall!.fontFamily, AppFonts.body);
      expect(AppFonts.display, 'Tajawal');
      expect(AppFonts.body, 'Cairo');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  group('flat design discipline', () {
    // A source scan, in the spirit of tool/rtl_lint.dart. Flat Design's rules are
    // negative — "no gradients", "no decorative shadows" — and negative rules do
    // not survive without something that fails.
    List<File> screenFiles() => Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    /// Source with `//` comments stripped.
    ///
    /// The first version of the gradient check flagged a COMMENT that explained a
    /// gradient had been REMOVED. A lint that fires on prose is the kind that
    /// gets deleted rather than fixed.
    String code(File f) => f
        .readAsLinesSync()
        .map((String line) {
          final int i = line.indexOf('//');
          return i == -1 ? line : line.substring(0, i);
        })
        .join('\n');

    test('no screen paints a gradient', () {
      final List<String> offenders = <String>[];
      for (final File f in screenFiles()) {
        final String src = code(f);
        for (final String banned in <String>[
          'LinearGradient',
          'RadialGradient',
          'SweepGradient',
        ]) {
          if (src.contains(banned)) {
            offenders.add('${f.path}: $banned');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Flat Design has no gradients. The vibrant field in '
            'core/widgets/app_background.dart is the only gradient in the app, '
            'and it exists because Glassmorphism needs something to blur.',
      );
    });

    test('no screen paints its own drop shadow', () {
      final List<String> offenders = <String>[];
      for (final File f in screenFiles()) {
        if (code(f).contains('boxShadow')) {
          offenders.add(f.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Depth comes from GlassSurface(lifted: true) on floating chrome '
            'only. A shadow anywhere else is decoration, which Flat forbids.',
      );
    });

    test('screens do not hard-code an opaque white SURFACE', () {
      // An opaque white card punches a hole in the glass layer and is the most
      // likely way this design gets partially undone.
      //
      // Scoped to surface-creating properties only. The first version banned
      // `Colors.white` outright and flagged six files whose white was a spinner
      // or an icon drawn ON a saturated fill — which is correct, and is what
      // AppColors.onFill exists for. A lint that fires on correct code gets
      // deleted, so it is narrowed instead of loosened.
      const List<String> surfaceProps = <String>[
        'fillColor: Colors.white',
        'backgroundColor: Colors.white',
        'scaffoldBackgroundColor: Colors.white',
        'Card(color: Colors.white',
        'surfaceTintColor: Colors.white',
      ];
      final List<String> offenders = <String>[];
      for (final File f in screenFiles()) {
        final String src = code(f);
        for (final String prop in surfaceProps) {
          if (src.contains(prop)) offenders.add('${f.path}: $prop');
        }
        // Formatting splits `decoration: BoxDecoration(color: Colors.white)`
        // across lines, so whitespace is collapsed before comparing. The Google
        // sign-in mark is exempt: white is fixed by Google's brand guidelines.
        final String flat = src.replaceAll(RegExp(r'\s+'), ' ');
        if (flat.contains('BoxDecoration( color: Colors.white') &&
            !f.path.contains('google_sign_in_button')) {
          offenders.add('${f.path}: BoxDecoration(color: Colors.white)');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Use GlassCard / GlassColors.surface, not an opaque white fill.',
      );
    });
  });
}
