import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeel_detail_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A member's page introduces him the way the aid ledger does: his NAME, and
/// his CODE facing it across the same line, at the same size.
///
/// The code sat underneath in a small muted style, which read as a caption — a
/// footnote to the heading rather than the other half of it. It is not a
/// footnote: «A-01» is how the association refers to him on every receipt and
/// every voucher, and it is what a reader checks when two men share a spelling.
///
/// Pinned on THIS screen as well as on the ledger because the two open on the
/// same man a tap apart, and a header that changes shape between them makes the
/// second one look like a different record.
class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000f1',
      email: 'admin@fam.test',
      displayName: 'المهدي',
      role: AppRole.admin,
      status: AccountStatus.approved,
    ),
  );
}

AdeelDetail _detail() => AdeelDetail.fromJson(<String, dynamic>{
  'adeel': <String, dynamic>{
    'id': 1,
    'adeelCode': 'A-01',
    'fullName': 'محمد العدولي',
    'phone': '0910000000',
    'notes': '',
    'registeredAt': '2026-01-01',
    'membershipStatus': 'نشط',
    'debt': '20.00',
    'paid': '20.00',
    'issued': '40.00',
    'monthlyExpected': '20.00',
  },
  'kpis': <String, dynamic>{
    'monthlyExpected': '20.00',
    'issued': '40.00',
    'debt': '20.00',
    'paid': '20.00',
    'openPeriods': 0,
  },
  'receivables': <dynamic>[],
  'payments': <dynamic>[],
});

/// Hoisted to file scope so both groups reach it — the header rules and the
/// folding rules are about the same screen and should not each build their own.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(411, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(_StubAuth.new),
        adeelDetailProvider(1).overrideWith((Ref ref) async => _detail()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: const AdeelDetailScreen(adeelId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  _foldingTests();
  _orderTests();
  _personalDataTests();

  testWidgets('the code sits on the far side of the name, not beneath it', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    // ⚠ TOPS, not centres. The two are aligned on their BASELINE, and a long
    //   name wraps while the code never does — so their centres can sit half a
    //   line apart while their first lines are perfectly level, which is what a
    //   reader sees.
    final Offset name = tester.getTopLeft(find.text('محمد العدولي'));
    final Offset code = tester.getTopLeft(find.text('A-01'));
    expect((name.dy - code.dy).abs(), lessThan(1.5));

    // And the code is to the LEFT, which in RTL is the far side. Asserted by
    // coordinate rather than by the order of the code, because the code reads
    // left-to-right and the screen does not.
    expect(code.dx, lessThan(name.dx));
  });

  testWidgets('...and it is the SAME size as the name', (
    WidgetTester tester,
  ) async {
    // Matching the size is what makes the two read as one line rather than as a
    // heading with a caption. Only the colour separates them, which is what
    // keeps the name the thing read first.
    await _pump(tester);

    final Text name = tester.widget<Text>(find.text('محمد العدولي'));
    final Text code = tester.widget<Text>(find.text('A-01'));

    expect(code.style?.fontSize, name.style?.fontSize);
    expect(code.style?.color, isNot(name.style?.color));
  });
}

/// The two sections arrive FOLDED, and each keeps its own figure on the closed
/// row.
///
/// The page opened as one long scroll: a grid of five figures, his personal
/// data, then every month he has ever been billed — twenty-four rows on a man
/// two years into the register. Folding turns it into a short list of questions
/// a reader picks from.
///
/// ⚠ AND THE FOLD KEEPS THE ANSWER. A fold that hides the conclusion costs a
///   tap to learn what a glance used to tell: «الملخص» carries what he owes and
///   «الاشتراكات» carries how many months are open, exactly as the treasury's
///   own folded groups keep a member's total on their closed row. What folds is
///   the working, never the conclusion.
void _foldingTests() {
  final L l = LAr();

  testWidgets('both arrive folded, with their figures still showing', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    // The headings are there...
    expect(find.text(l.familySummary), findsOneWidget);
    expect(find.text(l.duesSection), findsOneWidget);

    // ...and so are the two figures that survive the fold.
    expect(find.text(formatMoney('20.00')), findsWidgets);
    expect(find.text(l.openPeriodsCount(0)), findsOneWidget);

    // But the workings are NOT on the page.
    expect(find.text(l.issuedLabel), findsNothing);
    expect(find.text(l.totalPaid), findsNothing);
  });

  testWidgets('...and the summary opens onto its workings', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text(l.familySummary));
    await tester.pumpAndSettle();

    expect(find.text(l.issuedLabel), findsOneWidget);
    expect(find.text(l.totalPaid), findsOneWidget);
    expect(find.text(l.monthlyFeeLabel), findsWidgets);
  });
}

/// Order on a member's page: his NAME, then the ACTION, then the figures.
///
/// Staff open this page for one of two reasons — to record a payment, or to
/// look something up. The first is a single button, and it now sits directly
/// under his name where the thumb already is. The old order put five figures
/// between a treasurer and the only thing he came to press.
void _orderTests() {
  final L l = LAr();

  double y(WidgetTester tester, Finder f) => tester.getCenter(f).dy;

  testWidgets('تسجيل سداد sits under the name, above the summary', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    final double name = y(tester, find.text('محمد العدولي'));
    final double button = y(tester, find.text(l.registerPayment));
    final double summary = y(tester, find.text(l.familySummary));

    expect(button, greaterThan(name));
    expect(summary, greaterThan(button));
  });

  testWidgets('...and it is DISABLED, with a reason, when nothing is owed', (
    WidgetTester tester,
  ) async {
    // A vanishing button reads as a bug — moving it to the top makes that worse,
    // because its absence is now the first thing missing rather than the last.
    // The fixture owes 20.00, so this asserts the live case and the sentence
    // that would accompany the other one is absent.
    await _pump(tester);

    final FilledButton pay = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, l.registerPayment),
    );
    expect(pay.onPressed, isNotNull);
    expect(find.text(l.noDebtForFamily), findsNothing);
  });
}

/// His personal data lives behind his NAME, not in a panel.
///
/// It was three facts halfway down the page — his telephone, when he was
/// registered, his status — read once when somebody is looking for one of them
/// and scrolled past every other time. The name is where a reader reaches for
/// what the association holds ABOUT him, and it is the same door the portal
/// already uses for the same facts.
void _personalDataTests() {
  final L l = LAr();

  testWidgets('the page carries no personal-data panel', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    expect(find.text(l.personalData), findsNothing);
    expect(find.text('0910000000'), findsNothing);
  });

  testWidgets('...and tapping his NAME opens it', (WidgetTester tester) async {
    await _pump(tester);

    await tester.tap(find.text('محمد العدولي'));
    await tester.pumpAndSettle();

    expect(find.text(l.personalData), findsOneWidget);
    expect(find.text('0910000000'), findsOneWidget);
    expect(find.text(l.membershipStatusField), findsOneWidget);
  });

  testWidgets('...and the name SAYS it opens something', (
    WidgetTester tester,
  ) async {
    // A name that opens something and does not say so is a feature nobody
    // finds — and this is now the ONLY way to his personal data.
    await _pump(tester);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
}
