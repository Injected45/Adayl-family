import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../finance/domain/models.dart';
import '../../finance/presentation/providers.dart';
import '../domain/models.dart';
import 'providers.dart';

/// `YYYY-MM` for last month — a plain calendar step, not a business rule.
/// The prototype's dashboard button closes the PREVIOUS month too
/// (index.html:452), which is what the association actually does.
String _previousPeriod() {
  final DateTime now = DateTime.now().toUtc();
  final DateTime previous = DateTime.utc(now.year, now.month - 1);
  return '${previous.year}-${previous.month.toString().padLeft(2, '0')}';
}

Future<void> _generate(
  BuildContext context,
  WidgetRef ref,
  L l,
  String selectedPeriod,
) async {
  final String period = selectedPeriod.isEmpty
      ? _previousPeriod()
      : selectedPeriod;
  // Captured before the dialog: after an await the widget may be gone and the
  // context unusable.
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
    ref.invalidate(receivablesProvider(selectedPeriod));
    ref.invalidate(familiesProvider(''));
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

Future<void> _autoClose(BuildContext context, WidgetRef ref, L l) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final int created = await ref.read(financeRepositoryProvider).autoClose();
    ref.invalidate(receivablesProvider(''));
    ref.invalidate(familiesProvider(''));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          created == 0 ? l.nothingToGenerate : l.autoCloseResult(created),
        ),
      ),
    );
  } on ApiException catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeApiFailure(l, failure))),
    );
  }
}

/// Mirrors statusBadge() in index.html:198.
Color receivableTone(String status) => switch (status) {
  ReceivableStatusWire.fullyPaid => AppColors.success,
  ReceivableStatusWire.partiallyPaid => AppColors.warning,
  ReceivableStatusWire.unpaid => AppColors.danger,
  _ => AppColors.muted,
};

class ReceivablesScreen extends ConsumerWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final String period = ref.watch(receivablePeriodProvider);
    final AsyncValue<ReceivablesPage> page = ref.watch(
      receivablesProvider(period),
    );

    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navReceivables,
      currentRoute: AppRoutes.receivables,
      actions: <Widget>[
        // Raising receivables is a finance-manager act, so the control is not
        // merely hidden below that role — the API refuses it too.
        if (role.atLeast(AppRole.financeManager))
          PopupMenuButton<String>(
            icon: const Icon(Icons.playlist_add),
            onSelected: (String action) {
              unawaited(
                action == 'generate'
                    ? _generate(context, ref, l, period)
                    : _autoClose(context, ref, l),
              );
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'generate',
                child: Text(l.generateReceivables),
              ),
              PopupMenuItem<String>(
                value: 'autoClose',
                child: Text(l.autoClose),
              ),
            ],
          ),
      ],
      body: AsyncView<ReceivablesPage>(
        value: page,
        onRetry: () => ref.invalidate(receivablesProvider(period)),
        builder: (ReceivablesPage data) {
          final List<String> periods = <String>{
            ...data.items.map((ReceivableItem r) => r.period),
          }.toList()..sort((String a, String b) => b.compareTo(a));

          return ListView(
            padding: screenPadding(context),
            children: <Widget>[
              // The prototype keeps this warning permanently on screen because
              // it is the only place rule 5 is explained to the user.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  l.receivablesIntro,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF854D0E),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              Row(
                children: <Widget>[
                  Expanded(
                    child: _Summary(
                      label: l.issuedTotal,
                      value: formatMoney(data.summary.issued),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Summary(
                      label: l.collectedTotal,
                      value: formatMoney(data.summary.collected),
                      tone: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Summary(
                      label: l.outstandingTotal,
                      value: formatMoney(data.summary.outstanding),
                      tone: AppColors.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    ChoiceChip(
                      label: Text(l.allPeriods),
                      selected: period.isEmpty,
                      onSelected: (_) =>
                          ref.read(receivablePeriodProvider.notifier).state =
                              '',
                    ),
                    for (final String option in periods) ...<Widget>[
                      const SizedBox(width: AppSpacing.sm),
                      ChoiceChip(
                        label: Text(option),
                        selected: period == option,
                        onSelected: (_) =>
                            ref.read(receivablePeriodProvider.notifier).state =
                                option,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (data.items.isEmpty)
                EmptyStateView(
                  icon: Icons.receipt_long_outlined,
                  title: l.noReceivables,
                )
              else
                for (final ReceivableItem item in data.items)
                  _ReceivableCard(item: item),
            ],
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceivableCard extends StatelessWidget {
  const _ReceivableCard({required this.item});

  final ReceivableItem item;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
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
                        item.familyName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${item.familyCode} • ${item.periodLabel}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(
                  label: item.status,
                  tone: receivableTone(item.status),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.md,
              children: <Widget>[
                LabelledValue(
                  label: l.totalAmount,
                  value: formatMoney(item.total),
                ),
                LabelledValue(
                  label: l.paidAmount,
                  value: formatMoney(item.paid),
                ),
                LabelledValue(
                  label: l.remainingAmount,
                  value: formatMoney(item.balance),
                ),
                LabelledValue(
                  label: l.fatherFee,
                  value: formatMoney(item.fatherFee),
                ),
                LabelledValue(label: l.sonFee, value: formatMoney(item.sonFee)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            LabelledValue(
              label: l.billedSons,
              value: item.billedSonNames.isEmpty
                  ? l.noneBilled
                  : item.billedSonNames.join(ArabicPunctuation.listSeparator),
            ),
          ],
        ),
      ),
    );
  }
}
