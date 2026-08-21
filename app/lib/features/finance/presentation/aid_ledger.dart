import 'package:flutter/material.dart';

import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';

/// The aid ledger — «#، البند، القيمة، الإجمالي» with one row open at a time.
///
/// ── WHY THIS IS A FILE AND NOT A COPY ───────────────────────────────────────
/// «أسلافي» and «أسلاف للغير» answer different questions about the same table:
/// what the association gave ONE man, and what it spent on EVERYBODY. The
/// association asked for the second to read exactly like the first — «انسخ
/// الكود ونفذه على أسلاف للغير بالكامل».
///
/// ⚠ COPIED, THE TWO WOULD DRIFT. Every rule in here was argued once and is
///   easy to lose the second time: the columns are MEASURED rather than
///   divided into thirds, the ordinal belongs to the voucher and not to the
///   loop, a reversed line keeps its balance, and only one detail block is
///   open at a time. A second copy is a second place for each of those to be
///   quietly undone — and nothing would fail when it was.
///
/// ── WHAT THE CALLER SUPPLIES ────────────────────────────────────────────────
/// [all] is the WHOLE ledger and [rows] is what to show. They differ only
/// while a search is narrowing the table, and the difference is load-bearing:
/// the serial number is read from [all], so filtering cannot renumber history.
class AidLedger extends StatefulWidget {
  const AidLedger({
    required this.all,
    required this.rows,
    this.tone = AppColors.danger,
    super.key,
  });

  /// Every entry, oldest first — the source of the ordinal.
  final List<AidLedgerEntry> all;

  /// What to draw. The same list unless a search is narrowing it.
  final List<AidLedgerEntry> rows;

  /// The colour the two money columns are set in.
  ///
  /// ⚠ THE SAME TABLE ANSWERS TWO DIFFERENT QUESTIONS, and the colour is the
  ///   one place they part. On «أسلافي» the figures are what the association
  ///   GAVE this man — his, and green at his own request. On «أسلاف للغير»
  ///   they are what left the treasury, which is red on every other screen in
  ///   this app and red on that one too, headline and headings included.
  ///
  ///   A parameter, not a second widget: the LAYOUT is what the association
  ///   asked to be identical — «نفس طريقة العرض» — and layout is the part
  ///   that drifts when it is copied. A colour does not drift. It is one word
  ///   at each call site, and it keeps each screen consistent with its own
  ///   headline instead of with the other screen's.
  final Color tone;

  @override
  State<AidLedger> createState() => _AidLedgerState();
}

