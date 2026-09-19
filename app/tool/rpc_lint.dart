// tool/rpc_lint.dart — every `.rpc()` the app makes, checked against the SQL
// that defines it. Run from `app/`:  dart run tool/rpc_lint.dart
//
// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
// PostgREST resolves a function call by its NAME **and the set of named
// parameters it was given**. Send `p_adeel_ids` to a function whose argument is
// `p_ids` and PostgREST does not call it with a missing argument — it answers
// PGRST202, «function not found», exactly as if the patch had never been run.
//
// Nothing else in this repository can catch that:
//   • `flutter analyze` sees a Map<String, dynamic> of string keys.
//   • every widget/unit test fakes the repository, so no test has ever sent a
//     real parameter name anywhere.
//   • `supabase_lint` asks WHERE a write goes (an RPC, not PostgREST), never
//     whether the RPC it names can receive it.
//   • the SQL suites call the functions from psql, in SQL, where argument
//     names are optional and a mismatch is impossible.
//
// So the one layer that would notice is a handset — which is how a WHERE-less
// DELETE reached the association on 16/09. This closes the same class for
// argument names, offline and in the build gate.
//
// ⚠ IT IS A NAME CHECK, NOT A TYPE CHECK. Postgres resolves overloads by type
//   too; this tool only proves the call can REACH a function. Types are still
//   on whoever writes the patch.
import 'dart:io';

