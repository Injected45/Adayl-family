import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/chat/data/chat_repository.dart';
import 'package:family_app/features/chat/domain/models.dart';
import 'package:family_app/features/chat/presentation/chat_screen.dart';
import 'package:family_app/features/chat/presentation/providers.dart';
import 'package:family_app/features/chat/presentation/unread_bell.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// حذفُ الرسائل: فرديّ، جزئيّ، كلّيّ (15/09).
///
/// «حتي رسائل المحادثات بين المشترك والادمن اريد كونترول للحذف جزئي وفردي وكلي».
///
/// ⚠ WHO MAY DELETE WHAT IS PROVED IN POSTGRES — 30 checks on a replica before
///   PATCH_20260915f was handed over, including the hole it closes: the single
///   delete let a member tombstone the admin's message. This file pins the
///   SCREEN's half: which controls appear, for whom, and what they send.
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

const AppUser _member = AppUser(
  id: '00000000-0000-0000-0000-0000000000b1',
  email: 'adeel@fam.test',
  displayName: 'هيثم مفتاح عبدالعظيم',
  role: AppRole.viewer,
  status: AccountStatus.approved,
  adeelId: 3,
);

ChatMessage _msg(
  int id,
  String body, {
  bool mine = false,
  bool deleted = false,
}) => ChatMessage(
  id: id,
  authorName: mine ? 'المهدي' : 'سالم صالح الشيخي',
  authorAdeelId: mine ? null : 6,
  body: deleted ? '' : body,
  createdAt: '2026-09-15T09:00:00Z',
  mine: mine,
  fromStaff: mine,
  deleted: deleted,
);

class _StubChat extends ChatController {
  _StubChat(this._messages);
  final List<ChatMessage> _messages;
  int? removed;
  List<int>? removedMany;

  /// Across every room's stub: the thread's notifier is not the last one built.
  static int clearedTotal = 0;
  @override
  Future<List<ChatMessage>> build(int? threadAdeelId) async => _messages;
  @override
  Future<void> remove(int id) async => removed = id;
  @override
  Future<void> removeMany(List<int> ids) async => removedMany = ids;
  @override
  Future<int> clearThread() async {
    clearedTotal++;
    return _messages.length;
  }

  @override
  Future<void> refresh() async {}
}

class _FakeRepo implements ChatRepository {
  int clearedAll = 0;
  @override
  Future<int> clearAllThreads() async {
    clearedAll++;
    return 12;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final List<ChatMessage> _room = <ChatMessage>[
  _msg(1, 'السلام عليكم'),
  _msg(2, 'وعليكم السلام', mine: true),
  _msg(3, 'رسالة حُذفت', deleted: true),
  _msg(4, 'موعد الاجتماع'),
];

final List<ChatThread> _threads = <ChatThread>[
  const ChatThread(
    adeelId: 6,
    adeelName: 'سالم صالح الشيخي',
    adeelCode: 'A-06',
    messages: 4,
    lastBody: 'موعد الاجتماع',
    lastAt: '2026-09-15T09:00:00Z',
    lastFromStaff: false,
  ),
  const ChatThread(
    adeelId: 4,
    adeelName: 'ايمن صالح محمد صالح بلها',
    adeelCode: 'A-04',
    messages: 2,
    lastBody: 'شكرا',
    lastAt: '2026-09-14T09:00:00Z',
    lastFromStaff: true,
  ),
];

Finder _body(String text) => find.textContaining(text, findRichText: true);

Future<({_StubChat Function() chat, _FakeRepo repo})> _open(
  WidgetTester tester, {
  AppUser user = _admin,
  double width = 411,
  double height = 1400,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // ⚠ ONE STUB PER ROOM, as Riverpod builds one per family key — المجلس and
  //   each member's thread are separate notifiers.
  final List<_StubChat> made = <_StubChat>[];
  _StubChat.clearedTotal = 0;
  final _FakeRepo repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(user)),
        chatProvider.overrideWith(() {
          final _StubChat c = _StubChat(_room);
          made.add(c);
          return c;
        }),
        chatThreadsProvider.overrideWith((Ref ref) async => _threads),
        roomUnreadProvider.overrideWith(
          (Ref ref) async => (hall: 0, private: 0),
        ),
        threadUnreadProvider.overrideWith((Ref ref) async => <int, int>{}),
        chatRepositoryProvider.overrideWithValue(repo),
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
  return (chat: () => made.last, repo: repo);
}

void main() {
  final L l = LAr();
  tearDown(() => applyAppTheme(AppThemeMode.light));

  group('فرديّ', () {
    testWidgets('the admin’s long press offers this message alone', (
      WidgetTester tester,
    ) async {
      final ({_StubChat Function() chat, _FakeRepo repo}) h = await _open(
        tester,
      );
      await tester.longPress(_body('السلام عليكم'));
      await tester.pumpAndSettle();
      expect(find.text(l.chatDeleteThisMessage), findsOneWidget);
      expect(find.text(l.chatSelectMessages), findsOneWidget);

      await tester.tap(find.text(l.chatDeleteThisMessage));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l.delete));
      await tester.pumpAndSettle();
      expect(h.chat().removed, 1);
    });

    testWidgets(
      'a member’s long press on his own is the dialog it always was',
      (WidgetTester tester) async {
        final ({_StubChat Function() chat, _FakeRepo repo}) h = await _open(
          tester,
          user: _member,
        );
        await tester.longPress(_body('وعليكم السلام'));
        await tester.pumpAndSettle();
        expect(find.text(l.chatSelectMessages), findsNothing);
        expect(find.text(l.chatDeleteTitle), findsOneWidget);
        // And nothing else to select or clear for him.
        await tester.tap(find.text(l.cancel));
        await tester.pumpAndSettle();
        expect(h.chat().removed, isNull);
      },
    );
  });

