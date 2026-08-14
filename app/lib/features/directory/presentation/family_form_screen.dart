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
import '../../oversight/domain/models.dart';
import '../../oversight/presentation/providers.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Endpoints 11 and 13 — the only way to get a family into the system.
///
/// A full-screen route rather than a dialog: the father has ten fields and each
/// son has eight, which is not a dialog's worth of content on a phone.
class FamilyFormScreen extends ConsumerWidget {
  const FamilyFormScreen({this.familyId, super.key});

  /// Null when creating.
  final int? familyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (familyId == null) {
      return const _FamilyForm(existing: null);
    }
    return AsyncView<FamilyDetail>(
      value: ref.watch(familyDetailProvider(familyId!)),
      onRetry: () => ref.invalidate(familyDetailProvider(familyId!)),
      builder: (FamilyDetail detail) => _FamilyForm(existing: detail),
    );
  }
}

/// One member's editable fields.
class _MemberEditor {
  _MemberEditor({this.id, MemberView? from})
    : fullName = TextEditingController(text: from?.fullName ?? ''),
      nationalId = TextEditingController(text: from?.nationalId ?? ''),
      phone = TextEditingController(text: from?.phone ?? ''),
      subscriptionNo = TextEditingController(text: from?.subscriptionNo ?? ''),
      dob = TextEditingController(text: from?.dob ?? ''),
      workplace = TextEditingController(text: from?.workplace ?? ''),
      status = from?.membershipStatus ?? MembershipStatusWire.active;

  final int? id;
  final TextEditingController fullName;
  final TextEditingController nationalId;
  final TextEditingController phone;
  final TextEditingController subscriptionNo;
  final TextEditingController dob;
  final TextEditingController workplace;
  String status;

  void dispose() {
    fullName.dispose();
    nationalId.dispose();
    phone.dispose();
    subscriptionNo.dispose();
    dob.dispose();
    workplace.dispose();
  }

  MemberInput toInput() => MemberInput(
    id: id,
    fullName: fullName.text.trim(),
    nationalId: nationalId.text.trim(),
    phone: phone.text.trim(),
    subscriptionNo: subscriptionNo.text.trim(),
    dob: dob.text.trim(),
    workplace: workplace.text.trim(),
    status: status,
  );
}

class _FamilyForm extends ConsumerStatefulWidget {
  const _FamilyForm({required this.existing});

  final FamilyDetail? existing;

  @override
  ConsumerState<_FamilyForm> createState() => _FamilyFormState();
}

