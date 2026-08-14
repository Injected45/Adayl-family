import 'package:flutter/material.dart';

/// Glassmorphism + Flat Design.
///
/// ── The brief contains a genuine contradiction, so here is how it is resolved.
///
/// Flat Design specifies *no shadows, no gradients, 0–4px radius, solid
/// saturated fills*. Glassmorphism specifies *backdrop blur, translucency, a
/// vibrant background, layered z-depth*. Applied to the same element they cancel
/// out: a 4px-radius frosted pane with no depth reads as a rectangle of dirty
/// grey, not as glass.
///
/// The split used throughout this app:
///
///   GLASS governs the CHROME and the SURFACES — app bar, navigation, sheets,
///   dialogs, cards. Translucent, blurred, one hairline light border, floating
///   over a vibrant field.
///
///   FLAT governs the CONTENT inside those surfaces — solid saturated fills,
///   no gradients on text, icons, buttons or badges, crisp 1–2px strokes,
///   simple geometry, bold type, and no decorative drop shadows anywhere.
///
/// Glass needs something worth blurring. Frosted white over flat grey is just
/// grey, so [AppBackground] paints a vibrant field beneath everything — that
/// field is a functional requirement of the style, not decoration.
///
/// ── Deviations from the source guidance, and why
///
///   * Radius is 20px on glass panes, not Flat's 0–4px. See above.
///   * One very soft ambient shadow is permitted on FLOATING CHROME only (app
///     bar, bottom nav, sheets) to lift it off the field. Flat forbids
///     decorative shadows; this is the z-depth Glassmorphism requires, and it
///     appears on nothing else.
///   * Palette keeps the teal brand from index.html rather than the magenta the
///     generator proposed. This is a family association's treasury — the job is
///     trust, and brand continuity with the product people already use matters
///     more than novelty.
///
/// Every colour pairing below is contrast-tested in test/design_system_test.dart
/// against WCAG AA (4.5:1). Glassmorphism's documented failure mode is exactly
/// that, so it is asserted rather than eyeballed.
abstract final class AppColors {
  // ── Ink ────────────────────────────────────────────────────────────────────
  /// Body and heading text. 19:1 on white.
  static const Color ink = Color(0xFF0B1220);

  /// Secondary text. slate-600 — the lightest value that still clears AA on
  /// glass. Anything lighter is the single most common glassmorphism mistake.
  static const Color inkMuted = Color(0xFF475569);

  /// For labels ON a saturated flat fill.
  static const Color onFill = Color(0xFFFFFFFF);

  // ── Brand ──────────────────────────────────────────────────────────────────
  static const Color brand = Color(0xFF0F766E);
  static const Color brandDeep = Color(0xFF0B5A54);
  static const Color brandSoft = Color(0xFFCCFBF1);

  // ── Flat accents. Six, saturated, no gradients. ─────────────────────────────
  static const Color danger = Color(0xFFBE123C);
  static const Color dangerSoft = Color(0xFFFFE4E6);

  /// green-800, not green-700. Measured: green-700 reaches only 3.99:1
  /// against a 14% tint of itself, which is what StatusBadge draws, and it
  /// still fails at 10%. This is also the value index.html used.
  static const Color success = Color(0xFF166534);
  static const Color successSoft = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFF92400E);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color info = Color(0xFF4338CA);
  static const Color infoSoft = Color(0xFFE0E7FF);
  static const Color accent = Color(0xFFB45309);

  static const Color neutralSoft = Color(0xFFEEF2F6);

  // ── The vibrant field that makes glass legible ─────────────────────────────
  static const Color fieldBase = Color(0xFFE6F2F0);
  static const Color auroraTeal = Color(0xFF5EEAD4);
  static const Color auroraCyan = Color(0xFF7DD3FC);
  static const Color auroraAmber = Color(0xFFFDE68A);
  static const Color auroraViolet = Color(0xFFC7D2FE);

  // ── Compatibility aliases ──────────────────────────────────────────────────
  // Kept so the redesign did not have to touch 20 screens in one commit. New
  // code should use `ink` / `inkMuted` / `GlassColors`.
  static const Color text = ink;
  static const Color muted = inkMuted;
  static const Color background = fieldBase;
  static const Color card = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFDDE5EC);
  static const Color brandDark = brandDeep;
}

