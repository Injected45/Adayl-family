import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الغرفةُ تُقال، لا تُستنتج.
///
/// ⚠ REPORTED: «عندما أرسل محادثة من عديل إلى عديل فإن الرسالة تظهر أيضاً في
///   المحادثة العامة». Run against the app's own role, RLS held — a THIRD
///   member's hall query returned zero of the private message. What was real
///   is narrower and still fatal to the promise: the two PARTICIPANTS saw
///   their own private line inside المجلس, because the client asked for the
///   hall with «threadAdeelId IS NULL» and a direct message has that NULL too.
///
/// ⚠ SECOND TIME THIS AMBIGUITY HAS BITTEN. PATCH_20260823a tightened the READ
///   POLICY to «peer_a IS NULL» for the same reason; every other reader of
///   that column kept the old assumption. Hence `room`, and hence this file.
void main() {
  final String repo = File(
    'lib/features/chat/data/chat_repository.dart',
  ).readAsStringSync();

  test('⚠ no chat query decides a room from threadAdeelId being null', () {
    // ⚠ THE LEADING DOT MATTERS. The note above the fixed method quotes the
    //   old call to explain what went wrong; the CALL is «.isFilter(...)» on
    //   a builder, the prose is not. A bare match failed on documentation
    //   doing its job, which is a test complaining about the wrong thing.
    expect(
      repo,
      isNot(contains(".isFilter('threadAdeelId', null)")),
      reason:
          'a direct message ALSO has threadAdeelId null, so this filter cannot'
          ' tell the hall from a private line. Filter on room.',
    );
  });

  test('the hall, the board and the direct thread each name their room', () {
    expect(repo, contains("eq('room', 'hall')"));
    expect(repo, contains("eq('room', 'board')"));
    expect(repo, contains("eq('room', 'direct')"));
  });

  test('⚠ and the hall UNREAD COUNT names it too', () {
    // The badge had the same bug: a private conversation put a number on the
    // public room, which is the same lie in a smaller place.
    final int at = repo.indexOf('unreadInHall');
    expect(at, greaterThan(-1), reason: 'the hall counter is gone');
    expect(
      repo.substring(at, (at + 700).clamp(0, repo.length)),
      contains("eq('room', 'hall')"),
      reason: 'the hall badge must count the hall and nothing else',
    );
  });

  test('and a direct read is scoped by room AND by the pair', () {
    // ⚠ BOTH. The pair test alone matched every direct thread this man is in —
    // RLS then narrows it to his own, so it worked; but the room test is what
    // keeps a hall message with a null peer out of the intersection.
    final int at = repo.indexOf('directMessages');
    expect(at, greaterThan(-1));
    final String block = repo.substring(at, at + 900);
    expect(block, contains("eq('room', 'direct')"));
    expect(block, contains('peerA.eq.'));
  });

  test('⚠ the view actually carries the room, and decides direct FIRST', () {
    final String sql = File(
      '../supabase/PATCH_20260823f_chat_room.sql',
    ).readAsStringSync();

    final int at = sql.indexOf('CASE WHEN m.peer_a IS NOT NULL');
    expect(
      at,
      greaterThan(-1),
      reason:
          'the room must be decided on peer_a BEFORE thread_adeel_id — a '
          'direct message has thread_adeel_id null, so asking about the hall '
          'first rebuilds the bug inside the fix.',
    );
    final String block = sql.substring(at, at + 300);
    expect(block.indexOf("'direct'"), lessThan(block.indexOf("'hall'")));
  });
}
