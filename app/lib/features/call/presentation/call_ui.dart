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
import '../../../l10n/app_localizations.dart';
import '../data/call_repository.dart';
import '../data/call_session.dart';
import '../domain/models.dart';
import 'providers.dart';



/// Raise a call in [threadAdeelId] and open the in-call screen.
Future<void> startCall(
  BuildContext context,
  WidgetRef ref,
  int? threadAdeelId,
) async {
  final CallRepository repo = ref.read(callRepositoryProvider);
  final int id = await repo.start(threadAdeelId);
  if (!context.mounted) return;

  // ⚠ NO «caller» FLAG ANY MORE. Who offers whom is arithmetic: the man with
  //   the larger participant id — the one who joined later — offers to
  //   everyone already in. Both sides compute it from the same two numbers,
  //   so there is nothing to agree on and no glare.
  await _open(context, ref, CallSession(repository: repo, callId: id));
}

/// Answer [call] and open the in-call screen.
Future<void> answerCall(
  BuildContext context,
  WidgetRef ref,
  CallView call,
) async {
  final CallRepository repo = ref.read(callRepositoryProvider);
  // ⚠ ANSWERING IS JOINING. A two-person call is a mesh of two, so there is
  //   one verb for taking a seat and the group case is the general one — two
  //   verbs would be two code paths for the same act. join_call also turns
  //   «ترن» into «جارية» on the first seat taken.


  await _open(
    context,
    ref,
    CallSession(repository: repo, callId: call.id),
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

/// ── شاشة المكالمة ──────────────────────────────────────────────────────────
class _CallSheet extends StatefulWidget {
  const _CallSheet({required this.session});

  final CallSession session;

  @override
  State<_CallSheet> createState() => _CallSheetState();
}

class _CallSheetState extends State<_CallSheet> {
  bool _speaker = false;

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
              // ⚠ THE SHEET CLOSES ITSELF ONLY ON A FAILURE, never on «ended».
              //   A call that the other side hung up leaves «انتهت المكالمة» on
              //   screen until it is dismissed: a sheet that vanished on its own
              //   would leave the man unsure whether he hung up or lost signal.
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
                      CallPhase.failed || CallPhase.micDenied =>
                        AppColors.danger,
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
                        onTap: () => Navigator.of(context).pop(),
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
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
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

    // Not ringing, mine, or already on it — three separate ways there is
    // nothing to show, and each of them is a real state.
    if (call == null ||
        active != null ||
        call.mine ||
        call.status != CallStatusWire.ringing) {
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
                l.callIncoming(call.callerName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: () async {
                await ref
                    .read(callRepositoryProvider)
                    .end(call.id, declined: true);
                await ref.read(incomingCallProvider.notifier).refresh();
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(l.callDecline),
            ),
            FilledButton(
              onPressed: () => answerCall(context, ref, call),
              child: Text(l.callAnswer),
            ),
          ],
        ),
      ),
    );
  }
}
