import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter_test/flutter_test.dart';

/// The member's headline figure says WHOSE money it is, in words.
///
/// ── WHAT WENT WRONG ─────────────────────────────────────────────────────────
/// The portal put «رصيدك الآن» over a red debt and «رصيدك لدى الجمعية» over a
/// green credit. One noun for two opposite facts — and رصيد in Arabic reads as
/// money that is YOURS, so the red one said the reverse of what it meant. A
/// member asked, in as many words, whether «رصيدك الآن ٦٠٠» was what he owed or
/// what he had, and whether his prepaid عهدة might be rolled into it.
///
/// The arithmetic was never in doubt: `netBalance` is debt MINUS credit, and
/// FIFO allocation plus `settle_from_credit` make holding both at once
/// impossible. Only the NAME was wrong, which is the harder kind of wrong —
/// nothing on the screen looks broken.
///
/// ── WHY THIS IS A TEST AND NOT A CODE COMMENT ───────────────────────────────
/// Because the fix is one word in a translation file, and translation files are
/// edited by people who cannot see which figure a key sits over. «رصيد» is the
/// natural word for a balance and will suggest itself again.
void main() {
  final L l = LAr();

  test('the debt label never calls itself a رصيد', () {
    // This is the whole bug, stated as a rule. It sits over a RED figure the
    // member must pay.
    expect(
      l.myBalanceNow.contains('رصيد'),
      isFalse,
      reason: 'رصيد reads as money owed TO him — this label sits over a debt',
    );
    expect(l.myBalanceNow.contains('عليك'), isTrue);
  });

  test('...and the credit label names عهدة, not a رصيد either', () {
    // Same word, opposite fact. Naming this one عهدة keeps it the same term the
    // treasury and the home screen use for the identical quantity.
    expect(
      l.myWalletTitle.contains('عهدة') || l.myWalletTitle.contains('عهدت'),
      isTrue,
    );
  });

  test('the two labels share no word, so colour is never the only signal', () {
    // The point of the rename. A member who cannot separate red from green, or
    // who is reading a phone in Libyan sunlight, gets the answer from the words
    // alone — and so does anyone hearing the screen read aloud.
    Set<String> words(String s) => s.split(RegExp(r'\s+')).toSet();

    expect(
      words(l.myBalanceNow).intersection(words(l.myWalletTitle)),
      isEmpty,
      reason: 'the debt and credit headings must not begin with the same noun',
    );
  });

  test('the derivation strip agrees with the heading above it', () {
    // إجمالي المُصدَر − المسدَّد = ‹this›. It was «الرصيد», the same ambiguous
    // noun one line under the figure it explains.
    expect(l.myRemainingTotal.contains('رصيد'), isFalse);
  });
}
