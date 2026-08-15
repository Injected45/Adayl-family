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
      body: AsyncView<AdeelDetail>(
        value: detail,
        onRetry: () => ref.invalidate(adeelDetailProvider(adeelId)),
        builder: (AdeelDetail detail) {
          final AdeelView adeel = detail.adeel;
          return ListView(
            padding: screenPadding(context),
            children: <Widget>[
              Text(
                adeel.fullName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                adeel.adeelCode,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),

              _SummaryCard(detail: detail, currency: currency),
              const SizedBox(height: AppSpacing.lg),

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

              _SectionCard(
                title: l.personalData,
                child: Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.lg,
                  children: <Widget>[
                    LabelledValue(label: l.phone, value: adeel.phone),
                    LabelledValue(
                      label: l.subscriptionNo,
                      value: adeel.subscriptionNo,
                    ),
                    LabelledValue(label: l.dateOfBirth, value: adeel.dob),
                    LabelledValue(
                      label: l.age,
                      value: adeel.age == null ? '' : l.ageYears(adeel.age!),
                    ),
                    LabelledValue(
                      label: l.nationality,
                      value: adeel.nationality,
                    ),
                    LabelledValue(label: l.workplace, value: adeel.workplace),
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
              ),
              const SizedBox(height: AppSpacing.lg),

              // The sons section is gone with the household. What a reader
              // actually needs here is the same thing it needed there — what is
              // owed and for which months — and that is now the man's own dues.
              //
              // `duesSection`, not `myDuesTitle`: this is staff looking at
              // somebody else's record, so "اشتراكاتي" would be the wrong voice.
              // The portal keeps the first-person one.
              _SectionCard(
                title: l.duesSection,
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.detail, required this.currency});

  final AdeelDetail detail;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool owes = (double.tryParse(detail.debt) ?? 0) > 0;

    // This is the one hero surface on the screen, so it is the one that earns a
    // blur.
    return GlassSurface(
      blurred: true,
      lifted: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
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
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l.familySummary,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(title: title, child: child);
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
