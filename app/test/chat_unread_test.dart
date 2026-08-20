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
