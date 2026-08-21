import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import 'refresh.dart';

/// Keeps every figure in the app current, without anyone pressing anything.
///
/// ── WHY THE APP NEEDED THIS ─────────────────────────────────────────────────
/// Every read was fetched once and then cached until something threw it away:
/// pull-to-refresh on that one list, the ⟳ button in the bar, or leaving the
/// screen and coming back. So a treasurer with the dashboard open while somebody
/// else recorded a payment was looking at a figure that had been wrong for ten
/// minutes, with nothing on screen admitting it. The association reported it in
/// exactly those terms: «لا داعي لأن أخرج كل مرة وأرجع».
///
/// ⚠ THE INVALIDATION IS FREE FOR SCREENS NOBODY IS ON. Riverpod discards the
///   cached value and refetches on the next WATCH, so a tick costs one request
///   per provider actually being looked at — usually two or three — and nothing
///   at all for the fourteen that are not.
///
/// ── AND IT ONLY TICKS WHILE THE APP IS IN FRONT ─────────────────────────────
/// A phone in a pocket must not spend the association's free-tier requests. The
/// lifecycle observer stops the clock on pause and takes one refresh on resume —
/// which is also the moment the data is most likely to be stale, so the two
/// halves of that rule are the same rule.
///
/// ── WHAT IT IS NOT ──────────────────────────────────────────────────────────
/// Not Realtime. The app has no websocket — `my_adeel_id()` reads a request
/// header and a socket carries none, so a subscription would deliver a portal
/// member nothing while working perfectly for staff. Polling behaves identically
/// for both accounts, which on this app is worth more than the latency.
///
/// The chat keeps its own faster clock (four seconds, and only while the room is
/// open): a conversation and a balance are not read at the same rhythm.
class AutoRefresh extends ConsumerStatefulWidget {
  const AutoRefresh({required this.child, super.key});

  final Widget child;

  /// How often every cached read is thrown away.
  ///
  /// ⚠ FORTY-FIVE SECONDS IS A JUDGEMENT, NOT A DEFAULT. Faster is more
  ///   requests on a project the association does not pay for, and every one of
  ///   these figures is a subscription ledger rather than a conversation —
  ///   nobody is watching a treasury balance for it to twitch. Slower and the
  ///   complaint that produced this comes back.
  static const Duration interval = Duration(seconds: 45);

  @override
  ConsumerState<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends ConsumerState<AutoRefresh>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(AutoRefresh.interval, (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool front = state == AppLifecycleState.resumed;
    // Coming back is the moment the data is most likely to be old — an hour in
    // a pocket is an hour of other people's payments.
    if (front && !_foreground) _tick();
    _foreground = front;
  }

  void _tick() {
    if (!_foreground || !mounted) return;
    refreshAll(ref);

    // ── ومعها: هل ما زال مفتاحي صالحاً؟ ──────────────────────────────────
    // ⚠ refreshAll DELIBERATELY DOES NOT TOUCH THE SESSION — the router guard
    //   watches authControllerProvider, and a moment of «not signed in yet»
    //   every forty-five seconds would bounce a man off the screen he was
    //   reading. So it is exempt, and it must stay exempt.
    //
    // ⚠ BUT api_me() IS ALSO WHERE `deviceLocked` LIVES, and the association
    //   asked that a reissued key close the app «فوراً». Without this the old
    //   handset goes on showing his dues until he restarts, and the man given
    //   a new key is not the only one holding one.
    //
    //   refreshProfile() re-reads api_me and re-derives the stage from it. It
    //   never signs anybody out and never clears the session, so it is safe on
    //   a timer in a way that invalidating the provider would not be.
    unawaited(ref.read(authControllerProvider.notifier).refreshProfile());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
