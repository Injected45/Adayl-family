import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ── شكل إشعار المكالمة: لافتةٌ، لا شاشةٌ تبتلع الجهاز ──────────────────────
///
/// The association's first real three-handset test produced one visual
/// complaint and it was not in any widget: «الاسم يظهر بشكل كبير جدا اريدك ان
/// ترجع الحجم والشكل بشكل جميل مثل واتساب».
///
/// The cause was `fullScreenIntent: true` on the call notification. With
/// USE_FULL_SCREEN_INTENT granted and no full-screen Activity of ours for
/// Android to launch, the platform inflates the NOTIFICATION at full size — so
/// the caller's name became a display headline. And it was suppressing the
/// channel's sound at the same time, because Android expects the screen it
/// takes over to do the ringing.
///
/// ⚠ WHY A SOURCE SCAN. Nothing in a Flutter test can observe how Android
///   renders a notification — there is no notification in a test binding at
///   all. The decision is the thing worth pinning, exactly as
///   `two_doors_test` pins `devLoginEnabled` and `month_colour_test` pins the
///   colour of a month: read the file, and fail naming the line.
///
/// ⚠ AND THE MANIFEST IS HALF OF IT. Re-adding the flag alone would do nothing
///   on Android 14 without the permission, and re-adding the permission alone
///   would do nothing without the flag — so a future change that brought back
///   the symptom would have to touch both, and this test watches both.
void main() {
  test('⚠ the call notification asks for no full-screen takeover', () {
    final String src = File('lib/core/notify/notifier.dart').readAsStringSync();

    final List<String> offenders = <String>[];
    final List<String> lines = src.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      // The comment explaining the removal names the flag; the code must not.
      if (line.trimLeft().startsWith('//')) continue;
      if (line.contains('fullScreenIntent')) {
        offenders.add('notifier.dart:${i + 1}  ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'fullScreenIntent makes Android draw the notification at full screen '
          'when no full-screen Activity exists — the caller name fills the '
          'display — and it suppresses the channel sound. The in-app banner '
          'covers the foreground; a heads-up covers the rest:\n  '
          '${offenders.join('\n  ')}',
    );
  });

  test('and the manifest no longer claims the permission for it', () {
    final String man = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      RegExp(r'<uses-permission[^>]*USE_FULL_SCREEN_INTENT').hasMatch(man),
      isFalse,
      reason:
          'USE_FULL_SCREEN_INTENT is what lets Android honour the flag above. '
          'It is dropped deliberately — a permission asked for and never '
          'exercised is a claim the app does not honour.',
    );
  });

  test(
    'but a call still outranks a message, which is why there are two channels',
    () {
      // The fix must not have flattened the distinction it sits inside. A call
      // is Importance.max so it heads up; a message is not.
      final String src = File(
        'lib/core/notify/notifier.dart',
      ).readAsStringSync();
      final int call = src.indexOf('_callChannel');
      final int chat = src.indexOf('_chatChannel');
      expect(call, greaterThan(-1));
      expect(chat, greaterThan(call), reason: 'both channels still declared');

      final String callBlock = src.substring(call, chat);
      expect(
        callBlock,
        contains('Importance.max'),
        reason: 'a call must still be able to interrupt',
      );
      expect(
        callBlock,
        contains('AndroidNotificationCategory.call'),
        reason: 'the category is what makes Android treat it as a call at all',
      );
    },
  );
}
