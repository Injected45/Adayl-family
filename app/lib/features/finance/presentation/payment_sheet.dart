import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../directory/domain/models.dart';
import '../../directory/presentation/providers.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Opens the payment form. Returns true when a payment was recorded.
Future<bool> showPaymentSheet(BuildContext context, {int? familyId}) async {
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
        GlassSheet(child: _PaymentSheet(initialFamilyId: familyId)),
  );
  return saved ?? false;
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({this.initialFamilyId});

  final int? initialFamilyId;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reference = TextEditingController();
  final TextEditingController _receiver = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  int? _familyId;
  String _method = PaymentMethodWire.cash;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _familyId = widget.initialFamilyId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _receiver.dispose();
    _notes.dispose();
    super.dispose();
  }

  FamilyListItem? _selected(List<FamilyListItem> families) {
    for (final FamilyListItem family in families) {
      if (family.id == _familyId) return family;
    }
    return null;
  }

  /// Mirrors the server's guard so the button can be disabled before a round
  /// trip. The server re-reads the balance under a row lock and is the only
  /// authority; this is an affordance, not a rule.
  String? _validate(L l, FamilyListItem? family) {
    if (family == null) return null;
    final double debt = double.tryParse(family.debt) ?? 0;
    if (debt <= 0) return l.noDebtForFamily;

    final String raw = _amount.text.trim();
    if (raw.isEmpty) return null;
    final double? value = double.tryParse(raw);
    if (value == null || value <= 0) return l.errorGeneric;
    if (value > debt) return l.amountTooHigh(formatMoney(family.debt));
    return null;
  }

  Future<void> _submit(L l, FamilyListItem family) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final PaymentView payment = await ref
          .read(financeRepositoryProvider)
          .registerPayment(
            familyId: family.id,
            amount: _amount.text.trim(),
            method: _method,
            reference: _reference.text.trim(),
            receiver: _receiver.text.trim(),
            notes: _notes.text.trim(),
          );

      // Refresh everything the payment moved.
      ref.invalidate(paymentsProvider);
      ref.invalidate(cashSummaryProvider);
      ref.invalidate(cashMovementsProvider);
      ref.invalidate(familiesProvider(''));
      ref.invalidate(familyDetailProvider(family.id));
      ref.invalidate(statementProvider(family.id));

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
    final AsyncValue<List<FamilyListItem>> families = ref.watch(
      familiesProvider(''),
    );
    final bool isTransfer = _method == PaymentMethodWire.bankTransfer;

    return AsyncView<List<FamilyListItem>>(
      value: families,
      builder: (List<FamilyListItem> options) {
        final FamilyListItem? family = _selected(options);
        final String? problem = _validate(l, family);
        final double debt = double.tryParse(family?.debt ?? '0') ?? 0;
        final double? amount = double.tryParse(_amount.text.trim());
        final bool canSubmit =
            !_submitting &&
            family != null &&
            debt > 0 &&
            amount != null &&
            amount > 0 &&
            amount <= debt;

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
                  initialValue: _familyId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.selectFamily),
                  items: <DropdownMenuItem<int>>[
                    for (final FamilyListItem option in options)
                      DropdownMenuItem<int>(
                        value: option.id,
                        child: Text(
                          '${option.fatherName} • ${option.familyCode}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (int? value) => setState(() => _familyId = value),
                ),
                const SizedBox(height: AppSpacing.md),

                if (family != null) ...<Widget>[
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
                          formatMoney(family.debt),
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
                  enabled: !_submitting && debt > 0,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
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
                          : () => setState(() => _amount.text = family!.debt),
                      child: Text(l.payFullAmount),
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
                ],

                TextField(
                  controller: _receiver,
                  enabled: !_submitting,
                  decoration: InputDecoration(labelText: l.receiver),
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
                  onPressed: canSubmit ? () => _submit(l, family) : null,
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
                  Text(allocation.period),
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
