import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/vault_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../directory/domain/models.dart' show AdeelListItem;
import '../../directory/presentation/providers.dart' as directory;
import '../domain/models.dart';
import 'bank_fields.dart';
import 'providers.dart';

/// The voucher: money leaving the treasury.
///
/// Deliberately the same shape as the payment sheet — a bottom sheet, the same
/// amount field, the same نقداً/تحويل control, the same bank block — because a
/// treasurer who can take money in should not have to learn a second interface
/// to pay it out. What differs is what the association decided differs:
///
///   • a CATEGORY, from a fixed list, because "how much went on each heading"
///     is the only question a spend record exists to answer;
///   • a payee who may be an عديل from the register OR a free name, because the
///     association pays landlords and hospitals as well as its own members;
///   • ADMIN only, which the server enforces and this sheet does not duplicate
///     beyond not offering the button.
void showDisbursementSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.ink.withValues(alpha: 0.22),
    builder: (BuildContext sheetContext) => const _DisbursementSheet(),
  );
}

class _DisbursementSheet extends ConsumerStatefulWidget {
  const _DisbursementSheet();

  @override
  ConsumerState<_DisbursementSheet> createState() => _DisbursementSheetState();
}

class _DisbursementSheetState extends ConsumerState<_DisbursementSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _payee = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _handedBy = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final TextEditingController _bankName = TextEditingController();
  final TextEditingController _bankAccountNo = TextEditingController();
  final TextEditingController _bankAccountName = TextEditingController();

  /// The choice everything else on this form follows from. لمشترك asks WHO;
  /// جماعي asks WHAT FOR. They are never both asked, because a voucher is
  /// never both — `ck_disb_shape` refuses the row that tries.
  String _kind = DisbursementKindWire.member;
  String _method = PaymentMethodWire.cash;

  /// Only for جماعي. Starts null so the admin must choose: defaulting to فرح
  /// would file an unreviewed voucher under a real occasion.
  String? _category;

  /// Only for لمشترك. The server takes the NAME off that man's own row, so a
  /// voucher cannot name one person while pointing at another.
  int? _payeeAdeelId;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _amount,
      _payee,
      _reference,
      _handedBy,
      _note,
      _bankName,
      _bankAccountNo,
      _bankAccountName,
    ]) {
      c.dispose();
    }
    super.dispose();
  }


  /// Mirrors the server's guards so the button can be dead before a round trip.
  /// The server re-reads the treasury under a lock and is the only authority;
  /// this is an affordance, not a rule.
  String? _validate(L l, String available) {
    final double? value = double.tryParse(_amount.text.trim());
    if (_amount.text.trim().isEmpty) return null;
    if (value == null || value <= 0) return l.errorGeneric;

    // ── The rule that makes this screen safe ────────────────────────────────
    // A treasury that can go negative is one where the figure on the screen has
    // stopped describing anything, and the association would find out from a
    // bounced transfer rather than from the app.
    final double have = double.tryParse(available) ?? 0;
    if (value > have) return l.overTreasuryBalance(formatMoney(available));

    // The member comes first because it is the question the kind adds; the وجه
    // is asked of both and is reported last.
    if (_kind == DisbursementKindWire.member && _payeeAdeelId == null) {
      return l.payeeRequired;
    }
    if (_category == null) return l.categoryRequired;
    return null;
  }

  Future<void> _submit(L l) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> result = await ref
          .read(financeRepositoryProvider)
          .registerDisbursement(
            amount: _amount.text.trim(),
            // Each kind sends its own half and nulls the other. Sending both is
            // refused twice over — by RUL17 and by ck_disb_shape — so this is
            // convenience, never the guarantee.
            kind: _kind,
            category: _category,
            payeeAdeelId: _kind == DisbursementKindWire.member
                ? _payeeAdeelId
                : null,
            method: _method,
            reference: _method == PaymentMethodWire.bankTransfer
                ? _reference.text.trim()
                : null,
            bankName: _method == PaymentMethodWire.bankTransfer
                ? _bankName.text.trim()
                : null,
            bankAccountNo: _method == PaymentMethodWire.bankTransfer
                ? _bankAccountNo.text.trim()
                : null,
            bankAccountName: _method == PaymentMethodWire.bankTransfer
                ? _bankAccountName.text.trim()
                : null,
            handedBy: _handedBy.text.trim(),
            note: _note.text.trim(),
          );

      // Everything the voucher moved. The treasury summary and the member
      // portal's transparency figures both read the balance this changed.
      ref
        ..invalidate(disbursementsProvider)
        ..invalidate(expenseByCategoryProvider)
        ..invalidate(cashSummaryProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l.disbursementSaved(
                '${result['voucherNo']}',
                formatMoney('${result['balanceAfter']}'),
              ),
            ),
          ),
        );
    } on ApiException catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = describeApiFailure(l, failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AsyncValue<CashSummaryView> summary = ref.watch(cashSummaryProvider);
    final AsyncValue<List<AdeelListItem>> adeels = ref.watch(
      directory.adeelsProvider(''),
    );

    return GlassSheet(
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: AsyncView<CashSummaryView>(
            value: summary,
            onRetry: () => ref.invalidate(cashSummaryProvider),
            builder: (CashSummaryView cash) {
              final String? problem = _validate(l, cash.balance);
              final bool canSubmit =
                  !_submitting &&
                  problem == null &&
                  _amount.text.trim().isNotEmpty;

              return ListView(
                shrinkWrap: true,
                padding: screenPadding(context),
                children: <Widget>[
                  Text(
                    l.registerDisbursement,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // What the association actually holds, stated before the
                  // amount is typed rather than after it is refused.
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.neutralSoft,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Row(
                      children: <Widget>[
                        const VaultIcon(size: 18, color: AppColors.muted),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(l.associationBalance)),
                        Text(
                          formatMoney(cash.balance),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      ArabicDigitsFormatter(),
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: l.amount,
                      errorText: problem,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── THE CHOICE EVERYTHING ELSE FOLLOWS FROM ─────────────────
                  // Money to a NAMED man, or money on an OCCASION for everybody.
                  // Explicit rather than clever: a combined field that guessed
                  // from what was typed would sometimes attach a voucher to a
                  // man nobody meant, and the association reads these two apart
                  // in every report it asks for.
                  SegmentedButton<String>(
                    segments: <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: DisbursementKindWire.member,
                        label: Text(l.kindMember),
                        icon: const Icon(Icons.person_outline, size: 18),
                      ),
                      ButtonSegment<String>(
                        value: DisbursementKindWire.collective,
                        label: Text(l.kindCollective),
                        icon: const Icon(Icons.groups_outlined, size: 18),
                      ),
                    ],
                    selected: <String>{_kind},
                    showSelectedIcon: false,
                    // Switching CLEARS the other half. Left behind, it would be
                    // sent, refused by RUL17, and read as the form being broken
                    // rather than as a leftover.
                    onSelectionChanged: (Set<String> v) => setState(() {
                      _kind = v.first;
                      _payeeAdeelId = null;
                      _category = null;
                    }),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // WHO — only for لمشترك, and above the وجه because the man is
                  // what the admin came here knowing.
                  if (_kind == DisbursementKindWire.member) ...<Widget>[
                    adeels.when(
                      loading: () =>
                          const LinearProgressIndicator(minHeight: 2),
                      error: (Object e, StackTrace _) =>
                          Text(describeApiFailure(l, e)),
                      data: (List<AdeelListItem> options) =>
                          DropdownButtonFormField<int>(
                            initialValue: _payeeAdeelId,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: l.payee),
                            items: <DropdownMenuItem<int>>[
                              for (final AdeelListItem a in options)
                                DropdownMenuItem<int>(
                                  value: a.id,
                                  child: Text(
                                    '${a.fullName} • ${a.adeelCode}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (int? v) =>
                                setState(() => _payeeAdeelId = v),
                          ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // WHAT FOR — for BOTH kinds. A man may be given something for
                  // a wedding one month and a bereavement the next, and a list
                  // of names cannot tell those apart.
                  //
                  // The options are filtered by kind: مولود is never collective
                  // and فطور رمضان is never one man's. ck_disb_shape refuses the
                  // pairing outright, so this only keeps the picker from
                  // offering what the server would reject.
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.expenseCategory),
                    items: <DropdownMenuItem<String>>[
                      for (final String c in ExpenseCategoryWire.forKind(_kind))
                        DropdownMenuItem<String>(value: c, child: Text(c)),
                    ],
                    onChanged: (String? v) => setState(() => _category = v),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  SegmentedButton<String>(
                    segments: <ButtonSegment<String>>[
                      ButtonSegment<String>(
                        value: PaymentMethodWire.cash,
                        label: Text(l.methodCash),
                        icon: const Icon(Icons.payments_outlined, size: 18),
                      ),
                      ButtonSegment<String>(
                        value: PaymentMethodWire.bankTransfer,
                        label: Text(l.methodTransfer),
                        icon: const Icon(
                          Icons.account_balance_outlined,
                          size: 18,
                        ),
                      ),
                    ],
                    selected: <String>{_method},
                    showSelectedIcon: false,
                    onSelectionChanged: (Set<String> v) =>
                        setState(() => _method = v.first),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (_method == PaymentMethodWire.bankTransfer) ...<Widget>[
                    // Where the money was SENT. Recorded on the voucher rather
                    // than joined to settings, for the same reason a receipt
                    // snapshots the receiving account: this is history.
                    //
                    // The SAME remembering the collection side has, and the same
                    // widget — extracted rather than copied, because two
                    // implementations of one cascade drift and the second one to
                    // drift is the one nobody is looking at.
                    //
                    // ── Scoped by whatever the kind gives us to scope BY ─────
                    // لمشترك has a man, so it is his own accounts and nobody
                    // else's — offering another member's would invite paying
                    // one into the other's account.
                    //
                    // جماعي has no payee at all, by the association's own
                    // decision, so there is nothing to narrow by and the honest
                    // scope is every collective voucher: the association sends
                    // to the same caterer and the same hall each year, and that
                    // history is exactly what the field exists to save. Mixing
                    // the two pools is what must not happen.
                    BankFields(
                      history: <BankUsage>[
                        for (final DisbursementView d
                            in ref.watch(disbursementsProvider).valueOrNull ??
                                const <DisbursementView>[])
                          if (d.bankName.trim().isNotEmpty &&
                              (_kind == DisbursementKindWire.member
                                  ? _payeeAdeelId != null &&
                                        d.payeeAdeelId == _payeeAdeelId
                                  : !d.isForMember))
                            BankUsage(
                              bank: d.bankName,
                              holder: d.bankAccountName,
                              account: d.bankAccountNo,
                            ),
                      ],
                      bank: _bankName,
                      holder: _bankAccountName,
                      account: _bankAccountNo,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // INSIDE the transfer block. It is «رقم مرجع التحويل» — a
                    // number the BANK issues — so on a cash payout there is
                    // nothing it could hold. Left outside, it invited an admin
                    // to write something beside نقداً that the voucher would
                    // then print as a transfer reference.
                    TextField(
                      controller: _reference,
                      decoration: InputDecoration(labelText: l.reference),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  TextField(
                    controller: _handedBy,
                    decoration: InputDecoration(labelText: l.handedBy),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // ── The note is what makes a line READABLE years later ─────
                  // The heading says «مولود»; the note says whose birth. On the
                  // member's own statement that is the difference between "100
                  // for a birth" and "100 when حور was born" — and he is the one
                  // person who can tell whether the record is right.
                  //
                  // A hint rather than a required field: an admin recording an
                  // urgent payment at speed must not be blocked by a box, and
                  // the heading alone is still a true record. The hint is there
                  // so he knows what belongs in it when he does have a moment.
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: l.notesField,
                      hintText: l.disbursementNoteHint,
                      helperText: l.disbursementNoteHelp,
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── التاريخ ─────────────────────────────────────────
                  // ⚠ THERE IS NO PICKER HERE ANY MORE, and its absence is
                  //   the guarantee. It defaulted to the HANDSET clock and
                  //   then let that be edited — which is how a voucher came
                  //   to be dated tomorrow. The database now stamps spent_at
                  //   with its own now() in a BEFORE INSERT trigger, so no
                  //   value is left for this screen to propose or get wrong.
                  //
                  //   And a read-only line showing «today» would be worse
                  //   than nothing: it could only come from the device clock,
                  //   so on a tampered phone it would display a date the row
                  //   will not carry. One sentence, and no figure to doubt.
                  Row(
                    children: <Widget>[
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          l.disbursementDateAuto,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_error != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),

                  FilledButton.icon(
                    onPressed: canSubmit ? () => _submit(l) : null,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.north_east),
                    label: Text(l.confirmDisbursement),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