/// Translucency tokens.
///
/// Opacity is high on purpose. The guidance is explicit that a light-mode glass
/// card needs ~80% white, not 10% — at 10% the text sits on whatever happens to
/// be behind it and the contrast ratio becomes unknowable.
abstract final class GlassColors {
  /// Content surfaces: cards, panels, list rows. Text sits directly on this, so
  /// it is the most opaque.
  static const Color surface = Color(0xD1FFFFFF); // white @ 82%

  /// Floating chrome: app bar, navigation, sheets. Slightly more transparent
  /// because content is meant to be sensed moving beneath it.
  static const Color chrome = Color(0xBFFFFFFF); // white @ 75%

  /// Overlay surfaces: dialogs and bottom sheets.
  ///
  /// Nearly opaque, and for a concrete reason. A BackdropFilter inside an overlay
  /// route paints nothing on Android with Impeller, so these surfaces cannot be
  /// blurred (see GlassDialog). Without the frost there is nothing separating a
  /// translucent pane from the dimmed barrier behind it, and 82% white over a dark
  /// scrim reads as muddy grey rather than glass.
  static const Color overlay = Color(0xF7FFFFFF); // white @ 97%

  /// A recessed well inside a glass surface — inputs, KPI tiles, totals rows.
  ///
  /// Brand-tinted, not neutral. The first version used black at 8%, and the
  /// rendered result was dead grey that read as "disabled" rather than
  /// "recessed" — visible only once the design was looked at rather than
  /// measured. A cool tint at the same lightness reads as intentional depth.
  static const Color well = Color(0x120F766E); // brand @ 7%

  /// The well's own hairline. Depth needs an edge as well as a fill.
  static const Color wellEdge = Color(0x1A0F766E);

  /// The light-catching top edge. This single hairline is what reads as "glass"
  /// more than the blur does.
  static const Color stroke = Color(0xB3FFFFFF); // white @ 70%

  /// An outer hairline in ink, so the pane has a definite edge on a light
  /// field. A white-only border is invisible against pale backgrounds.
  static const Color hairline = Color(0x14101828); // ink @ 8%

  /// Ambient lift for floating chrome only.
  static const Color lift = Color(0x140B1220);
}

abstract final class AppRadius {
  /// Glass panes.
  static const double pane = 20;

  /// Flat controls — buttons, inputs.
  static const double control = 10;

  /// Flat badges and chips.
  static const double chip = 6;

  static const double pill = 999;

  // Compatibility alias.
  static const double card = pane;
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppMotion {
  /// Micro-interactions. The guidance range is 150–300ms; anything above 500ms
  /// reads as lag.
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 240);

  /// Entering. Ease-out for arrivals, ease-in for departures — linear reads
  /// robotic.
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
}

/// Fonts. Tajawal for display, Cairo for body.
///
/// Tajawal is geometric and slightly condensed, which gives headings presence
/// without shouting; Cairo is the more legible of the two at 11–14px, which is
/// where most of this app's text lives. Both are modern Arabic sans faces, so
/// the pairing reads as one voice at two weights rather than two typefaces
/// arguing.
///
/// Tajawal is declared as four STATIC weights in pubspec.yaml; Cairo is a single
/// variable file whose `wght` axis Flutter drives from `TextStyle.fontWeight`.
/// test/design_system_test.dart verifies both respond to fontWeight, because a
/// mis-declared family renders every weight at regular and nothing looks broken
/// enough to notice.
abstract final class AppFonts {
  static const String display = 'Tajawal';
  static const String body = 'Cairo';
}

