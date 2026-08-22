import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/wire_values.dart';
import '../../../core/notify/notifier.dart';
import '../../../core/notify/notify_text.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/call_repository.dart';
import '../data/call_session.dart';
import '../domain/models.dart';

final Provider<CallRepository> callRepositoryProvider = Provider<CallRepository>(
  (Ref ref) => CallRepository(ref.watch(supabaseClientProvider)),
);

/// المكالمة الواردة — watched from every screen in the app.
///
/// ⚠ ITS OWN CLOCK, AND IT CANNOT RIDE THE BELL'S. The chat counters all watch
///   `chatUnreadProvider` and re-run when its VALUE changes — which works
///   because a new message changes the count. A call changes no count at all,
///   so a provider watching the bell would be built once and never asked
///   again. The one thing this must never do is fail to notice a ringing
///   phone.
///
/// ⚠ THREE SECONDS AGAINST A SIXTY-SECOND RING. The window is what makes this
///   affordable: the query is one row, capped, and the server has already
///   excluded every stale «ترن» — see v_calls. Missing a call because the poll
///   was slow is the one failure this feature cannot have.
///
/// AUTO-DISPOSED, and kept alive only by the widget in the app bar — so a
/// signed-out or pending account holds no timer at all.
final AutoDisposeAsyncNotifierProvider<IncomingCall, CallView?>
incomingCallProvider =
    AutoDisposeAsyncNotifierProvider<IncomingCall, CallView?>(IncomingCall.new);

class IncomingCall extends AutoDisposeAsyncNotifier<CallView?> {
  static const Duration interval = Duration(seconds: 3);

  Timer? _timer;
  bool _gone = false;

  @override
  Future<CallView?> build() async {
    // ⚠ NOBODY OUTSIDE THE ASSOCIATION IS RUNG. A pending applicant and a
    //   suspended account would otherwise poll a refusal every three seconds
    //   for as long as the app is open — and be offered a call they could not
    //   join if one ever came back.
    final AppUser? user = ref.watch(authControllerProvider).user;
    if (user == null || user.status != AccountStatus.approved) return null;

    ref.onDispose(() {
      _gone = true;
      _timer?.cancel();
      _timer = null;
    });
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));

    return ref.read(callRepositoryProvider).liveAny();
  }

  Future<void> _tick() async {
    try {
      final CallView? call = await ref.read(callRepositoryProvider).liveAny();
      if (_gone) return;
      _notify(call);
      state = AsyncValue<CallView?>.data(call);
    } on Object {
      // A failed poll leaves the previous answer standing. Dropping a ringing
      // call to null because one request timed out would hang up on somebody.
    }
  }

  /// ── الرنين وهو في الخلفية ─────────────────────────────────────────────
  ///
  /// ⚠ THE BANNER IS NOT ENOUGH, and that is the whole of what the
  ///   association asked for: «اريد التطبيق يشتغل في الخلفية بحيث لما حد يرن
  ///   يصل الرنين وينتبه». A banner is a thing you see if you are already
  ///   looking; a notification is what reaches a phone in a pocket.
  ///
  /// ⚠ ONLY ON THE EDGE, never on every tick. This runs every three seconds;
  ///   re-posting the same notification each time would re-alert the phone
  ///   twenty times a minute for one call. `_ringing` is the id it last
  ///   announced, so a call is announced once and cleared once.
  int? _ringing;

  void _notify(CallView? call) {
    final bool live =
        call != null &&
        !call.mine &&
        (call.status == CallStatusWire.ringing ||
            call.status == CallStatusWire.active);

    if (!live) {
      if (_ringing != null) {
        _ringing = null;
        unawaited(AppNotifier.clearCall());
      }
      return;
    }
    if (_ringing == call.id) return;
    _ringing = call.id;
    unawaited(
      AppNotifier.ringing(call.callerName, NotifyText.incomingCall),
    );
  }

  /// Ask again now — after answering, declining or hanging up, so the banner
  /// goes without waiting out the interval.
  Future<void> refresh() => _tick();
}

/// من يمكن الاتصال به — قائمة الأسماء.
///
/// ⚠ AUTO-DISPOSED AND UNPOLLED. It is read when the screen opens and thrown
///   away when it closes: a directory of eight names does not change while a
///   man is looking at it, and a fourth timer for a list nobody watches is
///   the cost this app has been careful about all along.
final AutoDisposeFutureProvider<List<CallPeer>> callDirectoryProvider =
    AutoDisposeFutureProvider<List<CallPeer>>(
      (Ref ref) => ref.watch(callRepositoryProvider).directory(),
    );

/// The call this handset is actually on, if any.
///
/// ⚠ A SESSION, NOT A ROW. [CallSession] owns the microphone, the peer
///   connection and the signalling poll; putting it in a provider is what lets
///   the in-call screen be opened, closed and reopened without the call
///   dropping — and what guarantees exactly one microphone is ever live,
///   because there is exactly one slot for it.
final StateProvider<CallSession?> activeCallProvider =
    StateProvider<CallSession?>((Ref ref) => null);
