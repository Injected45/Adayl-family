import 'dart:convert';
import 'dart:io';

import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/directory/domain/models.dart';
import 'package:family_app/features/finance/domain/models.dart';
import 'package:family_app/features/oversight/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The view→model contract.
///
/// Every fixture here was captured from a REAL PostgreSQL running the real
/// migrations, by `supabase/tests/extract_fixtures.sh`, as an authenticated
/// caller with RLS in force. PostgREST builds its response body with `json_agg`
/// inside Postgres, so these bytes are what the Flutter client will actually
/// receive over the wire.
///
/// That makes this the strongest check available without a Supabase project: it
/// verifies the SQL and the Dart agree on every key, every type and every money
/// representation. The only thing it does not cover is the HTTP hop.
///
/// It also fails loudly if the SQL drifts. Rename a view column and the model
/// stops parsing here, before anyone runs the app.

Map<String, dynamic> _obj(String name) =>
    (jsonDecode(File('test/fixtures/supabase/$name').readAsStringSync()) as Map)
        .cast<String, dynamic>();

List<Map<String, dynamic>> _list(String name) =>
    (jsonDecode(File('test/fixtures/supabase/$name').readAsStringSync())
            as List<dynamic>)
        .map((dynamic e) => (e as Map).cast<String, dynamic>())
        .toList();

/// Walks any decoded JSON and reports every value that arrived as a `double`.
///
/// This is the check the whole design hinges on. Postgres `numeric` serialises to
/// a bare JSON number, `dart:convert` turns that into a `double`, and this project
/// forbids floats anywhere near money. Every view and RPC casts amounts to text
/// for exactly that reason — and an assertion is the only thing that keeps it true
/// the next time a column is added.
List<String> _doublesIn(Object? node, [String path = r'$']) {
  final List<String> found = <String>[];
  if (node is Map) {
    node.forEach((Object? k, Object? v) {
      found.addAll(_doublesIn(v, '$path.$k'));
    });
  } else if (node is List) {
    for (int i = 0; i < node.length; i++) {
      found.addAll(_doublesIn(node[i], '$path[$i]'));
    }
  } else if (node is double) {
    found.add('$path = $node');
  }
  return found;
}

