import 'package:flutter/material.dart';

import '../config/glass.dart';
import '../config/theme.dart';

/// Asks for a single line of text. Returns the trimmed value, or null if
/// dismissed.
///
/// The controller is owned by the dialog's own [State], so it is disposed when
/// the route is gone — not when the caller's `await` returns. Disposing it in
/// the caller looks equivalent but is not: the dialog is still building its
/// `TextField` during the exit animation, and a disposed controller throws
/// "A TextEditingController was used after being disposed" mid-frame, which then
/// corrupts the rest of the frame into a cascade of unrelated-looking errors.
///
/// This existed twice as a copy-pasted local function, and carried the bug in
/// both. One shared widget means one lifecycle to get right.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String message,
  required String fieldLabel,
  required String confirmLabel,
  required String cancelLabel,
  String initialValue = '',
  String? hintText,
  TextInputType keyboardType = TextInputType.text,
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _TextPromptDialog(
      title: title,
      message: message,
      fieldLabel: fieldLabel,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      initialValue: initialValue,
      hintText: hintText,
      keyboardType: keyboardType,
      destructive: destructive,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.message,
    required this.fieldLabel,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.initialValue,
    required this.hintText,
    required this.keyboardType,
    required this.destructive,
  });

  final String title;
  final String message;
  final String fieldLabel;
  final String confirmLabel;
  final String cancelLabel;
  final String initialValue;
  final String? hintText;
  final TextInputType keyboardType;
  final bool destructive;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: Text(widget.title),
      // Scrollable: with the keyboard up on a short viewport an AlertDialog's
      // content is height-constrained, and a fixed Column would overflow.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: widget.keyboardType,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                hintText: widget.hintText,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
