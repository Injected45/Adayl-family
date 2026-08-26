import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حاويةُ الرصيد تلبس وضعَ العديل — وثلاثةُ أحوالٍ لا اثنان.
///
/// «الحاوية بالكامل تظهر بلون خلفية حمراء شفافة في حال العديل عليه مديونية …
/// وتظهر باللون الأخضر الزجاجي الشفاف في حال أن العديل لديه قيمة عهدة له.
/// ويظل الوضع العادي الموجود الآن في حال العديل صفر.»
///
/// ⚠ WHY A SOURCE SCAN. Building this hero needs a live session, a device
///   header and three separate api_adeel_detail answers. The DECISION is what
///   is worth pinning — which state gets which colour, and that the third gets
///   none — exactly as this repo pins its other invisible decisions.
void main() {
  _hintTests();

  final String hero = File(
    'lib/features/directory/presentation/adeel_portal_screen.dart',
  ).readAsStringSync();

  test('the card is red when he owes and green when he is in credit', () {
    final int at = hero.indexOf('final Color? heroFill');
    expect(at, greaterThan(-1), reason: 'the tinted hero is gone');
    final String block = hero.substring(at, at + 400);

    expect(block, contains('owes'));
    expect(block, contains('AppColors.danger'));
    expect(block, contains('inCredit'));
    expect(block, contains('AppColors.success'));
  });

  test(
    '⚠ and untinted when he is level — a signal always on is not a signal',
    () {
      final int at = hero.indexOf('final Color? heroFill');
      final String block = hero.substring(at, hero.indexOf(';', at) + 1);

      // ⚠ THE LAST BRANCH, NOT «the word null appears somewhere». The first
      //   version asserted contains('null') — and the block also holds
      //   «heroFill == null» a few lines below, so it passed with a brand tint
      //   painted on the neutral state. Proven by making that change: the test
      //   stayed green. An assertion that cannot fail is decoration.
      expect(
        block.trimRight().endsWith(': null;'),
        isTrue,
        reason:
            'the third state must be NO tint. Colouring a man who owes nothing '
            'and is owed nothing leaves the card always coloured, and then the '
            'two that mean something say nothing.',
      );
    },
  );

  test('and the tint is translucent at the alpha the design suite proves', () {
    final int at = hero.indexOf('final Color? heroFill');
    final String block = hero.substring(at, at + 400);
    expect(
      block,
      contains('withValues(alpha: 0.10)'),
      reason:
          'the tinted-KPI test proves label-and-figure over a 10% fill of '
          'their own tone. Deepening this fill fails that pairing, and both '
          'sides move together so it fails quietly.',
    );
  });

  test('⚠ the ⓘ circle is gone from beside the name', () {
    expect(
      hero,
      isNot(contains('Icons.info_outline')),
      reason: 'removed by request — the whole card is now the affordance',
    );
  });

  test('⚠ and «نشط» no longer sits beside the name', () {
    expect(
      hero,
      isNot(contains('StatusBadge(label: adeel.membershipStatus')),
      reason:
          'the status moved into «تفاصيل اشتراكي». Two places for one fact, '
          'and on the card he reads daily it competed with his balance.',
    );

    final String details = File(
      'lib/features/directory/presentation/portal_sections.dart',
    ).readAsStringSync();
    expect(
      details,
      contains('label: l.statusLabel'),
      reason: 'and it must actually BE in the details section',
    );
  });

  test('أسلافي reads green and أسلاف الغير reads red', () {
    // ⚠ «what the association GAVE HIM» was printed in danger — the colour
    //   this app uses for «عليك». A gift is not a debt.
    final int mine = hero.indexOf('l.myAidTitle');
    final int others = hero.indexOf('l.aidOthersTitle');
    expect(mine, greaterThan(-1));
    expect(others, greaterThan(-1));

    expect(
      hero.substring(mine, mine + 1000),
      contains('AppColors.success'),
      reason: 'أسلافي is money he RECEIVED',
    );
    expect(
      hero.substring(others, others + 1000),
      contains('AppColors.danger'),
      reason: 'أسلاف الغير is money that LEFT the fund',
    );
  });

  test('⚠ the hero figure carries «د.ل» beside it, quietly and with a gap', () {
    final int at = hero.indexOf(
      'crossAxisAlignment: CrossAxisAlignment.baseline',
    );
    expect(
      at,
      greaterThan(-1),
      reason:
          'the amount and its unit must sit on a shared BASELINE — a smaller '
          'Text in a Row otherwise centres against the tall one and floats in '
          'the middle of the digits.',
    );
    final String block = hero.substring(at - 600, at + 1100);

    expect(
      block,
      contains('l.currency'),
      reason: 'the unit is missing from the balance he opens the app for',
    );
    // ⚠ A GAP, NOT A SPACE IN A STRING. formatMoneyWithCurrency joins them into
    //   ONE string, so the unit would inherit the 40pt display face and the
    //   tone — «د.ل» as tall and as red as the amount, which is the «ملاصقة»
    //   look this replaced.
    expect(
      block,
      contains('SizedBox(width: AppSpacing.xs)'),
      reason: '«لا تكون ملاصقة للقيمة ولكن بها فراغ قليل»',
    );
    // ⚠ AND THE UNIT IS MUTED. Red means «عليك» and green means «لك» on this
    //   card; a currency symbol is neither, and painting it in the tone would
    //   make the label look like part of the claim.
    final int unit = block.indexOf('l.currency');
    expect(
      block.substring(unit),
      contains('AppColors.muted'),
      reason: 'the unit must not wear the meaning-carrying tone',
    );
  });

  test('and GlassCard keeps «no fill» as its default', () {
    // Every other card in the app repeats down a page. A fill that defaulted
    // to anything would turn the app into a page of colour and make the one
    // card that means something mean nothing.
    final String glass = File('lib/core/config/glass.dart').readAsStringSync();
    expect(glass, contains('this.fill,'));
    expect(
      glass,
      isNot(contains('this.fill =')),
      reason: 'fill must have no default value — null is the normal case',
    );
  });
}

