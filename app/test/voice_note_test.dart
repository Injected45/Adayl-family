import 'dart:io';

import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/chat/data/voice_recorder.dart';
import 'package:family_app/features/chat/domain/models.dart';
import 'package:family_app/features/chat/presentation/chat_screen.dart';
import 'package:family_app/features/chat/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// المقاطعُ الصوتيّة — «بنفس شروط الرسائل».
///
/// ⚠ THE ONE RULE THIS FILE EXISTS FOR: a clip obeys every rule a message
///   obeys, and above all WHICH ROOM IT LANDS IN. The direct-chat bug was
///   exactly this failure for text — `_Room.direct` was declared and never set,
///   so 63 private messages went to المجلس — and a voice note is the same
///   mistake waiting a second time, on content that is more private, not less:
///   a man's own voice, in a room the association was promised is «خاصّة
///   تماماً».
///
/// ⚠ AND IT IS ASSERTED AGAINST THE SOURCE, not by driving the microphone.
///   `record` needs a platform channel no test binding provides — hasPermission
///   throws, the recorder returns false, and a widget test can never reach the
///   send at all. So what is pinned is the SHAPE: one door to the controllers,
///   and the room chosen by the same `_notifier` that text goes through.
String _read(String path) => File(path).readAsStringSync();

/// نافذةٌ من المصدر، لا تتجاوز نهايتَه.
///
/// ⚠ A BARE substring(at, at + n) THROWS ON THE LAST DECLARATION IN A FILE,
///   which is exactly where DirectChatController sits — so the guard would
///   have failed for a reason that has nothing to do with what it checks.
String _window(String s, int at, int n) =>
    s.substring(at, at + n > s.length ? s.length : at + n);

const AppUser _member = AppUser(
  id: '00000000-0000-0000-0000-0000000000b1',
  email: 'adeel@fam.test',
  displayName: 'أيمن صالح بلها',
  role: AppRole.viewer,
  status: AccountStatus.approved,
  adeelId: 6,
);

ChatMessage _voice({bool deleted = false, bool mine = true}) =>
    ChatMessage.fromJson(<String, dynamic>{
      'id': 41,
      'body': '',
      'authorName': mine ? 'أيمن صالح بلها' : 'هيثم مفتاح',
      'authorUserId': mine ? _member.id : 'someone-else',
      'fromStaff': false,
      'deleted': deleted,
      'createdAt': '2026-08-26T09:00:00+00:00',
      'threadAdeelId': null,
      'room': 'hall',
      'voicePath': deleted ? null : 'uid/41.m4a',
      'voiceMs': deleted ? null : 7400,
    });

class _Room extends ChatController {
  static final List<String> calls = <String>[];
  @override
  Future<List<ChatMessage>> build(int? threadAdeelId) async => <ChatMessage>[
    _voice(),
  ];
  @override
  Future<void> send(String body) async => calls.add('hall.text');
  @override
  Future<void> sendVoice(File file, int ms) async => calls.add('hall.voice');
  @override
  Future<void> remove(int id) async {}
  @override
  Future<void> refresh() async {}
}

