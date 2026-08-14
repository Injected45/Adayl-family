import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as google_web;

/// Web: `GoogleSignIn.authenticate()` is unsupported, and the flow can only be
/// started from the button Google renders itself. `onPressed` is therefore
/// unused here — the result arrives on the authentication events stream, which
/// is the same place the mobile path delivers it.
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
    if (busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Google's button renders its own label in the browser's locale.
    return Center(child: google_web.renderButton());
  }
}
