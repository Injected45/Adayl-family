import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/idle_auto_close.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// One proposal as a small card: whose it is and its title, nothing of what it
/// says. «تظهر الحاويات بشكل صغير تعرض اسم المشترك وعنوان المقترح».
///
/// The admin's card carries the member's name; a member's own card carries,
/// instead, where his proposal stands — the name on it would only ever be his.
class ProposalTile extends StatelessWidget {
  const ProposalTile({required this.proposal, required this.admin, super.key});

  final Proposal proposal;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      onTap: () => Navigator.of(
        context,
      ).push<void>(ProposalDetailScreen.route(proposal, admin: admin)),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (admin)
                  Text(
                    proposal.adeelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                Text(
                  proposal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (!admin) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            _StatusBadge(accepted: proposal.accepted),
          ],
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_left, size: 20, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.accepted});

  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return StatusBadge(
      label: accepted ? l.proposalAccepted : l.proposalPending,
      tone: accepted ? AppColors.success : AppColors.warning,
    );
  }
}

/// المقترح كاملًا، على الشاشة كلّها.
///
/// «ينقر الادمن على المقترح … ليفتح المقترح على الشاشه امامه و يقرأ ويستطيع ان
/// يستمر 30 ثانيه اذا فضل في حالة سكون يغلق. واذا فيه حركه ومشاهده … يظل معروض
/// ويمكن غلقه اجباري بيد الادمن». The same page, and the same clock, a notice
/// opens into — [IdleAutoClose].
///
/// ── THE ADMIN'S TWO DECISIONS ───────────────────────────────────────────────
/// On a proposal still waiting, and only there: «قبول» keeps it forever;
/// «رفض» asks once, then deletes it for everyone. An accepted proposal shows
/// neither — there is nothing left to decide, and nothing to reply with.
class ProposalDetailScreen extends ConsumerStatefulWidget {
  const ProposalDetailScreen({
    required this.proposal,
    this.admin = false,
    super.key,
  });

  final Proposal proposal;
  final bool admin;

  static const Duration idleFor = Duration(seconds: 30);

  static Route<void> route(Proposal proposal, {bool admin = false}) =>
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ProposalDetailScreen(proposal: proposal, admin: admin),
      );

  @override
  ConsumerState<ProposalDetailScreen> createState() =>
      _ProposalDetailScreenState();
}

class _ProposalDetailScreenState extends ConsumerState<ProposalDetailScreen> {
  bool _busy = false;

  Future<void> _decide({required bool accept}) async {
    final L l = L.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    if (!accept) {
      final bool? sure = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => GlassDialog(
          destructive: true,
          icon: const Icon(Icons.block),
          title: Text(l.proposalRejectTitle),
          content: Text(
            l.proposalRejectBody,
            style: const TextStyle(height: 1.5),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l.proposalReject),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final int id = widget.proposal.id;
      if (accept) {
        await ref.read(proposalsRepositoryProvider).accept(id);
      } else {
        await ref.read(proposalsRepositoryProvider).reject(id);
      }
      ref.invalidate(proposalsProvider);
      unawaited(ref.read(proposalsWaitingProvider.notifier).refresh());
      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accept ? l.proposalAcceptedDone : l.proposalRejectedDone,
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final Proposal p = widget.proposal;
    final bool decide = widget.admin && !p.accepted;

    return IdleAutoClose(
      idleFor: ProposalDetailScreen.idleFor,
      child: AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(l.proposalDetailTitle)),
          body: ListView(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl + bottomInset(context),
            ),
            children: <Widget>[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                          ),
                          child: Icon(
                            Icons.lightbulb_outline,
                            size: 24,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            p.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (widget.admin)
                          Text(
                            '${p.adeelName} · ${p.adeelCode}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.text,
                            ),
                          ),
                        Text(
                          formatDateTime(p.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        if (p.accepted || !widget.admin)
                          _StatusBadge(accepted: p.accepted),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      p.body,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.75,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // ⚠ STACKED, NEVER IN A ROW: buttons are full width in this theme.
              if (decide) ...<Widget>[
                FilledButton.icon(
                  onPressed: _busy ? null : () => _decide(accept: true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(l.proposalAccept),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _decide(accept: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.block),
                  label: Text(l.proposalReject),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              OutlinedButton(
                onPressed: () => unawaited(Navigator.of(context).maybePop()),
                child: Text(l.backAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
