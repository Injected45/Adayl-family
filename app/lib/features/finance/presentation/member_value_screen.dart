import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/state/refresh.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'member_months_chart.dart';
import 'providers.dart';

/// «الجدوى» — what a man put in, what he got out, and what the fund did.
///
/// ── THE RULE THIS SCREEN IS BUILT AGAINST, AND HOW IT SURVIVES ──────────────
/// «الجمعية خيرية»: aid is never deducted from a subscription. That is why the
/// aid ledger is a separate screen from the statement — the place the rule would
/// actually break is a layout that puts «ما صُرف له» beside «ما عليه» and invites
/// the eye to subtract.
///
/// The association asked for exactly that subtraction. So it is here, and the
/// rule survives in the WORDING rather than in a warning nobody reads:
///
///   received > paid  →  «أعطتك الجمعية أكثر مما دفعتَ بـ …»
///   paid > received  →  «فائض تكافلك» — what he contributed to others
///
/// ⚠ THE SECOND LABEL IS THE WHOLE SCREEN. Calling it a loss, or «لك عند
///   الجمعية», would teach a member that his subscriptions are a deposit he is
///   owed back — and teach the man who has taken more than he gave that he is
///   square and may stop. In a mutual fund the surplus of the men nothing
///   happened to IS what covers the man something happened to. That is not a
///   consolation for a bad number; it is what the number means.
///
/// ── AND WHY THESE FOUR STATISTICS AND NOT AN AVERAGE ────────────────────────
/// «ما الجدوى» is a question about COVER, not about return. An average payout
/// answers neither: most members receive nothing in a good year, and the mean
/// of mostly-zero is a small number that makes the fund look pointless.
///
/// So: how much of every hundred collected comes back to members, how many men
/// the fund has actually stood behind, and — the one that answers the question —
/// the LARGEST single payment it has ever made to one man. That last figure is
/// what a member is buying, and no average can say it.
///
/// Nothing is computed here. Every figure is summed by `api_member_value`,
/// because money is text end to end in this app.
class MemberValueScreen extends ConsumerWidget {
  const MemberValueScreen({required this.adeelId, super.key});

  final int adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.valueTitle)),
        body: RefreshIndicator(
          onRefresh: () async => refreshAll(ref),
          child: AsyncView<MemberValue>(
            value: ref.watch(memberValueProvider(adeelId)),
            onRetry: () => ref.invalidate(memberValueProvider(adeelId)),
            builder: (MemberValue v) => _Body(value: v),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.value});

  final MemberValue value;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    // ⚠ COMPARED, NEVER SUMMED. Reading the sign of a difference the SERVER
    //   computed is not the same as adding money in Dart — and the two figures
    //   themselves are printed exactly as they arrived.
    final double paid = double.tryParse(value.paid) ?? 0;
    final double got = double.tryParse(value.received) ?? 0;
    final double gap = (got - paid).abs();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        // ── His two figures, side by side and NOT stacked ──────────────────
        // Stacked, the lower one reads as a correction to the upper. Side by
        // side they read as two facts, which is what they are.
        GlassCard(
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Figure(
                  label: l.valuePaid,
                  amount: value.paid,
                  tone: AppColors.info,
                ),
              ),
              Container(width: 1, height: 44, color: GlassColors.wellEdge),
              Expanded(
                child: _Figure(
                  label: l.valueReceived,
                  amount: value.received,
                  tone: AppColors.success,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── The difference, named ─────────────────────────────────────────
        _Verdict(gap: gap, ahead: got > paid, even: got == paid),

        const SizedBox(height: AppSpacing.xl),
        Text(
          l.valueFund,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── What the fund does, in three lines and no prose ────────────────
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Line(text: l.valueBackToMembers(_rate(value))),
              const SizedBox(height: AppSpacing.sm),
              _Line(text: l.valueHelped(value.helped, value.members)),
              const SizedBox(height: AppSpacing.md),
              // ⚠ THE FIGURE THAT ANSWERS THE QUESTION. What the association has
              //   actually put behind one man when something happened to him —
              //   which is what a member is buying, and what no average says.
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.valueLargest,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Text(
                    formatMoney(value.largest),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── حركته، في الفراغ أسفل الشاشة ──────────────────────────────────
        // ⚠ IT DRAWS ITSELF ONLY IF THERE IS MOVEMENT. A man who has never
        //   paid gets the four figures and nothing else, rather than a
        //   full-width graphic of twelve empty columns on the one screen
        //   built to answer «ما الجدوى».
        const SizedBox(height: AppSpacing.xl),
        MemberMonthsChart(months: value.months),

        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }

  /// How much of every hundred collected has gone back to named members.
  ///
  /// Rounded to a whole number: «٧٨ من ١٠٠» is read at a glance and «77.63» is
  /// not, and the second digit of a ratio nobody acts on is noise.
  String _rate(MemberValue v) {
    final double collected = double.tryParse(v.collected) ?? 0;
    if (collected <= 0) return '0';
    final double back = double.tryParse(v.toMembers) ?? 0;
    return (back / collected * 100).round().toString();
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    required this.tone,
  });

  final String label;
  final String amount;
  final Color tone;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 2),
      Text(
        formatMoney(amount),
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: tone,
        ),
      ),
    ],
  );
}

/// The one sentence the whole screen turns on.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.gap, required this.ahead, required this.even});

  final double gap;
  final bool ahead;
  final bool even;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    if (even) {
      return GlassCard(
        child: Center(
          child: Text(
            l.valueEven,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return GlassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            ahead ? l.valueAhead : l.valueSurplus,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // The gap is printed from the server's own two figures, formatted
            // the way every other amount in the app is.
            formatMoney(gap.toStringAsFixed(2)),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              // ⚠ NEITHER GREEN NOR RED for the surplus. Green would read as a
              //   gain he can spend and red as a loss the association owes him,
              //   and it is neither — see the class note.
              color: ahead ? AppColors.success : AppColors.info,
            ),
          ),
          // ⚠ THE SENTENCE UNDER THE FIGURE IS GONE, at the association’s
          //   request — «ساهمتَ به في مساعدة غيرك…». Every heading above a
          //   VALUE stays, and so does every line inside «الجمعية»: those
          //   were asked for and kept. This one explained a figure that the
          //   heading directly above it already names.
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 13, height: 1.5));
}