void main() {
  final Map<String, List<_Signature>> sql = _readSqlFunctions();
  final List<_Call> calls = _readDartCalls();

  final List<String> problems = <String>[];

  for (final _Call call in calls) {
    final List<_Signature>? candidates = sql[call.function];
    if (candidates == null || candidates.isEmpty) {
      problems.add(
        '${call.where}  calls ${call.function}(), which no supabase/*.sql file '
        'creates — PostgREST answers PGRST202',
      );
      continue;
    }

    final bool ok = candidates.any(
      (_Signature s) => s.accepts(call.params, call.always),
    );
    if (!ok) {
      final String sent = call.params.isEmpty
          ? '(no parameters)'
          : call.params.join(', ');
      final String offered = candidates
          .map(
            (_Signature s) => s.args.isEmpty ? '()' : '(${s.names.join(', ')})',
          )
          .join('  |  ');
      problems.add(
        '${call.where}  calls ${call.function} with $sent\n'
        '      but the database declares $offered\n'
        '      → PostgREST cannot resolve it (PGRST202)',
      );
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln(
      'rpc_lint: ${problems.length} call(s) cannot reach their '
      'function:\n',
    );
    for (final String p in problems) {
      stderr.writeln('  $p\n');
    }
    exit(1);
  }

  stdout.writeln(
    'rpc_lint: ${calls.length} RPC call sites checked against '
    '${sql.length} functions, no problems found.',
  );
}

/// One `CREATE FUNCTION` signature, as the database will see it.
class _Signature {
  _Signature(this.name, this.args);

  final String name;
  final List<_Arg> args;

  List<String> get names => args.map((_Arg a) => a.name).toList();

  /// PostgREST hands over exactly the keys the client sent. The call reaches
  /// this function when every key it MIGHT send is an argument here, and every
  /// argument WITHOUT a default is one it ALWAYS sends.
  bool accepts(List<String> sent, List<String> always) {
    for (final String key in sent) {
      if (!args.any((_Arg a) => a.name == key)) return false;
    }
    for (final _Arg a in args) {
      if (!a.hasDefault && !always.contains(a.name)) return false;
    }
    return true;
  }
}

class _Arg {
  _Arg(this.name, {required this.hasDefault});
  final String name;
  final bool hasDefault;
}

class _Call {
  _Call(this.where, this.function, this.params, this.always);
  final String where;
  final String function;

  /// Every key this call can send.
  final List<String> params;

  /// The keys it sends UNCONDITIONALLY. A key written `if (x != null) 'p_to':`
  /// is absent whenever x is null, so it cannot satisfy an argument that has no
  /// DEFAULT — a distinction that only shows up at run time on a handset.
  final List<String> always;
}

/// Every function the schema and the patches define, in application order, with
/// `DROP FUNCTION` honoured — a signature that was dropped is not reachable
/// however many older files still create it.
Map<String, List<_Signature>> _readSqlFunctions() {
  final Directory supabase = Directory('../supabase');
  if (!supabase.existsSync()) {
    stderr.writeln('rpc_lint: run me from app/ — ../supabase is not there.');
    exit(2);
  }

  final List<File> migrations =
      Directory('../supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((File f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  final List<File> patches =
      supabase
          .listSync()
          .whereType<File>()
          .where(
            (File f) =>
                f.uri.pathSegments.last.startsWith('PATCH_') &&
                f.path.endsWith('.sql'),
          )
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  // name -> (argument-name list joined) -> signature, so a later CREATE of the
  // same shape replaces the earlier one rather than piling up.
  final Map<String, Map<String, _Signature>> out =
      <String, Map<String, _Signature>>{};

  final RegExp create = RegExp(
    r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?([a-z0-9_]+)\s*\(',
    caseSensitive: false,
  );
  final RegExp drop = RegExp(
    r'DROP\s+FUNCTION\s+(?:IF\s+EXISTS\s+)?(?:public\.)?([a-z0-9_]+)\s*\(',
    caseSensitive: false,
  );

  for (final File f in <File>[...migrations, ...patches]) {
    final String src = _stripComments(f.readAsStringSync());

    // ⚠ IN SOURCE ORDER, and that is the whole of it. A patch that changes a
    //   signature writes DROP then CREATE in the same file — applying every
    //   CREATE first and every DROP after would delete the function the patch
    //   just installed, and the tool would report a live endpoint as missing.
    //   (It did, on api_adeel_statement, the first time it ran.)
    final List<RegExpMatch> statements = <RegExpMatch>[
      ...create.allMatches(src),
      ...drop.allMatches(src),
    ]..sort((RegExpMatch a, RegExpMatch b) => a.start.compareTo(b.start));

    for (final RegExpMatch m in statements) {
      final String name = m.group(1)!;
      final String? inside = _balanced(src, m.end - 1);
      if (inside == null) continue;
      final bool isDrop = m.pattern == drop;

      if (isDrop) {
        // A DROP names types, not argument names, so the shape cannot be
        // matched by name. Drop by ARITY, which is what distinguishes the
        // overloads this repository actually creates.
        final int arity = _splitTop(
          inside,
        ).where((String s) => s.trim().isNotEmpty).length;
        out[name]?.removeWhere(
          (String _, _Signature s) => s.args.length == arity,
        );
      } else {
        final _Signature sig = _Signature(name, _parseArgs(inside));
        (out[name] ??= <String, _Signature>{})[sig.names.join(',')] = sig;
      }
    }
  }

  return out.map(
    (String k, Map<String, _Signature> v) =>
        MapEntry<String, List<_Signature>>(k, v.values.toList()),
  );
}

/// The text between the parenthesis at [open] and its match.
String? _balanced(String src, int open) {
  int depth = 0;
  for (int i = open; i < src.length; i++) {
    final String c = src[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return src.substring(open + 1, i);
    }
    // A dollar-quoted body cannot begin before the argument list closes, so
    // nothing else needs escaping here.
  }
  return null;
}

/// Argument names, with «does it have a DEFAULT» — commas inside a type such as
/// `numeric(12,2)` or an array default do not separate arguments.
List<_Arg> _parseArgs(String inside) {
  final List<_Arg> args = <_Arg>[];
  for (final String raw in _splitTop(inside)) {
    final String arg = raw.trim();
    if (arg.isEmpty) continue;
    final List<String> words = arg.split(RegExp(r'\s+'));
    if (words.isEmpty) continue;
    String first = words.first;
    // OUT/INOUT/VARIADIC prefixes, which this schema does not use but which
    // would silently shift the name by one word if it ever did.
    if (<String>[
          'out',
          'inout',
          'in',
          'variadic',
        ].contains(first.toLowerCase()) &&
        words.length > 1) {
      first = words[1];
    }
    args.add(
      _Arg(
        first,
        hasDefault: RegExp(
          r'\bDEFAULT\b|:=',
          caseSensitive: false,
        ).hasMatch(arg),
      ),
    );
  }
  return args;
}

/// Split on commas that are not inside parentheses or quotes.
List<String> _splitTop(String s) {
  final List<String> parts = <String>[];
  final StringBuffer buf = StringBuffer();
  int depth = 0;
  bool quoted = false;
  for (int i = 0; i < s.length; i++) {
    final String c = s[i];
    if (c == "'") quoted = !quoted;
    if (!quoted) {
      if (c == '(') depth++;
      if (c == ')') depth--;
      if (c == ',' && depth == 0) {
        parts.add(buf.toString());
        buf.clear();
        continue;
      }
    }
    buf.write(c);
  }
  parts.add(buf.toString());
  return parts;
}

/// Every `.rpc(...)` in lib/, with the parameter names it sends.
List<_Call> _readDartCalls() {
  final List<_Call> calls = <_Call>[];
  final RegExp call = RegExp(r"\.rpc<[^>]*>\(\s*'([a-z0-9_]+)'");

  for (final File f
      in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))) {
    final String src = f.readAsStringSync();
    for (final RegExpMatch m in call.allMatches(src)) {
      final String name = m.group(1)!;
      final int line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      String tail = _callTail(src, m.end);

      // ⚠ `params: someMap` — a map built a few lines above the call, which is
      //   how every optional argument in this app is written. Reading only the
      //   brackets of the call itself reported those calls as sending nothing.
      final RegExpMatch? named = RegExp(
        r'params:\s*([A-Za-z_][A-Za-z0-9_]*)\s*[,)]',
      ).firstMatch(tail);
      if (named != null) {
        final String? literal = _mapLiteral(
          src,
          named.group(1)!,
          before: m.start,
        );
        if (literal != null) tail = literal;
      }

      final List<String> params = <String>[];
      final List<String> always = <String>[];
      for (final RegExpMatch p in RegExp(
        r"(if\s*\([^)]*\)\s*)?'(p_[a-z0-9_]+)'\s*:",
      ).allMatches(tail)) {
        params.add(p.group(2)!);
        if (p.group(1) == null) always.add(p.group(2)!);
      }

      calls.add(
        _Call('${f.path.replaceAll(r'\', '/')}:$line', name, params, always),
      );
    }
  }
  return calls;
}

/// The `{ … }` of `final Map<String, dynamic> <name> = <String, dynamic>{ … };`
/// — the nearest declaration ABOVE the call, which is the one it reads.
String? _mapLiteral(String src, String variable, {required int before}) {
  final RegExp decl = RegExp(
    'Map<String,\\s*dynamic>\\s+$variable\\s*=\\s*<String,\\s*dynamic>\\s*\\{',
  );
  RegExpMatch? best;
  for (final RegExpMatch m in decl.allMatches(src)) {
    if (m.start < before) best = m;
  }
  if (best == null) return null;

  int depth = 0;
  for (int i = best.end - 1; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(best.end, i);
    }
  }
  return null;
}

/// From the function name to the closing bracket of the `.rpc(` call.
String _callTail(String src, int from) {
  int depth = 1;
  for (int i = from; i < src.length; i++) {
    final String c = src[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return src.substring(from, i);
    }
  }
  return src.substring(from);
}

/// `--` comments only. A `/* */` block never wraps a CREATE in this repository,
/// and a `--` line is where a commented-out signature would hide.
String _stripComments(String sql) => sql
    .split('\n')
    .map((String l) {
      final int i = l.indexOf('--');
      if (i < 0) return l;
      // Leave a `--` that sits inside a quoted string alone.
      final String before = l.substring(0, i);
      final int quotes = "'".allMatches(before).length;
      return quotes.isEven ? before : l;
    })
    .join('\n');
