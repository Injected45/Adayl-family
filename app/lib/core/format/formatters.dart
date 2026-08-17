import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Matches the prototype's `Intl.NumberFormat("ar-LY", {minimumFractionDigits:2,
/// maximumFractionDigits:2})` (index.html:104), so amounts render with the same
/// Arabic-Indic digits and separators the association already reads.
final NumberFormat _moneyFormat = NumberFormat.decimalPatternDigits(
  locale: 'ar_LY',
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

final DateFormat _dayFormat = DateFormat.yMd('ar');
final DateFormat _dateTimeFormat = DateFormat.yMd('ar').add_Hm();

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
