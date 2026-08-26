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
            Icon(Icons.diversity_3, size: 64, color: AppColors.onFill),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l.appTitle,
              style: TextStyle(
                color: AppColors.onFill,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xl * 2),
            SizedBox.square(
              dimension: 24,
              // ⚠ brand, NOT white@70%. The splash sits on the aurora
              //   field, which is PALE in the light palette — a white spinner
              //   on it was already faint and in الوضع الليلي it is the only
              //   bright thing on the screen. The brand colour inverts with
              //   the palette and reads on both.
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
