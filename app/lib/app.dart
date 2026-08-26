import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/config/palette.dart';
import 'core/config/theme.dart';
import 'core/config/theme_mode_provider.dart';
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

    // ── ⚠ الوضعُ يُشاهَد هنا، والتطبيقُ كلُّه يُعاد بناؤه ────────────────────
    //
    //   The palette is a set of plain statics, so a change to it repaints
    //   nothing on its own — the widgets have to be rebuilt to read the new
    //   values. Watching the mode at the ROOT is what does that: everything
    //   below is rebuilt in one pass, and buildAppTheme() is re-run with it.
    //
    // ⚠ AND THE KEY IS LOAD-BEARING. Without it Flutter reuses the element
    //   tree and every widget that did not itself depend on the provider keeps
    //   its old paint — a half-dark app. The key forces the subtree to be
    //   built afresh, which is exactly what a palette swap needs.
    final AppThemeMode mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      // onGenerateTitle rather than `title`, so even the window title comes
      // from the ARB file instead of a hard-coded Arabic literal.
      onGenerateTitle: (BuildContext context) => L.of(context).appTitle,
      debugShowCheckedModeBanner: false,

      key: ValueKey<AppThemeMode>(mode),
      theme: buildAppTheme(),
      // ⚠ ONE ThemeData, BUILT FROM WHICHEVER PALETTE IS LOADED — not a light
      //   theme and a dark theme handed to Flutter to choose between. This app
      //   names AppColors directly in 482 places; Flutter's own light/dark
      //   switch only reaches widgets that read Theme.of(context), so it would
      //   have changed the scaffolding and left every screen untouched.
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
