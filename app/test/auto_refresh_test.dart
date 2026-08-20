import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/state/auto_refresh.dart';
import 'package:family_app/core/widgets/async_view.dart';
import 'package:family_app/core/widgets/state_views.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app keeps itself current, and does not blink while doing it.
///
/// ── THE TWO HALVES ARE ONE FEATURE ──────────────────────────────────────────
/// Refreshing every read on a clock is worthless if every list flashes a spinner
/// while it happens — that is a worse screen than the stale figure it replaced,
/// and it is what `value.when(loading: spinner)` does on every `ref.invalidate`.
/// So the interval and the keep-the-last-answer rule are tested together.

void main() {
  testWidgets('the first load shows the spinner — there is nothing else', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(const AsyncValue<String>.loading()),
    );
    await tester.pump();

    expect(find.byType(LoadingStateView), findsOneWidget);
  });

  testWidgets('⚠ but a REFRESH keeps the figure that is already there', (
    WidgetTester tester,
  ) async {
    // The whole reason auto-refresh is usable. Every forty-five seconds every
    // provider goes back to loading; without this the treasury, the register and
    // the dashboard all blink to a spinner in step.
    await tester.pumpWidget(
      _host(const AsyncValue<String>.loading().copyWithPrevious(
        const AsyncValue<String>.data('1650.00'),
      )),
    );
    await tester.pumpAndSettle();

    expect(find.text('1650.00'), findsOneWidget);
    expect(find.byType(LoadingStateView), findsNothing);
  });

  testWidgets('⚠ and a FAILED refresh keeps it too', (
    WidgetTester tester,
  ) async {
    // The harder call, and the one that matters on a money screen: blanking a
    // treasury to «حدث خطأ» because one background tick lost the network is a
    // worse lie than a figure forty-five seconds old. The next tick corrects it
    // with nobody doing anything.
    await tester.pumpWidget(
      _host(
        AsyncValue<String>.error(Exception('offline'), StackTrace.empty)
            .copyWithPrevious(const AsyncValue<String>.data('1650.00')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1650.00'), findsOneWidget);
    expect(find.byType(ErrorStateView), findsNothing);
  });

  testWidgets('...while an error with nothing behind it IS an error page', (
    WidgetTester tester,
  ) async {
    // The case somebody must actually act on: a first load that failed. Hiding
    // this one would turn a broken install into a blank screen.
    await tester.pumpWidget(
      _host(AsyncValue<String>.error(Exception('offline'), StackTrace.empty)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ErrorStateView), findsOneWidget);
  });

  test('the clock is a judgement, and it is written down', () {
    // Pinned so the number cannot drift without somebody reading the note above
    // it: faster is more requests on a project the association does not pay for,
    // slower is the complaint that produced the feature.
    expect(AutoRefresh.interval, const Duration(seconds: 45));
  });

  testWidgets('AutoRefresh renders its child and nothing else', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AutoRefresh(child: Text('الرئيسية', textDirection: TextDirection.rtl)),
        ),
      ),
    );
    expect(find.text('الرئيسية'), findsOneWidget);
  });
}

Widget _host(AsyncValue<String> value) => ProviderScope(
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('ar'),
    localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
    supportedLocales: L.supportedLocales,
    home: Scaffold(
      body: AsyncView<String>(
        value: value,
        builder: (String data) => Text(data),
      ),
    ),
  ),
);
