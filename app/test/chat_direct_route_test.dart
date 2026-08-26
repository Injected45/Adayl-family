import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/call/domain/models.dart';
import 'package:family_app/features/call/presentation/providers.dart';
import 'package:family_app/features/chat/domain/models.dart';
import 'package:family_app/features/chat/presentation/chat_screen.dart';
import 'package:family_app/features/chat/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// رسالةٌ بين عديلين تذهب بينهما، لا إلى المجلس.
///
/// ⚠ THIS IS THE TEST THAT WAS MISSING, AND ITS ABSENCE SHIPPED THE BUG. The
///   existing suite proved the contact list renders, that الإدارة survives a
///   failed directory, and that a member's board message reaches HIS thread.
///   Nothing asked where a message goes after tapping a MAN.
///
///   `_Room.direct` was declared, wired into the reader and the writer, and
///   never set by anything: tapping a peer stored his id and left the room at
///   «private», so `_notifier` fell through to the hall writer with a null key
///   — which IS المجلس. Every private message the association sent was public.
///   Measured on their own database: 63 in المجلس, 61 in board threads, ZERO
///   carrying a peer pair.
///
/// ⚠ AND THE SERVER COULD NOT HAVE SAVED THEM. send_chat_message files the
///   message into whatever room it is TOLD; RLS then guards that room
///   perfectly. A client that names the wrong room is asking for exactly what
///   it gets, which is why this has to be caught here.
const AppUser _member = AppUser(
  id: '00000000-0000-0000-0000-0000000000b1',
  email: 'adeel@fam.test',
  displayName: 'أيمن صالح بلها',
  role: AppRole.viewer,
  status: AccountStatus.approved,
  adeelId: 6,
);

/// Records which room the screen addressed.
class _Hall extends ChatController {
  static final List<String> sent = <String>[];
  @override
  Future<List<ChatMessage>> build(int? threadAdeelId) async =>
      const <ChatMessage>[];
  @override
  Future<void> send(String body) async => sent.add('hall:$arg:$body');
  @override
  Future<void> remove(int id) async {}
  @override
  Future<void> refresh() async {}
}

class _Direct extends DirectChatController {
  static final List<String> sent = <String>[];
  @override
  Future<List<ChatMessage>> build(int peerAdeelId) async =>
      const <ChatMessage>[];
  @override
  Future<void> send(String body) async => sent.add('direct:$arg:$body');
  @override
  Future<void> remove(int id) async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  final L l = LAr();

  setUp(() {
    _Hall.sent.clear();
    _Direct.sent.clear();
  });

  testWidgets('⚠ a message to another عديل never reaches المجلس', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(_member)),
          chatProvider.overrideWith(_Hall.new),
          directChatProvider.overrideWith(_Direct.new),
          chatThreadsProvider.overrideWith(
            (Ref ref) async => const <ChatThread>[],
          ),
          callDirectoryProvider.overrideWith(
            (Ref ref) async => <CallPeer>[
              CallPeer.fromJson(<String, dynamic>{
                'adeelId': 3,
                'adeelCode': 'A-03',
                'name': 'هيثم مفتاح',
              }),
            ],
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

    // «محادثة خاصة» → the contact list → tap the other man.
    await tester.tap(find.text(l.chatConversations));
    await tester.pumpAndSettle();
    expect(
      find.text('هيثم مفتاح'),
      findsOneWidget,
      reason: 'the other عديل must be in the list to be tapped',
    );
    await tester.tap(find.text('هيثم مفتاح'));
    await tester.pumpAndSettle();

    // Type and send.
    await tester.enterText(find.byType(TextField), 'سرٌّ بيننا');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(
      _Direct.sent,
      <String>['direct:3:سرٌّ بيننا'],
      reason: 'the message must go to the peer conversation with A-03',
    );
    expect(
      _Hall.sent,
      isEmpty,
      reason:
          '⚠ THE WHOLE POINT. A single entry here is a private message the '
          'entire association can read — which is what happened, 63 times.',
    );
  });
}

class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _user);
}
