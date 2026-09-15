import 'dart:async';

import 'package:flutter/widgets.dart';

/// A page that goes back by itself when it is left untouched.
///
/// «يرجع كما كان بعدة فتره 30 ثانية اذا ترك ساكن. او ارجاعه فورا». Wraps the
/// page a notice or a proposal opens into — one clock, so the two cannot drift
/// into two different ideas of «ساكن».
///
/// [idleFor] counts from the last TOUCH — a tap anywhere, or a scroll of a
/// long text — so a reader moving through what he is reading is never closed
/// on. Closing at once is the page's own button; this only handles the wait.
///
/// ⚠ ONLY WHILE IT IS THE PAGE IN FRONT. If anything was opened above it — a
///   confirmation dialog, a newer notice — the count starts again rather than
///   popping whatever is on top, which would close the wrong thing.
///
/// ⚠ TRANSLUCENT, so a touch is counted AND still reaches the button beneath
///   it. An opaque listener would swallow «رجوع».
class IdleAutoClose extends StatefulWidget {
  const IdleAutoClose({required this.idleFor, required this.child, super.key});

  final Duration idleFor;
  final Widget child;

  @override
  State<IdleAutoClose> createState() => _IdleAutoCloseState();
}

class _IdleAutoCloseState extends State<IdleAutoClose> {
  Timer? _idle;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _idle?.cancel();
    super.dispose();
  }

  void _arm() {
    _idle?.cancel();
    _idle = Timer(widget.idleFor, _timeUp);
  }

  void _timeUp() {
    if (!mounted) return;
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _arm();
      return;
    }
    unawaited(Navigator.of(context).maybePop());
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _arm(),
    child: NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification _) {
        _arm();
        return false;
      },
      child: widget.child,
    ),
  );
}
