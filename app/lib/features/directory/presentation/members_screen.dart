import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final String query = ref.watch(memberSearchProvider);
    final AsyncValue<List<MemberListItem>> members = ref.watch(
      membersProvider(query),
    );

    return AppScaffold(
      title: l.navMembers,
      currentRoute: AppRoutes.members,
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: SearchField(
              hintText: l.searchMembersHint,
              initialValue: query,
              onChanged: (String value) =>
                  ref.read(memberSearchProvider.notifier).state = value,
            ),
          ),
          Expanded(
            child: AsyncView<List<MemberListItem>>(
              value: members,
              onRetry: () => ref.invalidate(membersProvider(query)),
              builder: (List<MemberListItem> items) {
                if (items.isEmpty) {
                  return EmptyStateView(
                    icon: query.isEmpty
                        ? Icons.person_search_outlined
                        : Icons.search_off_outlined,
                    title: query.isEmpty ? l.noMembers : l.noSearchResults,
                    message: query.isEmpty ? l.membersIntro : null,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final MemberListItem member = items[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.go(
                        '${AppRoutes.families}/${member.familyId}',
                      ),
                      title: Text(
                        member.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${member.nationalId} • ${member.familyName}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          StatusBadge(
                            label: member.relation,
                            tone: member.relation == MemberRelationWire.father
                                ? AppColors.brand
                                : AppColors.info,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            member.age == null ? '' : l.ageYears(member.age!),
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
