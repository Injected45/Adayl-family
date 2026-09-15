import 'package:family_app/core/config/palette.dart';
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

/// «حركة العدايل» في شاشة الصندوق (15/09).
///
/// «اريد ان اغير كلمة التحصيل الى حركة العدايل وان تجعل الحاوية مطوية …
/// واجمالي قيمة الفرق مابين ماتم دفعه العديل وما استلمة كما في شاشة الجدوى …
/// وكل مشترك يظهر امام اسمه صافي رصيد مستحق له … او رصيد مستحق عليه مثل رزق».
///
/// The eight rows are v_member_net as it answered on a copy of the live ledger:
/// seven men in credit, رزق at −35, total 30,790.
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

const List<(String, String, String)> _live = <(String, String, String)>[
  ('A-01', 'محمد حمد المانجا', '5995.00'),
  ('A-02', 'المهدي عبدالله محمد بوفراج الشوبكي', '3365.00'),
  ('A-03', 'هيثم مفتاح عبدالعظيم', '3345.00'),
  ('A-04', 'ايمن صالح محمد صالح بلها', '6065.00'),
  ('A-05', 'عبدالعزيز عطية حمد يونس الخشبي', '3765.00'),
  ('A-06', 'سالم صالح الشيخي', '3335.00'),
  ('A-07', 'عمران ونيس صالح ادم بوصخرة', '4955.00'),
  ('A-08', 'رزق المبروك جلجال', '-35.00'),
];

List<MemberNet> _rows({String total = '30790.00'}) => <MemberNet>[
  for (int i = 0; i < _live.length; i++)
    MemberNet(
      adeelId: i + 1,
      adeelCode: _live[i].$1,
      adeelName: _live[i].$2,
      paid: '0.00',
      received: '0.00',
      net: _live[i].$3,
      totalNet: total,
    ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<MemberNet>? rows,
  double width = 411,
}) async {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(_StubAuth.new),
        memberNetProvider.overrideWith((Ref ref) async => rows ?? _rows()),
        cashMovementsProvider.overrideWith(
          (Ref ref) async => <CashMovementView>[],
        ),
        disbursementsProvider.overrideWith(
          (Ref ref) async => <DisbursementView>[],
        ),
        cashSummaryProvider.overrideWith(
          (Ref ref) async => const CashSummaryView(
            total: '57880.00',
            cash: '57880.00',
            transfer: '0.00',
            today: '0.00',
            month: '0.00',
            year: '0.00',
            disbursed: '53650.00',
            balance: '4230.00',
          ),
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
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final L l = LAr();
  tearDown(() => applyAppTheme(AppThemeMode.light));

  testWidgets('«التحصيل» is now «حركة العدايل», folded on the total', (
    WidgetTester tester,
  ) async {
    await _pump(tester);

    expect(find.text(l.opsCollections), findsNothing);
    expect(find.text(l.membersMovementTitle), findsOneWidget);
    expect(find.text(l.membersNetOwedToThem), findsOneWidget);
    final Text total = tester.widget<Text>(find.text(formatMoney('30790.00')));
    expect(total.style?.color, AppColors.success);
    // Folded: no member on screen.
    expect(find.text('رزق المبروك جلجال'), findsNothing);
    expect(find.text('محمد حمد المانجا'), findsNothing);
  });

  testWidgets('opened, every member shows his own net beside his name', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text(l.membersMovementTitle));
    await tester.pumpAndSettle();

    for (final (String _, String name, String _) in _live) {
      expect(find.text(name), findsOneWidget, reason: name);
    }
    // Seven in credit…
    expect(find.text(l.memberNetOwedToHim), findsNWidgets(7));
    final Text ayman = tester.widget<Text>(find.text(formatMoney('6065.00')));
    expect(ayman.style?.color, AppColors.success);

    // …and رزق against him, in red, with no minus sign printed.
    expect(find.text(l.memberNetOwedByHim), findsOneWidget);
    final Text rizq = tester.widget<Text>(find.text(formatMoney('35.00')));
    expect(rizq.style?.color, AppColors.danger);
    expect(find.text(formatMoney('-35.00')), findsNothing);

    // Tapping again folds it.
    await tester.tap(find.text(l.membersMovementTitle));
    await tester.pumpAndSettle();
    expect(find.text('رزق المبروك جلجال'), findsNothing);
  });

  testWidgets('a total against the members reads so, in red', (
    WidgetTester tester,
  ) async {
    await _pump(tester, rows: _rows(total: '-120.00'));
    expect(find.text(l.membersNetOwedByThem), findsOneWidget);
    final Text total = tester.widget<Text>(find.text(formatMoney('120.00')));
    expect(total.style?.color, AppColors.danger);
  });

  test('the sign is READ from the server string, never computed', () {
    expect(moneySign('5995.00'), 1);
    expect(moneySign('-35.00'), -1);
    expect(moneySign('0.00'), 0);
    expect(moneySign('-0.00'), 0);
    expect(moneyMagnitude('-35.00'), '35.00');
    expect(moneyMagnitude('35.00'), '35.00');
  });

  for (final double width in <double>[320, 411]) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      testWidgets('fits at ${width.toInt()}px, open, in ${mode.name}', (
        WidgetTester tester,
      ) async {
        applyAppTheme(mode);
        await _pump(tester, width: width);
        await tester.tap(find.text(l.membersMovementTitle));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
