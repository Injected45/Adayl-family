import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import 'auth_controller.dart';

/// A first-class state, not an error.
///
/// The association is private, so a valid Google account grants nothing by
/// itself. This screen must never crash, never show an empty dashboard, and
/// never retry in a loop — it simply explains the wait and offers a way out.
///
/// It is also where a HEAD OF FAMILY lands, and where he gets in. He is not
/// waiting for an admin to approve him: he is holding a code the admin already
/// sent, and typing it here binds his account to his family and drops him
/// straight into his own portal. Both audiences see this screen because the
/// database cannot tell them apart until the code is typed — a signed-in
/// stranger and a father with a code are the same pending row.
class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final String? email = auth.pendingEmail;

    return CenteredMessage(
      icon: Icons.hourglass_top,
      iconColor: AppColors.warning,
      title: l.pendingTitle,
      body: auth.serverMessage ?? l.pendingBody,
      footnote: email == null ? null : l.pendingSignedInAs(email),
      actions: <Widget>[
        const _FamilyCodeBox(),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout, size: 18),
          label: Text(l.signOut),
        ),
      ],
    );
  }
}

/// "I have a family code."
///
/// Deliberately not validated here beyond "not empty". The code's shape is the
/// database's business — `redeem_family_code` normalises away dashes, spaces and
/// case, then either finds the row or raises RUL14 with an Arabic sentence the
/// error mapper shows verbatim. Re-implementing the alphabet in Dart would give
/// the man two different verdicts on the same string.
class _FamilyCodeBox extends ConsumerStatefulWidget {
  const _FamilyCodeBox();

  @override
  ConsumerState<_FamilyCodeBox> createState() => _FamilyCodeBoxState();
}

class _FamilyCodeBoxState extends ConsumerState<_FamilyCodeBox> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem(L l) async {
    final String typed = _code.text.trim();
    if (typed.isEmpty || _busy) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).redeemFamilyCode(typed);
      // The profile changed underneath the router: pending with no family has
      // become approved with one. Nothing else would notice, so the stage is
      // re-derived explicitly and the guard moves him to his portal.
      await ref.read(authControllerProvider.notifier).refreshProfile();
    } on ApiException catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeApiFailure(l, failure))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return GlassPanel(
      title: l.familyCodeTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.familyCodeBody,
            style: const TextStyle(fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _code,
            textInputAction: TextInputAction.done,
            // The alphabet has no lower-case letters and the code is read off a
            // phone screen, so the keyboard should not be guessing at words.
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (String _) => _redeem(l),
            onChanged: (String _) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.familyCodeField,
              hintText: l.familyCodeHint,
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _busy || _code.text.trim().isEmpty
                ? null
                : () => _redeem(l),
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onFill,
                    ),
                  )
                : const Icon(Icons.login, size: 18),
            label: Text(l.familyCodeAction),
          ),
        ],
      ),
    );
  }
}
