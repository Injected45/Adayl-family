/// Finance view models. Money stays an exact decimal string.
library;

import '../../../core/domain/wire_values.dart';

String _string(Object? value) => value == null ? '' : value.toString();
int _int(Object? value) => value is num ? value.toInt() : 0;

/// A key that may be ABSENT because the database predates it.
///
/// Not [_string], which turns a missing key into `''` — and an empty string is
/// not a money value: `double.tryParse('')` is null and the figure would render
/// as though it had failed to load. The fallback says what the older database
/// meant instead.
String _stringOr(Object? value, String fallback) =>
    value == null ? fallback : value.toString();

class PaymentAllocationView {
  const PaymentAllocationView({
    required this.receivableId,
    required this.period,
    required this.amount,
  });

  final int receivableId;
  final String period;
  final String amount;

  factory PaymentAllocationView.fromJson(Map<String, dynamic> json) =>
      PaymentAllocationView(
        receivableId: _int(json['receivableId']),
        period: _string(json['period']),
        amount: _string(json['amount']),
      );
}

class PaymentView {
  const PaymentView({
    required this.id,
    required this.receiptNo,
    required this.adeelId,
    this.adeelName = '',
    this.adeelCode = '',
    required this.amount,
    required this.method,
    required this.reference,
    required this.receiver,
    required this.notes,
    required this.bankName,
    required this.bankAccountNo,
    required this.bankAccountName,
    required this.status,
    required this.paidAt,
    required this.allocations,
  });

  final int id;
  final String receiptNo;
  final int adeelId;

  /// WHO paid, on the receipt itself.
  ///
  /// v_payments has sent these two all along; the model simply did not read
  /// them. The operations list is one card per receipt, and a receipt number
  /// with the months it settled answers "what was paid" without ever answering
  /// "by whom" — which on a screen that lists every collection in the
  /// association is the first question anyone has of it.
  ///
  /// Defaulted rather than required: the captured wire fixtures in
  /// test/fixtures/ predate this being parsed, and a hard cast would fail
  /// contract parsing on rows that are otherwise unchanged.
  final String adeelName;
  final String adeelCode;
  final String amount;
  final String method;
  final String? reference;
  final String? receiver;
  final String? notes;

  /// The association account this transfer landed in, AS IT STOOD when the
  /// payment was taken — a snapshot column on `payments`, not a join to current
  /// settings. Reprinting a receipt after the association changes bank must
  /// still name the account the money actually went to. Empty for cash.
  final String bankName;
  final String bankAccountNo;
  final String bankAccountName;
  final String status;
  final String paidAt;
  final List<PaymentAllocationView> allocations;

