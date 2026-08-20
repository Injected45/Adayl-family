import 'package:flutter/material.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';

/// The three small things that make the room feel like a room.
///
/// ── THE CONSTRAINT THEY ARE BUILT UNDER ─────────────────────────────────────
/// `test/design_system_test.dart` fails the build on `boxShadow` or ANY gradient
/// inside a screen, and the palette is contrast-tested to WCAG AA — so none of
/// the usual chat decoration is available. What is left is colour, shape,
/// spacing and motion, which is enough: the things below are all four.

/// A speaker's initial in a coloured disc.
///
/// ── WHY IT EARNS ITS SPACE ──────────────────────────────────────────────────
/// A family association's room is thirty men, a dozen of whom share a first
/// name. The author's name is already printed above each run, but a name is
/// read; a colour is RECOGNISED, and recognising who is speaking without reading
/// is the whole difference between scanning a conversation and working through
/// it.
///
/// ⚠ THE COLOUR IS DERIVED FROM THE NAME, NOT ASSIGNED. There is nowhere to
///   store an assignment — the room is a table of messages, and the author is a
///   snapshot string on the row — so it is a hash. That makes it STABLE across
///   devices and across restarts without a single byte of state, which is what a
///   recognition cue has to be: a colour that changed between sessions would be
///   worse than no colour.
///
/// ⚠ AND IT IS NEVER THE ONLY SIGNAL. The name sits beside it and the staff
///   badge beside that. Nobody has to distinguish six hues to use this screen.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({required this.name, this.size = 30, super.key});

  final String name;
  final double size;

  /// Six accents from the tested palette. Not arbitrary colours: each is already
  /// paired with [AppColors.onFill] elsewhere in the app, so the letter on top
  /// is legible without a second contrast check.
  static const List<Color> _tones = <Color>[
    AppColors.brand,
    AppColors.success,
    AppColors.info,
    AppColors.warning,
    AppColors.danger,
    AppColors.brandDeep,
  ];

  static Color toneFor(String name) {
    // A plain sum of code units. It needs to be stable and spread, not
    // cryptographic, and a name is a handful of characters.
    int h = 0;
    for (final int c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _tones[h % _tones.length];
  }

  /// The first letter of the first word that HAS one.
  ///
  /// Arabic names arrive with the odd leading space or a stray «ال», and a blank
  /// disc reads as a rendering fault. Falling back to a dash keeps it a disc.
  static String initialFor(String name) {
    for (final String part in name.trim().split(RegExp(r'\s+'))) {
      if (part.isNotEmpty) return part.characters.first;
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final Color tone = toneFor(name);

    return Semantics(
      label: name,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        child: Text(
          initialFor(name),
          style: TextStyle(
            fontSize: size * 0.44,
            fontWeight: FontWeight.w900,
            color: AppColors.onFill,
            // The disc is small and a tall Arabic letter would sit off centre
            // without this.
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Is this message nothing but emoji?
///
/// A bare «🙏» or «❤️❤️❤️» is a gesture, not a sentence, and every chat people
/// already use renders it large and without a bubble. Doing the same here costs
/// one predicate and is the single most-noticed thing on this screen.
///
/// ⚠ THE CAP OF THREE IS THE POINT. Without it a member pastes forty hearts and
///   they render at 40pt each, which is a page of the room gone. Above the cap
///   it is an ordinary message in an ordinary bubble.
bool isEmojiOnly(String body) {
  final String s = body.trim();
  if (s.isEmpty) return false;

  int glyphs = 0;
  for (final String ch in s.characters) {
    if (ch.trim().isEmpty) continue;
    if (!_looksEmoji(ch)) return false;
    glyphs++;
    if (glyphs > 3) return false;
  }
  return glyphs > 0;
}

/// Deliberately generous rather than exact. A full Unicode emoji property table
/// is thousands of ranges and a dependency; what this has to get right is «is
/// this a picture rather than a letter», and a false NEGATIVE simply renders a
/// normal bubble — the failure is invisible either way.
bool _looksEmoji(String ch) {
  final int r = ch.runes.first;
  return (r >= 0x1F300 && r <= 0x1FAFF) || // pictographs, faces, symbols
      (r >= 0x2600 && r <= 0x27BF) || //     miscellaneous and dingbats
      (r >= 0x1F000 && r <= 0x1F0FF) || //   tiles and cards
      r == 0x2764 || //                      ❤ on its own plane
      (r >= 0xFE00 && r <= 0xFE0F) || //     variation selectors
      (r >= 0x1F1E6 && r <= 0x1F1FF); //     regional indicators
}

/// A message arriving, rather than appearing.
///
/// The room polls every four seconds, so without this a message does not slide
/// in — it is simply there on the next frame, which reads as a redraw rather
/// than as someone speaking. A short fade and a few pixels of rise is the whole
/// effect.
///
/// ⚠ ONLY ON ARRIVAL, never on scroll. It is keyed on the message id by the
///   caller, so a bubble scrolling back into view is not re-animated — a list
///   that re-animates on scroll is the thing that makes chat apps feel cheap.
///
/// ⚠ AND IT OBEYS «تقليل الحركة». `prefersReducedMotion` collapses the duration
///   to zero rather than skipping the widget: the END STATE must be identical
///   either way, and a branch that returns a different tree is how those two
///   drift apart.
class ChatEntrance extends StatefulWidget {
  const ChatEntrance({required this.child, super.key});

  final Widget child;

  @override
  State<ChatEntrance> createState() => _ChatEntranceState();
}

class _ChatEntranceState extends State<ChatEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.fast,
  );

  @override
  void initState() {
    super.initState();
    // Started after the first frame so the duration can be read from a context
    // that exists. At zero duration the controller completes immediately and
    // nothing is ever seen mid-flight.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.duration = prefersReducedMotion(context)
          ? Duration.zero
          : AppMotion.fast;
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Animation<double> t = CurvedAnimation(
      parent: _c,
      curve: Curves.easeOutCubic,
    );

    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        builder: (BuildContext context, Widget? child) => Transform.translate(
          // Upward, because that is the direction a new message travels into a
          // list that is pinned to the bottom.
          offset: Offset(0, 8 * (1 - t.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
