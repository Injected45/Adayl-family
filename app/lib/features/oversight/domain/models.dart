/// Dashboard, alerts, reports, audit trail, users, and editable settings.
library;

import '../../auth/domain/app_user.dart';

String _string(Object? value) => value == null ? '' : value.toString();
int _int(Object? value) => value is num ? value.toInt() : 0;

/// The dashboard's stat row.
///
/// It used to count families, sons, and how many sons were eligible,
/// approaching the eligibility age, or under it. None of those quantities exist:
/// there are no families, every عديل is billed alike, and there is no age to be
/// under. What replaces them is the register broken down by membership status,
/// which is now the only thing that decides whether a charge is raised.
class DashboardStats {
  const DashboardStats({
    required this.adeels,
    required this.active,
    required this.suspended,
    required this.deceased,
    required this.debt,
    required this.collected,
    required this.cash,
    required this.transfer,
    required this.indebtedAdeels,
  });

  final int adeels;
  final int active;
  final int suspended;
  final int deceased;
  final String debt;
  final String collected;
  final String cash;
  final String transfer;
  final int indebtedAdeels;

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
    adeels: _int(json['adeels']),
    active: _int(json['active']),
    suspended: _int(json['suspended']),
    deceased: _int(json['deceased']),
    debt: _string(json['debt']),
    collected: _string(json['collected']),
    cash: _string(json['cash']),
    transfer: _string(json['transfer']),
    indebtedAdeels: _int(json['indebtedAdeels']),
  );
}

class DebtorRow {
  const DebtorRow({
    required this.adeelId,
    required this.adeelCode,
    required this.adeelName,
    required this.debt,
  });

  final int adeelId;
  final String adeelCode;
  final String adeelName;
  final String debt;

  factory DebtorRow.fromJson(Map<String, dynamic> json) => DebtorRow(
    adeelId: _int(json['adeelId']),
    adeelCode: _string(json['adeelCode']),
    adeelName: _string(json['adeelName']),
    debt: _string(json['debt']),
  );
}

// `UpcomingSon` is GONE, along with the "قريب من السن" card it fed. It listed
// sons whose sixteenth birthday fell inside warning_months, so the treasurer
// could see a charge coming before it appeared. With no age gate there is no
// charge to see coming: an عديل is billed from the day he is registered نشط.

class DashboardData {
  const DashboardData({
    required this.stats,
    required this.topDebtors,
    required this.closingPeriod,
    required this.closingPeriodLabel,
  });

  final DashboardStats stats;
  final List<DebtorRow> topDebtors;
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
    closingPeriod: _string(json['closingPeriod']),
    closingPeriodLabel: _string(json['closingPeriodLabel']),
  );
}

class AlertItem {
  const AlertItem({
    required this.type,
    required this.severity,
    required this.text,
    required this.adeelId,
  });

  final String type;
  final String severity;
  final String text;
  final int adeelId;

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
    type: _string(json['type']),
    severity: _string(json['severity']),
    text: _string(json['text']),
    adeelId: _int(json['adeelId']),
  );
}

class ReportPaymentRow {
  const ReportPaymentRow({
    required this.receiptNo,
    required this.adeelName,
    required this.amount,
    required this.method,
    required this.reference,
    required this.paidAt,
  });

  final String receiptNo;
  final String adeelName;
  final String amount;
  final String method;
  final String reference;
  final String paidAt;

  factory ReportPaymentRow.fromJson(Map<String, dynamic> json) =>
      ReportPaymentRow(
        receiptNo: _string(json['receiptNo']),
        adeelName: _string(json['adeelName']),
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
    required this.phone,
    this.adeelId,
  });

  final String name;
  final String phone;

  /// Which عديل holds the post. Both officials are elected FROM the members, so
  /// the post is a row in the register rather than a typed name — that is what
  /// stops the same man arriving as three spellings across a year of edits, and
  /// what lets the database refuse one person holding both posts.
  ///
  /// Nullable: a vacant post, or one filled by a typed name before the two were
  /// tied to the register. [name] and [phone] still carry the snapshot the
  /// server keeps beside the id, so a screen can render the holder without
  /// reading the register.
  final int? adeelId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'adeelId': adeelId,
    'name': name,
    'phone': phone,
  };

  factory OfficialInput.fromJson(Map<String, dynamic> json) => OfficialInput(
    adeelId: (json['adeelId'] as num?)?.toInt(),
    name: _string(json['name']),
    phone: _string(json['phone']),
  );
}

/// The full settings record, including the fields the read-only view omits.
class EditableSettings {
  const EditableSettings({
    required this.associationName,
    required this.currency,
    required this.memberFee,
    required this.systemStart,
    required this.autoClosePreviousMonths,
    required this.bankName,
    required this.bankAccountNo,
    required this.bankAccountName,
    required this.treasurer,
    required this.financeManager,
  });

