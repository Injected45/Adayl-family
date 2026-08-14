import 'package:flutter/material.dart';

import '../../../core/config/theme.dart';
import '../../../l10n/app_localizations.dart';

/// Shown while the stored refresh token is exchanged for a session. Brief, but
/// it must exist: without it the app would flash the login screen at every
/// cold start before restoring the session.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Scaffold(
      backgroundColor: AppColors.brandDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.diversity_3, size: 64, color: AppColors.onFill),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l.appTitle,
              style: const TextStyle(
                color: AppColors.onFill,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xl * 2),
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xB3FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
