import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/domain/wire_values.dart';
import '../../../core/notify/notifier.dart';
import '../../../core/notify/notify_text.dart';
import '../../../core/realtime/doorbell.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/call_repository.dart';
import '../data/call_ringtone.dart';
import '../data/call_session.dart';
import '../domain/models.dart';

final Provider<CallRepository> callRepositoryProvider = Provider<CallRepository>(
  (Ref ref) => CallRepository(ref.watch(supabaseClientProvider)),
);

/// نغمة الرنين — واحدة للتطبيق كلّه.
///
/// ⚠ NOT AUTO-DISPOSED, and that is the point. A tone that loops has to be
///   stoppable by whoever notices the call ended, and the object holding the
///   platform player must outlive the banner that started it — a disposed
///   provider would drop the only reference to a player still sounding.
final Provider<CallRingtone> callRingtoneProvider = Provider<CallRingtone>((
  Ref ref,
) {
  final CallRingtone tone = CallRingtone();
  ref.onDispose(tone.dispose);
  return tone;
});

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
  /// ⚠ TWO SECONDS, AND THE REAL FIX FOR «تأخير كثير جدا في ظهور المتصل» WAS
  ///   NOT THIS NUMBER. The banner lived inside AppScaffold, and the عديل
  ///   portal is deliberately not an AppScaffold — so on the one screen a
  ///   member actually sits on, this provider had no watcher, was disposed, and
  ///   POLLED NOTHING AT ALL. A call to him appeared only if he wandered into
  ///   المجلس. See app.dart, where the banner now sits above the whole app.
  ///
  ///   Two rather than three is the smaller half of the same complaint: the
  ///   query is one capped row and the server has already excluded every stale
  ///   «ترن», so the cost of asking more often is close to nothing, and
  ///   missing a call is the one failure this feature cannot have.
  static const Duration interval = Duration(seconds: 2);

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

    // ── والجرس ────────────────────────────────────────────────────────
    // ⚠ A RING HAS SIXTY SECONDS TO BE NOTICED AND THE FIRST FIVE ARE THE
    //   ONES THAT MATTER — a man who looks at his phone two seconds after it
    //   started is the ordinary case, not the lucky one. The clock above is
    //   the guarantee; this is the difference between «it rang» and «it rang
    //   the moment he called».
    final VoidCallback deafenCall = ref.read(doorbellProvider).listen((Ring r) {
      if (r == Ring.call) unawaited(_tick());
    });
    ref.onDispose(deafenCall);

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

  /// المكالمة التي قرّر فيها — ردّاً أو رفضاً.
  ///
  /// ⚠ WITHOUT THIS THE POLL UNDOES THE ANSWER, and the pre-emptive silence in
  ///   [decided] defeats itself. Pressing ردّ runs: silence the tone → `await
  ///   join()` (a round trip, one or two seconds on a Libyan connection) →
  ///   `_open()` sets activeCallProvider. A tick landing in that gap sees a
  ///   call that is still live and an activeCallProvider that is still null —
  ///   so it STARTS THE TONE AGAIN and re-posts the notification, on a call the
  ///   man has already answered. He hears his own phone ring into the
  ///   conversation.
  ///
  ///   The id is remembered rather than a bare flag, so the NEXT call still
  ///   rings: a decision belongs to one call, not to the handset.
  int? _decided;

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
      // The decision dies with the call it was about.
      _decided = null;
      // ⚠ STOPPED UNCONDITIONALLY, outside the `_ringing != null` guard. That
      //   flag tracks the NOTIFICATION, and the tone can be sounding when it is
      //   null — answering sets it null through [answered] while the call is
      //   still live and still returned by the poll. Tying the stop to the
      //   notification would leave the phone ringing through the conversation.
      unawaited(ref.read(callRingtoneProvider).stop());
      return;
    }

    // ── والصوت ─────────────────────────────────────────────────────────────
    // ⚠ THE NOTIFICATION IS NOT A RINGTONE, and that is what «تري رنين فقط لا
    //   تسمع اي صوت» was. A posted notification plays its channel's sound
    //   once — a fifth of a second — and Android may drop even that when the
    //   notification carries a full-screen intent, because it expects the
    //   screen it takes over to do the ringing. Nothing was doing it.
    //
    // ⚠ AND NOT WHILE HE IS ALREADY ON A CALL. The poll returns a «جارية» call
    //   the moment he joins one, so ringing on `live` alone would sound the
    //   tone into his own conversation for as long as it lasted.
    // ⚠ AND NOT ON A CALL HE HAS ALREADY DECIDED. See [_decided]: the answer
    //   and the seat are two round trips apart, and the poll runs between them.
    if (_decided == call.id) return;

    if (ref.read(activeCallProvider) == null) {
      unawaited(ref.read(callRingtoneProvider).start());
    }

    if (_ringing == call.id) return;
    _ringing = call.id;
    unawaited(
      AppNotifier.ringing(call.callerName, NotifyText.incomingCall),
    );
  }

  /// ردّ، أو رفض — فيسكت الرنين فوراً ولا يعود.
  ///
  /// ⚠ CALLED BY THE UI RATHER THAN INFERRED HERE, because the poll cannot see
  ///   the decision: the call stays «جارية» and stays returned for as long as
  ///   anybody is on it. Waiting for the row to change would ring through the
  ///   first seconds of every answered call.
  ///
  /// ⚠ AND IT TAKES THE ID, because silencing alone was not enough — the next
  ///   tick simply started the tone again. See [_decided].
  void decided(int callId) {
    _decided = callId;
    _ringing = null;
    unawaited(ref.read(callRingtoneProvider).stop());
    unawaited(AppNotifier.clearCall());
  }

  /// ⚠ VISIBLE, AND CALLED BY THE TESTS, for the same reason ChatChime.play
  ///   is: the DECISION is what is worth pinning and the poll around it needs
  ///   a network. call_answer_gap_test drives this directly to reproduce the
  ///   window between «ردّ» and the seat being taken.
  @visibleForTesting
  void notifyForTest(CallView? call) => _notify(call);

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
