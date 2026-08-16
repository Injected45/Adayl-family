/// Finance view models. Money stays an exact decimal string.
library;

String _string(Object? value) => value == null ? '' : value.toString();
int _int(Object? value) => value is num ? value.toInt() : 0;

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
  });

  final String total;
  final String cash;
  final String transfer;
  final String today;
  final String month;
  final String year;

  factory CashSummaryView.fromJson(Map<String, dynamic> json) =>
      CashSummaryView(
        total: _string(json['total']),
        cash: _string(json['cash']),
        transfer: _string(json['transfer']),
        today: _string(json['today']),
        month: _string(json['month']),
        year: _string(json['year']),
      );
}

class CashMovementView {
  const CashMovementView({
    required this.id,
    required this.receiptNo,
    required this.adeelName,
    required this.amount,
    required this.method,
    required this.movementType,
    required this.status,
    required this.occurredAt,
  });

  final int id;
  final String receiptNo;
  final String adeelName;
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
