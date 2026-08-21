/// Read-side view models.
///
/// Money is carried as the exact decimal STRING the server sent and is only
/// ever formatted for display — never parsed and re-summed, because every
/// total on every screen is computed server-side against the database.
library;

String _string(Object? value) => value == null ? '' : value.toString();
int _int(Object? value) => value is num ? value.toInt() : 0;

/// A key that may be ABSENT because the database predates it.
///
/// Distinct from [_string], which turns a missing key into `''` — and an empty
/// string is not a money value: `double.tryParse('')` is null, every comparison
/// against it is false, and a wallet the schema simply has not grown yet would
/// read as a figure that failed to load. The fallback says what the older
/// database MEANT instead.
String _stringOr(Object? value, String fallback) =>
    value == null ? fallback : value.toString();

class AssociationSettingsView {
  const AssociationSettingsView({
    required this.associationName,
    required this.currency,
    required this.memberFee,
    required this.bankName,
    required this.bankAccountNo,
    required this.bankAccountName,
    this.feeExceptions = const <String, String>{},
  });

  final String associationName;
  final String currency;

  /// One rate for everyone. There were two — a father's and a son's — until the
  /// association stopped billing households through their head.
  final String memberFee;

  /// The association's own receiving account, for a تحويل مصرفي. Empty until an
  /// admin fills it in, which the payment sheet renders as "not set yet" rather
  /// than as a blank line.
  final String bankName;
  final String bankAccountNo;
  final String bankAccountName;

  /// «ماعدا» — the calendar months that cost something other than [memberFee].
  ///
  /// ⚠ ON THE WIDELY READABLE VIEW, deliberately, and not only on the
  ///   admin-only settings shape. An عديل reads v_settings too, and the fee is
  ///   printed on HIS page as well — «الاشتراك الشهري: 100» is not wrong when
  ///   يناير costs 200, it is INCOMPLETE, and an incomplete figure invites no
  ///   second look. Same reasoning that put the bank account here.
  ///
  /// ⚠ AND IT DEFAULTS TO EMPTY rather than being required, so a database that
  ///   predates the column renders no line instead of failing to parse.
  final Map<String, String> feeExceptions;

  bool get hasBankAccount => bankAccountNo.trim().isNotEmpty;

  factory AssociationSettingsView.fromJson(Map<String, dynamic> json) =>
      AssociationSettingsView(
        associationName: _string(json['associationName']),
        currency: _string(json['currency']),
        memberFee: _string(json['memberFee']),
        // _string, not a cast: the captured wire fixtures in test/fixtures/
        // predate these columns, and a hard cast would fail contract parsing on
        // a view that is otherwise unchanged.
        bankName: _string(json['bankName']),
        bankAccountNo: _string(json['bankAccountNo']),
        bankAccountName: _string(json['bankAccountName']),
        feeExceptions: <String, String>{
          for (final MapEntry<String, dynamic> e in (json['feeExceptions']
                      as Map<String, dynamic>? ??
                  const <String, dynamic>{})
              .entries)
            e.key: _string(e.value),
        },
      );
}

class Official {
  const Official({required this.role, required this.name, required this.phone});

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
    this.credit = '0.00',
    this.netBalance = '0.00',
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

  /// Money he has handed over that no month has claimed yet — the wallet.
  ///
  /// Derived server-side as Σ payments − Σ allocations, never stored, so it
  /// cannot drift from the receipts it is made of. Defaults to '0.00' for a
  /// database that predates it, which reads as "no credit" rather than as a
  /// parse failure.
  final String credit;

  /// debt − credit. POSITIVE means he owes, NEGATIVE means the association is
  /// holding his money. One figure, and its sign is what the portal paints.
  final String netBalance;

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
    credit: _stringOr(json['credit'], '0.00'),
    netBalance: _stringOr(json['netBalance'], _string(json['debt'])),
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
    this.credit = '0.00',
    this.netBalance = '0.00',
  });

  final AdeelView adeel;
  final String monthlyExpected;
  final String issued;
  final String debt;
  final String paid;

  /// The wallet — see [AdeelView.credit].
  final String credit;

  /// `debt − credit`, and the ONE figure the portal leads with.
  final String netBalance;

  /// He owes the association. Red.
  bool get owes => (double.tryParse(netBalance) ?? 0) > 0;

  /// The association is holding money for him. Green.
  ///
  /// Not `!owes`: a balance of exactly zero is neither, and it deserves its own
  /// wording — "settled up" is an answer, "you have 0.00 in credit" is not.
  bool get inCredit => (double.tryParse(netBalance) ?? 0) < 0;

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
      credit: _stringOr(kpis['credit'], '0.00'),
      // Falls back to `debt`, which is what the net balance WAS before a wallet
      // existed: with no credit possible, what he owed and where he stood were
      // the same number. A build pointed at an older database therefore shows
      // exactly what it used to, rather than a zero balance for everyone.
      netBalance: _stringOr(kpis['netBalance'], _string(kpis['debt'])),
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

/// The association's treasury, in totals, as an عديل may read it.
///
/// Every field is an AGGREGATE. There is no name, no receipt and no per-member
/// figure in here, and that is the line between "transparency about the
/// collective purse" and "reading a neighbour's affairs" — the association
/// asked for the first and the second is what RLS spends its whole existence
/// preventing.
///
/// Read-only in the strongest sense available: the RPC behind it takes no
/// argument and performs no write, and nothing on the portal offers an action
/// against it.
class AssociationFinance {
  const AssociationFinance({
    required this.balance,
    required this.collected,
    required this.disbursed,
    required this.cash,
    required this.transfer,
    required this.issued,
    required this.outstanding,
    required this.members,
    required this.activeMembers,
    this.heldForMembers = '0.00',
  });

  /// What the association HOLDS: collections in, disbursements out.
  ///
  /// Distinct from [collected], which is everything that ever arrived. The two
  /// were the same number while money could not leave; presenting the first as
  /// the balance now would overstate the fund by every voucher written.
  final String balance;
  final String collected;
  final String disbursed;

  /// عهد المشتركين — cash the association holds and does not own, because a
  /// member paid ahead and his months are not billed yet.
  ///
  /// Shown to a member for the same reason the outgoing side is: a balance that
  /// counted money owed back to people would overstate the fund, which is the
  /// opposite of transparency. Defaults to zero for a database that predates the
  /// column.
  final String heldForMembers;
  final String cash;
  final String transfer;

  /// Everything ever charged to everybody, and what of it is still unpaid.
  final String issued;
  final String outstanding;

  final int members;
  final int activeMembers;

  factory AssociationFinance.fromJson(Map<String, dynamic> json) =>
      AssociationFinance(
        balance: _string(json['balance']),
        collected: _string(json['collected']),
        disbursed: _string(json['disbursed']),
        heldForMembers: _stringOr(json['heldForMembers'], '0.00'),
        cash: _string(json['cash']),
        transfer: _string(json['transfer']),
        issued: _string(json['issued']),
        outstanding: _string(json['outstanding']),
        members: _int(json['members']),
        activeMembers: _int(json['activeMembers']),
      );
}
