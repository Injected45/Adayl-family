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
import '../../../core/widgets/figure_breakdown.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../directory/presentation/providers.dart';
import '../../finance/domain/models.dart';
import '../../finance/presentation/providers.dart';
import '../domain/models.dart';
import 'providers.dart';

/// ONE headline figure, top debtors, and the month-closing button.
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

    // ── عهد المشتركين comes from the TREASURY view, not from api_dashboard ──
    // The dashboard RPC has no such field and adding one would mean another
    // patch on the live project; v_cash_summary already publishes it, and
    // read_cash is has_role('viewer') so every staff account that can open
    // this page can read it.
    //
    // valueOrNull, deliberately: the headline must not wait on a second call,
    // and if this one fails the qualifier is simply absent rather than the whole
    // page being an error. A liability that cannot be read is not shown as zero.
    final CashSummaryView? cash = ref.watch(cashSummaryProvider).valueOrNull;
    final double held = double.tryParse(cash?.heldForMembers ?? '0') ?? 0;

    return AppScaffold(
      title: l.navHome,
      currentRoute: AppRoutes.home,
      body: (BuildContext context) => AsyncView<DashboardData>(
        value: dashboard,
        onRetry: () => ref.invalidate(dashboardProvider),
        builder: (DashboardData data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(cashSummaryProvider);
          },
          child: ListView(
            // See cash_screen: a RefreshIndicator over a list that fits the
            // screen ignores the pull unless the physics always accept it.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: screenPadding(context),
            children: <Widget>[
              if (role.atLeast(AppRole.financeManager)) ...<Widget>[
                FilledButton.icon(
                  onPressed: () =>
                      _closeMonth(context, ref, l),
                  icon: const Icon(Icons.event_available, size: 18),
                  label: Text(l.closeMonth),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // ── ONE FIGURE, AND THE REST A TAP AWAY ──────────────────────
              // Four tiles stood here, equal in weight. Three of them answered
              // questions nobody opens this page to ask first: what the
              // association has COLLECTED is the headline, and how many members
              // stand behind it and how much is still owed are the workings.
              //
              // The «غير المحاسَبين / متوفى» tile is gone outright, not moved:
              // a count of who is NOT billed is a register question, and the
              // register itself answers it in the row that carries each man's
              // status.
              //
              // Same widget as the treasury's رصيد الجمعية bar, so the two
              // headline figures of the app are read the same way.
              FigureBar(
                label: l.statTotalCollected,
                value: formatMoney(data.stats.collected),
                tone: AppColors.success,
                // The split survives on the face of the bar: it is the one part
                // of the workings that changes how the figure is read.
                sub: l.subCashTransfer(
                  formatMoney(data.stats.cash),
                  formatMoney(data.stats.transfer),
                ),
                // ── WHAT THE HEADLINE DOES NOT SAY ON ITS OWN ──────────────
                // إجمالي المحصل counts every dinar that arrived, and part of
                // it can be عهدة — paid ahead for a month not yet billed, owed
                // back until it is. Read without this line the figure is not
                // wrong, it is MISREAD: a treasurer adds it to what the
                // association has.
                //
                // On the FACE rather than in the breakdown because it is not a
                // working. Tapping through is for «what is this made of»; this
                // changes what the number means, and a meaning behind a tap is
                // a meaning most readers never get.
                note: held > 0 ? l.heldOfWhich(formatMoney(cash!.heldForMembers)) : null,
                rows: <FigureRow>[
                  FigureRow(
                    label: l.statAdeels,
                    value: '${data.stats.adeels}',
                    trailing: l.subActive(data.stats.active),
                  ),
                  // Between what came in and what is owed, and toned like a
                  // debt rather than a collection — it is money that will
                  // leave. Same placement and same tone as the treasury's own
                  // bar, so the two read alike.
                  if (held > 0)
                    FigureRow(
                      label: l.heldForMembers,
                      value: formatMoney(cash!.heldForMembers),
                      tone: AppColors.warning,
                    ),
                  FigureRow(
                    label: l.statTotalDebt,
                    value: formatMoney(data.stats.debt),
                    trailing: l.subIndebtedAdeels(data.stats.indebtedAdeels),
                    tone: AppColors.danger,
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
                                '${AppRoutes.adeels}/${debtor.adeelId}',
                              ),
                              title: Text(
                                debtor.adeelName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                debtor.adeelCode,
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
              // The "قريب من السن" panel stood here, listing sons whose
              // sixteenth birthday fell within warning_months so a treasurer
              // could see a charge coming. There is no age gate and therefore
              // nothing to see coming — an عديل is billed from the day he is
              // registered نشط — so the panel is gone rather than left showing a
              // permanently empty list.
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks WHICH month, then confirms it.
///
/// The button used to close last month and only last month, which is right the
/// day you press it and wrong every day after: a month missed in March cannot be
/// raised in May without going somewhere else. Two steps now — pick, then
/// confirm — and the picker is server-fed, so it offers exactly the months
/// between `system_start` and last month and says which are already done.
Future<void> _closeMonth(BuildContext context, WidgetRef ref, L l) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final ClosablePeriod? chosen = await showDialog<ClosablePeriod>(
    context: context,
    builder: (BuildContext pickerContext) => const _PeriodPickerDialog(),
  );
  if (chosen == null || !context.mounted) return;
  final String period = chosen.period;

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => GlassDialog(
      title: Text(l.generateConfirmTitle(chosen.label)),
      content: Text(
        l.generateConfirmBody,
        style: const TextStyle(height: 1.5),
      ),
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
    ref.invalidate(adeelsProvider(''));
    ref.invalidate(receivablesProvider(''));
    // The month just closed is now `closed`, and the one after it has become the
    // `selectable` one. Both flags are stale, so the list has to go with them.
    ref.invalidate(closablePeriodsProvider);
    // ⚠ AND عهد المشتركين, which the close just SPENT. generate_period calls
    //   settle_from_credit per عديل as it raises his receivable, so a member
    //   who had paid ahead has less held for him — or none — the moment this
    //   returns. Leave it out and the headline goes on qualifying itself with a
    //   liability that no longer exists.
    ref.invalidate(cashSummaryProvider);
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

/// The month list. Newest first, with the closed ones marked and the blocked
/// ones greyed rather than hidden — a treasurer checking whether March was done
/// needs to SEE March.
///
/// Every row's state comes from the server: `closed` and `selectable` are rules
/// 15a and 15b, and the picker only paints them. Deciding here which month is
/// next would be a second implementation of a money rule, and the one that
/// counts is `generate_period`'s — which refuses anything else with RUL15.
class _PeriodPickerDialog extends ConsumerWidget {
  const _PeriodPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<ClosablePeriod>> periods = ref.watch(
      closablePeriodsProvider,
    );

    return GlassDialog(
      title: Text(l.selectPeriodTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: periods.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object error, StackTrace _) =>
              Text(describeApiFailure(l, error)),
          data: (List<ClosablePeriod> items) => items.isEmpty
              // system_start is in the future, or this month is the first one.
              // Either way there is nothing to close yet, and saying so beats an
              // empty box.
              ? Text(l.noPeriodsToClose)
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final ClosablePeriod p = items[index];
                    // Exactly one row is ever tappable — the earliest open
                    // month. The rest stay VISIBLE and inert: someone checking
                    // whether March was closed needs to see March, and someone
                    // wondering why August is greyed out needs to see the open
                    // July above it. Hiding them would answer neither question.
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      enabled: p.selectable,
                      title: Text(
                        p.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p.selectable
                              ? AppColors.ink
                              : AppColors.muted,
                        ),
                      ),
                      subtitle: Text(
                        p.selectable
                            ? p.period
                            // The reason it is not tappable, in words. "Greyed
                            // out with no explanation" is the version of this
                            // screen that generates a phone call.
                            : p.closed
                            ? l.periodClosedNote
                            : l.periodBlockedNote,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                      trailing: p.closed
                          ? StatusBadge(
                              label: l.periodClosedBadge,
                              tone: AppColors.success,
                            )
                          : p.selectable
                          ? const Icon(
                              Icons.chevron_left,
                              size: 20,
                              color: AppColors.muted,
                            )
                          : const Icon(
                              Icons.lock_outline,
                              size: 18,
                              color: AppColors.muted,
                            ),
                      onTap: p.selectable
                          ? () => Navigator.of(context).pop(p)
                          : null,
                    );
                  },
                ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
      ],
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
