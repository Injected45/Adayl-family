/// Read-side view models.
///
/// Money is carried as the exact decimal STRING the server sent and is only
/// ever formatted for display — never parsed and re-summed, because every
/// total on every screen is computed server-side against the database.
library;

String _string(Object? value) => value == null ? '' : value.toString();
int _int(Object? value) => value is num ? value.toInt() : 0;

class AssociationSettingsView {
  const AssociationSettingsView({
    required this.associationName,
    required this.currency,
    required this.memberFee,
  });

  final String associationName;
  final String currency;

  /// One rate for everyone. There were two — a father's and a son's — until the
  /// association stopped billing households through their head.
  final String memberFee;

  factory AssociationSettingsView.fromJson(Map<String, dynamic> json) =>
      AssociationSettingsView(
        associationName: _string(json['associationName']),
        currency: _string(json['currency']),
        memberFee: _string(json['memberFee']),
      );
}

class Official {
  const Official({
    required this.role,
    required this.name,
    required this.phone,
  });

  final String role;
  final String name;
  final String phone;

  factory Official.fromJson(Map<String, dynamic> json) => Official(
    role: _string(json['role']),
    name: _string(json['name']),
    phone: _string(json['phone']),
  );
}

/// One row of the register.
///
/// Replaces both `FamilyListItem` and `MemberListItem`. They described a
/// household and a person inside it; there is only one kind of thing now.
class AdeelListItem {
  const AdeelListItem({
    required this.id,
    required this.adeelCode,
    required this.fullName,
    required this.phone,
    required this.age,
    required this.membershipStatus,
    required this.debt,
    required this.issued,
    required this.monthlyExpected,
  });

  final int id;
  final String adeelCode;
  final String fullName;
  final String phone;
  final int? age;

  /// نشط / موقوف / متوفى — the only thing that decides whether he is billed.
  final String membershipStatus;
  final String debt;

  /// Everything ever charged to him, cancelled receivables excluded.
  final String issued;
  final String monthlyExpected;

  bool get hasDebt => (double.tryParse(debt) ?? 0) > 0;

  factory AdeelListItem.fromJson(Map<String, dynamic> json) => AdeelListItem(
    id: _int(json['id']),
    adeelCode: _string(json['adeelCode']),
    fullName: _string(json['fullName']),
    phone: _string(json['phone']),
    age: json['age'] is num ? (json['age'] as num).toInt() : null,
    membershipStatus: _string(json['membershipStatus']),
    debt: _string(json['debt']),
    issued: _string(json['issued']),
    monthlyExpected: _string(json['monthlyExpected']),
  );
}

/// The full record, as the detail screen and the portal read it.
///
/// `EligibilityKey` used to live here — مستحق / قريب من السن / غير مستحق /
/// موقوف, derived from a son's age against the eligibility age. There is no age
/// gate, so there is no eligibility: `membershipStatus` carries the whole
/// answer.
class AdeelView {
  const AdeelView({
    required this.id,
    required this.adeelCode,
    required this.fullName,
    required this.phone,
    required this.dob,
    required this.age,
    required this.notes,
    required this.registeredAt,
    required this.membershipStatus,
    required this.monthlyExpected,
    required this.debt,
    required this.paid,
    required this.issued,
  });

  final int id;
  final String adeelCode;
  final String fullName;
  final String phone;
  final String dob;
  final int? age;
  final String notes;
  final String registeredAt;
  final String membershipStatus;
  final String monthlyExpected;
  final String debt;
  final String paid;
  final String issued;

  bool get hasDebt => (double.tryParse(debt) ?? 0) > 0;

