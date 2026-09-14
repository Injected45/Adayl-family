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
import 'member_value_bar.dart';
import 'member_years_chart.dart';
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
/// ── HIS ACCOUNT, AND NOTHING OF THE FUND'S ──────────────────────────────────
/// The page once carried a «الجمعية» card — the share of everything collected
/// that went back to members, and the largest single payment to one man. The
/// association removed it entirely on 14/09. What is left is his own: what he
/// paid, what he received, the balance between them, his ratio by the
/// association's formula, and the two year by year.
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
                  // ── ⚠ دفعتَ أخضر، استلمتَ أحمر ───────────────────────
                  //
                  //   They were the other way round for one revision, on the
                  //   reasoning that «money leaving him is red». The
                  //   association reversed it, and the reversed pair is the
                  //   coherent one: these two figures now AGREE WITH THE
                  //   VERDICT UNDER THEM. Paying more ends in «رصيد مستحق لك»
                  //   in green; receiving more ends in «رصيد مستحق عليه» in
                  //   red. A figure that argued with the conclusion drawn from
                  //   it would be a card at war with itself.
                  tone: AppColors.success,
                  amount: value.paid,
                ),
              ),
              Container(width: 1, height: 44, color: GlassColors.wellEdge),
              Expanded(
                child: _Figure(
                  label: l.valueReceived,
                  amount: value.received,
                  tone: AppColors.danger,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── The difference, named ─────────────────────────────────────────
        _Verdict(gap: gap, ahead: got > paid, even: got == paid),

        // ── ⚠ حاويةُ «الجمعية» أُزيلت بالكامل (14/09) ─────────────────────
        // It held «عاد إلى العدايل X% من إجمالي المحصَّل» — one association-wide
        // number read by every man as his own — and «أكبر ما صُرف لمشترك
        // واحد». The association asked for the heading and everything under it
        // gone: «اريدك ان تخفيها تمام من التطبيق ولا اريد ظهورها بالمره». This
        // screen is his own account now; what came back to HIM is the card
        // below, by the association's formula.

        // ── حركته، في الفراغ أسفل الشاشة ──────────────────────────────────
        // ⚠ IT DRAWS ITSELF ONLY IF THERE IS MOVEMENT. A man who has never
        //   paid gets the four figures and nothing else, rather than a
        //   full-width graphic of twelve empty columns on the one screen
        //   built to answer «ما الجدوى».
        const SizedBox(height: AppSpacing.xl),
        // ── النسبة أولاً، ثمّ السنوات ───────────────────────────────────
        // ⚠ THE PROPORTION IS ANSWERABLE FROM THE FIRST RECEIPT, so it comes
        //   first: ما استلمتَ ÷ ما دفعتَ × 100, to two decimals, with the
        //   formula under it. The years beneath are the same two figures
        //   spread over time.
        MemberValueBar(paid: value.paid, received: value.received),
        // ⚠ YEAR BY YEAR SINCE 14/09, NOT A CALENDAR YEAR OF WAVES. The waves
        //   were called «غير منطقي وغير واضح»: a curve invents the months
        //   between readings, and one calendar year holds none of a member's
        //   aid when it came in 2018 and 2022. See MemberYearsChart.
        //
        // ⚠ AND IT DRAWS NOTHING ON A DATABASE WITHOUT PATCH_20260914 — `years`
        //   parses empty there — rather than failing the whole screen.
        const SizedBox(height: AppSpacing.xl),
        MemberYearsChart(years: value.years),

        const SizedBox(height: AppSpacing.xl),
      ],
    );
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
      Text(label, style: TextStyle(fontSize: 12, color: AppColors.muted)),
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
          // ── ⚠ رصيدٌ لك، أو رصيدٌ عليك ────────────────────────────────
          //
          //   «أعطتك الجمعية أكثر مما دفعتَ» / «فائض تكافلك» were the old
          //   headings, and they deliberately avoided the word «رصيد» — see
          //   the ARB descriptions, which are kept and now record why that
          //   changed. The association asked for a plain ledger reading:
          //   paid more → a balance in his favour, received more → a balance
          //   against him, green and red accordingly.
          //
          // ⚠ AND IT IS A READING, NOT AN OBLIGATION. Nothing in the database
          //   moved: a disbursement still writes no receivable, no payment and
          //   no allocation, so this figure can never appear in his statement
          //   and can never be collected from him. «الجمعية خيرية» is enforced
          //   by the schema, not by these two words — which is exactly why
          //   changing them is safe.
          Text(
            ahead ? l.valueOwedByHim : l.valueOwedToHim,
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
              // ⚠ RED WHEN HE RECEIVED MORE, GREEN WHEN HE PAID MORE — the
              //   opposite of what this line used to do, and asked for in
              //   those words. It used to paint «the association gave you
              //   more» green as good news; it now reads as a balance
              //   standing against him, which is what a ledger says.
              color: ahead ? AppColors.danger : AppColors.success,
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
