import 'package:flutter/material.dart';

import 'theme.dart';

/// شكلُ التطبيق: عاديّ أو ليليّ.
///
/// ⚠ THE TOKENS ARE MUTABLE STATICS AND THAT IS THE WHOLE DESIGN. `AppColors`
///   and `GlassColors` are named in 482 places across 45 files. Turning every
///   one of them into a `Theme.of(context)` lookup would be a rewrite of the
///   entire presentation layer for a preference; assigning the fields once and
///   rebuilding the app is the same result with none of that risk.
///
/// ⚠ AND IT ONLY WORKS BECAUSE NOTHING CACHES A COLOUR. Three things had to
///   change for that to be true, and each is commented where it lives:
///   the aliases (`text`, `muted`, `background`, `month`, `brandDark`) became
///   getters, the two derived `static` lists became getters, and 197 `const`
///   expressions lost their `const` — a widget frozen at compile time cannot
///   repaint in a new palette.
///
/// ⚠ NOTHING MAY READ A TOKEN BEFORE [applyAppTheme] RUNS. It is called in
///   main() before runApp, so the first frame is already in the right palette;
///   the fields carry the light values as their initialisers so a test that
///   forgets is light rather than blank.
enum AppThemeMode {
  /// الوضع العادي — الزجاج على حقلٍ فاتح.
  light,

  /// الوضع الليليّ — نفسُ الزجاج على حقلٍ داكن.
  dark,
}

