import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
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

/// The register — ONE screen where there were two.
///
/// `FamiliesScreen` listed households by their father's name with a count of
/// sons; `MembersScreen` listed every person with a relation badge and the
/// household they hung off. Both described the same people through a hierarchy
/// that no longer exists, so they collapsed into this.
class AdeelsScreen extends ConsumerWidget {
  const AdeelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final String query = ref.watch(adeelSearchProvider);
    final AsyncValue<List<AdeelListItem>> adeels = ref.watch(
      adeelsProvider(query),
    );

    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navRegister,
      currentRoute: AppRoutes.adeels,
      // Entering an عديل is a finance-manager act; the RPC refuses anyone else
      // and the router guards the route, so hiding the button is the third layer
      // rather than the only one.
      floatingActionButton: role.atLeast(AppRole.financeManager)
          ? FloatingActionButton.extended(
              onPressed: () => context.go('${AppRoutes.adeels}/new'),
              icon: const Icon(Icons.add),
              label: Text(l.addAdeel),
            )
          : null,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SearchField(
              hintText: l.searchAdeelsHint,
              initialValue: query,
              onChanged: (String value) =>
                  ref.read(adeelSearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: AsyncView<List<AdeelListItem>>(
              value: adeels,
              onRetry: () => ref.invalidate(adeelsProvider(query)),
              builder: (List<AdeelListItem> items) {
                if (items.isEmpty) {
                  return EmptyStateView(
                    icon: query.isEmpty
                        ? Icons.groups_outlined
                        : Icons.search_off_outlined,
                    title: query.isEmpty ? l.noAdeels : l.noSearchResults,
                    message: query.isEmpty ? l.registerIntro : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(adeelsProvider(query)),
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
                        _AdeelCard(adeel: items[index]),
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

class _AdeelCard extends StatelessWidget {
  const _AdeelCard({required this.adeel});

  final AdeelListItem adeel;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool active = adeel.membershipStatus == MembershipStatusWire.active;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.go('${AppRoutes.adeels}/${adeel.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      adeel.fullName,
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
                  StatusBadge.neutral(label: adeel.adeelCode),
                  // Membership status carries the whole billing answer now, so it
                  // is the badge that used to be "eligible / approaching age".
                  StatusBadge(
                    label: adeel.membershipStatus,
                    tone: active ? AppColors.success : AppColors.muted,
                  ),
                  if (adeel.age != null)
                    StatusBadge(
                      label: l.ageYears(adeel.age!),
                      tone: AppColors.info,
                    ),
                  if (adeel.hasDebt)
                    StatusBadge(
                      label: l.debtBadge(formatMoney(adeel.debt)),
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
