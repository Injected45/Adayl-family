import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Account approval and role management.
///
/// Without this screen a second person can never use the system: Google
/// Sign-In grants an identity, not access, and every account after the first
/// waits here for an administrator.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<UserAccount>> users = ref.watch(usersProvider);
    final String? myId = ref.watch(authControllerProvider).user?.id;

    return AppScaffold(
      title: l.navUsers,
      currentRoute: AppRoutes.users,
      body: AsyncView<List<UserAccount>>(
        value: users,
        onRetry: () => ref.invalidate(usersProvider),
        builder: (List<UserAccount> accounts) {
          if (accounts.isEmpty) {
            return EmptyStateView(
              icon: Icons.manage_accounts_outlined,
              title: l.noUsers,
            );
          }
          final List<UserAccount> pending = accounts
              .where((UserAccount user) => user.status == AccountStatus.pending)
              .toList();
          final List<UserAccount> rest = accounts
              .where((UserAccount user) => user.status != AccountStatus.pending)
              .toList();

          return ListView(
            padding: screenPadding(context),
            children: <Widget>[
              Text(
                l.usersIntro,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (pending.isNotEmpty) ...<Widget>[
                Text(
                  '${l.pendingRequests} (${pending.length})',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final UserAccount user in pending)
                  _UserCard(user: user, isSelf: user.id == myId),
                const SizedBox(height: AppSpacing.lg),
              ],

              Text(
                l.allUsers,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final UserAccount user in rest)
                _UserCard(user: user, isSelf: user.id == myId),
            ],
          );
        },
      ),
    );
  }
}

String _roleLabel(L l, AppRole role) => switch (role) {
  AppRole.admin => l.roleAdmin,
  AppRole.financeManager => l.roleFinanceManager,
  AppRole.treasurer => l.roleTreasurer,
  AppRole.viewer => l.roleViewer,
};

class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user, required this.isSelf});

  final UserAccount user;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final bool suspended = user.status == AccountStatus.suspended;
    final bool pending = user.status == AccountStatus.pending;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        user.email,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: pending
                      ? l.pendingTitle
                      : suspended
                      ? l.suspendedTitle
                      : _roleLabel(l, user.role),
                  tone: pending
                      ? AppColors.warning
                      : suspended
                      ? AppColors.danger
                      : AppColors.info,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${l.lastLogin}: ${user.lastLoginAt == null ? l.never : formatDateTime(user.lastLoginAt)}',
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),

            if (isSelf) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              // The server refuses this too — an administrator locking
              // themselves out would leave nobody able to administer.
              Text(
                l.cannotModifySelfNote,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ] else ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  if (pending)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 38),
                      ),
                      onPressed: () => _update(
                        context,
                        ref,
                        l,
                        user,
                        status: 'approved',
                        role: user.role.wireName,
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(l.approve),
                    ),
                  if (!pending)
                    DropdownButton<AppRole>(
                      value: user.role,
                      underline: const SizedBox.shrink(),
                      hint: Text(l.changeRole),
                      items: <DropdownMenuItem<AppRole>>[
                        for (final AppRole role in AppRole.values)
                          DropdownMenuItem<AppRole>(
                            value: role,
                            child: Text(_roleLabel(l, role)),
                          ),
                      ],
                      onChanged: (AppRole? role) {
                        if (role == null || role == user.role) return;
                        _update(context, ref, l, user, role: role.wireName);
                      },
                    ),
                  if (!pending)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        foregroundColor: suspended
                            ? AppColors.success
                            : AppColors.danger,
                      ),
                      onPressed: () => _update(
                        context,
                        ref,
                        l,
                        user,
                        status: suspended ? 'approved' : 'suspended',
                      ),
                      icon: Icon(
                        suspended ? Icons.lock_open : Icons.block,
                        size: 16,
                      ),
                      label: Text(suspended ? l.reactivate : l.suspend),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _update(
  BuildContext context,
  WidgetRef ref,
  L l,
  UserAccount user, {
  String? role,
  String? status,
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(oversightRepositoryProvider)
        .updateUser(userId: user.id, role: role, status: status);
    ref.invalidate(usersProvider);
    messenger.showSnackBar(SnackBar(content: Text(l.userUpdated)));
  } on ApiException catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeApiFailure(l, failure))),
    );
  }
}
