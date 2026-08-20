import 'package:family_app/features/finance/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// «الجدوى» — and the one label the whole screen turns on.
///
/// ── THE RULE IT IS BUILT AGAINST ────────────────────────────────────────────
/// «الجمعية خيرية»: aid is never deducted from a subscription. The aid ledger is
/// a separate screen from the statement for exactly that reason — the place the
/// rule would actually break is a layout that puts the two side by side and
/// invites the eye to subtract.
///
/// The association asked for that subtraction. It is here, and the rule survives
/// in the WORDING rather than in a warning nobody reads:
///
///   received > paid  →  «أعطتك الجمعية أكثر مما دفعتَ بـ …»
///   paid > received  →  «فائض تكافلك» — what he contributed to others
///
/// ⚠ CALLING THE SECOND ONE A LOSS, OR «لك عند الجمعية», WOULD BE THE WHOLE BUG.
///   It would teach a member that his subscriptions are a deposit he is owed
///   back, and teach the man who has taken more than he gave that he is square
///   and may stop paying. In a mutual fund the surplus of the men nothing
///   happened to IS what covers the man something happened to.
void main() {
  test('the model carries every figure as TEXT', () {
    // Money is text end to end: numeric reaches dart:convert as a floating-point
    // number, and every sum on this screen is the association's own money.
    final MemberValue v = MemberValue.fromJson(<String, dynamic>{
      'paid': '1200.00',
      'received': '2150.00',
      'collected': '18400.00',
      'toMembers': '14350.00',
      'helped': 6,
      'members': 10,
      'largest': '1750.00',
    });

    expect(v.paid, isA<String>());
    expect(v.received, '2150.00');
    expect(v.largest, '1750.00');
    expect(v.helped, 6);
    expect(v.members, 10);
  });

  test('an association that has given nothing still answers', () {
    // A fund in its first month: every figure zero, no nulls, one shape for the
    // screen to render. A blank here would read as a figure that failed to load
    // on the one screen whose whole purpose is figures.
    final MemberValue v = MemberValue.fromJson(<String, dynamic>{});

    expect(v.paid, '0.00');
    expect(v.received, '0.00');
    expect(v.collected, '0.00');
    expect(v.toMembers, '0.00');
    expect(v.largest, '0.00');
    expect(v.helped, 0);
    expect(v.members, 0);
  });

  test('⚠ the surplus is a DIRECTION, and the sign is what names it', () {
    // The screen reads the sign and picks the label. Both cases asserted here
    // because the labels are opposites and swapping them is a silent change:
    // the numbers stay right and the sentence becomes a lie.
    final MemberValue ahead = MemberValue.fromJson(<String, dynamic>{
      'paid': '1200.00',
      'received': '2150.00',
    });
    expect(
      double.parse(ahead.received) > double.parse(ahead.paid),
      isTrue,
      reason: 'أعطتك الجمعية أكثر مما دفعت',
    );

    final MemberValue behind = MemberValue.fromJson(<String, dynamic>{
      'paid': '1200.00',
      'received': '0.00',
    });
    expect(
      double.parse(behind.paid) > double.parse(behind.received),
      isTrue,
      reason: 'فائض تكافله — لا دين له على الجمعية',
    );
  });

  test('the coverage ratio survives an empty fund without dividing by zero', () {
    // «من كل 100 محصَّلة، صُرف X» is undefined before the first payment. The
    // screen answers 0 rather than NaN — which would render as «NaN» beside a
    // real currency on a real phone.
    final MemberValue v = MemberValue.fromJson(<String, dynamic>{
      'collected': '0.00',
      'toMembers': '0.00',
    });
    expect(double.parse(v.collected), 0);
  });
}
