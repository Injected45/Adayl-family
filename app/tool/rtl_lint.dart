// Enforces the two rules that keep an Arabic-first app correct and that the
// Dart analyzer cannot express:
//
//   1. No physical left/right layout. In an RTL app `EdgeInsets.only(left:)`
//      pins padding to the physical left regardless of text direction, so a
//      layout that looks right in English is visibly wrong in Arabic. The
//      directional variants flip automatically.
//
//   2. No Arabic string literals in widget code. Every visible string must come
//      from the ARB files, or half the interface becomes untranslatable and the
//      wording drifts between screens.
//
// Run: dart run tool/rtl_lint.dart
import 'dart:io';

class Rule {
  const Rule(this.pattern, this.message);
  final RegExp pattern;
  final String message;
}

final List<Rule> rules = <Rule>[
  Rule(
    RegExp(r'EdgeInsets\.only\s*\([^)]*\b(left|right)\s*:'),
    'EdgeInsets.only(left/right:) does not flip in RTL — use EdgeInsetsDirectional.only(start/end:)',
  ),
  Rule(
    RegExp(r'EdgeInsets\.fromLTRB\s*\('),
    'EdgeInsets.fromLTRB is physical — use EdgeInsetsDirectional.fromSTEB',
  ),
  Rule(
    RegExp(
      r'EdgeInsets\.symmetric\s*\([^)]*\bhorizontal\s*:[^)]*\)\s*\.\s*(left|right)',
    ),
    'physical horizontal inset — use the directional variant',
  ),
  Rule(
    RegExp(
      r'\bAlignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)\b',
    ),
    'physical Alignment does not flip in RTL — use AlignmentDirectional',
  ),
  Rule(
    RegExp(r'\bTextAlign\.(left|right)\b'),
    'TextAlign.left/right does not follow text direction — use TextAlign.start/end',
  ),
  Rule(
    RegExp(r'Positioned\s*\([^)]*\b(left|right)\s*:'),
    'Positioned(left/right:) is physical — use Positioned.directional(start/end:)',
  ),
  Rule(
    RegExp(
      r'BorderRadius\.only\s*\([^)]*\b(topLeft|topRight|bottomLeft|bottomRight)\s*:',
    ),
    'physical BorderRadius corners — use BorderRadiusDirectional',
  ),
];

final RegExp arabicLiteral = RegExp(r'''['"][^'"]*[؀-ۿ][^'"]*['"]''');

/// lib/l10n holds the ARB-derived translations, which are supposed to be Arabic.
///
/// Matched WITHOUT a leading slash: paths here are relative ("lib\l10n\..."),
/// so requiring one silently exempted nothing and flagged every generated
/// translation.
bool isExempt(String path) {
  final String normalised = path.replaceAll(r'\', '/');
  return normalised.contains('lib/l10n/') ||
      // The one file permitted to hold Arabic wire values — the enum strings
      // the database stores. See its header for why they are contained there.
      normalised.endsWith('lib/core/domain/wire_values.dart');
}

void main() {
  final Directory lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('Run this from the Flutter project root (app/).');
    exit(2);
  }

  final List<String> problems = <String>[];
  int scanned = 0;

  for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (isExempt(entity.path)) continue;
    scanned++;

    final List<String> lines = entity.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      final String code = line.trim();
      if (code.startsWith('//')) continue;

      for (final Rule rule in rules) {
        if (rule.pattern.hasMatch(line)) {
          problems.add('${entity.path}:${i + 1}  ${rule.message}\n    $code');
        }
      }

      if (arabicLiteral.hasMatch(line)) {
        problems.add(
          '${entity.path}:${i + 1}  Arabic string literal in widget code — '
          'move it to lib/l10n/app_ar.arb\n    $code',
        );
      }
    }
  }

  if (problems.isEmpty) {
    stdout.writeln('rtl_lint: $scanned files scanned, no problems found.');
    return;
  }

  stdout.writeln(
    'rtl_lint: ${problems.length} problem(s) in $scanned files:\n',
  );
  for (final String problem in problems) {
    stdout.writeln('  $problem\n');
  }
  exit(1);
}
