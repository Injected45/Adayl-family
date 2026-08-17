import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../directory/domain/models.dart' show AdeelListItem;
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
      body: (BuildContext context) => AsyncView<EditableSettings>(
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
        'memberFee': TextEditingController(text: widget.initial.memberFee),
        'systemStart': TextEditingController(text: widget.initial.systemStart),
        'bankName': TextEditingController(text: widget.initial.bankName),
        'bankAccountNo': TextEditingController(
          text: widget.initial.bankAccountNo,
        ),
        'bankAccountName': TextEditingController(
          text: widget.initial.bankAccountName,
        ),
      };

  bool _saving = false;

  /// The two posts, as عديل ids rather than typed names.
  ///
  /// Both officials are elected from the members, so a text box was the wrong
  /// control for them: it let the same man be entered under three spellings
  /// across a year of edits, and it let one person be recorded in both posts at
  /// once. Picking from the register removes both possibilities — and
  /// update_settings copies his name and phone out of his own row, so the
  /// association never maintains a second copy of either.
  late int? _treasurerId = widget.initial.treasurer.adeelId;
  late int? _financeId = widget.initial.financeManager.adeelId;

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
    memberFee: _text('memberFee'),
    systemStart: _text('systemStart'),
    autoClosePreviousMonths: widget.initial.autoClosePreviousMonths,
    bankName: _text('bankName'),
    bankAccountNo: _text('bankAccountNo'),
    bankAccountName: _text('bankAccountName'),
    // Only the id travels. The server reads the name and phone off the chosen
    // عديل's own row, so sending the old snapshot back would just give it a
    // chance to disagree with the register.
    treasurer: OfficialInput(
      adeelId: _treasurerId,
      name: widget.initial.treasurer.name,
      phone: widget.initial.treasurer.phone,
    ),
    financeManager: OfficialInput(
      adeelId: _financeId,
      name: widget.initial.financeManager.name,
      phone: widget.initial.financeManager.phone,
    ),
  );

  /// The two fields Postgres CASTS, checked here so it never has to answer.
  ///
  /// `update_settings` casts `memberFee` to numeric and `systemStart` to date.
  /// Anything they cannot parse comes back as 22P02 — a code that carries no
  /// wording, so the app can only say "something went wrong", and the admin is
  /// left staring at a screen where the thing he was actually changing (the two
  /// officials) failed for a reason belonging to a different field.
  ///
  /// Blank is NOT an error: [EditableSettings.toPatch] omits a blank key, so the
  /// server keeps the current value. Only a filled box that cannot be parsed is
  /// refused, and the message names the box.
  String? _rejectUncastable(L l, EditableSettings next) {
    final String fee = next.memberFee.trim();
    if (fee.isNotEmpty && double.tryParse(fee) == null) {
      return l.invalidNumberField(l.memberFeeField);
    }
    final String start = next.systemStart.trim();
    if (start.isNotEmpty && DateTime.tryParse(start) == null) {
      return l.invalidDateField(l.systemStartField);
    }
    return null;
  }

  Future<void> _save(L l) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final EditableSettings next = _collect();

    final String? refusal = _rejectUncastable(l, next);
    if (refusal != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(refusal)));
      return;
    }

    // These values are financially load-bearing, so the change is restated
    // before it is written rather than saved silently.
    final List<String> preview = <String>[
      if (next.memberFee != widget.initial.memberFee)
        '${l.memberFeeField}: ${widget.initial.memberFee} → ${next.memberFee}',
      if (next.systemStart != widget.initial.systemStart)
        '${l.systemStartField}: ${widget.initial.systemStart} → ${next.systemStart}',
      // Restated in full for the same reason the fee is: one wrong digit sends
      // every future transfer to a stranger, and it is the kind of mistake
      // nobody notices until a member says the money never arrived.
      if (next.bankAccountNo != widget.initial.bankAccountNo)
        '${l.bankAccountNoField}: ${widget.initial.bankAccountNo} → ${next.bankAccountNo}',
      if (next.bankAccountName != widget.initial.bankAccountName)
        '${l.bankAccountNameField}: ${widget.initial.bankAccountName} → ${next.bankAccountName}',
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
          label: l.memberFeeField,
          controller: _fields['memberFee']!,
          money: true,
        ),
        _Field(
          label: l.systemStartField,
          controller: _fields['systemStart']!,
          date: true,
        ),

        const SizedBox(height: AppSpacing.lg),
        _Section(title: l.bankAccountSection),
        _Field(label: l.bankNameField, controller: _fields['bankName']!),
        _Field(
          label: l.bankAccountNoField,
          controller: _fields['bankAccountNo']!,
        ),
        _Field(
          label: l.bankAccountNameField,
          controller: _fields['bankAccountName']!,
        ),

        const SizedBox(height: AppSpacing.lg),
        _Section(title: l.treasurerSection),
        _OfficialPicker(
          label: l.fullNameField,
          value: _treasurerId,
          // The other post's holder, so he cannot be offered twice. The
          // database refuses it either way (ck_settings_distinct_officials);
          // taking him off the list means the admin never gets that far.
          excludeAdeelId: _financeId,
          enabled: !_saving,
          onChanged: (int? id) => setState(() => _treasurerId = id),
        ),

        const SizedBox(height: AppSpacing.lg),
        _Section(title: l.financeManagerSection),
        _OfficialPicker(
          label: l.fullNameField,
          value: _financeId,
          excludeAdeelId: _treasurerId,
          enabled: !_saving,
          onChanged: (int? id) => setState(() => _financeId = id),
        ),

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

  /// The same set for both purges. The narrow one leaves the register standing,
  /// but an عديل row carries his own debt, so those lists are stale either way.
  void _invalidateEverything() {
    ref.invalidate(dashboardProvider);
    ref.invalidate(alertsProvider);
    ref.invalidate(auditProvider);
    ref.invalidate(reportProvider);
    ref.invalidate(directory.adeelsProvider);
    ref.invalidate(directory.adeelDetailProvider);
    ref.invalidate(directory.statementProvider);
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

/// Picks one عديل out of the register to hold a post.
///
/// Both officials are members of the association, so this is the control that
/// belonged here from the start. A text box allowed the same man under three
/// spellings and allowed one person in both posts at once; a list of real rows
/// allows neither, and `update_settings` then reads his name and phone off his
/// own record so the association never keeps a second copy of either.
///
/// [excludeAdeelId] is the other post's holder. The database refuses the
/// overlap regardless — ck_settings_distinct_officials — but removing him from
/// the list means the admin never reaches a refusal he then has to interpret.
class _OfficialPicker extends ConsumerWidget {
  const _OfficialPicker({
    required this.label,
    required this.value,
    required this.excludeAdeelId,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final int? excludeAdeelId;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<AdeelListItem>> adeels = ref.watch(
      directory.adeelsProvider(''),
    );
    final List<AdeelListItem> options = <AdeelListItem>[
      for (final AdeelListItem a
          in adeels.valueOrNull ?? const <AdeelListItem>[])
        if (a.id != excludeAdeelId) a,
    ];

    // A post whose holder is not in the list — he was excluded as the other
    // official, or the register is still loading — must not be handed to the
    // dropdown, which asserts on a value with no matching item.
    final bool valueIsOffered = options.any(
      (AdeelListItem a) => a.id == value,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DropdownButtonFormField<int?>(
        initialValue: valueIsOffered ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          helperText: options.isEmpty ? l.officialNeedsRegister : null,
          helperMaxLines: 2,
        ),
        items: <DropdownMenuItem<int?>>[
          // A post may be vacant. Without this there is no way to undo a
          // choice, and the only escape would be picking someone wrong.
          DropdownMenuItem<int?>(
            value: null,
            child: Text(
              l.notAssigned,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          for (final AdeelListItem a in options)
            DropdownMenuItem<int?>(
              value: a.id,
              child: Text(
                '${a.fullName} • ${a.adeelCode}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
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

// The Arabic-digit fold used to live here as a private class. It now sits in
// core/format/formatters.dart, because the fee was not the only box that casts
// on the server — the system-start date and an عديل's telephone need the same
// treatment, and both were written without it while a private copy sat one
// file away.

class _Field extends StatelessWidget {
  // `integer: true` went with the two whole-number fields this screen used to
  // carry — the eligibility age and the warning months. Neither exists any more,
  // so the flag had no caller left and the analyzer said so.
  const _Field({
    required this.label,
    required this.controller,
    this.money = false,
    this.date = false,
  });

  final String label;
  final TextEditingController controller;
  final bool money;

  /// A YYYY-MM-DD box. Gets the same Arabic-digit fold as [money] — the server
  /// casts this one to `date`, and ٢٠٢٦-٠١-٠١ is exactly as uncastable as an
  /// empty string. It was left as plain text when the fee was fixed, which is
  /// how 22P02 survived that fix.
  final bool date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: money
            ? const TextInputType.numberWithOptions(decimal: true)
            : date
            ? TextInputType.datetime
            : TextInputType.text,
        inputFormatters: <TextInputFormatter>[
          // Arabic-Indic digits FIRST, then the filter.
          //
          // Dart's `\d` is ASCII-only, so on an Arabic keyboard the filter below
          // silently ate every digit as it was typed: the box stayed empty, the
          // admin saved anyway, and `''::numeric` came back as 22P02 — an error
          // with no Arabic wording, so the app could only say "something went
          // wrong" and the failure never pointed at the field that caused it.
          //
          // Folding to ASCII before filtering means ٢٠ and 20 are the same
          // keystroke as far as this box is concerned. The value on the wire
          // stays ASCII, which is what Postgres can cast.
          if (money || date) ArabicDigitsFormatter(),
          if (money)
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          // Digits and the separator only. Postgres is strict about a date and
          // a stray character produces the same wordless 22P02 as an empty box.
          if (date) FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          hintText: date ? '2026-01-01' : null,
        ),
      ),
    );
  }
}
