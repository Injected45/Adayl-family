import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/chat/domain/models.dart';
import 'package:family_app/features/chat/presentation/chat_screen.dart';
import 'package:family_app/features/chat/presentation/emoji_panel.dart';
import 'package:family_app/features/chat/presentation/providers.dart';
import 'package:family_app/features/chat/presentation/unread_bell.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// مجلس العدايل — the first screen BOTH kinds of account reach.
///
/// Everything else in this app belongs to one audience. Staff read the
/// association; an عديل reads himself; `my_role()` returning NULL for a bound
/// portal account is what keeps the two apart. The room breaks that on purpose,
/// and the failures it invites are the quiet kind:
///
///   • a member sees an empty room and nothing says why (too narrow);
///   • a member reaches a screen full of the association's money (too wide).
///
/// The database side of both is proved in supabase/tests/46_chat.sql. What this
/// file protects is the SCREEN's half: that the router was widened by exactly
/// one route, that a bubble's side and its delete action come from the server's
/// answer rather than the client's opinion, and that a deleted message leaves a
/// visible mark rather than vanishing.
class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _user);
}

const AppUser _admin = AppUser(
  id: '00000000-0000-0000-0000-0000000000f1',
  email: 'admin@fam.test',
  displayName: 'المهدي',
  role: AppRole.admin,
  status: AccountStatus.approved,
);
const AppUser _viewer = AppUser(
  id: '00000000-0000-0000-0000-0000000000f2',
  email: 'viewer@fam.test',
  displayName: 'مطالع',
  role: AppRole.viewer,
  status: AccountStatus.approved,
);
ChatMessage _msg({
  required int id,
  required String body,
  String author = 'أيمن صالح بلها',
  bool mine = false,
  bool fromStaff = false,
  bool deleted = false,
  int? authorAdeelId,
  String at = '2026-08-19T09:00:00Z',
}) => ChatMessage(
  id: id,
  authorName: author,
  authorAdeelId: authorAdeelId,
  body: deleted ? '' : body,
  createdAt: at,
  mine: mine,
  fromStaff: fromStaff,
  deleted: deleted,
);

/// Stands in for the polling controller. The screen only ever reads the list and
/// calls three methods, so the timer and the network are not what these tests
/// are about — and a real four-second Timer inside a widget test is a hang
/// waiting to happen.
class _StubChat extends ChatController {
  _StubChat(this._messages);
  final List<ChatMessage> _messages;
  int deleted = 0;
  String? sent;
  @override
  Future<List<ChatMessage>> build(int? threadAdeelId) async => _messages;
  @override
  Future<void> send(String body) async => sent = body;

  /// Which room the screen asked for, so a test can assert that a member's
  /// private message went to HIS thread and not into المجلس.
  int? get room => arg;
  @override
  Future<void> remove(int id) async => deleted = id;
  @override
  Future<void> refresh() async {}
}

late Future<void> Function(WidgetTester) _openRoom;
late String? Function() _lastSent;
late Future<void> Function(WidgetTester, {int hall, int private})
_openWithRooms;
late Future<void> Function(WidgetTester, List<ChatMessage>, {AppUser user})
_openAs;

