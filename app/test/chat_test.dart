import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/chat/domain/models.dart';
import 'package:family_app/features/chat/presentation/chat_screen.dart';
import 'package:family_app/features/chat/presentation/providers.dart';
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
  String at = '2026-08-19T09:00:00Z',
}) => ChatMessage(
  id: id,
  authorName: author,
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

void main() {
  final L l = LAr();
  late _StubChat chat;
  final List<ChatThread> threads = <ChatThread>[];

  Widget host(List<ChatMessage> messages, {AppUser user = _viewer}) {
    chat = _StubChat(messages);
    return ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(user)),
        chatProvider.overrideWith(() => chat),
        chatThreadsProvider.overrideWith((Ref ref) async => threads),
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
  }) async {
    tester.view.physicalSize = const Size(411, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(messages, user: user));
    await tester.pumpAndSettle();
  }

  testWidgets('the room shows what everyone said, not only what I said', (
    WidgetTester tester,
  ) async {
    // One room. Every other list in this app is scoped to the reader; a chat
    // where each person sees a different subset is not a chat.
    await open(tester, <ChatMessage>[
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
    await open(tester, <ChatMessage>[
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
    await open(tester, <ChatMessage>[
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
    await open(tester, <ChatMessage>[
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
    await open(tester, <ChatMessage>[_msg(id: 1, body: 'أهلاً')]);
    await tester.enterText(find.byType(TextField), '  وعليكم السلام  ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(chat.sent, 'وعليكم السلام');
  });
  testWidgets('an empty box sends nothing', (WidgetTester tester) async {
    // Guarded in the screen as well as in send_chat_message, because the round
    // trip to be told "الرسالة فارغة" is a worse answer than no round trip.
    await open(tester, <ChatMessage>[_msg(id: 1, body: 'أهلاً')]);
    await tester.enterText(find.byType(TextField), '    ');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(chat.sent, isNull);
  });
  testWidgets('a man may delete his OWN message', (WidgetTester tester) async {
    await open(tester, <ChatMessage>[_msg(id: 7, body: 'كلامي', mine: true)]);
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
    await open(tester, <ChatMessage>[
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
    await open(tester, <ChatMessage>[
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
    await open(tester, <ChatMessage>[
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
        AppRoutes.alerts,
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
        AppRoutes.alerts,
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

    testWidgets('...and المجلس is still the other segment, not replaced by it', (
      WidgetTester tester,
    ) async {
      await _pumpChat(tester, _member);
      expect(find.text(l.chatHall), findsOneWidget);
      // The same segment reads differently to the two accounts, and both
      // readings are honest: he writes TO the board, they read FROM everyone.
      expect(find.text(l.chatToBoard), findsOneWidget);
      expect(find.text(l.chatInbox), findsNothing);
    });

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
