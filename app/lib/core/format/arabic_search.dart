/// بحث ذكي — matching Arabic the way a person types it, not the way it is
/// stored.
///
/// ── لماذا لا يكفي `contains` ────────────────────────────────────────────────
/// A plain substring match fails on the things Libyan users actually type, and
/// it fails SILENTLY — the row is there, the spelling is right to the eye, and
/// the screen says «لا توجد نتائج»:
///
/// - **الهمزات.** «احمد» and «أحمد» are the same name and different strings.
///   Nobody types the hamza on a phone keyboard, and the register is full of
///   both spellings because eight different people entered it.
/// - **التاء المربوطة.** «فاطمه» / «فاطمة».
/// - **الألف المقصورة.** «يحيى» / «يحيي», «مصطفى» / «مصطفي».
/// - **الأرقام العربية.** The app forces the `ar` locale, so the keyboard
///   offers ٠١٢٣٤٥٦٧٨٩ — and a man searching for «A-٠٤» would never find
///   «A-04».
/// - **التشكيل والتطويل.** A name pasted from elsewhere carries َ ً ّ or a
///   ـــ stretch that no search box user will ever reproduce.
///
/// ── ولماذا الحروف مكتوبة بأرقامها ───────────────────────────────────────────
/// ⚠ EVERY CHARACTER HERE IS A CODEPOINT, NOT A LITERAL, and that is not to
///   dodge the Arabic-literal lint. `'أ'` and `'ا'` are one pixel apart in most
///   monospace fonts and identical in some — a folding table written in glyphs
///   is a table nobody can review. `أ → ا` can be checked against
///   Unicode; a glyph can only be squinted at.
library;

/// Whitespace and the punctuation that sits inside a code or a period —
/// including U+060C, the Arabic comma.
final RegExp _separators = RegExp(r'[\s\-_/.,\u060C:]+');

/// Fold a string to the form both sides of a search are compared in.
///
/// Lowercases Latin, folds the Arabic letters people vary, drops tashkeel and
/// tatweel entirely, converts Arabic-Indic and Persian digits to ASCII, and
/// collapses runs of whitespace and separators.
String foldForSearch(String input) {
  final StringBuffer out = StringBuffer();

  for (final int c in input.toLowerCase().runes) {
    // ── تشكيل: dropped, never folded ──────────────────────────────────────
    // U+064B…U+0652 are the harakat, U+0670 is the dagger alef, U+0640 is
    // tatweel. None of them is ever typed into a search box.
    if ((c >= 0x064B && c <= 0x0652) || c == 0x0670 || c == 0x0640) continue;

    out.writeCharCode(switch (c) {
      // ألف بكل صورها → ا
      0x0622 || 0x0623 || 0x0625 || 0x0671 => 0x0627, // آ أ إ ٱ
      // تاء مربوطة → هاء
      0x0629 => 0x0647, // ة
      // ألف مقصورة → ياء
      0x0649 => 0x064A, // ى
      // همزة على واو / على ياء → و / ي
      0x0624 => 0x0648, // ؤ
      0x0626 => 0x064A, // ئ
      // كاف وياء فارسيتان، تظهران من لوحات مفاتيح بعض الأجهزة
      0x06A9 => 0x0643, // ک
      0x06CC => 0x064A, // ی
      // ٠..٩  و  ۰..۹  →  0..9
      >= 0x0660 && <= 0x0669 => c - 0x0660 + 0x30,
      >= 0x06F0 && <= 0x06F9 => c - 0x06F0 + 0x30,
      _ => c,
    });
  }

  // Separators collapse to single spaces. See [_tight] for the second form
  // this is compared against.
  //
  // ، is the ARABIC COMMA, written as an escape for the same reason the
  // folding table above is: it is indistinguishable from a Latin comma at a
  // glance, and the RTL lint is right to refuse an Arabic glyph inside a string
  // rather than trust a reader to tell the two apart.
  return out.toString().replaceAll(_separators, ' ').trim();
}

/// The same fold with the separators gone entirely.
///
/// ⚠ TWO FORMS, BECAUSE ONE CANNOT SATISFY BOTH HABITS. A code is written
///   «A-04» and searched for as «A04», as «A 04» and as «04» — three people
///   type it three ways and each is certain his is the obvious one. Matching
///   only the spaced form fails «A04»; matching only the tight form loses the
///   word boundary that keeps «محمد يناير» meaning two words.
///
///   So a token matches if it is in EITHER. The cost is a rare false
///   positive — «0420» reaches across the gap in «A-04 2026» — and that is
///   the right way to be wrong in a search box: a row too many is seen and
///   dismissed in a second, a row missing is concluded to be absent from the
///   register and entered again.
String _tight(String folded) => folded.replaceAll(' ', '');

/// Does [haystack] satisfy every word of [query]?
///
/// ⚠ AND ACROSS WORDS, NOT OR, and that is what makes it feel intelligent.
///   «محمد يناير» should find Muhammad's January row and nothing else. With OR
///   it returns every Muhammad AND every January — more results the more you
///   type, which is the opposite of what typing more is for.
///
/// An empty query matches everything: a blank search box is not a filter.
bool matchesSearch(String query, Iterable<String?> fields) {
  final String needle = foldForSearch(query);
  if (needle.isEmpty) return true;

  final String hay = foldForSearch(
    fields.where((String? f) => f != null && f.isNotEmpty).join(' '),
  );
  final String tight = _tight(hay);

  for (final String word in needle.split(' ')) {
    if (word.isEmpty) continue;
    if (hay.contains(word)) continue;
    if (tight.contains(_tight(word))) continue;
    return false;
  }
  return true;
}
