import 'package:family_app/core/config/theme.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeel_portal_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// One عديل, one handset — the part of it the app is responsible for.
///
/// The RULE lives in `my_adeel_id()`, which returns NULL for a device that does
/// not match and therefore hands this screen an empty register, an empty ledger
/// and a zero balance. Nothing here enforces anything; what these pin is that
/// the member is TOLD, because the alternative — a portal that renders
/// perfectly and is simply empty — reads as a broken app rather than a rule the
/// association set, and he would ring about the wrong problem.
///
/// `deviceLocked` defaults to FALSE on purpose, so a build pointed at a
/// database that predates the rule behaves exactly as it did before instead of
/// locking every member out of a screen the server is willing to fill. The last
/// test is that default.

class _Auth extends AuthController {
  _Auth(this.locked);

  final bool locked;

  @override
  AuthState build() => AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000e1',
      email: 'adeel@fam.test',
      displayName: 'عديل',
      role: AppRole.viewer,
      status: AccountStatus.approved,
      adeelId: 1,
      adeelCode: 'A-0001',
      deviceLocked: locked,
    ),
  );
}

AdeelDetail _detail() => AdeelDetail.fromJson(<String, dynamic>{
  'adeel': <String, dynamic>{
    'id': 1,
    'adeelCode': 'A-0001',
    'fullName': 'المهدي العدولي',
    'phone': '0910000000',
    'notes': '',
    'registeredAt': '2026-01-01',
    'dob': '1980-01-01',
    'age': 46,
    'membershipStatus': 'نشط',
    'debt': '20.00',
    'paid': '0.00',
    'issued': '20.00',
    'monthlyExpected': '20.00',
  },
  'kpis': <String, dynamic>{
    'monthlyExpected': '20.00',
    'issued': '20.00',
    'debt': '20.00',
    'paid': '0.00',
    'openPeriods': 1,
  },
  'receivables': <dynamic>[],
  'payments': <dynamic>[],
});

void main() {
  final L l = LAr();

  Widget app({required bool locked}) => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _Auth(locked)),
      adeelDetailProvider(1).overrideWith((Ref ref) async => _detail()),
      statementProvider(1).overrideWith(
        (Ref ref) async => const Statement(
          movements: <StatementMovement>[],
          closingBalance: '20.00',
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: const AdeelPortalScreen(),
    ),
  );

  testWidgets('the wrong handset is told why, not shown an empty page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(locked: true));
    await tester.pumpAndSettle();

    expect(find.text(l.deviceLockedTitle), findsOneWidget);
    expect(find.text(l.deviceLockedBody), findsOneWidget);

    // Not a blank statement wearing a message: the portal's own furniture must
    // be gone, or he will scroll past the explanation into a page of zeroes.
    expect(find.text(l.myBalanceNow), findsNothing);
    expect(find.text(l.myDetailsTitle), findsNothing);
  });

  testWidgets('he can still sign out of the wrong handset', (
    WidgetTester tester,
  ) async {
    // The only two things he can do are ring the association and get off this
    // screen. Removing the sign-out button would strand a man holding a phone
    // that is not his.
    await tester.pumpWidget(app(locked: true));
    await tester.pumpAndSettle();

    expect(find.text(l.signOut), findsOneWidget);
  });

  testWidgets('his code is quoted, so the association can find him', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(locked: true));
    await tester.pumpAndSettle();

    expect(find.text('A-0001'), findsOneWidget);
  });

  testWidgets('the right handset sees the portal exactly as before', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(locked: false));
    await tester.pumpAndSettle();

    expect(find.text(l.deviceLockedTitle), findsNothing);
    expect(find.text(l.myBalanceNow), findsOneWidget);
    expect(find.text('المهدي العدولي'), findsOneWidget);
  });

  test('a database without the flag does not lock anyone out', () {
    // api_me() on a project that has not had the patch applied returns no
    // `deviceLocked` key at all. Reading a missing key as `true` would black
    // out every portal in the association the moment the app updated ahead of
    // the schema.
    final AppUser parsed = AppUser.fromJson(<String, dynamic>{
      'id': '00000000-0000-0000-0000-0000000000e1',
      'email': 'adeel@fam.test',
      'displayName': 'عديل',
      'role': 'viewer',
      'status': 'approved',
      'adeelId': 1,
    });
    expect(parsed.deviceLocked, isFalse);
  });
}
