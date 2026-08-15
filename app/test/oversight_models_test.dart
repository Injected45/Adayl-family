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
        'treasurer': <String, dynamic>{
          'name': 'سالم',
          'phone': '09',
        },
        'financeManager': <String, dynamic>{
          'name': 'إبراهيم',
          'phone': '08',
        },
      };

      final EditableSettings parsed = EditableSettings.fromJson(json);
      expect(parsed.toJson(), json);
      // Money stays a string end to end — it is never parsed into a double.
      expect(parsed.memberFee, isA<String>());
    });
  });

}
