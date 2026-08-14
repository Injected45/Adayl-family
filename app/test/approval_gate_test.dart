import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// The approval gate on the SIGN-IN path.
///
/// `restore()` — the relaunch path — always derived the stage from
/// `user.status`, so a pending account resumed onto its waiting screen. The
/// fresh sign-in path did not: `_adopt()` fetched the profile through
/// `api_me()`, read the status, and returned a Session regardless. Nothing
/// raised ACCOUNT_PENDING, so `AuthStage.pending` was unreachable through
/// sign-in and a pending account went straight to the dashboard.
///
/// It looked harmless because RLS gives a pending caller nothing, so the
/// dashboard rendered zeros — an association with no families and an empty
/// treasury, which is indistinguishable from a new one. The refusal was being
/// displayed as data.
///
/// These assert the decision itself, on the model the repository branches on.
/// A widget test cannot reach it without a live GoTrue session, and the
/// interesting case is precisely the one that never reaches a screen.
void main() {
  AppUser userWith(AccountStatus status) => AppUser(
    id: 'ecf4c6d0-0000-4000-8000-000000000001',
    email: 'someone@example.com',
    displayName: 'Someone',
    role: AppRole.viewer,
    status: status,
  );

  group('approval gate', () {
    test('an approved account is let through', () {
      expect(userWith(AccountStatus.approved).isApproved, isTrue);
    });

    // The regression. Before the fix this was the only status that reached the
    // dashboard when it should not have.
    test('a pending account is NOT approved', () {
      expect(userWith(AccountStatus.pending).isApproved, isFalse);
    });

    test('a suspended account is NOT approved', () {
      expect(userWith(AccountStatus.suspended).isApproved, isFalse);
    });

    // The two must stay distinguishable: they map to different screens and
    // different messages, and collapsing them would tell a suspended member
    // their account is merely awaiting approval.
    test('pending and suspended are distinct', () {
      expect(AccountStatus.pending, isNot(AccountStatus.suspended));
    });

    // An unrecognised status must not be read as permission. A renamed enum
    // value in the database would otherwise silently admit everyone.
    test('an unknown wire status falls back to pending, never approved', () {
      expect(AccountStatus.fromWire('brand_new_value'), AccountStatus.pending);
      expect(AccountStatus.fromWire(null), AccountStatus.pending);
      expect(
        userWith(AccountStatus.fromWire('brand_new_value')).isApproved,
        isFalse,
      );
    });
  });
}
