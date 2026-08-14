/// Dashboard, alerts, reports, audit trail, users, and editable settings.
library;

import '../../../core/domain/wire_values.dart';
import '../../auth/domain/app_user.dart';

String _string(Object? value) => value == null ? '' : value.toString();
int _int(Object? value) => value is num ? value.toInt() : 0;

class DashboardStats {
  const DashboardStats({
    required this.families,
    required this.sons,
    required this.eligible,
    required this.soon,
    required this.under,
    required this.debt,
    required this.collected,
    required this.cash,
    required this.transfer,
    required this.indebtedFamilies,
  });

  final int families;
  final int sons;
  final int eligible;
  final int soon;
  final int under;
  final String debt;
  final String collected;
  final String cash;
  final String transfer;
  final int indebtedFamilies;

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
    families: _int(json['families']),
    sons: _int(json['sons']),
    eligible: _int(json['eligible']),
    soon: _int(json['soon']),
    under: _int(json['under']),
    debt: _string(json['debt']),
    collected: _string(json['collected']),
    cash: _string(json['cash']),
    transfer: _string(json['transfer']),
    indebtedFamilies: _int(json['indebtedFamilies']),
  );
}

class DebtorRow {
  const DebtorRow({
    required this.familyId,
    required this.familyCode,
    required this.fatherName,
    required this.debt,
  });

  final int familyId;
  final String familyCode;
  final String fatherName;
  final String debt;

  factory DebtorRow.fromJson(Map<String, dynamic> json) => DebtorRow(
    familyId: _int(json['familyId']),
    familyCode: _string(json['familyCode']),
    fatherName: _string(json['fatherName']),
    debt: _string(json['debt']),
  );
}

class UpcomingSon {
  const UpcomingSon({
    required this.sonId,
    required this.sonName,
    required this.familyId,
    required this.fatherName,
  });

  final int sonId;
  final String sonName;
  final int familyId;
  final String fatherName;

  factory UpcomingSon.fromJson(Map<String, dynamic> json) => UpcomingSon(
    sonId: _int(json['sonId']),
    sonName: _string(json['sonName']),
    familyId: _int(json['familyId']),
    fatherName: _string(json['fatherName']),
  );
}

class DashboardData {
  const DashboardData({
    required this.stats,
    required this.topDebtors,
    required this.upcomingSons,
    required this.closingPeriod,
    required this.closingPeriodLabel,
  });

  final DashboardStats stats;
  final List<DebtorRow> topDebtors;
  final List<UpcomingSon> upcomingSons;
  final String closingPeriod;
  final String closingPeriodLabel;

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
    stats: DashboardStats.fromJson(
      (json['stats'] as Map).cast<String, dynamic>(),
    ),
    topDebtors: (json['topDebtors'] as List<dynamic>)
        .map(
          (dynamic e) => DebtorRow.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(),
    upcomingSons: (json['upcomingSons'] as List<dynamic>)
        .map(
          (dynamic e) =>
              UpcomingSon.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(),
    closingPeriod: _string(json['closingPeriod']),
    closingPeriodLabel: _string(json['closingPeriodLabel']),
  );
}

class AlertItem {
  const AlertItem({
    required this.type,
    required this.severity,
    required this.text,
    required this.familyId,
  });

  final String type;
  final String severity;
  final String text;
  final int familyId;

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
    type: _string(json['type']),
    severity: _string(json['severity']),
    text: _string(json['text']),
    familyId: _int(json['familyId']),
  );
}

class ReportPaymentRow {
  const ReportPaymentRow({
    required this.receiptNo,
    required this.familyName,
    required this.amount,
    required this.method,
    required this.reference,
    required this.paidAt,
  });

  final String receiptNo;
  final String familyName;
  final String amount;
  final String method;
  final String reference;
  final String paidAt;

  factory ReportPaymentRow.fromJson(Map<String, dynamic> json) =>
      ReportPaymentRow(
        receiptNo: _string(json['receiptNo']),
        familyName: _string(json['familyName']),
        amount: _string(json['amount']),
        method: _string(json['method']),
        reference: _string(json['reference']),
        paidAt: _string(json['paidAt']),
      );
}

class FinancialReport {
  const FinancialReport({
    required this.from,
    required this.to,
    required this.issued,
    required this.issuedCount,
    required this.collected,
    required this.collectedCount,
    required this.debt,
    required this.partialCount,
    required this.payments,
  });

  final String from;
  final String to;
  final String issued;
  final int issuedCount;
  final String collected;
  final int collectedCount;
  final String debt;
  final int partialCount;
  final List<ReportPaymentRow> payments;

  factory FinancialReport.fromJson(Map<String, dynamic> json) =>
      FinancialReport(
        from: _string(json['from']),
        to: _string(json['to']),
        issued: _string(json['issued']),
        issuedCount: _int(json['issuedCount']),
        collected: _string(json['collected']),
        collectedCount: _int(json['collectedCount']),
        debt: _string(json['debt']),
        partialCount: _int(json['partialCount']),
        payments: (json['payments'] as List<dynamic>)
            .map(
              (dynamic e) =>
                  ReportPaymentRow.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList(),
      );
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.eventType,
    required this.detail,
    required this.ref,
    required this.actorName,
    required this.occurredAt,
  });

  final int id;
  final String eventType;
  final String detail;
  final String ref;
  final String actorName;
  final String occurredAt;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
    id: _int(json['id']),
    eventType: _string(json['eventType']),
    detail: _string(json['detail']),
    ref: _string(json['ref']),
    actorName: _string(json['actorName']),
    occurredAt: _string(json['occurredAt']),
  );
}

