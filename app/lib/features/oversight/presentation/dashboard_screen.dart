import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../directory/presentation/providers.dart';
import '../../finance/domain/models.dart';
import '../../finance/presentation/providers.dart';
import '../domain/models.dart';
import 'providers.dart';

/// The four stat cards, top debtors and approaching birthdays of index.html:448.
/// Every figure is computed by the server and verified against the prototype's
/// own `stats` object by the Phase 6 parity harness.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<DashboardData> dashboard = ref.watch(dashboardProvider);
    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navHome,
      currentRoute: AppRoutes.home,
      body: AsyncView<DashboardData>(
        value: dashboard,
        onRetry: () => ref.invalidate(dashboardProvider),
        builder: (DashboardData data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: ListView(
            padding: screenPadding(context),
            children: <Widget>[
              Text(
                l.dashboardIntro,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (role.atLeast(AppRole.financeManager)) ...<Widget>[
                FilledButton.icon(
                  onPressed: () =>
                      _closeMonth(context, ref, l, data.closingPeriod),
                  icon: const Icon(Icons.event_available, size: 18),
                  label: Text(l.closeMonth(data.closingPeriodLabel)),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              StatCardGrid(
                children: <Widget>[
                  _Stat(
                    label: l.statFamilies,
                    value: '${data.stats.families}',
                    sub: l.subSons(data.stats.sons),
                  ),
                  _Stat(
                    label: l.statEligibleSons,
                    value: '${data.stats.eligible}',
                    sub: l.subApproaching(data.stats.soon),
                    tone: AppColors.info,
                  ),
                  _Stat(
                    label: l.statTotalDebt,
                    value: formatMoney(data.stats.debt),
                    sub: l.subIndebtedFamilies(data.stats.indebtedFamilies),
                    tone: AppColors.danger,
                  ),
                  _Stat(
                    label: l.statTotalCollected,
                    value: formatMoney(data.stats.collected),
                    sub: l.subCashTransfer(
                      formatMoney(data.stats.cash),
                      formatMoney(data.stats.transfer),
                    ),
                    tone: AppColors.success,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              _Panel(
                title: l.topDebtors,
                child: data.topDebtors.isEmpty
                    ? EmptyStateView(
                        icon: Icons.verified_outlined,
                        title: l.noDebtsNow,
                      )
                    : Column(
                        children: <Widget>[
                          for (final DebtorRow debtor in data.topDebtors)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () => context.go(
                                '${AppRoutes.families}/${debtor.familyId}',
                              ),
                              title: Text(
                                debtor.fatherName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                debtor.familyCode,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              trailing: Text(
                                formatMoney(debtor.debt),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              _Panel(
                title: l.upcomingAlerts,
                child: data.upcomingSons.isEmpty
                    ? EmptyStateView(
                        icon: Icons.cake_outlined,
                        title: l.noAgeAlerts,
                      )
                    : Column(
                        children: <Widget>[
                          for (final UpcomingSon son in data.upcomingSons)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () => context.go(
                                '${AppRoutes.families}/${son.familyId}',
                              ),
                              title: Text(
                                son.sonName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                l.sonOf(son.fatherName),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              trailing: StatusBadge(
                                label: l.approachingBadge,
                                tone: AppColors.warning,
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _closeMonth(
  BuildContext context,
  WidgetRef ref,
  L l,
  String period,
) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => GlassDialog(
      title: Text(l.generateConfirmTitle(period)),
      content: Text(l.generateConfirmBody, style: const TextStyle(height: 1.5)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l.generateConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    final GenerateResultView result = await ref
        .read(financeRepositoryProvider)
        .generatePeriod(period);
    ref.invalidate(dashboardProvider);
    ref.invalidate(familiesProvider(''));
    ref.invalidate(receivablesProvider(''));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.created == 0
              ? l.nothingToGenerate
              : l.generateResult(result.created, result.skipped),
        ),
      ),
    );
  } on ApiException catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeApiFailure(l, failure))),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub, this.tone});

  final String label;
  final String value;
  final String? sub;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final Color accent = tone ?? AppColors.brand;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Flat Design's way of carrying meaning: a solid saturated bar,
              // no gradient, no shadow. It also encodes the tone for anyone who
              // cannot distinguish the value's colour, so hue is not the only
              // signal.
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: tone ?? AppColors.ink,
              ),
            ),
          ),
          if (sub != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(title: title, child: child);
  }
}
