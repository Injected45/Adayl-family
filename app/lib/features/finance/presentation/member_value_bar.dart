import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../l10n/app_localizations.dart';

/// «من كل مئة دفعتَها، كم عاد إليك» — الجدوى في صورة واحدة.
///
/// ── لماذا هذا حلّ محلّ الرسم الزمني ────────────────────────────────────────
/// The first chart plotted twelve months. The association looked at it and said
/// «لا يفيدني بشيء», and it was right — not because the chart was wrong but
/// because the DATA has no time in it yet: everything was entered in one month,
/// so eleven flat months met a vertical jump. A trend needs a history this
/// association will not have for a year.
///
/// ⚠ AND «الجدوى» ASKS A RATIO, NOT A TREND. «كم دفعتُ مقابل كم أخذت» is one
///   proportion, it is answerable from the very first receipt, and it goes on
///   being the same question in five years. A bar answers it; a time axis
///   answers a question nobody asked yet.
///
/// ⚠ IT IS THE SAME SENTENCE THE ASSOCIATION BLOCK ALREADY MAKES — «من كل 100
///   محصّلة، صُرف 17 على المشتركين» — read for one man instead of for the fund.
///   Two scales, one idea, so the screen says one thing twice rather than two
///   things once.
class MemberValueBar extends StatelessWidget {
  const MemberValueBar({required this.paid, required this.received, super.key});

  /// Money as text, end to end. Parsed here to MEASURE a rectangle and never
  /// printed as a number: every figure on screen is the server's own string.
  final String paid;
  final String received;

  double get _paid => double.tryParse(paid) ?? 0;
  double get _received => double.tryParse(received) ?? 0;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    // ⚠ NOTHING TO COMPARE IS NOT A BAR OF ZERO. A man who has never paid gets
    //   no proportion at all — the figures above already say so, and an empty
    //   track would invite him to read it as «you got nothing back».
    if (_paid <= 0) return const SizedBox.shrink();

    final double share = _received / _paid;
    // ⚠ CAPPED FOR THE DRAWING, NOT FOR THE READING. A man given more than he
    //   paid is the point of a charitable fund, not an error — the bar fills
    //   and the line beneath says so in words.
    final double fill = math.min(share, 1);
    final int percent = (share * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.valueShareTitle,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ── The sentence, before the picture ──────────────────────────
              // ⚠ THE NUMBER IS THE ANSWER AND THE BAR IS THE ILLUSTRATION,
              //   in that order. A bar alone makes the reader estimate a
              //   percentage he could have been told.
              Text(
                share >= 1
                    ? l.valueShareOver(percent)
                    : l.valueShareOf(percent),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  // ⚠ RED BELOW 100%, BY REQUEST — and it is worth knowing what
                  //   it says. Everywhere else in this app red means «عليك»: a
                  //   debt, something owed. Here it means «عاد إليك أقل مما
                  //   دفعت», which in a صندوق تكافل is the ORDINARY and
                  //   fortunate case — a man who has not needed the fund. The
                  //   association weighed that and chose the colour anyway: it
                  //   marks who has drawn on the fund and who has carried it.
                  color: share >= 1 ? AppColors.success : AppColors.danger,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── The bar ───────────────────────────────────────────────────
              // The TRACK is what he paid; the FILL is what came back. One
              // rectangle inside another, which is the only shape that says
              // «part of» without a legend.
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Stack(
                  children: <Widget>[
                    Container(height: 22, color: GlassColors.well),
                    FractionallySizedBox(
                      widthFactor: fill,
                      child: Container(height: 22, color: AppColors.success),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── The two figures, at the two ends ──────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  // ⚠ THE THIRD PLACE THESE TWO FIGURES APPEAR, and it was
                  //   nearly missed: «استلمتَ» was green and «دفعتَ» was BLUE
                  //   here, so a sweep that only looked for green-and-red
                  //   would have walked past it. Both now match the card above
                  //   and the chart below — «دفعتَ» green, «استلمتَ» red — and
                  //   one figure in a different colour on a third container is
                  //   how a reader learns to distrust all of them.
                  _End(
                    label: l.valueReceived,
                    value: received,
                    tone: AppColors.danger,
                  ),
                  _End(
                    label: l.valuePaid,
                    value: paid,
                    tone: AppColors.success,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _End extends StatelessWidget {
  const _End({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(label, style: TextStyle(fontSize: 11, color: AppColors.muted)),
      Text(
        formatMoney(value),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          color: tone,
        ),
      ),
    ],
  );
}
