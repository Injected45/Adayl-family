import 'dart:io';

import 'package:family_app/core/domain/wire_values.dart';
import 'package:family_app/core/realtime/doorbell.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/call/data/call_repository.dart';
import 'package:family_app/features/call/data/call_ringtone.dart';
import 'package:family_app/features/call/domain/models.dart';
import 'package:family_app/features/call/presentation/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// ⚠ الرنينُ توقّف عن الوصول، والساعةُ لم تكن السبب.
///
///   The association reported it three times and each time the interval came
///   down — three seconds, two, one — and each time it changed NOTHING,
///   because the clock was never what was broken.
///
///   IncomingCall.build() watches authControllerProvider. AutoRefresh calls
///   refreshProfile() every forty-five seconds, and refreshProfile assigns a
///   NEW AuthState — the class carries no operator ==, so the assignment always
///   emits. Riverpod then re-runs build() ON THE SAME NOTIFIER OBJECT, firing
///   the previous build's onDispose first — which set `_gone = true`, a field
///   build() never cleared.
///
///   From that moment the poll went on running perfectly, fetched the ringing
///   call every second, and threw the answer away at `if (_gone) return`. The
///   banner was left with exactly one source of truth: build()'s own return
///   value. So a ringing phone reached the other handset up to forty-five
///   seconds later, at a moment unrelated to the call.
///
/// ⚠ AND NOTHING WOULD HAVE CAUGHT IT. There is no error, no exception, no
///   failed request — a correct answer is fetched and discarded. It is
///   invisible to the analyzer, to a widget test that pumps once, and to any
///   test that reads the provider WITHOUT first making it rebuild. That last
///   clause is the whole design of this file: the rebuild is the test.
class _FakeRepo extends CallRepository {
  _FakeRepo() : super(SupabaseClient('http://127.0.0.1:1', 'anon'));

  CallView? answer;
  int reads = 0;

  @override
  Future<CallView?> liveAny() async {
    reads++;
    return answer;
  }
}

CallView _ringing(int id) => CallView.fromJson(<String, dynamic>{
  'id': id,
  'threadAdeelId': null,
  'callerName': 'هيثم مفتاح',
  'mine': false,
  'status': CallStatusWire.ringing,
  'startedAt': '2026-08-26T09:00:00Z',
  'answeredAt': null,
  'endedAt': null,
  'peerAdeelId': 3,
});

const AppUser _member = AppUser(
  id: '00000000-0000-0000-0000-0000000000b1',
  email: 'adeel@fam.test',
  displayName: 'أيمن صالح بلها',
  role: AppRole.viewer,
  status: AccountStatus.approved,
  adeelId: 6,
);

/// An auth controller that can be made to emit, exactly as refreshProfile does.
class _Auth extends AuthController {
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _member);

  /// ⚠ A NEW OBJECT EVERY TIME, and that is not a contrivance — it is what
  ///   refreshProfile() does on the real forty-five-second tick, and AuthState
  ///   carries no operator == so Riverpod treats every assignment as a change.
  void reemit() => state = AuthState(stage: AuthStage.signedIn, user: _member);
}