class _FamilyFormState extends ConsumerState<_FamilyForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late _MemberEditor _father;
  late List<_MemberEditor> _sons;

  /// Editors removed from the form but not yet disposed.
  ///
  /// Disposing one inside `setState` frees its controllers while the widget it
  /// belongs to is still mounted for the current frame, which throws
  /// "used after being disposed" exactly as the dialog controllers did. They are
  /// released with the screen instead.
  final List<_MemberEditor> _discarded = <_MemberEditor>[];

  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final FamilyDetail? existing = widget.existing;
    _father = _MemberEditor(id: existing?.father?.id, from: existing?.father);
    _sons = (existing?.sons ?? <MemberView>[])
        .map((MemberView son) => _MemberEditor(id: son.id, from: son))
        .toList();
  }

  @override
  void dispose() {
    _father.dispose();
    for (final _MemberEditor son in _sons) {
      son.dispose();
    }
    for (final _MemberEditor son in _discarded) {
      son.dispose();
    }
    super.dispose();
  }

  Future<void> _save(L l) async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final GoRouter router = GoRouter.of(context);
    setState(() => _saving = true);

    try {
      final MemberInput father = _father.toInput();
      final List<MemberInput> sons = _sons
          .map((_MemberEditor son) => son.toInput())
          .toList();

      final int id;
      if (widget.existing == null) {
        id = await ref
            .read(oversightRepositoryProvider)
            .createFamily(father: father, sons: sons);
      } else {
        id = widget.existing!.id;
        await ref
            .read(oversightRepositoryProvider)
            .updateFamily(familyId: id, father: father, sons: sons);
      }

      ref.invalidate(familiesProvider(''));
      ref.invalidate(familyDetailProvider(id));
      ref.invalidate(membersProvider(''));
      ref.invalidate(dashboardProvider);

      messenger.showSnackBar(SnackBar(content: Text(l.familySaved)));
      router.go('${AppRoutes.families}/$id');
    } on ApiException catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The server names the clashing national ID and the family that owns it,
      // so its message is more useful than anything generated here.
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

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool isNew = widget.existing == null;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (bool didPop, Object? _) async {
        if (didPop) return;
        // Resolved before the dialog await; the context may be gone after it.
        final GoRouter router = GoRouter.of(context);
        if (await _confirmDiscard(l)) {
          router.go(AppRoutes.families);
        }
      },
      // The field again: this screen pushes its own Scaffold rather than going
      // through AppScaffold, because it owns a PopScope for the unsaved-changes
      // guard.
      child: AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: GlassColors.chrome,
            title: Text(isNew ? l.addFamily : l.editFamily),
            actions: <Widget>[
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
                _SectionTitle(title: l.fatherData),
                _MemberFields(editor: _father, isFather: true, l: l),

                const SizedBox(height: AppSpacing.xl),
                _SectionTitle(title: l.sonsSection),
                for (final (int index, _MemberEditor son) in _sons.indexed)
                  Card(
                    margin: const EdgeInsetsDirectional.only(
                      bottom: AppSpacing.md,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                l.sonNumber(index + 1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              IconButton(
                                tooltip: l.removeSon,
                                onPressed: () => setState(() {
                                  _dirty = true;
                                  _discarded.add(_sons.removeAt(index));
                                }),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.danger,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                          _MemberFields(editor: son, isFather: false, l: l),
                        ],
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _dirty = true;
                    _sons.add(_MemberEditor());
                  }),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l.addSon),
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

class _MemberFields extends StatefulWidget {
  const _MemberFields({
    required this.editor,
    required this.isFather,
    required this.l,
  });

  final _MemberEditor editor;
  final bool isFather;
  final L l;

  @override
  State<_MemberFields> createState() => _MemberFieldsState();
}

class _MemberFieldsState extends State<_MemberFields> {
  @override
  Widget build(BuildContext context) {
    final L l = widget.l;
    final _MemberEditor editor = widget.editor;
    final String required = l.requiredField;

    return Column(
      children: <Widget>[
        _Input(
          label: l.fullNameField,
          controller: editor.fullName,
          validator: (String? value) =>
              (value == null || value.trim().isEmpty) ? required : null,
        ),
        _Input(
          label: l.nationalId,
          controller: editor.nationalId,
          validator: (String? value) =>
              (value == null || value.trim().isEmpty) ? required : null,
        ),
        _Input(label: l.phone, controller: editor.phone),
        if (widget.isFather)
          _Input(label: l.subscriptionNo, controller: editor.subscriptionNo),
        _DobInput(label: l.dateOfBirth, controller: editor.dob, l: l),
        _Input(label: l.workplace, controller: editor.workplace),
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
          child: DropdownButtonFormField<String>(
            initialValue: editor.status,
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
              if (value != null) setState(() => editor.status = value);
            },
          ),
        ),
      ],
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
  const _DobInput({
    required this.label,
    required this.controller,
    required this.l,
  });

  final String label;
  final TextEditingController controller;
  final L l;

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
            // A future birth date is refused by the server and by a database
            // trigger; bounding the picker means it cannot be entered at all.
            lastDate: now,
          );
          if (picked != null) {
            setState(() {
              widget.controller.text = picked.toIso8601String().substring(
                0,
                10,
              );
            });
          }
        },
      ),
    );
  }
}
