import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models.dart';
import 'family_detail_screen.dart' show eligibilityTone;
import 'providers.dart';

/// What a head of family sees: his own family, and nothing of the association's.
///
/// Deliberately NOT an AppScaffold. That widget carries the navigation bar, and
/// every destination on it is a screen he must not reach — the router refuses
/// him anyway, so offering the tabs and then bouncing him back would be a worse
/// interface than not offering them at all.
///
/// It reuses `api_family_detail` and `api_family_statement` rather than adding
/// portal-only endpoints. Both are SECURITY INVOKER, so the very call an admin
/// makes returns only what RLS allows THIS caller — one family. A separate
/// endpoint would be a second place for the scoping to be got wrong, and only
/// one of them would be covered by supabase/tests/45_family_portal.sql.
class FamilyPortalScreen extends ConsumerWidget {
  const FamilyPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final int? familyId = auth.user?.familyId;

    // The router guarantees this. Without it, the frame between redeeming a
    // code and the redirect landing would be a crash rather than a spinner.
    if (familyId == null) return const LoadingStateView();

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            l.myFamilyTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            auth.user?.familyCode ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      icon: const Icon(Icons.logout),
                      tooltip: l.signOut,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AsyncView<FamilyDetail>(
                  value: ref.watch(familyDetailProvider(familyId)),
                  onRetry: () => ref.invalidate(familyDetailProvider(familyId)),
                  builder: (FamilyDetail data) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(familyDetailProvider(familyId));
                      ref.invalidate(statementProvider(familyId));
                    },
                    child: _PortalBody(familyId: familyId, family: data),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalBody extends ConsumerWidget {
  const _PortalBody({required this.familyId, required this.family});

  final int familyId;
  final FamilyDetail family;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<Statement> statement = ref.watch(
      statementProvider(familyId),
    );
    final bool owes = (double.tryParse(family.debt) ?? 0) > 0;

    return ListView(
      padding: screenPadding(context),
      children: <Widget>[
        Text(
          l.myFamilyIntro,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),

        StatCardGrid(
          children: <Widget>[
            _Kpi(
              label: l.debt,
              value: formatMoney(family.debt),
              tone: owes ? AppColors.danger : AppColors.success,
            ),
            _Kpi(label: l.totalPaid, value: formatMoney(family.paid)),
            _Kpi(
              label: l.monthlyExpected,
              value: formatMoney(family.monthlyExpected),
            ),
            _Kpi(label: l.sonsCount, value: '${family.sonsCount}'),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),

        _SectionTitle(l.myMembersSection),
        if (family.father != null) _MemberTile(member: family.father!),
        for (final MemberView son in family.sons) _MemberTile(member: son),

        const SizedBox(height: AppSpacing.xl),
        _SectionTitle(l.myStatementSection),
        statement.when(
          loading: () => const LoadingStateView(),
          error: (Object error, StackTrace _) =>
              ErrorStateView(message: describeApiFailure(l, error)),
          data: (Statement data) => data.movements.isEmpty
              ? EmptyStateView(icon: Icons.receipt_long, title: l.noMovements)
              : Column(
                  children: <Widget>[
                    for (final StatementMovement m in data.movements)
                      _MovementTile(movement: m),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: tone ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final MemberView member;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  member.fullName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  member.age == null
                      ? member.nationalId
                      : l.ageYears(member.age!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          // The label comes from the database, not from here: lib/l10n has no
          // eligibility wording, and one spelling everywhere is the point.
          StatusBadge(
            label: member.eligibilityLabel,
            tone: eligibilityTone(member.eligibility),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final StatementMovement movement;

  @override
  Widget build(BuildContext context) {
    final String? credit = movement.credit;
    final bool isCredit = credit != null && credit.isNotEmpty;
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  movement.note.isEmpty ? movement.reference : movement.note,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${movement.date} • ${movement.reference}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(isCredit ? credit : movement.debit),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: isCredit ? AppColors.success : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
