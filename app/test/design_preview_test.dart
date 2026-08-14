import 'dart:io';

import 'package:family_app/core/config/glass.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/core/widgets/app_scaffold.dart';
import 'package:family_app/core/widgets/async_view.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the REAL [AppScaffold] to a PNG so the design can be LOOKED AT.
///
/// Contrast ratios and blur counts can all be perfect while the result is ugly or
/// unusable, and no matcher notices. This is the check with eyes.
///
/// It renders the shipping widget tree rather than a reconstruction, and that
/// distinction earned itself: an earlier version rebuilt the chrome by hand here,
/// so it could not have shown that `extendBodyBehindAppBar: true` was hiding the
/// first row of every screen behind the app bar. A person had to find that in the
/// running app. A preview built from the real shell fails the way the app does.
///
/// Regenerate:
///   flutter test --update-goldens --dart-define=WRITE_PREVIEW=true \
///     test/design_preview_test.dart
///
/// NOT a pass/fail golden — skipped unless goldens are being written, so font
/// rasterisation differences between machines cannot fail the build.

/// Stands in for the real controller, which on build() subscribes to Google token
/// streams and bootstraps from secure storage. Overriding build() sidesteps all of
/// that and pins a signed-in admin, so every destination is visible.
class _StubAuth extends AuthController {
  @override
  AuthState build() => const AuthState(
    stage: AuthStage.signedIn,
    user: AppUser(
      id: '00000000-0000-0000-0000-0000000000a1',
      email: 'admin@fam.test',
      displayName: 'مدير النظام',
      role: AppRole.admin,
      status: AccountStatus.approved,
    ),
  );
}

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

  // The icon font too, or every Icon renders as an empty placeholder box and the
  // preview misrepresents the design in the way most likely to be mistaken for a
  // real bug. Read from the tree-shaken copy the web build already produced, so
  // no SDK path is hard-coded; skipped if absent.
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

  Widget app(Widget home) => ProviderScope(
    overrides: <Override>[authControllerProvider.overrideWith(_StubAuth.new)],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      home: home,
    ),
  );

  Future<void> shoot(WidgetTester tester, Size size, String name) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const _DemoScreen()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  const bool write = bool.fromEnvironment('WRITE_PREVIEW', defaultValue: false);

  testWidgets(
    'phone',
    (WidgetTester tester) =>
        shoot(tester, const Size(430, 932), 'glass_flat_phone'),
    skip: !write,
  );

  testWidgets(
    'wide rail',
    (WidgetTester tester) =>
        shoot(tester, const Size(1100, 800), 'glass_flat_wide'),
    skip: !write,
  );
}

/// A dashboard-shaped body inside the real shell.
class _DemoScreen extends StatelessWidget {
  const _DemoScreen();

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return AppScaffold(
      title: l.navHome,
      currentRoute: AppRoutes.home,
      body: ListView(
        padding: screenPadding(context),
        children: <Widget>[
          GlassSurface(
            blurred: true,
            lifted: true,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _Head(
                  icon: Icons.summarize_outlined,
                  title: 'ملخص العائلة',
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: <Widget>[
                    for (final (String lbl, String v, Color? t)
                        in <(String, String, Color?)>[
                          ('عدد الأبناء', '4', null),
                          ('المستحق', '60.00', null),
                          ('المديونية', '120.00', AppColors.danger),
                        ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: _Well(label: lbl, value: v, tone: t),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Row(
            children: <Widget>[
              Expanded(
                child: _Stat(
                  label: 'إجمالي المحصل',
                  value: '48,250.00',
                  sub: 'نقداً 30,000 • تحويل 18,250',
                  tone: AppColors.success,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: _Stat(
                  label: 'إجمالي المديونية',
                  value: '7,410.00',
                  sub: '12 عائلة مدينة',
                  tone: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          GlassPanel(
            title: 'أكبر المدينين',
            icon: Icons.groups_outlined,
            child: Column(
              children: <Widget>[
                for (final (String n, String c, String st, Color t)
                    in <(String, String, String, Color)>[
                      (
                        'محمد علي الرحالة',
                        'F-0001',
                        'مسدد جزئياً',
                        AppColors.warning,
                      ),
                      (
                        'أحمد سالم الرحالة',
                        'F-0002',
                        'غير مسدد',
                        AppColors.danger,
                      ),
                      (
                        'يوسف عمر الرحالة',
                        'F-0003',
                        'مسدد بالكامل',
                        AppColors.success,
                      ),
                    ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                n,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                c,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        StatusBadge(label: st, tone: t),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: () {}, child: const Text('تسجيل دفعة')),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: () {},
            child: const Text('إنشاء استحقاقات الشهر'),
          ),
          const SizedBox(height: AppSpacing.md),
          GlassCard(
            child: TextField(
              controller: TextEditingController(text: '250.00'),
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                hintText: '0.00',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: AppColors.brandDeep),
      ),
      const SizedBox(width: AppSpacing.md),
      Text(title, style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

class _Well extends StatelessWidget {
  const _Well({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: GlassColors.well,
      borderRadius: BorderRadius.circular(AppRadius.control),
      border: Border.all(color: GlassColors.wellEdge),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: tone ?? AppColors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub, this.tone});
  final String label;
  final String value;
  final String? sub;
  final Color? tone;

  @override
  Widget build(BuildContext context) => GlassCard(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: tone ?? AppColors.brand,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: tone ?? AppColors.ink,
            ),
          ),
        ),
        if (sub != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            sub!,
            maxLines: 2,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ],
    ),
  );
}
