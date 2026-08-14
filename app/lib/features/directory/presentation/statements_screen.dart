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

class StatementsScreen extends ConsumerWidget {
  const StatementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final int? selected = ref.watch(selectedStatementFamilyProvider);
    final AsyncValue<List<FamilyListItem>> families = ref.watch(
      familiesProvider(''),
    );

    return AppScaffold(
      title: l.navStatements,
      currentRoute: AppRoutes.statements,
      body: AsyncView<List<FamilyListItem>>(
        value: families,
        onRetry: () => ref.invalidate(familiesProvider('')),
        builder: (List<FamilyListItem> options) => Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: DropdownButtonFormField<int>(
                initialValue: selected,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.selectFamily),
                items: <DropdownMenuItem<int>>[
                  for (final FamilyListItem family in options)
                    DropdownMenuItem<int>(
                      value: family.id,
                      child: Text(
                        '${family.fatherName} • ${family.familyCode}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (int? value) =>
                    ref.read(selectedStatementFamilyProvider.notifier).state =
                        value,
              ),
            ),
            Expanded(
              child: selected == null
                  ? EmptyStateView(
                      icon: Icons.description_outlined,
                      title: l.selectFamilyToView,
                      message: l.statementsIntro,
                    )
                  : _StatementBody(familyId: selected),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementBody extends ConsumerWidget {
  const _StatementBody({required this.familyId});

  final int familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<Statement> statement = ref.watch(
      statementProvider(familyId),
    );

    return AsyncView<Statement>(
      value: statement,
      onRetry: () => ref.invalidate(statementProvider(familyId)),
      builder: (Statement data) {
        if (data.movements.isEmpty) {
          return EmptyStateView(
            icon: Icons.inbox_outlined,
            title: l.noMovements,
          );
        }
        return ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
          children: <Widget>[
            for (final StatementMovement movement in data.movements)
              _MovementCard(movement: movement),
            const SizedBox(height: AppSpacing.md),
            Card(
              color: AppColors.brandSoft,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      l.closingBalance,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      formatMoney(data.closingBalance),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: AppColors.brandDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.movement});

  final StatementMovement movement;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool isCharge = movement.debit != null;

    return Card(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  isCharge ? Icons.north_east : Icons.south_west,
                  size: 16,
                  color: isCharge ? AppColors.danger : AppColors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    movement.type,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatMoney(isCharge ? movement.debit : movement.credit),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isCharge ? AppColors.danger : AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  formatDate(movement.date),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                Text(
                  '${l.movementBalance}: ${formatMoney(movement.balance)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (movement.note.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                movement.note,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
