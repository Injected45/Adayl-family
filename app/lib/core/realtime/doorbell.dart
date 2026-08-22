import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client_provider.dart';

/// جرس الباب — «حدث شيء»، ولا شيء غير ذلك.
///
/// ── لماذا جرسٌ ولا اشتراكٌ على الجداول ─────────────────────────────────────
/// Polling put a floor under how fast a message could arrive: six-tenths of a
/// second at best, a second and a half after a pause. The association measured
/// it on three handsets and said so — «مافيه تاخير لحظي للرساله، يفترض تكون
/// اسرع بأجزاء من الثانيه».
///
/// The obvious answer is a `postgres_changes` subscription, and it is the one
/// thing this schema cannot use. `my_adeel_id()` reads the **`x-device-id`
/// request header**; a websocket carries no headers; so a row-level
/// subscription evaluated for a portal member matches no policy and delivers
/// him nothing — while working perfectly for staff. A bug that is invisible to
/// whoever tests it.
///
/// ⚠ SO THE BELL CARRIES NOTHING. Not the message, not the sender, not an id.
///   Whoever hears it does the same authenticated REST read the app already
///   does, and **RLS decides everything exactly as it does today**. The
///   websocket is a doorbell; the door is unchanged.
///
/// ⚠ AND THE CHANNEL IS PRIVATE, WHICH IS ONLY POSSIBLE BECAUSE OF WHAT IT DOES
///   NOT CARRY. The device lock answers «which handset?» — worth asking of a
///   man's dues. A doorbell hands over nothing that deserves it, so its policy
///   only has to answer «is this account in the association?», and that is
///   answerable from `auth.uid()` alone. See PATCH_20260822g.
///
/// ⚠ AND IT IS NEVER A DEPENDENCY. Every poll in this app goes on running
///   underneath. A carrier that blocks websockets, a Realtime service never
///   enabled, a ring that is dropped — each costs the speed and nothing else.
///   That is why nothing here retries, reports, or blocks a screen: the app is
///   correct without it and merely faster with it.
enum Ring {
  /// رسالة جديدة في المجلس أو في خيطٍ خاص.
  chat,

  /// مكالمة رُفعت، أو رُدّ عليها، أو أُنهيت.
  call,
}

class Doorbell {
  Doorbell(this._client);

  /// ⚠ A FUNCTION, NOT THE CLIENT, AND THAT IS THE DESIGN RATHER THAN A STYLE.
  ///   Taking the client would mean CONSTRUCTING the bell needs a configured
  ///   Supabase — so `ref.read(doorbellProvider)` inside a poll's `build()`
  ///   would throw «Supabase is not configured» and take the whole room down
  ///   with it. A test caught exactly that.
  ///
  ///   And it is the same principle the rest of this file rests on: the bell is
  ///   an accelerator, never a dependency. Anything that makes the app WORSE
  ///   when the bell is unavailable is wrong, and needing it to exist at all is
  ///   the strongest form of that.
  final SupabaseClient Function() _client;

  /// ⚠ ONE CHANNEL FOR THE WHOLE APP, AND ONE TOPIC. A channel per feature
  ///   would be a websocket subscription per feature — and each needs its own
  ///   policy on `realtime.messages`, which is a schema-wide table. One topic
  ///   with a `kind` inside the payload keeps the security surface at exactly
  ///   one policy pair.
  static const String topic = 'association';

  RealtimeChannel? _channel;
  final Set<void Function(Ring)> _listeners = <void Function(Ring)>{};

  /// Whether the bell is actually connected. Read by nothing that decides
  /// anything — it exists so a failure can be seen rather than guessed at.
  bool connected = false;

  /// ابدأ الاستماع. Safe to call repeatedly.
  void start() {
    if (_channel != null) return;
    try {
      final SupabaseClient db = _client();
      final RealtimeChannel c = db.channel(
        topic,
        opts: const RealtimeChannelConfig(private: true),
      );

      c.onBroadcast(
        event: 'ring',
        callback: (Map<String, dynamic> payload) {
          final Object? kind = payload['kind'];
          final Ring? ring = switch (kind) {
            'chat' => Ring.chat,
            'call' => Ring.call,
            _ => null,
          };
          if (ring == null) return;
          // ⚠ A COPY, BECAUSE A LISTENER MAY REMOVE ITSELF. Iterating the live
          //   set while a provider disposes during the callback throws a
          //   concurrent-modification error inside a websocket handler, where
          //   nothing would ever report it.
          for (final void Function(Ring) l in _listeners.toList()) {
            try {
              l(ring);
            } on Object catch (e) {
              debugPrint('doorbell listener: $e');
            }
          }
        },
      );

      c.subscribe((RealtimeSubscribeStatus status, Object? error) {
        connected = status == RealtimeSubscribeStatus.subscribed;
        if (!connected) debugPrint('doorbell: $status $error');
      });

      _channel = c;
    } on Object catch (e) {
      // The app polls. It always polls.
      debugPrint('doorbell start: $e');
    }
  }

  /// أوقِف — عند الخروج من الحساب.
  ///
  /// ⚠ THE CHANNEL HOLDS THE SESSION'S TOKEN. Leaving it open across a sign-out
  ///   means a socket authenticated as the previous man, on a private channel
  ///   whose policy was evaluated for him.
  Future<void> stop() async {
    connected = false;
    final RealtimeChannel? c = _channel;
    _channel = null;
    if (c == null) return;
    try {
      await _client().removeChannel(c);
    } on Object catch (e) {
      debugPrint('doorbell stop: $e');
    }
  }

  /// اسمع. Returns the way to stop listening.
  VoidCallback listen(void Function(Ring) onRing) {
    _listeners.add(onRing);
    start();
    return () => _listeners.remove(onRing);
  }

  /// دُقّ الجرس — بعد إرسال رسالة، أو رفع مكالمة.
  ///
  /// ⚠ FIRE AND FORGET, AND NEVER AWAITED BY A SCREEN. The write it announces
  ///   has already succeeded; a ring that fails changes nothing except how soon
  ///   the other man finds out, and blocking a send button on a websocket would
  ///   trade a certainty for a nicety.
  void ring(Ring kind) {
    final RealtimeChannel? c = _channel;
    if (c == null || !connected) return;
    unawaited(
      c
          .sendBroadcastMessage(
            event: 'ring',
            payload: <String, dynamic>{'kind': kind.name},
          )
          .then((_) {}, onError: (Object e) => debugPrint('doorbell ring: $e')),
    );
  }
}

/// ⚠ NOT AUTO-DISPOSED. It owns a websocket and a listener set that outlive any
///   one screen — the chat room, the bell and the call poll all hold a
///   subscription to it, and they come and go independently.
final Provider<Doorbell> doorbellProvider = Provider<Doorbell>((Ref ref) {
  // ⚠ read, NOT watch, AND ONLY WHEN THE BELL ACTUALLY RINGS. Watching would
  //   resolve the client the moment this provider is first touched — which is
  //   inside a poll's build(), on a machine that may have no Supabase
  //   configured at all.
  final Doorbell bell = Doorbell(() => ref.read(supabaseClientProvider));
  ref.onDispose(() => unawaited(bell.stop()));
  return bell;
});