  group('جزئيّ', () {
    Future<({_StubChat Function() chat, _FakeRepo repo})> selecting(
      WidgetTester tester,
    ) async {
      final ({_StubChat Function() chat, _FakeRepo repo}) h = await _open(
        tester,
      );
      await tester.longPress(_body('السلام عليكم'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.chatSelectMessages));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('select, add another, delete both after asking', (
      WidgetTester tester,
    ) async {
      final ({_StubChat Function() chat, _FakeRepo repo}) h = await selecting(
        tester,
      );
      expect(find.text(l.chatSelectedCount(1)), findsOneWidget);
      // The composer gives way to the selection bar.
      expect(find.byType(TextField), findsNothing);

      await tester.tap(_body('موعد الاجتماع'));
      await tester.pumpAndSettle();
      expect(find.text(l.chatSelectedCount(2)), findsOneWidget);

      // A tap again takes one out.
      await tester.tap(_body('موعد الاجتماع'));
      await tester.pumpAndSettle();
      expect(find.text(l.chatSelectedCount(1)), findsOneWidget);
      await tester.tap(_body('موعد الاجتماع'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, l.delete));
      await tester.pumpAndSettle();
      expect(find.text(l.chatDeleteManyTitle(2)), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text(l.delete)),
      );
      await tester.pumpAndSettle();
      expect(h.chat().removedMany?.toSet(), <int>{1, 4});
      expect(find.text(l.chatDeletedMany(2)), findsOneWidget);
      // Back to writing.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('«تحديد الكل» takes every live message, never a tombstone', (
      WidgetTester tester,
    ) async {
      final ({_StubChat Function() chat, _FakeRepo repo}) h = await selecting(
        tester,
      );
      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();
      expect(find.text(l.chatSelectedCount(3)), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, l.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(
        h.chat().removedMany,
        isNull,
        reason: 'cancelling deletes nothing',
      );
    });

    testWidgets('✕ ends the selection without deleting', (
      WidgetTester tester,
    ) async {
      final ({_StubChat Function() chat, _FakeRepo repo}) h = await selecting(
        tester,
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text(l.chatSelectedCount(1)), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(h.chat().removedMany, isNull);
    });
  });

  group('كلّيّ', () {
    testWidgets('«مسح كل الرسائل الخاصة» is red, asks, then clears', (
      WidgetTester tester,
    ) async {
      final ({_StubChat Function() chat, _FakeRepo repo}) h = await _open(
        tester,
      );
      await tester.tap(find.text(l.chatInbox));
      await tester.pumpAndSettle();

      final Finder button = find.widgetWithText(
        FilledButton,
        l.chatClearAllThreads,
      );
      expect(button, findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(button)
            .style
            ?.backgroundColor
            ?.resolve(<WidgetState>{}),
        AppColors.danger,
      );

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(l.chatClearAllTitle), findsOneWidget);
      expect(find.text(l.chatClearAllBody(2)), findsOneWidget);
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(h.repo.clearedAll, 0);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(l.chatClearConfirm),
        ),
      );
      await tester.pumpAndSettle();
      expect(h.repo.clearedAll, 1);
      expect(find.text(l.chatClearedAll(12)), findsOneWidget);
    });

    testWidgets('«مسح المحادثة» on one member’s conversation', (
      WidgetTester tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text(l.chatInbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('سالم صالح الشيخي'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l.chatClearThread));
      await tester.pumpAndSettle();
      expect(
        find.text(l.chatClearThreadTitle('سالم صالح الشيخي')),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(l.chatClearConfirm),
        ),
      );
      await tester.pumpAndSettle();
      expect(_StubChat.clearedTotal, 1);
      expect(find.text(l.chatClearedThread(4)), findsOneWidget);
      // Back to the inbox.
      expect(find.text(l.chatClearAllThreads), findsOneWidget);
    });

    testWidgets('a member sees no clearing at all', (
      WidgetTester tester,
    ) async {
      await _open(tester, user: _member);
      expect(find.text(l.chatClearAllThreads), findsNothing);
      expect(find.text(l.chatClearThread), findsNothing);
    });
  });

  // «لا اريد اي حرف يخرج خارج اطار الديزاين».
  for (final double width in <double>[320, 411]) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      testWidgets('selection bar, header and inbox fit at ${width.toInt()}px '
          'in ${mode.name}', (WidgetTester tester) async {
        applyAppTheme(mode);
        await _open(tester, width: width, height: 900);
        await tester.longPress(_body('السلام عليكم'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l.chatSelectMessages));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        await tester.tap(find.text(l.chatInbox));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('سالم صالح الشيخي'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
