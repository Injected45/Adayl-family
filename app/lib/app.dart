import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/theme.dart';
import 'core/l10n/latin_digit_localizations.dart';
import 'core/router/app_router.dart';
import 'core/state/auto_refresh.dart';
import 'l10n/app_localizations.dart';

class FamilyApp extends ConsumerWidget {
  const FamilyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(routerProvider);

    return MaterialApp.router(
      // onGenerateTitle rather than `title`, so even the window title comes
      // from the ARB file instead of a hard-coded Arabic literal.
      onGenerateTitle: (BuildContext context) => L.of(context).appTitle,
      debugShowCheckedModeBanner: false,

      theme: buildAppTheme(),
      // The prototype has no dark palette, and inventing one would be a
      // redesign rather than a migration. Revisit as a deliberate piece of work.
      themeMode: ThemeMode.light,

      // Arabic is forced rather than following the device: this is a Libyan
      // family association and the data itself (statuses, payment methods) is
      // stored in Arabic. Flutter derives Directionality.rtl from the locale,
      // so nothing needs to wrap the tree in a Directionality widget.
      locale: const Locale('ar'),
      // Arabic words, Latin digits — see latin_digit_localizations.dart. The
      // wrapper must come first, so it is prepended here rather than edited
      // into L.localizationsDelegates, which gen-l10n regenerates.
      localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
      supportedLocales: L.supportedLocales,

      routerConfig: router,

      // ── EVERY FIGURE STAYS CURRENT ON ITS OWN ────────────────────────────
      // Wrapped around the whole app rather than mounted per screen: one clock
      // for the association, so navigating does not restart it and a screen
      // left open does not stop it. The refresh costs a request only for the
      // providers actually being watched — see core/state/auto_refresh.dart.
      builder: (BuildContext context, Widget? child) =>
          AutoRefresh(child: child ?? const SizedBox.shrink()),
    );
  }
}
