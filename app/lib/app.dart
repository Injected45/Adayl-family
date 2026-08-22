import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/theme.dart';
import 'core/l10n/latin_digit_localizations.dart';
import 'core/router/app_router.dart';
import 'core/state/auto_refresh.dart';
import 'features/call/presentation/call_ui.dart';
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
      //
      // ── و«فلان يتصل»، فوق كل شاشة بلا استثناء ───────────────────────────
      // ⚠ IT LIVED IN AppScaffold AND THAT WAS A REAL BUG, not a tidy-up. Only
      //   screens built from AppScaffold carried it — and the عديل portal is
      //   deliberately not one, so the member sitting on his own screen had no
      //   banner and, because the provider is auto-disposed and nothing was
      //   watching it, NO CALL POLL AT ALL. Ringing him did nothing until he
      //   wandered into المجلس.
      //
      // ⚠ AND IT MUST BE INSIDE AutoRefresh, not beside it: the banner watches
      //   incomingCallProvider, and the heartbeat that pokes that provider in
      //   the background is registered by AutoRefresh. Two roots would be two
      //   answers to «is anybody calling».
      //
      //   It draws nothing unless a call is actually live, so every screen —
      //   including /login and /pending, where the provider returns null before
      //   ever starting a timer — carries it for the price of a SizedBox.
      builder: (BuildContext context, Widget? child) => AutoRefresh(
        child: Column(
          children: <Widget>[
            const IncomingCallBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }
}