  final String associationName;
  final String currency;
  final String memberFee;
  final String systemStart;
  final bool autoClosePreviousMonths;

  /// The association's receiving bank account, as one record rather than a
  /// thing a treasurer retypes on every transfer. `register_payment` snapshots
  /// it onto the payment server-side; nothing here is sent with a collection.
  final String bankName;
  final String bankAccountNo;
  final String bankAccountName;
  final OfficialInput treasurer;
  final OfficialInput financeManager;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'associationName': associationName,
    'currency': currency,
    'memberFee': memberFee,
    'systemStart': systemStart,
    'autoClosePreviousMonths': autoClosePreviousMonths,
    'bankName': bankName,
    'bankAccountNo': bankAccountNo,
    'bankAccountName': bankAccountName,
    'treasurer': treasurer.toJson(),
    'financeManager': financeManager.toJson(),
  };

  /// What `update_settings(p_patch)` actually reads — and it is NOT [toJson].
  ///
  /// The two officials travel in different shapes in each direction, which is
  /// the whole bug this method exists to close:
  ///
  ///   api_settings() RETURNS them nested — {"treasurer": {"name", "phone"}} —
  ///   and [fromJson]/[toJson] mirror that faithfully.
  ///
  ///   update_settings() READS them flat — `p_patch ->> 'treasurerName'`.
  ///
  /// Posting the nested shape to the RPC therefore left all four lookups NULL,
  /// `coalesce` kept the existing value, and the treasurer and finance manager
  /// silently never saved while every other field on the same screen did. No
  /// error, no warning: the save reported success and the names came back
  /// unchanged.
  ///
  /// Kept as a SEPARATE method rather than reshaping [toJson], because toJson
  /// is the faithful mirror of what the server sends and the round-trip test
  /// depends on that symmetry. This one is the wire format of one specific RPC,
  /// and naming it after that job is what stops the two being confused again.
  Map<String, dynamic> toPatch() => <String, dynamic>{
    'associationName': associationName,
    'currency': currency,
    'memberFee': memberFee,
    'systemStart': systemStart,
    'autoClosePreviousMonths': autoClosePreviousMonths,
    'bankName': bankName,
    'bankAccountNo': bankAccountNo,
    'bankAccountName': bankAccountName,
    // The posts, as عديل ids. These are what update_settings acts on: it copies
    // the chosen man's name and phone out of the register, so the four text
    // keys below are only consulted when a post has no عديل behind it.
    //
    // Always sent, including as null — `p_patch ? 'treasurerAdeelId'` is how the
    // server tells "vacate this post" from "leave it alone", and omitting the
    // key would make vacating impossible.
    'treasurerAdeelId': treasurer.adeelId,
    'financeAdeelId': financeManager.adeelId,
    'treasurerName': treasurer.name,
    'treasurerPhone': treasurer.phone,
    'financeName': financeManager.name,
    'financePhone': financeManager.phone,
  };

  factory EditableSettings.fromJson(Map<String, dynamic> json) =>
      EditableSettings(
        associationName: _string(json['associationName']),
        currency: _string(json['currency']),
        memberFee: _string(json['memberFee']),
        systemStart: _string(json['systemStart']),
        autoClosePreviousMonths: json['autoClosePreviousMonths'] == true,
        bankName: _string(json['bankName']),
        bankAccountNo: _string(json['bankAccountNo']),
        bankAccountName: _string(json['bankAccountName']),
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
    required this.payments,
    required this.allocations,
    required this.cashMovements,
    required this.auditEntries,
    this.adeels = 0,
  });

  final int receivables;
  final int payments;
  final int allocations;
  final int cashMovements;
  final int auditEntries;

  /// Only `purge_all_data` reports this. The financial purge leaves the register
  /// alone and omits the key, so it decodes to zero — which is the truth about
  /// what it removed, not a missing value.
  ///
  /// `receivableLines` used to sit alongside it and is gone with the table: a
  /// receivable bills one عديل for one month, so there was nothing left for a
  /// line to describe.
  final int adeels;

  /// Every row the purge removed, for the one-line confirmation the screen
  /// shows. The figures are kept separately because an admin who purged by
  /// accident will want to know exactly what went.
  int get total =>
      receivables +
      payments +
      allocations +
      cashMovements +
      auditEntries +
      adeels;

  factory PurgeResult.fromJson(Map<String, dynamic> json) => PurgeResult(
    receivables: _int(json['receivables']),
    payments: _int(json['payments']),
    allocations: _int(json['allocations']),
    cashMovements: _int(json['cashMovements']),
    auditEntries: _int(json['auditEntries']),
    adeels: _int(json['adeels']),
  );
}

