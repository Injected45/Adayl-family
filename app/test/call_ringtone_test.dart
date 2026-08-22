import 'dart:io';
import 'dart:typed_data';

import 'package:family_app/core/notify/background_service.dart';
import 'package:family_app/features/call/data/call_ringtone.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── الرنين: متى يبدأ، ومتى يسكت، وكم مرّة ──────────────────────────────────
///
/// «ايضا اريد صوت رنين عن الاتصال لانه الان لايصدر صوت، تري رنين فقط لا تسمع
///  اي صوت».
///
/// ⚠ WHAT WAS WRONG WAS NOT A MISSING FILE — it was the assumption that a
///   NOTIFICATION rings. A posted notification plays its channel's sound once,
///   for a fraction of a second, and Android may drop even that when the
///   notification carries a full-screen intent, because it expects the screen
///   it takes over to do the ringing. Nothing was doing it. A call is not an
///   alert: it repeats until somebody answers.
///
/// ⚠ THE SOUND ITSELF IS NOT TESTED, and cannot be: sounding a tone needs a
///   platform channel no test binding provides. What is pinned is the DECISION
///   — every branch that reaches a play, and every branch that must not.
class _Spy extends CallRingtone {
  int plays = 0;

  @override
  Future<void> play() async => plays++;
}

