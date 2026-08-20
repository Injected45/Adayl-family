import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeel_form_screen.dart';
import 'package:family_app/features/directory/presentation/adeels_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// AGE IS GONE FROM THE INTERFACE, and this is what keeps it gone.
///
/// The association stopped collecting a date of birth and stopped wanting an
/// age shown anywhere. Age had already decided nothing about billing — the
/// eligibility gate was removed when the family model was — so what remained
/// were two fields carrying a fact the register had no use for: a date picker
/// on the form, and a badge on the register beside every man's name.
///
/// ⚠ The DATABASE still has the column, and still holds every date already
///   entered. The form omits the `dob` key rather than sending an empty one, and
///   `save_adeel` leaves an absent key alone instead of nulling it — so editing
///   an عديل today does not quietly erase what was typed last month. Dropping
///   the column is a separate, deliberate act for the association to ask for.
///
/// The wire still CARRIES `age`, computed by v_adeels, and
/// supabase_contract_test still asserts on it — deliberately: that assertion is
/// what proves a seven-year-old is billed exactly like a fifty-one-year-old, and
/// it is about the billing rule, not about a screen.

class _StubAuth extends AuthController {
  _StubAuth(this.role);

  final AppRole role;

  @override
  AuthState build() => AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000f1',
      email: 'staff@fam.test',
      displayName: 'المهدي',
      role: role,
      status: AccountStatus.approved,
    ),
  );
}

/// Carries an age on the wire ON PURPOSE. A screen that hid the badge only
/// because the fixture had no age would pass this test and fail in production.
final AdeelListItem _withAge = AdeelListItem.fromJson(<String, dynamic>{
  'id': 1,
  'adeelCode': 'A-01',
  'fullName': 'المهدي العدولي',
  'phone': '0910000000',
  'membershipStatus': 'نشط',
  'debt': '0.00',
  'paid': '20.00',
  'issued': '20.00',
  'monthlyExpected': '20.00',
  'dob': '1980-01-01',
  'age': 46,
});

Widget _host(Widget child, {List<Override> overrides = const <Override>[]}) =>
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(AppRole.admin)),
        ...overrides,
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: child,
      ),
    );

void main() {
  final L l = LAr();

  testWidgets('the form does not ask for a date of birth', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const AdeelFormScreen()));
    await tester.pumpAndSettle();

    expect(find.text(l.dateOfBirth), findsNothing);
    // The fields that DO remain, so "found nothing" cannot be "rendered
    // nothing".
    expect(find.text(l.fullNameField), findsOneWidget);
    expect(find.text(l.phone), findsOneWidget);
  });

  testWidgets('the register shows no age, even when the wire carries one', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        const AdeelsScreen(),
        overrides: <Override>[
          adeelsProvider(
            '',
          ).overrideWith((Ref ref) async => <AdeelListItem>[_withAge]),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('المهدي العدولي'), findsOneWidget);
    expect(find.text(l.ageYears(46)), findsNothing);

    // ⚠ AND THE CODE IS THE POSITIVE CONTROL NOW, not the status badge. A
    //   test that only asserts absences passes just as well on a screen that
    //   rendered nothing at all, so one thing that MUST be there has to be
    //   named — and after the association put the name and the code on one
    //   line, the code is what that line carries beside the name.
    expect(find.text('A-01'), findsOneWidget);

    // ⚠ «نشط» IS DELIBERATELY ABSENT FROM THE REGISTER. It used to sit here,
    //   and it was removed because the register lists everyone and almost
    //   everyone is نشط — one true fact repeated on every row, distinguishing
    //   nobody. It lives on the detail screen instead, beside the fields it
    //   qualifies, where a موقوف is read against the man rather than a list.
    expect(find.text('نشط'), findsNothing);
  });
}
