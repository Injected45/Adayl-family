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