void main() {
  group('money never arrives as a float', () {
    // Names of keys that carry money. If any of these ever decodes to a double,
    // the ::text cast was dropped from a view and the treasury is now running on
    // binary floating point.
    const Set<String> moneyKeys = <String>{
      'amount',
      'balance',
      'cash',
      'collected',
      'credit',
      'currentFee',
      'debit',
      'debt',
      'fatherFee',
      'issued',
      'monthlyExpected',
      'month',
      'outstanding',
      'paid',
      'sonFee',
      'today',
      'total',
      'transfer',
      'year',
    };

    for (final String file in <String>[
      'settings.json',
      'settings_view.json',
      'dashboard.json',
      'family_detail.json',
      'family_statement.json',
      'receivables.json',
      'financial_report.json',
      'families.json',
      'members.json',
      'payments.json',
      'cash_movements.json',
      'cash_summary.json',
    ]) {
      test('$file contains no floating-point value at all', () {
        final Object? decoded = jsonDecode(
          File('test/fixtures/supabase/$file').readAsStringSync(),
        );
        expect(
          _doublesIn(decoded),
          isEmpty,
          reason:
              'a numeric column reached the client unquoted — add ::text to it '
              'in supabase/migrations/20260811091000_api_surface.sql',
        );
      });
    }

    test('every money key is a String, in every fixture', () {
      final List<String> offenders = <String>[];
      void walk(Object? node, String path) {
        if (node is Map) {
          node.forEach((Object? k, Object? v) {
            if (moneyKeys.contains(k) && v != null && v is! String) {
              offenders.add('$path.$k is ${v.runtimeType}');
            }
            walk(v, '$path.$k');
          });
        } else if (node is List) {
          for (int i = 0; i < node.length; i++) {
            walk(node[i], '$path[$i]');
          }
        }
      }

      for (final FileSystemEntity f in Directory(
        'test/fixtures/supabase',
      ).listSync()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        walk(jsonDecode(f.readAsStringSync()), f.uri.pathSegments.last);
      }
      expect(offenders, isEmpty);
    });

    test('the money strings are exact to the minor unit', () {
      // Not merely "a string" — the right string. A cast that produced
      // "40.0000000001" would satisfy the type check above and still be wrong.
      final Map<String, dynamic> detail = _obj('family_detail.json');
      final Map<String, dynamic> kpis = (detail['kpis'] as Map)
          .cast<String, dynamic>();
      for (final String key in <String>['debt', 'paid', 'monthlyExpected']) {
        expect(
          kpis[key] as String,
          matches(RegExp(r'^-?\d+\.\d{2}$')),
          reason: 'kpis.$key = ${kpis[key]}',
        );
      }
    });
  });

  group('directory', () {
    test('settings parse', () {
      final AssociationSettingsView s = AssociationSettingsView.fromJson(
        _obj('settings_view.json'),
      );
      expect(s.currency, isNotEmpty);
      expect(s.fatherFee, '20.00');
      expect(s.sonFee, '10.00');
      expect(s.eligibilityAge, 16);
      expect(s.warningMonths, 3);
    });

    test('officials parse, both roles present', () {
      final List<Official> officials = _list(
        'officials.json',
      ).map(Official.fromJson).toList();
      expect(officials.length, 2);
      expect(
        officials.map((Official o) => o.role),
        containsAll(<String>['treasurer', 'financeManager']),
      );
    });

    test('families list parses with its computed counts', () {
      final List<FamilyListItem> families = _list(
        'families.json',
      ).map(FamilyListItem.fromJson).toList();
      expect(families, hasLength(2));

      final FamilyListItem first = families.firstWhere(
        (FamilyListItem f) => f.familyCode == 'F-0001',
      );
      expect(first.fatherName, 'الأب الأول');
      // Three sons in the fixture, two of them over 16.
      expect(first.sonsCount, 3);
      expect(first.eligibleCount, 2);
      // Father (20) + two eligible sons (10 each) at CURRENT settings.
      expect(first.monthlyExpected, '40.00');
    });

    test('members list parses, fathers and sons distinguished', () {
      final List<MemberListItem> members = _list(
        'members.json',
      ).map(MemberListItem.fromJson).toList();
      expect(members, hasLength(6));
      expect(
        members.where((MemberListItem m) => m.relation == 'الأب').length,
        2,
      );
      expect(
        members.every((MemberListItem m) => m.fullName.isNotEmpty),
        isTrue,
      );
      expect(
        members.every((MemberListItem m) => m.familyName.isNotEmpty),
        isTrue,
        reason: 'every member should resolve its family via the father name',
      );
    });

    test('family detail parses its nested family/father/sons/kpis', () {
      final FamilyDetail d = FamilyDetail.fromJson(_obj('family_detail.json'));
      expect(d.id, 1);
      expect(d.familyCode, 'F-0001');
      expect(d.father, isNotNull);
      expect(d.father!.fullName, 'الأب الأول');
      expect(d.sons, hasLength(3));
      expect(d.sonsCount, 3);
      expect(d.eligibleCount, 2);
      // 80 issued across two periods, 50 collected, so 30 outstanding.
      expect(d.paid, '50.00');
      expect(d.debt, '30.00');
    });

    test('member eligibility comes through as the app expects', () {
      final FamilyDetail d = FamilyDetail.fromJson(_obj('family_detail.json'));
      final Set<String> keys = d.sons
          .map((MemberView m) => m.eligibility.name)
          .toSet();
      // Whatever the values are, they must map onto the enum rather than
      // silently degrading — EligibilityKey.fromWire has a fallback, so an
      // unrecognised string would look like valid data.
      expect(keys, isNotEmpty);
      expect(
        d.sons.map((MemberView m) => m.eligibilityLabel),
        everyElement(isNotEmpty),
      );
      // Two of the three sons are over 16 in the fixture.
      expect(
        d.sons
            .where((MemberView m) => m.eligibility == EligibilityKey.eligible)
            .length,
        2,
      );
    });

    test('statement parses as an ordered running balance', () {
      final Map<String, dynamic> raw = _obj('family_statement.json');
      final List<StatementMovement> movements =
          (raw['movements'] as List<dynamic>)
              .map(
                (dynamic e) => StatementMovement.fromJson(
                  (e as Map).cast<String, dynamic>(),
                ),
              )
              .toList();
      expect(movements, isNotEmpty);
      expect(raw['closingBalance'], '30.00');

      // Rule 11: the running balance must actually run. Recomputing it from the
      // debits and credits has to reproduce the column exactly, or the window
      // function is ordering by something other than what it emits.
      double running = 0;
      for (final StatementMovement m in movements) {
        running += double.parse(m.debit ?? '0') - double.parse(m.credit ?? '0');
        expect(
          double.parse(m.balance),
          closeTo(running, 0.001),
          reason: 'balance drifted at ${m.reference}',
        );
      }
      expect(
        double.parse(raw['closingBalance'] as String),
        closeTo(running, 0.001),
      );
    });

    test('receivables page parses with a summary that ties to its items', () {
      final Map<String, dynamic> raw = _obj('receivables.json');
      final ReceivablesPage page = ReceivablesPage(
        items: (raw['items'] as List<dynamic>)
            .map(
              (dynamic e) =>
                  ReceivableItem.fromJson((e as Map).cast<String, dynamic>()),
            )
            .toList(),
        summary: ReceivablesSummary.fromJson(
          (raw['summary'] as Map).cast<String, dynamic>(),
        ),
      );
      expect(page.items, isNotEmpty);
      expect(page.items.first.periodLabel, contains('20'));

      double issued = 0;
      double outstanding = 0;
      for (final ReceivableItem r in page.items) {
        if (r.status == 'ملغي') continue;
        issued += double.parse(r.total);
        outstanding += double.parse(r.balance);
      }
      expect(double.parse(page.summary.issued), closeTo(issued, 0.001));
      expect(
        double.parse(page.summary.outstanding),
        closeTo(outstanding, 0.001),
      );
    });

    test('the Arabic period label is a month name, not a raw period', () {
      final Map<String, dynamic> raw = _obj('receivables.json');
      final List<ReceivableItem> items = (raw['items'] as List<dynamic>)
          .map(
            (dynamic e) =>
                ReceivableItem.fromJson((e as Map).cast<String, dynamic>()),
          )
          .toList();
      final ReceivableItem march = items.firstWhere(
        (ReceivableItem r) => r.period == '2026-03',
      );
      expect(march.periodLabel, 'مارس 2026');
    });
  });

  group('finance', () {
    test('payments parse with their FIFO allocations nested', () {
      final List<PaymentView> payments = _list(
        'payments.json',
      ).map(PaymentView.fromJson).toList();
      expect(payments, hasLength(2));

      final PaymentView split = payments.firstWhere(
        (PaymentView p) => p.amount == '50.00',
      );
      // 50 against 40 owed for February and 40 for March: February fills, March
      // takes the remaining 10.
      expect(split.allocations, hasLength(2));
      expect(split.allocations.first.period, '2026-02');
      expect(split.allocations.first.amount, '40.00');
      expect(split.allocations.last.period, '2026-03');
      expect(split.allocations.last.amount, '10.00');
      expect(split.receiptNo, startsWith('PAY-'));
    });

    test('a cancelled payment keeps its row and its allocations', () {
      final List<PaymentView> payments = _list(
        'payments.json',
      ).map(PaymentView.fromJson).toList();
      final PaymentView cancelled = payments.firstWhere(
        (PaymentView p) => p.status == 'ملغي',
      );
      expect(
        cancelled.allocations,
        isNotEmpty,
        reason: 'rule 9 preserves them',
      );
    });

    test('cash movements parse and the voided one is still listed', () {
      final List<CashMovementView> movements = _list(
        'cash_movements.json',
      ).map(CashMovementView.fromJson).toList();
      expect(movements, hasLength(2));
      expect(
        movements.where((CashMovementView m) => m.status == 'ملغي').length,
        1,
        reason: 'rule 9: voided, never hidden',
      );
    });

    test('the cash summary excludes the voided movement', () {
      final CashSummaryView summary = CashSummaryView.fromJson(
        _obj('cash_summary.json'),
      );
      // 50 collected, 5 cancelled → 50 in the treasury.
      expect(summary.total, '50.00');
      expect(summary.cash, '50.00');
      expect(summary.transfer, '0.00');
    });
  });

  group('oversight', () {
    test('dashboard parses stats, debtors and upcoming sons', () {
      final DashboardData d = DashboardData.fromJson(_obj('dashboard.json'));
      // Association-wide, across BOTH seeded families: 3 sons in F-0001 plus 1
      // in F-0002. An earlier version of this test asserted 3 and 35.00, which
      // were family-1 figures — the fixture is the whole association.
      expect(d.stats.families, 2);
      expect(d.stats.sons, 4);
      expect(d.stats.eligible, 3);
      expect(d.stats.collected, '50.00');
      // 100 issued across two periods, 50 collected → 50 outstanding.
      expect(d.stats.debt, '50.00');
      expect(
        d.stats.transfer,
        '0.00',
        reason: 'an empty bucket is still money',
      );
      expect(d.topDebtors, isNotEmpty);
      expect(d.closingPeriod, matches(RegExp(r'^\d{4}-\d{2}$')));
      expect(d.closingPeriodLabel, isNotEmpty);
      expect(d.closingPeriodLabel, isNot(d.closingPeriod));
    });

    test('top debtors are ordered by debt, descending', () {
      final DashboardData d = DashboardData.fromJson(_obj('dashboard.json'));
      final List<double> debts = d.topDebtors
          .map((DebtorRow r) => double.parse(r.debt))
          .toList();
      final List<double> sorted = List<double>.of(debts)
        ..sort((double a, double b) => b.compareTo(a));
      expect(debts, sorted);
      expect(debts.every((double v) => v > 0), isTrue);
    });

    test('alerts parse and carry a family to navigate to', () {
      final List<AlertItem> alerts = _list(
        'alerts.json',
      ).map(AlertItem.fromJson).toList();
      expect(alerts, isNotEmpty);
      expect(alerts.every((AlertItem a) => a.text.isNotEmpty), isTrue);
      expect(alerts.every((AlertItem a) => a.familyId > 0), isTrue);
      expect(alerts.map((AlertItem a) => a.type).toSet(), isNot(contains('')));
    });

    test('financial report parses with its payment rows', () {
      final FinancialReport r = FinancialReport.fromJson(
        _obj('financial_report.json'),
      );
      // Two periods x two families = four receivables: 40+40 for F-0001 and
      // 10+10 for F-0002.
      expect(r.issued, '100.00');
      expect(r.collected, '50.00');
      expect(r.issuedCount, 4);
      // The cancelled payment is out of the collected figure and out of the list.
      expect(r.collectedCount, 1);
      expect(r.payments, hasLength(1));
      expect(r.payments.first.amount, '50.00');
    });

    test('audit entries parse, newest-first orderable', () {
      final List<AuditEntry> entries = _list(
        'audit.json',
      ).map(AuditEntry.fromJson).toList();
      expect(entries, isNotEmpty);
      expect(
        entries.map((AuditEntry e) => e.eventType).toSet(),
        containsAll(<String>['payment.register', 'payment.cancel']),
      );
      expect(entries.every((AuditEntry e) => e.actorName.isNotEmpty), isTrue);
      // Microsecond timestamps: several entries land inside one operation, and
      // second precision made the display order unstable.
      expect(entries.first.occurredAt, contains('.'));
    });

    test('user accounts parse, with uuid ids and real roles', () {
      final List<UserAccount> users = _list(
        'users.json',
      ).map(UserAccount.fromJson).toList();
      expect(users, hasLength(6));

      final UserAccount admin = users.firstWhere(
        (UserAccount u) => u.email == 'admin@fam.test',
      );
      expect(admin.role, AppRole.admin);
      expect(admin.status, AccountStatus.approved);

      // The migration's one forced model change: ids are uuids now.
      expect(
        admin.id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        ),
      );

      // A role that failed to map would silently become `viewer`, so an explicit
      // check that the non-viewers survived the round trip.
      expect(
        users.map((UserAccount u) => u.role).toSet(),
        containsAll(<AppRole>[
          AppRole.admin,
          AppRole.financeManager,
          AppRole.treasurer,
          AppRole.viewer,
        ]),
      );
    });

    test('the pending and suspended accounts are distinguishable', () {
      final List<UserAccount> users = _list(
        'users.json',
      ).map(UserAccount.fromJson).toList();
      expect(
        users
            .firstWhere((UserAccount u) => u.email == 'pending@fam.test')
            .status,
        AccountStatus.pending,
      );
      expect(
        users
            .firstWhere((UserAccount u) => u.email == 'suspended@fam.test')
            .status,
        AccountStatus.suspended,
      );
    });

    test('editable settings parse, officials nested', () {
      final EditableSettings s = EditableSettings.fromJson(
        _obj('settings.json'),
      );
      expect(s.associationName, isNotEmpty);
      expect(s.systemStart, '2026-01-01');
      expect(s.treasurer, isNotNull);
      expect(s.financeManager, isNotNull);
    });
  });

  group('auth', () {
    test('api_me parses into an AppUser', () {
      final Map<String, dynamic> me = _obj('me.json');
      final AppUser user = AppUser.fromJson(me);
      expect(user.email, isNotEmpty);
      expect(user.role, isA<AppRole>());
      expect(user.id, isNotEmpty);
    });
  });
}
