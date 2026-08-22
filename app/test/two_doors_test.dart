import 'dart:io';

import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── بابان لا ثالث لهما ──────────────────────────────────────────────────────
///
/// «لا أريد كثرة صلاحيات، ولا موظف ولا زائر ولا غير ذلك. أريد فقط "أدمن"
///  و"عديل بمفتاح من الأدمن". غير ذلك امنع وصكّر واقفل أي شيء».
///
/// ⚠ WHAT HAPPENED. A member signed in with Google, was never asked for a code,
///   and opened the ASSOCIATION app under his own name. Six accounts sat at
///   role=viewer, status=approved, adeel_id=NULL — and `my_role()` handed the
///   role to any approved profile with no عديل binding. `viewer` was never «a
///   visitor who sees nothing»: it was the lowest STAFF rank, with the register
///   and the treasury behind it.
///
/// ⚠ THE RULE ITSELF LIVES IN POSTGRES, and it has to — the anon key ships
///   inside the APK, so a check in Dart is a suggestion. This file does not
///   re-implement it, and the route side is already pinned by `chat_test.dart`.
///   What is here is the pair of Dart-side facts that could let the hole back in
///   WITHOUT the database noticing, because neither is visible in review.
void main() {
  // ⚠ THE CREDENTIALS ARE OUT AND CANNOT BE PUT BACK. `run_emulator.bat`
  //   carries the password of a real approved admin and this repository is
  //   public; deleting the line leaves it in the git history. THAT hole closes
  //   by rotating the password, and nothing in Dart can close it — GoTrue
  //   accepts those credentials from curl with the public anon key, with no app
  //   involved.
  //
  //   What IS closable here is the second half: a shipped APK that offers a
  //   password field at all. The old guard was `bool.fromEnvironment`, and a
  //   --dart-define is set by whoever runs the build — that is configuration,
  //   not a guard. `kReleaseMode` is set by the compiler and cannot be passed
  //   in.
  //
  // ⚠ AND IT IS CHECKED BY READING THE SOURCE, like the RTL and base-table
  //   lints, because the value cannot be observed from inside a test: a test
  //   binary is a DEBUG build, so `devLoginEnabled` here reports what debug
  //   does and would pass however release behaved.
  test('the dev sign-in is gated on kReleaseMode, not only a --dart-define', () {
    final String src = File(
      'lib/core/supabase/supabase_config.dart',
    ).readAsStringSync();

    final int at = src.indexOf('devLoginEnabled');
    expect(at, greaterThan(-1), reason: 'devLoginEnabled has been renamed');

    final String decl = src.substring(at, src.indexOf(';', at));
    expect(
      decl.contains('kReleaseMode'),
      isTrue,
      reason:
          'devLoginEnabled must be false in a release build regardless of any '
          '--dart-define. Found: $decl',
    );
  });

  // ⚠ THE DISCRIMINATOR IS THE BINDING, NOT THE ROLE NAME, and that is the
  //   whole architecture: `my_role()` returns NULL the moment `adeel_id` is
  //   set, so a bound account fails every staff policy without one of them
  //   being edited. A test that asserted `role == viewer` would go on passing
  //   the day the roles collapsed to two — which is the day this patch landed.
  test('isAdeelPortal follows adeel_id, not the role name', () {
    const AppUser bound = AppUser(
      id: 'u1',
      email: 'a@b.c',
      displayName: 'عديل',
      role: AppRole.viewer,
      status: AccountStatus.approved,
      adeelId: 7,
    );
    const AppUser unbound = AppUser(
      id: 'u2',
      email: 'd@e.f',
      displayName: 'لا أحد',
      role: AppRole.viewer,
      status: AccountStatus.approved,
    );
    expect(bound.isAdeelPortal, isTrue);

    // ⚠ AND THIS IS THE ACCOUNT FROM THE INCIDENT — approved, viewer, no
    //   binding. It is NOT a portal account, so nothing in Dart pins it down;
    //   what stops it is `my_role()` returning NULL for anyone who is not an
    //   admin. The assertion records that this side cannot help, so nobody
    //   later mistakes the router guard for the thing holding the door.
    expect(unbound.isAdeelPortal, isFalse);
  });
}
