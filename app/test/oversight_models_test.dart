import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/oversight/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardData', () {
    test('parses the stats object the server sends', () {
      final DashboardData data = DashboardData.fromJson(<String, dynamic>{
        'stats': <String, dynamic>{
          'adeels': 6,
          'active': 4,
          'suspended': 1,
          'deceased': 1,
          'debt': '75.00',
          'collected': '135.00',
          'cash': '95.00',
          'transfer': '40.00',
          'indebtedAdeels': 2,
        },
        'topDebtors': <dynamic>[
          <String, dynamic>{
            'adeelId': 1,
            'adeelCode': 'A-0001',
            'adeelName': 'محمد',
            'debt': '45.00',
          },
        ],
        'closingPeriod': '2026-07',
        'closingPeriodLabel': 'يوليو ٢٠٢٦',
      });

      expect(data.stats.adeels, 6);
      expect(data.stats.debt, '75.00');
      expect(data.topDebtors.single.adeelCode, 'A-0001');
      expect(data.closingPeriod, '2026-07');
    });

    test('the status buckets account for every عديل', () {
      // Unlike the eligibility buckets they replaced, these ARE exhaustive:
      // member_status has exactly three values and every row carries one, so a
      // total that does not reconcile means a status was added to the enum
      // without being counted here.
      final DashboardData data = DashboardData.fromJson(<String, dynamic>{
        'stats': <String, dynamic>{
          'adeels': 4,
          'active': 2,
          'suspended': 1,
          'deceased': 1,
          'debt': '0.00',
          'collected': '0.00',
          'cash': '0.00',
          'transfer': '0.00',
          'indebtedAdeels': 0,
        },
        'topDebtors': <dynamic>[],
        'closingPeriod': '2026-07',
        'closingPeriodLabel': 'x',
      });
      expect(
        data.stats.active + data.stats.suspended + data.stats.deceased,
        data.stats.adeels,
      );
    });
  });

  group('UserAccount', () {
    test('parses an account and its role', () {
      final UserAccount user = UserAccount.fromJson(<String, dynamic>{
        'id': 3,
        'email': 'someone@example.test',
        'displayName': 'أمين',
        'role': 'treasurer',
        'status': 'approved',
        'lastLoginAt': null,
        'approvedByName': 'المسؤول الأول',
      });
      expect(user.role, AppRole.treasurer);
      expect(user.status, AccountStatus.approved);
      expect(user.lastLoginAt, isNull);
    });

    test('an unknown role degrades to viewer, never to admin', () {
      final UserAccount user = UserAccount.fromJson(<String, dynamic>{
        'id': 4,
        'role': 'superuser',
        'status': 'approved',
      });
      expect(user.role, AppRole.viewer);
    });
  });

  group('EditableSettings', () {
    test('round-trips through JSON without losing a field', () {
      const Map<String, dynamic> json = <String, dynamic>{
        'associationName': 'جمعية العائلة',
        'currency': 'د.ل',
        'memberFee': '20.00',
        'systemStart': '2026-01-01',
        'autoClosePreviousMonths': true,
        // The association's receiving account. register_payment snapshots it
        // onto every تحويل مصرفي server-side, so it has to survive this trip
        // intact — a field dropped here is an account number silently reverting
        // to blank the next time an admin saves settings.
        'bankAccountNo': 'LY83 0021 0000 0001 2345 6789',
        'bankAccountName': 'جمعية العدايل',
        // adeelId is the post's real identity: both officials are elected from
        // the register, so api_settings sends which عديل holds each post and
        // the name/phone beside it are the server's snapshot of his row.
        'treasurer': <String, dynamic>{
          'adeelId': 7,
          'name': 'سالم',
          'phone': '09',
        },
        'financeManager': <String, dynamic>{
          'adeelId': 12,
          'name': 'إبراهيم',
          'phone': '08',
        },
      };

      final EditableSettings parsed = EditableSettings.fromJson(json);
      expect(parsed.toJson(), json);
      // Money stays a string end to end — it is never parsed into a double.
      expect(parsed.memberFee, isA<String>());
    });

    test('toPatch uses the FLAT keys update_settings actually reads', () {
      // The bug this pins: api_settings sends the officials NESTED, so toJson
      // does too — but update_settings reads `p_patch ->> 'treasurerName'`.
      // Posting the nested shape left all four lookups NULL, coalesce kept the
      // old row, and the treasurer and finance manager silently never saved
      // while every other field on the same screen did.
      //
      // The literals below are copied from
      // supabase/migrations/20260811090600_rpc.sql. If someone renames a key on
      // either side, this fails instead of the save quietly doing nothing.
      const EditableSettings settings = EditableSettings(
        associationName: 'جمعية العدايل',
        currency: 'د.ل',
        memberFee: '20.00',
        systemStart: '2026-01-01',
        autoClosePreviousMonths: true,
        bankAccountNo: '0021-000-1234',
        bankAccountName: 'جمعية العدايل',
        treasurer: OfficialInput(
          adeelId: 7,
          name: 'سالم',
          phone: '0910000001',
        ),
        financeManager: OfficialInput(
          adeelId: 12,
          name: 'إبراهيم',
          phone: '0910000002',
        ),
      );

      final Map<String, dynamic> patch = settings.toPatch();

      // The ids are what update_settings acts on — it reads the name and phone
      // off each chosen عديل's own row. They are sent FLAT, like the rest.
      expect(patch['treasurerAdeelId'], 7);
      expect(patch['financeAdeelId'], 12);
      expect(patch['treasurerName'], 'سالم');
      expect(patch['treasurerPhone'], '0910000001');
      expect(patch['financeName'], 'إبراهيم');
      expect(patch['financePhone'], '0910000002');

      // And the nested shape must NOT be what goes to the RPC: its presence is
      // exactly what made the save look like it worked.
      expect(patch.containsKey('treasurer'), isFalse);
      expect(patch.containsKey('financeManager'), isFalse);
    });

    test('a vacant post sends an explicit null, not a missing key', () {
      // update_settings tells "vacate this post" from "leave it alone" with
      // `p_patch ? 'treasurerAdeelId'`. Dropping the key when the value is null
      // — which most JSON builders do by habit — would make a post impossible
      // to clear once filled, and the only escape would be picking someone
      // wrong on purpose.
      const EditableSettings vacant = EditableSettings(
        associationName: 'ج',
        currency: 'د.ل',
        memberFee: '20.00',
        systemStart: '2026-01-01',
        autoClosePreviousMonths: true,
        bankAccountNo: '',
        bankAccountName: '',
        treasurer: OfficialInput(name: '', phone: ''),
        financeManager: OfficialInput(name: '', phone: ''),
      );

      final Map<String, dynamic> patch = vacant.toPatch();

      expect(patch.containsKey('treasurerAdeelId'), isTrue);
      expect(patch.containsKey('financeAdeelId'), isTrue);
      expect(patch['treasurerAdeelId'], isNull);
      expect(patch['financeAdeelId'], isNull);
    });
  });

}
