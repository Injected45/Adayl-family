import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/config/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../data/key_qr.dart';

/// «امسح الرمز» — كاميرا تقرأ الرمز بمجرّد التصويب، ولا تنتظر صورة.
///
/// ⚠ THIS REPLACED A PHOTOGRAPH, AND THE REPLACEMENT IS THE WHOLE POINT. The
///   first build opened the system camera through `image_picker`: the member
///   had to frame the square, press the shutter, then confirm the photo, and
///   only then did anything happen. He pressed a button that said «امسح» and
///   got an ordinary full-screen camera — «تفتح كاميرا عاديه ولا تلتقط الـQR».
///   Nobody expects to take a PICTURE of a code; they expect to point the phone
///   at it. The decoding was never the problem (it reads a square rotated 18°,
///   noisy and JPEG-crushed), the interaction was.
///
/// ⚠ **AND IT COSTS THE APP A CAMERA PERMISSION, which was the reason the first
///   version avoided it.** Any live scanner merges
///   `<uses-permission android:name="android.permission.CAMERA"/>` into the
///   manifest, and Android then requires that permission to be GRANTED before
///   `image_picker` may open the camera — so photographing a bylaw page now
///   asks once, where it used to ask never. That is the trade the association's
///   own test forced: a feature that works and asks once beats a feature that
///   asks nothing and does not work. `image_picker` requests it itself when the
///   manifest declares it, so no permission package is involved.
class KeyScannerScreen extends StatefulWidget {
  const KeyScannerScreen({super.key});

  @override
  State<KeyScannerScreen> createState() => _KeyScannerScreenState();
}

class _KeyScannerScreenState extends State<KeyScannerScreen> {
  /// ⚠ QR ONLY, and no duplicates. Narrowing the formats is what keeps a
  ///   barcode on a tin of tomatoes from being read as a key, and
  ///   `noDuplicates` is what stops the same square firing thirty times a
  ///   second while the member holds the phone still.
  final MobileScannerController _camera = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Set the instant a key is found, because `onDetect` keeps arriving while
  /// the page is popping and a second pop would take the screen beneath it.
  bool _done = false;

  @override
  void dispose() {
    unawaited(_camera.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture, L l) {
    if (_done) return;

    for (final Barcode code in capture.barcodes) {
      final String? raw = code.rawValue;
      if (raw == null) continue;

      final String? key = keyFromQrPayload(raw);
      if (key != null) {
        _done = true;
        Navigator.of(context).pop(key);
        return;
      }
    }

    // A QR that is not ours: say so and keep looking, rather than closing the
    // camera on a man who simply pointed it at the wrong thing.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l.familyCodeScanForeign)));
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final double side =
        MediaQuery.sizeOf(context).shortestSide * 0.7;

    return Scaffold(
      backgroundColor: AppColors.qrInk,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _camera,
            onDetect: (BarcodeCapture capture) => _onDetect(capture, l),
            errorBuilder: (BuildContext context, MobileScannerException error) =>
                _CameraRefused(message: l.familyCodeScanNoCamera),
          ),

          // The frame he aims with. Nothing fancy: a square of the brand colour
          // over the preview, because a preview with no target reads as «the
          // camera is just open».
          Center(
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.brandSoft, width: 3),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.xl,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                l.familyCodeScanHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.qrPaper,
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          // ⚠ IconButton, not a filled one: a filled button is full width in
          //   this theme and asserts inside a Row. SafeArea so it clears the
          //   notch on the phones the association carries.
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: Semantics(
                label: l.close,
                button: true,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: AppColors.qrPaper),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a refused camera looks like: a sentence and a way out, never a black
/// rectangle that looks like a broken app.
class _CameraRefused extends StatelessWidget {
  const _CameraRefused({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.qrPaper, fontSize: 15, height: 1.7),
      ),
    ),
  );
}
