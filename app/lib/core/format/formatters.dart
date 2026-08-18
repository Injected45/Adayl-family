import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// ── EVERY FIGURE IN THIS APP IS IN LATIN DIGITS ─────────────────────────────
///
/// `en`, and it is worth being exact about why, because the obvious reason is
/// wrong. This was `ar_LY`, matching the prototype's
/// `Intl.NumberFormat("ar-LY", …)` (index.html:104) — and it ALSO printed
/// 1,234.56. intl carries no `ar_LY` data at all, so it fell back to `ar`, whose
/// number symbols already hold `ZERO_DIGIT: '0'`. **Money in this app was never
/// Arabic-Indic**, and changing this line changed no pixel.
///
/// What genuinely WAS Arabic-Indic is dates, for an unrelated reason — see the
/// DateFormats below. `en` is kept here because it is explicit: it names the
/// separators these screens use ('.' and ',') rather than arriving at them
/// through a locale that does not exist and a fallback nobody would think to
/// look for.
///
/// ⚠ INPUT is a different problem and is NOT solved here. The app forces the
///   `ar` locale, so the keyboard still offers ٠١٢٣٤٥٦٧٨٩ and a treasurer
///   typing a fee still produces them. [ArabicDigitsFormatter] below folds
///   those to ASCII as they are typed, and it is still required on every
///   numeric field.
final NumberFormat _moneyFormat = NumberFormat.decimalPatternDigits(
  locale: 'en',
  decimalDigits: 2,
);

/// The API sends money as an exact decimal string. Parsing to a double here is
/// safe ONLY because this is the display edge — the client performs no monetary
/// arithmetic whatsoever; every total it shows was computed by the server.
String formatMoney(String? decimal) {
  if (decimal == null || decimal.isEmpty) return _moneyFormat.format(0);
  return _moneyFormat.format(double.tryParse(decimal) ?? 0);
}

String formatMoneyWithCurrency(String? decimal, String currency) =>
    '${formatMoney(decimal)} $currency';

/// ── ARABIC MONTHS, LATIN DIGITS: «10 فبراير 2026» ───────────────────────────
///
/// How Libya writes a date, and what the association asked for in as many
/// words. The two halves come from one locale and Flutter offers no switch
/// between them — the fix is in `core/l10n/latin_digit_localizations.dart`, and
/// it is upstream of this file: `GlobalMaterialLocalizations` installs Flutter's
/// own date symbols for `ar`, which carry `ZERODIGIT: '٠'`, and from that ONE
/// field intl derives every digit it prints for the locale. That is what turned
/// these formatters Arabic-Indic inside the app while a bare test showed them
/// Latin.
///
/// So the locale here is `ar` on purpose and stays that way: the month names
/// have to come from somewhere, and hard-coding twelve of them in a formatter
/// would put user-facing Arabic outside its two homes for no gain.
///
/// This was briefly `yyyy-MM-dd`, on the theory that the digits were the problem
/// and a numeric pattern sidestepped them. It did — by removing the month name
/// as well, which is the half the association actually wanted in Arabic.
final DateFormat _dayFormat = DateFormat('d MMMM y', 'ar');
final DateFormat _dateTimeFormat = DateFormat('d MMMM y', 'ar').add_Hm();

String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final DateTime? parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : _dayFormat.format(parsed.toLocal());
}

String formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final DateTime? parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : _dateTimeFormat.format(parsed.toLocal());
}

/// Folds Arabic-Indic digits to ASCII as they are typed.
///
/// The app forces the `ar` locale, so the keyboard offers ٠١٢٣٤٥٦٧٨٩ and
/// anyone typing a figure naturally produces them. Every numeric cast on the
/// server is ASCII-only, and Dart's own `\d` is too — so a `FilteringTextInput
/// Formatter` placed BEFORE this one does not merely reject the digits, it
/// makes them invisible: each keystroke is dropped and the box never fills.
/// That is what emptied the monthly-fee box and turned a settings save into a
/// bare `22P02`.
///
/// Always list this FIRST. The Arabic decimal separator ٫ (U+066B) folds to '.'
/// for the same reason.
///
/// Lives here rather than beside one screen because three boxes now need it —
/// the fee, the system start date, and an عديل's telephone — and a private copy
/// in each is how the second and third came to be written without it.
class ArabicDigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final StringBuffer out = StringBuffer();
    for (final int rune in newValue.text.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.writeCharCode(0x30 + rune - 0x0660); // ٠-٩
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.writeCharCode(0x30 + rune - 0x06F0); // ۰-۹ (extended)
      } else if (rune == 0x066B) {
        out.writeCharCode(0x2E); // ٫ → .
      } else {
        out.writeCharCode(rune);
      }
    }
    final String text = out.toString();
    if (text == newValue.text) return newValue;

    // Length is unchanged by a one-for-one fold, so the caret keeps its offset
    // — recomputing it would move the cursor mid-typing.
    return TextEditingValue(
      text: text,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
