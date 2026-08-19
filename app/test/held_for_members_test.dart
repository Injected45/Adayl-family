import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/finance/presentation/cash_screen.dart';
import 'package:family_app/features/finance/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// عهد المشتركين on the treasury screen.
///
/// A member may pay a year ahead. The cash is in the box and `total` counts it,
/// but until the month it covers is billed it is owed back — so `balance`, the
/// figure under «رصيد الجمعية», excludes it, and `register_disbursement`
/// refuses anything above that same number.
///
/// ⚠ THE SCREEN MUST NOT PROMISE WHAT THE SERVER WILL REFUSE. That is the whole
///   reason the subtraction is server-side and this file only checks the
///   display: an admin who reads 60 and is refused 60 has no way to tell a bug
///   from a rule. The figures here are all `v_cash_summary`'s.
///
/// The subtitle is where a treasurer meets the difference. He has counted the
/// notes in his hand; the app shows him less; the line between the two says
/// why. Without it the app is simply wrong to the one person who can check it.

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

/// 60 collected, 40 still the members', 0 spent → 20 spendable.
const CashSummaryView _withHoldings = CashSummaryView(
  total: '60.00',
  cash: '35.00',
  transfer: '25.00',
  today: '0.00',
  month: '60.00',
  year: '60.00',
  outstanding: '0.00',
  disbursed: '0.00',
  heldForMembers: '40.00',
  balance: '20.00',
);

/// Nothing prepaid, so the amber line is absent and only the outflow shows.
const CashSummaryView _noHoldings = CashSummaryView(
  total: '60.00',
  cash: '60.00',
  transfer: '0.00',
  today: '0.00',
  month: '60.00',
  year: '60.00',
  outstanding: '0.00',
  disbursed: '5.00',
  heldForMembers: '0.00',
  balance: '55.00',
);

void main() {
  final L l = LAr();

  Widget host(CashSummaryView summary) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      cashSummaryProvider.overrideWith((Ref ref) async => summary),
      cashMovementsProvider.overrideWith(
        (Ref ref) async => <CashMovementView>[],
      ),
      disbursementsProvider.overrideWith(
        (Ref ref) async => <DisbursementView>[],
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const CashScreen(),
    ),
  );

  Future<void> pump(WidgetTester tester, CashSummaryView summary) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(summary));
    await tester.pumpAndSettle();
  }

  testWidgets('رصيد الجمعية shows what may be SPENT, not what is in the box', (
    WidgetTester tester,
  ) async {
    await pump(tester, _withHoldings);

    // 20, not 60. The 40 belongs to members until their months are billed.
    expect(find.text(formatMoney('20.00')), findsOneWidget);
    expect(find.text(l.associationBalance), findsOneWidget);
  });

  testWidgets('...and a line on the face says where the missing cash went', (
    WidgetTester tester,
  ) async {
    // The treasurer counted 60 and the screen says 20. This line is the whole
    // explanation, and it is on the face of the bar rather than one tap down
    // for exactly that reason.
    //
    // ⚠ It moved from the subtitle to its own line, and that was not cosmetic:
    //   the subtitle held EITHER عهد OR what had been disbursed, so the more
    //   urgent of the two displaced the other and neither could be toned. Now
    //   both are on the face, and this one is amber.
    await pump(tester, _withHoldings);

    final Finder note = find.text(l.heldOfWhich(formatMoney('40.00')));
    expect(note, findsOneWidget);
    expect(tester.widget<Text>(note).style?.color, AppColors.warning);

    // And the outflow is no longer displaced by it — the reason the two were
    // separated in the first place.
    expect(
      find.text('${l.totalDisbursed} ${formatMoney('0.00')}'),
      findsOneWidget,
    );
  });

  testWidgets('the breakdown carries عهد between what came in and what left', (
    WidgetTester tester,
  ) async {
    await pump(tester, _withHoldings);
    await tester.tap(find.text(l.associationBalance));
    await tester.pumpAndSettle();

    expect(find.text(l.heldForMembers), findsOneWidget);
    expect(find.text(formatMoney('40.00')), findsOneWidget);
    // The cash really did arrive, and the collected figure still says so —
    // the pair to the balance above. If عهد were simply not recorded, both the
    // balance and this would read 20 and the association's books would be short.
    expect(find.text(l.totalCollected), findsOneWidget);
    expect(find.text(formatMoney('60.00')), findsOneWidget);
  });

  testWidgets('with nothing prepaid the line is not shown at all', (
    WidgetTester tester,
  ) async {
    // «عهد المشتركين 0.00» under every balance is a permanent explanation of a
    // situation that is not happening. What went out stays on the subtitle,
    // where it now lives on every balance rather than only on the ones with
    // nothing prepaid.
    await pump(tester, _noHoldings);

    expect(find.textContaining(l.heldForMembers), findsNothing);
    expect(
      find.text('${l.totalDisbursed} ${formatMoney('5.00')}'),
      findsOneWidget,
    );
    expect(find.text(formatMoney('55.00')), findsOneWidget);
  });

  test('a database with no heldForMembers column reports zero, not blank', () {
    // v_cash_summary on a project that predates the column sends no such key.
    // Zero is the state every association was in before prepayment existed;
    // a blank would render as a figure that failed to load, on the one screen
    // where that ambiguity is worst.
    final CashSummaryView old = CashSummaryView.fromJson(<String, dynamic>{
      'total': '700.00',
      'cash': '450.00',
      'transfer': '250.00',
      'today': '0.00',
      'month': '700.00',
      'year': '700.00',
      'balance': '700.00',
    });

    expect(old.heldForMembers, '0.00');
    expect(old.balance, '700.00');
  });
}
