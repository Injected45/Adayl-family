import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// The regulatory trail. Reachable only by a finance manager or admin, and the
/// API refuses anyone else regardless of what the navigation shows.
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final String type = ref.watch(auditTypeProvider);
    final AsyncValue<AuditPage> audit = ref.watch(auditProvider(type));
    final AsyncValue<AuditPage> unfiltered = ref.watch(auditProvider(''));
    final List<String> types = unfiltered.valueOrNull?.eventTypes ?? <String>[];

    return AppScaffold(
      title: l.navAudit,
      currentRoute: AppRoutes.audit,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l.auditIntro,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      ChoiceChip(
                        label: Text(l.allEvents),
                        selected: type.isEmpty,
                        onSelected: (_) =>
                            ref.read(auditTypeProvider.notifier).state = '',
                      ),
                      for (final String option in types) ...<Widget>[
                        const SizedBox(width: AppSpacing.sm),
                        ChoiceChip(
                          label: Text(option),
                          selected: type == option,
                          onSelected: (_) =>
                              ref.read(auditTypeProvider.notifier).state =
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
            child: AsyncView<AuditPage>(
              value: audit,
              onRetry: () => ref.invalidate(auditProvider(type)),
              builder: (AuditPage page) {
                if (page.items.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.history_outlined,
                    title: l.noAuditEntries,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final AuditEntry entry = page.items[index];
                    return Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: StatusBadge(
                                  label: entry.eventType,
                                  tone: AppColors.brand,
                                ),
                              ),
                              Text(
                                formatDateTime(entry.occurredAt),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            entry.detail,
                            style: const TextStyle(fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${l.auditActor}: ${entry.actorName}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
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
