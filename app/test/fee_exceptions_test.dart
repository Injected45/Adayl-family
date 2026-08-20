import 'dart:io';

import 'package:family_app/features/oversight/domain/models.dart';
import 'package:family_app/features/oversight/presentation/settings_screen.dart';
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

  // ── ما الذي يصل فعلاً إلى القاعدة ─────────────────────────────────────────
  //
  // `update_settings` saves the WHOLE settings screen in one statement, and
  // `ck_settings_fee_exceptions` refuses anything that is not «شهر: مبلغ». So a
  // row the admin added and never filled in does not merely fail to save
  // itself — it takes the association name, the fee, the bank details and the
  // officials down with it, to a 23514 that shows no Arabic message at all
  // because _isDisplayable only trusts a RULnn.
  group('ماعدا — ما يُرسَل وما يُسقَط', () {
    test('⚠ a row added and never filled in is dropped, not sent', () {
      expect(
        liveFeeExceptions(<String, String>{'01': '200', '06': ''}),
        <String, String>{'01': '200'},
      );
    });

    test('and whitespace is not an amount either', () {
      expect(liveFeeExceptions(<String, String>{'01': '   '}), isEmpty);
    });

    test('a figure is trimmed on its way out', () {
      expect(
        liveFeeExceptions(<String, String>{'01': ' 200.00 '}),
        <String, String>{'01': '200.00'},
      );
    });

    // ⚠ THE OTHER HALF OF THE RULE. A MALFORMED figure still travels: «200.»
    //   is refused by the CHECK and the admin is told. Dropping it here would
    //   save silently and leave يناير at the standard fee while he believed he
    //   had changed it — the worse of the two failures by a wide margin.
    test('⚠ but a malformed figure still travels, so the database refuses it', () {
      expect(
        liveFeeExceptions(<String, String>{'01': '200.'}),
        <String, String>{'01': '200.'},
      );
    });
  });

  // ⚠ THE ROWS MUST BE KEYED BY THEIR MONTH. Both fields in _ExceptionRow take
  //   `initialValue`, which is read on the FIRST build and never again — so
  //   without a key, removing a row or changing a month (the list re-sorts)
  //   makes Flutter match the widgets by POSITION, and the field that moved up
  //   keeps the amount of the row that used to be there. The admin then reads a
  //   figure against a month it does not belong to, and saves it.
  //
  //   Scanned rather than pumped: reaching that row needs a router, a session
  //   and a live Supabase client, and the property is one line of source.
  test('⚠ each ماعدا row is keyed by its month', () {
    final String src = File(
      'lib/features/oversight/presentation/settings_screen.dart',
    ).readAsStringSync();

    expect(
      src.contains('key: ValueKey<String>(month)'),
      isTrue,
      reason: 'without a key the amount fields keep the previous row’s text',
    );
  });
}
