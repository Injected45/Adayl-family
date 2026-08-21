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
import 'aid_ledger.dart';
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
/// ── AND IT IS THE SAME LEDGER AS «أسلافي», NOT A LOOK-ALIKE ─────────────────
/// The association asked for it in those words — «انسخ الكود ونفذه على أسلاف
/// للغير بالكامل». So the table is [AidLedger], the one widget both screens
/// build: «#، البند، القيمة، الإجمالي», one row open at a time, the ordinal
/// belonging to the voucher rather than to the loop.
///
/// ⚠ COPIED INSTEAD, THE TWO WOULD DRIFT — and every rule inside that table was
///   argued once and is easy to lose the second time.
///
/// ── AND THE SCOPE IS IN POSTGRES ────────────────────────────────────────────
/// `read_collective_disbursements` admits a bound member to exactly the rows
/// with no payee; `api_aid_others` is SECURITY INVOKER and reads under his own
/// policies. Drop that one policy and this screen empties itself with no code
/// change — nothing here decides who may read what.
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

        // ⚠ NO «حسب الوجه» BREAKDOWN HERE ANY MORE, at the association's
        //   request: «يوجد عنوان باسم حسب الوجه وتحته حقول الصرف لا اريدها
        //   تظهر». It was a heading and a card per occasion above the table,
        //   and it said the same thing the table already says — every voucher
        //   below carries its وجه in the البند column, so the breakdown was a
        //   second summary of rows the reader can see. Two answers to one
        //   question is what makes a screen feel long.
        //
        //   `api_aid_others` still RETURNS byCategory and the model still
        //   parses it — the server contract is unchanged and the staff-side
        //   «الإنفاق حسب الوجه» in payments_screen still uses it. Only this
        //   screen stops drawing it.

        // ── The ledger ──────────────────────────────────────────────────────
        // ⚠ THE SAME WIDGET «أسلافي» DRAWS, at the association's request. Not a
        //   second implementation that looks like it: the ordinal belongs to
        //   the voucher, the running total is the server's, a reversed line
        //   keeps its balance, and one detail block is open at a time. Each of
        //   those is a decision that took an argument, and a copy is a second
        //   place to lose it silently.
        //
        // `all` and `rows` are the same list here: this screen carries no
        // search box, so nothing narrows the table and the ordinal is simply
        // the position.
        GlassPanel(
          title: l.aidOthersAll,
          icon: Icons.receipt_long_outlined,
          child: AidLedger(all: aid.vouchers, rows: aid.vouchers),
        ),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}
