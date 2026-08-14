import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRole', () {
    test('parses every role the server can send', () {
      expect(AppRole.fromWire('admin'), AppRole.admin);
      expect(AppRole.fromWire('financeManager'), AppRole.financeManager);
      expect(AppRole.fromWire('treasurer'), AppRole.treasurer);
      expect(AppRole.fromWire('viewer'), AppRole.viewer);
    });

    test('falls back to the LEAST privileged role, never the most', () {
      // A newer server introducing a role this build has never heard of must
      // not accidentally grant administrator access.
      expect(AppRole.fromWire('superuser'), AppRole.viewer);
      expect(AppRole.fromWire(null), AppRole.viewer);
      expect(AppRole.fromWire(''), AppRole.viewer);
    });

    test('hierarchy is admin > financeManager > treasurer > viewer', () {
      expect(AppRole.admin.atLeast(AppRole.financeManager), isTrue);
      expect(AppRole.financeManager.atLeast(AppRole.treasurer), isTrue);
      expect(AppRole.treasurer.atLeast(AppRole.viewer), isTrue);

      expect(AppRole.treasurer.atLeast(AppRole.financeManager), isFalse);
      expect(AppRole.viewer.atLeast(AppRole.treasurer), isFalse);
    });
  });

  group('AccountStatus', () {
    test('an unrecognised status is treated as pending, not approved', () {
      expect(AccountStatus.fromWire('who-knows'), AccountStatus.pending);
      expect(AccountStatus.fromWire(null), AccountStatus.pending);
    });
  });

  group('AppUser', () {
    test('parses the server payload', () {
      final AppUser user = AppUser.fromJson(<String, dynamic>{
        // A uuid: identity is auth.users.id now, not a bigint.
        'id': '00000000-0000-0000-0000-000000000007',
        'email': 'treasurer@example.test',
        'displayName': 'أمين الصندوق',
        'pictureUrl': null,
        'role': 'treasurer',
        'status': 'approved',
      });

      expect(user.id, '00000000-0000-0000-0000-000000000007');
      expect(user.displayName, 'أمين الصندوق');
      expect(user.role, AppRole.treasurer);
      expect(user.isApproved, isTrue);
    });

    test('survives missing optional fields', () {
      final AppUser user = AppUser.fromJson(<String, dynamic>{
        'id': '00000000-0000-0000-0000-000000000001',
        'role': 'admin',
        'status': 'approved',
      });
      expect(user.email, '');
      expect(user.pictureUrl, isNull);
    });
  });

  group('Session', () {
    test('parses a sign-in response', () {
      final Session session = Session.fromJson(<String, dynamic>{
        'accessToken': 'header.payload.signature',
        'refreshToken': 'opaque-refresh',
        'expiresIn': 900,
        'user': <String, dynamic>{
          'id': '00000000-0000-0000-0000-000000000001',
          'email': 'first@example.test',
          'displayName': 'المسؤول الأول',
          'role': 'admin',
          'status': 'approved',
        },
      });

      expect(session.accessToken, 'header.payload.signature');
      expect(session.refreshToken, 'opaque-refresh');
      expect(session.user.role, AppRole.admin);
    });
  });
}
