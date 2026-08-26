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

  /// آخرُ ملفٍّ طُلب — فالنغمتان ليستا واحدة.
  ///
  /// ⚠ THE CALLER AND THE RECEIVER HEAR DIFFERENT SOUNDS, and a spy that only
  ///   counted plays could not tell them apart — which is exactly the mistake
  ///   worth guarding: a caller hearing his own ringtone cannot tell whether
  ///   the other phone is ringing or his own.
  String? lastAsset;

  @override
  Future<void> play({String asset = CallRingtone.receiverAsset}) async {
    plays++;
    lastAsset = asset;
  }
}

void main() {
  _ringbackTests();

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
    test(
      '⚠ and starting again while ringing does NOT restart the loop',
      () async {
        final _Spy t = _Spy();
        await t.start();
        await t.start();
        await t.start();
        expect(t.plays, 1);
      },
    );

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
    test(
      'ringtone.wav is a loopable 16-bit mono WAV that starts and ends silent',
      () {
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
          reason:
              'first sample must be silence or every loop starts with a click',
        );
        expect(
          data.getInt16(bytes.length - 2, Endian.little).abs(),
          lessThan(64),
          reason: 'last sample must be silence or the loop clicks',
        );
      },
    );

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

      expect(
        rms(0, 0.28),
        greaterThan(0.001),
        reason: 'the first tone is silent',
      );
      expect(
        rms(0.36, 0.64),
        greaterThan(0.001),
        reason: 'the second tone is silent',
      );
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
  //
  // ⚠ THE FLOOR WAS EIGHT SECONDS AND IT WAS LOWERED DELIBERATELY, on evidence
  //   rather than preference. «Several chances» answers «did he MISS the call»;
  //   the association asked a different question — «هل ظهر الرنين بمجرد الرنّ»
  //   — and their own call log answered it: 24 seconds to one answer, 73 to
  //   another. In the background this beat IS the clock, so ten seconds was
  //   the floor those numbers were built on.
  //
  // ⚠ AND THE BATTERY ARGUMENT IS NOT DISMISSED, IT IS PRICED. The beat sends
  //   one word to the main isolate, which then makes two capped, body-less
  //   requests. refreshAll is deliberately not called there. Three seconds
  //   would be a poll disguised as a heartbeat; three is the floor now, and
  //   anything under it should be argued for in a comment like this one.
  test(
    'the background heartbeat catches a sixty-second ring several times',
    () {
      expect(BackgroundService.heartbeat.inSeconds, lessThanOrEqualTo(15));
      expect(
        60 ~/ BackgroundService.heartbeat.inSeconds,
        greaterThanOrEqualTo(4),
        reason: 'too slow to be sure of catching a ring',
      );
      // And not so fast that a phone in a pocket pays for it.
      expect(BackgroundService.heartbeat.inSeconds, greaterThanOrEqualTo(3));
    },
  );
}