void main() {
  // ⚠ THE RING AND THE NOTIFICATION BOTH REACH FOR A PLATFORM CHANNEL, and
  //   _notify runs on the SAME tick the state is set on. Without a binding the
  //   channel throws before the assignment — which would fail this test for a
  //   reason that has nothing to do with what it guards.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('⚠ النبضُ يظلّ يعمل بعد إعادة البناء — لا يتجمّد الرنين', () async {
    final _FakeRepo repo = _FakeRepo();
    final _Auth auth = _Auth();

    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        callRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => auth),
        // ⚠ The bell must not reach for a socket in a test — and the whole
        //   point of this poll is that it is correct WITHOUT one.
        doorbellProvider.overrideWithValue(_DeafBell()),
        callRingtoneProvider.overrideWithValue(_MuteTone()),
      ],
    );
    addTearDown(c.dispose);

    // Kept alive the way the banner keeps it alive in the real app.
    final ProviderSubscription<AsyncValue<CallView?>> sub = c.listen(
      incomingCallProvider,
      (AsyncValue<CallView?>? a, AsyncValue<CallView?> b) {},
    );
    addTearDown(sub.close);

    await c.read(incomingCallProvider.future);
    expect(c.read(incomingCallProvider).value, isNull);

    // ── الحدث: نبضةُ التحديث تُعيد إصدار حالة الدخول ──────────────────────
    // This is the forty-five-second tick, and nothing more than that.
    auth.reemit();
    await c.read(incomingCallProvider.future);

    // Now somebody calls. The poll is what has to find it.
    repo.answer = _ringing(77);
    final int before = repo.reads;

    await c.read(incomingCallProvider.notifier).refresh();

    expect(
      repo.reads,
      greaterThan(before),
      reason: 'the poll must still be ASKING after a rebuild',
    );
    expect(
      c.read(incomingCallProvider).value?.id,
      77,
      reason:
          '⚠ THE WHOLE BUG IN ONE LINE. Without the fix the call IS fetched — '
          'reads goes up — and then dropped on the floor by a flag the '
          'previous build set and this one never cleared. The banner stays '
          'null, the phone stays silent, and every interval anybody lowers '
          'changes nothing at all.',
    );
  });

  test('⚠ نبضتان متتاليتان لا تتزاحمان', () async {
    final _FakeRepo repo = _FakeRepo();

    final ProviderContainer c = ProviderContainer(
      overrides: <Override>[
        callRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(_Auth.new),
        doorbellProvider.overrideWithValue(_DeafBell()),
        callRingtoneProvider.overrideWithValue(_MuteTone()),
      ],
    );
    addTearDown(c.dispose);

    final ProviderSubscription<AsyncValue<CallView?>> sub = c.listen(
      incomingCallProvider,
      (AsyncValue<CallView?>? a, AsyncValue<CallView?> b) {},
    );
    addTearDown(sub.close);

    await c.read(incomingCallProvider.future);
    final IncomingCall n = c.read(incomingCallProvider.notifier);
    final int before = repo.reads;

    // ⚠ TWO AT ONCE IS WHAT A SLOW CONNECTION PRODUCES: the clock fires again
    //   before the previous request has landed. Without the in-flight guard
    //   both go out, and the LAST to arrive decides what the banner shows —
    //   which can be the older answer.
    await Future.wait<void>(<Future<void>>[n.refresh(), n.refresh()]);

    expect(
      repo.reads - before,
      1,
      reason: 'a second request while one is in flight must be declined',
    );
  });

  test('⚠ الجرس يترجم الأنواع الثلاثة كلَّها', () {
    // ⚠ ACCESS WAS MISSING AT THE EAR while being broadcast at the mouth, so
    //   a revoked handset went on showing his dues until the forty-five-second
    //   tick — the exact delay the ring exists to remove. A switch whose
    //   default arm returns null loses a whole feature without one error.
    final String src = File(
      'lib/core/realtime/doorbell.dart',
    ).readAsStringSync();
    for (final String kind in <String>['chat', 'call', 'access']) {
      expect(
        src.contains("'$kind' => Ring.$kind,"),
        isTrue,
        reason: 'Ring.$kind is rung somewhere and must be heard',
      );
    }
  });
}

/// A bell that is never connected — which is the state every test runs in, and
/// a state the real app must survive.
class _DeafBell implements Doorbell {
  @override
  bool connected = false;
  @override
  void ring(Ring kind) {}
  @override
  void start() {}
  @override
  Future<void> stop() async {}
  @override
  VoidCallback listen(void Function(Ring) onRing) => () {};
}

/// نغمةٌ صامتة — تسجيل القرار دون قناةٍ للمنصّة.
class _MuteTone implements CallRingtone {
  @override
  bool get isRinging => false;
  @override
  Future<void> start() async {}
  @override
  Future<void> startRingback() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> play({String asset = CallRingtone.receiverAsset}) async {}
  @override
  void dispose() {}
}
