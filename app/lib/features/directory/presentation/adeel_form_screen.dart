import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../oversight/presentation/providers.dart';
import '../domain/models.dart';
import 'providers.dart';

/// The only way to get an عديل into the register, and to amend one.
///
/// It used to be a father with ten fields plus a growable list of sons with
/// eight each — a whole household in one form, with a discard list for editors
/// removed mid-edit and an ordering rule about deleting sons before inserting
/// them. One call writes one row now, so all of that is gone and what remains is
/// a single set of fields.
class AdeelFormScreen extends ConsumerWidget {
  const AdeelFormScreen({this.adeelId, super.key});

  /// Null when creating.
  final int? adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (adeelId == null) {
      return const _AdeelForm(existing: null);
    }
    return AsyncView<AdeelDetail>(
      value: ref.watch(adeelDetailProvider(adeelId!)),
      onRetry: () => ref.invalidate(adeelDetailProvider(adeelId!)),
      builder: (AdeelDetail detail) => _AdeelForm(existing: detail.adeel),
    );
  }
}

class _AdeelForm extends ConsumerStatefulWidget {
  const _AdeelForm({required this.existing});

  final AdeelView? existing;

  @override
  ConsumerState<_AdeelForm> createState() => _AdeelFormState();
}

class _AdeelFormState extends ConsumerState<_AdeelForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  late final TextEditingController _fullName;
  late final TextEditingController _phone;
  late final TextEditingController _subscriptionNo;
  late final TextEditingController _dob;
  late final TextEditingController _workplace;
  late final TextEditingController _nationality;
  late String _status;

  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final AdeelView? existing = widget.existing;
    _fullName = TextEditingController(text: existing?.fullName ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _subscriptionNo = TextEditingController(
      text: existing?.subscriptionNo ?? '',
    );
    _dob = TextEditingController(text: existing?.dob ?? '');
    _workplace = TextEditingController(text: existing?.workplace ?? '');
    _nationality = TextEditingController(
      text: existing?.nationality.isNotEmpty ?? false
          ? existing!.nationality
          : MemberDefaults.nationality,
    );
    _status = existing?.membershipStatus ?? MemberDefaults.status;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _phone.dispose();
    _subscriptionNo.dispose();
    _dob.dispose();
    _workplace.dispose();
    _nationality.dispose();
    super.dispose();
  }

  Future<void> _save(L l) async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);
    setState(() => _saving = true);

    try {
      final int id = await ref
          .read(directoryRepositoryProvider)
          .saveAdeel(
            id: widget.existing?.id,
            fields: <String, String>{
              'fullName': _fullName.text.trim(),
              'phone': _phone.text.trim(),
              'subscriptionNo': _subscriptionNo.text.trim(),
              'dob': _dob.text.trim(),
              'workplace': _workplace.text.trim(),
              'nationality': _nationality.text.trim(),
              'status': _status,
            },
          );

      ref.invalidate(adeelsProvider(''));
      ref.invalidate(adeelDetailProvider(id));
      ref.invalidate(dashboardProvider);

      messenger.showSnackBar(SnackBar(content: Text(l.adeelSaved)));
      router.go('${AppRoutes.adeels}/$id');
    } on ApiException catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The server names what it refused, so its message is more useful
      // than anything generated here.
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiFailure(l, failure))),
      );
    }
  }

  Future<bool> _confirmDiscard(L l) async {
    if (!_dirty) return true;
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        title: Text(l.discardChangesTitle),
        content: Text(l.discardChangesBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.discard),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  /// Removing an عديل outright, offered only while editing an existing one.
  ///
  /// The server refuses the moment he has any financial history, and the dialog
  /// says so up front rather than letting the refusal arrive as a surprise —
  /// but it does NOT try to decide the question itself. Whether a receivable
  /// exists is the database's answer to give.
  Future<void> _delete(L l) async {
    final int? id = widget.existing?.id;
    if (id == null) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);

    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        title: Text(l.deleteAdeelTitle),
        content: Text(l.deleteAdeelBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (go != true) return;

    try {
      await ref.read(directoryRepositoryProvider).deleteAdeel(id);
      ref.invalidate(adeelsProvider(''));
      ref.invalidate(dashboardProvider);
      messenger.showSnackBar(SnackBar(content: Text(l.adeelDeleted)));
      router.go(AppRoutes.adeels);
    } on ApiException catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiFailure(l, failure))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool isNew = widget.existing == null;
    final String required = l.requiredField;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        // Resolved before the dialog await; the context may be gone after it.
        final GoRouter router = GoRouter.of(context);
        if (await _confirmDiscard(l)) {
          router.go(AppRoutes.adeels);
        }
      },
      // This screen pushes its own Scaffold rather than going through
      // AppScaffold, because it owns a PopScope for the unsaved-changes guard.
      child: AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: GlassColors.chrome,
            title: Text(isNew ? l.addAdeel : l.editAdeel),
            actions: <Widget>[
              if (!isNew)
                IconButton(
                  tooltip: l.deleteAdeelTitle,
                  onPressed: _saving ? null : () => _delete(l),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                  ),
                ),
              IconButton(
                onPressed: _saving ? null : () => _save(l),
                icon: const Icon(Icons.check),
              ),
            ],
          ),
          body: Form(
            key: _form,
            onChanged: () {
              if (!_dirty) setState(() => _dirty = true);
            },
            child: ListView(
              padding: screenPadding(context),
              children: <Widget>[
                _SectionTitle(title: l.personalData),
                _Input(
                  label: l.fullNameField,
                  controller: _fullName,
                  validator: (String? value) =>
                      (value == null || value.trim().isEmpty) ? required : null,
                ),
                _Input(label: l.phone, controller: _phone),
                _Input(label: l.subscriptionNo, controller: _subscriptionNo),
                _DobInput(label: l.dateOfBirth, controller: _dob),
                _Input(label: l.nationality, controller: _nationality),
                _Input(label: l.workplace, controller: _workplace),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.md,
                  ),
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: InputDecoration(
                      labelText: l.membershipStatusField,
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: MembershipStatusWire.active,
                        child: Text(l.statusActive),
                      ),
                      DropdownMenuItem<String>(
                        value: MembershipStatusWire.suspended,
                        child: Text(l.statusSuspended),
                      ),
                      DropdownMenuItem<String>(
                        value: MembershipStatusWire.deceased,
                        child: Text(l.statusDeceased),
                      ),
                    ],
                    onChanged: (String? value) {
                      if (value != null) {
                        setState(() {
                          _dirty = true;
                          _status = value;
                        });
                      }
                    },
                  ),
                ),

                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: _saving ? null : () => _save(l),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onFill,
                          ),
                        )
                      : Text(l.save),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

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

class _Input extends StatelessWidget {
  const _Input({required this.label, required this.controller, this.validator});

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: controller,
        validator: validator,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}

class _DobInput extends StatefulWidget {
  const _DobInput({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  State<_DobInput> createState() => _DobInputState();
}

class _DobInputState extends State<_DobInput> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: TextFormField(
        controller: widget.controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        onTap: () async {
          final DateTime now = DateTime.now();
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate:
                DateTime.tryParse(widget.controller.text) ??
                DateTime(now.year - 20),
            firstDate: DateTime(1900),
            // A future birth date is refused by a database trigger; bounding the
            // picker means it cannot be entered at all.
            lastDate: now,
          );
          if (picked != null) {
            setState(() {
              widget.controller.text = picked.toIso8601String().substring(0, 10);
            });
          }
        },
      ),
    );
  }
}
