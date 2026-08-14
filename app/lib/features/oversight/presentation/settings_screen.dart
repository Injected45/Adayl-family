import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../directory/presentation/providers.dart' as directory;
import '../../finance/presentation/providers.dart' as finance;
import '../domain/models.dart';
import 'providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<EditableSettings> settings = ref.watch(
      editableSettingsProvider,
    );

    return AppScaffold(
      title: l.navSettings,
      currentRoute: AppRoutes.settings,
      body: AsyncView<EditableSettings>(
        value: settings,
        onRetry: () => ref.invalidate(editableSettingsProvider),
        // Keyed so the form rebuilds from scratch after a save.
        builder: (EditableSettings data) => _SettingsForm(
          key: ValueKey<String>(data.toJson().toString()),
          initial: data,
        ),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.initial, super.key});

  final EditableSettings initial;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{
        'associationName': TextEditingController(
          text: widget.initial.associationName,
        ),
        'currency': TextEditingController(text: widget.initial.currency),
        'fatherFee': TextEditingController(text: widget.initial.fatherFee),
        'sonFee': TextEditingController(text: widget.initial.sonFee),
        'eligibilityAge': TextEditingController(
          text: '${widget.initial.eligibilityAge}',
        ),
        'warningMonths': TextEditingController(
          text: '${widget.initial.warningMonths}',
        ),
        'systemStart': TextEditingController(text: widget.initial.systemStart),
        'treasurerName': TextEditingController(
          text: widget.initial.treasurer.name,
        ),
        'treasurerNationalId': TextEditingController(
          text: widget.initial.treasurer.nationalId,
        ),
        'treasurerPhone': TextEditingController(
          text: widget.initial.treasurer.phone,
        ),
        'financeName': TextEditingController(
          text: widget.initial.financeManager.name,
        ),
        'financeNationalId': TextEditingController(
          text: widget.initial.financeManager.nationalId,
        ),
        'financePhone': TextEditingController(
          text: widget.initial.financeManager.phone,
        ),
      };

  bool _saving = false;

  @override
  void dispose() {
    for (final TextEditingController controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text.trim();

  EditableSettings _collect() => EditableSettings(
    associationName: _text('associationName'),
    currency: _text('currency'),
    fatherFee: _text('fatherFee'),
    sonFee: _text('sonFee'),
    eligibilityAge: int.tryParse(_text('eligibilityAge')) ?? 0,
    warningMonths: int.tryParse(_text('warningMonths')) ?? 0,
    systemStart: _text('systemStart'),
    autoClosePreviousMonths: widget.initial.autoClosePreviousMonths,
    treasurer: OfficialInput(
      name: _text('treasurerName'),
      nationalId: _text('treasurerNationalId'),
      phone: _text('treasurerPhone'),
    ),
    financeManager: OfficialInput(
      name: _text('financeName'),
      nationalId: _text('financeNationalId'),
      phone: _text('financePhone'),
    ),
  );

  Future<void> _save(L l) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final EditableSettings next = _collect();

    // These values are financially load-bearing, so the change is restated
    // before it is written rather than saved silently.
    final List<String> preview = <String>[
      if (next.fatherFee != widget.initial.fatherFee)
        '${l.fatherFeeField}: ${widget.initial.fatherFee} → ${next.fatherFee}',
      if (next.sonFee != widget.initial.sonFee)
        '${l.sonFeeField}: ${widget.initial.sonFee} → ${next.sonFee}',
      if (next.eligibilityAge != widget.initial.eligibilityAge)
        '${l.eligibilityAgeField}: ${widget.initial.eligibilityAge} → ${next.eligibilityAge}',
      if (next.warningMonths != widget.initial.warningMonths)
        '${l.warningMonthsField}: ${widget.initial.warningMonths} → ${next.warningMonths}',
      if (next.systemStart != widget.initial.systemStart)
        '${l.systemStartField}: ${widget.initial.systemStart} → ${next.systemStart}',
    ];

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        title: Text(l.confirmChangesTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l.settingsWarning,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.md),
            if (preview.isEmpty)
              Text(l.noChanges, style: const TextStyle(color: AppColors.muted))
            else
              for (final String line in preview)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 4),
                  child: Text(line, style: const TextStyle(fontSize: 13)),
                ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.save),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await ref.read(oversightRepositoryProvider).saveSettings(next);
      ref.invalidate(editableSettingsProvider);
      ref.invalidate(directory.settingsProvider);
      ref.invalidate(directory.officialsProvider);
      ref.invalidate(auditProvider(''));
      messenger.showSnackBar(SnackBar(content: Text(l.settingsSaved)));
    } on ApiException catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiFailure(l, failure))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return ListView(
      padding: screenPadding(context),
      children: <Widget>[
        Text(
          l.settingsIntro,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            l.settingsWarning,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF854D0E),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        _Section(title: l.generalSection),
        _Field(
          label: l.associationNameField,
          controller: _fields['associationName']!,
        ),
        _Field(label: l.currencyField, controller: _fields['currency']!),
        _Field(
          label: l.fatherFeeField,
          controller: _fields['fatherFee']!,
          money: true,
        ),
        _Field(
          label: l.sonFeeField,
          controller: _fields['sonFee']!,
          money: true,
        ),
        _Field(
          label: l.eligibilityAgeField,
          controller: _fields['eligibilityAge']!,
          integer: true,
        ),
        _Field(
          label: l.warningMonthsField,
          controller: _fields['warningMonths']!,
          integer: true,
        ),
        _Field(label: l.systemStartField, controller: _fields['systemStart']!),

        const SizedBox(height: AppSpacing.lg),
        _Section(title: l.treasurerSection),
        _Field(label: l.fullNameField, controller: _fields['treasurerName']!),
        _Field(
          label: l.nationalId,
          controller: _fields['treasurerNationalId']!,
        ),
        _Field(label: l.phone, controller: _fields['treasurerPhone']!),

        const SizedBox(height: AppSpacing.lg),
        _Section(title: l.financeManagerSection),
        _Field(label: l.fullNameField, controller: _fields['financeName']!),
        _Field(label: l.nationalId, controller: _fields['financeNationalId']!),
        _Field(label: l.phone, controller: _fields['financePhone']!),

        const SizedBox(height: AppSpacing.xl),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(l),
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onFill,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(l.save),
        ),

        // Admin-only, and last on the page on purpose: it is the one control
        // here that destroys rather than configures. The database repeats the
        // same role check, so hiding it is presentation only.
        if ((ref.watch(authControllerProvider).user?.role ?? AppRole.viewer)
            .atLeast(AppRole.admin)) ...<Widget>[
          const SizedBox(height: AppSpacing.xl * 2),
          const _DangerZone(),
        ],
      ],
    );
  }
}