void main() {
  const String screen = 'lib/features/chat/presentation/chat_screen.dart';
  const String providers = 'lib/features/chat/presentation/providers.dart';
  const String bubble = 'lib/features/chat/presentation/voice_bubble.dart';
  const String repo = 'lib/features/chat/data/chat_repository.dart';

  group('الغرفة', () {
    test('⚠ الصوت يمرّ من بابِ النصِّ نفسِه — _notifier', () {
      final String s = _read(screen);

      // The send path inside _stopRec.
      final int at = s.indexOf('Future<void> _stopRec(');
      expect(at, greaterThan(0), reason: 'the voice send path must exist');
      final String body = _window(s, at, 1400);

      expect(
        body.contains('_notifier.sendVoice('),
        isTrue,
        reason:
            '⚠ THE ROOM IS CHOSEN IN ONE PLACE. _notifier is the only thing '
            'that knows whether this screen is المجلس, a board thread, or a '
            'private conversation between two عدايل.',
      );
      expect(
        body.contains('chatProvider(') || body.contains('directChatProvider('),
        isFalse,
        reason:
            '⚠ A SECOND PATH TO THE CONTROLLERS IS THE BUG ITSELF. Reading a '
            'provider here re-decides the room, and a wrong answer files a '
            'man\'s voice into a room the association promised nobody reads.',
      );
    });

    test('⚠ كلا الكاتبَين يُنفّذ sendVoice، كلٌّ إلى وحدته', () {
      final String s = _read(screen);

      expect(
        s.contains('Future<void> sendVoice(File file, int ms);'),
        isTrue,
        reason: 'ChatWriter must declare it, or a caller can bypass the door',
      );

      for (final String w in <String>['_RoomWriter', '_DirectWriter']) {
        final int at = s.indexOf('class $w implements ChatWriter');
        expect(at, greaterThan(0), reason: '$w must exist');
        final String impl = _window(s, at, 700);
        expect(
          impl.contains('sendVoice(File file, int ms) => _n.sendVoice('),
          isTrue,
          reason:
              '$w must forward the clip to ITS OWN controller. A writer that '
              'does not implement it would not compile — which is the point '
              'of putting it on the interface rather than on one screen.',
        );
      }
    });

    test('⚠ وحدتا التحكّم تكتبان إلى غرفتين مختلفتين', () {
      final String s = _read(providers);

      final int room = s.indexOf('class ChatController');
      final int direct = s.indexOf('class DirectChatController');
      expect(room, greaterThan(0));
      expect(direct, greaterThan(room));

      final String roomBody = s.substring(room, direct);
      final String directBody = s.substring(direct);

      expect(
        roomBody.contains("repo.send('', threadAdeelId: arg"),
        isTrue,
        reason: 'المجلس/خيط الإدارة goes through send with a thread id',
      );
      expect(
        directBody.contains("repo.sendDirect('', toAdeelId: arg"),
        isTrue,
        reason:
            '⚠ sendDirect, NOT send. The two RPCs file into different rooms, '
            'and send() with a peer id would put a private clip in a board '
            'thread the admin reads.',
      );
      expect(
        directBody.contains('repo.send('),
        isFalse,
        reason: 'the direct controller must never reach the room writer',
      );
    });
  });

  group('الرفعُ والتنظيف', () {
    test('⚠ الملفُّ أوّلاً ثمّ الرسالة، والمهجورُ يُكنَس', () {
      final String s = _read(providers);

      for (final String cls in <String>[
        'class ChatController',
        'class DirectChatController',
      ]) {
        final int at = s.indexOf(cls);
        final int v = s.indexOf('Future<void> sendVoice(', at);
        expect(v, greaterThan(at), reason: '$cls must carry sendVoice');
        final String body = _window(s, v, 900);

        final int up = body.indexOf('uploadVoice(');
        final int msg = body.indexOf('voicePath: path');
        expect(up, greaterThan(0), reason: 'the clip must be uploaded');
        expect(
          msg > up,
          isTrue,
          reason:
              '⚠ ORDER. A message written before its file exists points at '
              'nothing — a bubble on screen that plays silence. A failed '
              'upload, the other way round, simply sends nothing.',
        );
        expect(
          body.contains('removeVoice(path)'),
          isTrue,
          reason:
              '⚠ AN ORPHANED CLIP IS UNREACHABLE — no row names it and the '
              'read policy has nothing to join — but it still fills a bucket '
              'nobody can account for.',
        );
        expect(
          body.contains('deleteLocalVoice(file)'),
          isTrue,
          reason:
              '⚠ AND THE HANDSET\'S COPY GOES EITHER WAY. A recording of a '
              'man\'s voice is not left on a phone because a request failed.',
        );
      }
    });

    test('⚠ الميكروفون يُغلق مع الشاشة', () {
      final String s = _read(screen);
      final int at = s.indexOf('  void dispose() {');
      final String body = _window(s, at, 1400);
      expect(
        body.contains('_recorder.dispose()'),
        isTrue,
        reason:
            '⚠ LEAVING MID-RECORDING MUST NOT LEAVE A HOT MICROPHONE. '
            'dispose() cancels first, which also deletes the half-clip.',
      );
      expect(
        body.contains('_recTick?.cancel()'),
        isTrue,
        reason: 'a timer calling setState on a dead State throws',
      );
    });
  });

  group('التشغيل', () {
    test('⚠ الرابطُ المُوقَّع يُطلب عند الضغط، لا مع كلِّ رسالة', () {
      final String b = _read(bubble);
      expect(
        b.contains('voiceUrl('),
        isTrue,
        reason: 'a private bucket needs a signed link to play at all',
      );

      final int build = b.indexOf('Widget build(BuildContext context)');
      expect(
        b.substring(build).contains('voiceUrl('),
        isFalse,
        reason:
            '⚠ SIGNING ON BUILD WOULD SIGN EVERY CLIP THE ROOM SCROLLS PAST '
            '— forty requests for one a man might listen to, and forty links '
            'that did not need to exist.',
      );

      final String r = _read(repo);
      final int u = r.indexOf('voiceUrl(');
      expect(
        RegExp(r'createSignedUrl\(').hasMatch(_window(r, u, 700)),
        isTrue,
        reason:
            '⚠ SIGNED, NOT PUBLIC. A public URL is readable by anyone who '
            'ever sees it, for ever, with no policy in the way.',
      );
    });

    testWidgets('⚠ رسالةٌ صوتيّة تُرسم مشغِّلاً، لا فقاعةً فارغة', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(411, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            authControllerProvider.overrideWith(() => _StubAuth(_member)),
            chatProvider.overrideWith(_Room.new),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            locale: const Locale('ar'),
            localizationsDelegates: latinDigitDelegates(
              L.localizationsDelegates,
            ),
            supportedLocales: L.supportedLocales,
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.play_circle_outline),
        findsOneWidget,
        reason:
            '⚠ A VOICE NOTE CARRIES AN EMPTY BODY, so the plain text branch '
            'paints a bubble with nothing in it — a message that arrived, '
            'occupies a row, and cannot be heard.',
      );
      expect(
        find.text('0:07'),
        findsOneWidget,
        reason: 'the length is what tells a man whether he has time to listen',
      );
    });
  });

  test('⚠ الحدُّ دقيقةٌ واحدة، والخادم يقول الشيءَ نفسَه', () {
    expect(VoiceRecorder.maxLength, const Duration(seconds: 60));

    final String sql = _read('../supabase/PATCH_20260826a_voice_notes.sql');
    expect(
      sql.contains('60000'),
      isTrue,
      reason:
          '⚠ THE RULE THAT DECIDES IS THE ONE IN THE DATABASE. The cap in '
          'Dart is a courtesy that stops a man recording two minutes and '
          'being told at the end that it was wasted.',
    );
  });
}

class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _user);
}
