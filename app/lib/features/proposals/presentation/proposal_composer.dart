import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'proposal_detail_screen.dart';
import 'providers.dart';

/// «إضافة مقترح» — the member's box, and beneath it what he has sent.
///
/// Two parts, as asked: the title, «لايسمح باكثر من 20 حرف», and the text.
/// Sent, it goes to the admin's «مقترحات المشتركين» under his name.
///
/// ⚠ THE 20 IS COUNTED AS POSTGRES COUNTS IT. `char_length` counts code points;
///   a TextField's `maxLength` counts what a reader sees as one letter, and the
///   two differ the moment a letter carries a mark. [CodePointLimit] is what
///   actually stops the typing, so the field can never hold a title the
///   database will refuse.
class ProposalComposer extends ConsumerStatefulWidget {
  const ProposalComposer({super.key});

  @override
  ConsumerState<ProposalComposer> createState() => _ProposalComposerState();
}

class _ProposalComposerState extends ConsumerState<ProposalComposer> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final L l = L.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // ⚠ CLEARED FIRST: a second refusal queued behind the first would appear
    //   only after it, seconds late, answering a tap he already made.
    messenger.clearSnackBars();
    if (_title.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.proposalTitleEmpty)));
      return;
    }
    if (_body.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.proposalBodyEmpty)));
      return;
    }

    setState(() => _sending = true);
    try {
      await ref
          .read(proposalsRepositoryProvider)
          .submit(title: _title.text, body: _body.text);
      if (!mounted) return;
      _title.clear();
      _body.clear();
      FocusScope.of(context).unfocus();
      ref.invalidate(proposalsProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.proposalSent)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _title,
                enabled: !_sending,
                maxLength: proposalTitleMax,
                inputFormatters: const <TextInputFormatter>[
                  CodePointLimit(proposalTitleMax),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l.proposalTitleLabel),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _body,
                enabled: !_sending,
                minLines: 5,
                maxLines: 12,
                maxLength: proposalBodyMax,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: l.proposalBodyLabel,
                  alignLabelWithHint: true,
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onFill,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(l.proposalSend),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            l.myProposalsHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        AsyncView<List<Proposal>>(
          value: ref.watch(proposalsProvider),
          onRetry: () => ref.invalidate(proposalsProvider),
          builder: (List<Proposal> mine) => mine.isEmpty
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.xs,
                  ),
                  child: Text(
                    l.myProposalsEmpty,
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final Proposal p in mine)
                      ProposalTile(
                        key: ValueKey<int>(p.id),
                        proposal: p,
                        admin: false,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Stops a field at [max] CODE POINTS — Postgres's `char_length` — and cuts a
/// paste to fit rather than refusing it whole.
class CodePointLimit extends TextInputFormatter {
  const CodePointLimit(this.max);

  final int max;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final List<int> runes = newValue.text.runes.toList();
    if (runes.length <= max) return newValue;
    final String cut = String.fromCharCodes(runes.take(max));
    return TextEditingValue(
      text: cut,
      selection: TextSelection.collapsed(offset: cut.length),
    );
  }
}
