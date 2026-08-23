/// ── فتح مكالمة ─────────────────────────────────────────────────────────────
///
/// ⚠ THE MICROPHONE PERMISSION IS ASKED FOR BY getUserMedia ITSELF, at the
///   moment the handset is pressed and never at launch — a permission dialog
///   on a screen that is not asking for anything is the one people refuse, and
///   a refusal is remembered, so asking at the wrong moment costs the feature
///   permanently.
///
/// ⚠ AND NO permission_handler PACKAGE. It was added and taken back out: its
///   Android module fails to compile against this project's Gradle, and it was
///   buying nothing — flutter_webrtc raises the same system dialog, and a
///   denial arrives as a getUserMedia failure that CallSession already reports
///   as [CallPhase.micDenied]. A second package to ask a question the first
///   one already asks is a build to maintain for no answer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/realtime/doorbell.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../data/call_repository.dart';
import '../data/call_session.dart';
import '../domain/models.dart';
import 'providers.dart';

/// ⚠ A CALL THAT CANNOT START MUST SAY SO. Both entry points below post to
///   the server before any screen appears — start_call refuses anyone the
///   thread does not admit, and answer_call refuses the SECOND person to
///   press ردّ, which is a normal race rather than a fault. Without this the
///   failure was silent: the button was pressed, nothing opened, and nothing
///   said why.
void _report(ScaffoldMessengerState messenger, L l, Object error) {
  messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, error))));
}

/// Raise a call in [threadAdeelId] and open the in-call screen.
Future<void> startCall(
  BuildContext context,
  WidgetRef ref, {
  int? threadAdeelId,
  int? peerAdeelId,
}) async {
  final L l = L.of(context);
  // Captured BEFORE the await: after it the widget may be gone and the
  // context unusable — the same rule _generate() follows in receivables.
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final CallRepository repo = ref.read(callRepositoryProvider);

  final int id;
  try {
    id = await repo.start(
      threadAdeelId: threadAdeelId,
      peerAdeelId: peerAdeelId,
    );
  } on Object catch (e) {
    _report(messenger, l, e);
    return;
  }

  // ── ثم دُقّ الجرس ─────────────────────────────────────────────────────────
  // ⚠ THE FIRST FIVE SECONDS OF A SIXTY-SECOND RING ARE THE ONES THAT DECIDE
  //   whether he catches it, and the poll's two seconds are spent before the
  //   banner even appears. The ring carries no id and no name — it only says
  //   «ask now» — so every handset in the association runs the same
  //   authenticated read it would have run anyway, two seconds sooner.
  ref.read(doorbellProvider).ring(Ring.call);

  if (!context.mounted) return;

  // ⚠ NO «caller» FLAG ANY MORE. Who offers whom is arithmetic: the man with
  //   the larger participant id — the one who joined later — offers to
  //   everyone already in. Both sides compute it from the same two numbers,
  //   so there is nothing to agree on and no glare.
  await _open(
    context,
    ref,
    // ⚠ THE BELL GOES IN, so a hang-up on either handset reaches the other in
    //   about a tenth of a second instead of on its next beat. Optional by
    //   design — see CallSession — and the poll underneath is unchanged.
    CallSession(
      repository: repo,
      callId: id,
      doorbell: ref.read(doorbellProvider),
    ),
  );
}

