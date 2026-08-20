import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/state/refresh.dart';
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
    final AsyncValue<List<AdeelListItem>> adeels = ref.watch(
      adeelsProvider(''),
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
                  // The register moves with every payment and every
                  // closing, and so does everything else — see refreshAll.
                  onRefresh: () async => refreshAll(ref),
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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.go('${AppRoutes.adeels}/${adeel.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // ── سطر واحد: الرقم ثم الاسم ────────────────────────────────
              // ⚠ THE CODE LEADS, and that is what puts it beside the name
              //   instead of under it. A-01 is how the association refers to a
              //   man out loud — «العديل واحد» — so it reads as part of his
              //   name here, not as a label attached afterwards.
              Row(
                children: <Widget>[
                  // ⚠ HIS OWN COLOUR, not the neutral grey it used to be.
                  //   The register is scanned, not read: a man is found by
                  //   the shape of his row before any of it is spelled out,
                  //   and eight identical grey chips give the eye nothing to
                  //   aim at. Seeded on the id, so his colour is the same on
                  //   every screen and every device, for ever.
                  StatusBadge(
                    label: adeel.adeelCode,
                    tone: AppColors.identityTone(adeel.id),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      adeel.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

              // ⚠ «نشط» IS GONE FROM HERE, and it belongs where it went. The
              //   register lists everyone, and the overwhelming majority are
              //   نشط — so the badge repeated one true fact on every row and
              //   said nothing about any of them. It is on the detail screen,
              //   beside the fields it actually qualifies, where a موقوف or a
              //   متوفى is read against the man rather than against a list.
              //
              // ⚠ THE DEBT IS NOT, and this is the one line I kept against the
              //   letter of «الاسم والرقم فقط». It appears only for a man who
              //   actually owes — never on a clear register — and it is the
              //   figure the collection round is planned from. Say the word and
              //   it goes too; it is one `if` away.
              if (adeel.hasDebt) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                StatusBadge(
                  label: l.debtBadge(formatMoney(adeel.debt)),
                  tone: AppColors.danger,
                ),
              ],
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
    final CashSummaryView? summary = ref.watch(cashSummaryProvider).valueOrNull;
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
