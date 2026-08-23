import 'dart:io';

import 'package:family_app/core/realtime/doorbell.dart';
import 'package:flutter_test/flutter_test.dart';

/// قفلُ الهاتف عند إصدار مفتاحٍ جديد — سرعتُه، لا صلاحيتُه.
///
/// ⚠ THE PERMISSION WAS NEVER SLOW. issue_adeel_code clears
/// profiles.device_id inside its own transaction, and my_adeel_id() returns
/// NULL without a match — so the old handset is refused by the database from
/// that instant, and every read it makes comes back empty.
///
/// What lagged was the phone NOTICING. `deviceLocked` arrives in api_me(), and
/// api_me() was re-read only on AutoRefresh's forty-five-second tick — so a
/// revoked handset went on PAINTING his dues out of its own cache for most of
/// a minute. The association asked for «فوراً», and «فوراً» is measured
/// against the screen, not against what the server already refused.
///
/// ⚠ Ring.access carries no id and no name. Every handset hears «somebody's
///   key changed» and asks api_me() about ITSELF — the same authenticated call
///   the timer would have made, only sooner. Nothing about anyone else leaks,
///   and no policy anywhere changes.
void main() {
  test('the doorbell knows how to say «a key changed»', () {
    expect(Ring.values, contains(Ring.access));
    // ⚠ Three and only three. A fourth kind added without a listener is a ring
    //   nobody answers; one added without a ringer is a listener that never
    //   fires. Both are silent, so the count is asserted rather than assumed.
    expect(
      Ring.values.length,
      3,
      reason:
          'a Ring was added or removed — make sure something rings it AND '
          'something listens for it, then update this count.',
    );
  });

  test('issuing a key rings it, and only AFTER the key is issued', () {
    final String src = File(
      'lib/features/directory/presentation/adeel_detail_screen.dart',
    ).readAsStringSync();

    final int issued = src.indexOf('.issueAdeelCode(adeelId)');
    // ⚠ SEARCH FROM THE ISSUE CALL, NOT FROM THE TOP. «فكّ الارتباط» rings the
    //   same bell for the same reason and sits ABOVE this in the file, so a
    //   bare indexOf found ITS ring and reported the issue path as ringing too
    //   early. The test was measuring the wrong statement, and it would have
    //   gone on passing after the issue ring was deleted.
    final int rung = src.indexOf('ring(Ring.access)', issued);

    expect(issued, greaterThan(-1), reason: 'the issue call is gone');
    expect(
      rung,
      greaterThan(-1),
      reason:
          'issuing a key must ring the doorbell, or the old handset waits for '
          'the forty-five-second tick to find out it was revoked.',
    );
    expect(
      rung,
      greaterThan(issued),
      reason:
          'ringing before the RPC would send every handset to ask a question '
          'whose answer has not changed yet — and would ring on a failure.',
    );
  });

  test('and unlinking an account rings it too', () {
    // Unbinding releases the handset server-side exactly as issuing does — the
    // phone is refused from that instant — so it owes the same speed.
    final String src = File(
      'lib/features/directory/presentation/adeel_detail_screen.dart',
    ).readAsStringSync();

    final int unbound = src.indexOf('.unbindAdeel(adeelId)');
    expect(unbound, greaterThan(-1), reason: 'the unlink call is gone');
    expect(
      src.indexOf('ring(Ring.access)', unbound),
      greaterThan(unbound),
      reason:
          'unlinking must ring the doorbell, or the released handset keeps '
          'painting his dues until the forty-five-second tick.',
    );
  });

  test('and every handset answers it by asking api_me about itself', () {
    final String src = File(
      'lib/core/state/auto_refresh.dart',
    ).readAsStringSync();

    expect(
      src,
      contains('Ring.access'),
      reason:
          'nothing listens for the ring — it would be a bell in an empty '
          'house, and the lock would still take forty-five seconds.',
    );

    // ⚠ refreshProfile(), NEVER refreshAll(). The ring answers one question —
    //   «هل ما زال مفتاحي صالحاً» — and sweeping fourteen providers because
    //   somebody ELSE got a new key is the battery cost this app has refused
    //   all along. It is also the provider that must not be invalidated: the
    //   router guard watches it, and a moment of «not signed in» would bounce
    //   a man off the screen he was reading.
    final int at = src.indexOf('Ring.access');
    final String after = src.substring(at, at + 260);
    expect(
      after,
      contains('refreshProfile()'),
      reason: 'the ring must re-read api_me, which is where deviceLocked lives',
    );
    expect(
      after,
      isNot(contains('refreshAll')),
      reason: 'one question, not a sweep of the whole app',
    );
  });

  test('and the listener is released in dispose, like the other one', () {
    // ⚠ THIS CLOSURE READS `ref`. ConsumerState.read asserts not-disposed, so a
    //   ring arriving after dispose throws — and in this app that once aborted
    //   the rest of dispose() and leaked every timer below it.
    final String src = File(
      'lib/core/state/auto_refresh.dart',
    ).readAsStringSync();
    final int disposed = src.indexOf('void dispose()');
    expect(disposed, greaterThan(-1));
    expect(
      src.substring(disposed),
      contains('_deafen?.call()'),
      reason: 'the doorbell subscription must be released in dispose',
    );
  });
}
