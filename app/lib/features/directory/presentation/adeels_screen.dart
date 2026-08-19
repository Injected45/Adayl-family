import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/glass.dart';
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
import '../../finance/domain/models.dart';
import '../../finance/presentation/providers.dart';
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
    // ── THE SEARCH BOX IS GONE ────────────────────────────────────────────
    // Removed at the association's request. The repository still takes a query
    // and `adeelSearchProvider` still exists — the receivables screen and the
    // payment sheet both search the register — so this screen simply asks for
    // all of it.
    //
    // ⚠ It is one widget to put back, and the day the register outgrows a
    //   single scroll is the day to do it: the filter itself lives in
    //   PostgREST, not here, so nothing about it has been lost.
    final AsyncValue<List<AdeelListItem>> adeels = ref.watch(adeelsProvider(''));

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
      body: (BuildContext context) => Column(
        children: <Widget>[
          // ── What the register adds up to ────────────────────────────────
          // The list answers "who owes what" one man at a time; this answers
          // "how much is out there", which is the question the register is
          // opened with and which no row on it carries.
          //
          // The figure is the SERVER's — v_cash_summary.outstanding, the same
          // one the treasury screen shows — never a sum of the rows. Adding the
          // visible debts in Dart would put the association's receivables on
          // binary floating point, and would silently mean something different
          // the moment the list were paged.
          //
          // It used to hide while a search was active, because a whole-register
          // total above three filtered rows is a figure that does not add up to
          // what is under it. With no search there is nothing to filter and the
          // figure always describes the list beneath it.
          const _OutstandingBar(),
          Expanded(
            child: AsyncView<List<AdeelListItem>>(
              value: adeels,
              onRetry: () => ref.invalidate(adeelsProvider('')),
              builder: (List<AdeelListItem> items) {
                if (items.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.groups_outlined,
                    title: l.noAdeels,
                    message: l.registerIntro,
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(adeelsProvider('')),
                  child: ListView.separated(
                    // Always scrollable so a register of three عدايل can still
                    // be pulled to refresh. Without it the RefreshIndicator
                    // above responds only once the list is long enough to
                    // overflow, and the gesture appears to be broken on exactly
                    // the association that has least reason to doubt it.
                    physics: const AlwaysScrollableScrollPhysics(),
                    // bottomInset, not a bare 24: the navigation pill and the
                    // add button both FLOAT over the body, so a fixed inset
                    // leaves the last عديل in the register behind one of them.
                    // The context here is the one AppScaffold hands its body
                    // builder — the screen's own context reads past the
                    // MediaQuery that publishes this and returns zero.
                    padding: EdgeInsetsDirectional.fromSTEB(
                      16,
                      0,
                      16,
                      24 + bottomInset(context),
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
                  // No age badge. The association stopped collecting a date of
                  // birth, and age decided nothing about billing even while it
                  // was collected — membership status above carries the whole
                  // answer, which is why it took the badge that used to read
                  // "eligible / approaching age".
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

/// إجمالي المستحق, across the top of the register.
///
/// Reads `v_cash_summary` — the same figure the treasury screen puts on its
/// balance bar, so the two pages cannot disagree about what the association is
/// owed. Silent while it loads or fails: the register is usable without it, and
/// an error strip above a working list would be the loudest thing on the page.
class _OutstandingBar extends ConsumerWidget {
  const _OutstandingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final CashSummaryView? summary = ref
        .watch(cashSummaryProvider)
        .valueOrNull;
    if (summary == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                // The tone money owed carries everywhere else in the app, and
                // it encodes the meaning for a reader who cannot separate the
                // colours — hue is never the only signal.
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l.totalOutstanding,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Text(
              formatMoney(summary.outstanding),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
