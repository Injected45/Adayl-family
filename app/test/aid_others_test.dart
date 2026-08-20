import 'package:family_app/features/finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// «أسلاف للغير» — what the association gave everybody else.
///
/// ── THE DECISION BEHIND IT ──────────────────────────────────────────────────
/// Until PATCH_20260820b a member saw his own aid and nothing else, because a
/// row here records that a NAMED man received إعانة for a bereavement, a birth
/// or an emergency — the most private fact this system holds. The association
/// chose otherwise, in these words: «كل شيء بالأسماء».
///
/// ⚠ AND THE DECISION IS A POLICY, NOT A FILTER IN DART. What admits a member
///   to the rows is `read_all_disbursements_adeel`; `api_aid_others` is SECURITY
///   INVOKER and reads under his own policies. Dropping that one statement
///   empties this screen with no code change — which is the only sense in which
///   a decision like this is reversible at all. Nothing below is a permission
///   check, and nothing below could be trusted as one.
void main() {
  test('a full answer parses, names and all', () {
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '2250.00',
      'count': 3,
      'men': <dynamic>[
        <String, dynamic>{
          'adeelId': 3,
          'name': 'المهدي عبدالله محمد',
          'total': '1500.00',
          'count': 2,
        },
        <String, dynamic>{
          'adeelId': 9,
          'name': 'سالم صالح الشيخي',
          'total': '750.00',
          'count': 1,
        },
      ],
      'vouchers': <dynamic>[
        <String, dynamic>{
          'id': 7,
          'voucherNo': 'EXP-07',
          'amount': '750.00',
          'kind': 'لمشترك',
          'category': 'عزاء',
          'payeeAdeelId': 9,
          'payeeName': 'سالم صالح الشيخي',
          'payeeCode': '',
          'method': 'نقداً',
          'status': 'معتمد',
          'spentAt': '2026-08-19T13:40:00Z',
          'runningTotal': '750.00',
        },
      ],
    });

    expect(a.total, '2250.00');
    expect(a.count, 3);
    expect(a.men.first.name, 'المهدي عبدالله محمد');
    expect(a.vouchers.single.voucher.payeeName, 'سالم صالح الشيخي');
  });

  test('⚠ the totals are STRINGS, never parsed into a double', () {
    // Money is text end to end in this app: numeric reaches dart:convert as a
    // floating-point number, and a screen that summed the association's amounts
    // itself would put its treasury on binary floating point. api_aid_others
    // does the adding, in Postgres.
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '1234.50',
      'count': 1,
      'men': <dynamic>[],
      'vouchers': <dynamic>[],
    });
    expect(a.total, isA<String>());
    expect(a.total, '1234.50');
  });

  test('⚠ the payee CODE is empty for another man, and that is correct', () {
    // v_disbursements LEFT JOINs `adeels` for the code, and a member's RLS on
    // that table is still his own row only. The NAME survives because it is
    // snapshot onto the voucher. So the screen reads a name with no code beside
    // it — the register stays closed, which is the half of privacy the
    // association did NOT give up.
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '750.00',
      'count': 1,
      'men': <dynamic>[],
      'vouchers': <dynamic>[
        <String, dynamic>{
          'id': 7,
          'voucherNo': 'EXP-07',
          'amount': '750.00',
          'kind': 'لمشترك',
          'category': 'عزاء',
          'payeeAdeelId': 9,
          'payeeName': 'سالم صالح الشيخي',
          'payeeCode': '',
          'method': 'نقداً',
          'status': 'معتمد',
          'spentAt': '2026-08-19T13:40:00Z',
          'runningTotal': '750.00',
        },
      ],
    });

    expect(a.vouchers.single.voucher.payeeName, isNotEmpty);
    expect(a.vouchers.single.voucher.payeeCode, isEmpty);
  });

  test('an empty answer is empty, not a crash', () {
    // What a member gets the moment `read_all_disbursements_adeel` is dropped,
    // and what he gets on an association that has disbursed nothing. The screen
    // must have one shape for both.
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '0.00',
      'count': 0,
    });
    expect(a.isEmpty, isTrue);
    expect(a.men, isEmpty);
    expect(a.vouchers, isEmpty);
  });
}
