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
final DateFormat _monthOnlyFormat = DateFormat('MMMM', 'ar');

/// A billing period — `2026-01` — as a month name: «يناير».
///
/// One receipt often settles several months at once (FIFO takes the oldest
/// first), and the allocation line then reads
/// «2026-01: 100.00، 2026-02: 100.00، 2026-03: 100.00» — three years repeated
/// on a phone, for a receipt written this year. The month alone says the same
/// thing in a third of the room.
///
/// ⚠ THE YEAR COMES BACK WHEN IT IS NOT THIS ONE. The association drops it
///   because the app is worked in the current year and everything on the screen
///   belongs to it — true today, and false the first January that settles a
///   December. A bare «ديسمبر» on a receipt written in 2027 is ambiguous
///   between two months twelve apart, on the one document a member keeps.
///   So the rule is "drop what is obvious", not "drop the year": same short
///   line all year, and «ديسمبر 2026» when the period is not the current year.
///
/// The month names come from intl's `ar` data rather than a table of twelve
/// strings here: user-facing Arabic has two homes in this project and a
/// formatter is neither of them — and the calendar already prints these exact
/// names beside every date on the screen.
String formatPeriodMonth(String? period) {
  if (period == null || period.length < 7) return period ?? '';
  final int? year = int.tryParse(period.substring(0, 4));
  final int? month = int.tryParse(period.substring(5, 7));
  if (year == null || month == null || month < 1 || month > 12) return period;

  final String name = _monthOnlyFormat.format(DateTime(year, month));
  return year == DateTime.now().year ? name : '$name $year';
}

/// Libya’s wall clock, and deliberately NOT the handset’s.
///
/// ⚠ `toLocal()` READS THE DEVICE TIMEZONE, which is a setting. A phone put
///   on UTC+9 renders a voucher stamped at 23:30 Tripoli as the NEXT day, and
///   two members comparing screens then see different dates for one receipt.
///   The database stamps an absolute instant; the day it belongs to is the
///   association’s day, not the reader’s.
///
/// ⚠ A FIXED +02:00, and that is exact rather than approximate: Libya has
///   observed no daylight saving since 2013 and sits on UTC+2 all year. One
///   constant, no timezone database, no package — and if that ever changes,
///   this line is the only thing that changes with it.
const Duration _libyaOffset = Duration(hours: 2);

/// ⚠ ONLY WHEN THE WIRE CARRIED A ZONE. `DateTime.tryParse` marks a value UTC
///   when the text ends in Z or an offset — which is what a Postgres
///   `timestamptz` always sends. A bare «2026-08-21» from a `date` column
///   parses as LOCAL midnight instead, and shifting that would move the day
///   by one on any device east of Tripoli. So a day that arrived as a day is
///   already the answer, and is left exactly as it is.
DateTime _tripoli(DateTime t) => t.isUtc ? t.add(_libyaOffset) : t;

String formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final DateTime? parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : _dayFormat.format(_tripoli(parsed));
}

String formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final DateTime? parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : _dateTimeFormat.format(_tripoli(parsed));
}

/// The clock alone: «09:24».
///
/// A chat bubble carries the time and the LIST carries the date, printed once
/// between days — so repeating «10 فبراير 2026» on four hundred lines would be
/// the same fact four hundred times. 24-hour, matching add_Hm() in
/// [formatDateTime], because that is what the association's own screens
/// already show.
final DateFormat _timeOnlyFormat = DateFormat.Hm('ar');

String formatTime(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final DateTime? parsed = DateTime.tryParse(iso);
  return parsed == null ? '' : _timeOnlyFormat.format(_tripoli(parsed));
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

/// A calendar month by number — «يناير» for 1.
///
/// For the «ماعدا» rows in Settings, where the exception belongs to January
/// every year rather than to one January. The name comes from intl's `ar` data
/// for the same reason [formatPeriodMonth] takes it from there: Arabic has two
/// homes in this project and a formatter is neither of them.
String monthName(int month) => _monthOnlyFormat.format(DateTime(2000, month));