ThemeData buildAppTheme() {
  const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.brand,
    onPrimary: AppColors.onFill,
    primaryContainer: AppColors.brandSoft,
    onPrimaryContainer: AppColors.brandDeep,
    secondary: AppColors.info,
    onSecondary: AppColors.onFill,
    secondaryContainer: AppColors.infoSoft,
    onSecondaryContainer: AppColors.info,
    tertiary: AppColors.accent,
    onTertiary: AppColors.onFill,
    error: AppColors.danger,
    onError: AppColors.onFill,
    errorContainer: AppColors.dangerSoft,
    onErrorContainer: AppColors.danger,
    // Transparent, because every surface in this app is glass painted over
    // AppBackground. A grey scaffold colour here would sit between the field and
    // the panes and kill the effect.
    surface: Color(0x00FFFFFF),
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.line,
    outlineVariant: AppColors.line,
  );

  // 1.5 line-height on body copy, per the typography guidance. Arabic needs it
  // more than Latin does: the script has tall ascenders and deep descenders that
  // collide at 1.2.
  final TextTheme text = const TextTheme(
    displaySmall: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 30,
      fontWeight: FontWeight.w800,
      height: 1.3,
      color: AppColors.ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 24,
      fontWeight: FontWeight.w800,
      height: 1.3,
      color: AppColors.ink,
    ),
    headlineSmall: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 20,
      fontWeight: FontWeight.w800,
      height: 1.35,
      color: AppColors.ink,
    ),
    titleLarge: TextStyle(
      fontFamily: AppFonts.display,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: AppColors.ink,
    ),
    titleMedium: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      height: 1.45,
      color: AppColors.ink,
    ),
    // 16px minimum for body copy on mobile.
    bodyLarge: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 16,
      height: 1.55,
      color: AppColors.ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 14,
      height: 1.55,
      color: AppColors.ink,
    ),
    bodySmall: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 12,
      height: 1.5,
      color: AppColors.inkMuted,
    ),
    labelLarge: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: AppColors.ink,
    ),
    labelMedium: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.4,
      color: AppColors.inkMuted,
    ),
    labelSmall: TextStyle(
      fontFamily: AppFonts.body,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: AppColors.inkMuted,
    ),
  );

  final RoundedRectangleBorder controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.control),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppFonts.body,
    textTheme: text,

    // Transparent so AppBackground shows through. AppBackground is installed
    // once, by AppScaffold.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,

    // The app bar is a glass pane built in AppScaffold, so the Material one is
    // stripped to nothing rather than fighting it.
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    ),

    // Flat: elevation 0, no surface tint, no drop shadow. Depth comes from the
    // glass hairline instead.
    cardTheme: CardThemeData(
      color: GlassColors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pane),
        side: const BorderSide(color: GlassColors.hairline),
      ),
    ),

    // 52px tall — comfortably over the 44px minimum touch target, and the same
    // height as before so no screen's rhythm changes.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onFill,
        disabledBackgroundColor: AppColors.neutralSoft,
        disabledForegroundColor: AppColors.inkMuted,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: controlShape,
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: AppColors.brandDeep,
        backgroundColor: GlassColors.surface,
        side: const BorderSide(color: AppColors.line, width: 1.5),
        shape: controlShape,
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandDeep,
        minimumSize: const Size(64, 44),
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(44, 44),
      ),
    ),

    // Inputs are a recessed well, not another pane — otherwise a field inside a
    // glass card is glass on glass and the boundary disappears.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GlassColors.well,
      isDense: true,
      contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
      hintStyle: const TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.inkMuted,
      ),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.inkMuted,
        fontWeight: FontWeight.w600,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: GlassColors.wellEdge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: GlassColors.wellEdge),
      ),
      // 2px focus ring, always visible. Keyboard users cannot use this app
      // without it and glass hides a subtle one completely.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.brand, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.danger, width: 2),
      ),
    ),

    // The real bar is a glass pane in AppScaffold; this keeps Material from
    // painting its own opaque one underneath.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.brandSoft,
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? AppColors.brandDeep
              : AppColors.inkMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (Set<WidgetState> states) => TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? AppColors.brandDeep
              : AppColors.inkMuted,
        ),
      ),
    ),

    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: AppColors.brandSoft,
      selectedIconTheme: IconThemeData(color: AppColors.brandDeep, size: 24),
      unselectedIconTheme: IconThemeData(color: AppColors.inkMuted, size: 24),
      selectedLabelTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w800,
        color: AppColors.brandDeep,
      ),
      unselectedLabelTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w600,
        color: AppColors.inkMuted,
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pane),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 14,
        height: 1.55,
        color: AppColors.ink,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      dragHandleColor: AppColors.inkMuted,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: GlassColors.surface,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 6,
        vertical: 8,
      ),
    ),

    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.brandDeep,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 12,
        color: AppColors.inkMuted,
      ),
      minVerticalPadding: 10,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 14,
        color: AppColors.onFill,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    ),

    dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.brand,
      linearTrackColor: AppColors.neutralSoft,
    ),

    // Flat: no ripple splash bleeding across a glass pane's rounded corner.
    splashFactory: InkSparkle.splashFactory,
  );
}
