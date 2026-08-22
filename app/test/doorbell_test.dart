import 'dart:io';

import 'package:family_app/core/realtime/doorbell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── جرس الباب: ما يحمله، ومن يسمعه، وماذا يحدث إن سقط ─────────────────────
///
/// «مافيه تاخير لحظي للرساله، يفترض تكون اسرع بأجزاء من الثانيه». Polling put a
/// floor under that — six-tenths of a second at best — and the bell is what
/// goes under it.
///
/// ⚠ THE WEBSOCKET ITSELF IS NOT TESTED, and cannot be: it needs a configured
///   Supabase, a network and a server. What is pinned is everything AROUND it —
///   and every one of these is a way the bell could quietly make the app worse
///   rather than faster, which is the only kind of failure it is allowed to
///   have.
void main() {
  // ⚠ THE ONE PROPERTY THE WHOLE DESIGN RESTS ON. If constructing or using the
  //   bell can throw, then every poll that touches it inherits the failure —
  //   and the room, the badge and the call banner all touch it. A test caught
  //   exactly this: `Doorbell(client)` resolved Supabase at construction, and
  //   `ChatController.build()` died with «Supabase is not configured».
  group('it can never make the app worse', () {
    test('constructing it resolves nothing', () {
      // No Supabase in a test binding — and this must still not throw.
      expect(
        () => Doorbell(() => throw StateError('Supabase is not configured')),
        returnsNormally,
      );
    });

    test('⚠ and listening on an unusable client does not throw either', () {
      final Doorbell bell = Doorbell(
        () => throw StateError('Supabase is not configured'),
      );
      late final VoidCallback deafen;
      expect(() => deafen = bell.listen((Ring _) {}), returnsNormally);
      expect(bell.connected, isFalse, reason: 'it must not claim to be up');
      expect(deafen, returnsNormally);
    });

    test('⚠ ringing while disconnected is silent, not an error', () {
      final Doorbell bell = Doorbell(
        () => throw StateError('Supabase is not configured'),
      );
      // The message has already been saved by the time this is called. A throw
      // here would surface as a failed SEND to the one man who must never
      // wonder whether his message went.
      expect(() => bell.ring(Ring.chat), returnsNormally);
      expect(() => bell.ring(Ring.call), returnsNormally);
    });

    test('and stopping one that never started is harmless', () async {
      final Doorbell bell = Doorbell(
        () => throw StateError('Supabase is not configured'),
      );
      await expectLater(bell.stop(), completes);
      expect(bell.connected, isFalse);
    });
  });

  group('the shape of the ring', () {
    // ⚠ THE KIND IS ALL IT CARRIES, AND THAT IS THE SECURITY ARGUMENT, not a
    //   convenience. No message text, no sender, no id — so a listener learns
    //   only «ask now», and every read that follows goes through RLS exactly as
    //   it does today. If a payload ever grows a field, the private channel
    //   stops being sufficient and this test is where that decision surfaces.
    test('there are exactly two kinds, and both are bare words', () {
      expect(Ring.values, <Ring>[Ring.chat, Ring.call]);
      expect(Ring.chat.name, 'chat');
      expect(Ring.call.name, 'call');
    });

    // ⚠ ONE TOPIC, AND THE POLICY IS WRITTEN AGAINST THIS EXACT STRING.
    //   PATCH_20260822g scopes both policies to `realtime.topic() =
    //   'association'` — a topic added here without a policy would be a
    //   private channel nobody can join, which presents as «Realtime does not
    //   work» rather than as a missing policy.
    test('⚠ one topic, and it matches the policy in PATCH_20260822g', () {
      expect(Doorbell.topic, 'association');
    });
  });

  group('listeners', () {
    test('a listener stops hearing once it deafens', () {
      final Doorbell bell = Doorbell(() => throw StateError('no client'));
      int heard = 0;
      final VoidCallback deafen = bell.listen((Ring _) => heard++);
      deafen();
      // Nothing can deliver a ring without a socket, so what is asserted here
      // is that removing is accepted and idempotent — the leak this prevents is
      // a provider's callback outliving the provider, holding a dead `ref`.
      expect(deafen, returnsNormally);
      expect(heard, 0);
    });
  });

  // ⚠ AND NO `eventsPerSecond`, WHICH IS A CORRECTION RATHER THAN A TIDY-UP.
  //   It sat in the client options as 1, reading like a rate limit; it was
  //   raised to 10 with a paragraph explaining that 1 would have capped the
  //   bell at one ring a second — and that explanation was WRONG. In this
  //   client the field is read by nothing at all: deprecated with «client side
  //   rate limit has been removed, this option will be ignored», and absent
  //   from every other file in the package.
  //
  //   Pinned by reading the SOURCE, because the mistake was believing a comment
  //   over the code, and a test asserting a value would repeat it.
  test('⚠ the inert throttle is gone from the client options', () {
    final String src = File(
      'lib/core/supabase/supabase_client_provider.dart',
    ).readAsStringSync();
    final int at = src.indexOf('realtimeClientOptions:');
    expect(
      at == -1 || !src.substring(at, at + 200).contains('eventsPerSecond:'),
      isTrue,
      reason:
          'eventsPerSecond is ignored by this client — a number here implies a '
          'control that does not exist, and sends the next reader hunting a '
          'dropped ring in the wrong place',
    );
  });
}