/// Settings → منطقة الخطر. Two purges, kept deliberately separate.
///
/// The narrow one clears the figures. The wide one takes the directory with
/// them — and therefore the figures too, because every receivable and receipt
/// references a family with ON DELETE RESTRICT and a family cannot be removed
/// while its receipt survives. Each demands its OWN typed phrase, so the phrase
/// that clears the money cannot empty the directory by accident.
class _DangerZone extends ConsumerStatefulWidget {
  const _DangerZone();

  @override
  ConsumerState<_DangerZone> createState() => _DangerZoneState();
}

class _DangerZoneState extends ConsumerState<_DangerZone> {
  /// Which card is mid-flight. A key rather than a bool so only that button
  /// spins, while both are disabled — two truncates racing would serialise on
  /// the same locks anyway, and the second would report counts of zero.
  String? _running;

  Future<void> _purge(
    L l, {
    required String key,
    required String phrase,
    required String dialogTitle,
    required String dialogAction,
    required List<String> dialogBody,
    required Future<PurgeResult> Function(String confirm) call,
    required String emptyMessage,
  }) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      // Dismissing by tapping the scrim must not be readable as either answer.
      barrierDismissible: false,
      builder: (BuildContext _) => _PurgeConfirmDialog(
        phrase: phrase,
        title: dialogTitle,
        actionLabel: dialogAction,
        body: dialogBody,
      ),
    );
    if (confirmed != true) return;

    setState(() => _running = key);
    try {
      final PurgeResult result = await call(phrase);
      _invalidateEverything();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.total == 0 ? emptyMessage : l.purgeDone(result.total),
          ),
        ),
      );
    } on ApiException catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiFailure(l, failure))),
      );
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  /// The same set for both purges. The narrow one leaves the directory standing,
  /// but a family row carries its own debt, so those lists are stale either way.
  void _invalidateEverything() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(alertsProvider);
    ref.invalidate(auditProvider);
    ref.invalidate(reportProvider);
    ref.invalidate(directory.familiesProvider);
    ref.invalidate(directory.familyDetailProvider);
    ref.invalidate(directory.statementProvider);
    ref.invalidate(directory.membersProvider);
    ref.invalidate(directory.receivablesProvider);
    ref.invalidate(finance.paymentsProvider);
    ref.invalidate(finance.cashSummaryProvider);
    ref.invalidate(finance.cashMovementsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Section(title: l.dangerZoneSection),
        _DangerCard(
          title: l.purgeTitle,
          body: <String>[l.purgeIntro, l.purgeKeeps],
          warning: l.purgeIrreversible,
          buttonLabel: l.purgeButton,
          busy: _running == 'financial',
          enabled: _running == null,
          onPressed: () => _purge(
            l,
            key: 'financial',
            phrase: PurgeWire.confirmPhrase,
            dialogTitle: l.purgeConfirmTitle,
            dialogAction: l.purgeConfirmAction,
            dialogBody: <String>[l.purgeIntro],
            call: (String confirm) => ref
                .read(oversightRepositoryProvider)
                .purgeFinancialData(confirm: confirm),
            emptyMessage: l.purgeNothingToDo,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DangerCard(
          title: l.purgeAllTitle,
          body: <String>[
            l.purgeAllIntro,
            l.purgeAllWhyFinancial,
            l.purgeAllKeeps,
          ],
          warning: l.purgeIrreversible,
          buttonLabel: l.purgeAllButton,
          busy: _running == 'all',
          enabled: _running == null,
          onPressed: () => _purge(
            l,
            key: 'all',
            phrase: PurgeWire.confirmPhraseAll,
            dialogTitle: l.purgeAllConfirmTitle,
            dialogAction: l.purgeAllConfirmAction,
            dialogBody: <String>[l.purgeAllIntro, l.purgeAllWhyFinancial],
            call: (String confirm) =>
                ref.read(oversightRepositoryProvider).purgeAllData(
                  confirm: confirm,
                ),
            emptyMessage: l.purgeAllNothingToDo,
          ),
        ),
      ],
    );
  }
}