  factory AdeelView.fromJson(Map<String, dynamic> json) => AdeelView(
    id: _int(json['id']),
    adeelCode: _string(json['adeelCode']),
    fullName: _string(json['fullName']),
    phone: _string(json['phone']),
    dob: _string(json['dob']),
    age: json['age'] is num ? (json['age'] as num).toInt() : null,
    notes: _string(json['notes']),
    registeredAt: _string(json['registeredAt']),
    membershipStatus: _string(json['membershipStatus']),
    monthlyExpected: _string(json['monthlyExpected']),
    debt: _string(json['debt']),
    paid: _string(json['paid']),
    issued: _string(json['issued']),
  );
}

/// `api_adeel_detail` — his record, his KPIs, his dues and his receipts.
class AdeelDetail {
  const AdeelDetail({
    required this.adeel,
    required this.monthlyExpected,
    required this.issued,
    required this.debt,
    required this.paid,
    required this.openPeriods,
    required this.receivables,
  });

  final AdeelView adeel;
  final String monthlyExpected;
  final String issued;
  final String debt;
  final String paid;
  final int openPeriods;
  final List<ReceivableItem> receivables;

  factory AdeelDetail.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> kpis = (json['kpis'] as Map)
        .cast<String, dynamic>();
    return AdeelDetail(
      adeel: AdeelView.fromJson((json['adeel'] as Map).cast<String, dynamic>()),
      monthlyExpected: _string(kpis['monthlyExpected']),
      issued: _string(kpis['issued']),
      debt: _string(kpis['debt']),
      paid: _string(kpis['paid']),
      openPeriods: _int(kpis['openPeriods']),
      receivables: (json['receivables'] as List<dynamic>? ?? <dynamic>[])
          .map(
            (dynamic e) =>
                ReceivableItem.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
    );
  }
}

class ReceivableItem {
  const ReceivableItem({
    required this.id,
    required this.adeelId,
    required this.adeelName,
    required this.adeelCode,
    required this.period,
    required this.periodLabel,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
  });

  final int id;
  final int adeelId;

  /// Snapshotted onto the receivable when it was raised, so a receipt printed
  /// years later still shows the name as it stood then.
  final String adeelName;

  final String adeelCode;
  final String period;
  final String periodLabel;
  final String total;
  final String paid;
  final String balance;
  final String status;

  factory ReceivableItem.fromJson(Map<String, dynamic> json) => ReceivableItem(
    id: _int(json['id']),
    adeelId: _int(json['adeelId']),
    adeelName: _string(json['adeelName']),
    adeelCode: _string(json['adeelCode']),
    period: _string(json['period']),
    periodLabel: _string(json['periodLabel']),
    total: _string(json['total']),
    paid: _string(json['paid']),
    balance: _string(json['balance']),
    status: _string(json['status']),
  );
}

class ReceivablesPage {
  const ReceivablesPage({required this.items, required this.summary});

  final List<ReceivableItem> items;
  final ReceivablesSummary summary;
}

class ReceivablesSummary {
  const ReceivablesSummary({
    required this.issued,
    required this.collected,
    required this.outstanding,
  });

  final String issued;
  final String collected;
  final String outstanding;

  factory ReceivablesSummary.fromJson(Map<String, dynamic> json) =>
      ReceivablesSummary(
        issued: _string(json['issued']),
        collected: _string(json['collected']),
        outstanding: _string(json['outstanding']),
      );
}

class StatementMovement {
  const StatementMovement({
    required this.date,
    required this.reference,
    required this.type,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.note,
  });

  final String date;
  final String reference;
  final String type;
  final String? debit;
  final String? credit;
  final String balance;
  final String note;

  factory StatementMovement.fromJson(Map<String, dynamic> json) =>
      StatementMovement(
        date: _string(json['date']),
        reference: _string(json['reference']),
        type: _string(json['type']),
        debit: json['debit'] as String?,
        credit: json['credit'] as String?,
        balance: _string(json['balance']),
        note: _string(json['note']),
      );
}

class Statement {
  const Statement({required this.movements, required this.closingBalance});

  final List<StatementMovement> movements;
  final String closingBalance;
}