/// نغمتان لا واحدة: ما يسمعه المتّصل، وما يسمعه المستقبِل.
///
/// ⚠ «عند الاتصال يبقى صامت». A caller with no tone cannot tell whether the
///   call went anywhere at all — the screen says «يرنّ» and the earpiece says
///   nothing, which is exactly when a man hangs up and tries again.
///
/// ⚠ AND THEY MUST NOT BE THE SAME FILE. A caller hearing his own ringtone
///   cannot tell whether the other man's phone is ringing or his own.
void _ringbackTests() {
  test('⚠ the caller and the receiver hear different files', () {
    expect(
      CallRingtone.callerAsset,
      isNot(CallRingtone.receiverAsset),
      reason: 'one signal for two opposite meanings is no signal',
    );
  });

  test('starting a ringback plays the CALLER file, and once', () async {
    final _Spy t = _Spy();
    await t.startRingback();
    expect(t.plays, 1);
    expect(t.lastAsset, CallRingtone.callerAsset);

    // ⚠ IDEMPOTENT, like start(). The phase listener fires on every change and
    //   would otherwise restart the loop from the top — a stutter, not a ring.
    await t.startRingback();
    expect(t.plays, 1);
  });

  test('and the receiver tone is still the default', () async {
    final _Spy t = _Spy();
    await t.start();
    expect(t.lastAsset, CallRingtone.receiverAsset);
  });

  test('⚠ and one player, so the two can never sound together', () async {
    // A handset is only ever one end of one call. Holding two loopers would
    // leave whichever was not stopped ringing until the app was restarted.
    final _Spy t = _Spy();
    await t.startRingback();
    await t.start();
    expect(t.plays, 1, reason: 'the second must be refused while one is live');
    await t.stop();
    await t.start();
    expect(t.plays, 2, reason: 'and allowed once the first has stopped');
  });

  test('⚠ the ringback file exists, and begins and ends at silence', () {
    // The same rule ringtone.wav is built to: a non-zero edge puts a click at
    // the top of every repeat, and this clip repeats every three seconds.
    final File f = File('assets/sounds/ringback.wav');
    expect(f.existsSync(), isTrue, reason: 'the caller has no tone at all');

    final Uint8List b = f.readAsBytesSync();
    expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE');

    final ByteData d = ByteData.sublistView(b);
    expect(d.getInt16(44, Endian.little), 0, reason: 'starts on a click');
    expect(
      d.getInt16(b.length - 2, Endian.little),
      0,
      reason: 'ends on a click, heard at every repeat',
    );
  });

  test('⚠ the call teardown always runs, whatever throws', () {
    // ── THE WORST FAILURE THIS FILE GUARDS ─────────────────────────────────
    //
    //   activeCallProvider is set on the FIRST line of _open, and the banner
    //   hides while it is non-null — that is how a man is stopped from being
    //   offered a call he is already on. So anything throwing between that line
    //   and the cleanup leaves the provider holding a dead session, and THAT
    //   HANDSET NEVER SHOWS AN INCOMING CALL AGAIN — not this call, any call,
    //   until the app is restarted.
    //
    //   The window is real and it GREW with the ringback: a modal route, a
    //   WebRTC teardown, a platform-channel audio stop, a listener and a
    //   provider read. One of those throwing is not a hypothesis.
    final String src = File(
      'lib/features/call/presentation/call_ui.dart',
    ).readAsStringSync();

    final int at = src.indexOf('Future<void> _open(');
    expect(at, greaterThan(-1));
    final String fn = src.substring(at, (at + 6000).clamp(0, src.length));

    expect(
      fn,
      contains('} finally {'),
      reason: 'the cleanup must run on every path out of _open',
    );
    final int fin = fn.indexOf('} finally {');
    final String cleanup = fn.substring(fin);
    expect(cleanup, contains('activeCallProvider.notifier).state = null'));
    expect(cleanup, contains('session.dispose()'));
    expect(cleanup, contains('removeListener(followPhase)'));
  });

  test('⚠ and the RECEIVER never hears a ringback', () {
    // open() sets the phase to «ringing» on BOTH handsets — it means «I have my
    // seat and the call is not connected yet», which is true of the man who
    // answered too. A telephone ringback under the button he just pressed is
    // the sound of a call that has NOT been answered.
    final String src = File(
      'lib/features/call/presentation/call_ui.dart',
    ).readAsStringSync();

    expect(src, contains('bool ringback = false'));
    expect(
      src,
      contains('if (ringback && session.phase.value == CallPhase.ringing)'),
      reason: 'the tone must be gated on WHO raised the call',
    );
    // And exactly one caller opts in: the man who raised it.
    expect(
      'ringback: true'.allMatches(src).length,
      1,
      reason: 'answerCall must never pass it',
    );
  });

  test('and the caller hears it only while the call is RINGING', () {
    final String src = File(
      'lib/features/call/presentation/call_ui.dart',
    ).readAsStringSync();

    expect(src, contains('startRingback()'));
    // ⚠ ON THE PHASE, NOT A TIMER. The session owns the truth about when a call
    //   stops ringing — an answer, a refusal, an expiry, a hang-up all end it —
    //   so a listener on `phase` can never disagree with the screen.
    expect(
      src,
      contains('session.phase.addListener'),
      reason: 'a separate clock would eventually ring into a live conversation',
    );
    // ⚠ THE RINGBACK'S OWN LISTENER, NOT «a removeListener somewhere». The
    //   sheet releases one too — «widget.session.phase.removeListener(_onPhase)»
    //   — and a bare match on the method name found THAT and passed while the
    //   ringback's listener was deleted. Proven by deleting it: the test stayed
    //   green. The callback's NAME is what makes the assertion specific.
    expect(
      src,
      contains('session.phase.removeListener(followPhase)'),
      reason:
          'session.dispose() disposes phase; a listener left on it is the leak '
          'this codebase has paid for before — and the tone would loop with '
          'nothing holding a reference to stop it',
    );
    expect(
      src,
      contains('session.phase.addListener(followPhase)'),
      reason: 'and it must be the same callback that was attached',
    );
  });
}
