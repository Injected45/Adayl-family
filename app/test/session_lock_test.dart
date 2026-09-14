import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/auth/presentation/pending_screen.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 14/09 — منطقةُ الخطر أُلغيت، والمفتاحُ يربط الجهازَ والدخولَ معًا.
///
/// ── منطقة الخطر ─────────────────────────────────────────────────────────────
/// «الغاء منطقة الخطر بالكامل … تم اعتماد التطبيق وتحميل كافة البيانات
/// الحقيقية فيه». The buttons are gone from the app and the two functions are
/// gone from the list the app may call (PATCH_20260914b) — so an admin phone
/// still carrying an older APK is refused too. This file pins the app's half.
///
/// ── القفل ───────────────────────────────────────────────────────────────────
/// «اي مشترك يسجل خروج لا يفتح الا بمفتاح جديد … واذا غير الجهاز لا يفتح الا
/// بموافقة الادمن ومفتاح جديد». The rule is in `my_adeel_id()` and was proved
/// against a copy of the live database (20 checks: a login from before the rule
/// kept, a new login locked, a used key refused, a new key opening, another
/// phone locked, the admin untouched, both purges refused). What the app owes
/// the member is the true sentence on the screen he lands on.
class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _user);
}

void main() {
  final L l = LAr();

  group('the danger zone is gone', () {
    test('no purge control is left in settings', () {
      final String src = File(
        'lib/features/oversight/presentation/settings_screen.dart',
      ).readAsStringSync();
      for (final String gone in <String>[
        '_DangerZone',
        'purgeFinancialData',
        'purgeAllData',
        'PurgeWire',
        'dangerZoneSection',
      ]) {
        expect(src, isNot(contains(gone)), reason: '$gone must not return');
      }
    });

    test('and nothing in the app can call the two functions', () {
      final List<String> callers = <String>[];
      for (final FileSystemEntity e in Directory(
        'lib',
      ).listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final String src = e.readAsStringSync();
        if (src.contains("'purge_financial_data'") ||
            src.contains("'purge_all_data'")) {
          callers.add(e.path);
        }
      }
      expect(callers, isEmpty);
    });
  });

  group('a member whose login is not the keyed one', () {
    Future<void> pump(WidgetTester tester, AppUser user) async {
      tester.view.physicalSize = const Size(360, 900);
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
            localizationsDelegates: latinDigitDelegates(
              L.localizationsDelegates,
            ),
            supportedLocales: L.supportedLocales,
            home: const PendingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is told he needs a new key — not «awaiting approval»', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        const AppUser(
          id: '00000000-0000-0000-0000-0000000000b1',
          email: 'adeel@fam.test',
          displayName: 'هيثم',
          role: AppRole.viewer,
          status: AccountStatus.approved,
          adeelId: 3,
          deviceLocked: true,
        ),
      );
      expect(find.text(l.deviceLockedTitle), findsOneWidget);
      expect(find.text(l.deviceLockedBody), findsOneWidget);
      expect(find.text(l.pendingTitle), findsNothing);
      // ...and the box to type it is right there.
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a stranger still reads the ordinary waiting message', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        const AppUser(
          id: '00000000-0000-0000-0000-0000000000c1',
          email: 'new@fam.test',
          displayName: 'جديد',
          role: AppRole.viewer,
          status: AccountStatus.pending,
        ),
      );
      expect(find.text(l.pendingTitle), findsOneWidget);
      expect(find.text(l.deviceLockedTitle), findsNothing);
    });
  });
}
