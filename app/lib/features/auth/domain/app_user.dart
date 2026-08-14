/// Roles form a hierarchy: admin ⊇ financeManager ⊇ treasurer ⊇ viewer.
///
/// The client uses this only to decide what to SHOW. Every one of these checks
/// is repeated on the server, which is where they are actually enforced —
/// hiding a button is presentation, never security.
enum AppRole {
  admin('admin', 3),
  financeManager('financeManager', 2),
  treasurer('treasurer', 1),
  viewer('viewer', 0);

  const AppRole(this.wireName, this.rank);

  final String wireName;
  final int rank;

  bool atLeast(AppRole minimum) => rank >= minimum.rank;

  static AppRole fromWire(String? value) => AppRole.values.firstWhere(
    (role) => role.wireName == value,
    // An unknown role must fall back to the LEAST privileged, never the most.
    orElse: () => AppRole.viewer,
  );
}

enum AccountStatus {
  pending('pending'),
  approved('approved'),
  suspended('suspended');

  const AccountStatus(this.wireName);

  final String wireName;

  static AccountStatus fromWire(String? value) =>
      AccountStatus.values.firstWhere(
        (status) => status.wireName == value,
        orElse: () => AccountStatus.pending,
      );
}

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    this.pictureUrl,
    this.familyId,
    this.familyCode,
  });

  /// A uuid, not a number. Identity belongs to Supabase Auth (auth.users.id)
  /// now, so this is the same value auth.uid() returns inside every RLS policy —
  /// which is what makes profiles.id a direct key lookup rather than a mapping.
  final String id;
  final String email;
  final String displayName;
  final String? pictureUrl;
  final AppRole role;
  final AccountStatus status;

  /// The family this account is the head of, or null for association staff.
  ///
  /// This is the branch the whole family portal turns on, and it is deliberately
  /// NOT derived from [role]: a head of family is stored as `viewer`, because
  /// the staff ladder has no rung for him. The database makes the same
  /// distinction the same way — `my_role()` returns NULL as soon as
  /// `profiles.family_id` is set — so what this app shows him and what RLS will
  /// hand him cannot disagree.
  final int? familyId;

  /// F-0001 and the like, for the portal's heading. Null for staff.
  final String? familyCode;

  bool get isApproved => status == AccountStatus.approved;

  /// Read-only access to exactly one family, and nothing of the association's.
  bool get isFamilyHead => familyId != null;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    id: json['id'] as String,
    email: json['email'] as String? ?? '',
    displayName: json['displayName'] as String? ?? '',
    pictureUrl: json['pictureUrl'] as String?,
    role: AppRole.fromWire(json['role'] as String?),
    status: AccountStatus.fromWire(json['status'] as String?),
    familyId: (json['familyId'] as num?)?.toInt(),
    familyCode: json['familyCode'] as String?,
  );
}

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final AppUser user;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
  );
}