/// One destructive action, presented the same way both times: what it removes,
/// what it spares, then the irreversibility line in red directly above the
/// button that does it.
class _DangerCard extends StatelessWidget {
  const _DangerCard({
    required this.title,
    required this.body,
    required this.warning,
    required this.buttonLabel,
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final List<String> body;
  final String warning;
  final String buttonLabel;
  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.danger,
            ),
          ),
          for (final String line in body) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(line, style: const TextStyle(fontSize: 12, height: 1.6)),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            warning,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: enabled ? onPressed : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.onFill,
            ),
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onFill,
                    ),
                  )
                : const Icon(Icons.delete_forever_outlined, size: 18),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

/// Type-the-phrase confirmation.
///
/// The button stays disabled until the field matches [phrase] exactly — the same
/// string the corresponding SQL function compares against. Checking it here as
/// well is not belt-and-braces for its own sake: it makes the refusal instant
/// and legible instead of a round trip that comes back RUL13.
///
/// [phrase] is a parameter, not a constant, because the two purges must not
/// share one. An admin who means to clear the figures and is shown the wider
/// dialog types the phrase he knows, and is refused.
class _PurgeConfirmDialog extends StatefulWidget {
  const _PurgeConfirmDialog({
    required this.phrase,
    required this.title,
    required this.actionLabel,
    required this.body,
  });

  final String phrase;
  final String title;
  final String actionLabel;
  final List<String> body;

  @override
  State<_PurgeConfirmDialog> createState() => _PurgeConfirmDialogState();
}

class _PurgeConfirmDialogState extends State<_PurgeConfirmDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool matches = _typed.text.trim() == widget.phrase;

    return GlassDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final String line in widget.body) ...<Widget>[
            Text(line, style: const TextStyle(fontSize: 12, height: 1.6)),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(
            l.purgeIrreversible,
            style: const TextStyle(
              fontSize: 12,
              height: 1.6,
              fontWeight: FontWeight.w700,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l.purgeConfirmPrompt(widget.phrase),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _typed,
            autofocus: true,
            onChanged: (String _) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.purgeConfirmField,
              isDense: true,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: matches ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: AppColors.onFill,
          ),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.money = false,
    this.integer = false,
  });

  final String label;
  final TextEditingController controller;
  final bool money;
  final bool integer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: money || integer
            ? TextInputType.numberWithOptions(decimal: money)
            : TextInputType.text,
        inputFormatters: <TextInputFormatter>[
          if (money)
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          if (integer) FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
