import 'package:family_app/features/finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// «أسلاف للغير» — الصرف الجماعي، لا سلف المشتركين الآخرين.
///
/// ── THE DECISION, AND THE ONE IT REPLACED ───────────────────────────────────
/// An earlier draft showed a member what the association had given every OTHER
/// member, by name, under a policy admitting him to every voucher. The
/// association looked at it and chose otherwise: the screen carries the
/// COLLECTIVE spending — فطور رمضان and its like — and nothing about any man.
///
/// That is the better rule, not merely the narrower one. A row naming a man who
/// received إعانة for a bereavement is the most private fact this system holds;
/// a row saying 400 went on فطور رمضان answers what a member actually wants to
/// know — «أين يذهب مالي» — and exposes nobody.
///
/// ⚠ AND THE SCOPE IS A POLICY, NOT A FILTER IN DART.
///   `read_collective_disbursements` is `payee_adeel_id IS NULL AND
///   my_adeel_id() IS NOT NULL`. Nothing below is a permission check, and
///   nothing below could be trusted as one — but the SHAPE of the answer is
///   worth pinning, because a screen that grew a payee column again would be
///   the first sign the policy had been widened underneath it.
void main() {
  test('a collective answer parses: totals, occasions, vouchers', () {
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '1150.00',
      'count': 3,
      'byCategory': <dynamic>[
        <String, dynamic>{
          'category': 'فطور رمضان',
          'total': '900.00',
          'count': 2,
        },
        <String, dynamic>{'category': 'عزاء', 'total': '250.00', 'count': 1},
      ],
      'vouchers': <dynamic>[
        <String, dynamic>{
          'id': 7,
          'voucherNo': 'EXP-07',
          'amount': '450.00',
          'kind': 'جماعي',
          'category': 'فطور رمضان',
          'payeeAdeelId': null,
          'payeeName': '',
          'payeeCode': '',
          'note': 'إفطار الجمعة الأخيرة',
          'method': 'نقداً',
          'status': 'معتمد',
          'spentAt': '2026-08-19T13:40:00Z',
          'runningTotal': '450.00',
        },
      ],
    });

    expect(a.total, '1150.00');
    expect(a.count, 3);
    expect(a.byCategory.first.category, 'فطور رمضان');
    expect(a.byCategory.first.total, '900.00');
    expect(a.vouchers.single.voucher.category, 'فطور رمضان');
  });

  test('⚠ a collective voucher names NOBODY, and that is the whole point', () {
    // ck_disb_shape refuses a payee on a collective voucher — that is what makes
    // it collective. So the screen has no name to print and cannot be made to
    // print one; the occasion is what identifies the row instead.
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '450.00',
      'count': 1,
      'byCategory': <dynamic>[],
      'vouchers': <dynamic>[
        <String, dynamic>{
          'id': 7,
          'voucherNo': 'EXP-07',
          'amount': '450.00',
          'kind': 'جماعي',
          'category': 'فطور رمضان',
          'payeeAdeelId': null,
          'payeeName': '',
          'payeeCode': '',
          'method': 'نقداً',
          'status': 'معتمد',
          'spentAt': '2026-08-19T13:40:00Z',
          'runningTotal': '450.00',
        },
      ],
    });

    expect(a.vouchers.single.voucher.payeeAdeelId, isNull);
    expect(a.vouchers.single.voucher.payeeName, isEmpty);
    expect(a.vouchers.single.voucher.category, isNotEmpty);
  });

  test('⚠ the totals are STRINGS, never parsed into a double', () {
    // Money is text end to end: numeric reaches dart:convert as a floating-point
    // number, and every sum on this screen is the association's own money.
    // api_aid_others does the adding, in Postgres.
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '1234.50',
      'count': 1,
      'byCategory': <dynamic>[],
      'vouchers': <dynamic>[],
    });
    expect(a.total, isA<String>());
    expect(a.total, '1234.50');
  });

  test('an empty answer is empty, not a crash', () {
    // What a member gets the moment `read_collective_disbursements` is dropped,
    // and what he gets on an association that has spent nothing collectively.
    // The screen must have one shape for both.
    final AidOthers a = AidOthers.fromJson(<String, dynamic>{
      'total': '0.00',
      'count': 0,
    });
    expect(a.isEmpty, isTrue);
    expect(a.byCategory, isEmpty);
    expect(a.vouchers, isEmpty);
  });
}
