import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/widgets/stat_card.dart';
import 'package:family_app/core/widgets/text_prompt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression cover for the two console crashes.
///
/// Both were reported from a running app, so both need a check that fails if
/// the old shape comes back — reading the code is not evidence.
/// Hosts a widget under the REAL app theme.
///
/// This used to be a bare `MaterialApp` with no theme, and that gap let every
/// dialog in the app ship broken: the failure came from
/// `filledButtonTheme.minimumSize`, which a themeless host never applies. These
/// tests passed while the app showed a dimmed screen and no dialog at all.
///
/// A widget test that does not use the app's own theme is not testing the app.
Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  locale: const Locale('ar'),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

/// A faithful copy of the private stat card the four screens render
/// (dashboard_screen.dart `_Stat`). The test has to use the real thing: the
/// overflow came from that card's intrinsic height exceeding the height a
/// `childAspectRatio` allowed it, so a slimmer stand-in would not reproduce it.
class _ScreenStat extends StatelessWidget {
  const _ScreenStat({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            if (sub != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                sub!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void main() {
  group('showTextPrompt', () {
    // The old code built the controller in the calling function and disposed
    // it after `await showDialog(...)`. The dialog's exit transition still
    // paints for ~200ms after the future completes, so the field rebuilt
    // against a disposed controller: "A TextEditingController was used after
    // being disposed". Cancelling, then settling, is exactly that window.
    testWidgets('cancelling then settling does not touch a dead controller', (
      WidgetTester tester,
    ) async {
      String? result = 'unset';

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                result = await showTextPrompt(
                  context,
                  title: 'title',
                  message: 'message',
                  fieldLabel: 'label',
                  confirmLabel: 'confirm',
                  cancelLabel: 'cancel',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('title'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'typed then abandoned');
      await tester.pump();

      await tester.tap(find.text('cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('submitting returns the trimmed text', (
      WidgetTester tester,
    ) async {
      String? result;

      await tester.pumpWidget(
        _host(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async {
                result = await showTextPrompt(
                  context,
                  title: 'title',
                  message: 'message',
                  fieldLabel: 'label',
                  confirmLabel: 'confirm',
                  cancelLabel: 'cancel',
                  initialValue: 'seeded@example.com',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The seed reaches the field, so the caller's default is editable
      // rather than merely a hint.
      expect(find.text('seeded@example.com'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '  spaced@example.com  ');
      await tester.tap(find.text('confirm'));
      await tester.pumpAndSettle();

      expect(result, 'spaced@example.com');
      expect(tester.takeException(), isNull);
    });

    testWidgets('reopening after a cancel builds a fresh controller', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showTextPrompt(
                context,
                title: 'title',
                message: 'message',
                fieldLabel: 'label',
                confirmLabel: 'confirm',
                cancelLabel: 'cancel',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      for (int attempt = 0; attempt < 3; attempt++) {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'attempt $attempt');
        await tester.tap(find.text('cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('StatCardGrid', () {
    // The four dashboards used GridView.count with childAspectRatio between
    // 1.55 and 2.4. A ratio pins height to a fraction of width, so a narrow
    // phone or a raised text scale overflowed every card by ~30px. Height is
    // now intrinsic, so neither can overflow.
    for (final (double width, double scale) in <(double, double)>[
      (320, 1.0),
      (360, 1.3),
      (411, 2.0),
      (800, 1.6),
    ]) {
      testWidgets('does not overflow at ${width}px, text scale $scale', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: SingleChildScrollView(
                child: StatCardGrid(
                  children: <Widget>[
                    for (int i = 0; i < 6; i++)
                      _ScreenStat(
                        label: 'إجمالي المحصل من الاشتراكات $i',
                        value: '1,234,567.89',
                        sub: 'اليوم 12,345.67 • هذا الشهر 98,765.43',
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('widens to four columns past the breakpoint', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          StatCardGrid(
            children: <Widget>[
              for (int i = 0; i < 4; i++)
                _ScreenStat(label: 'label $i', value: '$i'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Four across 1200px, not two.
      expect(
        tester.getSize(find.byType(_ScreenStat).first).width,
        lessThan(1200 / 3),
      );
    });
  });
}
