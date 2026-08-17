import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/officials_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two ways an Arabic-only app leaks its wire format to the people using it.
///
/// Both were live on the association's own screens, and neither could fail:
/// rtl_lint watches for Arabic literals in widget code, so an ENGLISH wire
/// value printed verbatim is invisible to it, and a text box that accepts any
/// character cannot report a character it should not have accepted.

class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000d1',
      email: 'admin@fam.test',
      displayName: 'المهدي',
      role: AppRole.admin,
      status: AccountStatus.approved,
    ),
  );
}

void main() {
  final L l = LAr();

  group('the officials screen', () {
    testWidgets('names the two posts in Arabic, not in wire values', (
      WidgetTester tester,
    ) async {
      // v_officials emits 'treasurer' and 'financeManager' — ASCII identifiers,
      // which the screen printed straight onto the page as its two headings.
      // The association read English on an Arabic-only screen for as long as
      // that view has existed.
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authControllerProvider.overrideWith(_StubAuth.new),
            officialsProvider.overrideWith(
              (Ref ref) async => const <Official>[
                Official(
                  role: 'treasurer',
                  name: 'المهدي عبدالله محمد',
                  phone: '0925093709',
                ),
                Official(
                  role: 'financeManager',
                  name: 'ايمن صالح بلها',
                  phone: '0910000000',
                ),
              ],
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: const Locale('ar'),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            home: const OfficialsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l.treasurerSection), findsOneWidget);
      expect(find.text(l.financeManagerSection), findsOneWidget);
      expect(find.text('treasurer'), findsNothing);
      expect(find.text('financeManager'), findsNothing);
    });
  });

  group('ArabicDigitsFormatter', () {
    // The app forces `ar`, so the keyboard offers ٠١٢٣ and every numeric cast
    // on the server is ASCII-only. Folding has to happen BEFORE any filter,
    // which is the ordering these assertions exist to keep honest.
    TextEditingValue fold(String typed) => ArabicDigitsFormatter()
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: typed));

    test('Arabic-Indic digits become ASCII', () {
      expect(fold('٠١٢٣٤٥٦٧٨٩').text, '0123456789');
    });

    test('the extended Persian range folds too', () {
      expect(fold('۲۰').text, '20');
    });

    test('the Arabic decimal separator becomes a full stop', () {
      expect(fold('٢٠٫٥٠').text, '20.50');
    });

    test('ASCII passes through untouched, caret and all', () {
      const TextEditingValue typed = TextEditingValue(
        text: '100.00',
        selection: TextSelection.collapsed(offset: 6),
      );
      final TextEditingValue out = ArabicDigitsFormatter()
          .formatEditUpdate(TextEditingValue.empty, typed);
      expect(out, same(typed));
    });

    test('a phone box keeps digits and separators and drops the rest', () {
      // `₩912346` is in the live register: a keyboard slip into a currency sign
      // that the box accepted because it accepted anything.
      final TextInputFormatter allow =
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]'));
      final TextEditingValue folded = fold('₩٩١٢٣٤٦');
      final TextEditingValue out =
          allow.formatEditUpdate(TextEditingValue.empty, folded);
      expect(out.text, '912346');
    });
  });
}
