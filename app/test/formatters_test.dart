import 'package:family_app/core/format/formatters.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// EVERY FIGURE THIS APP DISPLAYS IS IN LATIN DIGITS.
///
/// Both formatters used to be Arabic-locale: money was `ar_LY` (٦٠٠٫٠٠) and
/// dates were `DateFormat.yMd('ar')` (٢٠٢٦/٠٢/١٠). The association asked for one
/// script across the whole app, and the reason is visible on any receipt: dates
/// that reach a screen as plain strings from SQL — `registeredAt`, the year
/// inside «يناير 2026» — are Latin because Postgres wrote them with to_char, so
/// an Arabic-Indic amount sat beside a Latin date on the same line.
///
/// These are four lines of configuration that every screen in the app reads
/// through, which is exactly why they are worth pinning: nothing else would
/// fail if one of them quietly went back to `ar`.
///
/// ⚠ INPUT IS A SEPARATE PROBLEM, and the last test here is the one that keeps
///   it solved. The app forces the `ar` locale, so the keyboard still offers
///   ٠١٢٣٤٥٦٧٨٩ whatever the display does — and Postgres casts and Dart's `\d`
///   are ASCII-only. [ArabicDigitsFormatter] is what stands between the two.
void main() {
  // What the app gets from GlobalMaterialLocalizations at startup and a pure
  // unit test does not. Without it, a DateFormat built for `ar` throws: the
  // locale symbols were never installed. The widget test further down loads the
  // real delegates and is the one that proves the app own path.
  setUpAll(() => initializeDateFormatting('ar', null));

  group('money', () {
    test('renders in Latin digits, to the minor unit', () {
      expect(formatMoney('600'), '600.00');
      expect(formatMoney('600.5'), '600.50');
      // No Arabic-Indic digit, and no Arabic decimal separator ٫ (U+066B),
      // which is what `ar_LY` used to emit between the two halves.
      expect(formatMoney('600.00'), isNot(contains('٫')));
      expect(RegExp(r'^[0-9,.]+$').hasMatch(formatMoney('1234.56')), isTrue);
    });

    test('thousands are grouped the way the rest of the numerals are', () {
      expect(formatMoney('1234.56'), '1,234.56');
    });

    test('a missing amount is a real zero, not a blank', () {
      // A blank in a money column reads as a figure that failed to load, which
      // on a treasury screen is the worst available ambiguity.
      expect(formatMoney(null), '0.00');
      expect(formatMoney(''), '0.00');
    });
  });

  group('dates', () {
    test('render with an ARABIC month and LATIN digits', () {
      // «10 فبراير 2026» — how Libya writes a date, and the thing Flutter has
      // no switch for: the month name and the digits come from one locale.
      expect(formatDate('2026-02-10T09:00:00Z'), '10 فبراير 2026');
      expect(
        formatDateTime('2026-02-10T00:00:00Z').startsWith('10 فبراير 2026'),
        isTrue,
      );
      // No Arabic-Indic digit anywhere in the output.
      expect(RegExp(r'[٠-٩]').hasMatch(formatDate('2026-02-10')),
          isFalse);
    });

    test('a billing period reads as a month name alone, in the current year', () {
      // One receipt often settles several months at once, and «2026-01: 100.00»
      // three times over prints the same year three times on a phone. The month
      // says it in a third of the room.
      //
      // Computed from today's year rather than hard-coded: an assertion that
      // said '2026' would pass all year and fail on the first of January, which
      // is the worst possible morning to find out.
      final int thisYear = DateTime.now().year;
      expect(formatPeriodMonth('$thisYear-01'), 'يناير');
      expect(formatPeriodMonth('$thisYear-03'), 'مارس');
    });

    test('...and keeps the year when the month is NOT in it', () {
      // The association drops the year because everything on the screen belongs
      // to the year being worked — true today, false the first January that
      // settles a December. A bare «ديسمبر» on a receipt written in the next
      // year is ambiguous between two months twelve apart, on the one document
      // a member keeps.
      final int lastYear = DateTime.now().year - 1;
      expect(formatPeriodMonth('$lastYear-12'), 'ديسمبر $lastYear');
    });

    test('an unreadable period is passed through, not guessed at', () {
      expect(formatPeriodMonth(null), '');
      expect(formatPeriodMonth('2026-13'), '2026-13');
      expect(formatPeriodMonth('nonsense'), 'nonsense');
    });

    test('an empty or unparseable date is passed through, never invented', () {
      expect(formatDate(null), '');
      expect(formatDate(''), '');
      // Not a crash and not "today": a value the app cannot read is shown as it
      // arrived, so whoever looks at it can see what is wrong with it.
      expect(formatDate('not a date'), 'not a date');
    });
  });

  testWidgets('the CALENDAR reads in Arabic with Latin digits too', (
    WidgetTester tester,
  ) async {
    // ⚠ THE TEST THAT MATTERS, and the one the group above cannot do.
    //
    // A bare unit test never loads GlobalMaterialLocalizations, so intl keeps
    // its own `ar` data and prints Latin digits — which is precisely why the
    // bug was invisible in tests and obvious on a phone. Loading the delegates
    // installs Flutter's `ar` date symbols, whose ZERODIGIT is ٠, and from that
    // one field every digit intl prints for the locale follows: the calendar
    // AND `formatDate`.
    //
    // So this pumps the REAL delegate list the app ships and asks the Material
    // localizations directly. It also settles a rule nobody should have to take
    // on trust — that the first delegate for a type is the one Flutter uses —
    // by asserting the outcome rather than the ordering.
    late MaterialLocalizations material;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            material = MaterialLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final DateTime d = DateTime(2026, 2, 10);
    expect(material.formatYear(d), '2026');
    expect(material.formatMonthYear(d), 'فبراير 2026');
    expect(material.formatFullDate(d), contains('10 فبراير 2026'));
    // The words stay Arabic. The alternative that was briefly in place —
    // overriding the picker's locale to `en` — bought the digits by making the
    // whole calendar English, which is the opposite of what is wanted.
    expect(material.okButtonLabel, isNot('OK'));

    // And our own formatter, now that Flutter's symbols are installed: this is
    // the combination that was impossible before.
    expect(formatDate('2026-02-10'), '10 فبراير 2026');
  });

  test('typed Arabic-Indic digits are still folded to ASCII on the way in', () {
    // The DISPLAY being Latin changes nothing about the keyboard. Every numeric
    // field still needs this, and it is listed first on each of them because a
    // FilteringTextInputFormatter placed before it does not merely reject the
    // digits — it drops each keystroke and the box never fills.
    final ArabicDigitsFormatter formatter = ArabicDigitsFormatter();
    final TextEditingValue out = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '٥٠٠٫٥'),
    );
    expect(out.text, '500.5');
  });
}
