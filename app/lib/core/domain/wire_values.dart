/// The Arabic values the API and database actually store.
///
/// These are NOT display strings — they are enum values that travel over the
/// wire, chosen to match `index.html` exactly so the migration could import the
/// association's existing records untouched.
///
/// This is the ONLY file allowed to contain them. Risk R7 in the migration plan
/// is that a spelling change in one screen silently breaks a comparison in
/// another; keeping every literal here means such a change is a one-line edit
/// with a compiler to catch the rest. `tool/rtl_lint.dart` exempts this file
/// and flags Arabic literals anywhere else in widget code.
///
/// Anything the user READS still comes from `lib/l10n/app_ar.arb`. Where a wire
/// value also happens to be shown — a receivable's status, say — the API sends
/// a display label alongside it rather than the screen reusing the enum.
library;

abstract final class ReceivableStatusWire {
  static const String unpaid = 'غير مسدد';
  static const String partiallyPaid = 'مسدد جزئياً';
  static const String fullyPaid = 'مسدد بالكامل';
  static const String cancelled = 'ملغي';
}

abstract final class MembershipStatusWire {
  static const String active = 'نشط';
  static const String suspended = 'موقوف';
  static const String deceased = 'متوفى';
}

abstract final class PaymentMethodWire {
  static const String cash = 'نقداً';
  static const String bankTransfer = 'تحويل مصرفي';
}

/// What the association spent the money ON — the `expense_category` enum.
///
/// A fixed list, and these nine strings are the database's own labels: the
/// voucher stores the enum, so a heading here that does not match the enum
/// exactly is a 22P02 at insert time rather than a mislabelled row.
///
/// [all] is the order the picker offers, which is the order they were declared
/// in — general aid first, the specific occasions after it, the association's
/// own running costs last, and `other` at the end where an escape hatch
/// belongs.
abstract final class ExpenseCategoryWire {
  static const String socialAid = 'إعانة اجتماعية';
  static const String condolence = 'عزاء ووفاة';
  static const String wedding = 'مناسبة زواج';
  static const String medical = 'علاج ومرض';
  static const String administrative = 'مصاريف إدارية';
  static const String rentAndUtilities = 'إيجار وخدمات';
  static const String hospitality = 'ضيافة واجتماعات';
  static const String bankFees = 'رسوم مصرفية';
  static const String other = 'أخرى';

  static const List<String> all = <String>[
    socialAid,
    condolence,
    wedding,
    medical,
    administrative,
    rentAndUtilities,
    hospitality,
    bankFees,
    other,
  ];
}

/// The two posts, as `v_officials` emits them.
///
/// ASCII, unlike every other enum here, and that is the whole trap: the
/// Arabic-literal lint had nothing to object to, so the officials screen
/// printed `treasurer` and `financeManager` straight onto an Arabic-only page
/// and nothing failed. A wire value is a wire value whatever alphabet it is
/// written in — it belongs here, and the screen translates it.
abstract final class OfficialRoleWire {
  static const String treasurer = 'treasurer';
  static const String financeManager = 'financeManager';
}

// MemberRelationWire ('أب' / 'ابن') is GONE. It labelled a person's place inside
// a household, and the association stopped billing households: every عديل is
// billed in his own right, so there is no relation left to state. Removing it
// rather than leaving it unused is deliberate — an unused wire enum is an
// invitation to reintroduce the two-tier model by accident.

abstract final class MemberDefaults {
  /// Every عديل defaults to active. A stored value, not display text.
  static const String status = MembershipStatusWire.active;
}

abstract final class PurgeWire {
  /// The phrase `purge_financial_data(p_confirm)` compares against before it
  /// truncates anything, byte for byte.
  ///
  /// A wire value, not a caption: the settings dialog shows it as the text to
  /// copy, but what makes it belong here is that the database holds the same
  /// literal. Changing the wording on the screen alone would leave an admin
  /// typing exactly what he was asked for and being refused.
  static const String confirmPhrase = 'مسح نهائي';

  /// What `purge_all_data(p_confirm)` demands — the wider purge that takes the
  /// register of عدايل with it.
  ///
  /// Deliberately NOT a superstring of [confirmPhrase]: the two phrases are
  /// compared with `<>`, so an admin who typed the financial phrase into the
  /// wrong dialog is refused rather than emptying the register. That property
  /// is the reason there are two functions instead of one with a flag.
  static const String confirmPhraseAll = 'مسح كل البيانات';
}

abstract final class ArabicPunctuation {
  /// U+060C, the Arabic comma. Joining a list with a Latin ',' looks wrong in
  /// Arabic text and is what the prototype uses throughout.
  static const String listSeparator = '، ';
}
