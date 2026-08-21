import 'package:family_app/core/format/arabic_search.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── البحث الذكي ────────────────────────────────────────────────────────────
///
/// Every case here is a way a plain `contains` FAILS SILENTLY: the row is on
/// the register, the spelling looks right on screen, and the search says «لا
/// توجد نتائج». A treasurer then concludes the man is not entered and enters
/// him a second time — and `adeels` has no natural key to refuse the duplicate,
/// so he is billed the monthly fee twice.
///
/// That is why these are tests and not a comment: the failure of a search box
/// is not «a search box is annoying», it is a duplicate on the register.
void main() {
  group('الهمزات — nobody types them on a phone', () {
    test('أحمد is found by typing احمد', () {
      expect(matchesSearch('احمد', <String>['أحمد المهدي']), isTrue);
    });

    test('and إبراهيم / آدم fold the same way', () {
      expect(matchesSearch('ابراهيم', <String>['إبراهيم']), isTrue);
      expect(matchesSearch('ادم', <String>['آدم']), isTrue);
    });

    // ⚠ AND IT WORKS IN BOTH DIRECTIONS. The register holds both spellings
    //   because eight different people entered it — so folding only the query
    //   would fix half the cases and leave the other half looking like a bug in
    //   the half that works.
    test('⚠ and the other way round: أحمد in the query finds احمد on the row', () {
      expect(matchesSearch('أحمد', <String>['احمد']), isTrue);
    });
  });

  test('التاء المربوطة — فاطمه finds فاطمة', () {
    expect(matchesSearch('فاطمه', <String>['فاطمة']), isTrue);
    expect(matchesSearch('فاطمة', <String>['فاطمه']), isTrue);
  });

  test('الألف المقصورة — مصطفي finds مصطفى', () {
    expect(matchesSearch('مصطفي', <String>['مصطفى']), isTrue);
    expect(matchesSearch('يحيى', <String>['يحيي']), isTrue);
  });

  // ⚠ THE APP FORCES THE `ar` LOCALE, so the keyboard offers ٠١٢٣٤٥٦٧٨٩ and a
  //   figure typed naturally is Arabic-Indic. Without this fold, searching a
  //   code or a month by number never works — and it is the fastest way to find
  //   a row, so it is the one people try first.
  test('⚠ الأرقام العربية — ٠٤ finds 04', () {
    expect(matchesSearch('٠٤', <String>['A-04']), isTrue);
    expect(matchesSearch('٢٠٢٦-٠١', <String>['2026-01']), isTrue);
  });

  test('التشكيل والتطويل are dropped, not folded', () {
    expect(matchesSearch('محمد', <String>['مُحَمَّد']), isTrue);
    expect(matchesSearch('محمد', <String>['محـــمد']), isTrue);
  });

  group('الفواصل', () {
    test('a code is found with or without its dash', () {
      expect(matchesSearch('a04', <String>['A-04']), isTrue);
      expect(matchesSearch('A-04', <String>['A-04']), isTrue);
      expect(matchesSearch('04', <String>['A-04']), isTrue);
    });

    test('and Latin case does not matter', () {
      expect(matchesSearch('a-04', <String>['A-04']), isTrue);
    });
  });

  group('كلمتان', () {
    // ⚠ AND ACROSS WORDS, NOT OR — the whole reason this feels intelligent.
    //   With OR, typing more words returns MORE rows, which is the opposite of
    //   what typing more is for.
    test('«محمد يناير» finds only محمد\'s January row', () {
      const List<String> januaryMuhammad = <String>[
        'محمد سالم',
        'A-03',
        '2026-01',
        'يناير 2026',
      ];
      const List<String> marchMuhammad = <String>[
        'محمد سالم',
        'A-03',
        '2026-03',
        'مارس 2026',
      ];
      const List<String> januarySalem = <String>[
        'سالم أحمد',
        'A-05',
        '2026-01',
        'يناير 2026',
      ];

      expect(matchesSearch('محمد يناير', januaryMuhammad), isTrue);
      expect(matchesSearch('محمد يناير', marchMuhammad), isFalse);
      expect(matchesSearch('محمد يناير', januarySalem), isFalse);
    });

    test('and the order of the words does not matter', () {
      expect(
        matchesSearch('يناير محمد', <String>['محمد سالم', 'يناير 2026']),
        isTrue,
      );
    });
  });

  test('an empty query matches everything — a blank box is not a filter', () {
    expect(matchesSearch('', <String>['أي شيء']), isTrue);
    expect(matchesSearch('   ', <String>['أي شيء']), isTrue);
  });

  test('and a null or empty field is skipped rather than matched', () {
    expect(matchesSearch('محمد', <String?>[null, '', 'محمد']), isTrue);
    expect(matchesSearch('محمد', <String?>[null, '']), isFalse);
  });

  // ⚠ THE HALF THAT PROVES THE REST. A folder that folded everything to the
  //   empty string would pass every test above and match every row.
  test('⚠ and something that does NOT match still does not', () {
    expect(matchesSearch('خالد', <String>['أحمد المهدي', 'A-04']), isFalse);
    expect(matchesSearch('99', <String>['A-04', '2026-01']), isFalse);
  });

  group('foldForSearch itself', () {
    test('collapses separators to single spaces and trims', () {
      expect(foldForSearch('  A--04 / 2026 '), 'a 04 2026');
    });

    test('leaves an ordinary Arabic word alone', () {
      expect(foldForSearch('سالم'), 'سالم');
    });
  });
}
