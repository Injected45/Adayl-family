import 'package:family_app/features/oversight/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── منصبٌ فارغ يعني اسماً فارغاً ────────────────────────────────────────────
///
/// «في تطبيق الأدمن أضفت أمين الصندوق فقط وتركت المدير المالي فارغاً … عند
/// تحصيل أي مال يظهر اسم المدير المالي الذي كان موجوداً قبل المسح».
///
/// ⚠ THE FAILURE WAS SILENT AND SURVIVED A FULL PURGE, which is what makes it
///   worth a test rather than a fix. The settings screen has NO name field —
///   the name is derived from the chosen عديل — so clearing the post sent
///   `adeelId: null` with the OLD name still attached. `update_settings` does
///   `coalesce(p_patch ->> 'financeName', finance_manager_name)`, and a
///   non-null empty-of-meaning string is not null, so the stale name was
///   written straight back on every save. `v_officials` then offered a man who
///   held no post, on the collection sheet, indefinitely.
///
/// ⚠ AND THE PURGES CANNOT CLEAR IT. Both deliberately leave
///   `association_settings` standing — wiping the association's own name and
///   fee is not what «مسح البيانات» means — so the stale official outlived
///   every reset.
void main() {
  EditableSettings withPosts({int? treasurerId, int? financeId}) =>
      EditableSettings(
        associationName: 'جمعية العدايل',
        currency: 'د.ل',
        memberFee: '20',
        systemStart: '2026-01-01',
        autoClosePreviousMonths: false,
        feeExceptions: const <String, String>{},
        bankName: '',
        bankAccountNo: '',
        bankAccountName: '',
        treasurer: OfficialInput(
          adeelId: treasurerId,
          name: treasurerId == null ? '' : 'أمين الصندوق',
          phone: treasurerId == null ? '' : '091',
        ),
        financeManager: OfficialInput(
          adeelId: financeId,
          name: financeId == null ? '' : 'المدير المالي',
          phone: financeId == null ? '' : '092',
        ),
      );

  test('a filled post sends its id', () {
    final Map<String, dynamic> j = withPosts(
      treasurerId: 3,
      financeId: 5,
    ).toPatch();

    expect(j['treasurerAdeelId'], 3);
    expect(j['financeAdeelId'], 5);
  });

  // ⚠ THE KEY MUST BE PRESENT AND EMPTY, never absent. `update_settings` reads
  //   an ABSENT key as «leave this alone» — which is the same bug in a
  //   different disguise, and the one that let a purged name survive.
  test('⚠ a vacant post sends an EMPTY name, not the old one', () {
    final Map<String, dynamic> j = withPosts(
      treasurerId: 3,
      financeId: null,
    ).toPatch();

    expect(j.containsKey('financeName'), isTrue, reason: 'key was omitted');
    expect(j['financeName'], '');
    expect(j['financePhone'], '');
    expect(j['financeAdeelId'], isNull);

    // And the post that IS filled is untouched by the other one's vacancy.
    expect(j['treasurerAdeelId'], 3);
    expect(j['treasurerName'], 'أمين الصندوق');
  });

  test('...and the same holds for the treasurer', () {
    final Map<String, dynamic> j = withPosts(
      treasurerId: null,
      financeId: 5,
    ).toPatch();

    expect(j['treasurerName'], '');
    expect(j['treasurerPhone'], '');
    expect(j['financeName'], 'المدير المالي');
  });

  test('both vacant clears both', () {
    final Map<String, dynamic> j = withPosts().toPatch();

    expect(j['treasurerName'], '');
    expect(j['financeName'], '');
    expect(j['treasurerAdeelId'], isNull);
    expect(j['financeAdeelId'], isNull);
  });
}
