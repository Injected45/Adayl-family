import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/notify/notifier.dart';
import '../../../core/router/destinations.dart';
import '../../../core/state/refresh.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../notifications/presentation/providers.dart';
import '../domain/models.dart';
import 'proposal_detail_screen.dart';
import 'providers.dart';

/// مقترحات المشتركين — the admin's tab.
///
/// Every proposal as a small card, name and title. Those still waiting come
/// first, because they are the ones asking for something; the accepted ones
/// follow, kept for as long as the association exists «للرجوع اليها في اي
/// وقت». A rejected proposal is not here — it no longer exists anywhere.
class ProposalsScreen extends ConsumerStatefulWidget {
  const ProposalsScreen({super.key});

  @override
  ConsumerState<ProposalsScreen> createState() => _ProposalsScreenState();
}

class _ProposalsScreenState extends ConsumerState<ProposalsScreen> {
  /// ⚠ CAPTURED, and cleared after the frame — the notices' tab learned why.
  late final StateController<bool> _open;

  @override
  void initState() {
    super.initState();
    _open = ref.read(proposalsScreenOpenProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _open.state = true;
      // He is looking at them: the phone's alert and the banner have said
      // what they came to say.
      unawaited(AppNotifier.clearProposals());
      if (ref.read(noticePeekProvider)?.route == AppRoutes.proposals) {
        ref.read(noticePeekProvider.notifier).dismiss();
      }
    });
  }

  @override
  void dispose() {
    final StateController<bool> open = _open;
    Future<void>.microtask(() {
      if (open.mounted) open.state = false;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return AppScaffold(
      title: l.proposalsTitle,
      currentRoute: AppRoutes.proposals,
      body: (BuildContext context) => RefreshIndicator(
        onRefresh: () async => refreshAll(ref),
        child: AsyncView<List<Proposal>>(
          value: ref.watch(proposalsProvider),
          onRetry: () => ref.invalidate(proposalsProvider),
          builder: (List<Proposal> all) {
            final List<Proposal> waiting = <Proposal>[
              for (final Proposal p in all)
                if (!p.accepted) p,
            ];
            final List<Proposal> accepted = <Proposal>[
              for (final Proposal p in all)
                if (p.accepted) p,
            ];

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xl + bottomInset(context),
              ),
              children: <Widget>[
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xl),
                    child: ProposalsEmpty(text: l.proposalsEmpty),
                  ),
                if (waiting.isNotEmpty) ...<Widget>[
                  _Heading(text: l.proposalsWaitingHeading(waiting.length)),
                  for (final Proposal p in waiting)
                    ProposalTile(
                      key: ValueKey<int>(p.id),
                      proposal: p,
                      admin: true,
                    ),
                ],
                if (accepted.isNotEmpty) ...<Widget>[
                  if (waiting.isNotEmpty) const SizedBox(height: AppSpacing.lg),
                  _Heading(text: l.proposalsAcceptedHeading(accepted.length)),
                  for (final Proposal p in accepted)
                    ProposalTile(
                      key: ValueKey<int>(p.id),
                      proposal: p,
                      admin: true,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: AppSpacing.xs,
      bottom: AppSpacing.sm,
    ),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class ProposalsEmpty extends StatelessWidget {
  const ProposalsEmpty({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(AppRadius.pane),
        ),
        child: Icon(
          Icons.lightbulb_outline,
          size: 30,
          color: AppColors.brandDeep,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );
}
