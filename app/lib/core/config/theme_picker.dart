import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'palette.dart';
import 'theme.dart';
import 'theme_mode_provider.dart';

/// شكلُ التطبيق: عاديّ أو ليليّ.
///
/// ⚠ ONE WIDGET, TWO HOMES. It was written private inside the عديل portal and
///   the association then asked for it in the admin app too. Copying it would
///   have been two pickers that drift — one gains an option, the other keeps
///   the old labels — for a control whose whole job is to be the same thing
///   everywhere.
///
/// ⚠ AND THE PALETTE WAS NEVER PORTAL-ONLY. AppColors and GlassColors are
///   plain statics swapped by applyAppTheme, so the mode has always covered
///   every screen in the app; only the CONTROL was in one place. Nothing about
///   the theme changed to add it here.
///
/// ⚠ A SEGMENTED CONTROL, NOT A SWITCH. «داكن / عادي» are two named states a
///   man picks between; a switch would need a label saying which way is on, and
///   «الوضع الليلي: مُطفأ» is a sentence nobody reads twice.
///
/// ⚠ AND IT WRITES BEFORE IT RETURNS, so the screen he is looking at repaints
///   under him. That is the confirmation: no snack bar, no «تم الحفظ» — the
///   change IS the feedback.
class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AppThemeMode mode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
          child: Text(
            l.themeLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ),
        SegmentedButton<AppThemeMode>(
          segments: <ButtonSegment<AppThemeMode>>[
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.light,
              icon: const Icon(Icons.light_mode_outlined, size: 18),
              label: Text(l.themeLight),
            ),
            ButtonSegment<AppThemeMode>(
              value: AppThemeMode.dark,
              icon: const Icon(Icons.dark_mode_outlined, size: 18),
              label: Text(l.themeDark),
            ),
          ],
          selected: <AppThemeMode>{mode},
          showSelectedIcon: false,
          onSelectionChanged: (Set<AppThemeMode> v) =>
              ref.read(themeModeProvider.notifier).set(v.first),
        ),
      ],
    );
  }
}
