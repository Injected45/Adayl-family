import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «دفعتَ» أخضر و«استلمتَ» أحمر — في كل حاويةٍ على الشاشة.
///
/// ⚠ THE PAIR APPEARS IN FOUR CONTAINERS AND ONE OF THEM WAS NEARLY MISSED.
///   The two figures sit on the value card, on the chart legend, on the chart
///   itself and on the two ends of the share bar — and on that last one
///   «دفعتَ» was BLUE, so a sweep looking for green-and-red walked straight
///   past it. One figure in a different colour on a third container is how a
///   reader learns to distrust all of them.
///
/// ⚠ AND THE PAIR WAS REVERSED ONCE, deliberately, then reversed back. It is
///   pinned here so a future «money leaving him should be red» does not undo
///   it silently: the colours now AGREE WITH THE VERDICT under them — paying
///   more ends in «رصيد مستحق لك» in green, receiving more in «رصيد مستحق
///   عليه» in red.
void main() {
  /// Every place a `l.valuePaid` / `l.valueReceived` / `l.myPaidTotal` label is
  /// given a tone, as (file, label, expected colour).
  const Map<String, String> expected = <String, String>{
    'l.valuePaid': 'AppColors.success',
    'l.myPaidTotal': 'AppColors.success',
    'l.valueReceived': 'AppColors.danger',
  };

  const List<String> files = <String>[
    'lib/features/finance/presentation/member_value_screen.dart',
    'lib/features/finance/presentation/member_months_chart.dart',
    'lib/features/finance/presentation/member_value_bar.dart',
    'lib/features/directory/presentation/adeel_portal_screen.dart',
  ];

  test('⚠ every «دفعتَ» is green and every «استلمتَ» is red', () {
    final List<String> wrong = <String>[];
    int seen = 0;

    for (final String f in files) {
      final List<String> lines = File(f).readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        for (final MapEntry<String, String> e in expected.entries) {
          if (!lines[i].contains('label: ${e.key}')) continue;
          // ⚠ A WINDOW ON BOTH SIDES. The first version looked only AFTER
          //   the label — and the chart legend writes «tone:» BEFORE it, so
          //   two of the six call sites were never examined and the count
          //   came back 4. A scan that silently covers less than it claims is
          //   the same defect this test exists to catch.
          final int from = (i - 6).clamp(0, lines.length);
          final int end = (i + 6).clamp(0, lines.length);
          final String near = lines.sublist(from, end).join('\n');
          if (!near.contains('tone:')) continue;
          seen++;
          if (!near.contains(e.value)) {
            wrong.add('$f:${i + 1}  ${e.key} → expected ${e.value}');
          }
        }
      }
    }

    expect(
      seen,
      greaterThanOrEqualTo(6),
      reason:
          'the pair is drawn in four containers — if this count drops, a call '
          'site was renamed and is no longer being checked at all',
    );
    expect(
      wrong,
      isEmpty,
      reason:
          '«دفعتَ» is green and «استلمتَ» is red in EVERY container. One in a '
          'different colour teaches the reader to distrust all of them:\n  '
          '${wrong.join('\n  ')}',
    );
  });

  test(
    'and the chart draws its waves in the same two colours as its legend',
    () {
      // A legend in one colour over a wave in another is a chart that lies
      // quietly — the reader believes the key and reads the wrong line.
      final String src = File(
        'lib/features/finance/presentation/member_months_chart.dart',
      ).readAsStringSync();

      expect(
        src,
        contains('_wave(canvas, paid, x, y, AppColors.success, dashed: false)'),
        reason: 'the «دفعتَ» wave must be green, and solid',
      );
      expect(
        src,
        contains('_wave(canvas, got, x, y, AppColors.danger, dashed: true)'),
        reason: 'the «استلمتَ» wave must be red, and dashed',
      );
    },
  );

  test('⚠ and the dash survives, because colour alone is not identity', () {
    // The pair validates at ΔE 6.4 under tritanopia — the floor band, legal
    // only with a second channel. The dash IS that channel.
    final String src = File(
      'lib/features/finance/presentation/member_months_chart.dart',
    ).readAsStringSync();
    expect(src, contains('dashed: false'));
    expect(src, contains('dashed: true'));
  });
}
