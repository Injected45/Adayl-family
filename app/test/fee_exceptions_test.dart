import 'package:family_app/features/oversight/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// اشتراكٌ يختلف باختلاف الشهر.
///
/// The association agreed that some calendar months carry a different
/// subscription — يناير and يونيو at 200 while every other month stays at 100.
///
/// ⚠ KEYED BY CALENDAR MONTH, NOT BY PERIOD. «January is 200», not «January
///   2026 is 200» — so an entry holds every year until it is removed, and the
///   December somebody forgot to set it again cannot bill the wrong figure.
///   `generate_period` matches the key against `substr(period, 6, 2)`, which is
///   why «1» would never match and «01» must.
void main() {
  const OfficialInput nobody = OfficialInput(
    adeelId: null,
    name: '',
    phone: '',
  );

  EditableSettings settings(Map<String, String> exceptions) => EditableSettings(
    associationName: 'جمعية العدايل',
    currency: 'د.ل',
    memberFee: '100.00',
    feeExceptions: exceptions,
    systemStart: '2026-01-01',
    autoClosePreviousMonths: false,
    bankName: '',
    bankAccountNo: '',
    bankAccountName: '',
    treasurer: nobody,
    financeManager: nobody,
  );

  test('the exceptions travel to the server', () {
    final Map<String, dynamic> patch = settings(<String, String>{
      '01': '200.00',
      '06': '200.00',
    }).toPatch();

    expect(patch['feeExceptions'], <String, String>{
      '01': '200.00',
      '06': '200.00',
    });
    // And the standard fee is unchanged by their presence: the exceptions are
    // an override for named months, never a replacement for the fee itself.
    expect(patch['memberFee'], '100.00');
  });

  test('⚠ an EMPTY set is still sent, so the last one can be removed', () {
    // update_settings replaces the set rather than merging it, so removing an
    // exception is sending one fewer. Omit the key when the map empties and the
    // final removal becomes impossible — exactly the case an admin reaches for
    // when the association drops a special month.
    final Map<String, dynamic> patch = settings(
      <String, String>{},
    ).toPatch();

    expect(patch.containsKey('feeExceptions'), isTrue);
    expect(patch['feeExceptions'], <String, String>{});
  });

  test('a database that predates the column reads as no exceptions', () {
    // Not null, and not a crash: an app newer than its database must show every
    // month at the standard fee, which is exactly what the database is doing.
    final EditableSettings s = EditableSettings.fromJson(<String, dynamic>{
      'associationName': 'جمعية العدايل',
      'currency': 'د.ل',
      'memberFee': '100.00',
      'systemStart': '2026-01-01',
      'treasurer': <String, dynamic>{},
      'financeManager': <String, dynamic>{},
    });

    expect(s.feeExceptions, isEmpty);
  });

  test('and a set that came back is read whole', () {
    final EditableSettings s = EditableSettings.fromJson(<String, dynamic>{
      'associationName': 'جمعية العدايل',
      'currency': 'د.ل',
      'memberFee': '100.00',
      'feeExceptions': <String, dynamic>{'01': '200.00', '06': '200.00'},
      'systemStart': '2026-01-01',
      'treasurer': <String, dynamic>{},
      'financeManager': <String, dynamic>{},
    });

    expect(s.feeExceptions['01'], '200.00');
    expect(s.feeExceptions['06'], '200.00');
    expect(s.feeExceptions['02'], isNull);
  });
}
