import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Where a page of the bylaws comes from: the camera, or the phone's files.
///
/// ⚠ SHRUNK ON THE PHONE, BEFORE IT IS SENT. A photo straight off a handset is
///   four to twelve megabytes; the database takes three at most, and a page of
///   text reads perfectly at 2000 pixels on its long side. `image_picker` does
///   the resize and re-encode natively, so no image package ships in the APK.
///
/// A class behind a provider, not calls in the screen, for one reason: the
/// camera needs a platform channel no test binding has, and the screen's
/// behaviour — what is uploaded, what is refused, what it says — is what the
/// tests must reach.
class PagePicker {
  const PagePicker();

  static const double maxSide = 2000;
  static const int quality = 80;

  /// One photo from the camera, or nothing if he backed out.
  Future<List<Uint8List>> camera() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: quality,
    );
    return file == null
        ? const <Uint8List>[]
        : <Uint8List>[await file.readAsBytes()];
  }

  /// Any number of images from the phone, in the order he chose them.
  Future<List<Uint8List>> device() async {
    final List<XFile> files = await ImagePicker().pickMultiImage(
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: quality,
    );
    return <Uint8List>[for (final XFile f in files) await f.readAsBytes()];
  }
}
