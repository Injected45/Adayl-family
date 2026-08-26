import 'dart:io';

import 'package:family_app/features/chat/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// دقّةُ الإشعار — ما يقوله، ومتى يُعيد قولَه.
///
/// Two defects, both invisible from inside the app:
///
///   1. THE CONTENT WAS A COUNT. The title was «3» and the body said «لديك
///      رسائل جديدة في مجلس العدايل» for EVERY message — including a private
///      one between two عدايل and a thread with the board. A notification that
///      names the wrong room is worse than a silent one: it is read, believed
///      and acted on.
///
///   2. IT RE-ANNOUNCED ON EVERY REBUILD. `build()` armed the CHIME against
///      the first count («the first count never rings») and never armed the
///      notification, so `_announced` stayed 0 and the next tick posted a
///      fresh alert for messages already announced — a phone re-alerting for
///      yesterday's messages every time the app resumed.
void main() {
  final String bell = File(
    'lib/features/chat/presentation/unread_bell.dart',
  ).readAsStringSync();

  test('⚠ the notification baseline is armed, like the chime', () {
    final int at = bell.indexOf('onCount(first, suppressed: true)');
    expect(at, greaterThan(-1), reason: 'the chime arming is gone');
    expect(
      bell.substring(at, at + 900),
      contains('_announced = first'),
      reason:
          'without this, _announced starts at 0 after every rebuild and the '
          'next tick re-announces messages that were already announced.',
    );
  });

  test('⚠ and the content comes from the message, not from the count', () {
    expect(
      bell,
      contains('newestUnread'),
      reason: 'the alert must name the sender and quote the line',
    );

    // ⚠ AND IT IS ACTUALLY CALLED. The first version of this test only checked
    //   that _announce EXISTED and read its body — so replacing the call site
    //   with the old count-based post left the function sitting unused and the
    //   test green. Proven by making that change: it passed. A guard that
    //   checks a definition and not its use is checking nothing.
    expect(
      bell,
      contains('unawaited(_announce(n))'),
      reason: 'the rise must go through _announce, not post a bare count',
    );
    expect(
      bell,
      isNot(contains('AppNotifier.message(l10nTitle(n)')),
      reason: 'that is the count-as-title alert this replaced',
    );

    final int at = bell.indexOf('Future<void> _announce');
    expect(at, greaterThan(-1));
    final String fn = bell.substring(at, at + 1400);

    expect(fn, contains('m.authorName'), reason: 'who wrote it');
    expect(fn, contains('m.body'), reason: 'what he wrote');
    expect(
      fn,
      contains("m.room == 'hall'"),
      reason:
          'the hall needs its NAME in the title — a message there is from one '
          'of eight men and the room is the context. A private line and a '
          'board thread are already identified by their author.',
    );
  });

  test('⚠ and a failed lookup still posts something', () {
    final int at = bell.indexOf('Future<void> _announce');
    final String fn = bell.substring(at, at + 1400);
    expect(
      fn,
      contains('} on Object {'),
      reason:
          'a vague alert is recoverable; a missing one is not. The generic '
          'text must survive a failed row read.',
    );
  });

  test('an empty body never becomes an empty notification', () {
    // A deleted message arrives with body '' — the view sends '' rather than
    // the text, so nothing in Dart has to hide anything. Posting it would be a
    // blank line on a lock screen.
    final int at = bell.indexOf('Future<void> _announce');
    expect(
      bell.substring(at, at + 1400),
      contains('m.body.trim().isNotEmpty'),
      reason: 'a deleted message must fall back to the generic line',
    );
  });

  test('⚠ the room comes from the server and defaults to the PUBLIC one', () {
    // Inferring the room from threadAdeelId has caused two defects already.
    // And an unknown room must be treated as the hall: labelling a private
    // line as something it is not is the one mistake that cannot be undone.
    final ChatMessage old = ChatMessage.fromJson(<String, dynamic>{
      'id': 1,
      'authorName': 'فلان',
      'body': 'نص',
      'createdAt': '2026-08-23T10:00:00Z',
      'mine': false,
      'fromStaff': false,
      'deleted': false,
      'threadName': '',
    });
    expect(old.room, 'hall');

    for (final String r in <String>['hall', 'board', 'direct']) {
      final ChatMessage m = ChatMessage.fromJson(<String, dynamic>{
        'id': 1,
        'authorName': 'فلان',
        'body': 'نص',
        'createdAt': '2026-08-23T10:00:00Z',
        'mine': false,
        'fromStaff': false,
        'deleted': false,
        'threadName': '',
        'room': r,
      });
      expect(m.room, r);
    }
  });

  test('and the tick itself stays cheap — one capped column, no bodies', () {
    // ⚠ THE WHOLE REASON TWO SECONDS IS AFFORDABLE. The extra row is fetched
    //   on the RISE only; if unreadSince ever starts selecting bodies, the
    //   bell becomes an expensive request running every two seconds.
    final String repo = File(
      'lib/features/chat/data/chat_repository.dart',
    ).readAsStringSync();
    final int at = repo.indexOf('unreadSince');
    expect(at, greaterThan(-1));
    expect(
      repo.substring(at, at + 600),
      contains(".select('id')"),
      reason: 'the bell must not fetch message bodies',
    );
  });
}
