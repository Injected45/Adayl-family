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
import '../../auth/domain/app_user.dart';
import '../../directory/domain/models.dart';
import '../../directory/presentation/providers.dart';
import '../domain/models.dart';
import 'bank_fields.dart';
import 'providers.dart';

/// Opens the payment form. Returns true when a payment was recorded.
Future<bool> showPaymentSheet(BuildContext context, {int? adeelId}) async {
  final bool? saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    // The barrier has to dim: a frosted pane over undimmed content has nothing
    // to separate it from, and the tap-to-dismiss area looks inert.
    barrierColor: AppColors.ink.withValues(alpha: 0.22),
    builder: (BuildContext sheetContext) =>
        GlassSheet(child: _PaymentSheet(initialAdeelId: adeelId)),
  );
  return saved ?? false;
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({this.initialAdeelId});

  final int? initialAdeelId;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  /// The PAYER's account — his bank, the name on it, its number.
  ///
  /// Free text, and deliberately not a setting: an عديل may transfer from more
  /// than one account and more than one bank, so which he used is a fact about
  /// this collection. What makes retyping cheap is [_BankFields], which offers
  /// what this same عديل used before and narrows each field by the one above it.
  final TextEditingController _bankName = TextEditingController();
  final TextEditingController _bankHolder = TextEditingController();
  final TextEditingController _bankAccountNo = TextEditingController();

  /// Who took the money — one of the two officials named in settings, not free
  /// text.
  ///
  /// It was a text field, and a text field for a name that only ever has two
  /// possible values collects spelling variants: the same treasurer arrives as
  /// three different receivers across a year of receipts, and "who collected
  /// this" stops being answerable by grouping. The names live in
  /// association_settings and are already served by v_officials, so the sheet
  /// reads them rather than asking the treasurer to retype one.
  ///
  /// Nullable because the server keeps `receiver` optional — an association that
  /// has not filled in the two names yet must still be able to collect.
  String? _receiver;

  int? _adeelId;
  String _method = PaymentMethodWire.cash;
  bool _submitting = false;
  String? _error;

  bool get _isTransfer => _method == PaymentMethodWire.bankTransfer;

  @override
  void initState() {
    super.initState();
    _adeelId = widget.initialAdeelId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    _bankName.dispose();
    _bankHolder.dispose();
    _bankAccountNo.dispose();
    super.dispose();
  }

  AdeelListItem? _selected(List<AdeelListItem> adeels) {
    for (final AdeelListItem adeel in adeels) {
      if (adeel.id == _adeelId) return adeel;
    }
    return null;
  }

  /// Mirrors the server's guard so the button can be disabled before a round
  /// trip. The server re-reads the balance under a row lock and is the only
  /// authority; this is an affordance, not a rule.
  String? _validate(L l, AdeelListItem? adeel) {
    if (adeel == null) return null;

    // ── Owing nothing is no longer a reason to refuse the money ─────────────
    // Both of the guards that used to live here are gone, and deliberately: a
    // member may hand over a year at once, or round his payment up, and the
    // surplus becomes credit against his name. `noDebtForFamily` and
    // `amountTooHigh` described a system that could not hold money it had not
    // yet earned; register_payment now can.
    //
    // What is left is what is still impossible: nothing, and negative.
    final String raw = _amount.text.trim();
    if (raw.isEmpty) return null;
    final double? value = double.tryParse(raw);
    if (value == null || value <= 0) return l.errorGeneric;
    return null;
  }

  /// The surplus, stated the moment it appears rather than on the receipt.
  ///
  /// Overpaying is allowed, which means a treasurer who means 500 and types
  /// 5000 is no longer stopped by anything. This is what stops him instead —
  /// not a refusal, a sentence saying where the extra is going, while the
  /// keyboard is still open and the correction costs one keystroke.
  String? _creditNotice(L l, AdeelListItem? adeel) {
    if (adeel == null) return null;
    final double debt = double.tryParse(adeel.debt) ?? 0;
    final double? value = double.tryParse(_amount.text.trim());
    if (value == null || value <= debt) return null;
    return l.creditNotice(formatMoney((value - debt).toStringAsFixed(2)));
  }

  Future<void> _submit(L l, AdeelListItem adeel) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final PaymentView payment = await ref
          .read(financeRepositoryProvider)
          .registerPayment(
            adeelId: adeel.id,
            amount: _amount.text.trim(),
            method: _method,
            reference: _reference.text.trim(),
            receiver: _receiver,
            notes: _notes.text.trim(),
            // Only meaningful for a transfer. The server drops them for cash
            // anyway, but sending text left over from a method the treasurer
            // switched away from would be the client asserting something untrue.
            bankName: _isTransfer ? _bankName.text.trim() : null,
            bankAccountName: _isTransfer ? _bankHolder.text.trim() : null,
            bankAccountNo: _isTransfer ? _bankAccountNo.text.trim() : null,
          );

      // Refresh everything the payment moved.
      ref.invalidate(paymentsProvider);
      ref.invalidate(cashSummaryProvider);
      ref.invalidate(cashMovementsProvider);
      ref.invalidate(adeelsProvider(''));
      ref.invalidate(adeelDetailProvider(adeel.id));
      ref.invalidate(statementProvider(adeel.id));

      if (!mounted) return;
      Navigator.of(context).pop(true);
      await _showReceipt(context, l, payment);
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
    final AsyncValue<List<AdeelListItem>> adeels = ref.watch(
      adeelsProvider(''),
    );
    final bool isTransfer = _method == PaymentMethodWire.bankTransfer;

    return AsyncView<List<AdeelListItem>>(
      value: adeels,
      builder: (List<AdeelListItem> options) {
        final AdeelListItem? adeel = _selected(options);
        final String? problem = _validate(l, adeel);
        final String? credit = _creditNotice(l, adeel);
        final double debt = double.tryParse(adeel?.debt ?? '0') ?? 0;
        final double? amount = double.tryParse(_amount.text.trim());
        // ── ما يمنع الإرسال هو ما يستحيل، لا ما هو غير معتاد ─────────────────
        // كان هنا شرطان زائدان — `debt > 0` و`amount <= debt` — وهما بقيّة من
        // نظامٍ لا يقدر أن يحتفظ بمالٍ لم يستحقّه بعد. وقد زالا من
        // register_payment ومن _validate أعلاه، وبقيا هنا؛ فكانت النتيجة أن
        // إيداعًا لمشترك لا التزام عليه ممنوعٌ بزرٍّ معطَّل لا يقول لماذا.
        //
        // وأسوأ منه أن `amount <= debt` كان يجعل _creditNotice تحتها شفرةً
        // ميتة: الرسالة لا تظهر إلا حين يتجاوز المبلغ الدَّين، وهي الحالة
        // نفسها التي كان الزر فيها معطَّلًا. فكان التطبيق يشرح فائض الرصيد
        // ويرفض تسجيله في آنٍ واحد.
        final bool canSubmit =
            !_submitting && adeel != null && amount != null && amount > 0;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: screenPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l.registerPayment,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                DropdownButtonFormField<int>(
                  // Opaque: see GlassColors.menu.
                  dropdownColor: GlassColors.menu,
                  initialValue: _adeelId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.selectFamily),
                  items: <DropdownMenuItem<int>>[
                    for (final AdeelListItem option in options)
                      DropdownMenuItem<int>(
                        value: option.id,
                        child: Text(
                          '${option.fullName} • ${option.adeelCode}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (int? value) => setState(() => _adeelId = value),
                ),
                const SizedBox(height: AppSpacing.md),

                if (adeel != null) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: debt > 0
                          ? AppColors.dangerSoft
                          : AppColors.successSoft,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          l.currentDebt,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          formatMoney(adeel.debt),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: debt > 0
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                TextField(
                  controller: _amount,
                  // الحقل مفتوح دائمًا: مشتركٌ لا التزام عليه هو بالضبط من
                  // نودع له عهدة، وتعطيل الحقل كان يمنع ذلك بلا كلمة واحدة
                  // تشرح السبب.
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    // أولًا دائمًا، وإلا فإن FilteringTextInputFormatter تحتها
                    // لا ترفض الأرقام العربية بل تبتلعها: كل ضغطة تُسقَط
                    // والصندوق يبقى فارغًا بلا رسالة. هذا الحقل كان الوحيد في
                    // التطبيق بلا هذه السطر.
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
                if (debt > 0) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _amount.text = adeel!.debt),
                      child: Text(l.payFullAmount),
                    ),
                  ),
                ],
                if (credit != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  // A NOTICE, not an error: the payment is valid and will go
                  // through. Amber rather than red for exactly that reason —
                  // red would read as "fix this", and there may be nothing to
                  // fix.
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Row(
                      children: <Widget>[
                        const VaultIcon(size: 18, color: AppColors.warning),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            credit,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
                  onSelectionChanged: _submitting
                      ? null
                      : (Set<String> value) =>
                            setState(() => _method = value.first),
                ),
                const SizedBox(height: AppSpacing.md),

                // Only meaningful for a transfer, and optional even then —
                // index.html leaves it optional and this phase does not add
                // rules the prototype did not have.
                if (isTransfer) ...<Widget>[
                  TextField(
                    controller: _reference,
                    enabled: !_submitting,
                    decoration: InputDecoration(labelText: l.reference),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Only this عديل's own transfers, and only the ones that
                  // actually carry an account. A cancelled payment still
                  // describes an account he really used, so it stays in the
                  // history: the suggestion is about typing, not money.
                  BankFields(
                    history: <BankUsage>[
                      for (final PaymentView p
                          in ref.watch(paymentsProvider).valueOrNull ??
                              const <PaymentView>[])
                        if (p.adeelId == adeel?.id &&
                            p.bankName.trim().isNotEmpty)
                          BankUsage(
                            bank: p.bankName,
                            holder: p.bankAccountName,
                            account: p.bankAccountNo,
                          ),
                    ],
                    bank: _bankName,
                    holder: _bankHolder,
                    account: _bankAccountNo,
                    enabled: !_submitting,
                  ),
                ],

                _ReceiverField(
                  value: _receiver,
                  enabled: !_submitting,
                  onChanged: (String? name) => setState(() => _receiver = name),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _notes,
                  enabled: !_submitting,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: l.notesField),
                ),

                if (_error != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.danger,
                    ),
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: canSubmit ? () => _submit(l, adeel) : null,
                  child: _submitting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onFill,
                          ),
                        )
                      : Text(l.confirmPayment),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Who received the money, chosen from the two officials named in settings.
///
/// A dropdown rather than a text field, and the reason is not tidiness: a free
/// text box for a name with two possible values collects spelling variants. The
/// same treasurer arrives as three different receivers across a year of
/// receipts, and "how much did he collect" stops being answerable by grouping —
/// on a ledger whose whole point is that the figures tie out.
///
/// The names come from `v_officials`, which reads the same
/// `association_settings` row the settings screen writes, so there is one
/// spelling of each name in the system and renaming an official in settings
/// changes what this offers immediately.
///
/// Nothing here is a rule. `receiver` is optional on the server and stays
/// optional: an association that has not filled in the two names yet must still
/// be able to record a collection, so the field degrades to a disabled dropdown
/// that says where to set them rather than blocking the payment.
class _ReceiverField extends ConsumerWidget {
  const _ReceiverField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<Official>> officials = ref.watch(officialsProvider);

    // valueOrNull, not .when: while the two names load, or if that read fails,
    // the sheet must keep working. An empty list renders the disabled state,
    // which is the same thing an association with no officials set sees.
    final List<Official> named = <Official>[
      for (final Official official
          in officials.valueOrNull ?? const <Official>[])
        if (official.name.trim().isNotEmpty) official,
    ];

    return DropdownButtonFormField<String>(
      // Opaque: see GlassColors.menu.
      dropdownColor: GlassColors.menu,
      // A name that is no longer offered — an official renamed in settings
      // while this sheet sat open — would make the dropdown assert. Fall back
      // to nothing selected instead.
      initialValue: named.any((Official official) => official.name == value)
          ? value
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: l.receiver,
        helperText: named.isEmpty ? l.receiverNotConfigured : null,
        helperMaxLines: 2,
      ),
      items: <DropdownMenuItem<String>>[
        for (final Official official in named)
          DropdownMenuItem<String>(
            value: official.name,
            child: Text(
              '${official.name} • ${_roleLabel(l, official.role)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled && named.isNotEmpty ? onChanged : null,
    );
  }

  /// `v_officials` sends the role as its wire name, the same literal `app_role`
  /// stores. The label beside the name is what the user reads, so it comes from
  /// l10n — and an unrecognised role falls through to the raw value rather than
  /// being hidden, because a role we cannot name is worth seeing.
  static String _roleLabel(L l, String wire) {
    if (wire == AppRole.treasurer.wireName) return l.roleTreasurer;
    if (wire == AppRole.financeManager.wireName) return l.roleFinanceManager;
    return wire;
  }
}

/// Shows what the SERVER actually allocated. Deliberately not predicted before
/// confirming: the FIFO rule lives on the server and duplicating it here would
/// create a second implementation that could quietly disagree.
Future<void> _showReceipt(BuildContext context, L l, PaymentView payment) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => GlassDialog(
      icon: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
      title: Text(l.paymentSaved, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LabelledValue(label: l.receiptNo, value: payment.receiptNo),
          const SizedBox(height: AppSpacing.md),
          LabelledValue(label: l.amount, value: formatMoney(payment.amount)),
          // The account the money went to, off the payment's own snapshot — so
          // this receipt keeps naming it even after the association banks
          // somewhere else. Absent for cash, which has none.
          if (payment.bankName.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            LabelledValue(label: l.bankNameField, value: payment.bankName),
          ],
          if (payment.bankAccountNo.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            LabelledValue(
              label: l.bankAccountNoField,
              value: payment.bankAccountNo,
            ),
          ],
          if (payment.bankAccountName.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            LabelledValue(
              label: l.bankAccountNameField,
              value: payment.bankAccountName,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            l.allocationPreview,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final PaymentAllocationView allocation in payment.allocations)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    formatPeriodMonth(allocation.period),
                    style: const TextStyle(
                      color: AppColors.month,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatMoney(allocation.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l.close),
        ),
      ],
    ),
  );
}
