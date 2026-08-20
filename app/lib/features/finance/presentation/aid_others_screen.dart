import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/state/refresh.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// «أسلاف للغير» — what the association gave everybody except the reader.
///
/// ── THIS SCREEN EXISTS BECAUSE THE ASSOCIATION DECIDED IT SHOULD ────────────
/// Until PATCH_20260820b a member saw his own aid and nothing else, and the
/// comment beside `read_own_disbursements` said why: a row here records that a
/// NAMED man received إعانة — for a bereavement, a birth, an emergency — which
/// is the most private fact this system holds. The association chose otherwise,
/// in these words: «كل شيء بالأسماء».
///
/// ⚠ AND THE DECISION LIVES IN POSTGRES, NOT HERE. `read_all_disbursements_adeel`
///   is what admits a member to the rows; `api_aid_others` is SECURITY INVOKER
///   and reads under his own policies. Drop that one policy and this screen
///   empties itself with no code change — which is the property that makes the
///   choice reversible in the only way it can be.
///
/// ── WHAT IT DOES NOT SHOW ───────────────────────────────────────────────────
/// What another man OWES. The register is still scoped to his own row, and the
/// name on each voucher is the SNAPSHOT on the row rather than a lookup — so
/// this screen needs no access to the register at all, and gets none.
///
/// Cancelled vouchers are absent, unlike his own ledger where rule 9 keeps them
/// struck through: his own reversals are his history, another man's are an
/// administrative correction, and showing them invites the reading that
/// somebody was given something and had it taken back.
class AidOthersScreen extends ConsumerWidget {
  const AidOthersScreen({required this.adeelId, super.key});

  final int adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.aidOthersTitle)),
        body: RefreshIndicator(
          // The whole app, not this provider. A member has no ⟳ button anywhere
          // — the portal carries no app bar — so the pull is his only refresh
          // and it has to be the complete one. See core/state/refresh.dart.
          onRefresh: () async => refreshAll(ref),
          child: AsyncView<AidOthers>(
            value: ref.watch(aidOthersProvider(adeelId)),
            onRetry: () => ref.invalidate(aidOthersProvider(adeelId)),
            builder: (AidOthers data) => _Body(aid: data),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.aid});

  final AidOthers aid;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    if (aid.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl * 2),
          EmptyStateView(
            icon: Icons.volunteer_activism_outlined,
            title: l.aidOthersEmpty,
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        // ── The headline ────────────────────────────────────────────────────
        // Summed by Postgres, never here: money is text end to end in this app,
        // and a screen that added the association's amounts itself would put
        // them on binary floating point.
        GlassCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      l.aidOthersTitle,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      formatMoney(aid.total),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                l.aidVoucherCount(aid.count),
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // ── Who received, largest first ─────────────────────────────────────
        // The question this screen is opened with is «من أخذ»، not «متى» — so
        // the men come before the vouchers, and a list in date order would
        // answer something nobody asked.
        Text(
          l.aidOthersRecipients,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final AidRecipient m in aid.men) _RecipientRow(man: m),

        const SizedBox(height: AppSpacing.xl),
        Text(
          l.aidOthersAll,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final AidLedgerEntry v in aid.vouchers) _VoucherRow(entry: v),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({required this.man});

  final AidRecipient man;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  man.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.aidVoucherCount(man.count),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(man.total),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoucherRow extends StatelessWidget {
  const _VoucherRow({required this.entry});

  final AidLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  entry.voucher.payeeName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // The occasion, then the date. «لماذا» before «متى»: an
                  // association reads its charity by what it was for.
                  '${entry.voucher.category} · ${formatDate(entry.voucher.spentAt)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(entry.voucher.amount),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