class _AidLedgerState extends State<AidLedger> {
  /// The ONE voucher whose detail is open, by id. Null is none.
  ///
  /// ── WHY THE STATE IS HERE AND NOT IN EACH ROW ───────────────────────────
  /// It used to live in the row, which made expansion independent: open four
  /// headings and four paragraphs stack down the page, and the table the
  /// reader came to scan stops being one. The association asked for an
  /// accordion — opening a second closes the first — and that is a rule about
  /// the SET of rows, which no single row can enforce about its siblings.
  ///
  /// ⚠ BY ID, NEVER BY INDEX. A search rewrites the list, so the row at
  ///   position 2 after typing is a different voucher from the one before it.
  ///   An index would leave another voucher's detail hanging open under a line
  ///   it does not belong to, and nothing on screen would say so. An id that
  ///   filters out matches nothing and the block closes, which is the right
  ///   answer to «the row you were reading is gone».
  int? _openId;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Column(
      children: <Widget>[
          if (widget.rows.isEmpty)
            EmptyStateView(icon: Icons.search_off, title: l.aidNoMatch)
          else
            // ── The columns are measured, not divided ────────────────────────
            // LayoutBuilder because the answer depends on the width the panel
            // actually got, which nothing above it knows. Computed once here
            // and handed down, so the header and every row are laid out from
            // the SAME numbers — which is the whole of why the heading sits
            // centred over its own column.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                final TextScaler scaler = MediaQuery.textScalerOf(context);
                const TextStyle headStyle = TextStyle(
                  fontSize: kAidLedgerSize,
                  fontWeight: FontWeight.w800,
                );
                final _LedgerMetrics metrics = _LedgerMetrics(
                  // The ordinal column: at most three digits, and the heading
                  // word is wider than any of them. A tighter cap than the
                  // money columns because it is the least informative of the
                  // four and must never be the one that squeezes البند.
                  serial: _columnWidth(
                    values: <String>[
                      l.aidColSerial,
                      '${widget.all.length}',
                    ],
                    style: headStyle,
                    scaler: scaler,
                    available: c.maxWidth,
                    share: 0.18,
                  ),
                  // The heading is measured with the values, not assumed
                  // narrower than them: «الإجمالي» is wider than «600.00».
                  amount: _columnWidth(
                    values: <String>[
                      l.aidColAmount,
                      for (final AidLedgerEntry e in widget.rows)
                        formatMoney(e.voucher.amount),
                    ],
                    style: headStyle,
                    scaler: scaler,
                    available: c.maxWidth,
                  ),
                  running: _columnWidth(
                    values: <String>[
                      l.aidColRunning,
                      for (final AidLedgerEntry e in widget.rows)
                        formatMoney(e.runningTotal),
                    ],
                    style: headStyle,
                    scaler: scaler,
                    available: c.maxWidth,
                  ),
                );

                return Column(
                  children: <Widget>[
                    _LedgerHead(metrics: metrics),
                    // Keyed by voucher id: a search rewrites the list, and
                    // without a key Flutter would reuse a row's element for
                    // whatever voucher lands at that index.
                    //
                    // The serial comes from the FULL ledger, not from this
                    // loop's index: it belongs to the voucher, exactly as the
                    // running total does, so a filter cannot renumber history.
                    //
                    // `open` and `onToggle` come from the PANEL, which is what
                    // makes the rows an accordion: a row cannot know whether a
                    // sibling is open, so no row can close one.
                    for (final AidLedgerEntry e in widget.rows)
                      _LedgerLine(
                        key: ValueKey<int>(e.voucher.id),
                        entry: e,
                        metrics: metrics,
                        tone: widget.tone,
                        serial: widget.all.indexOf(e) + 1,
                        open: _openId == e.voucher.id,
                        onToggle: () => setState(
                          () => _openId = _openId == e.voucher.id
                              ? null
                              : e.voucher.id,
                        ),
                      ),
                  ],
                );
              },
            ),
      ],
    );
  }
}

/// The size every cell in the table is set at.
const double kAidLedgerSize = 12;

/// How wide each money column actually needs to be.
///
/// ── WHY THE COLUMNS ARE NOT THIRDS ──────────────────────────────────────────
/// They were, and equal thirds are the wrong answer to an unequal question.
/// «500.00» needs about half the room a third gives it, while «مناسبة اجتماعية»
/// needs more than a third and wrapped — so the table spent its width on the
/// two columns that had none to spend and starved the one that did.
///
/// So the two money columns are MEASURED against the values they will actually
/// hold, and البند is given everything left over. Small figures leave a wide
/// heading column and no wrapping at all; large ones take what they need and
/// the heading wraps only when it genuinely must.
///
/// ── MEASURED, NOT GUESSED ───────────────────────────────────────────────────
/// A TextPainter laid out with the very style and text scale the cell will use,
/// so the answer holds at any system font size. A hard-coded 80dp would be
/// right on one phone and wrong on the next — and wrong in the direction that
/// clips money.
///
/// Computed ONCE per render and handed to both the header and every row, which
/// is what makes the heading sit centred over its own column: two independently
/// sized Rows agree only by coincidence, and stop agreeing the first time a
/// value gets longer than the word above it.
class _LedgerMetrics {
  const _LedgerMetrics({
    required this.serial,
    required this.amount,
    required this.running,
  });

  /// The ordinal column at the far right. Narrow by nature — it holds one to
  /// three digits — and capped tighter than the money columns for the same
  /// reason: it is the least informative of the four and must never be the one
  /// that squeezes البند.
  final double serial;

  final double amount;
  final double running;
}

/// The widest string a column will hold, plus breathing room.
///
/// ⚠ CAPPED at a share of the table. A pathological figure — a treasury
///   mis-keyed as 99,999,999.00 — would otherwise take the width البند needs to
///   stay readable, and the answer to one bad row must not be an unreadable
///   table. Past the cap the money wraps instead, which is the same rule every
///   other cell here follows.
double _columnWidth({
  required Iterable<String> values,
  required TextStyle style,
  required TextScaler scaler,
  required double available,
  double share = 0.30,
}) {
  double widest = 0;
  for (final String v in values) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: v, style: style),
      textDirection: TextDirection.rtl,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = widest > tp.width ? widest : tp.width;
    tp.dispose();
  }
  // AppSpacing.sm each side: a column packed to the exact pixel reads as two
  // figures colliding, not as two columns.
  final double padded = widest + AppSpacing.sm * 2;
  final double cap = available * share;
  return padded > cap ? cap : padded;
}

