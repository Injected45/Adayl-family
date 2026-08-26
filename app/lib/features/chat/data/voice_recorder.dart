import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// تسجيلُ مقطعٍ صوتيّ.
///
/// ⚠ SIXTY SECONDS, AND THE SERVER SAYS SO TOO. send_chat_message refuses
///   anything longer, so this cap is a courtesy — it stops a man recording two
///   minutes and being told at the end that it was wasted. The rule that
///   decides is the one in the database, as it is for every other rule here.
///
/// ⚠ AND THE MICROPHONE PERMISSION IS ALREADY ASKED FOR BY CALLS. A refusal
///   arrives as `false` from hasPermission() rather than as an exception, so
///   the screen can say «لا إذن للميكروفون» instead of failing silently — the
///   same distinction CallPhase.micDenied exists to make.
class VoiceRecorder {
  VoiceRecorder();

  static const Duration maxLength = Duration(seconds: 60);

  final AudioRecorder _rec = AudioRecorder();
  DateTime? _startedAt;
  String? _path;

  bool get isRecording => _startedAt != null;

  /// كم مضى من التسجيل.
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// يبدأ. يُرجع false إن رُفض الإذن.
  Future<bool> start() async {
    if (_startedAt != null) return true;
    try {
      if (!await _rec.hasPermission()) return false;

      final Directory dir = await getTemporaryDirectory();
      // ⚠ THE TEMP DIRECTORY, NOT DOCUMENTS. A clip that was never sent is
      //   rubbish, and the platform clears this on its own — a recording
      //   abandoned mid-sentence must not survive on the handset for ever.
      _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        // ⚠ AAC IN AN m4a CONTAINER: the one format Android, iOS and every
        //   browser play without a codec argument, and about 1 KB per second
        //   at this bitrate — a minute is 60 KB, which the free bucket can
        //   carry for years of an association of eight.
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: _path!,
      );
      _startedAt = DateTime.now();
      return true;
    } on Object catch (e) {
      debugPrint('voice start: $e');
      _startedAt = null;
      return false;
    }
  }

  /// يُنهي ويُرجع الملفَّ ومدّتَه، أو null إن لم يُسجَّل شيءٌ يُذكر.
  ///
  /// ⚠ UNDER A SECOND IS NOT A MESSAGE. A press that slipped produces a
  ///   quarter-second of room noise, and sending it wastes a notification on
  ///   everybody in the room. It is discarded here rather than refused later.
  Future<(File, int)?> stop() async {
    if (_startedAt == null) return null;
    final int ms = elapsed.inMilliseconds;
    _startedAt = null;
    try {
      final String? out = await _rec.stop();
      if (out == null) return null;
      final File f = File(out);
      if (ms < 1000 || !f.existsSync()) {
        await _quietlyDelete(f);
        return null;
      }
      return (f, ms.clamp(0, maxLength.inMilliseconds));
    } on Object catch (e) {
      debugPrint('voice stop: $e');
      return null;
    }
  }

  /// يُلغي ويحذف.
  Future<void> cancel() async {
    if (_startedAt == null) return;
    _startedAt = null;
    try {
      final String? out = await _rec.stop();
      if (out != null) await _quietlyDelete(File(out));
    } on Object catch (e) {
      debugPrint('voice cancel: $e');
    }
  }

  Future<void> dispose() async {
    await cancel();
    await _rec.dispose();
  }

  static Future<void> _quietlyDelete(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } on Object {
      // A temp file the platform will clear anyway.
    }
  }
}
