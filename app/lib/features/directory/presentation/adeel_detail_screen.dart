import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../finance/presentation/payment_sheet.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Issues a fresh access code for this عديل and shows it once, with a copy
/// button — the admin then sends it to him.
///
/// Always issues rather than reading the current one back. The code IS the
/// credential, and "show me what it is" and "give me a new one" are the same
/// gesture for an admin who has lost the message: issuing revokes the previous
/// code but does NOT sign out someone who already redeemed it, because by then
/// the binding lives on his profile rather than on the code.
Future<void> _showAccessCode(
  BuildContext context,
  WidgetRef ref,
  int adeelId,
) async {
  final L l = L.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final String code = await ref
        .read(directoryRepositoryProvider)
        .issueAdeelCode(adeelId);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        title: Text(l.issueCodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.issueCodeBody,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l.close),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              messenger.showSnackBar(
                SnackBar(content: Text(l.issueCodeCopied)),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(l.copy),
          ),
        ],
      ),
    );
  } on ApiException catch (failure) {
    messenger.showSnackBar(
      SnackBar(content: Text(describeApiFailure(l, failure))),
    );
  }
}

/// `eligibilityTone` used to live here, colouring a son's مستحق / قريب من السن /
/// غير مستحق badge. There is no age gate, so membership status is the only tone
/// left to pick: active is a live subscription, anything else is not.
Color membershipTone(String status) =>
    status == MembershipStatusWire.active ? AppColors.success : AppColors.muted;

class AdeelDetailScreen extends ConsumerWidget {
  const AdeelDetailScreen({required this.adeelId, super.key});

  final int adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<AdeelDetail> detail = ref.watch(
      adeelDetailProvider(adeelId),
    );
    final String currency =
        ref.watch(settingsProvider).valueOrNull?.currency ?? '';

    final AppRole role =
        ref.watch(authControllerProvider).user?.role ?? AppRole.viewer;