/// الجملُ التوضيحيّة الأربع — محذوفةٌ، وتُطوى بلا أثر.
///
/// «اسمك ورقمك وحالتك وقيمة الاشتراك» sat under a page listing exactly those;
/// «أين يقف مال الجمعية — للاطلاع فقط» sat over the figures it described. The
/// association read all four and said «زائدة عن الحاجة».
void _hintTests() {
  test('⚠ the four section hints are empty', () {
    final Map<String, dynamic> ar =
        const JsonDecoder().convert(
              File('lib/l10n/app_ar.arb').readAsStringSync(),
            )
            as Map<String, dynamic>;

    for (final String key in <String>[
      'portalDetailsHint',
      'portalBankHint',
      'portalOfficialsHint',
      'portalTreasuryHint',
    ]) {
      expect(
        ar.containsKey(key),
        isTrue,
        reason: '\$key was deleted, not emptied',
      );
      expect(
        ar[key],
        '',
        reason:
            '\$key describes what its own page already shows. Emptied rather '
            'than removed, so a section that wants a hint again gets one by '
            'filling in the ARB with no widget to edit.',
      );
    }
  });

  test('and BOTH render sites collapse on an empty hint', () {
    // ⚠ A Text('') is not nothing: it leaves a blank line and its spacer. The
    //   subtitle is drawn twice — on the menu tile and on the page header — and
    //   guarding one of them would leave the other showing a gap on every
    //   section.
    final String src = File(
      'lib/features/directory/presentation/portal_sections.dart',
    ).readAsStringSync();
    expect(
      'section.subtitle.isNotEmpty'.allMatches(src).length,
      2,
      reason:
          'both the menu tile and the page header must guard on empty — the '
          'count is asserted so a third render site cannot be added unguarded',
    );
  });
}
