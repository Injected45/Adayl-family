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
    required this.method,
    required this.status,
    required this.spentAt,
    this.category = '',
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

  /// One of [ExpenseCategoryWire.all], and EMPTY for a member voucher — the man
  /// is the heading, so asking which category besides asks the same question
  /// twice.
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
