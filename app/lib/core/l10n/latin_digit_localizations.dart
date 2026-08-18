import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';

/// ARABIC WORDS, LATIN DIGITS — «الثلاثاء، 10 فبراير 2026».
///
/// This is how Libya writes a date, and until now the app could not: the two
/// halves come from one locale and Flutter offers no switch between them.
///
/// ── Where the Arabic-Indic digits actually came from ────────────────────────
/// Not from intl. Its own `ar` data renders Latin digits — `DateFormat.yMMMd('ar')`
/// in a bare test prints «10 فبراير 2026» already. What changes that is
/// `GlobalMaterialLocalizations`: when its delegate loads, it installs Flutter's
/// OWN date symbols for the locale, and Flutter's `ar` carries
/// `ZERODIGIT: '٠'` — ٠. From that one field intl derives every digit it
/// prints for that locale, so after the delegate loads the calendar reads
/// ١٠ فبراير ٢٠٢٦ **and so does every date this app formats itself**.
///
/// That is why the fix belongs here and not in the formatters: they were never
/// the cause, and patching them would have left the calendar wrong.
///
/// ── Why it loads TWICE ──────────────────────────────────────────────────────
/// The symbols do not exist until the parent delegate installs them, so they
/// cannot be patched before the first load. And `GlobalMaterialLocalizations`
/// builds its DateFormats DURING that load — some of them cache the zero digit
/// at construction, which is why patching after one load fixed
/// `formatFullDate` and left `formatYear` printing ٢٠٢٦.
///
/// So: load (installs the symbols), patch, load again (rebuilds the formatters
/// from the patched symbols) and return the second result. The first instance is
/// discarded. It happens once per locale, at startup.
///
/// ⚠ NOTHING ELSE CHANGES. The buttons stay «حسنًا» and «إلغاء», the weekday and
///   month names stay Arabic, the direction stays RTL. The alternative that was
///   briefly in place — `Localizations.override(locale: en)` around the picker —
///   bought Latin digits by making the whole calendar English, which is the
///   opposite of what a Libyan association reads.
///
/// It must be listed BEFORE `GlobalMaterialLocalizations.delegate`; the first
/// delegate for a given type is the one Flutter uses. `latinDigitDelegates`
/// below does that, and `formatters_test` asserts the result rather than the
/// ordering rule, so a change in Flutter's precedence would fail loudly.
class LatinDigitMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const LatinDigitMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      GlobalMaterialLocalizations.delegate.isSupported(locale);

  /// ⚠ `.then(...)`, NOT `async`/`await`, and it is load-bearing.
  ///
  /// Flutter's global delegates return a `SynchronousFuture`, and `then` on one
  /// runs its callback immediately and hands back another synchronous future —
  /// so localizations still resolve within the FIRST frame. Writing this method
  /// `async` makes it a real Future however fast the work is, `Localizations`
  /// renders an empty box until the next frame, and every screen in the app
  /// gains a blank first frame. In the test suite it was not subtle: a dozen
  /// widget tests stopped finding the button they tap, because `pumpWidget`
  /// returned before anything had been built.
  @override
  Future<MaterialLocalizations> load(Locale locale) {
    return GlobalMaterialLocalizations.delegate.load(locale).then((_) {
      // `languageCode`, not the full tag: the app forces `Locale('ar')` and that
      // is the key the symbols were installed under. A DateFormat built for a
      // locale intl does not know silently falls back, and the patch would land
      // on the wrong entry without a word.
      DateFormat.y(locale.languageCode).dateSymbols.ZERODIGIT = null;

      return GlobalMaterialLocalizations.delegate.load(locale);
    });
  }

  @override
  bool shouldReload(LatinDigitMaterialLocalizationsDelegate old) => false;
}

/// The app's delegate list, with the Latin-digit Material delegate ahead of the
/// global one it wraps.
List<LocalizationsDelegate<dynamic>> latinDigitDelegates(
  List<LocalizationsDelegate<dynamic>> generated,
) => <LocalizationsDelegate<dynamic>>[
  const LatinDigitMaterialLocalizationsDelegate(),
  ...generated,
];