    return AppScaffold(
      title: l.navRegister,
      currentRoute: AppRoutes.adeels,
      actions: <Widget>[
        // admin, not financeManager: issuing a code hands someone a permanent
        // read of this عديل's figures, which is an access decision rather than a
        // financial one. issue_adeel_code() gates on admin too, so a finance
        // manager pressing it would get RUL00 — the button is hidden because
        // offering it and then refusing is worse than not offering it.
        if (role.atLeast(AppRole.admin))
          IconButton(
            tooltip: l.issueCodeTitle,
            onPressed: () => _showAccessCode(context, ref, adeelId),
            icon: const Icon(Icons.key_outlined),
          ),
        if (role.atLeast(AppRole.financeManager))
          IconButton(
            tooltip: l.editAdeel,
            onPressed: () => context.go('${AppRoutes.adeels}/$adeelId/edit'),
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
      body: (BuildContext context) => AsyncView<AdeelDetail>(
        value: detail,
        onRetry: () => ref.invalidate(adeelDetailProvider(adeelId)),
        builder: (AdeelDetail detail) {
          final AdeelView adeel = detail.adeel;
          return ListView(
            padding: screenPadding(context),
            children: <Widget>[
              // ── The name, his code FACING it, and his DATA behind it ──────
              // The code sat under the name in a small muted style, which read
              // as a caption — a footnote to the heading rather than the other
              // half of it. It is not a footnote: «A-06» is how the association
              // refers to him on every receipt and voucher, and it is what a
              // reader checks when two men share a spelling.
              //
              // Same treatment as the aid ledger's header, deliberately: the
              // two screens open on the same man and should introduce him the
              // same way.
              //
              // ⚠ AND THE NAME IS THE DOOR to his personal data. That was a
              //   panel of three facts halfway down the page — his telephone,
              //   when he was registered, his status — read once when somebody
              //   is looking for one of them and scrolled past every other
              //   time. The name is where a reader reaches for what the
              //   association holds ABOUT him, which is the same door the
              //   portal uses for the same reason.
              //
              // `end` rather than left — in Arabic that is the left edge, and
              // the same widget puts it on the right in English. Baseline
              // alignment because a long name wraps and the code never does, so
              // their first lines are what must stay level.
              InkWell(
                onTap: () => _showPersonalData(context, adeel),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          adeel.fullName,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // The affordance. A name that opens something and does
                      // not say so is a feature nobody finds — and this is now
                      // the ONLY way to his personal data.
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        adeel.adeelCode,
                        // The SAME size as the name, and muted rather than
                        // smaller: matching the size is what makes the two read
                        // as one line; the colour keeps the name first.
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── THE ACTION FIRST, THE FIGURES UNDER IT ────────────────────
              // Staff open a member's page for one of two reasons: to record a
              // payment, or to look something up. The first is a single button
              // and it now sits directly under his name, where the thumb
              // already is; the summary follows, folded.
              //
              // It reads correctly in both cases too — «هذا الرجل، سجّل له
              // سدادًا» — where the old order made a treasurer scroll past five
              // figures to reach the only thing he came to press.
              if (role.atLeast(AppRole.treasurer)) ...<Widget>[
                // Disabled rather than hidden when nothing is owed, with the
                // reason shown — a vanishing button reads as a bug.
                FilledButton.icon(
                  onPressed: (double.tryParse(detail.debt) ?? 0) > 0
                      ? () async {
                          final bool saved = await showPaymentSheet(
                            context,
                            adeelId: adeel.id,
                          );
                          if (saved) {
                            ref.invalidate(adeelDetailProvider(adeel.id));
                          }
                        }
                      : null,
                  icon: const Icon(Icons.add_card, size: 18),
                  label: Text(l.registerPayment),
                ),
                if ((double.tryParse(detail.debt) ?? 0) <= 0) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.noDebtForFamily,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],

              _SummaryCard(detail: detail, currency: currency),
              const SizedBox(height: AppSpacing.lg),

              // ── What the association GAVE him ───────────────────────────
              // A link, not a panel. Everything on this page is «ما عليه» —
              // dues raised, dues owed — and aid is the opposite direction. Put
              // as a figure among them it would read as something that nets off
              // against the debt beside it, which for a جمعية خيرية is exactly
              // wrong: what a man is given is never deducted from what he owes.
              // A separate screen, with the rule written at the top of it, is
              // the layout that cannot be misread.
              OutlinedButton.icon(
                onPressed: () => context.go('${AppRoutes.adeels}/$adeelId/aid'),
                icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                label: Text(l.openAid),
              ),
              const SizedBox(height: AppSpacing.lg),

              // «البيانات الشخصية» stood here as a panel of three facts. It
              // is behind his NAME now — see _showPersonalData — because it is
              // read once when somebody is looking for one of them and
              // scrolled past every other time.

              // The sons section is gone with the household. What a reader
              // actually needs here is the same thing it needed there — what is
              // owed and for which months — and that is now the man's own dues.
              //
              // `duesSection`, not `myDuesTitle`: this is staff looking at
              // somebody else's record, so "اشتراكاتي" would be the wrong voice.
              // The portal keeps the first-person one.
              // FOLDED, and the closed row still says how many months are open.
              // On a man two years into the register this list is twenty-four
              // rows, and a reader almost never wants all of them — he wants to
              // know whether anything is outstanding, which the heading now
              // answers without being opened.
              _FoldingSection(
                title: l.duesSection,
                icon: Icons.event_note_outlined,
                trailing: Text(
                  l.openPeriodsCount(detail.openPeriods),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: detail.openPeriods > 0
                        ? AppColors.danger
                        : AppColors.muted,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    for (final ReceivableItem item in detail.receivables)
                      _DueTile(item: item, currency: currency),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// His personal data, behind his name.
///
/// It was a panel halfway down the page carrying three facts — his telephone,
/// when he was registered, his status — read once when somebody is looking for
/// one of them and scrolled past every other time. A sheet costs a tap on the
/// rare occasion and nothing on the common one.
///
/// The same door the portal uses for the same facts, so a reader who learns it
/// on one screen has learned it on both.
void _showPersonalData(BuildContext context, AdeelView adeel) {
  final L l = L.of(context);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.ink.withValues(alpha: 0.22),
    builder: (BuildContext sheetContext) => GlassSheet(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.inkMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l.personalData,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.xl,
                runSpacing: AppSpacing.lg,
                children: <Widget>[
                  LabelledValue(label: l.phone, value: adeel.phone),
                  // ── NO DATE OF BIRTH, AND NO AGE ────────────────────────
                  // The association stopped collecting either. Age decided
                  // nothing about billing even before this — membership status
                  // is the only thing that gates a charge — so the fields were
                  // carrying a fact the register had no use for.
                  //
                  // The COLUMN is still in the database and still holds every
                  // date already entered. Nothing writes it any more (the form
                  // omits the key, and save_adeel leaves an absent key alone
                  // rather than nulling it), and nothing reads it. Dropping the
                  // column would erase what the association typed, and it can
                  // be dropped later on purpose if they decide the dates are
                  // not wanted at all.
                  LabelledValue(
                    label: l.registeredAt,
                    value: adeel.registeredAt,
                  ),
                  LabelledValue(
                    label: l.membershipStatusField,
                    value: adeel.membershipStatus,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail, required this.currency});

  final AdeelDetail detail;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool owes = (double.tryParse(detail.debt) ?? 0) > 0;

    // ── FOLDED, with what he OWES on the closed row ─────────────────────────
    // Five figures in a grid answered a question a reader almost never asks in
    // full: what he is billed monthly, what has been issued, what he has paid,
    // how many months are open — and, buried among them as a peer, the one
    // figure the page is opened for. Folded, the debt is the heading; the
    // workings are a tap under it.
    //
    // It keeps the blurred hero surface rather than the plain card the section
    // below uses: it is still the top of the page, and folding a thing does not
    // demote it.
    return GlassSurface(
      blurred: true,
      lifted: true,
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.summarize_outlined,
              size: 18,
              color: AppColors.brandDeep,
            ),
          ),
          title: Text(
            l.familySummary,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                formatMoney(detail.debt),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: owes ? AppColors.danger : AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.expand_more, size: 20, color: AppColors.muted),
            ],
          ),
          children: <Widget>[
            StatCardGrid(
              children: <Widget>[
                _Kpi(
                  label: l.monthlyFeeLabel,
                  value: formatMoney(detail.monthlyExpected),
                ),
                _Kpi(label: l.issuedLabel, value: formatMoney(detail.issued)),
                _Kpi(
                  label: l.debt,
                  value: formatMoney(detail.debt),
                  tone: owes ? AppColors.danger : AppColors.success,
                ),
                _Kpi(label: l.totalPaid, value: formatMoney(detail.paid)),
                _Kpi(
                  label: l.openPeriodsBadge(detail.openPeriods),
                  value: '${detail.openPeriods}',
                ),
              ],
            ),
            if (currency.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(currency, style: Theme.of(context).textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    // A recessed well, not another pane: these sit INSIDE the summary glass, and
    // glass on glass has no readable boundary.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: GlassColors.well,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: GlassColors.wellEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: tone ?? AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A section that arrives FOLDED, and says on its closed row what is inside.
///
/// ── WHY FOLD AT ALL ─────────────────────────────────────────────────────────
/// A member's page opened as one long scroll: the summary grid, his personal
/// data, then every month he has ever been billed. On a man two years into the
/// register that last list is twenty-four rows, and everything a reader came
/// for was above it or buried in it. Folding turns the page into a short list
/// of questions he can pick from.
///
/// ── AND WHY THE CLOSED ROW STILL CARRIES A FIGURE ───────────────────────────
/// A fold that hides the answer costs a tap to learn what a glance used to
/// tell. So the heading keeps the ONE number the section is opened for — what
/// he owes, how many months are outstanding — exactly as the treasury's own
/// folded groups keep a member's total on their closed row. The detail is what
/// folds away, never the conclusion.
///
/// Built on ExpansionTile inside the app's own glass card, with the tile's
/// divider suppressed: without that it draws its own line inside the card and
/// the whole thing reads as two stacked cards.
class _FoldingSection extends StatelessWidget {
  const _FoldingSection({
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;

  /// The figure that survives the fold. Null when the section has no single
  /// number worth carrying.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          childrenPadding: const EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          leading: icon == null
              ? null
              : Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: AppColors.brandDeep),
                ),
          title: Text(title, style: Theme.of(context).textTheme.titleLarge),
          trailing: trailing == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    trailing!,
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppColors.muted,
                    ),
                  ],
                ),
          children: <Widget>[child],
        ),
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({required this.item, required this.currency});

  final ReceivableItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  item.periodLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StatusBadge(
                label: item.status,
                tone: item.status == ReceivableStatusWire.fullyPaid
                    ? AppColors.success
                    : item.status == ReceivableStatusWire.cancelled
                    ? AppColors.muted
                    : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.md,
            children: <Widget>[
              LabelledValue(
                label: l.totalDue,
                value: '${formatMoney(item.total)} $currency',
              ),
              LabelledValue(label: l.totalPaid, value: formatMoney(item.paid)),
              LabelledValue(label: l.debt, value: formatMoney(item.balance)),
            ],
          ),
        ],
      ),
    );
  }
}
