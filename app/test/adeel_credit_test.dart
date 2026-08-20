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

/// العهدة — what a man has handed over that no month has claimed yet, on the
/// staff's own view of him.
///
/// The figure already travelled: `api_adeel_detail` has returned `credit` since
/// the wallet was built, and the portal has shown him his own. The association's
/// side of the same screen did not, so a treasurer taking a payment could not
/// see that the man was already months ahead.
///
/// ⚠ AND IT IS THE ONE TINTED CARD IN THAT GRID, which is the whole reason it
///   works. Five recessed wells and one that is not is a difference found
///   without being looked for; a second tinted card would turn it into a colour
///   scheme and the reader would start comparing them instead of noticing one.
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

AdeelDetail _detail({required String credit}) =>
    AdeelDetail.fromJson(<String, dynamic>{
      'adeel': <String, dynamic>{
        'id': 1,
        'adeelCode': 'A-01',
        'fullName': 'محمد العدولي',
        'phone': '0910000000',
        'notes': '',
        'registeredAt': '2026-01-01',
        'membershipStatus': 'نشط',
        'debt': '0.00',
        'paid': '600.00',
        'issued': '200.00',
        'monthlyExpected': '100.00',
      },
      'kpis': <String, dynamic>{
        'monthlyExpected': '100.00',
        'issued': '200.00',
        'debt': '0.00',
        'paid': '600.00',
        'openPeriods': 0,
        'credit': credit,
        'netBalance': '-$credit',
      },
      'receivables': <dynamic>[],
      'payments': <dynamic>[],
    });

/// Opens the screen and unfolds ملخص المشترك, because the grid arrives closed.
Future<L> _open(WidgetTester tester, {required String credit}) async {
  tester.view.physicalSize = const Size(411, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(_StubAuth.new),
        adeelDetailProvider(
          1,
        ).overrideWith((Ref ref) async => _detail(credit: credit)),
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

  final L l = LAr();
  await tester.tap(find.text(l.familySummary));
  await tester.pumpAndSettle();
  return l;
}

/// The Container the tinted card paints itself with.
BoxDecoration _cardOf(WidgetTester tester, Finder label) {
  final Finder box = find
      .ancestor(of: label, matching: find.byType(Container))
      .first;
  return tester.widget<Container>(box).decoration! as BoxDecoration;
}

void main() {
  testWidgets('a man who paid ahead shows العهدة in the summary', (
    WidgetTester tester,
  ) async {
    final L l = await _open(tester, credit: '400.00');

    expect(find.text(l.adeelCredit), findsOneWidget);
    expect(find.text(formatMoney('400.00')), findsWidgets);
  });

  // ⚠ THE HALF THAT KEEPS IT MEANING SOMETHING. «العهدة: 0.00» on every man is
  //   one true fact repeated until it stops being read — and a card coloured
  //   unlike its five neighbours has to MEAN something on the days it appears.
  testWidgets('...and a man with none does not get an empty card', (
    WidgetTester tester,
  ) async {
    final L l = await _open(tester, credit: '0.00');

    expect(find.text(l.adeelCredit), findsNothing);
    // The rest of the grid is still there, so "found nothing" cannot be
    // "rendered nothing".
    expect(find.text(l.totalPaid), findsOneWidget);
  });

  testWidgets('the card wears the tone, it does not merely print in it', (
    WidgetTester tester,
  ) async {
    final L l = await _open(tester, credit: '400.00');

    final BoxDecoration card = _cardOf(tester, find.text(l.adeelCredit));

    // ⚠ AppColors.warning, THE SAME عهدة AS EVERYWHERE ELSE — the treasury
    //   summary, the dashboard and the member's own portal all use it for this
    //   one idea. A sixth colour on the sixth screen makes it a sixth concept.
    expect(card.color!.r, AppColors.warning.r);
    expect(card.color!.g, AppColors.warning.g);
    expect(card.color!.b, AppColors.warning.b);
    expect(card.color!.a, lessThan(1.0), reason: 'a tint, not a fill');

    // And the label joins it, which is what the association asked for: the
    // container, the writing and the figure, not the figure alone.
    final Text label = tester.widget<Text>(find.text(l.adeelCredit));
    expect(label.style?.color, AppColors.warning);
  });

  testWidgets('and its NEIGHBOURS stay plain, so it is the only tinted one', (
    WidgetTester tester,
  ) async {
    final L l = await _open(tester, credit: '400.00');

    for (final String plain in <String>[l.totalPaid, l.issuedLabel]) {
      final BoxDecoration card = _cardOf(tester, find.text(plain));
      expect(
        card.color,
        GlassColors.well,
        reason: '$plain must stay a plain recessed well',
      );
    }
  });
}
