import 'package:flutter/material.dart';

import '../../../../core/config/theme.dart';

/// Android, iOS, desktop: our own button drives GoogleSignIn.authenticate().
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onFill,
              ),
            )
          : Container(
              width: 22,
              height: 22,
              // Stays literal white, and stays a circle: this is Google's mark,
              // and their branding guidelines fix both. It is the one element in
              // the app exempt from the design system.
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text(
                'G',
                style: TextStyle(
                  color: AppColors.brand,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  height: 1,
                ),
              ),
            ),
      label: Text(label),
    );
  }
}
