import 'dart:io';

import 'package:family_app/features/directory/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// لوحُ المتأخّرات — والحدُّ الذي لا يتجاوزه.
///
/// The association asked for arrears BY NAME, visible to every member:
/// «ليصبح كل العدايل على دراية بكل من عليهم مستحقات ولم يدفعوا». That reverses
/// a rule this app had held from the start — api_association_finance() says
/// «no per-member figure» and the treasury page says «Aggregates only».
///
/// ⚠ THE REVERSAL IS NARROW AND THIS FILE IS WHERE THAT IS ENFORCED. A debt to
///   the group is the group's business. What the group GAVE a man is not:
///   «فلان أُعطي 500 لعزاء» is the most private fact this system holds, and
///   `read_all_disbursements_adeel` was DROPPED for exactly that reason. The
///   day somebody adds aid to this panel «for completeness», this test fails.
ArrearsRow _row({
  String owed = '0.00',
  String held = '0.00',
  bool mine = false,
}) => ArrearsRow.fromJson(<String, dynamic>{
  'adeelId': 3,
  'adeelCode': 'A-03',
  'name': 'هيثم مفتاح',
  'owed': owed,
  'held': held,
  'status': 'نشط',
  'mine': mine,
});

void main() {
  test('a man who owes reads as owing, and one who paid ahead does not', () {
    expect(_row(owed: '160.00').owes, isTrue);
    expect(_row(owed: '160.00').hasCredit, isFalse);

    expect(_row(held: '250.00').owes, isFalse);
    expect(_row(held: '250.00').hasCredit, isTrue);

    // ⚠ ZERO IS NOT «owes». A man billed and paid in full must not be painted
    //   red beside the four who have not paid at all.
    expect(_row().owes, isFalse);
    expect(_row().hasCredit, isFalse);
  });

  test('and the comparison parses the TEXT amount, never sorts it', () {
    // Money is text end to end in this app. «90» > «160» as strings, and a
    // screen that compared them that way would call the smaller debt the
    // larger one.
    expect(_row(owed: '90.00').owes, isTrue);
    expect(_row(owed: '160.00').owes, isTrue);
    expect(
      double.parse(_row(owed: '160.00').owed) >
          double.parse(_row(owed: '90.00').owed),
      isTrue,
      reason: 'the ordering is the server\'s, on numbers, not on these strings',
    );
  });

  test('⚠ the board carries arrears and credit — and nothing about aid', () {
    // The model is the contract. If a field for aid, a voucher, an occasion or
    // a receipt ever appears here, the narrow reversal has become a wide one.
    final String src = File(
      'lib/features/directory/domain/models.dart',
    ).readAsStringSync();
    final int at = src.indexOf('class ArrearsRow');
    expect(at, greaterThan(-1));
    final String body = src.substring(
      at,
      src.indexOf('class AssociationFinance'),
    );

    for (final String forbidden in <String>[
      'aid',
      'voucher',
      'disburs',
      'occasion',
      'receipt',
    ]) {
      expect(
        body.toLowerCase(),
        isNot(contains(forbidden)),
        reason:
            'ArrearsRow must not carry «\$forbidden». A debt to the group is '
            'the group\'s business; what the group gave a man is not — see '
            'PATCH_20260823a on why read_all_disbursements_adeel was dropped.',
      );
    }
  });

  test('⚠ and the SQL gates on in_association(), not on a role', () {
    // Too narrow and an عديل sees an empty board with nothing saying why —
    // which is what a naive has_role('viewer') check would produce, and which
    // passes every test written by somebody holding a staff account. Too wide
    // and a pending applicant reads the association's debtor list.
    final String sql = File(
      '../supabase/PATCH_20260823e_arrears_board.sql',
    ).readAsStringSync();

    expect(
      sql,
      contains('public.in_association()'),
      reason:
          'the board must use the one place «is he in the association» is '
          'answered — staff by my_role, an عديل by my_adeel_id',
    );
    expect(
      sql,
      contains('SECURITY DEFINER'),
      reason:
          'INVOKER would hand every man his OWN arrears under a heading that '
          'says «الجمعية» — a wrong answer with nothing on screen to doubt',
    );
    expect(
      sql,
      // ⚠ THE TABLE, NOT THE WORD. The header explains why aid is excluded
      //   and names read_all_disbursements_adeel doing it — a bare 'disburse'
      //   match failed on that sentence, which is documentation working.
      isNot(contains('public.disbursements')),
      reason: 'no aid on this board, in the SQL either',
    );
  });

  test('and it is shown ABOVE the collected totals, by request', () {
    final String src = File(
      'lib/features/directory/presentation/portal_sections.dart',
    ).readAsStringSync();
    final int board = src.indexOf('const _ArrearsBoard()');
    final int cash = src.indexOf('label: l.collectedCash');
    expect(board, greaterThan(-1), reason: 'the board is gone from الصندوق');
    expect(cash, greaterThan(-1));
    expect(
      board,
      lessThan(cash),
      reason:
          '«تجعله يظهر في أعلى القائمة فوق المحصل نقدا» — under the totals it '
          'is a detail; above them it is the first thing a member reads.',
    );
  });
}
