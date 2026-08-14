import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/supabase/supabase_config.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/text_prompt_dialog.dart';
import '../../../l10n/app_localizations.dart';
import 'auth_controller.dart';
import 'failure_text.dart';
import 'widgets/google_sign_in_button.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AuthState auth = ref.watch(authControllerProvider);

    // AppBackground explicitly: this screen sits OUTSIDE AppScaffold, which is
    // what installs the field everywhere else. Since the theme sets
    // scaffoldBackgroundColor to transparent, without this the sign-in screen
    // would render on bare canvas.
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: screenPadding(context),
              // The one hero pane in the app. A sign-in screen is the whole
              // viewport with one card in it, so this is where a frosted surface
              // over the field does the most work and costs the least — a single
              // BackdropFilter on a screen with nothing else on it.
              child: GlassSurface(
                blurred: true,
                lifted: true,
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.brand,
                            borderRadius: BorderRadius.circular(AppRadius.pane),
                          ),
                          child: const Icon(
                            Icons.diversity_3,
                            size: 36,
                            color: AppColors.onFill,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        l.appTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l.appTagline,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xl * 1.5),
                      Text(
                        l.loginTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        l.loginSubtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      if (!SupabaseConfig.isConfigured) ...<Widget>[
                        // Deliberately ahead of the auth error: with no URL and no
                        // key, every sign-in attempt fails for this reason and the
                        // resulting network error would explain nothing. Not
                        // localised on purpose — the audience is whoever built the
                        // binary, not the association's treasurer.
                        _Notice(
                          message: SupabaseConfig.misconfigurationHint,
                          tone: AppColors.danger,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      if (auth.hasError) ...<Widget>[
                        _Notice(
                          message: describeAuthFailure(l, auth),
                          tone: auth.errorCode == LocalAuthError.cancelled
                              ? AppColors.warning
                              : AppColors.danger,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // Rendered even when unconfigured, so the reason is visible
                      // in the notice above rather than presenting a dead button
                      // with no explanation.
                      GoogleSignInButton(
                        label: auth.stage == AuthStage.signingIn
                            ? l.signingIn
                            : l.signInWithGoogle,
                        busy: auth.stage == AuthStage.signingIn,
                        onPressed: () =>
                            ref.read(authControllerProvider.notifier).signIn(),
                      ),

                      // Drawn only with --dart-define=DEV_LOGIN=true, and useless
                      // unless the server has DEV_LOGIN_ENABLED=true as well. Kept
                      // visually separate and explicitly labelled so it can never be
                      // mistaken for the real thing.
                      if (SupabaseConfig.devLoginEnabled) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        const Divider(),
                        const SizedBox(height: AppSpacing.lg),
                        _Notice(
                          message: l.devSignInWarning,
                          tone: AppColors.warning,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton.icon(
                          onPressed: auth.isBusy
                              ? null
                              : () => _showDevSignIn(context, ref, l),
                          icon: const Icon(
                            Icons.construction_outlined,
                            size: 18,
                          ),
                          label: Text(l.devSignIn),
                        ),
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

Future<void> _showDevSignIn(BuildContext context, WidgetRef ref, L l) async {
  final String? chosen = await showTextPrompt(
    context,
    title: l.devSignIn,
    message: l.devSignInWarning,
    fieldLabel: l.devSignInEmail,
    confirmLabel: l.devSignInConfirm,
    cancelLabel: l.cancel,
    initialValue: SupabaseConfig.devLoginEmail,
    keyboardType: TextInputType.emailAddress,
  );

  if (chosen == null || chosen.isEmpty) return;
  await ref.read(authControllerProvider.notifier).devSignIn(chosen);
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.tone});

  final String message;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: tone, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