/// One cell: one line when the words fit, two when they do not.
///
/// ── WHAT THIS IS NOT ────────────────────────────────────────────────────────
/// It was briefly a FittedBox that SHRANK anything too wide, so «مناسبة
/// اجتماعية» rendered a point smaller than «مولود» beside it. That bought a
/// single line at the price of a column with two type sizes in it, which is a
/// rule fighting the layout rather than serving it — and the association was
/// right to reject it. Text on a phone wraps; that is what text does.
///
/// So the cell simply lays out in the width it has. Short values take one line
/// and the row stays tight; a long one opens a second line and finishes the
/// word there, at the SAME size as everything around it.
///
/// ── WHAT MAKES TWO LINES LOOK DELIBERATE ────────────────────────────────────
/// Three things, and without them a wrapped row reads as a mistake:
///
///   • `height: 1.35` — the default leading is set for prose, and two lines of
///     a 12px table cell at it sit almost touching;
///   • the ROW is centred vertically (see _LedgerLine), so a two-line heading
///     does not drag the two figures beside it up to its first line;
///   • `maxLines: 2` with an ellipsis as the backstop. Two is what the widest
///     of the six headings needs; anything demanding a third would be a value
///     nobody typed, and letting one row grow without limit would push the rest
///     of the table off the screen.
class _Cell extends StatelessWidget {
  const _Cell(this.text, {required this.style, this.align = TextAlign.center});

  final String text;
  final TextStyle style;

  /// Centred by default — the two money columns and the ordinal read as stacks
  /// under their headings. البند passes `start`, which in RTL is the RIGHT
  /// edge: it is the column with words in it, and words are read from where
  /// they begin. Centring them left a ragged margin against the «#» beside it
  /// and cost the eye a moment on every row finding where the heading starts.
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: style.copyWith(height: 1.35),
    textAlign: align,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
  );
}

class _LedgerHead extends StatelessWidget {
  const _LedgerHead({required this.metrics});

  final _LedgerMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    const TextStyle style = TextStyle(
      fontSize: kAidLedgerSize,
      fontWeight: FontWeight.w800,
      color: AppColors.muted,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // البند takes what the two figures leave. It is the column with words
          // in it, so it is the one that benefits from every pixel the numbers
          // did not need.
          // FIRST in the children list, which in RTL puts it at the FAR RIGHT.
          SizedBox(
            width: metrics.serial,
            child: _Cell(l.aidColSerial, style: style),
          ),
          // Start-aligned, so the heading sits over words that begin in the
          // same place — flush with «#» on its right.
          Expanded(
            child: _Cell(
              l.aidColCategory,
              style: style,
              align: TextAlign.start,
            ),
          ),
          SizedBox(
            width: metrics.amount,
            child: _Cell(l.aidColAmount, style: style),
          ),
          SizedBox(
            width: metrics.running,
            child: _Cell(l.aidColRunning, style: style),
          ),
        ],
      ),
    );
  }
}

/// One ledger line, and the detail it hides until it is asked for.
///
/// ── WHY THE DETAIL IS FOLDED AWAY ───────────────────────────────────────────
/// The columns are the accounting and they must stay readable down the page: a
/// member scanning years of aid is reading a TABLE, and a table stops being one
/// the moment every row grows a paragraph under it. The note is the paragraph —
/// «اسم المولود» is short, but "أعطي له لعلاج والدته في تونس وتم تسليمه
/// بحضور..." is not, and one long note pushes every other line off the screen.
///
/// So the line stays one line, and tapping it opens the rest beneath it.
///
/// ── AND ONLY ONE AT A TIME ──────────────────────────────────────────────────
/// [open] and [onToggle] come from the panel; this widget holds no state of its
/// own. That is the whole mechanism of the accordion the association asked for:
/// a row cannot know whether a sibling is open, so no row can close one. Four
/// open at once put four paragraphs down a page whose point is a table.
class _LedgerLine extends StatelessWidget {
  const _LedgerLine({
    required this.entry,
    required this.metrics,
    required this.tone,
    required this.serial,
    required this.open,
    required this.onToggle,
    super.key,
  });

