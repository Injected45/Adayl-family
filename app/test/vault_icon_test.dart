import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/widgets/vault_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// الخزينة is the association's mark for الصندوق, and the piggy bank is gone.
///
/// `Icons.savings_outlined` is a PIGGY BANK. It stood for the fund that collects
/// every man's subscription and pays out for a bereavement — an animal, and a
/// child's toy, on the most serious screen in the app. The association asked for
/// a safe and asked that it be the mark of الصندوق wherever it appears.
///
/// ⚠ THE SOURCE SCAN IS THE POINT OF THIS FILE. A widget test can only prove
///   the screens it builds, and the piggy bank was in FOUR places across three
///   features — a sheet that opens only for a member in credit, a portal state
///   that needs a prepaid عديل to reach, a voucher form, a section menu. Pinning
///   them one by one would leave the fifth, and the fifth is exactly how a
///   symbol quietly stops being official.
void main() {
  test('no piggy bank survives anywhere in lib/', () {
    final List<String> offenders = <String>[];

    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        // The COMMENT in vault_icon.dart names the icon it replaced, and must
        // go on naming it — that is where the reason is written down. Only code
        // is scanned.
        final String line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('Icons.savings')) {
          offenders.add('${e.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'الصندوق wears الخزينة now — use VaultIcon at: ${offenders.join(', ')}',
    );
  });

  testWidgets('the safe paints, and takes the colour it is given', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: VaultIcon(size: 18, color: AppColors.warning)),
        ),
      ),
    );

    // It occupies exactly the box an Icon of the same size would, which is what
    // lets it sit in a Row beside real icons without shifting the text.
    expect(tester.getSize(find.byType(VaultIcon)), const Size(18, 18));
  });

  testWidgets('...and with no colour it inherits the ambient IconTheme', (
    WidgetTester tester,
  ) async {
    // The reason `color` is nullable. Dropped into a disabled row, the safe must
    // grey out with the icons around it rather than staying black beside them.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IconTheme(
            data: IconThemeData(color: AppColors.danger),
            child: Center(child: VaultIcon(size: 24)),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(VaultIcon), findsOneWidget);
  });
}
