import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/features/oversight/presentation/period_picker_dialog.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// «إقفال شهر» مطويّةٌ على آخر شهرٍ أُقفل (15/09). The rules of the full list
/// itself — one tappable month, blocked months inert — live in
/// period_picker_test.dart, against the real wire fixture.
///
/// «اريد عرض حاوية بها اخر شهر تم اقفالة واذا اردت رؤية القائمة اضغط على هذه
/// الحاوية تنسل ويظهر كل الاقفالات كما هي الان».
///
/// The live ledger closes 2024-12 → 2026-09: twenty-two months, all closed —
/// which is exactly the list that no longer fitted on a phone.
List<ClosablePeriod> _months({String? openPeriod}) {
  final List<ClosablePeriod> out = <ClosablePeriod>[];
  DateTime d = DateTime(2024, 12);
  final DateTime last = openPeriod == null
      ? DateTime(2026, 9)
      : DateTime(2026, 10);
  while (!d.isAfter(last)) {
    final String p = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final bool isOpen = p == openPeriod;
    out.add(
      ClosablePeriod(
        period: p,
        label: 'شهر $p',
        closed: !isOpen,
        selectable: isOpen,
      ),
    );
    d = DateTime(d.year, d.month + 1);
  }
  return out.reversed.toList(); // newest first, as the server sends them
}

Future<void> _pump(
  WidgetTester tester,
  List<ClosablePeriod> months, {
  double width = 411,
  double height = 800,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        closablePeriodsProvider.overrideWith((Ref ref) async => months),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: const Scaffold(body: Center(child: PeriodPickerDialog())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final L l = LAr();
  tearDown(() => applyAppTheme(AppThemeMode.light));

  testWidgets('it opens folded on the last closed month, and nothing else', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _months());

    expect(find.text(l.periodLastClosed), findsOneWidget);
    expect(find.text('شهر 2026-09'), findsOneWidget);
    expect(find.text(l.periodShowAll), findsOneWidget);
    // No other month is on screen until the container is opened.
    expect(find.text('شهر 2026-08'), findsNothing);
    expect(find.text('شهر 2024-12'), findsNothing);
    expect(find.byType(PeriodRow), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the container opens every month, as the list was', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _months());

    await tester.tap(find.text(l.periodLastClosed));
    await tester.pumpAndSettle();

    expect(find.byType(PeriodRow), findsNWidgets(22));
    expect(find.text(l.periodHideAll), findsOneWidget);
    // The oldest month is reachable by scrolling inside the dialog.
    await tester.dragUntilVisible(
      find.text('شهر 2024-12'),
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    expect(find.text('شهر 2024-12'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // And tapping again folds it.
    await tester.dragUntilVisible(
      find.text(l.periodLastClosed),
      find.byType(SingleChildScrollView),
      const Offset(0, 200),
    );
    await tester.tap(find.text(l.periodLastClosed));
    await tester.pumpAndSettle();
    expect(find.byType(PeriodRow), findsNothing);
  });

  testWidgets('⚠ the month that CAN be closed stays outside the fold', (
    WidgetTester tester,
  ) async {
    // 1 October: October is open, September is the last closed.
    await _pump(tester, _months(openPeriod: '2026-10'));

    // The one actionable row is visible without opening anything...
    final Finder open = find.widgetWithText(PeriodRow, 'شهر 2026-10');
    expect(open, findsOneWidget);
    final Text label = tester.widget<Text>(find.text('شهر 2026-10'));
    expect(label.style?.color, AppColors.month);
    // ...above the folded container naming September.
    expect(find.text('شهر 2026-09'), findsOneWidget);
    expect(find.byType(PeriodRow), findsOneWidget);

    // Opened, October is not listed twice.
    await tester.tap(find.text(l.periodLastClosed));
    await tester.pumpAndSettle();
    expect(find.text('شهر 2026-10'), findsOneWidget);
    expect(find.byType(PeriodRow), findsNWidgets(23));
  });

  testWidgets('tapping the open month returns it to the caller', (
    WidgetTester tester,
  ) async {
    ClosablePeriod? chosen;
    tester.view.physicalSize = const Size(411, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          closablePeriodsProvider.overrideWith(
            (Ref ref) async => _months(openPeriod: '2026-10'),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await showDialog<ClosablePeriod>(
                    context: context,
                    builder: (_) => const PeriodPickerDialog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('شهر 2026-10'));
    await tester.pumpAndSettle();
    expect(chosen?.period, '2026-10');
  });

  testWidgets('with nothing closed yet there is no fold', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const <ClosablePeriod>[
      ClosablePeriod(
        period: '2024-12',
        label: 'شهر 2024-12',
        closed: false,
        selectable: true,
      ),
    ]);
    expect(find.text(l.periodLastClosed), findsNothing);
    expect(find.byType(PeriodRow), findsOneWidget);
  });

  for (final AppThemeMode mode in AppThemeMode.values) {
    testWidgets(
      '22 months fit a 320×640 phone, open and closed, ${mode.name}',
      (WidgetTester tester) async {
        applyAppTheme(mode);
        await _pump(
          tester,
          _months(openPeriod: '2026-10'),
          width: 320,
          height: 640,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(l.periodLastClosed));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
