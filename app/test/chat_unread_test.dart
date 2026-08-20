import 'package:family_app/features/chat/data/chat_read_state.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// How far this handset has read the room.
///
/// ── WHY THE MARK IS ON THE DEVICE ───────────────────────────────────────────
/// The obvious shape is a `chat_reads` table, and it is the wrong trade: a third
/// patch on a live project inside one week, for a fact that is not association
/// data. No figure depends on it and losing it costs one badge showing zero.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues(<String, String>{});

  const ChatReadState reads = ChatReadState(FlutterSecureStorage());

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  _threadMarkTests();
  _independentRoomsTests();

  test('a fresh install has read nothing, and that is not the same as all', () {
    // ⚠ ZERO MEANS "EVERYTHING IS NEW". Seeding it to the newest id instead
    //   would silently mark as read a hundred messages nobody has opened — and
    //   a new member would arrive to a room that says there is nothing waiting.
    expectLater(reads.lastRead(), completion(0));
  });

  test('the mark is remembered', () async {
    await reads.markRead(42);
    expect(await reads.lastRead(), 42);
  });

  test('⚠ and it NEVER moves backwards', () async {
    // The mark is written from two places — the room as it is read, and the
    // screen on its way out. An older value arriving late would resurrect
    // messages the man has already read, and the bell would ring at him for a
    // conversation he finished.
    await reads.markRead(42);
    await reads.markRead(7);
    expect(await reads.lastRead(), 42);
  });

  test('a zero or negative id writes nothing', () async {
    // An empty room reports newest = 0. Writing it would be harmless today and
    // would become a silent reset the first time the id ever arrives unset.
    await reads.markRead(42);
    await reads.markRead(0);
    await reads.markRead(-1);
    expect(await reads.lastRead(), 42);
  });
}

/// The per-conversation mark, which answers a different question.
///
/// The bell says «هل هناك جديد» across the whole association. The inbox says
/// «من منهم ينتظر». One global number cannot answer the second, so there are two
/// marks — written at different moments, and neither derivable from the other.
void _threadMarkTests() {
  const ChatReadState reads = ChatReadState(FlutterSecureStorage());

  test('nothing read means every conversation is waiting', () async {
    expect(await reads.threadMarks(), isEmpty);
  });

  test('each conversation carries its own mark', () async {
    await reads.markThreadRead(6, 40);
    await reads.markThreadRead(9, 12);

    final Map<int, int> marks = await reads.threadMarks();
    expect(marks[6], 40);
    expect(marks[9], 12);
  });

  test('⚠ and one NEVER moves backwards, thread by thread', () async {
    // Written from two places — the thread screen as it renders, and the inbox
    // as it is opened. An older value arriving late would make a conversation
    // the board has just read look unanswered again.
    await reads.markThreadRead(6, 40);
    await reads.markThreadRead(6, 5);
    expect((await reads.threadMarks())[6], 40);
  });

  test('a corrupt map reads as "nothing read", never as a crash', () async {
    // It shows every conversation as waiting — visibly wrong, self-correcting
    // the moment each is opened, and it keeps the inbox on screen. Throwing
    // would take the whole list down over a decoration.
    await const FlutterSecureStorage().write(
      key: 'chat_thread_marks',
      value: 'not json at all',
    );
    expect(await reads.threadMarks(), isEmpty);
  });
}

/// The bug the association found, as a rule that cannot come back.
///
/// «الأرقام تصبح عالقة ولا تختفي إلا عندما يكتب شيئاً في المحادثة.»
///
/// ── WHY IT HAPPENED ─────────────────────────────────────────────────────────
/// The screen kept ONE «newest id I have rendered» for both rooms. Opening
/// المجلس set it to that room's newest — say 50. Switching to the private
/// thread, whose newest was 30, then failed the `30 <= 50` guard and returned
/// before marking anything at all. The badge sat there until a new message
/// pushed an id past 50, which is precisely what writing one does — and is
/// precisely why it looked as though typing was what cleared it.
///
/// ⚠ THE MARKS THEMSELVES WERE NEVER THE PROBLEM, which is why this is tested
///   here rather than in the widget: they are independent and monotonic, and
///   the fix was to stop a single counter deciding whether to write them.
void _independentRoomsTests() {
  const ChatReadState reads = ChatReadState(FlutterSecureStorage());

  test('المجلس and a private thread do not share a mark', () async {
    // The exact sequence: the open room read to 50, then a quieter thread read
    // to 30. Both must land.
    await reads.markHallRead(50);
    await reads.markThreadRead(6, 30);

    expect(await reads.hallRead(), 50);
    expect((await reads.threadMarks())[6], 30);
  });

  test('...and reading one never moves the other', () async {
    await reads.markThreadRead(6, 30);
    await reads.markHallRead(90);

    expect((await reads.threadMarks())[6], 30);
  });

  test('two private threads are independent of each other too', () async {
    // Same failure one level down: the board reads a busy conversation, then a
    // quiet one, and the quiet one must still clear.
    await reads.markThreadRead(6, 80);
    await reads.markThreadRead(9, 12);

    final Map<int, int> marks = await reads.threadMarks();
    expect(marks[6], 80);
    expect(marks[9], 12);
  });
}