class AuditPage {
  const AuditPage({
    required this.items,
    required this.total,
    required this.eventTypes,
  });

  final List<AuditEntry> items;
  final int total;
  final List<String> eventTypes;
}

class UserAccount {
  const UserAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    required this.lastLoginAt,
    required this.approvedByName,
  });

  /// A uuid string. See AppUser.id.
  final String id;
  final String email;
  final String displayName;
  final AppRole role;
  final AccountStatus status;
  final String? lastLoginAt;
  final String? approvedByName;

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
    id: _string(json['id']),
    email: _string(json['email']),
    displayName: _string(json['displayName']),
    role: AppRole.fromWire(json['role'] as String?),
    status: AccountStatus.fromWire(json['status'] as String?),
    lastLoginAt: json['lastLoginAt'] as String?,
    approvedByName: json['approvedByName'] as String?,
  );
}

class OfficialInput {
  const OfficialInput({
    required this.name,
    required this.nationalId,
    required this.phone,
  });

  final String name;
  final String nationalId;
  final String phone;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'nationalId': nationalId,
    'phone': phone,
  };

  factory OfficialInput.fromJson(Map<String, dynamic> json) => OfficialInput(
    name: _string(json['name']),
    nationalId: _string(json['nationalId']),
    phone: _string(json['phone']),
  );
}

/// The full settings record, including the fields the read-only view omits.
class EditableSettings {
  const EditableSettings({
    required this.associationName,
    required this.currency,
    required this.fatherFee,
    required this.sonFee,
    required this.eligibilityAge,
    required this.warningMonths,
    required this.systemStart,
    required this.autoClosePreviousMonths,
    required this.treasurer,
    required this.financeManager,
  });

  final String associationName;
  final String currency;
  final String fatherFee;
  final String sonFee;
  final int eligibilityAge;
  final int warningMonths;
  final String systemStart;
  final bool autoClosePreviousMonths;
  final OfficialInput treasurer;
  final OfficialInput financeManager;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'associationName': associationName,
    'currency': currency,
    'fatherFee': fatherFee,
    'sonFee': sonFee,
    'eligibilityAge': eligibilityAge,
    'warningMonths': warningMonths,
    'systemStart': systemStart,
    'autoClosePreviousMonths': autoClosePreviousMonths,
    'treasurer': treasurer.toJson(),
    'financeManager': financeManager.toJson(),
  };

  factory EditableSettings.fromJson(Map<String, dynamic> json) =>
      EditableSettings(
        associationName: _string(json['associationName']),
        currency: _string(json['currency']),
        fatherFee: _string(json['fatherFee']),
        sonFee: _string(json['sonFee']),
        eligibilityAge: _int(json['eligibilityAge']),
        warningMonths: _int(json['warningMonths']),
        systemStart: _string(json['systemStart']),
        autoClosePreviousMonths: json['autoClosePreviousMonths'] == true,
        treasurer: OfficialInput.fromJson(
          (json['treasurer'] as Map).cast<String, dynamic>(),
        ),
        financeManager: OfficialInput.fromJson(
          (json['financeManager'] as Map).cast<String, dynamic>(),
        ),
      );
}

/// What `purge_financial_data` reports it erased.
///
/// Counts, not money, so `_int` is right here — these are the only numbers in
/// the app that legitimately arrive as JSON numbers rather than text.
class PurgeResult {
  const PurgeResult({
    required this.receivables,
    required this.receivableLines,
    required this.payments,
    required this.allocations,
    required this.cashMovements,
    required this.auditEntries,
    this.families = 0,
    this.members = 0,
  });

  final int receivables;
  final int receivableLines;
  final int payments;
  final int allocations;
  final int cashMovements;
  final int auditEntries;

  /// Only `purge_all_data` reports these. The financial purge leaves the
  /// directory alone and omits both keys, so they decode to zero — which is the
  /// truth about what it removed, not a missing value.
  final int families;
  final int members;

  /// Every row the purge removed, for the one-line confirmation the screen
  /// shows. The figures are kept separately because an admin who purged by
  /// accident will want to know exactly what went.
  int get total =>
      receivables +
      receivableLines +
      payments +
      allocations +
      cashMovements +
      auditEntries +
      families +
      members;

  factory PurgeResult.fromJson(Map<String, dynamic> json) => PurgeResult(
    receivables: _int(json['receivables']),
    receivableLines: _int(json['receivableLines']),
    payments: _int(json['payments']),
    allocations: _int(json['allocations']),
    cashMovements: _int(json['cashMovements']),
    auditEntries: _int(json['auditEntries']),
    families: _int(json['families']),
    members: _int(json['members']),
  );
}

/// One member as the family form submits it.
class MemberInput {
  const MemberInput({
    this.id,
    required this.fullName,
    required this.nationalId,
    this.phone = '',
    this.subscriptionNo = '',
    this.dob,
    this.nationality = MemberDefaults.nationality,
    this.workplace = '',
    this.status = MemberDefaults.status,
    this.notes = '',
  });

  final int? id;
  final String fullName;
  final String nationalId;
  final String phone;
  final String subscriptionNo;
  final String? dob;
  final String nationality;
  final String workplace;
  final String status;
  final String notes;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': ?id,
    'fullName': fullName,
    'nationalId': nationalId,
    'phone': phone,
    'subscriptionNo': subscriptionNo,
    'dob': dob != null && dob!.isNotEmpty ? dob : null,
    'nationality': nationality,
    'workplace': workplace,
    'status': status,
    'notes': notes,
  };
}
