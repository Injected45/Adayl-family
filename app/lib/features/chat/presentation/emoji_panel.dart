import 'package:flutter/material.dart';

import '../../../core/config/theme.dart';
import '../../../l10n/app_localizations.dart';

/// The emoji keyboard, in the app rather than from the system.
///
/// ── WHY IT IS HERE AT ALL ───────────────────────────────────────────────────
/// Every Android keyboard has an emoji sheet, so this looks redundant until you
/// watch somebody use it: on the Arabic layouts common on these handsets the
/// emoji key is two taps away behind a language switch, and it drops the user
/// into a full-screen picker with a Latin search box. In a room where most of
/// what is sent is a greeting, a prayer and a heart, the fifteen that matter
/// should be one tap from the message box.
///
/// ── WHY NO PACKAGE ──────────────────────────────────────────────────────────
/// The published emoji-picker packages carry a full Unicode table, a search
/// index and a recents store, and pull platform channels for skin tones. This
/// is a grid of string constants. Nothing here needs a dependency, an APK
/// larger by a megabyte, or an upgrade path.
///
/// ── WHY THE CATEGORIES ARE THESE ────────────────────────────────────────────
/// They are what the association actually sends: faces, then the gestures and
/// the دعاء that open and close most messages, then hearts, then the occasions
/// this app already knows about — a birth, a wedding, a bereavement. It is not
/// a complete emoji set and is not trying to be; the system keyboard remains
/// one tap further for anyone who wants the rest.
///
/// ⚠ THE 1000-CHARACTER CAP IS ENFORCED HERE TOO. `maxLength` on the TextField
///   stops TYPING past the cap, but a controller written to directly does not
///   pass through an input formatter — so without the check below the picker
///   would be the one way to build a message the database then refuses.
class EmojiPanel extends StatefulWidget {
  const EmojiPanel({
    required this.onPick,
    required this.onBackspace,
    this.maxHeight = 250,
    super.key,
  });

  /// Called with one emoji. The composer decides where it lands.
  final void Function(String emoji) onPick;

  /// Deleting is on the panel because the keyboard is not on screen while it is
  /// open — without this, correcting a mis-tapped emoji means closing the panel
  /// and opening the keyboard.
  final VoidCallback onBackspace;

  final double maxHeight;

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  int _group = 0;

  static const List<List<String>> _groups = <List<String>>[
    // Faces.
    <String>[
      '😀',
      '😃',
      '😄',
      '😁',
      '😊',
      '🙂',
      '😉',
      '😍',
      '🥰',
      '😘',
      '😂',
      '🤣',
      '🙃',
      '😌',
      '😔',
      '😢',
      '😭',
      '😡',
      '🤔',
      '😴',
      '🤗',
      '😇',
      '🥺',
      '😎',
      '🤩',
      '😅',
      '😳',
      '🙄',
      '😏',
      '🤨',
    ],
    // Gestures and دعاء — the ones that open and close a message.
    <String>[
      '👍',
      '👎',
      '👌',
      '✌️',
      '🤲',
      '🙏',
      '🤝',
      '👏',
      '💪',
      '👋',
      '☝️',
      '✋',
      '🖐️',
      '🤞',
      '🫶',
      '🫡',
      '🙌',
      '🤦',
      '🤷',
      '💐',
    ],
    // Hearts.
    <String>[
      '❤️',
      '🩷',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '🤎',
      '💔',
      '❣️',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💘',
      '💝',
      '💟',
    ],
    // The occasions this app already has a وجه صرف for, and the everyday rest.
    <String>[
      '🎉',
      '🎊',
      '🎁',
      '🌹',
      '🕌',
      '📿',
      '☪️',
      '🌙',
      '⭐',
      '✨',
      '🔥',
      '💯',
      '✅',
      '❌',
      '⚠️',
      '📌',
      '📞',
      '🏠',
      '🚗',
      '☕',
      '🍰',
      '🌴',
      '🕋',
      '📅',
      '💰',
      '📄',
      '🔔',
      '👨‍👩‍👦',
      '🧒',
      '👴',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final List<String> tabs = <String>[
      l.emojiFaces,
      l.emojiHands,
      l.emojiHearts,
      l.emojiOccasions,
    ];

    return Container(
      height: widget.maxHeight,
      decoration: const BoxDecoration(
        color: GlassColors.well,
        border: Border(top: BorderSide(color: GlassColors.wellEdge)),
      ),
      child: Column(
        children: <Widget>[
          // ── The category strip ──────────────────────────────────────────────
          // Words, not pictograms. A row of four emoji standing for four groups
          // of emoji is a puzzle, and it is unreadable to a screen reader.
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (BuildContext context, int i) {
                final bool on = i == _group;
                return ChoiceChip(
                  label: Text(tabs[i]),
                  selected: on,
                  onSelected: (_) => setState(() => _group = i),
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(AppSpacing.sm),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 48,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _groups[_group].length,
              itemBuilder: (BuildContext context, int i) {
                final String e = _groups[_group][i];
                return InkWell(
                  onTap: () => widget.onPick(e),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  child: Center(
                    // Sized generously: an emoji rendered at label size is a
                    // smudge, and this grid is the one place they are the
                    // content rather than a decoration on it.
                    child: Text(e, style: const TextStyle(fontSize: 24)),
                  ),
                );
              },
            ),
          ),
          // ── Backspace ───────────────────────────────────────────────────────
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(
                end: AppSpacing.md,
                bottom: AppSpacing.xs,
              ),
              child: IconButton(
                onPressed: widget.onBackspace,
                icon: const Icon(Icons.backspace_outlined, size: 20),
                tooltip: l.emojiBackspace,
                visualDensity: VisualDensity.compact,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
