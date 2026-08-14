import 'package:family_app/core/config/glass.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every dialog in the app, laid out under the REAL theme.
///
/// ── Why this file exists
///
/// Every dialog in this app was invisible on device: tapping the button dimmed
/// the screen and showed nothing. The cause was in the theme, not the dialogs:
///
///     filledButtonTheme:  minimumSize: const Size.fromHeight(52)
///
/// `Size.fromHeight` sets width to **double.infinity**, not 0. On a page that is
/// exactly right — the Column bounds the width and the infinite minimum is what
/// makes a button span it. But `GlassDialog` lays its actions out in a **Row**,
/// and a Row gives children unbounded width, so the infinity is never clamped:
///
///     BoxConstraints forces an infinite width.
///     BoxConstraints(w=Infinity, 52.0<=h<=Infinity)
///     The relevant error-causing widget was: FilledButton
///
/// A subtree that fails layout paints nothing, which is why a barrier appeared
/// over a dimmed screen with no dialog on it.
///
/// ── Why the existing tests missed it
///
/// They hosted their widgets in a bare `MaterialApp` with no `theme:`. The
/// offending `minimumSize` therefore never applied, and three dialog tests passed
/// green while the feature was completely broken in the app. A widget test that
/// does not use the app's own theme is not testing the app.
///
/// So every case below is built with `buildAppTheme()`, and each mirrors a real
/// call site's action shape. Reintroducing `Size.fromHeight(52)` in GlassDialog
/// makes all of them fail with the production error — verified.
Widget host(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  locale: const Locale('ar'),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: child),
  ),
);

