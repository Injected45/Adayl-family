import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// «الاشتراك الشهري: 100» — a complete answer only while every month costs 100.
///
/// The association priced يناير and يونيو differently, and from that moment the
/// card on the عديل's page was NOT WRONG BUT INCOMPLETE.
///
/// ⚠ INCOMPLETE IS WORSE THAN MISSING, which is the whole reason this exists. A
///   blank invites a question; «100» invites nothing at all, and the man reads
///   it, believes it, and is surprised in January by a figure the database was
///   always going to bill him. generate_period has charged the month's own rate
///   since 20/08 (c); this is the same fact, said where he reads his fee.
void main() {
  final L l = LAr();

  // monthName goes through intl's ar data, which a bare unit test does not
  // load for itself.
  setUpAll(() => initializeDateFormatting('ar', null));

  test('the months are listed with their own figures', () {
    final String line = formatFeeExceptions(
      <String, String>{'01': '200.00', '06': '200.00'},
      l.feeExceptionLabel,
    );

    expect(line, contains(l.feeExceptionLabel));
    expect(line, contains(monthName(1)));
    expect(line, contains(monthName(6)));
    expect(line, contains(formatMoney('200.00')));
  });

  // ⚠ SORTED BY MONTH, NEVER BY INSERTION. fee_exceptions is a jsonb object and
  //   keeps whatever order it was written in, so without the sort the line
  //   reorders itself every time an admin edits the settings — and a line that
  //   moves on its own reads as a fault.
  test('and they are ordered by month, whatever order they were entered', () {
    final String line = formatFeeExceptions(
      <String, String>{'06': '200.00', '01': '150.00'},
      '',
    );
    expect(line.indexOf(monthName(1)), lessThan(line.indexOf(monthName(6))));
  });

  // ⚠ NO EXCEPTIONS MUST RENDER NOTHING, not an orphan «ماعدا». The caller keys
  //   its whole row off isNotEmpty, so an empty string here is what keeps the
  //   card looking exactly as it did before the feature existed.
  test('no exceptions is an empty string, not a bare label', () {
    expect(formatFeeExceptions(<String, String>{}, l.feeExceptionLabel), '');
  });

  test('a nonsense key is printed as-is rather than invented into a month', () {
    // The database refuses anything but «01».."12" — ck_settings_fee_exceptions
    // — so this can only arrive from a hand-edited row. Passing it through is
    // honest; guessing at it would hide the corruption.
    final String line = formatFeeExceptions(<String, String>{'99': '5.00'}, '');
    expect(line, contains('99'));
  });

  // ── And the view model carries it at all ──────────────────────────────────
  test('v_settings parses the map, and an old database parses to empty', () {
    final AssociationSettingsView withIt = AssociationSettingsView.fromJson(
      <String, dynamic>{
        'associationName': 'جمعية العدايل',
        'currency': 'د.ل',
        'memberFee': '100.00',
        'feeExceptions': <String, dynamic>{'01': '200.00'},
      },
    );
    expect(withIt.feeExceptions['01'], '200.00');

    // ⚠ A DATABASE THAT PREDATES THE COLUMN must parse, not throw. The portal
    //   reads this view on every launch; a hard cast would turn «one patch
    //   behind» into «the app does not open».
    final AssociationSettingsView without = AssociationSettingsView.fromJson(
      <String, dynamic>{
        'associationName': 'جمعية العدايل',
        'currency': 'د.ل',
        'memberFee': '100.00',
      },
    );
    expect(without.feeExceptions, isEmpty);
  });
}
