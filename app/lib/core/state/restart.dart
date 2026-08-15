import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Restarts the app from inside itself, without leaving it.
///
/// ── What this actually does, and what it CANNOT do
///
/// It rebuilds the entire widget tree under a fresh key and mounts a NEW
/// [ProviderScope], so every Riverpod provider is disposed and recreated. The
/// effect is what quitting and reopening the app gives you: no cached read, no
/// half-finished form, the router's redirect guard re-run from scratch, and
/// every screen refetched on first build.
///
/// It does NOT reload the app's CODE. The Dart already running is the Dart that
/// keeps running — an app cannot patch itself from inside. A code change still
/// needs hot reload from the host (VS Code's ⚡, or `r` in the `flutter run`
/// console). That is the one thing a button here can never do, and saying so in
/// the UI is better than letting someone press this and wonder why their edit
/// did not appear.
///
/// ── Why this and the refresh button both exist
///
/// [refreshAll] throws away cached DATA and leaves you where you were standing.
/// This throws away EVERYTHING, including the session-scoped state the app holds
/// about who you are and what you were doing. Refresh is the one to reach for
/// nine times out of ten; this is for the tenth — when the app is in a state you
/// no longer trust and you want a clean slate without a rebuild.
class RestartWidget extends StatefulWidget {
  const RestartWidget({required this.child, super.key});

  final Widget child;

  /// Call from anywhere below a [RestartWidget].
  ///
  /// `findAncestorStateOfType` rather than an InheritedWidget on purpose: the
  /// state this reaches is deliberately NOT something a rebuild can depend on.
  /// Nothing should rebuild because the app is restartable; it either is or the
  /// call is a no-op, and a silent no-op is the right failure here — better a
  /// button that does nothing than a crash in the one path someone reaches for
  /// when things are already wrong.
  static void restart(BuildContext context) {
    context.findAncestorStateOfType<_RestartWidgetState>()?._restart();
  }

  @override
  State<RestartWidget> createState() => _RestartWidgetState();
}

class _RestartWidgetState extends State<RestartWidget> {
  Key _key = UniqueKey();

  void _restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) {
    // KeyedSubtree with a new key forces Flutter to discard the old element
    // tree entirely rather than update it in place — which is what makes every
    // State object below run initState again.
    //
    // The ProviderScope is INSIDE the keyed subtree, not outside it. That is the
    // whole point: a scope mounted above the key would survive the rebuild and
    // hand the new tree the same cached providers it had before, which is a
    // repaint dressed up as a restart.
    return KeyedSubtree(
      key: _key,
      child: ProviderScope(child: widget.child),
    );
  }
}
