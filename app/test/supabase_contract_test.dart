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
      'debit',
      'debt',
      'issued',
      'memberFee',
      'monthlyExpected',
      'month',
      'outstanding',
      'paid',
      'today',
      'total',
      'transfer',
      'year',
    };

    for (final String file in <String>[
      'settings.json',
      'settings_view.json',
      'dashboard.json',
      'adeel_detail.json',
      'adeel_statement.json',
      'receivables.json',
      'financial_report.json',
      'adeels.json',
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
      final Map<String, dynamic> detail = _obj('adeel_detail.json');
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
      // ONE rate. fatherFee/sonFee and the eligibilityAge/warningMonths pair are
      // gone from the wire entirely — if a view ever reintroduced them this
      // model would not carry them and the assertion below would be the first
      // thing to notice.
      expect(s.memberFee, '20.00');
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

    test('the register parses with its computed money columns', () {
      final List<AdeelListItem> adeels = _list(
        'adeels.json',
      ).map(AdeelListItem.fromJson).toList();
      expect(adeels, hasLength(4));

      final AdeelListItem first = adeels.firstWhere(
        (AdeelListItem a) => a.adeelCode == 'A-0001',
      );
      expect(first.fullName, 'العديل الأول');
      // One flat rate, and it is what he would be charged today.
      expect(first.monthlyExpected, '20.00');
    });

    test('membership status, not age, decides what is charged', () {
      final List<AdeelListItem> adeels = _list(
        'adeels.json',
      ).map(AdeelListItem.fromJson).toList();

      // THE assertion that pins the whole model change. A-0002 is seven years
      // old in the fixture and has been billed exactly like the 51-year-old, so
      // no age gate survives anywhere between the settings table and this model.
      final AdeelListItem child = adeels.firstWhere(
        (AdeelListItem a) => a.adeelCode == 'A-0002',
      );
      expect(child.age, lessThan(16));
      expect(child.monthlyExpected, '20.00');
      expect(child.issued, isNot('0.00'));

      // And the two who are not نشط were charged nothing, whatever their age.
      for (final String code in <String>['A-0003', 'A-0004']) {
        final AdeelListItem inactive = adeels.firstWhere(
          (AdeelListItem a) => a.adeelCode == code,
        );
        expect(inactive.membershipStatus, isNot('نشط'));
        expect(inactive.monthlyExpected, '0.00');
        expect(inactive.issued, '0.00');
      }
    });

    test('adeel detail parses its nested adeel/kpis/receivables', () {
      final AdeelDetail d = AdeelDetail.fromJson(_obj('adeel_detail.json'));
      expect(d.adeel.id, 1);
      expect(d.adeel.adeelCode, 'A-0001');
      expect(d.adeel.fullName, 'العديل الأول');
      // 40 issued across two periods, 30 collected, so 10 outstanding.
      expect(d.issued, '40.00');
      expect(d.paid, '30.00');
      expect(d.debt, '10.00');
      expect(d.openPeriods, 1);
      expect(d.receivables, isNotEmpty);
    });

    test('a receivable carries the name it was raised against', () {
      final AdeelDetail d = AdeelDetail.fromJson(_obj('adeel_detail.json'));
      // Snapshot columns, not a join: a receipt printed years later must read
      // the same even if the register is edited afterwards.
      expect(
        d.receivables.every((ReceivableItem r) => r.adeelName.isNotEmpty),
        isTrue,
      );
      expect(
        d.receivables.every(
          (ReceivableItem r) => r.adeelNationalId.isNotEmpty,
        ),
        isTrue,
      );
    });

    test('statement parses as an ordered running balance', () {
      final Map<String, dynamic> raw = _obj('adeel_statement.json');
      final List<StatementMovement> movements =
          (raw['movements'] as List<dynamic>)
              .map(
                (dynamic e) => StatementMovement.fromJson(
                  (e as Map).cast<String, dynamic>(),
                ),
              )
              .toList();
      expect(movements, isNotEmpty);
      expect(raw['closingBalance'], '10.00');

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
        (PaymentView p) => p.amount == '30.00',
      );
      // 30 against 20 owed for February and 20 for March: February fills, March
      // takes the remaining 10.
      expect(split.allocations, hasLength(2));
      expect(split.allocations.first.period, '2026-02');
      expect(split.allocations.first.amount, '20.00');
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
      // 30 collected, 5 cancelled → 30 in the treasury.
      expect(summary.total, '30.00');
      expect(summary.cash, '30.00');
      expect(summary.transfer, '0.00');
    });
  });

  group('oversight', () {
    test('dashboard parses stats and debtors', () {
      final DashboardData d = DashboardData.fromJson(_obj('dashboard.json'));
      // Association-wide: four عدايل on the register, two of them نشط and
      // therefore the only two billed.
      expect(d.stats.adeels, 4);
      expect(d.stats.active, 2);
      expect(d.stats.suspended, 1);
      expect(d.stats.deceased, 1);
      expect(d.stats.collected, '30.00');
      // 2 active × 2 periods × 20.00 = 80 issued, 30 collected → 50 outstanding.
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

    test('alerts parse and carry an عديل to navigate to', () {
      final List<AlertItem> alerts = _list(
        'alerts.json',
      ).map(AlertItem.fromJson).toList();
      expect(alerts, isNotEmpty);
      expect(alerts.every((AlertItem a) => a.text.isNotEmpty), isTrue);
      expect(alerts.every((AlertItem a) => a.adeelId > 0), isTrue);
      expect(alerts.map((AlertItem a) => a.type).toSet(), isNot(contains('')));
    });

    test('financial report parses with its payment rows', () {
      final FinancialReport r = FinancialReport.fromJson(
        _obj('financial_report.json'),
      );
      // Two periods x two ACTIVE عدايل = four receivables at 20.00 each. The
      // موقوف and المتوفى are billed nothing, so they contribute none.
      expect(r.issued, '80.00');
      expect(r.collected, '30.00');
      expect(r.issuedCount, 4);
      // The cancelled payment is out of the collected figure and out of the list.
      expect(r.collectedCount, 1);
      expect(r.payments, hasLength(1));
      expect(r.payments.first.amount, '30.00');
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