/// يُبدّل اللوحة. يُستدعى قبل runApp وعند كل تغيير.
///
/// ⚠ EVERY VALUE IN THE DARK COLUMN WAS MEASURED, NOT PICKED. Each accent
///   clears WCAG AA against the dark content surface, the dark chrome, the dark
///   well AND its own 10% tint — the four pairings design_system_test proves,
///   which now runs in BOTH palettes. The worst of the ten is `danger` at
///   5.69:1 on its own tint; the rest sit between 6.6 and 15.
void applyAppTheme(AppThemeMode mode) {
  final bool dark = mode == AppThemeMode.dark;

  // ── الحبر ────────────────────────────────────────────────────────────────
  AppColors.ink = dark ? const Color(0xFFE8EEF5) : const Color(0xFF0B1220);
  AppColors.inkMuted = dark
      ? const Color(0xFF9FB0C4)
      : const Color(0xFF475569);

  // ⚠ onFill INVERTS, AND I HAD IT BACKWARDS. The first version pinned it to
  //   white with a confident note saying «flipping it would put white text on
  //   a light accent» — which is exactly what NOT flipping it does. The dark
  //   palette's accents ARE the light ones (#4ADE80, #FB7185, #FCD34D), so a
  //   white label on them measured 1.48:1. The contrast suite caught it on its
  //   first run in the dark palette, which is the whole reason it now runs in
  //   both.
  AppColors.onFill = dark ? const Color(0xFF0B1220) : const Color(0xFFFFFFFF);

  // ── العلامة ──────────────────────────────────────────────────────────────
  AppColors.brand = dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E);
  AppColors.brandDeep = dark
      ? const Color(0xFF99F6E4)
      : const Color(0xFF0B5A54);
  AppColors.brandSoft = dark
      ? const Color(0xFF134E4A)
      : const Color(0xFFCCFBF1);

  // ── الألوان الستّة ───────────────────────────────────────────────────────
  AppColors.danger = dark ? const Color(0xFFFB7185) : const Color(0xFFBE123C);
  AppColors.success = dark ? const Color(0xFF4ADE80) : const Color(0xFF166534);
  AppColors.warning = dark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);
  AppColors.info = dark ? const Color(0xFFA5B4FC) : const Color(0xFF4338CA);
  AppColors.accent = dark ? const Color(0xFFFDBA74) : const Color(0xFFB45309);
  AppColors.dues = dark ? const Color(0xFFD8B4FE) : const Color(0xFF6B21A8);

  // ── الظِّلال الفاتحة: تنقلب إلى غامقةٍ مشبعة ─────────────────────────────
  AppColors.dangerSoft = dark
      ? const Color(0xFF4C1D24)
      : const Color(0xFFFFE4E6);
  AppColors.successSoft = dark
      ? const Color(0xFF14361F)
      : const Color(0xFFDCFCE7);
  AppColors.warningSoft = dark
      ? const Color(0xFF422006)
      : const Color(0xFFFEF3C7);
  AppColors.infoSoft = dark
      ? const Color(0xFF262B57)
      : const Color(0xFFE0E7FF);
  AppColors.neutralSoft = dark
      ? const Color(0xFF1B2536)
      : const Color(0xFFEEF2F6);

  // ── الحقل الذي يجعل الزجاج زجاجاً ────────────────────────────────────────
  //
  // ⚠ THE WASHES STAY SATURATED AND ONLY THE BASE INVERTS. The aurora is what
  //   gives a translucent pane something worth blurring — see AppBackground —
  //   and washing it out in dark mode would leave frosted grey on black, which
  //   is the exact failure the light palette's note warns about.
  AppColors.fieldBase = dark
      ? const Color(0xFF0B1220)
      : const Color(0xFFE6F2F0);
  AppColors.auroraTeal = dark
      ? const Color(0xFF0F766E)
      : const Color(0xFF5EEAD4);
  AppColors.auroraCyan = dark
      ? const Color(0xFF0E7490)
      : const Color(0xFF7DD3FC);
  AppColors.auroraAmber = dark
      ? const Color(0xFF78350F)
      : const Color(0xFFFDE68A);
  AppColors.auroraViolet = dark
      ? const Color(0xFF312E81)
      : const Color(0xFFC7D2FE);

  AppColors.card = dark ? const Color(0xFF111C2E) : const Color(0xFFFFFFFF);
  AppColors.line = dark ? const Color(0xFF243044) : const Color(0xFFDDE5EC);

  // ── الزجاج ───────────────────────────────────────────────────────────────
  //
  // ⚠ THE ALPHAS ARE UNCHANGED AND THE TINT INVERTS. 82% / 75% / 97% are the
  //   figures the light palette's note defends — at 10% the text sits on
  //   whatever is behind it and the contrast becomes unknowable. That argument
  //   does not care which way round the colours are.
  GlassColors.surface = dark
      ? const Color(0xD1111C2E)
      : const Color(0xD1FFFFFF);
  GlassColors.chrome = dark
      ? const Color(0xBF111C2E)
      : const Color(0xBFFFFFFF);
  GlassColors.overlay = dark
      ? const Color(0xF70E1726)
      : const Color(0xF7FFFFFF);

  // ⚠ STILL FULLY OPAQUE. A dropdown opens over undimmed content, and text on
  //   text is the one thing translucency must never produce — in either
  //   palette. See the note on GlassColors.menu.
  GlassColors.menu = dark ? const Color(0xFF16213A) : const Color(0xFFFFFFFF);

  GlassColors.well = dark
      ? const Color(0x2900000F)
      : const Color(0x120F766E);

  // ── حوافُّ الزجاج، وهي ما يجعله زجاجاً ───────────────────────────────────
  //
  // ⚠ THESE FOUR WERE MISSED ON THE FIRST PASS and would have been invisible
  //   in the worst way: a dark pane keeps its LIGHT edges, so every card gets a
  //   bright white rim and every hairline disappears into the dark — the panes
  //   stop reading as glass and start reading as boxes. Nothing would have
  //   failed; it would simply have looked wrong.
  //
  // ⚠ AND THE DIRECTION FLIPS, NOT JUST THE VALUE. On light glass the rim is
  //   WHITE at 70% (a highlight) and the hairline is INK at 8% (a shadow line).
  //   On dark glass the rim must be white at a LOW alpha — 70% white on a dark
  //   pane is a bright frame, not a highlight — and the hairline must be white
  //   too, because ink on ink is nothing at all.
  // ⚠ ولونُ كلّ عديل: إضاءةٌ مقيسة، لا مقلوبة. See identityTone.
  AppColors.identityLight = dark ? 0.76 : 0.24;

  GlassColors.stroke = dark
      ? const Color(0x38FFFFFF)
      : const Color(0xB3FFFFFF);
  GlassColors.hairline = dark
      ? const Color(0x1FFFFFFF)
      : const Color(0x14101828);
  GlassColors.wellEdge = dark
      ? const Color(0x24FFFFFF)
      : const Color(0x1A0F766E);

  // ⚠ THE LIFT GOES DEEPER, NOT LIGHTER. It is the one soft shadow this design
  //   permits, and a shadow on a dark field has to be darker than the field to
  //   be seen at all.
  GlassColors.lift = dark
      ? const Color(0x66000000)
      : const Color(0x140B1220);
}
