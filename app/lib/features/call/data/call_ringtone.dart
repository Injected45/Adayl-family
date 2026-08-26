import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// صوت الرنين — ما يجعل مكالمةً واردةً تُسمع لا تُرى فقط.
///
/// ⚠ THE ASSOCIATION SAW THE BANNER AND HEARD NOTHING: «تري رنين فقط، لا تسمع
///   اي صوت». The banner was there and the notification was posted, and the
///   notification is where the silence came from — a posted notification plays
///   the CHANNEL's sound, which is a single «ding» lasting a fifth of a second,
///   and on a phone in a pocket during a conversation that is indistinguishable
///   from nothing. A call is not an alert. A call rings until somebody answers.
///
/// ── ولماذا نغمتنا نحن ─────────────────────────────────────────────────────
/// The same reason `message_pop.wav` is ours: this repository is public, and
/// shipping a ringtone belonging to Google or Apple would be redistributing it.
/// `assets/sounds/ringtone.wav` is synthesised — G5 then C6, each with a 6 ms
/// raised-cosine attack and an exponential tail, then a rest, in a two-second
/// loop that is the cadence of a telephone.
///
/// ⚠ IT BEGINS AND ENDS AT DIGITAL SILENCE, deliberately. Looping a clip whose
///   last sample is not zero puts a click at the start of every repeat, and a
///   click is the loudest thing in the file.
class CallRingtone {
  CallRingtone();

  /// ── ⚠ نغمتان، لا واحدة ────────────────────────────────────────────────
  ///
  ///   «ringtone.wav» is what the RECEIVER hears — «somebody is calling you».
  ///   «ringback.wav» is what the CALLER hears while he waits — «طوط طوط»,
  ///   the sound a telephone makes back at you. They are not the same signal
  ///   and must never be the same file: a caller hearing his own ringtone
  ///   cannot tell whether the other man's phone is ringing or his own.
  ///
  /// ⚠ AND THE SILENCE WAS THE COMPLAINT: «عند الاتصال يبقى صامت». A caller
  ///   with no tone has no way to know the call went anywhere at all — the
  ///   screen says «يرنّ» and the earpiece says nothing, and on a Libyan
  ///   connection that is exactly when a man hangs up and tries again.
  ///
  /// ⚠ IT IS OURS, SYNTHESISED, like the other two — 440 Hz + 480 Hz together,
  ///   which is what a telephone ringback IS; one sine alone reads as a
  ///   microwave. 400 ms on, 200 off, 400 on, then two seconds of silence.
  ///   This repository is public and a borrowed tone would be somebody's
  ///   property.
  ///
  /// ⚠ AND IT BEGINS AND ENDS AT DIGITAL SILENCE, with soft edges on each
  ///   burst. A non-zero edge puts a click at the top of every repeat — the
  ///   same rule ringtone.wav is built to, and call_ringtone_test asserts it
  ///   against the BYTES.
  static const String receiverAsset = 'sounds/ringtone.wav';
  static const String callerAsset = 'sounds/ringback.wav';

  /// ⚠ ONE PLAYER, REUSED — the same rule as [ChatChime], for a worse failure.
  ///   A player per ring would leave the previous one looping forever, because
  ///   nothing else holds a reference to stop it. Two calls in a minute and the
  ///   phone rings until it is restarted.
  AudioPlayer? _player;

  bool _ringing = false;

  /// Whether the tone is currently sounding. Read by the tests.
  bool get isRinging => _ringing;

  /// ابدأ الرنين عند المستقبِل. Idempotent — the poll that drives this fires
  /// every second and would otherwise restart the loop from the top each tick,
  /// which sounds like a stutter rather than a ring.
  Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    await play();
  }

  /// وابدأ الرنينَ الراجع عند المتّصل. Same idempotence, same player.
  ///
  /// ⚠ THE SAME SINGLE PLAYER, so the two can never sound together. A handset
  ///   is only ever one end of one call, and holding two loopers would leave
  ///   whichever was not stopped ringing until the app was restarted — the
  ///   failure the one-player rule above exists to prevent.
  Future<void> startRingback() async {
    if (_ringing) return;
    _ringing = true;
    await play(asset: callerAsset);
  }

  /// أوقِف الرنين — عند الرد أو الرفض أو انتهاء المكالمة.
  Future<void> stop() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _player?.stop();
    } on Object catch (e) {
      debugPrint('ringtone stop: $e');
    }
  }

  /// ⚠ VISIBLE, AND OVERRIDDEN IN THE TESTS, for the same reason as
  ///   [ChatChime.play]: sounding a tone needs a platform channel no test
  ///   binding provides, so what is pinned is the DECISION — every branch that
  ///   reaches this line and every branch that must not.
  @visibleForTesting
  Future<void> play({String asset = receiverAsset}) async {
    try {
      final AudioPlayer p = _player ??= AudioPlayer();
      // ⚠ LOOP, and this is the whole difference from the chime. The clip is
      //   two seconds; a call rings for sixty.
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(
        AssetSource(asset),
        volume: 1,
        ctx: AudioContext(
          android: const AudioContextAndroid(
            // ⚠ notificationRingtone, NOT notification. It routes to the RING
            //   volume rather than the notification volume — which is the
            //   slider a man actually raises when he wants to hear his phone,
            //   and the one that stays up when notifications are turned down.
            usageType: AndroidUsageType.notificationRingtone,
            contentType: AndroidContentType.sonification,
            // ⚠ AND IT TAKES FOCUS, unlike the chime. A ring that plays under
            //   music at the same level is a ring nobody hears; `gain` ducks
            //   whatever is playing for as long as the call is ringing, and
            //   hands it back when stop() is called.
            audioFocus: AndroidAudioFocus.gain,
          ),
          // playAndRecord rather than ambient: the microphone is about to be
          // opened for this very call, and switching category mid-answer is
          // what makes the first second of a call silent on iOS.
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playAndRecord,
            options: const <AVAudioSessionOptions>{
              AVAudioSessionOptions.defaultToSpeaker,
            },
          ),
        ),
      );
    } on Object catch (e) {
      // ⚠ A SILENT RING IS NOT AN ERROR THE USER SHOULD SEE. No audio device, a
      //   headset pulled, a test with no platform channel — the banner is still
      //   on screen and the call can still be answered, which is the part that
      //   decides whether he misses it.
      debugPrint('ringtone: $e');
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
    _ringing = false;
  }
}