void main() {
  group('the decision', () {
    test('starting rings once', () async {
      final _Spy t = _Spy();
      await t.start();
      expect(t.plays, 1);
      expect(t.isRinging, isTrue);
    });

    // ⚠ THE POLL THAT DRIVES THIS FIRES EVERY THREE SECONDS AND SEES THE SAME
    //   RINGING CALL EACH TIME. Restarting the loop on every tick would cut the
    //   tone off two seconds in, forever — a stutter, not a ring. The idempotence
    //   is the feature.
    test('⚠ and starting again while ringing does NOT restart the loop', () async {
      final _Spy t = _Spy();
      await t.start();
      await t.start();
      await t.start();
      expect(t.plays, 1);
    });

    test('stopping silences it, and it can ring again afterwards', () async {
      final _Spy t = _Spy();
      await t.start();
      await t.stop();
      expect(t.isRinging, isFalse);

      await t.start();
      expect(t.plays, 2, reason: 'a second call must ring');
    });

    // Stop is called from the poll on every tick where no call is live, and
    // from the answer and decline buttons. It has to be free to call at any
    // time, including before anything ever rang.
    test('stopping when silent is harmless', () async {
      final _Spy t = _Spy();
      await t.stop();
      await t.stop();
      expect(t.isRinging, isFalse);
      expect(t.plays, 0);
    });
  });

  group('the asset', () {
    // ⚠ THE FILE IS CHECKED, NOT JUST ITS EXISTENCE. This clip is played with
    //   ReleaseMode.loop, so its first and last samples must be digital
    //   silence: a non-zero edge puts a click at the start of every repeat, and
    //   a click is the loudest thing in the file. That is a property of the
    //   BYTES, and nothing else in this project would ever notice it changing.
    test('ringtone.wav is a loopable 16-bit mono WAV that starts and ends silent', () {
      final File f = File('assets/sounds/ringtone.wav');
      expect(f.existsSync(), isTrue, reason: 'the ringtone asset is missing');

      final bytes = f.readAsBytesSync();
      final data = bytes.buffer.asByteData();

      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(22, Endian.little), 1, reason: 'must be mono');
      expect(data.getUint16(34, Endian.little), 16, reason: 'must be 16-bit');

      expect(
        data.getInt16(44, Endian.little),
        0,
        reason: 'first sample must be silence or every loop starts with a click',
      );
      expect(
        data.getInt16(bytes.length - 2, Endian.little).abs(),
        lessThan(64),
        reason: 'last sample must be silence or the loop clicks',
      );
    });

    test('and it carries a real tone, measured as energy not one sample', () {
      final bytes = File('assets/sounds/ringtone.wav').readAsBytesSync();
      final data = bytes.buffer.asByteData();

      // ⚠ RMS OVER A WINDOW, NEVER A SINGLE SAMPLE. Writing this the naive way
      //   the first time reported the tone as silent — any sine crosses zero
      //   twice per cycle, so one sample says nothing at all about whether a
      //   sound is there.
      double rms(double fromSec, double toSec) {
        const int rate = 44100;
        final int a = 44 + (fromSec * rate).round() * 2;
        final int b = 44 + (toSec * rate).round() * 2;
        double sum = 0;
        int n = 0;
        for (int i = a; i < b && i < bytes.length - 1; i += 2) {
          final double v = data.getInt16(i, Endian.little) / 32767;
          sum += v * v;
          n++;
        }
        return n == 0 ? 0 : (sum / n);
      }

      expect(rms(0, 0.28), greaterThan(0.001), reason: 'the first tone is silent');
      expect(rms(0.36, 0.64), greaterThan(0.001), reason: 'the second tone is silent');
      // The rest before the loop repeats — what makes it a ring rather than a
      // continuous buzz.
      expect(rms(0.75, 1.95), lessThan(1e-8), reason: 'the rest is not silent');
    });
  });

  group('the foreground service', () {
    // ⚠ THIS IS THE TEST THAT WOULD HAVE CAUGHT THE WHOLE BUG, and it did not
    //   exist. The app carried both FOREGROUND_SERVICE permissions and the code
    //   that starts the service and a TaskHandler and a permanent-notification
    //   channel — and no <service> element, which flutter_foreground_task does
    //   NOT declare in its own manifest. startService() failed on every call
    //   into a catch that only debugPrints, so the service never ran once and
    //   nothing anywhere said so. Every notification fell back to a Dart Timer
    //   in a backgrounded engine: «مره يصل اشعار مره بتاخر وغير منتظم».
    //
    // ⚠ AND IT IS ASSERTED BY READING THE MANIFEST, like the RTL and
    //   base-table lints, because there is no other way: a missing service is
    //   invisible to the analyzer, invisible to a widget test, and invisible on
    //   screen. It shows up only on a real handset, only in the background, and
    //   only as «sometimes».
    final String manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    test('is declared — the permissions alone start nothing', () {
      expect(
        manifest.contains(
          'com.pravera.flutter_foreground_task.service.ForegroundService',
        ),
        isTrue,
        reason:
            'no <service> element: startService() fails silently and every '
            'background notification falls back to a throttled Dart Timer',
      );
    });

    // ⚠ ANDROID 14+ THROWS AT RUNTIME on a foreground service started with no
    //   declared type — it does not degrade, it takes the app down. The
    //   permission and the type have to agree, and neither implies the other.
    test('carries a service type, and the matching permission', () {
      expect(manifest, contains('android:foregroundServiceType='));
      expect(manifest, contains('FOREGROUND_SERVICE_DATA_SYNC'));
      expect(manifest, contains('android:foregroundServiceType="dataSync"'));
    });

    test('and the notification permission Android 13+ refuses without', () {
      expect(manifest, contains('POST_NOTIFICATIONS'));
    });
  });

  // ⚠ THE HEARTBEAT IS A CLOCK AND NOTHING ELSE, and this pins the arithmetic
  //   rather than the plumbing: a ring lives sixty seconds (v_calls expires
  //   it), so the interval must give several chances at it. One chance is a
  //   missed call whenever a single request fails.
  test('the background heartbeat catches a sixty-second ring several times', () {
    expect(BackgroundService.heartbeat.inSeconds, lessThanOrEqualTo(15));
    expect(
      60 ~/ BackgroundService.heartbeat.inSeconds,
      greaterThanOrEqualTo(4),
      reason: 'too slow to be sure of catching a ring',
    );
    // And not so fast that a phone in a pocket pays for it.
    expect(BackgroundService.heartbeat.inSeconds, greaterThanOrEqualTo(8));
  });
}
