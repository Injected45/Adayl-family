import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/oversight/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardData', () {
    test('parses the stats object the server sends', () {
      final DashboardData data = DashboardData.fromJson(<String, dynamic>{
        'stats': <String, dynamic>{
          'families': 2,
          'sons': 6,
          'eligible': 3,
          'soon': 1,
          'under': 1,
          'debt': '75.00',
          'collected': '135.00',
          'cash': '95.00',
          'transfer': '40.00',
          'indebtedFamilies': 2,
        },
        'topDebtors': <dynamic>[
          <String, dynamic>{
            'familyId': 1,
            'familyCode': 'F-0001',
            'fatherName': 'محمد',
            'debt': '45.00',
          },
        ],
        'upcomingSons': <dynamic>[
          <String, dynamic>{
            'sonId': 3,
            'sonName': 'عمر',
            'familyId': 1,
            'fatherName': 'محمد',
          },
        ],
        'closingPeriod': '2026-07',
        'closingPeriodLabel': 'يوليو ٢٠٢٦',
      });

      expect(data.stats.families, 2);
      expect(data.stats.debt, '75.00');
      expect(data.topDebtors.single.familyCode, 'F-0001');
      expect(data.upcomingSons.single.sonName, 'عمر');
      expect(data.closingPeriod, '2026-07');
    });

    test('the eligibility buckets need not sum to the son count', () {
      // The prototype's else-if chain leaves an inactive son in no bucket, so
      // a client that "corrected" this would disagree with the association's
      // own figures.
      final DashboardData data = DashboardData.fromJson(<String, dynamic>{
        'stats': <String, dynamic>{
          'families': 1,
          'sons': 4,
          'eligible': 2,
          'soon': 0,
          'under': 1,
          'debt': '0.00',
          'collected': '0.00',
          'cash': '0.00',
          'transfer': '0.00',
          'indebtedFamilies': 0,
        },
        'topDebtors': <dynamic>[],
        'upcomingSons': <dynamic>[],
        'closingPeriod': '2026-07',
        'closingPeriodLabel': 'x',
      });
      expect(
        data.stats.eligible + data.stats.soon + data.stats.under,
        lessThan(data.stats.sons),
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
        'fatherFee': '20.00',
        'sonFee': '10.00',
        'eligibilityAge': 16,
        'warningMonths': 3,
        'systemStart': '2026-01-01',
        'autoClosePreviousMonths': true,
        'treasurer': <String, dynamic>{
          'name': 'سالم',
          'nationalId': '1',
          'phone': '09',
        },
        'financeManager': <String, dynamic>{
          'name': 'إبراهيم',
          'nationalId': '2',
          'phone': '08',
        },
      };

      final EditableSettings parsed = EditableSettings.fromJson(json);
      expect(parsed.toJson(), json);
      // Money stays a string end to end — it is never parsed into a double.
      expect(parsed.fatherFee, isA<String>());
    });
  });

  group('MemberInput', () {
    test('omits a null id so the server treats it as a new member', () {
      const MemberInput fresh = MemberInput(
        fullName: 'ابن جديد',
        nationalId: '123',
      );
      expect(fresh.toJson().containsKey('id'), isFalse);

      const MemberInput existing = MemberInput(
        id: 7,
        fullName: 'ابن قائم',
        nationalId: '456',
      );
      expect(existing.toJson()['id'], 7);
    });

    test('an empty date of birth is sent as null, not an empty string', () {
      const MemberInput member = MemberInput(
        fullName: 'x',
        nationalId: 'y',
        dob: '',
      );
      expect(member.toJson()['dob'], isNull);
    });
  });
}
