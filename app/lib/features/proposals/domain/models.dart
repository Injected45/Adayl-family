/// مقترحٌ من مشترك — one row of `v_proposals`.
///
/// ⚠ TWO STATES, NOT THREE. A proposal waits, or it was accepted. A rejected
///   one is not a state — `reject_proposal` DELETES the row, so it is gone
///   from the admin's tab and from the member's list alike: «يختفي تماما».
///
/// ⚠ AN ACCEPTED PROPOSAL IS FOREVER, AND THE DATABASE SAYS SO. `proposals_guard`
///   refuses every edit and every delete of one, whoever asks.
class Proposal {
  const Proposal({
    required this.id,
    required this.adeelId,
    required this.adeelCode,
    required this.adeelName,
    required this.title,
    required this.body,
    required this.accepted,
    required this.createdAt,
    this.decidedAt,
  });

  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
    id: (json['id'] as num).toInt(),
    adeelId: (json['adeelId'] as num?)?.toInt() ?? 0,
    adeelCode: json['adeelCode'] as String? ?? '',
    adeelName: json['adeelName'] as String? ?? '',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    accepted: json['status'] == 'accepted',
    createdAt: json['createdAt'] as String? ?? '',
    decidedAt: json['decidedAt'] as String?,
  );

  final int id;
  final int adeelId;
  final String adeelCode;

  /// Snapshot of his name when he sent it.
  final String adeelName;
  final String title;
  final String body;
  final bool accepted;
  final String createdAt;
  final String? decidedAt;
}

/// The title's limit — «لايسمح باكثر من 20 حرف». `ck_proposal_title` and
/// `submit_proposal` count characters the way Postgres does (code points), so
/// the field counts them the same way.
const int proposalTitleMax = 20;

/// The text's limit, the database's.
const int proposalBodyMax = 2000;
