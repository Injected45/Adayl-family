import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/data/key_qr.dart';

/// ما يراه الأدمن بعد إصدار المفتاح: الرمزُ مكتوبًا ومرسومًا.
///
/// A widget of its own rather than a column inside the dialog, so the one thing
/// that can go wrong with it can be tested: a 180-pixel square plus two
/// paragraphs inside a dialog on a 320-wide phone, in both themes.
class AccessCodeView extends StatelessWidget {
  const AccessCodeView({required this.code, super.key});

  final String code;

  /// ما يحمله المربّعُ فعلًا.
  ///
  /// ⚠ Exposed because `QrImageView` keeps its `data` private, so without this
  ///   no test could tie what is DRAWN to what the member's app accepts — and
  ///   a square drawn without the prefix is refused by every member with
  ///   «هذا ليس رمز دخول» and nothing on screen to explain why.
  String get payload => keyQrPayload(code);

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.issueCodeBody,
          style: const TextStyle(fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: AppSpacing.md),

        // The code stays, and stays FIRST. The QR saves a man from being
        // dictated eight characters down a bad line; the text is what still
        // works when the key goes out by WhatsApp, when his camera will not
        // focus, and when he is not in the room.
        SelectableText(
          code,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.qrPaper,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: QrImageView(
              data: payload,
              size: 170,
              backgroundColor: AppColors.qrPaper,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.qrInk,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.qrInk,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l.issueCodeScanHint,
          style: TextStyle(fontSize: 11, height: 1.6, color: AppColors.muted),
        ),
      ],
    );
  }
}
