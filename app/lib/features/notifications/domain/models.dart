/// ما يصل من الجمعية — one row of `v_notifications`.
///
/// ⚠ WRITTEN BY THE DATABASE, NEVER BY THE CLIENT. A receipt, a voucher, a
///   closed month and a message from the admin each INSERT a row from a trigger
///   or from `send_broadcast()` (PATCH_20260913c). Nothing in Dart composes the
///   text, so the words a member reads are the ones the server stored — and an
///   older APK reads the same sentence a newer one does.
///
/// ⚠ AND NO MONEY FIELD. The amount lives inside [body] as the server wrote it
///   («5,415.00 د.ل»). A notice is a sentence about the ledger, not a figure
///   from it, and nothing here may add one up.
class AppNotice {
  const AppNotice({
    required this.id,
    required this.audience,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.ref,
    this.adeelCode,
    this.adeelName,
  });

  factory AppNotice.fromJson(Map<String, dynamic> json) => AppNotice(
    id: (json['id'] as num).toInt(),
    audience: json['audience'] as String? ?? 'all',
    kind: NoticeKind.fromWire(json['kind'] as String?),
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    ref: json['ref'] as String?,
    createdAt: json['createdAt'] as String? ?? '',
    adeelCode: json['adeelCode'] as String?,
    adeelName: json['adeelName'] as String?,
  );

  final int id;

  /// `member` — addressed to one عديل; `all` — to the whole association.
  final String audience;
  final NoticeKind kind;
  final String title;
  final String body;

  /// The receipt, voucher or month it is about. For display only.
  final String? ref;

  /// ISO timestamp, rendered in Tripoli time by the formatters.
  final String createdAt;

  /// Who it was addressed to — null for a notice to everyone. A member sees
  /// his own code here; staff see whoever it was.
  final String? adeelCode;
  final String? adeelName;

  bool get toEveryone => audience == 'all';
}

/// The six things that write a notice. The wire names are the CHECK
/// constraint's in `ck_notifications_kind`.
enum NoticeKind {
  receivable('receivable'),
  payment('payment'),
  paymentCancelled('payment_cancelled'),
  disbursement('disbursement'),
  disbursementCancelled('disbursement_cancelled'),
  broadcast('broadcast'),

  /// ⚠ NEVER WRITTEN BY THE DATABASE — `ck_notifications_kind` does not allow
  ///   it. The admin's in-app banner for a new proposal borrows the notice's
  ///   banner, and this is only what gives it the proposal's icon.
  proposal('proposal');

  const NoticeKind(this.wire);

  final String wire;

  /// ⚠ AN UNKNOWN KIND IS A MESSAGE, NOT A CRASH. A later patch may add a
  ///   seventh; an APK that predates it must still show the row, and the
  ///   server's own title already says what it is.
  static NoticeKind fromWire(String? wire) {
    for (final NoticeKind k in values) {
      if (k.wire == wire) return k;
    }
    return NoticeKind.broadcast;
  }

  bool get isCancellation =>
      this == NoticeKind.paymentCancelled ||
      this == NoticeKind.disbursementCancelled;
}
