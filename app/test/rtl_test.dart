import 'package:family_app/core/widgets/state_views.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  localizationsDelegates: L.localizationsDelegates,
  supportedLocales: L.supportedLocales,
  home: child,
);

void main() {
  testWidgets('the Arabic locale drives right-to-left layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(const ErrorStateView(message: 'خطأ')));
    await tester.pumpAndSettle();

    // Directionality is derived from the locale, so nothing in the tree needs
    // to wrap itself in a Directionality widget.
    final BuildContext context = tester.element(find.byType(ErrorStateView));
    expect(Directionality.of(context), TextDirection.rtl);
  });

  testWidgets('visible text is resolved from the ARB file, in Arabic', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(ErrorStateView(message: 'تعذّر تحميل البيانات', onRetry: () {})),
    );
    await tester.pumpAndSettle();

    // 'إعادة المحاولة' comes from app_ar.arb, not from a literal in the widget.
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    expect(find.text('تعذّر تحميل البيانات'), findsOneWidget);
  });

  testWidgets('an empty state reads as information, not as a failure', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EmptyStateView(
          icon: Icons.inbox_outlined,
          title: 'لا توجد تنبيهات حالية',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا توجد تنبيهات حالية'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('the English fallback locale still resolves every key', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L.localizationsDelegates,
        supportedLocales: L.supportedLocales,
        home: ErrorStateView(message: 'boom', onRetry: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    final BuildContext context = tester.element(find.byType(ErrorStateView));
    expect(Directionality.of(context), TextDirection.ltr);
  });
}
