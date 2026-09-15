import 'dart:typed_data';

/// صفحةٌ من قانون الجمعية — one row of `v_bylaw_pages`, WITHOUT its image.
///
/// ⚠ THE LIST CARRIES NO PIXELS. Each page's bytes are read on their own
///   (`BylawsRepository.image`), so opening the list costs a few bytes a page
///   and a reader downloads only the pages he scrolls to.
class BylawPage {
  const BylawPage({
    required this.id,
    required this.mime,
    required this.sizeBytes,
    required this.createdAt,
  });

  factory BylawPage.fromJson(Map<String, dynamic> json) => BylawPage(
    id: (json['id'] as num).toInt(),
    mime: json['mime'] as String? ?? 'image/jpeg',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    createdAt: json['createdAt'] as String? ?? '',
  );

  final int id;
  final String mime;
  final int sizeBytes;
  final String createdAt;
}

/// The largest page the database accepts — `ck_bylaw_size` and
/// `add_bylaw_page` both say 3,000,000 bytes. Checked here only so an
/// oversized photo is refused before it is uploaded, not instead of there.
const int bylawMaxBytes = 3000000;

/// What a picked file really is, read from its first bytes — never from its
/// name. `add_bylaw_page` makes the same test, so a file this calls an image
/// is one the database will take.
String? imageMimeOf(Uint8List bytes) {
  bool at(int offset, List<int> magic) {
    if (bytes.length < offset + magic.length) return false;
    for (int i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (at(0, <int>[0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (at(0, <int>[0x52, 0x49, 0x46, 0x46]) &&
      at(8, <int>[0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  return null;
}
