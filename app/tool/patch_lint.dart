// ignore_for_file: avoid_print
import 'dart:io';

/// patch_lint — refuses a `PATCH_*.sql` that is wrong in a way a person will
/// not notice until it is running against the association's money.
///
/// Run from `app/`, like the other two:
///   dart run tool/patch_lint.dart
///
/// ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
/// Every rule below is a check that was being done BY HAND, in a message, once
/// per patch — and a check done by hand is a check that will be skipped on the
/// evening it matters. The association put it plainly: «لا أريد غلط في التاريخ.
/// أمر قطعي». A promise to be careful is not an answer to that; a gate is.
///
/// ⚠ AND IT CARRIES NO EXEMPTION LIST, deliberately. The moment a lint keeps a
///   list of files it forgives, the list is the real specification and the rule
///   is decoration. The four patches whose names ran ahead of the calendar were
///   RENAMED to their true dates rather than exempted here.
void main() {
  final Directory dir = Directory('../supabase');
  if (!dir.existsSync()) {
    print('patch_lint: ../supabase not found — run me from app/');
    exit(2);
  }

  final List<File> patches =
      dir
          .listSync()
          .whereType<File>()
          .where((File f) => _name(f).startsWith('PATCH_'))
          .toList()
        ..sort((File a, File b) => _name(a).compareTo(_name(b)));

  final List<String> problems = <String>[];
  final DateTime today = DateTime.now();

  for (final File f in patches) {
    final String name = _name(f);
    final String src = f.readAsStringSync();

    // ── 1. THE DATE IN THE NAME IS NOT IN THE FUTURE ────────────────────────
    //
    // ⚠ THE ONE THIS FILE WAS BUILT FOR. Four patches were numbered as a
    //   SEQUENCE and dressed as dates — 22, 23, 24 — while the calendar said
    //   the 20th. It is the same mistake the whole of 20/08 was spent removing
    //   from the vouchers: a date nobody checked, in the future, that every
    //   later reader believes.
    final RegExp stamp = RegExp(r'^PATCH_(\d{4})(\d{2})(\d{2})([a-z]?)_');
    final RegExpMatch? m = stamp.firstMatch(name);
    if (m == null) {
      problems.add('$name: not PATCH_YYYYMMDD[letter]_name.sql');
    } else {
      final DateTime named = DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
      // Compared by DAY, not by instant: a patch written at 01:39 is still
      // written today, and a clock a few minutes ahead must not fail a build.
      final DateTime cutoff = DateTime(today.year, today.month, today.day);
      if (named.isAfter(cutoff)) {
        problems.add(
          '$name: dated ${_iso(named)}, which has not happened '
          '(today is ${_iso(cutoff)})',
        );
      }
    }

    // Comments carry prose about failures; the rules below are about CODE.
    final String code = src
        .split('\n')
        .map((String line) {
          final int i = line.indexOf('--');
          return i == -1 ? line : line.substring(0, i);
        })
        .join('\n');

    // ── 2. ONE TRANSACTION, OPENED AND CLOSED ───────────────────────────────
    //
    // ⚠ A patch that forgets COMMIT leaves the editor holding an open
    //   transaction that is rolled back when the tab closes — so it reports no
    //   error and lands nothing, which is the most confusing outcome available.
    final int begins = RegExp(r'^BEGIN;', multiLine: true).allMatches(src).length;
    final int commits =
        RegExp(r'^COMMIT;', multiLine: true).allMatches(src).length;
    if (begins != 1 || commits != 1) {
      problems.add('$name: needs exactly one BEGIN; and one COMMIT; '
          '(found $begins / $commits)');
    }

    // ── 3. DOLLAR QUOTES BALANCE ────────────────────────────────────────────
    //
    // ⚠ An odd tag swallows the rest of the file into a string literal, and
    //   Postgres reports it as a syntax error hundreds of lines from the cause.
    //   This has happened here: a JS rewrite turned `$` into `$$` inside a
    //   generated patch and the damage was invisible on screen.
    final Map<String, int> tags = <String, int>{};
    for (final RegExpMatch t
        in RegExp(r'\$[a-z_]*\$').allMatches(code)) {
      tags.update(t.group(0)!, (int n) => n + 1, ifAbsent: () => 1);
    }
    tags.forEach((String tag, int n) {
      if (n.isOdd) problems.add('$name: $tag appears $n times — unbalanced');
    });

    // ── 4. NO TABLE THAT DOES NOT EXIST ─────────────────────────────────────
    //
    // ⚠ `public.settings` was written in a patch that meant
    //   `association_settings`, and it would have aborted on its first
    //   statement. It was found because somebody asked «هل فيه ترقيعات لا
    //   تعمل؟» — which is not a process.
    for (final RegExpMatch t
        in RegExp(r'\bpublic\.([a-z_]+)\b').allMatches(code)) {
      final String table = t.group(1)!;
      if (_ghosts.contains(table)) {
        problems.add('$name: public.$table does not exist in this schema');
      }
    }

    // ── 4b. NO BACKSLASH-ESCAPED QUOTE ──────────────────────────────────────
    //
    // ⚠ `\'` IS A JAVASCRIPT ESCAPE AND A POSTGRES SYNTAX ERROR. Postgres
    //   doubles a quote to escape it and has no backslash escape at all in a
    //   standard-conforming string. These patches are generated by small JS
    //   scripts, and an escape that was correct in the generator landed
    //   verbatim in the file — 42601 at the first one, on a message nobody
    //   would ever have read anyway.
    //
    //   It has bitten twice now in different forms: once as `$` doubling
    //   inside dollar-quotes, once as this. Both are the generator leaking
    //   into the generated.
    if (code.contains(r"\'")) {
      problems.add('$name: contains \\\' — Postgres escapes a quote by '
          'doubling it, and a backslash is a syntax error');
    }
    // ── 5. THE LOCKDOWN SWEEP GOES AFTER THE LAST CREATE ────────────────────
    //
    // ⚠ 20/08 (b) put it in the middle and created a trigger function below it.
    //   The sweep never saw that function, it took the built-in EXECUTE to
    //   PUBLIC, and assert_function_grants() rolled the whole patch back naming
    //   a function rather than the missing REVOKE.
    final int sweep = code.lastIndexOf(r'DO $lockdown$');
    if (sweep >= 0) {
      final int lastCreate = RegExp(
        r'^CREATE (OR REPLACE )?(FUNCTION|TRIGGER|POLICY|VIEW)',
        multiLine: true,
      ).allMatches(code).map((RegExpMatch c) => c.start).fold(-1, _max);
      if (lastCreate > sweep) {
        problems.add(
          '$name: the DO \$lockdown\$ sweep runs BEFORE a later CREATE — '
          'anything created after it keeps EXECUTE to PUBLIC',
        );
      }
    }

    // ── 6. THE GUARDS ARE CALLED ────────────────────────────────────────────
    //
    // They are what turn a bad patch into a rolled-back one. A patch without
    // them can land broken and report success.
    for (final String guard in <String>[
      'assert_signin_intact',
      'assert_function_grants',
      'assert_no_public_execute',
      'assert_views_security_invoker',
    ]) {
      if (!code.contains(guard)) {
        problems.add('$name: does not call $guard()');
      }
    }
  }

  // ── 7. AND NO FUTURE DATE ANYWHERE IN supabase/, not just in a filename ──
  //
  // ⚠ THE FIRST VERSION OF THIS LINT CHECKED FILENAMES ONLY, and the very next
  //   thing handed over was WHICH_STATE.sql still printing «PATCH 21/08» …
  //   «PATCH 24/08» in its display rows and its verdict. The files had been
  //   renamed; the labels INSIDE them had not. A rule that guards the name and
  //   not the text catches the tidy half of the mistake and reports success.
  //
  // Two forms are used in this repo and both are checked: `PATCH_YYYYMMDD`
  // when a file is named, and `PATCH DD/MM` when a row is labelled.
  final RegExp longForm = RegExp(r'PATCH_(\d{4})(\d{2})(\d{2})');
  final RegExp shortForm = RegExp(r'PATCH (\d{2})/(\d{2})');
  final DateTime cutoff = DateTime(today.year, today.month, today.day);

  for (final File f in dir.listSync().whereType<File>()) {
    final String name = _name(f);
    if (!name.endsWith('.sql')) continue;
    final String src = f.readAsStringSync();

    for (final RegExpMatch r in longForm.allMatches(src)) {
      final DateTime d = DateTime(
        int.parse(r.group(1)!),
        int.parse(r.group(2)!),
        int.parse(r.group(3)!),
      );
      if (d.isAfter(cutoff)) {
        problems.add(
          '$name: refers to ${r.group(0)}, a date that has not happened',
        );
      }
    }

    for (final RegExpMatch r in shortForm.allMatches(src)) {
      // No year on these labels, so the current one is assumed — which is what
      // a reader assumes too, and is exactly why a stale label misleads.
      final DateTime d = DateTime(
        today.year,
        int.parse(r.group(2)!),
        int.parse(r.group(1)!),
      );
      if (d.isAfter(cutoff)) {
        problems.add(
          '$name: prints «${r.group(0)}», a date that has not happened',
        );
      }
    }
  }
  if (problems.isEmpty) {
    print('patch_lint: ${patches.length} patches scanned and every .sql date '
        'checked, no problems found.');
    return;
  }
  for (final String p in problems) {
    print('patch_lint: $p');
  }
  exit(1);
}

int _max(int a, int b) => a > b ? a : b;

String _name(File f) => f.uri.pathSegments.last;

String _iso(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// Tables that do NOT exist and have been written by mistake.
///
/// ⚠ A DENY-LIST, NOT AN ALLOW-LIST, and that is a deliberate trade. An
///   allow-list would have to be regenerated every time the schema grows a
///   table, and a lint that fails on correct new code is a lint that gets
///   deleted. This catches the names that have actually been typed in error
///   here; add to it the next time one is.
const Set<String> _ghosts = <String>{
  'settings', // meant association_settings — caught by hand on 2026-08-20
  'families', // the pre-adeel schema
  'members',
  'receivable_lines',
};