  final AidLedgerEntry entry;
  final _LedgerMetrics metrics;

  /// Both money columns, from the screen above — see AidLedger.tone.
  final Color tone;

  /// His position in the FULL ledger, oldest as 1 — not in the filtered list.
  /// The number belongs to the voucher, exactly as the running total does, so a
  /// search cannot renumber history.
  final int serial;

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final DisbursementView v = entry.voucher;
    final bool cancelled = v.cancelled;
    final TextStyle base = TextStyle(
      fontSize: kAidLedgerSize,
      color: cancelled ? AppColors.muted : null,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                // ── Two lines must not drag the figures up with them ───────
                // A wrapped heading makes its cell taller than the two beside
                // it, and with the default top alignment the two amounts would
                // sit level with its FIRST line — the row would read as though
                // the money belonged to the word above rather than to the row.
                // Centred, the three stay on one optical line whatever any of
                // them does.
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  // FIRST in the children list, which in RTL puts it at the FAR
                  // RIGHT — beside the header cell of the same width above it.
                  //
                  // Muted, because it is an index and not a fact about the
                  // money: it should be findable when someone is looking for it
                  // and invisible when they are reading the two figures.
                  SizedBox(
                    width: metrics.serial,
                    child: _Cell(
                      '$serial',
                      style: base.copyWith(color: AppColors.muted),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        // ── The heading FIRST, flush with «#» ───────────────
                        // It used to sit after the chevron and centred, so the
                        // words began at a different place on every row and the
                        // margin against the ordinal was ragged. Now the column
                        // starts where the reader's eye already is.
                        Expanded(
                          child: _Cell(
                            v.category,
                            style: base,
                            align: TextAlign.start,
                          ),
                        ),
                        // The affordance, pinned to the far end of the column.
                        // Without it a tappable table row is a feature nobody
                        // discovers, and it doubles as the state: pointing down
                        // means "there is more", turned means "you are looking
                        // at it".
                        //
                        // At the END rather than before the word, because a
                        // chevron between «#» and the heading is exactly the
                        // gap that made the column look ragged.
                        Icon(
                          open ? Icons.expand_less : Icons.expand_more,
                          size: 14,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: metrics.amount,
                    // ── BOTH COLUMNS TAKE THE SCREEN'S TONE ─────────────
                    // ⚠ AND THE COMMENT THAT USED TO SIT HERE WAS WRONG. It
                    //   said القيمة was red while الإجمالي «is his and is
                    //   green» — and both cells were painted danger. A note
                    //   describing an intention the code never carried out is
                    //   worse than no note: the next reader trusts it and
                    //   goes looking for a bug in the wrong place.
                    //
                    //   What is true now: the screen decides, both columns
                    //   agree, and «أسلافي» is green because what a man was
                    //   given is not a loss to him.
                    child: _Cell(
                      formatMoney(v.amount),
                      style: base.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cancelled ? AppColors.muted : tone,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: metrics.running,
                    // NEVER struck through, even on a reversed line. The amount
                    // was cancelled; the balance at that point in the ledger
                    // was not — it is simply the same figure as the line above,
                    // which is what a reversal looks like in a running total.
                    child: _Cell(
                      formatMoney(entry.runningTotal),
                      style: TextStyle(
                        fontSize: kAidLedgerSize,
                        fontWeight: FontWeight.w800,
                        color: tone,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (open) _LedgerDetail(voucher: v),
        ],
      ),
    );
  }
}

/// What one voucher actually was, opened under its line.
///
/// A recessed well rather than another card: it belongs to the row above it,
/// and a second bordered surface inside a panel reads as a separate record.
class _LedgerDetail extends StatelessWidget {
  const _LedgerDetail({required this.voucher});

  final DisbursementView voucher;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsetsDirectional.only(top: 2, bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: GlassColors.well,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: GlassColors.wellEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── The order the association asked for ─────────────────────────────
          // Two facts to a line where they belong together, one to a line where
          // they do not. It is not decoration: «رقم الإيصال» and «التاريخ»
          // together identify the voucher — they are how it is found in a
          // folder — and «طريقة الدفع» with «المبلغ» is how the money moved.
          // Splitting either pair across two lines made the reader assemble it.
          //
          // The date used to lead the TABLE and cost more width than it
          // answered: «19 أغسطس 2026» wraps beside a one-word heading, so every
          // row was double height. Down here it sits with the number it belongs
          // to.
          _DetailPair(
            firstLabel: l.voucherNo,
            firstValue: voucher.voucherNo,
            secondLabel: l.aidColDate,
            secondValue: formatDate(voucher.spentAt),
          ),
          _DetailPair(
            firstLabel: l.method,
            firstValue: voucher.method,
            secondLabel: l.amount,
            secondValue: formatMoney(voucher.amount),
          ),
          // WHO received it, taken from the voucher itself — `payee_name` is a
          // snapshot the database wrote when the money was handed over, and
          // ck_disb_shape guarantees a member voucher carries one. Nothing here
          // is typed or inferred.
          //
          // Paired with the heading: WHO and WHAT FOR are the two halves of one
          // question, and the block now reads as THREE lines of two columns —
          // every label starting on one of two straight edges — with the note
          // alone underneath. «المُسلِّم» was between them and is gone at the
          // association's request: two lines whose Arabic differs by a letter,
          // one of them about a person the member has no reason to look up.
          // ⚠ AND A COLLECTIVE VOUCHER HAS NO RECIPIENT TO NAME. ck_disb_shape
          //   refuses a payee on one — that is what MAKES it collective — so on
          //   «أسلاف للغير» this pair would print a label with a blank beside
          //   it, and a blank where a name belongs reads as data that failed
          //   to load rather than as a fact about the voucher.
          //
          //   The heading then stands alone, which is honest: فطور رمضان is
          //   the whole answer to «who and what for» when the answer to «who»
          //   is everybody.
          if (voucher.payeeName.isEmpty)
            _DetailLine(
              label: l.expenseCategory,
              value: voucher.category,
            )
          else
            _DetailPair(
              firstLabel: l.recipient,
              firstValue: voucher.payeeName,
              secondLabel: l.expenseCategory,
              secondValue: voucher.category,
            ),
          // Rule 9: a reversed voucher stays legible and says what it is.
          //
          // The ONE thing that breaks the two-column rhythm, and deliberately:
          // it appears on nothing but a struck-through voucher, so a line of
          // its own is what an exception should look like. On every normal
          // voucher the block is three pairs and a note.
          if (voucher.cancelled)
            _DetailLine(label: l.statusLabel, value: l.voided),
          // ── The note is LAST, alone, and BESIDE its label ─────────────────
          // Alone because it is prose of unknown length: «حور» is three letters
          // and a paragraph about a hospital in Tunis is not, and pairing it
          // would give whatever sat next to it a column that shrinks with the
          // sentence. Beside its label rather than under it, because a detail
          // block is read DOWN its labels and a value that steps off that
          // rhythm is the one the eye loses.
          if (voucher.note.isNotEmpty)
            _DetailLine(label: l.aidNoteLabel, value: voucher.note),
        ],
      ),
    );
  }
}

/// Two facts on one line, each with its label ABOVE it.
///
/// Used where the pair IS the fact: a voucher is identified by its number and
/// its date together — that is how it is found in a folder — and money is
/// described by its amount and how it moved. Split across two lines the reader
/// assembles them himself; side by side they read once.
///
/// ── STACKED, NOT THE 96px LABEL COLUMN [_DetailLine] USES ───────────────────
/// That column is right for a full-width line and wrong for half of one: it
/// would leave «10 فبراير 2026» about seventy pixels to live in, so the value
/// wraps, the two halves come out different heights and the labels stop being
/// level — which is the one thing a detail block is read down.
///
/// Equal halves for the same reason: sizing each to its content would start the
/// second label at a different place on every row.
class _DetailPair extends StatelessWidget {
  const _DetailPair({
    required this.firstLabel,
    required this.firstValue,
    required this.secondLabel,
    required this.secondValue,
  });

  final String firstLabel;
  final String firstValue;
  final String secondLabel;
  final String secondValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _Stacked(label: firstLabel, value: firstValue),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _Stacked(label: secondLabel, value: secondValue),
          ),
        ],
      ),
    );
  }
}

class _Stacked extends StatelessWidget {
  const _Stacked({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

