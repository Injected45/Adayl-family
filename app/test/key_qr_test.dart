import 'package:family_app/core/config/glass.dart';
import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/data/key_qr.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/auth/presentation/pending_screen.dart';
import 'package:family_app/features/directory/presentation/access_code_view.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// مفتاحُ الدخول كرمز QR.
///
/// ⚠ READING THE SQUARE IS NOT TESTED HERE, AND CANNOT BE: the phone's camera
///   does it through `mobile_scanner`, and no widget test owns a camera. What
///   IS testable is the contract between the two halves — the payload the
///   admin's screen draws and the payload the scanner accepts — and that is
///   the one place this feature can be wrong while both sides look right.
///
///   (An earlier build decoded a PHOTOGRAPH in Dart and was tested end to end
///   here, at four levels of rotation, noise and JPEG crushing. Every case
///   passed, and the feature still failed on the first handset, because taking
///   a picture of a code and confirming it is not what «امسح» means to anyone.
///   The lesson is kept deliberately: a complete test of the wrong interaction
///   proves nothing about the feature.)
void main() {
  const String code = 'K7M4-2QX9-TB5A';

  group('the payload', () {
    test('a key goes out and comes back', () {
      expect(keyFromQrPayload(keyQrPayload(code)), code);
    });

    test('⚠ a QR that is not ours is refused, not fed to the database', () {
      // Without the prefix every QR in the world — a receipt, a wifi card —
      // would be sent to redeem_adeel_code and would spend one of the five
      // attempts an hour the member has.
      expect(keyFromQrPayload('https://example.com'), isNull);
      expect(keyFromQrPayload('WIFI:S:home;T:WPA;P:1234;;'), isNull);
      expect(keyFromQrPayload(code), isNull, reason: 'a bare code is not ours');
    });

    test('an empty key is nothing, and spacing does not matter', () {
      expect(keyFromQrPayload('adayl-key:'), isNull);
      expect(keyFromQrPayload('adayl-key:   '), isNull);
      expect(keyFromQrPayload('  adayl-key:$code  '), code);
    });
  });

  group('the two screens', () {
    final L l = LAr();

    Future<void> pump(WidgetTester tester, Widget child, double width) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the admin sees the key written AND drawn', (
      WidgetTester tester,
    ) async {
      await pump(tester, const AccessCodeView(code: code), 411);

      expect(find.text(code), findsOneWidget, reason: 'the text never goes');
      expect(find.byType(QrImageView), findsOneWidget);

      // ⚠ What is DRAWN must be what the scanner accepts. Without this the
      //   square could carry the bare code, every scan would answer «this is
      //   not an access code», and both halves would look correct alone.
      final String drawn = tester
          .widget<AccessCodeView>(find.byType(AccessCodeView))
          .payload;
      expect(keyFromQrPayload(drawn), code);
    });

    for (final AppThemeMode mode in AppThemeMode.values) {
      testWidgets('…and it fits a 320px phone in ${mode.name}', (
        WidgetTester tester,
      ) async {
        applyAppTheme(mode);
        addTearDown(() => applyAppTheme(AppThemeMode.light));
        await pump(tester, const AccessCodeView(code: code), 320);
        expect(
          tester.takeException(),
          isNull,
          reason: 'the QR pushed something out of the frame',
        );
      });
    }

    testWidgets('⚠ and inside the real dialog on a short phone', (
      WidgetTester tester,
    ) async {
      // GlassDialog puts its content in a plain Column — nothing scrolls. A
      // 170px square plus two paragraphs on a 360×640 handset is exactly the
      // shape that overflowed «المزيد» twice before.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (BuildContext _) => GlassDialog(
                    title: Text(l.issueCodeTitle),
                    content: const AccessCodeView(code: code),
                    actions: <Widget>[
                      TextButton(onPressed: () {}, child: Text(l.close)),
                    ],
                  ),
                ),
                child: const Text('x'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('x'));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text(code), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the dialog does not scroll — the square must fit as it is',
      );
    });

    testWidgets('the member is offered the camera beside the box', (
      WidgetTester tester,
    ) async {
      // ⚠ Mounted as the HOME, not inside a Scaffold of the test's own: the
      //   screen brings its own, and nesting it asserts in the renderer before
      //   a single expectation runs.
      tester.view.physicalSize = const Size(411, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authControllerProvider.overrideWith(
              () => _StubAuth(
                const AppUser(
                  id: '00000000-0000-0000-0000-0000000000c1',
                  email: 'new@fam.test',
                  displayName: 'جديد',
                  role: AppRole.viewer,
                  status: AccountStatus.pending,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: const Locale('ar'),
            localizationsDelegates: latinDigitDelegates(
              L.localizationsDelegates,
            ),
            supportedLocales: L.supportedLocales,
            home: const PendingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l.familyCodeScan), findsOneWidget);
      expect(
        find.text(l.familyCodeAction),
        findsOneWidget,
        reason: 'typing the key is still there — the camera is an addition',
      );
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    });
  });
}

class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _user);
}