/// Answer [call] and open the in-call screen.
Future<void> answerCall(
  BuildContext context,
  WidgetRef ref,
  CallView call,
) async {
  final L l = L.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final CallRepository repo = ref.read(callRepositoryProvider);

  // ⚠ ANSWERING IS JOINING. A two-person call is a mesh of two, so there is
  //   one verb for taking a seat and the group case is the general one — two
  //   verbs would be two code paths for the same act. join_call also turns
  //   «ترن» into «جارية» on the first seat taken.
  //
  // ⚠ AND IT CAN BE REFUSED FOR A GOOD REASON: the call ended while the
  //   banner was on screen, or the room is full. Both are ordinary, and both
  //   have to be said out loud rather than swallowed.
  // ⚠ THE TONE STOPS BEFORE THE REQUEST, not after it. join_call is a round
  //   trip, and on a Libyan mobile connection that is a second or two of the
  //   phone still ringing in his hand after he has answered it — which reads
  //   as a tap that did nothing. If the join then fails, the poll is three
  //   seconds away and starts it again.
  ref.read(incomingCallProvider.notifier).decided(call.id);

  try {
    await repo.join(call.id);
  } on Object catch (e) {
    _report(messenger, l, e);
    await ref.read(incomingCallProvider.notifier).refresh();
    return;
  }
  if (!context.mounted) return;

  await _open(
    context,
    ref,
    CallSession(
      repository: repo,
      callId: call.id,
      doorbell: ref.read(doorbellProvider),
    ),
  );
}

Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  CallSession session,
) async {
  ref.read(activeCallProvider.notifier).state = session;
  unawaited(session.open());

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext _) => _CallSheet(session: session),
  );

  await session.close();
  session.dispose();
  ref.read(activeCallProvider.notifier).state = null;
  unawaited(ref.read(incomingCallProvider.notifier).refresh());
}

/// هل تُغلق شاشةُ المكالمة نفسَها في هذا الطور؟
///
/// ── ⚠ LIFTED OUT FOR THE SAME REASON peersToOfferTo IS ──────────────────────
/// [_CallSheet] is private and reaching it needs a Navigator, a ProviderScope,
/// a live session and a microphone — so the DECISION would go untested, and it
/// is a decision that fails silently in both directions: too eager and a man
/// loses the screen telling him his microphone was refused; too shy and the
/// call «يبقي مفتوح عند الطرف الاخر الى ان يقفله بنفسه», which is what the
/// association reported.
///
/// ⚠ «انتهت» AND NOTHING ELSE. A failure and a refused microphone each want a
///   decision from him — check the signal, grant the permission — and a screen
///   that closed itself would take the question away with it. «يرنّ» and
///   «جارٍ الاتصال» are a call in progress; «متصل» is a call he is on.
@visibleForTesting
bool sheetDismissesItself(CallPhase phase) => phase == CallPhase.ended;

/// ── شاشة المكالمة ──────────────────────────────────────────────────────────
class _CallSheet extends StatefulWidget {
  const _CallSheet({required this.session});

  final CallSession session;

  @override
  State<_CallSheet> createState() => _CallSheetState();
}

class _CallSheetState extends State<_CallSheet> {
  bool _speaker = false;

