import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../config/glass.dart';
import '../config/theme.dart';
import 'app_background.dart';

/// A screen with nothing to show yet. Distinct from an error: an empty state is
/// often a GOOD outcome (no outstanding debts, no alerts) and should read that
/// way rather than as a failure.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(AppRadius.pane),
              ),
              child: Icon(icon, size: 30, color: AppColors.brandDeep),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (action != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppRadius.pane),
              ),
              child: const Icon(
                Icons.error_outline,
                size: 30,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: 200,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(l.retry),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingStateView extends StatelessWidget {
  const LoadingStateView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// A full-page message with an icon, used by the login, pending, suspended, and
/// forbidden screens so they stay visually consistent.
class CenteredMessage extends StatelessWidget {
  const CenteredMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.footnote,
    this.actions = const <Widget>[],
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String? footnote;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // AppBackground explicitly: these four screens sit OUTSIDE AppScaffold, which
    // is what normally installs the field. Without it the transparent scaffold
    // colour would render them on bare black.
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: GlassSurface(
                blurred: true,
                lifted: true,
                padding: const EdgeInsets.all(AppSpacing.xl),
                margin: const EdgeInsets.all(AppSpacing.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Flat: a solid tinted square with a small radius, not a
                      // circle and not a gradient.
                      Center(
                        child: Container(
                          width: 76,
                          height: 76,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.pane),
                          ),
                          child: Icon(icon, size: 38, color: iconColor),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                      if (footnote != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          footnote!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (actions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        ...actions,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