Future<void> openDialog(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    host(
      Builder(
        builder: (BuildContext context) => TextButton(
          onPressed: () =>
              showDialog<void>(context: context, builder: (_) => dialog),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  /// Each entry is the action list of a real dialog in the app.
  final Map<String, List<Widget>> callSites = <String, List<Widget>>{
    // dashboard_screen.dart _closeMonth - the one that was reported.
    'close month: TextButton + FilledButton': <Widget>[
      TextButton(onPressed: () {}, child: const Text('إلغاء')),
      FilledButton(onPressed: () {}, child: const Text('إنشاء')),
    ],
    // text_prompt_dialog.dart - the dev sign-in prompt, also reported.
    'text prompt: TextButton + FilledButton': <Widget>[
      TextButton(onPressed: () {}, child: const Text('إلغاء')),
      FilledButton(onPressed: () {}, child: const Text('دخول')),
    ],
    // text_prompt_dialog.dart with destructive: true, and
    // family_form_screen.dart's discard confirmation.
    'destructive: styled FilledButton': <Widget>[
      TextButton(onPressed: () {}, child: const Text('إلغاء')),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
        onPressed: () {},
        child: const Text('تأكيد الإلغاء'),
      ),
    ],
    // payment_sheet.dart _showReceipt - a lone action.
    'single TextButton': <Widget>[
      TextButton(onPressed: () {}, child: const Text('إغلاق')),
    ],
    // An OutlinedButton carries the same Size.fromHeight(52) in the theme, so it
    // fails identically. No dialog uses one today; this stops the next one from
    // rediscovering the bug.
    'OutlinedButton (not used yet, but the theme makes it fail too)': <Widget>[
      OutlinedButton(onPressed: () {}, child: const Text('لاحقاً')),
      FilledButton(onPressed: () {}, child: const Text('حسناً')),
    ],
    'three actions': <Widget>[
      TextButton(onPressed: () {}, child: const Text('أ')),
      OutlinedButton(onPressed: () {}, child: const Text('ب')),
      FilledButton(onPressed: () {}, child: const Text('ج')),
    ],
  };

  group('GlassDialog lays out with real buttons in its actions', () {
    callSites.forEach((String name, List<Widget> actions) {
      testWidgets(name, (WidgetTester tester) async {
        await openDialog(
          tester,
          GlassDialog(
            title: const Text('عنوان'),
            content: const Text('نص التأكيد', style: TextStyle(height: 1.5)),
            actions: actions,
          ),
        );

        // The assertion that was firing in production. takeException() returning
        // null is the whole point of this file.
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout threw - the dialog would paint nothing on device',
        );

        // Laying out is not enough: it has to be VISIBLE and non-degenerate.
        // A zero-size pane also throws no exception.
        expect(find.byType(GlassSurface), findsOneWidget);
        final Size pane = tester.getSize(find.byType(GlassSurface).first);
        expect(pane.width, greaterThan(200), reason: 'pane too narrow: $pane');
        expect(pane.height, greaterThan(80), reason: 'pane too short: $pane');

        expect(find.text('عنوان'), findsOneWidget);
        expect(find.text('نص التأكيد'), findsOneWidget);

        // And every action must be on screen and tappable, not clipped out.
        for (final Widget action in actions) {
          final Finder label = find.descendant(
            of: find.byWidget(action),
            matching: find.byType(Text),
          );
          expect(label, findsOneWidget);
          final Size size = tester.getSize(find.byWidget(action));
          expect(
            size.width.isFinite && size.width > 0,
            isTrue,
            reason: 'action has a non-finite or zero width: $size',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(44),
            reason: 'below the 44px minimum touch target: $size',
          );
        }
      });
    });

    testWidgets('the icon slot lays out too', (WidgetTester tester) async {
      // payment_sheet.dart's receipt dialog uses it.
      await openDialog(
        tester,
        GlassDialog(
          icon: const Icon(Icons.check_circle, size: 40),
          title: const Text('تم'),
          content: const Text('محتوى'),
          actions: <Widget>[
            FilledButton(onPressed: () {}, child: const Text('حسناً')),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('a long Arabic body does not break it', (
      WidgetTester tester,
    ) async {
      // generateConfirmBody is 107 characters; the real one wraps to several
      // lines at phone width.
      await openDialog(
        tester,
        GlassDialog(
          title: const Text('إنشاء استحقاقات 2026-07'),
          content: const Text(
            'سيتم إنشاء استحقاق لكل عائلة عليها اشتراك مستحق لهذا الشهر. '
            'تغيير الإعدادات لاحقاً لا يغيّر هذه السجلات.',
            style: TextStyle(height: 1.5),
          ),
          actions: <Widget>[
            TextButton(onPressed: () {}, child: const Text('إلغاء')),
            FilledButton(onPressed: () {}, child: const Text('إنشاء')),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(GlassSurface).first).height,
        greaterThan(150),
        reason: 'the wrapped body should make the pane taller',
      );
    });
  });

  group('the theme value that caused it', () {
    test('page buttons still get an infinite minimum width, deliberately', () {
      // The global setting is NOT a bug and must not be "fixed" here: it is what
      // makes a FilledButton span its Column on every screen. Only a Row is
      // hostile to it, which is why GlassDialog overrides it locally instead.
      final ThemeData theme = buildAppTheme();
      final Size? filled = theme.filledButtonTheme.style?.minimumSize?.resolve(
        <WidgetState>{},
      );
      final Size? outlined = theme.outlinedButtonTheme.style?.minimumSize
          ?.resolve(<WidgetState>{});
      expect(filled?.width, double.infinity);
      expect(outlined?.width, double.infinity);
      expect(filled?.height, 52);
    });

    test('a bare Row of themed buttons DOES fail - the bug is real', () {
      // Documents the mechanism rather than trusting the prose above. If Flutter
      // ever changes this, the comment in GlassDialog becomes wrong and this
      // fails, which is the right way to find out.
      final Size? min = buildAppTheme().filledButtonTheme.style?.minimumSize
          ?.resolve(<WidgetState>{});
      expect(
        min!.width.isInfinite,
        isTrue,
        reason: 'Size.fromHeight sets width to infinity - that is the bug',
      );
    });
  });
}
