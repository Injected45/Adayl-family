import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/state/refresh.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'call_ui.dart';
import 'providers.dart';

/// «اتصال بعديل» — من أتصل به، ولا شيء غير ذلك.
///
/// ── لماذا هذه الشاشة موجودة ────────────────────────────────────────────────
/// A member has no register. He can reach his own dues and المجلس, and that is
/// the whole of the portal — so before he can ring another man he needs
/// somewhere to find him. `api_call_directory` answers exactly that question
/// and nothing adjacent to it.
///
/// ⚠ NAMES AND CODES, NEVER FIGURES. What the association refused, when it
///   turned down «أسلاف للغير» by name, was MONEY against a name. Identity was
///   never the objection — المجلس has always shown every member every other
///   member's name and words. A phone number, a balance or a debt on this
///   screen would be the thing they actually said no to.
///
/// ⚠ AND ONLY MEN WHOSE APP IS BOUND TO A HANDSET are listed. The server does
///   that filtering, not this screen: offering a call to somebody who has never
///   redeemed his key is offering a call that rings in an empty room, and the
///   caller would blame the app rather than the absence.
class CallDirectoryScreen extends ConsumerWidget {
  const CallDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.callDirectoryTitle)),
        body: RefreshIndicator(
          // The whole app, not this provider: a member has no ⟳ button
          // anywhere, so the pull is his only refresh and it has to be complete.
          onRefresh: () async => refreshAll(ref),
          child: AsyncView<List<CallPeer>>(
            value: ref.watch(callDirectoryProvider),
            onRetry: () => ref.invalidate(callDirectoryProvider),
            builder: (List<CallPeer> peers) {
              if (peers.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: <Widget>[
                    const SizedBox(height: AppSpacing.xl * 2),
                    // ⚠ SAYS WHY, not «لا يوجد». An empty list here almost
                    //   always means the other men have not redeemed their keys
                    //   yet — which is something the admin can act on, and a
                    //   bare emptiness is not.
                    EmptyStateView(
                      icon: Icons.person_off_outlined,
                      title: l.callDirectoryEmpty,
                    ),
                  ],
                );
              }

              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: peers.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (BuildContext context, int i) =>
                    _PeerRow(peer: peers[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PeerRow extends ConsumerWidget {
  const _PeerRow({required this.peer});

  final CallPeer peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        // The code in his own colour, the way it is everywhere else — one man,
        // one tone, whatever screen he appears on.
        leading: CircleAvatar(
          backgroundColor: AppColors.identityTone(peer.adeelId),
          child: Text(
            peer.code,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.onFill,
            ),
          ),
        ),
        title: Text(
          peer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        // ⚠ AN ICON BUTTON, NOT A FILLED ONE. A FilledButton is full width in
        //   this theme — Size.fromHeight(52) — so one inside a ListTile's
        //   trailing row forces an infinite width and asserts. That took a
        //   screen down once already; see the incoming-call banner.
        trailing: IconButton.filled(
          onPressed: () => unawaited(
            startCall(context, ref, peerAdeelId: peer.adeelId),
          ),
          tooltip: l.callStart,
          icon: const Icon(Icons.call),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: AppColors.onFill,
          ),
        ),
      ),
    );
  }
}
