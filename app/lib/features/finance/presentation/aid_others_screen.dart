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

/// «أسلاف للغير» — الصرف الجماعي: what the association spent on everybody.
///
/// ── WHAT IT SHOWS ───────────────────────────────────────────────────────────
/// فطور رمضان and its like. A collective voucher is attributed to nobody —
/// `ck_disb_shape` refuses a payee on one — so this screen names no member and
/// could not be made to.
///
/// ⚠ AN EARLIER DRAFT LISTED OTHER MEMBERS' AID, BY NAME, and the association
///   chose otherwise after seeing it. That is the better rule, not merely the
///   safer one: a row saying a named man was given something for a bereavement
///   is the most private fact this system holds, while a row saying 400 went on
///   فطور رمضان answers what a member actually wants to know — «أين يذهب مالي»
///   — and exposes nobody at all.
///
/// ── AND THE SCOPE IS IN POSTGRES ────────────────────────────────────────────
/// `read_collective_disbursements` admits a bound member to exactly the rows
/// with no payee; `api_aid_others` is SECURITY INVOKER and reads under his own
/// policies. Drop that one policy and this screen empties itself with no code
/// change — nothing here decides who may read what.
///
/// The وجه leads and the vouchers follow, because «على ماذا أُنفق» is the
/// question, and a communal expense has no man to group under.
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

        // ── By occasion, largest first ──────────────────────────────────────
        // «على ماذا أُنفق» is the question, not «متى» — so the headings come
        // before the vouchers, and a list in date order would answer something
        // nobody asked.
        Text(
          l.aidOthersRecipients,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final ExpenseByCategory c in aid.byCategory) _CategoryRow(row: c),

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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.row});

  final ExpenseByCategory row;

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
                  row.category,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l.aidVoucherCount(row.count),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(row.total),
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
                // ⚠ THE OCCASION LEADS, because there is no payee to lead with.
                //   A collective voucher carries no man at all — that is what
                //   makes it collective — so the وجه is what identifies it, and
                //   printing an empty payeeName here would leave a blank line
                //   where a reader expects a name.
                Text(
                  entry.voucher.category,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // The date, and the note when there is one — «فطور رمضان» says
                  // what it was for and the note says which one.
                  entry.voucher.note.isEmpty
                      ? formatDate(entry.voucher.spentAt)
                      : '${formatDate(entry.voucher.spentAt)} · ${entry.voucher.note}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
