import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/arabic_search.dart';
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
    ref.invalidate(adeelsProvider(''));
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
    ref.invalidate(adeelsProvider(''));
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

class ReceivablesScreen extends ConsumerStatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  ConsumerState<ReceivablesScreen> createState() =>
      _ReceivablesScreenState();
}

class _ReceivablesScreenState extends ConsumerState<ReceivablesScreen> {
  /// ⚠ SCREEN STATE, NOT A PROVIDER, and deliberately so. A search is the
  ///   one thing on this screen that belongs to the person holding the
  ///   phone rather than to the association — refreshAll sweeps every
  ///   provider in this app on a timer, and a box that emptied itself
  ///   mid-word every forty-five seconds would be unusable. It also means
  ///   the query dies with the screen, which is what leaving a search should
  ///   do.
  String _query = '';

  @override
  Widget build(BuildContext context) {
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
      body: (BuildContext context) => AsyncView<ReceivablesPage>(
        value: page,
        onRetry: () => ref.invalidate(receivablesProvider(period)),
        builder: (ReceivablesPage data) {
          final List<String> periods = <String>{
            ...data.items.map((ReceivableItem r) => r.period),
          }.toList()..sort((String a, String b) => b.compareTo(a));

          // ⚠ THE FILTER RUNS OVER THE PAGE ALREADY IN HAND. No second
          //   request, no server round trip per keystroke — and no chance
          //   of the totals above coming from one query while the rows come
          //   from another.
          //
          //   Four fields, because those are the four ways a treasurer
          //   actually looks for a row: the man, his code, the month — in
          //   both the «2026-01» form and the «يناير 2026» one — and the
          //   state it is in.
          final List<ReceivableItem> shown = data.items
              .where(
                (ReceivableItem r) => matchesSearch(_query, <String?>[
                  r.adeelName,
                  r.adeelCode,
                  r.period,
                  r.periodLabel,
                  r.status,
                ]),
              )
              .toList();

          return ListView(
            padding: screenPadding(context),
            children: <Widget>[
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

              // ── البحث الذكي، فوق أول اسم مباشرةً ────────────────────
              // ⚠ HERE AND NOT IN THE APP BAR. The association asked for it
              //   «فوق اول اسم من الاعلي», and that is the right place: it
              //   sits directly against the thing it filters, so the list
              //   shortening under it is visibly the box's doing. A search
              //   icon in the bar hides both the query and the fact that
              //   one is active, which is how a filtered screen gets
              //   mistaken for missing data.
              //
              // ⚠ AND BELOW THE THREE TOTALS, NOT ABOVE THEM. Those figures
              //   are the SERVER's for the whole period and do not move when
              //   the list is narrowed — money is never summed in Dart. A
              //   box above them would read as filtering them too.
              if (data.items.isNotEmpty) ...<Widget>[
                SearchField(
                  hintText: l.receivableSearchHint,
                  initialValue: _query,
                  onChanged: (String q) {
                    if (mounted) setState(() => _query = q);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              if (data.items.isEmpty)
                EmptyStateView(
                  icon: Icons.receipt_long_outlined,
                  title: l.noReceivables,
                )
              else ...<Widget>[
                // Only while it is narrowing something — see the ARB note.
                if (_query.trim().isNotEmpty) ...<Widget>[
                  Text(
                    l.receivableSearchCount(shown.length, data.items.length),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (shown.isEmpty)
                  EmptyStateView(
                    icon: Icons.search_off_outlined,
                    title: l.noSearchResults,
                  )
                else
                  for (final ReceivableItem item in shown)
                    _ReceivableCard(item: item),
              ],
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
                        item.adeelName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      // ⚠ THE MONTH ALONE TAKES THE COLOUR, not the whole
                      //   line. The code beside it is an identity and the
                      //   bullet is punctuation; painting all three blue
                      //   would say they are the same kind of thing.
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(text: '${item.adeelCode} • '),
                            TextSpan(
                              text: item.periodLabel,
                              style: const TextStyle(
                                color: AppColors.month,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
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
              ],
            ),
            // The father's and son's fee rates, the list of billed sons and the
            // snapshotted national ID are all gone from a receivable: it charges
            // ONE عديل at ONE rate, so the rate IS the total, and his name in
            // the heading above is the only identifying thing left on it.
          ],
        ),
      ),
    );
  }
}
