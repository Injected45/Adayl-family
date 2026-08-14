import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final String type = ref.watch(alertTypeProvider);
    final AsyncValue<List<AlertItem>> alerts = ref.watch(alertsProvider(type));
    // Populated from the unfiltered list so the chips do not vanish once a
    // filter is applied.
    final AsyncValue<List<AlertItem>> all = ref.watch(alertsProvider(''));
    final List<String> types = <String>{
      ...(all.valueOrNull ?? <AlertItem>[]).map((AlertItem a) => a.type),
    }.toList();

    return AppScaffold(
      title: l.navAlerts,
      currentRoute: AppRoutes.alerts,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.alertsIntro,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      ChoiceChip(
                        label: Text(l.allTypes),
                        selected: type.isEmpty,
                        onSelected: (_) =>
                            ref.read(alertTypeProvider.notifier).state = '',
                      ),
                      for (final String option in types) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        ChoiceChip(
                          label: Text(option),
                          selected: type == option,
                          onSelected: (_) =>
                              ref.read(alertTypeProvider.notifier).state =
                                  option,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<AlertItem>>(
              value: alerts,
              onRetry: () => ref.invalidate(alertsProvider(type)),
              builder: (List<AlertItem> items) {
                if (items.isEmpty) {
                  // An empty alert list is a good outcome, so it reads as
                  // reassurance rather than as an absence.
                  return EmptyStateView(
                    icon: Icons.verified_outlined,
                    title: l.noAlerts,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (BuildContext context, int index) {
                    final AlertItem alert = items[index];
                    final Color tone = alert.severity == 'danger'
                        ? AppColors.danger
                        : AppColors.warning;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        onTap: () => context.go(
                          '${AppRoutes.families}/${alert.familyId}',
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  alert.text,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              StatusBadge(label: alert.type, tone: tone),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
