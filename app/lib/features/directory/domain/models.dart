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
    required this.fatherFee,
    required this.sonFee,
    required this.eligibilityAge,
    required this.warningMonths,
  });

  final String associationName;
  final String currency;
  final String fatherFee;
  final String sonFee;
  final int eligibilityAge;
  final int warningMonths;

  factory AssociationSettingsView.fromJson(Map<String, dynamic> json) =>
      AssociationSettingsView(
        associationName: _string(json['associationName']),
        currency: _string(json['currency']),
        fatherFee: _string(json['fatherFee']),
        sonFee: _string(json['sonFee']),
        eligibilityAge: _int(json['eligibilityAge']),
        warningMonths: _int(json['warningMonths']),
      );
}

class Official {
  const Official({
    required this.role,
    required this.name,
    required this.nationalId,
    required this.phone,
  });

  final String role;
  final String name;
  final String nationalId;
  final String phone;

  factory Official.fromJson(Map<String, dynamic> json) => Official(
    role: _string(json['role']),
    name: _string(json['name']),
    nationalId: _string(json['nationalId']),
    phone: _string(json['phone']),
  );
}

class FamilyListItem {
  const FamilyListItem({
    required this.id,
    required this.familyCode,
    required this.fatherName,
    required this.sonsCount,
    required this.eligibleCount,
    required this.debt,
    required this.monthlyExpected,
  });

  final int id;
  final String familyCode;
  final String fatherName;
  final int sonsCount;
  final int eligibleCount;
  final String debt;
  final String monthlyExpected;

  bool get hasDebt => (double.tryParse(debt) ?? 0) > 0;

  factory FamilyListItem.fromJson(Map<String, dynamic> json) => FamilyListItem(
    id: _int(json['id']),
    familyCode: _string(json['familyCode']),
    fatherName: _string(json['fatherName']),
    sonsCount: _int(json['sonsCount']),
    eligibleCount: _int(json['eligibleCount']),
    debt: _string(json['debt']),
    monthlyExpected: _string(json['monthlyExpected']),
  );
}

/// The four states index.html shows for a son's subscription eligibility.
enum EligibilityKey { eligible, soon, under, inactive }

EligibilityKey _eligibilityFromWire(String? value) => switch (value) {
  'eligible' => EligibilityKey.eligible,
  'soon' => EligibilityKey.soon,
  'under' => EligibilityKey.under,
  _ => EligibilityKey.inactive,
};

class MemberView {
  const MemberView({
    required this.id,
    required this.fullName,
    required this.nationalId,
    required this.phone,
    required this.subscriptionNo,
    required this.dob,
    required this.age,
    required this.nationality,
    required this.workplace,
    required this.registeredAt,
    required this.membershipStatus,
    required this.eligibility,
    required this.eligibilityLabel,
    required this.currentFee,
  });

  final int id;
  final String fullName;
  final String nationalId;
  final String phone;
  final String subscriptionNo;
  final String dob;
  final int? age;
  final String nationality;
  final String workplace;
  final String registeredAt;
  final String membershipStatus;
  final EligibilityKey eligibility;

  /// The server sends the Arabic label so it can never disagree with the badge
  /// the prototype showed for the same member.
  final String eligibilityLabel;
  final String? currentFee;

  factory MemberView.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> eligibility =
        (json['eligibility'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    return MemberView(
      id: _int(json['id']),
      fullName: _string(json['fullName']),
      nationalId: _string(json['nationalId']),
      phone: _string(json['phone']),
      subscriptionNo: _string(json['subscriptionNo']),
      dob: _string(json['dob']),
      age: json['age'] is num ? (json['age'] as num).toInt() : null,
      nationality: _string(json['nationality']),
      workplace: _string(json['workplace']),
      registeredAt: _string(json['registeredAt']),
      membershipStatus: _string(json['membershipStatus']),
      eligibility: _eligibilityFromWire(eligibility['key'] as String?),
      eligibilityLabel: _string(eligibility['label']),
      currentFee: json['currentFee'] as String?,
    );
  }
}

class FamilyDetail {
  const FamilyDetail({
    required this.id,
    required this.familyCode,
    required this.father,
    required this.sons,
    required this.sonsCount,
    required this.eligibleCount,
    required this.soonCount,
    required this.monthlyExpected,
    required this.debt,
    required this.paid,
  });

  final int id;
  final String familyCode;
  final MemberView? father;
  final List<MemberView> sons;
  final int sonsCount;
  final int eligibleCount;
  final int soonCount;
  final String monthlyExpected;
  final String debt;
  final String paid;

  factory FamilyDetail.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> family = (json['family'] as Map)
        .cast<String, dynamic>();
    final Map<String, dynamic> kpis = (json['kpis'] as Map)
        .cast<String, dynamic>();
    return FamilyDetail(
      id: _int(family['id']),
      familyCode: _string(family['familyCode']),
      father: json['father'] == null
          ? null
          : MemberView.fromJson(
              (json['father'] as Map).cast<String, dynamic>(),
            ),
      sons: (json['sons'] as List<dynamic>)
          .map(
            (dynamic e) =>
                MemberView.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList(),
      sonsCount: _int(kpis['sonsCount']),
      eligibleCount: _int(kpis['eligibleCount']),
      soonCount: _int(kpis['soonCount']),
      monthlyExpected: _string(kpis['monthlyExpected']),
      debt: _string(kpis['debt']),
      paid: _string(kpis['paid']),
    );
  }
}

class MemberListItem {
  const MemberListItem({
    required this.id,
    required this.familyId,
    required this.fullName,
    required this.relation,
    required this.familyName,
    required this.nationalId,
    required this.phone,
    required this.workplace,
    required this.age,
  });

  final int id;
  final int familyId;
  final String fullName;
  final String relation;
  final String familyName;
  final String nationalId;
  final String phone;
  final String workplace;
  final int? age;

  factory MemberListItem.fromJson(Map<String, dynamic> json) => MemberListItem(
    id: _int(json['id']),
    familyId: _int(json['familyId']),
    fullName: _string(json['fullName']),
    relation: _string(json['relation']),
    familyName: _string(json['familyName']),
    nationalId: _string(json['nationalId']),
    phone: _string(json['phone']),
    workplace: _string(json['workplace']),
    age: json['age'] is num ? (json['age'] as num).toInt() : null,
  );
}

class ReceivableItem {
  const ReceivableItem({
    required this.id,
    required this.familyName,
    required this.familyCode,
    required this.period,
    required this.periodLabel,
    required this.fatherFee,
    required this.sonFee,
    required this.billedSonNames,
    required this.total,
    required this.paid,
    required this.balance,
    required this.status,
  });

  final int id;
  final String familyName;
  final String familyCode;
  final String period;
  final String periodLabel;
  final String fatherFee;
  final String sonFee;
  final List<String> billedSonNames;
  final String total;
  final String paid;
  final String balance;
  final String status;

  factory ReceivableItem.fromJson(Map<String, dynamic> json) => ReceivableItem(
    id: _int(json['id']),
    familyName: _string(json['familyName']),
    familyCode: _string(json['familyCode']),
    period: _string(json['period']),
    periodLabel: _string(json['periodLabel']),
    fatherFee: _string(json['fatherFee']),
    sonFee: _string(json['sonFee']),
    billedSonNames: (json['billedSonNames'] as List<dynamic>? ?? <dynamic>[])
        .map(_string)
        .toList(),
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
