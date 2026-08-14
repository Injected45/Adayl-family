import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models.dart';
import 'providers.dart';

class FamiliesScreen extends ConsumerWidget {
  const FamiliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final String query = ref.watch(familySearchProvider);
    final AsyncValue<List<FamilyListItem>> families = ref.watch(
      familiesProvider(query),
    );

    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navFamilies,
      currentRoute: AppRoutes.families,
      // Entering a family is a finance-manager act; the API refuses anyone else
      // and the router guards the route, so hiding the button is the third layer
      // rather than the only one.
      floatingActionButton: role.atLeast(AppRole.financeManager)
          ? FloatingActionButton.extended(
              onPressed: () => context.go('${AppRoutes.families}/new'),
              icon: const Icon(Icons.add),
              label: Text(l.addFamily),
            )
          : null,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SearchField(
              hintText: l.searchFamiliesHint,
              initialValue: query,
              onChanged: (String value) =>
                  ref.read(familySearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: AsyncView<List<FamilyListItem>>(
              value: families,
              onRetry: () => ref.invalidate(familiesProvider(query)),
              builder: (List<FamilyListItem> items) {
                if (items.isEmpty) {
                  return EmptyStateView(
                    icon: query.isEmpty
                        ? Icons.groups_outlined
                        : Icons.search_off_outlined,
                    title: query.isEmpty ? l.noFamilies : l.noSearchResults,
                    message: query.isEmpty ? l.familiesIntro : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(familiesProvider(query)),
                  child: ListView.separated(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      0,
                      16,
                      24,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (BuildContext context, int index) =>
                        _FamilyCard(family: items[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.family});

  final FamilyListItem family;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.go('${AppRoutes.families}/${family.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      family.fatherName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_left,
                    color: AppColors.muted,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  StatusBadge.neutral(label: family.familyCode),
                  StatusBadge(
                    label: l.sonsBadge(family.sonsCount),
                    tone: AppColors.info,
                  ),
                  StatusBadge(
                    label: l.eligibleBadge(family.eligibleCount),
                    tone: AppColors.success,
                  ),
                  if (family.hasDebt)
                    StatusBadge(
                      label: l.debtBadge(formatMoney(family.debt)),
                      tone: AppColors.danger,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
