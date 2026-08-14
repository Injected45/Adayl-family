import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import 'auth_controller.dart';

class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AuthState auth = ref.watch(authControllerProvider);

    return CenteredMessage(
      icon: Icons.block,
      iconColor: AppColors.danger,
      title: l.suspendedTitle,
      body: auth.serverMessage ?? l.suspendedBody,
      actions: <Widget>[
        OutlinedButton.icon(
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout, size: 18),
          label: Text(l.signOut),
        ),
      ],
    );
  }
}
