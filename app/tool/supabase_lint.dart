// Enforces the two Supabase rules the Dart analyzer cannot express.
//
// Run: dart run tool/supabase_lint.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// RULE 1 — reads go through a v_* view or an api_* function, NEVER a base table.
//
// This closes residual risk R1 from docs/SUPABASE_MIGRATION_PLAN.md, and it is
// not a style preference.
//
// Postgres serialises `numeric` as a bare JSON number, and `dart:convert` decodes
// that to `double`. Every view casts money to text for exactly that reason. But
// `authenticated` must ALSO hold SELECT on the base tables, because
// `security_invoker` means each view reads them AS the caller — so
// `.from('receivables')` works perfectly, returns 40.00 as a double, and puts the
// association's treasury on binary floating point with nothing visibly broken.
//
// The database cannot prevent it. This can.
//
// ─────────────────────────────────────────────────────────────────────────────
// RULE 2 — no writes through PostgREST. Every mutation is an RPC.
//
// `authenticated` holds no INSERT/UPDATE/DELETE privilege on any table and no
// table carries a write policy, so a direct write would fail at runtime rather
// than corrupt anything. This catches it at build time instead, and points at the
// function that should have been called.
//
// The reason writes are RPC-only: registering one payment inserts a payment, N
// allocations, N receivable updates and a cash movement. A policy can only judge
// the row in front of it; it cannot know this INSERT is the third of five that
// must all land or none. A function body is one transaction.
import 'dart:io';

/// Base tables. Reading any of these from Dart is the money bug.
const Set<String> baseTables = <String>{
  'profiles',
  'association_settings',
  'families',
  'members',
  'receivables',
  'receivable_lines',
  'payments',
  'payment_allocations',
  'cash_movements',
  'audit_log',
};

/// Which RPC replaces a direct write, so the error says what to do instead.
const Map<String, String> writeReplacement = <String, String>{
  'families': 'save_family()',
  'members': 'save_family()',
  'receivables': 'generate_period() / auto_close_periods()',
  'receivable_lines': 'generate_period()',
  'payments': 'register_payment() / cancel_payment()',
  'payment_allocations': 'register_payment()',
  'cash_movements': 'register_payment() / cancel_payment()',
  'association_settings': 'update_settings()',
  'profiles': 'set_user_access()',
  'audit_log': 'nothing — the audit trail is written by triggers',
};

class Finding {
  Finding(this.file, this.line, this.message, this.source);
  final String file;
  final int line;
  final String message;
  final String source;
}

/// `.from('x')` — the table or view a query targets.
final RegExp fromCall = RegExp(r'''\.from\(\s*['"]([A-Za-z0-9_]+)['"]''');

/// A PostgREST mutation.
final RegExp writeCall = RegExp(r'\.(insert|upsert|update|delete)\s*\(');

void main() {
  final Directory lib = Directory('lib');
  if (!lib.existsSync()) {
    stderr.writeln('supabase_lint: run me from the app/ directory');
    exit(2);
  }

  final List<Finding> findings = <Finding>[];
  int scanned = 0;

  for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    scanned++;

    final List<String> lines = entity.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String raw = lines[i];

      // Comments explain the rule constantly; scanning them would flag the
      // explanations. The gradient check in test/design_system_test.dart learned
      // this the hard way.
      final int comment = raw.indexOf('//');
      final String code = comment == -1 ? raw : raw.substring(0, comment);
      if (code.trim().isEmpty) continue;

      for (final RegExpMatch match in fromCall.allMatches(code)) {
        final String target = match.group(1)!;
        if (!baseTables.contains(target)) continue;
        findings.add(
          Finding(
            entity.path,
            i + 1,
            "reads the BASE TABLE '$target'. Money comes back as a JSON number "
            "there, which decodes to double in Dart — use 'v_$target' or an "
            'api_* function.',
            code.trim(),
          ),
        );
      }

      // A write is only reportable when it targets a table on the same line or
      // the one before, which is how these read after formatting.
      if (writeCall.hasMatch(code)) {
        final String window = (i > 0 ? lines[i - 1] : '') + code;
        final List<RegExpMatch> targets = fromCall.allMatches(window).toList();
        // The LAST match only. A two-line window can straddle the end of an
        // unrelated query, and naming that table would point the fix at the wrong
        // place — the closest `.from(...)` is the one being written to.
        for (final RegExpMatch match
            in targets.isEmpty
                ? const <RegExpMatch>[]
                : <RegExpMatch>[targets.last]) {
          final String target = match.group(1)!;
          final String bare = target.startsWith('v_')
              ? target.substring(2)
              : target;
          if (!baseTables.contains(bare)) continue;
          findings.add(
            Finding(
              entity.path,
              i + 1,
              "writes to '$target' through PostgREST. Every mutation is an RPC — "
              'call ${writeReplacement[bare]} instead, so it happens in one '
              'transaction.',
              code.trim(),
            ),
          );
        }
      }
    }
  }

  if (findings.isEmpty) {
    stdout.writeln('supabase_lint: $scanned files scanned, no problems found.');
    return;
  }

  for (final Finding f in findings) {
    stdout.writeln('${f.file}:${f.line}: ${f.message}');
    stdout.writeln('    ${f.source}');
  }
  stdout.writeln('');
  stdout.writeln('supabase_lint: ${findings.length} problem(s).');
  exit(1);
}
