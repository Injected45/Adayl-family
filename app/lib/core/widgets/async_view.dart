import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../config/theme.dart';
import '../network/api_exception.dart';
import 'state_views.dart';

/// Every failed request already carries a display-ready Arabic message from the
/// server; only transport failures, which never reached it, need a local
/// string.
String describeApiFailure(L l, Object error) {
  if (error is ApiException) {
    final String? fromServer = error.serverMessage;
    if (fromServer != null && fromServer.isNotEmpty) return fromServer;
    return switch (error.kind) {
      ApiFailureKind.network => l.errorNetworkBody,
      ApiFailureKind.timeout => l.errorTimeout,
      _ => l.errorGeneric,
    };
  }
  return l.errorGeneric;
}

/// Renders the three states every screen must have from one `AsyncValue`,
/// so no screen hand-manages loading and error booleans.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    required this.value,
    required this.builder,
    this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return value.when(
      data: builder,
      loading: () => const LoadingStateView(),
      error: (Object error, StackTrace _) => ErrorStateView(
        message: describeApiFailure(l, error),
        onRetry: onRetry,
      ),
    );
  }
}

/// A flat status chip. Was the prototype's rounded pill (index.html:34-37);
/// now a 6px-radius rectangle, which is Flat Design's geometry, with a solid
/// tinted fill and no shadow.
///
/// The fill is 10%, and that number was measured rather than chosen. The label
/// is drawn in the saturated `tone` over a tint of the SAME tone, so both sides
/// of the contrast ratio move together — increasing the tint darkens the fill and
/// the text stays put, so the ratio falls. At 14% both the success green and the
/// brand teal drop below 4.5:1. At 10% every tone in use clears it.
/// test/design_system_test.dart asserts this for all of them.
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.label, required this.tone, super.key});

  const StatusBadge.neutral({required this.label, super.key})
    : tone = AppColors.inkMuted;

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: tone,
        ),
      ),
    );
  }
}

/// Debounced so a search fires once the user pauses, not once per keystroke.
class SearchField extends StatefulWidget {
  const SearchField({
    required this.hintText,
    required this.onChanged,
    this.initialValue = '',
    super.key,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final String initialValue;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _controller.clear();
                  _debounce?.cancel();
                  widget.onChanged('');
                  setState(() {});
                },
              ),
        isDense: true,
      ),
    );
  }
}

/// A label above a value, used throughout the detail screens.
class LabelledValue extends StatelessWidget {
  const LabelledValue({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value.isEmpty ? '—' : value,
          style: const TextStyle(
            fontFamily: AppFonts.body,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}