  /// ⚠ LONG ENOUGH TO BE READ, SHORT ENOUGH NOT TO BE «still open».
  ///   «انتهت المكالمة» has to appear — see [_onPhase] — but it is a message,
  ///   not a screen he has to dismiss.
  static const Duration linger = Duration(milliseconds: 1200);

  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    widget.session.phase.addListener(_onPhase);
    // The call can already be over: the other man may have hung up while this
    // sheet was being built.
    _onPhase();
  }

  /// ── ⚠ «من قفل، يقفل على الاثنين» — THE HALF THAT WAS MISSING ─────────────
  ///
  ///   The rule was already enforced twice: leave_call ends a «جارية» call the
  ///   moment fewer than two live seats remain, and CallSession._tick closes
  ///   this handset on the same count. Both were working, and the association
  ///   still reported «يبقي الاتصال مفتوح عند الطرف الاخر الى ان يقفله بنفسه»
  ///   — because THE SHEET NEVER CLOSED ITSELF. The microphone was off, the
  ///   call was over, and the screen stayed until he pressed red.
  ///
  /// ⚠ THE OLD NOTE HERE DEFENDED THAT, and its reasoning is kept rather than
  ///   discarded: a screen that vanishes on its own leaves a man unsure whether
  ///   he hung up, was hung up on, or lost signal. So «انتهت المكالمة» is still
  ///   shown — for [linger] — and only then does the sheet go. The association
  ///   overruled the conclusion, not the concern.
  ///
  /// ⚠ ONLY ON «انتهت». A failure and a refused microphone each want a decision
  ///   from him — check the signal, grant the permission — and a screen that
  ///   closed itself would take the question away with it.
  void _onPhase() {
    if (!sheetDismissesItself(widget.session.phase.value)) return;
    // ⚠ Assign-if-null, so a second notification cannot schedule a second pop.
    _dismiss ??= Timer(linger, () {
      // mounted is the whole guard: the man may have pressed red himself, in
      // which case this sheet is already gone and popping again would take the
      // screen underneath it with it.
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    widget.session.phase.removeListener(_onPhase);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: GlassCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ValueListenableBuilder<CallPhase>(
            valueListenable: widget.session.phase,
            builder: (BuildContext context, CallPhase phase, _) {
              // ⚠ IT CLOSES ITSELF ON «انتهت» AND ON NOTHING ELSE — see
              //   [_CallSheetState._onPhase] for why, and for why a failure and
              //   a refused microphone deliberately stay on screen.
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    phase == CallPhase.talking
                        ? Icons.phone_in_talk
                        : Icons.phone,
                    size: 44,
                    color: switch (phase) {
                      CallPhase.talking => AppColors.success,
                      CallPhase.failed ||
                      CallPhase.micDenied => AppColors.danger,
                      CallPhase.ended => AppColors.muted,
                      _ => AppColors.brand,
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    switch (phase) {
                      CallPhase.connecting => l.callConnecting,
                      CallPhase.ringing => l.callRinging,
                      CallPhase.talking => l.callTalking,
                      CallPhase.ended => l.callEnded,
                      CallPhase.failed => l.callFailed,
                      CallPhase.micDenied => l.callMicDenied,
                    },
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── من على الخط ───────────────────────────────────────
                  // ⚠ NAMES, NOT A COUNT. «٣ مشاركين» tells a man the call is
                  //   busy; it does not tell him whether the person he needs
                  //   is on it — which is the only question anybody asks
                  //   before speaking. The list is the server's: a seat
                  //   unheard from for twenty seconds is simply not returned,
                  //   so nobody lingers on it after his phone died.
                  ValueListenableBuilder<List<CallParticipant>>(
                    valueListenable: widget.session.people,
                    builder:
                        (
                          BuildContext context,
                          List<CallParticipant> people,
                          _,
                        ) => Text(
                          people
                              .map((CallParticipant p) => p.displayName)
                              .join(ArabicPunctuation.listSeparator),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      ValueListenableBuilder<bool>(
                        valueListenable: widget.session.muted,
                        builder: (BuildContext context, bool muted, _) =>
                            _Round(
                              icon: muted ? Icons.mic_off : Icons.mic,
                              label: muted ? l.callUnmute : l.callMute,
                              on: muted,
                              onTap: widget.session.toggleMute,
                            ),
                      ),
                      _Round(
                        icon: _speaker ? Icons.volume_up : Icons.hearing,
                        label: l.callSpeaker,
                        on: _speaker,
                        onTap: () {
                          setState(() => _speaker = !_speaker);
                          unawaited(widget.session.setSpeaker(_speaker));
                        },
                      ),
                      _Round(
                        icon: Icons.call_end,
                        label: l.callHangUp,
                        tone: AppColors.danger,
                        on: true,
                        // ── ⚠ THE SESSION CLOSES BEFORE THE SHEET DOES ──────
                        //
                        //   This used to be pop() alone, and _open then did
                        //   «await showModalBottomSheet(...)» followed by
                        //   «await session.close()». That future does not
                        //   complete until the route's DISMISS ANIMATION has
                        //   finished — so leave_call, the one request that ends
                        //   the call for the other man, was not even sent until
                        //   this sheet had finished sliding off screen, and
                        //   then waited behind the media teardown as well.
                        //
                        //   Three delays stacked on one act. This removes the
                        //   first: the request goes out on the tap.
                        //
                        // ⚠ UNAWAITED, DELIBERATELY. A hang-up must never wait
                        //   on a network; close() stops the microphone itself
                        //   and is idempotent, so the «await session.close()»
                        //   in _open remains correct and becomes a no-op.
                        onTap: () {
                          unawaited(widget.session.close());
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.tone = AppColors.brand,
  });

  final IconData icon;
  final String label;
  final bool on;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton.filled(
          onPressed: onTap,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: on ? tone : tone.withValues(alpha: 0.12),
            foregroundColor: on ? AppColors.onFill : tone,
            minimumSize: const Size(56, 56),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// ── شريط «فلان يتصل» ───────────────────────────────────────────────────────
///
/// ⚠ A BANNER IN THE SCAFFOLD, NOT A DIALOG. A dialog would seize whatever
///   screen the man is on — mid-payment, mid-voucher — and a call is an
///   invitation, not an interruption that overrides an unsaved form. The banner
///   is impossible to miss and costs nothing to ignore.
class IncomingCallBanner extends ConsumerWidget {
  const IncomingCallBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final CallView? call = ref.watch(incomingCallProvider).valueOrNull;
    final CallSession? active = ref.watch(activeCallProvider);

    // Three separate ways there is nothing to show, and each is a real state:
    // no call at all, one I raised myself, or one I am already sitting in.
    //
    // ⚠ AND «جارية» IS OFFERED TOO, NOT ONLY «ترن». A group call in المجلس is
    //   live for as long as people are on it — a man who opens the app five
    //   minutes in must still be able to join, and a banner that only ever
    //   showed the first sixty seconds would make المجلس a call you can only
    //   catch at the start.
    //
    //   Safe now that v_calls ENDS a «جارية» call whose seats are all empty
    //   (PATCH_20260821i). Before that, an abandoned call stayed live forever
    //   and this would have offered it for ever after.
    if (call == null ||
        active != null ||
        call.mine ||
        (call.status != CallStatusWire.ringing &&
            call.status != CallStatusWire.active)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: GlassCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: <Widget>[
            const Icon(Icons.phone_callback, color: AppColors.brand),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                call.status == CallStatusWire.ringing
                    ? l.callIncoming(call.callerName)
                    : l.callOngoing(call.callerName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // ⚠ THE SIZE IS STATED, NOT INHERITED. This banner used to
                //   sit inside AppScaffold, under a Scaffold and a
                //   Material, and took its size from them; it now sits in
                //   MaterialApp.builder, above the Navigator, where what
                //   is in scope is whatever that builder happens to leave
                //   there. A widget that draws over EVERY screen must not
                //   depend on that — call_banner_root_test measures it at
                //   the root and fails if the size ever becomes somebody
                //   else's decision again.
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            // ⚠ ICON BUTTONS, AND THIS IS NOT A STYLE CHOICE. A FilledButton
            //   in this app is FULL WIDTH by theme — minimumSize is
            //   Size.fromHeight(52), which is Size(double.infinity, 52) — so
            //   putting one in a Row forces an infinite width and the layout
            //   ASSERTS. This banner lives in AppScaffold, which every screen
            //   builds, so that assert would have taken the whole app down the
            //   instant the first call rang. A widget test found it; nothing
            //   else would have, because no screen renders a call until one
            //   arrives.
            //
            //   IconButtons carry their own finite minimumSize and are what a
            //   call banner looks like anyway.
            // ── ⚠ SEMANTICS, NOT tooltip, AND THE REASON IS STRUCTURAL ──────
            //
            // `Tooltip` requires an `Overlay` ancestor, and the Overlay lives
            // inside the Navigator — which is BELOW this banner now that it
            // sits at the app root rather than inside AppScaffold. A tooltip
            // here throws «No Overlay widget found» the instant a call rings,
            // on whatever screen the man is on, and takes the app with it.
            //
            // Nothing was lost: a tooltip needs a long press on a phone and is
            // almost never seen, while `Semantics` reaches TalkBack — which is
            // the audience the label was for. See call_banner_root_test.
            Semantics(
              button: true,
              label: l.callDecline,
              child: IconButton.filled(
                onPressed: () async {
                  // Silence first, for the same reason as answering: the
                  // refusal is a round trip and he has already decided.
                  ref.read(incomingCallProvider.notifier).decided(call.id);
                  await ref
                      .read(callRepositoryProvider)
                      .end(call.id, declined: true);
                  await ref.read(incomingCallProvider.notifier).refresh();
                },
                icon: const Icon(Icons.call_end),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.onFill,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Semantics(
              button: true,
              label: l.callAnswer,
              child: IconButton.filled(
                onPressed: () => answerCall(context, ref, call),
                icon: const Icon(Icons.call),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.onFill,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
