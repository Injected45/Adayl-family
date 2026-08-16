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
    return _CentredScrollBody(
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
    return _CentredScrollBody(
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
    );
  }
}

/// Centres a short message, and scrolls it once it stops being short.
///
/// [EmptyStateView] and [ErrorStateView] were a bare `Center`, which has two
/// failure modes that only appear on a real device. A long message — a database
/// error sentence, or an empty state with a paragraph of guidance — overflows a
/// landscape phone and Flutter paints the yellow-and-black stripes over the part
/// that did not fit, with no way to reach it. And the retry button sat wherever
/// centring put it, which on a screen with a floating pill and a FAB can be
/// underneath both.
///
/// `ConstrainedBox(minHeight: viewport)` inside the scroll view is what keeps
/// the ordinary case unchanged: the child is still centred when it fits, and
/// only becomes draggable when it does not.
class _CentredScrollBody extends StatelessWidget {
  const _CentredScrollBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double inset = bottomInset(context);
        final double padded = AppSpacing.xl * 2 + inset;
        // hasBoundedHeight is false when one of these sits inside ANOTHER scroll
        // view — an empty statement rendered into a tab, for instance. Asking a
        // ConstrainedBox for an infinite minimum asserts, so in that case there
        // is no vertical centring to do and the child simply takes its own
        // height. clamp covers the other end: a viewport shorter than the
        // padding would otherwise ask for a negative minimum.
        final double minHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - padded).clamp(0.0, double.infinity)
            : 0.0;
        return SingleChildScrollView(
          // Always scrollable: without it a message that fits cannot be dragged,
          // and a message that does not fit becomes reachable only after the
          // content grows — an inconsistency the user feels before they can name.
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl + inset,
          ),
          child: ConstrainedBox(
            // Minus the padding just added, or the minimum height exceeds the
            // viewport by exactly that much and every empty state becomes
            // scrollable by a few pixels for no reason.
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: child),
          ),
        );
      },
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