  factory PaymentView.fromJson(Map<String, dynamic> json) => PaymentView(
    id: _int(json['id']),
    receiptNo: _string(json['receiptNo']),
    adeelId: _int(json['adeelId']),
    adeelName: _string(json['adeelName']),
    adeelCode: _string(json['adeelCode']),
    amount: _string(json['amount']),
    method: _string(json['method']),
    reference: json['reference'] as String?,
    receiver: json['receiver'] as String?,
    notes: json['notes'] as String?,
    // _string, not a cast: the captured wire fixtures in test/fixtures/ predate
    // these two columns, and a hard cast would fail contract parsing on rows
    // that are otherwise unchanged.
    bankName: _string(json['bankName']),
    bankAccountNo: _string(json['bankAccountNo']),
    bankAccountName: _string(json['bankAccountName']),
    status: _string(json['status']),
    paidAt: _string(json['paidAt']),
    allocations: (json['allocations'] as List<dynamic>? ?? <dynamic>[])
        .map(
          (dynamic e) => PaymentAllocationView.fromJson(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList(),
  );
}

class CashSummaryView {
  const CashSummaryView({
    required this.total,
    required this.cash,
    required this.transfer,
    required this.today,
    required this.month,
    required this.year,
    this.outstanding = '0.00',
    this.disbursed = '0.00',
    this.heldForMembers = '0.00',
    String? balance,
  }) : balance = balance ?? total;

  final String total;
  final String cash;
  final String transfer;
  final String today;
  final String month;
  final String year;

  /// Every subscriber's unpaid balance, summed — the half of the treasury's
  /// position that has NOT arrived.
  ///
  /// Replaced "collected this year", which in an association's first year is
  /// the same figure as the total collected: two tiles showing one number.
  final String outstanding;

  /// Money that LEFT the treasury, and what is therefore actually held.
  ///
  /// [total] is everything ever COLLECTED and keeps that meaning. It was also
  /// what the screen called «رصيد الجمعية», which was true only while money
  /// could not leave: the moment disbursement exists, collected-to-date and
  /// held-today are different numbers, and calling the first one the balance
  /// overstates the fund by everything it has ever paid out.
  final String disbursed;
  final String balance;

  /// عهد المشتركين — cash in the box that the association does NOT own.
  ///
  /// A member may pay a year ahead. The money is real and [total] counts it,
  /// but until the month it covers is billed it is owed back to him, and
  /// [balance] therefore excludes it: the figure under «رصيد الجمعية» is what
  /// may actually be SPENT. register_disbursement refuses anything above the
  /// same number, so the screen cannot promise what the server will refuse.
  ///
  /// Defaults to zero for a database that predates the column — which reads as
  /// "nothing is held", the state every project was in before prepayment
  /// existed, rather than as a figure that failed to load.
  final String heldForMembers;

  factory CashSummaryView.fromJson(Map<String, dynamic> json) =>
      CashSummaryView(
        total: _string(json['total']),
        cash: _string(json['cash']),
        transfer: _string(json['transfer']),
        today: _string(json['today']),
        month: _string(json['month']),
        year: _string(json['year']),
        outstanding: _stringOr(json['outstanding'], '0.00'),
        disbursed: _stringOr(json['disbursed'], '0.00'),
        heldForMembers: _stringOr(json['heldForMembers'], '0.00'),
        // Falls back to `total`, which is what the balance WAS before money
        // could leave. A database that predates disbursement therefore reads
        // exactly as it used to, rather than showing every association a zero.
        balance: _stringOr(json['balance'], _string(json['total'])),
      );
}

class CashMovementView {
  const CashMovementView({
    required this.id,
    required this.receiptNo,
    required this.adeelName,
    required this.adeelId,
    required this.adeelCode,
    required this.amount,
    required this.method,
    required this.movementType,
    required this.status,
    required this.occurredAt,
  });

  final int id;
  final String receiptNo;
  final String adeelName;

  /// Grouped BY this, never by the name. The register has no natural key — two
  /// men may be entered under the same spelling — and folding them into one
  /// row on the treasury screen would merge two people's money.
  final int adeelId;
  final String adeelCode;
  final String amount;
  final String method;
  final String movementType;
  final String status;
  final String occurredAt;

  factory CashMovementView.fromJson(Map<String, dynamic> json) =>
      CashMovementView(
        id: _int(json['id']),
        receiptNo: _string(json['receiptNo']),
        adeelName: _string(json['adeelName']),
        adeelId: _int(json['adeelId']),
        adeelCode: _string(json['adeelCode']),
        amount: _string(json['amount']),
        method: _string(json['method']),
        movementType: _string(json['movementType']),
        status: _string(json['status']),
        occurredAt: _string(json['occurredAt']),
      );
}

class GenerateResultView {
  const GenerateResultView({
    required this.period,
    required this.created,
    required this.skipped,
  });

  final String period;
  final int created;
  final int skipped;

  factory GenerateResultView.fromJson(Map<String, dynamic> json) =>
      GenerateResultView(
        period: _string(json['period']),
        created: _int(json['created']),
        skipped: _int(json['skipped']),
      );
}

/// One month the dashboard's close-month button may offer.
///
/// `label` comes from the server, not from a client-side month name. There is
/// exactly one spelling of each Arabic month in this system and it lives in
/// `period_label()`, so that the receivables list, this picker and the audit
/// trail can never disagree about what يوليو is called.
class ClosablePeriod {
  const ClosablePeriod({
    required this.period,
    required this.label,
    required this.closed,
    required this.selectable,
  });

  /// `YYYY-MM`, the value generate_period() takes.
  final String period;
  final String label;

  /// True once someone has closed this month. Rule 15a then REFUSES it: a month
  /// is closed once, and re-running would report "0 created" without saying
  /// whether that meant "already done" or "nothing to do".
  ///
  /// Read from closed_periods, not from the receivables. A month that billed
  /// nobody is still closed, and inferring closure from charges would leave it
  /// open forever — blocking every month after it under rule 15b.
  final bool closed;

  /// True for the EARLIEST month not yet closed, and only that one. Rule 15b
  /// accepts no other, so this is the single tappable row in the picker.
  ///
  /// Computed by the database because it IS rule 15b. Working it out in Dart
  /// would be a second implementation of a money rule, free to disagree with the
  /// one that actually decides.
  final bool selectable;

  factory ClosablePeriod.fromJson(Map<String, dynamic> json) => ClosablePeriod(
    period: _string(json['period']),
    label: _string(json['label']),
    closed: json['closed'] == true,
    selectable: json['selectable'] == true,
  );
}

/// One voucher: money that LEFT the treasury.
///
/// The mirror of [PaymentView], and the differences are the interesting part.
/// A payment is always FOR an عديل and is allocated across his months; a
/// disbursement is for a heading and may go to anybody — a member, a landlord,
/// a hospital — so it carries a category and an optional register link instead
/// of allocations.
///
/// ⚠ A disbursement to an عديل is NOT a credit against his subscription. It
///   never touches his receivables, his wallet or his statement. The link is
///   there so "how much aid went to this man" can be answered, and treating it
///   as a payment would let the association's charity cancel its own dues.
class DisbursementView {
  const DisbursementView({
    required this.id,
    required this.voucherNo,
    required this.amount,
    required this.kind,
    required this.category,
    required this.method,
    required this.status,
    required this.spentAt,
    this.payeeName = '',
    this.payeeAdeelId,
    this.payeeCode = '',
    this.reference = '',
    this.bankName = '',
    this.bankAccountNo = '',
    this.bankAccountName = '',
    this.handedBy = '',
    this.note = '',
  });

  final int id;

  /// EXP-000001, generated by the database beside PAY-000001.
  final String voucherNo;
  final String amount;

  /// [DisbursementKindWire.member] or [DisbursementKindWire.collective], and
  /// the only field to branch on. The two below are each empty for one kind,
  /// which `ck_disb_shape` guarantees — so reading `payeeName` to decide would
  /// be inferring the shape from a symptom instead of asking.
  final String kind;

  /// One of [ExpenseCategoryWire.all]. Present on BOTH kinds: the payee says
  /// WHO was paid and this says WHAT FOR, which the register of names cannot
  /// answer. Which five of the six are legal depends on [kind].
  final String category;

  /// A SNAPSHOT of the register row, and EMPTY for a collective voucher:
  /// nobody receives فطور رمضان the way a member receives aid. A snapshot even
  /// though [payeeAdeelId] sits beside it, because a voucher reprinted after
  /// the man is renamed must still say who was actually paid.
  final String payeeName;
  final int? payeeAdeelId;
  final String payeeCode;

  bool get isForMember => kind == DisbursementKindWire.member;

  /// What to put on the voucher card where a name would go. One or the other is
  /// always present, so the card never has to render an empty line.
  String get subject => isForMember ? payeeName : category;

  final String method;
  final String reference;

  /// Where the money was SENT, for a transfer. Empty for cash.
  final String bankName;
  final String bankAccountNo;
  final String bankAccountName;

  /// Who physically handed it over — a name, not a user id: the man carrying
  /// cash to a hospital is not necessarily the one holding the phone.
  final String handedBy;
  final String note;

  final String status;
  final String spentAt;

  bool get cancelled => status == ReceivableStatusWire.cancelled;

  factory DisbursementView.fromJson(Map<String, dynamic> json) =>
      DisbursementView(
        id: _int(json['id']),
        voucherNo: _string(json['voucherNo']),
        amount: _string(json['amount']),
        kind: _string(json['kind']),
        category: _string(json['category']),
        payeeName: _string(json['payeeName']),
        payeeAdeelId: (json['payeeAdeelId'] as num?)?.toInt(),
        payeeCode: _string(json['payeeCode']),
        method: _string(json['method']),
        reference: _string(json['reference']),
        bankName: _string(json['bankName']),
        bankAccountNo: _string(json['bankAccountNo']),
        bankAccountName: _string(json['bankAccountName']),
        handedBy: _string(json['handedBy']),
        note: _string(json['note']),
        status: _string(json['status']),
        spentAt: _string(json['spentAt']),
      );
}

/// What one heading has cost. Every heading appears, including the ones nothing
/// has been spent on — a report that omits a zero reads as one that forgot it.
class ExpenseByCategory {
  const ExpenseByCategory({
    required this.category,
    required this.total,
    required this.count,
  });

  final String category;
  final String total;
  final int count;

  bool get isEmpty => (double.tryParse(total) ?? 0) == 0;

  factory ExpenseByCategory.fromJson(Map<String, dynamic> json) =>
      ExpenseByCategory(
        category: _string(json['category']),
        total: _string(json['total']),
        count: _int(json['count']),
      );
}

/// One line of a member's aid ledger: a voucher, and the total so far.
///
/// [runningTotal] is computed by a WINDOW FUNCTION in `api_adeel_aid`, never
/// here. Money crosses the wire as text precisely so that nothing on the client
/// adds it up, and a running total accumulated in Dart would be the one figure
/// on the screen computed in binary floating point.
///
/// A REVERSED voucher keeps its line and carries the SAME running total as the
/// line above it — rule 9 says history stays visible, and a cancelled voucher
/// moved no money. So the column can repeat, and a reader seeing two identical
/// figures in a row is looking at a reversal, not a bug.
class AidLedgerEntry {
  const AidLedgerEntry({required this.voucher, required this.runningTotal});

  final DisbursementView voucher;
  final String runningTotal;

  factory AidLedgerEntry.fromJson(Map<String, dynamic> json) => AidLedgerEntry(
    voucher: DisbursementView.fromJson(json),
    runningTotal: _string(json['runningTotal']),
  );

  /// Everything a search box may match, lower-cased once.
  ///
  /// Built from the row rather than searched field-by-field at the call site,
  /// so a field added to the voucher is searchable by editing one place — and
  /// so «فرح» typed into the box finds the wedding whether it is the heading,
  /// the note, or part of who handed the money over.
  String get haystack => <String>[
    voucher.voucherNo,
    voucher.category,
    voucher.note,
    voucher.handedBy,
    voucher.method,
    voucher.amount,
    voucher.spentAt,
  ].join(' ').toLowerCase();
}

/// One year of what the association gave one man.
class AidByYear {
  const AidByYear({
    required this.year,
    required this.total,
    required this.count,
  });

  /// `2026`. A string because it is a label, never arithmetic.
  final String year;
  final String total;
  final int count;

  factory AidByYear.fromJson(Map<String, dynamic> json) => AidByYear(
    year: _string(json['year']),
    total: _string(json['total']),
    count: _int(json['count']),
  );
}

/// What the association has GIVEN one عديل — the counterpart of his statement,
/// and deliberately not part of it.
///
/// ⚠ AID IS NOT A CREDIT AGAINST HIS SUBSCRIPTION. الجمعية خيرية: a man given
/// something for a bereavement still owes that month's fee, and nothing on this
/// object may ever be subtracted from anything on [Statement]. The separation is
/// structural rather than a matter of which screen shows what — a voucher writes
/// no receivable, no payment and no allocation, and the statement merges exactly
/// those two tables — but it is written here too, because the place this rule
/// would be broken is a screen that puts the two figures in one column.
///
/// [byCategory] carries ONLY the occasions he actually received something under,
/// unlike the association-wide `v_expense_by_category`, which lists every
/// heading including the untouched ones. The difference is the question: "we
/// spent nothing on فرح this year" is an answer about the association, and "he
/// was never given anything for a wedding" is not an answer he is missing.
///
/// [vouchers] includes CANCELLED ones so the screen can strike them through,
/// exactly as a cancelled receipt is shown. They are excluded from [total].
class AdeelAid {
  const AdeelAid({
    required this.adeelId,
    required this.adeelCode,
    required this.adeelName,
    required this.total,
    required this.count,
    required this.firstAt,
    required this.lastAt,
    required this.byCategory,
    required this.byYear,
    required this.ledger,
  });

  final int adeelId;

  /// Empty when the caller may not read this man's row — which is what an عديل
  /// gets if he asks about somebody else. The screen shows nothing rather than
  /// a refusal, so the id he guessed is not confirmed to exist.
  final String adeelCode;
  final String adeelName;

  /// Lifetime, cancelled vouchers excluded. `'0.00'` when he has received
  /// nothing — a real zero, never an empty string, so the screen has one shape.
  final String total;
  final int count;

  /// `YYYY-MM-DD`, empty when he has received nothing.
  final String firstAt;
  final String lastAt;

  final List<ExpenseByCategory> byCategory;
  final List<AidByYear> byYear;

  /// OLDEST FIRST, because that is the only order in which a running total
  /// means anything: read the other way it accumulates backwards and the last
  /// line would show the first voucher's amount as though it were the sum.
  final List<AidLedgerEntry> ledger;

  bool get isEmpty => count == 0;

  factory AdeelAid.fromJson(Map<String, dynamic> json) => AdeelAid(
    adeelId: _int(json['adeelId']),
    adeelCode: _string(json['adeelCode']),
    adeelName: _string(json['adeelName']),
    total: _string(json['total']),
    count: _int(json['count']),
    firstAt: _string(json['firstAt']),
    lastAt: _string(json['lastAt']),
    byCategory: <ExpenseByCategory>[
      for (final dynamic e
          in (json['byCategory'] as List<dynamic>? ?? const <dynamic>[]))
        ExpenseByCategory.fromJson(e as Map<String, dynamic>),
    ],
    byYear: <AidByYear>[
      for (final dynamic e
          in (json['byYear'] as List<dynamic>? ?? const <dynamic>[]))
        AidByYear.fromJson(e as Map<String, dynamic>),
    ],
    ledger: <AidLedgerEntry>[
      for (final dynamic e
          in (json['vouchers'] as List<dynamic>? ?? const <dynamic>[]))
        AidLedgerEntry.fromJson(e as Map<String, dynamic>),
    ],
  );
}

/// الصرف الجماعي — what the association spent on everybody at once.
///
/// ── WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT ───────────────────────────
/// فطور رمضان and its like: money that belongs to no member in particular. A
/// collective voucher carries no payee at all — `ck_disb_shape` refuses one —
/// so this list names nobody and cannot be made to.
///
/// ⚠ AN EARLIER DRAFT SHOWED OTHER MEMBERS' AID, BY NAME. The association
///   looked at it and chose otherwise, and the choice is the better one: a row
///   saying a named man received إعانة for a bereavement is the most private
///   fact this system holds, while a row saying 400 went on فطور رمضان answers
///   the question a member actually has — «أين يذهب مالي» — and exposes no one.
///
/// ⚠ AND THE SCOPE IS A POLICY, NOT A FILTER HERE.
///   `read_collective_disbursements` is `payee_adeel_id IS NULL AND
///   my_adeel_id() IS NOT NULL`. Drop it and this screen empties itself;
///   nothing in Dart decides who may read what, and nothing in Dart could be
///   trusted to.
///
/// ⚠ CANCELLED VOUCHERS ARE ABSENT. A reversal on a communal expense is an
///   administrative correction and belongs in the audit trail, not on a screen
///   a member opens to see where the fund went.
class AidOthers {
  const AidOthers({
    required this.total,
    required this.count,
    required this.byCategory,
    required this.vouchers,
  });

  /// Lifetime collective spending, cancelled excluded.
  final String total;
  final int count;

  /// By occasion, largest first. «على ماذا أُنفق» is the question this screen
  /// is opened with, and a communal expense has no man to group under — the
  /// وجه is the only grouping it has.
  final List<ExpenseByCategory> byCategory;

  /// Newest first.
  final List<AidLedgerEntry> vouchers;

  bool get isEmpty => count == 0;

  factory AidOthers.fromJson(Map<String, dynamic> json) => AidOthers(
    total: _string(json['total']),
    count: _int(json['count']),
    byCategory: <ExpenseByCategory>[
      for (final dynamic e
          in (json['byCategory'] as List<dynamic>? ?? const <dynamic>[]))
        ExpenseByCategory.fromJson((e as Map).cast<String, dynamic>()),
    ],
    vouchers: <AidLedgerEntry>[
      for (final dynamic e
          in (json['vouchers'] as List<dynamic>? ?? const <dynamic>[]))
        AidLedgerEntry.fromJson((e as Map).cast<String, dynamic>()),
    ],
  );
}

/// ما دفعه المشترك وما استلمه، وموقع الجمعية من ذلك.
///
/// ── WHY THIS EXISTS, AND THE RULE IT WAS BUILT AGAINST ──────────────────────
/// The association asked a member to be shown what he has paid, what he has
/// received, and the difference — which is precisely the layout the aid ledger
/// was kept SEPARATE from his statement to avoid. «الجمعية خيرية»: aid is never
/// deducted from a subscription, and a screen that subtracts one from the other
/// invites the reading that a man who has taken more than he gave is square, or
/// that one who has taken less is owed.
///
/// ⚠ SO THE SUBTRACTION IS NAMED, NOT AVOIDED. In a mutual fund the surplus of
///   the men nothing happened to is exactly what covers the man something
///   happened to — so a positive difference is «الجمعية أعطتك أكثر مما دفعت»
///   and a negative one is «فائض تكافلك», what he contributed to others. Neither
///   is a profit and neither is a debt, and the wording is what carries that.
///   See AidValueScreen, where the labels live.
///
/// ⚠ AND NOTHING HERE IS SUBTRACTED IN DART. Every figure arrives summed by
///   Postgres, as text — see api_member_value.
class MemberValue {
  const MemberValue({
    required this.paid,
    required this.received,
    required this.collected,
    required this.toMembers,
    required this.helped,
    required this.members,
    required this.largest,
  });

  /// What HE has paid — receipts, not what he was billed.
  final String paid;

  /// What the association has given HIM.
  final String received;

  /// What the fund has collected, and how much of it has gone back to named
  /// members. Collective spending is excluded from [toMembers] on purpose: a
  /// shared meal comes back to everybody at once and answers a different
  /// question.
  final String collected;
  final String toMembers;

  /// How many men the fund has stood behind, out of how many pay into it.
  final int helped;
  final int members;

  /// ⚠ THE INSURANCE FIGURE. The largest single voucher the association has
  ///   written to one man — what a member is actually buying, and the one
  ///   number no average can say.
  final String largest;

  // ⚠ EVERY AMOUNT DEFAULTS TO '0.00', NEVER TO AN EMPTY STRING. A blank in a
  //   money column reads as a figure that failed to load, and on the one screen
  //   whose entire purpose is figures that is the worst possible ambiguity —
  //   the reader cannot tell «nothing yet» from «something went wrong».
  factory MemberValue.fromJson(Map<String, dynamic> json) => MemberValue(
    paid: _stringOr(json['paid'], '0.00'),
    received: _stringOr(json['received'], '0.00'),
    collected: _stringOr(json['collected'], '0.00'),
    toMembers: _stringOr(json['toMembers'], '0.00'),
    helped: _int(json['helped']),
    members: _int(json['members']),
    largest: _stringOr(json['largest'], '0.00'),
  );
}
