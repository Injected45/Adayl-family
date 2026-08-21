import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The sound a new message makes when nobody is looking at the room.
///
/// ── لماذا نغمتنا نحن وليست نغمة مسنجر ───────────────────────────────────────
/// The association asked for «نغمة مسنجر الفيسبوك». Meta's audio file is their
/// property; shipping it inside this APK — from a public repository — would be
/// redistributing it. So `assets/sounds/message_pop.wav` is OURS, synthesised
/// to the same shape: a fast attack, an upward pitch glide and a short
/// exponential tail, which is what makes a sound read as a «pop» rather than as
/// a beep. Two hundred milliseconds, mono, normalised to −3 dBFS.
///
/// ── AND IT IS NOT A NOTIFICATION ────────────────────────────────────────────
/// ⚠ NOTHING RINGS WHILE THE APP IS CLOSED, and no amount of work in this file
///   changes that. A background alert needs a push service — a Firebase
///   project, a server key and something server-side to send it — and this app
///   has no server at all. What this is: the app is open, a message arrives,
///   and you are told without having to be looking at the right screen.
class ChatChime {
  ChatChime();

  /// ⚠ ONE PLAYER, REUSED. Constructing an AudioPlayer per message leaks a
  ///   platform-side player on Android and, on a burst of three or four
  ///   messages, plays them on top of each other.
  AudioPlayer? _player;

  /// ⚠ ARMED ONLY AFTER THE FIRST COUNT IS KNOWN.
  ///
  ///   The bell's first read is «how many were waiting before I opened the
  ///   app», which is almost never zero — so a chime on that reading would
  ///   greet every launch with a sound for messages that arrived yesterday.
  ///   The count has to have been seen once before a RISE in it means anything.
  int? _seen;

  /// Call on every count the bell produces. Rings only on a genuine rise.
  ///
  /// [suppressed] is «he is looking at the conversation right now» — WhatsApp's
  /// rule and the association's: «اذا فاتح الرسائل فتصل الرسائل بدون جرس».
  /// The count still advances, so the badge stays truthful; only the sound is
  /// withheld.
  void onCount(int count, {required bool suppressed}) {
    final int? before = _seen;
    _seen = count;

    if (before == null) return;
    if (count <= before) return;
    if (suppressed) return;

    play();
  }

  /// Forget the baseline — after a sign-out, or when the account changes.
  ///
  /// Without it the next account's first count is compared against the previous
  /// one's, and a smaller number would arm the chime at the wrong moment.
  void reset() => _seen = null;

  /// Actually make the sound.
  ///
  /// ⚠ VISIBLE, AND OVERRIDDEN IN THE TESTS. Playing needs a platform channel
  ///   no test binding provides, so the DECISION above is what is pinned —
  ///   every branch that reaches this line and every branch that must not.
  ///   Private, it could not be, and the rules would have gone untested.
  @visibleForTesting
  Future<void> play() async {
    try {
      final AudioPlayer p = _player ??= AudioPlayer();
      // ⚠ NOT `media`. A notification competes with music rather than pausing
      //   it, and it follows the phone's notification volume — including
      //   silent mode, which is a setting the association's members expect to
      //   be obeyed.
      await p.setReleaseMode(ReleaseMode.stop);
      await p.play(
        AssetSource('sounds/message_pop.wav'),
        volume: 0.9,
        ctx: AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.notification,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.none,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
        ),
      );
    } on Object catch (e) {
      // ⚠ A SOUND THAT WILL NOT PLAY IS NOT AN ERROR THE USER SHOULD SEE. No
      //   audio device, a headset pulled mid-play, a test with no platform
      //   channel — the message itself still arrived and the badge still moved,
      //   which is the part that matters.
      debugPrint('chat chime: $e');
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
