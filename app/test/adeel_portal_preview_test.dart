import 'dart:convert';
import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/directory/presentation/adeel_portal_screen.dart';
import 'package:family_app/features/directory/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the REAL [AdeelPortalScreen] to a PNG so the statement can be LOOKED
/// AT before anyone signs in.
///
/// The portal is the one screen that cannot be reached from a staff account: it
/// needs an عديل bound by an access code, which needs a register, which needs a
/// first admin. That chain is long enough that "does the ledger read like a bank
/// statement" would otherwise be unanswerable until the whole thing is live —
/// and the answer to that question is a matter of looking, not of asserting.
///
/// It renders the shipping widget tree against the REAL captured wire JSON in
/// test/fixtures/supabase/, so a column that would be empty in the app is empty
/// here too.
///
/// Regenerate:
///   flutter test --update-goldens --dart-define=WRITE_PREVIEW=true \
///     test/adeel_portal_preview_test.dart
///
/// NOT a pass/fail golden — skipped unless goldens are being written, so font
/// rasterisation differences between machines cannot fail the build.

class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    // adeelId set and no role: exactly what my_role() returning NULL looks like
    // on the client, which is what pins him to this screen.
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000b1',
      email: 'adeel@fam.test',
      displayName: 'عديل',
      role: AppRole.viewer,
      status: AccountStatus.approved,
      adeelId: 1,
      adeelCode: 'A-01',
    ),
  );
}

Map<String, dynamic> _obj(String file) =>
    (jsonDecode(File('test/fixtures/supabase/$file').readAsStringSync()) as Map)
        .cast<String, dynamic>();

Future<void> _loadFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (String family, String path) in <(String, String)>[
    (AppFonts.body, 'assets/fonts/Cairo-Variable.ttf'),
    (AppFonts.display, 'assets/fonts/Tajawal-ExtraBold.ttf'),
  ]) {
    final FontLoader loader = FontLoader(family)
      ..addFont(
        Future<ByteData>.value(
          File(path).readAsBytesSync().buffer.asByteData(),
        ),
      );
    await loader.load();
  }

  final File icons = File('build/web/assets/fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final FontLoader iconLoader = FontLoader('MaterialIcons')
      ..addFont(
        Future<ByteData>.value(icons.readAsBytesSync().buffer.asByteData()),
      );
    await iconLoader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  final AdeelDetail detail = AdeelDetail.fromJson(_obj('adeel_detail.json'));

  // Assembled the way DirectoryRepository.statement() does; `Statement` is the
  // one model whose parsing lives in the repository rather than on the class.
  final Map<String, dynamic> raw = _obj('adeel_statement.json');
  final Statement statement = Statement(
    movements: (raw['movements'] as List<dynamic>)
        .map(
          (dynamic e) =>
              StatementMovement.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(),
    closingBalance: raw['closingBalance'] as String? ?? '0.00',
  );

  Widget app() => ProviderScope(
    overrides: <Override>[
      authControllerProvider.overrideWith(_StubAuth.new),
      adeelDetailProvider(1).overrideWith((Ref ref) async => detail),
      statementProvider(1).overrideWith((Ref ref) async => statement),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,
      home: const AdeelPortalScreen(),
    ),
  );

  const bool write = bool.fromEnvironment('WRITE_PREVIEW', defaultValue: false);

  testWidgets(
    'adeel portal',
    (WidgetTester tester) async {
      // Tall enough that the whole page renders in one shot: the ledger is
      // below two other blocks, and a viewport-height preview would cut off the
      // thing being previewed.
      tester.view.physicalSize = const Size(411, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/adeel_portal.png'),
      );

      // The LEDGER, which is behind the segmented control and is the half of
      // this screen that most needs looking at: four columns —
      // البيان | مدين | دائن | الرصيد — on a phone-width card, where the
      // question "does it fit" cannot be answered by reading the code.
      await tester.tap(find.text(LAr().myStatementSection).last);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/adeel_portal_ledger.png'),
      );
    },
    skip: !write,
  );
}
