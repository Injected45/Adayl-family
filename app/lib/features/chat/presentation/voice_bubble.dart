import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'providers.dart';

/// مقطعٌ صوتيٌّ داخل فقاعة.
///
/// ⚠ THE URL IS FETCHED ON PRESS, NEVER WITH THE MESSAGE. The bucket is
///   private, so playing needs a signed link — and signing every clip in a room
///   as it scrolls past would be forty requests for one a man might listen to.
///   It is also the safer shape: a link that is never created cannot leak.
///
/// ⚠ AND THE SIGNATURE IS STILL SUBJECT TO THE POLICY. Supabase signs only what
///   the caller may read, so a man asking for a clip whose message he cannot
///   see gets a refusal rather than a link. Nothing here decides who may
///   listen; the storage policy does, by asking the message.
class VoiceBubble extends ConsumerStatefulWidget {
  const VoiceBubble({
    required this.path,
    required this.ms,
    required this.tone,
    super.key,
  });

  final String path;
  final int ms;

  /// The bubble's own ink, so the control belongs to the bubble rather than
  /// sitting on it — mine and the room's are different colours.
  final Color tone;

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  AudioPlayer? _player;
  StreamSubscription<void>? _done;
  bool _busy = false;
  bool _playing = false;

  @override
  void dispose() {
    // ⚠ THE SUBSCRIPTION FIRST, THEN THE PLAYER. A completion event arriving
    //   after dispose would call setState on a dead State — the same rule the
    //   chat's own timers follow.
    _done?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_playing) {
      await _player?.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }

    setState(() => _busy = true);
    try {
      final String url = await ref
          .read(chatRepositoryProvider)
          .voiceUrl(widget.path);
      if (!mounted) return;

      final AudioPlayer p = _player ??= AudioPlayer();
      await _done?.cancel();
      _done = p.onPlayerComplete.listen((void _) {
        if (mounted) setState(() => _playing = false);
      });
      await p.play(UrlSource(url));
      if (mounted) setState(() => _playing = true);
    } on Object {
      // ⚠ SILENT, AND DELIBERATELY. A clip that will not play is one row on a
      //   screen full of them; a red banner over the conversation for it would
      //   be louder than the thing itself. The button simply returns to rest.
      if (mounted) setState(() => _playing = false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «٠:٠٧» — a clip is seconds, never hours.
  String get _length {
    final int s = (widget.ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          button: true,
          label: _playing ? l.voiceStop : l.voicePlay,
          child: InkResponse(
            onTap: _toggle,
            radius: 22,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: _busy
                  ? SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: widget.tone,
                      ),
                    )
                  : Icon(
                      _playing
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      size: 26,
                      color: widget.tone,
                    ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Icon(Icons.graphic_eq, size: 16, color: widget.tone),
        const SizedBox(width: AppSpacing.xs),
        Text(
          _length,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: widget.tone,
          ),
        ),
      ],
    );
  }
}
