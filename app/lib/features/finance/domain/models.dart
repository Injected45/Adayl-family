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
    required this.familyId,
    required this.amount,
    required this.method,
    required this.reference,
    required this.receiver,
    required this.notes,
    required this.status,
    required this.paidAt,
    required this.allocations,
  });

  final int id;
  final String receiptNo;
  final int familyId;
  final String amount;
  final String method;
  final String? reference;
  final String? receiver;
  final String? notes;
  final String status;
  final String paidAt;
  final List<PaymentAllocationView> allocations;

  factory PaymentView.fromJson(Map<String, dynamic> json) => PaymentView(
    id: _int(json['id']),
    receiptNo: _string(json['receiptNo']),
    familyId: _int(json['familyId']),
    amount: _string(json['amount']),
    method: _string(json['method']),
    reference: json['reference'] as String?,
    receiver: json['receiver'] as String?,
    notes: json['notes'] as String?,
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
    required this.familyName,
    required this.amount,
    required this.method,
    required this.movementType,
    required this.status,
    required this.occurredAt,
  });

  final int id;
  final String receiptNo;
  final String familyName;
  final String amount;
  final String method;
  final String movementType;
  final String status;
  final String occurredAt;

  factory CashMovementView.fromJson(Map<String, dynamic> json) =>
      CashMovementView(
        id: _int(json['id']),
        receiptNo: _string(json['receiptNo']),
        familyName: _string(json['familyName']),
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
