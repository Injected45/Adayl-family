import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/core/widgets/app_scaffold.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A member is never shown a door he cannot open.
///
/// ── WHAT WENT WRONG ─────────────────────────────────────────────────────────
/// المحادثات is the one association screen a portal account may occupy, and it
/// is built on AppScaffold — which carries the navigation pill. The pill filtered
/// by ROLE, and a bound member carries `AppRole.viewer`, so it offered him the
/// register, the treasury, the receivables and the reports. Every one of them
/// bounced him straight back.
///
/// ⚠ AND THAT IS WORSE THAN AN ERROR MESSAGE. A row of doors that do not open
///   tells a member the app is keeping things from him and invites him to wonder
///   what — about an association he belongs to and pays into. Hiding them inside
///   «المزيد» would not have been a fix: the question survives the sheet.
///
/// The refusal itself is unchanged and lives where it belongs — the router guard
/// and RLS. This is about not extending an invitation.
class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _user);
}

const AppUser _member = AppUser(
  id: '00000000-0000-0000-0000-0000000000b1',
  email: 'adeel@fam.test',
  displayName: 'أيمن صالح بلها',
  role: AppRole.viewer,
  status: AccountStatus.approved,
  adeelId: 6,
);

const AppUser _staff = AppUser(
  id: '00000000-0000-0000-0000-0000000000f1',
  email: 'admin@fam.test',
  displayName: 'المهدي',
  role: AppRole.admin,
  status: AccountStatus.approved,
);

void main() {
  final L l = LAr();

  Future<void> open(WidgetTester tester, AppUser user) async {
    tester.view.physicalSize = const Size(411, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(user)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: AppScaffold(
            title: l.navChat,
            currentRoute: AppRoutes.chat,
            body: (BuildContext context) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a member sees no destination but the one he is on', (
    WidgetTester tester,
  ) async {
    await open(tester, _member);

    // Not the register, not the treasury, not the receivables — and not
    // «المزيد», which would only move the same question one tap away.
    expect(find.text(l.navRegister), findsNothing);
    expect(find.text(l.navCash), findsNothing);
    expect(find.text(l.navReceivables), findsNothing);
    expect(find.text(l.navHome), findsNothing);
    expect(find.text(l.navMore), findsNothing);
  });

  testWidgets('...and he is given a way back to his own page', (
    WidgetTester tester,
  ) async {
    // He arrived with `context.go`, which REPLACED the location — nothing on the
    // stack for a back gesture to pop, and on Android the system button would
    // put him out of the app. Without this the room is a one-way door.
    await open(tester, _member);
    // By TOOLTIP, not by icon: Icons.home_outlined is also the الرئيسية
    // destination in the staff bar, so the glyph alone cannot tell the two
    // apart — and the assertion below would pass for the wrong reason.
    expect(find.byTooltip(l.myFamilyTitle), findsOneWidget);
  });

  testWidgets('⚠ and STAFF still have the whole bar', (
    WidgetTester tester,
  ) async {
    // The other half of the rule, and the one a careless fix breaks: hiding the
    // pill for everybody would be a far bigger regression than the bug, and it
    // would pass the two tests above.
    await open(tester, _staff);

    expect(find.text(l.navHome), findsOneWidget);
    expect(find.text(l.navMore), findsOneWidget);
    // And no back control: the bar underneath already goes everywhere.
    expect(find.byTooltip(l.myFamilyTitle), findsNothing);
  });
}