void main() {
  _barBackTests();
  final L l = LAr();
  late _StubChat chat;
  final List<ChatThread> threads = <ChatThread>[];

  Widget host(
    List<ChatMessage> messages, {
    AppUser user = _viewer,
    RoomUnread rooms = (hall: 0, private: 0),
  }) {
    chat = _StubChat(messages);
    return ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(user)),
        chatProvider.overrideWith(() => chat),
        chatThreadsProvider.overrideWith((Ref ref) async => threads),
        // The counts are given, not fetched — these tests are about where the
        // numbers LAND, and the query that produces them has its own file.
        roomUnreadProvider.overrideWith((Ref ref) async => rooms),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: const ChatScreen(),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester,
    List<ChatMessage> messages, {
    AppUser user = _viewer,
    RoomUnread rooms = (hall: 0, private: 0),
  }) async {
    tester.view.physicalSize = const Size(411, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(messages, user: user, rooms: rooms));
    await tester.pumpAndSettle();
  }

  _openRoom = (WidgetTester tester) =>
      open(tester, <ChatMessage>[_msg(id: 1, body: 'أهلاً')]);
  _openAs =
      (
        WidgetTester tester,
        List<ChatMessage> messages, {
        AppUser user = _viewer,
      }) => open(tester, messages, user: user);
  _openWithRooms = (WidgetTester tester, {int hall = 0, int private = 0}) =>
      open(
        tester,
        <ChatMessage>[_msg(id: 1, body: 'أهلاً')],
        rooms: (hall: hall, private: private),
      );
  _lastSent = () => chat.sent;
  _segmentCountTests();
  _keyboardTests();
  _emojiTests();
  _openThreadTests();

  testWidgets('the room shows what everyone said, not only what I said', (
    WidgetTester tester,
  ) async {
    // One room. Every other list in this app is scoped to the reader; a chat
    // where each person sees a different subset is not a chat.
    await _openAs(tester, <ChatMessage>[
      _msg(
        id: 1,
        body: 'اجتماع الجمعية يوم الجمعة',
        author: 'الإدارة',
        fromStaff: true,
      ),
      _msg(id: 2, body: 'إن شاء الله نحضر', mine: true),
      _msg(id: 3, body: 'وأنا كذلك', author: 'سالم أحمد'),
    ]);
    expect(find.text('اجتماع الجمعية يوم الجمعة'), findsOneWidget);
    expect(find.text('إن شاء الله نحضر'), findsOneWidget);
    expect(find.text('وأنا كذلك'), findsOneWidget);
  });
  testWidgets('a message from the board is marked as such', (
    WidgetTester tester,
  ) async {
    // An announcement about a meeting reads differently from a neighbour's
    // opinion of it, and the room should not have to guess which it is looking
    // at. `fromStaff` is a snapshot taken when the message was sent, so a
    // treasurer later demoted still spoke as staff at the time.
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'اجتماع الجمعية', author: 'المهدي', fromStaff: true),
      _msg(id: 2, body: 'حاضر', author: 'سالم أحمد'),
    ]);
    expect(find.text(l.chatFromBoard), findsOneWidget);
  });
  testWidgets('the sender name is printed once per RUN, not once per message', (
    WidgetTester tester,
  ) async {
    // Four lines from one man are one turn in a conversation, not four separate
    // announcements.
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'السلام عليكم', author: 'سالم أحمد'),
      _msg(id: 2, body: 'كيف حالكم', author: 'سالم أحمد'),
      _msg(id: 3, body: 'بخير', author: 'عمر علي'),
    ]);
    expect(find.text('سالم أحمد'), findsOneWidget);
    expect(find.text('عمر علي'), findsOneWidget);
  });
  testWidgets('a deleted message leaves a MARK, it does not vanish', (
    WidgetTester tester,
  ) async {
    // «فلان حذف شيئاً هنا» is information. A message that simply disappears
    // makes everyone who saw it doubt what they read — and the words themselves
    // are already erased in the database, so the tombstone costs no privacy.
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'شيء قيل', author: 'سالم أحمد', deleted: true),
      _msg(id: 2, body: 'ثم كلام بعده', author: 'عمر علي'),
    ]);
    expect(find.text(l.chatDeleted), findsOneWidget);
    expect(find.text('شيء قيل'), findsNothing);
    expect(find.text('ثم كلام بعده'), findsOneWidget);
  });
  testWidgets('typing and sending goes through the controller, trimmed', (
    WidgetTester tester,
  ) async {
    await _openAs(tester, <ChatMessage>[_msg(id: 1, body: 'أهلاً')]);
    await tester.enterText(find.byType(TextField), '  وعليكم السلام  ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(chat.sent, 'وعليكم السلام');
  });
  testWidgets('an empty box sends nothing', (WidgetTester tester) async {
    // Guarded in the screen as well as in send_chat_message, because the round
    // trip to be told "الرسالة فارغة" is a worse answer than no round trip.
    await _openAs(tester, <ChatMessage>[_msg(id: 1, body: 'أهلاً')]);
    await tester.enterText(find.byType(TextField), '    ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(chat.sent, isNull);
  });
  testWidgets('a man may delete his OWN message', (WidgetTester tester) async {
    await _openAs(tester, <ChatMessage>[
      _msg(id: 7, body: 'كلامي', mine: true),
    ]);
    await tester.longPress(find.text('كلامي'));
    await tester.pumpAndSettle();
    expect(find.text(l.chatDeleteTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l.delete));
    await tester.pumpAndSettle();
    expect(chat.deleted, 7);
  });
  testWidgets('...and a VIEWER cannot delete anyone else\'s', (
    WidgetTester tester,
  ) async {
    // `mine` is answered by the view from auth.uid(); the screen never compares
    // ids itself. Hiding the action is presentation — delete_chat_message
    // refuses it too — but a control that appears and then fails is a worse
    // screen than one that never offered.
    await _openAs(tester, <ChatMessage>[
      _msg(id: 8, body: 'كلام غيري', author: 'سالم أحمد'),
    ]);
    await tester.longPress(find.text('كلام غيري'));
    await tester.pumpAndSettle();
    expect(find.text(l.chatDeleteTitle), findsNothing);
    expect(chat.deleted, 0);
  });
  testWidgets('...but an ADMIN may, because moderation is a board act', (
    WidgetTester tester,
  ) async {
    // Deliberately admin and not financeManager: moderating what a member said
    // is not a financial power, and the association put the whole outgoing side
    // of the treasury a rung above finance for the same reason.
    await _openAs(tester, <ChatMessage>[
      _msg(id: 9, body: 'كلام يحتاج حذفاً', author: 'سالم أحمد'),
    ], user: _admin);
    await tester.longPress(find.text('كلام يحتاج حذفاً'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l.delete));
    await tester.pumpAndSettle();
    expect(chat.deleted, 9);
  });
  testWidgets('a deleted message offers nothing to delete again', (
    WidgetTester tester,
  ) async {
    await _openAs(tester, <ChatMessage>[
      _msg(id: 10, body: 'ذهب', mine: true, deleted: true),
    ], user: _admin);
    await tester.longPress(find.text(l.chatDeleted));
    await tester.pumpAndSettle();
    expect(find.text(l.chatDeleteTitle), findsNothing);
  });
  _guardTests();
  _privateTests();
  group('the room in the navigation', () {
    test('is reachable, and NOT in the phone bottom bar', () {
      // The bar is a four-slot budget spent on the money path, and the people
      // this room was built for never see it: an عديل is on the portal and his
      // way in is the button there.
      final AppDestination? room = destinationForRoute(AppRoutes.chat);
      expect(room, isNotNull);
      expect(room!.primary, isFalse);
      expect(room.isVisibleTo(AppRole.viewer), isTrue);
    });
  });
}

void _guardTests() {
  group('the portal boundary', () {
    test('an عديل may open the room', () {
      expect(portalMayOpen(AppRoutes.chat), isTrue);
    });
    test('...and his own portal, which is where he starts', () {
      expect(portalMayOpen(AppRoutes.myDues), isTrue);
    });
    test('...and is still refused EVERY other association screen', () {
      // The list is written out rather than derived from appDestinations,
      // because a route added to that list tomorrow must FAIL this test until
      // somebody decides which side of the boundary it is on. Deriving it would
      // let a new screen admit itself.
      for (final String route in <String>[
        AppRoutes.home,
        AppRoutes.adeels,
        AppRoutes.receivables,
        AppRoutes.payments,
        AppRoutes.cash,
        AppRoutes.statements,
        AppRoutes.reports,
        AppRoutes.officials,
        AppRoutes.audit,
        AppRoutes.settings,
        AppRoutes.users,
      ]) {
        expect(
          portalMayOpen(route),
          isFalse,
          reason: 'the portal must not reach $route',
        );
      }
    });
    test('the set is exactly two, and grows only with a policy', () {
      // The count is the guard on the guard. Widening the set is a real
      // decision — it needs a policy that admits him, or he arrives at a blank
      // screen — and a number that has to be edited is how that decision gets
      // noticed in review.
      final int allowed = <String>[
        AppRoutes.myDues,
        AppRoutes.chat,
        AppRoutes.home,
        AppRoutes.adeels,
        AppRoutes.receivables,
        AppRoutes.payments,
        AppRoutes.cash,
        AppRoutes.statements,
        AppRoutes.reports,
        AppRoutes.officials,
        AppRoutes.audit,
        AppRoutes.settings,
        AppRoutes.users,
      ].where(portalMayOpen).length;
      expect(allowed, 2);
    });
  });
}

/// A bound portal account: approved, no staff reach, one عديل and one thread.
const AppUser _member = AppUser(
  id: '00000000-0000-0000-0000-0000000000b1',
  email: 'adeel@fam.test',
  displayName: 'أيمن صالح بلها',
  role: AppRole.viewer,
  status: AccountStatus.approved,
  adeelId: 6,
);

/// Builds the screen on its own, outside `main`'s closures, so the private
/// group can reach it. Returns the stub so a test can ask WHICH ROOM the screen
/// requested — the one thing the screen decides and the server cannot correct.
Future<_StubChat> _pumpChat(WidgetTester tester, AppUser user) async {
  final Map<int?, _StubChat> made = <int?, _StubChat>{};
  tester.view.physicalSize = const Size(411, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(user)),
        chatProvider.overrideWith(() {
          final _StubChat c = _StubChat(<ChatMessage>[]);
          return c;
        }),
        chatThreadsProvider.overrideWith(
          (Ref ref) async => const <ChatThread>[],
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return made[null] ?? _StubChat(<ChatMessage>[]);
}

/// Switches to the private segment and sends one message, then reports which
/// room the screen addressed.
Future<_StubChat> _openPrivate(WidgetTester tester, AppUser user) async {
  late _StubChat opened;
  tester.view.physicalSize = const Size(411, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(user)),
        chatProvider.overrideWith(() => opened = _StubChat(<ChatMessage>[])),
        chatThreadsProvider.overrideWith(
          (Ref ref) async => const <ChatThread>[],
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: const ChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(LAr().chatToBoard));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'سؤال خاص');
  await tester.tap(find.byIcon(Icons.send_rounded));
  await tester.pumpAndSettle();
  return opened;
}

/// الخاص — the private thread, and the wall the whole feature rests on.
///
/// The wall itself is in the database: `read_chat` hands a member only threads
/// he is a side of, and `send_chat_message` refuses him a thread that is not
/// his. supabase/tests/46_chat.sql proves both from the side that would be
/// violated. What this file protects is that the SCREEN asks for the right room
/// — a member's private message must carry HIS id, not land in المجلس.
void _privateTests() {
  final L l = LAr();

  group('the private side', () {
    testWidgets('a member writes to the board, into HIS OWN thread', (
      WidgetTester tester,
    ) async {
      final _StubChat sent = await _openPrivate(tester, _member);
      expect(sent.room, 6, reason: 'his own adeelId, never null');
    });

    testWidgets(
      '...and المجلس is still the other segment, not replaced by it',
      (WidgetTester tester) async {
        await _pumpChat(tester, _member);
        expect(find.text(l.chatHall), findsOneWidget);
        // The same segment reads differently to the two accounts, and both
        // readings are honest: he writes TO the board, they read FROM everyone.
        expect(find.text(l.chatToBoard), findsOneWidget);
        expect(find.byIcon(Icons.arrow_forward), findsNothing);
      },
    );

    testWidgets('staff see an INBOX there instead, and no composer', (
      WidgetTester tester,
    ) async {
      // Until they pick somebody there is no conversation to write into, and a
      // composer with nowhere to send is a box that swallows what you type.
      await _pumpChat(tester, _admin);
      await tester.tap(find.text(l.chatInbox));
      await tester.pumpAndSettle();

      expect(find.text(l.chatInboxEmpty), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}

/// The emoji key, and what it must not break.
///
/// Every Android keyboard already has emoji, so the panel exists for a reason
/// worth stating: on the Arabic layouts common on these handsets it is two taps
/// behind a language switch. In a room where most of what is sent is a greeting,
/// a prayer and a heart, those should be one tap from the message box.
///
/// ⚠ WHAT IS ACTUALLY BEING GUARDED IS THE MESSAGE BOX, NOT THE GRID. Writing
///   to a TextEditingController bypasses the field's input formatters, so the
///   picker is a second way into the same text with none of the field's rules
///   applied — the 1000-character cap among them. And an emoji is several UTF-16
///   units, so deleting by index leaves half a glyph, which renders as ▯.
void _emojiTests() {
  final L l = LAr();

  Finder emojiKey() => find.byIcon(Icons.emoji_emotions_outlined);

  testWidgets('the key opens the grid, and closes it again', (
    WidgetTester tester,
  ) async {
    await _openRoom(tester);

    expect(find.byType(EmojiPanel), findsNothing);

    await tester.tap(emojiKey());
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPanel), findsOneWidget);

    // The icon now offers the way BACK, which is how every keyboard toggle on
    // the platform behaves.
    await tester.tap(find.byIcon(Icons.keyboard_alt_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(EmojiPanel), findsNothing);
  });

  testWidgets('a tap puts the emoji in the box, at the cursor', (
    WidgetTester tester,
  ) async {
    await _openRoom(tester);

    await tester.enterText(find.byType(TextField), 'سلام');
    await tester.tap(emojiKey());
    await tester.pumpAndSettle();

    await tester.tap(find.text('😀'));
    await tester.pumpAndSettle();

    final TextField box = tester.widget<TextField>(find.byType(TextField));
    expect(box.controller!.text, 'سلام😀');
  });

  testWidgets('the categories switch, and دعاء is behind its own chip', (
    WidgetTester tester,
  ) async {
    // 🙏 is the most-sent glyph in an association room and it is NOT on the
    // first page, so the chips are load-bearing rather than decoration.
    await _openRoom(tester);
    await tester.tap(emojiKey());
    await tester.pumpAndSettle();

    expect(find.text('🙏'), findsNothing);

    await tester.tap(find.text(l.emojiHands));
    await tester.pumpAndSettle();

    await tester.tap(find.text('🙏'));
    await tester.pumpAndSettle();

    final TextField box = tester.widget<TextField>(find.byType(TextField));
    expect(box.controller!.text, '🙏');
  });

  testWidgets('backspace removes ONE emoji, not half of one', (
    WidgetTester tester,
  ) async {
    // The bug this exists for: an emoji is two or more UTF-16 code units, so
    // deleting one unit leaves a lone surrogate that renders as ▯ and is sent
    // to the database that way.
    await _openRoom(tester);

    await tester.tap(emojiKey());
    await tester.pumpAndSettle();
    await tester.tap(find.text('😀'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l.emojiBackspace));
    await tester.pumpAndSettle();

    final TextField box = tester.widget<TextField>(find.byType(TextField));
    expect(box.controller!.text, isEmpty);
  });

  testWidgets('the grid cannot push a message past the 1000-character cap', (
    WidgetTester tester,
  ) async {
    // maxLength stops TYPING past it. A controller written to directly is not
    // filtered, so without the check in _insert the picker would be the one way
    // to build a message send_chat_message then refuses.
    await _openRoom(tester);

    final TextField box = tester.widget<TextField>(find.byType(TextField));
    box.controller!.text = 'ا' * 1000;
    await tester.pump();

    await tester.tap(emojiKey());
    await tester.pumpAndSettle();
    await tester.tap(find.text('😀'));
    await tester.pumpAndSettle();

    expect(box.controller!.text.characters.length, 1000);
  });
}

/// From a man's message in المحادثة الجماعية into his private one.
///
/// The board reads something in the open room and wants a private word about it.
/// Tapping his name, his disc or his bubble opens the thread — no hunting
/// through an inbox for a name that is on the screen already.
///
/// ⚠ AND IT IS STAFF-ONLY, WHICH IS A PERMISSION AND NOT A COURTESY. A private
///   thread has exactly two sides, and `read_chat` gives the second side to
///   `has_role('viewer')` — FALSE for a bound portal account, because my_role()
///   returns NULL while adeel_id is set. A member tapping another member would
///   land on a room the SERVER refuses to fill: empty, with nothing on it saying
///   why. He gets no tap target at all instead, which is the only honest answer
///   the client can give.
void _openThreadTests() {
  final L l = LAr();

  testWidgets('staff tap a name in the open room and land in his thread', (
    WidgetTester tester,
  ) async {
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'متى الاجتماع؟', author: 'أيمن صالح', authorAdeelId: 6),
    ], user: _admin);

    // Still in the open room.
    expect(find.text(l.chatHall), findsOneWidget);

    await tester.tap(find.text('أيمن صالح'));
    await tester.pumpAndSettle();

    // The heading is now HIS conversation, taken from the message's own
    // snapshot name — no register lookup, which is the property that lets the
    // room be read without access to the register at all.
    expect(find.text('أيمن صالح'), findsWidgets);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('...and tapping his BUBBLE does the same', (
    WidgetTester tester,
  ) async {
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'متى الاجتماع؟', author: 'أيمن صالح', authorAdeelId: 6),
    ], user: _admin);

    await tester.tap(find.text('متى الاجتماع؟'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });

  testWidgets('⚠ a MEMBER gets no such door, on any of the three targets', (
    WidgetTester tester,
  ) async {
    // The rule, asserted from the side that would be a privacy hole. He taps
    // another member's name and stays exactly where he was — the segment still
    // reads المحادثة الجماعية.
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'متى الاجتماع؟', author: 'سالم أحمد', authorAdeelId: 9),
    ], user: _member);

    await tester.tap(find.text('سالم أحمد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('متى الاجتماع؟'));
    await tester.pumpAndSettle();

    // Still the open room, and never someone else's thread.
    expect(find.text(l.chatHall), findsOneWidget);
    expect(find.text(l.chatToBoard), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });

  testWidgets('⚠ and a message from الإدارة opens nothing', (
    WidgetTester tester,
  ) async {
    // It carries no عديل, so there is no thread behind it. Without the null
    // check this would open a thread for id null and show the inbox instead —
    // which looks like a bug in the tap, not in the data.
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'اجتماع الجمعية', author: 'المهدي', fromStaff: true),
    ], user: _admin);

    await tester.tap(find.text('اجتماع الجمعية'));
    await tester.pumpAndSettle();

    expect(find.text(l.chatHall), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });
}

/// A count on the room you are NOT in.
///
/// The bell at the top says «هناك ٣» and does not say where. On this screen the
/// two rooms are one tap apart, so WHERE is the only part that is missing — a
/// man reading الخاص must be told that المجلس moved, and the reverse.
///
/// ⚠ THE ROOM HE IS IN READS ZERO BY CONSTRUCTION, not by a branch. The list
///   writes its own room's mark as it renders, so by the time the count is asked
///   there is nothing above it. A screen that also suppressed the badge would be
///   a second copy of that rule, free to disagree with the first.
void _segmentCountTests() {
  final L l = LAr();

  testWidgets('the other room carries its number', (WidgetTester tester) async {
    await _openWithRooms(tester, hall: 0, private: 4);

    // He is in المجلس; الخاص is the one with something waiting.
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('...and both are shown when both have something', (
    WidgetTester tester,
  ) async {
    await _openWithRooms(tester, hall: 2, private: 7);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('nothing waiting anywhere — no numbers at all', (
    WidgetTester tester,
  ) async {
    await _openWithRooms(tester, hall: 0, private: 0);
    expect(find.text('0'), findsNothing);
    // And the labels are still there, which is what says the badges are an
    // annotation rather than a replacement.
    expect(find.text(l.chatHall), findsOneWidget);
  });
}

/// The keyboard opens and the conversation STAYS ON SCREEN.
///
/// ── THE BUG THIS PINS ───────────────────────────────────────────────────────
/// «بمجرد الضغط للكتابة ترتفع وتختفي كل واجهة المحادثة.»
///
/// Scaffold lifts its whole body above the keyboard already —
/// `resizeToAvoidBottomInset` is on by default — and the composer ALSO added
/// `MediaQuery.viewInsets.bottom` to its own padding. The keyboard was counted
/// twice: the box rose a full keyboard-height above the keyboard, and the
/// message list, being whatever was left, was squeezed to nothing.
///
/// ⚠ WHAT THE COMPOSER MUST STILL RESERVE is the navigation pill, which FLOATS
///   over the body and which the Scaffold knows nothing about. Removing that one
///   too would put the send button under the pill — a bug this file has already
///   caught once, with a tap that missed.
void _keyboardTests() {
  testWidgets('with the keyboard up, the messages are still there', (
    WidgetTester tester,
  ) async {
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'أهلاً بكم'),
      _msg(id: 2, body: 'وعليكم السلام', mine: true),
    ]);

    // A keyboard, as the platform reports one.
    tester.view.viewInsets = const FakeViewPadding(bottom: 700);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pumpAndSettle();

    expect(find.text('أهلاً بكم'), findsOneWidget);
    expect(find.text('وعليكم السلام'), findsOneWidget);
    // And the box is still reachable, which is the other half of usable.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('...and the send button is not swallowed by the keyboard', (
    WidgetTester tester,
  ) async {
    await _openAs(tester, <ChatMessage>[_msg(id: 1, body: 'أهلاً')]);

    tester.view.viewInsets = const FakeViewPadding(bottom: 700);
    addTearDown(() => tester.view.resetViewInsets());
    await tester.pumpAndSettle();

    // The tap has to LAND — the assertion that catches a control pushed under
    // something the user cannot see through.
    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(_lastSent(), 'مرحبا');
  });
}

/// ── سهم الرجوع في الشريط ────────────────────────────────────────────────────
///
/// The room is reached with `context.go`, which REPLACES the location — so
/// there is nothing on the stack to pop and Android's system button leaves the
/// app. Without a control in the bar the room is a one-way door, which is how
/// the association found it.
///
/// ⚠ AND IT MUST NOT BE THE SAME GLYPH AS THE THREAD'S. Both point right,
///   because «back» points right in a right-to-left app — but the first attempt
///   used arrow_forward for both, and the tests above went ambiguous instantly:
///   they use that icon as the marker for «I am inside a private thread». The
///   bar wears a chevron; the thread keeps the solid arrow.
void _barBackTests() {
  testWidgets('the bar carries a way out of the room, at every moment', (
    WidgetTester tester,
  ) async {
    await _pumpChat(tester, _admin);
    expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    // …and the thread marker is NOT showing, because no thread is open.
    expect(find.byIcon(Icons.arrow_forward), findsNothing);
  });

  testWidgets('...and a member has one too — his portal is not a dead end', (
    WidgetTester tester,
  ) async {
    await _pumpChat(tester, _member);
    expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
  });

  testWidgets('⚠ and the two arrows stay distinguishable inside a thread', (
    WidgetTester tester,
  ) async {
    await _openAs(tester, <ChatMessage>[
      _msg(id: 1, body: 'متى الاجتماع؟', author: 'أيمن صالح', authorAdeelId: 6),
    ], user: _admin);

    await tester.tap(find.text('متى الاجتماع؟'));
    await tester.pumpAndSettle();

    // One of each, never two of one: the bar leaves الشاشة and the header
    // leaves المحادثة, and a reader has to be able to tell them apart.
    expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
  });
}
