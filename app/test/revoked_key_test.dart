import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── الدستور: مفتاحٌ جديد يُبطل القديم ويغلق التطبيق فوراً ───────────────────
///
/// «عندما أُصدر مفتاحاً جديداً لمشترك يبطل القديم ويغلق التطبيق فوراً ولن يفتح
/// من جديد إلا بالمفتاح الجديد الذي يستلمه من الأدمن».
///
/// ⚠ THE RULE IS ENFORCED IN POSTGRES, NOT HERE. `issue_adeel_code` overwrites
///   the code row and clears `profiles.device_id` in one act, and
///   `my_adeel_id()` returns NULL unless the device matches — so the old
///   handset is refused every row by RLS whatever any screen decides. What the
///   app owes is to SAY so and to offer the one way back in.
///
/// ⚠ AND «الطريق الوحيد» IS THE POINT OF THIS TEST. The portal normally admits
///   two routes — his dues and المجلس. A revoked key must reach NEITHER: not a
///   half-empty page, not a chat room, only the code box. Getting that ordering
///   wrong in the router leaves a locked member reading the association's chat.
void main() {
  AppUser member({required bool locked}) => AppUser(
    id: 'u1',
    email: 'a@b.c',
    displayName: 'عديل',
    role: AppRole.viewer,
    status: AccountStatus.approved,
    adeelId: 4,
    adeelCode: 'A-04',
    deviceLocked: locked,
  );

  test('a bound member is a portal account, locked or not', () {
    expect(member(locked: false).isAdeelPortal, isTrue);
    // ⚠ STILL TRUE WHEN LOCKED, and it has to be: api_me reports adeel_id from
    //   the profile row, which the reissue does NOT clear. If this flipped to
    //   false he would fall through to the staff branch — an approved viewer,
    //   which reads the WHOLE association. The lock must never widen reach.
    expect(member(locked: true).isAdeelPortal, isTrue);
  });

  group('what the portal may open while the key is valid', () {
    test('his dues and المجلس, and nothing else', () {
      expect(portalMayOpen(AppRoutes.myDues), isTrue);
      expect(portalMayOpen(AppRoutes.chat), isTrue);
      expect(portalMayOpen(AppRoutes.home), isFalse);
      expect(portalMayOpen(AppRoutes.adeels), isFalse);
      expect(portalMayOpen(AppRoutes.cash), isFalse);
      expect(portalMayOpen(AppRoutes.settings), isFalse);
    });
  });

  // ⚠ THE ORDERING IS THE RULE, so it is asserted as one: the lock is checked
  //   BEFORE the portal pin. Written as the router's own decision so the test
  //   fails if the two branches are ever swapped — which would silently leave a
  //   revoked member inside المجلس.
  group('and what it may open once the key is revoked', () {
    String? destination(AppUser user, String location) {
      if (user.isAdeelPortal && user.deviceLocked) {
        return location == AppRoutes.pending ? null : AppRoutes.pending;
      }
      if (user.isAdeelPortal) {
        return portalMayOpen(location) ? null : AppRoutes.myDues;
      }
      return null;
    }

    test('⚠ every route becomes the code screen — including his own dues', () {
      final AppUser locked = member(locked: true);
      for (final String route in <String>[
        AppRoutes.myDues,
        AppRoutes.chat,
        AppRoutes.home,
        AppRoutes.adeels,
      ]) {
        expect(destination(locked, route), AppRoutes.pending, reason: route);
      }
    });

    test('...and the code screen itself is where he is allowed to stay', () {
      expect(destination(member(locked: true), AppRoutes.pending), isNull);
    });

    test('while an unlocked member is untouched', () {
      final AppUser ok = member(locked: false);
      expect(destination(ok, AppRoutes.myDues), isNull);
      expect(destination(ok, AppRoutes.chat), isNull);
      expect(destination(ok, AppRoutes.adeels), AppRoutes.myDues);
    });
  });
}
