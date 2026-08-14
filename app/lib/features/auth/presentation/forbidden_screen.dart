import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';

/// Reached when a signed-in user navigates to a screen above their role —
/// usually a stale deep link, or a demotion applied while the app was open.
class ForbiddenScreen extends StatelessWidget {
  const ForbiddenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return CenteredMessage(
      icon: Icons.lock_outline,
      iconColor: AppColors.muted,
      title: l.forbiddenTitle,
      body: l.forbiddenBody,
      actions: <Widget>[
        FilledButton.icon(
          onPressed: () => context.go(AppRoutes.home),
          icon: const Icon(Icons.home_outlined, size: 18),
          label: Text(l.backToHome),
        ),
      ],
    );
  }
}
