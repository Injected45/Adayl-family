import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/network/api_exception.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/core/supabase/supabase_failures.dart';
import 'package:family_app/core/widgets/nav_pill_bar.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/notifications/data/notice_read_state.dart';
import 'package:family_app/features/notifications/data/notifications_repository.dart';
import 'package:family_app/features/notifications/domain/models.dart';
import 'package:family_app/features/notifications/presentation/notifications_screen.dart';
import 'package:family_app/features/notifications/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// الإشعارات — what reaches a member, what the admin sees, and the one box that
/// writes to everyone.
///
/// ⚠ WHO RECEIVES WHICH NOTICE IS PROVED IN POSTGRES, not here: the triggers,
///   the audience of each, RLS for a member against another member's voucher,
///   and that a broken notifications table cannot stop a receipt — twenty-six
///   checks against a copy of the live ledger before PATCH_20260913c was handed
///   over. What this file pins is the SCREEN's half: the badge's decision, the
///   member seeing no composer and no recipients, the admin's confirmation, and
///   that nothing leaves the frame at 320px in either theme.
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

class _StubUnread extends NoticesUnread {
  _StubUnread(this.count);
  final int count;
  final List<int> marked = <int>[];
  @override
  Future<int> build() async => count;
  @override
  Future<void> markSeen(int newestId) async => marked.add(newestId);
  final List<int> readOnes = <int>[];
  @override
  Future<void> readOne(int id) async => readOnes.add(id);
}

class _FakeReads extends NoticeReadState {
  _FakeReads(this.seen) : super(const FlutterSecureStorage());
  final int seen;
  @override
  Future<int> lastSeen(String userId) async => seen;
  @override
  Future<void> markSeen(String userId, int id) async {}
}

class _FakeRepo implements NotificationsRepository {
  final List<({String? title, String body})> sent =
      <({String? title, String body})>[];

  @override
  Future<void> sendBroadcast({required String body, String? title}) async =>
      sent.add((title: title, body: body));

  @override
  Future<List<AppNotice>> list({int limit = 200}) async => _notices();
  @override
  Future<int> unreadSince(int sinceId, {int cap = 99}) async => 0;
  @override
  Future<AppNotice?> newestSince(int sinceId) async => null;
  @override
  Future<int> newestId() async => 0;
  int cleared = 0;
  @override
  Future<int> clearAll() async {
    cleared++;
    return _notices().length;
  }

  @override
  Future<AppNotice?> byId(int id) async {
    for (final AppNotice n in _notices()) {
      if (n.id == id) return n;
    }
    return null;
  }
}

/// The worst case on purpose: a four-word Libyan name, a voucher note that is
/// a whole sentence, and a thousands figure.
List<AppNotice> _notices() => <AppNotice>[
  AppNotice.fromJson(<String, dynamic>{
    'id': 12,
    'audience': 'all',
    'kind': 'broadcast',
    'title': 'رسالة من الإدارة',
    'body':
        'اجتماع الجمعية العمومية يوم الجمعة القادم بعد صلاة العصر في بيت '
        'الحاج عبدالرحمن محمد عبدالسلام الشيباني، والحضور مهمّ لجميع الأعضاء',
    'createdAt': '2026-09-13T10:15:00Z',
  }),
  AppNotice.fromJson(<String, dynamic>{
    'id': 11,
    'audience': 'member',
    'kind': 'disbursement',
    'title': 'صرف لك من الصندوق',
    'body':
        'صُرف لك 12,345.00 د.ل — حالات طارئة («علاج في تونس»). سند رقم EXP-63.',
    'ref': 'EXP-63',
    'createdAt': '2026-09-12T20:00:00Z',
    'adeelCode': 'A-03',
    'adeelName': 'عبدالرحمن محمد عبدالسلام الشيباني',
  }),
  AppNotice.fromJson(<String, dynamic>{
    'id': 9,
    'audience': 'member',
    'kind': 'payment_cancelled',
    'title': 'إلغاء إيصال',
    'body': 'أُلغي الإيصال رقم PAY-147 بقيمة 150.00 د.ل.',
    'ref': 'PAY-147',
    'createdAt': '2026-09-01T08:00:00Z',
    'adeelCode': 'A-03',
    'adeelName': 'هيثم مفتاح عبدالعظيم',
  }),
];

Future<({_StubUnread unread, _FakeRepo repo})> _pump(
  WidgetTester tester, {
  required AppUser user,
  required bool portal,
  double width = 411,
  int seen = 10,
  List<AppNotice>? notices,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _StubUnread unread = _StubUnread(0);
  final _FakeRepo repo = _FakeRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(user)),
        noticesUnreadProvider.overrideWith(() => unread),
        noticeReadStateProvider.overrideWithValue(_FakeReads(seen)),
        notificationsRepositoryProvider.overrideWithValue(repo),
        noticesProvider.overrideWith((Ref ref) async => notices ?? _notices()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: NotificationsScreen(portal: portal),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (unread: unread, repo: repo);
}

void main() {
  final L l = LAr();
  tearDown(() => applyAppTheme(AppThemeMode.light));

  group('the badge decides', () {
    test('the first reading arms and never announces', () {
      expect(
        decideNoticeAlert(
          armed: false,
          announced: 0,
          count: 7,
          onScreen: false,
        ),
        NoticeAlert.arm,
      );
    });

    test('a rise announces once; the same count says nothing', () {
      expect(
        decideNoticeAlert(armed: true, announced: 2, count: 3, onScreen: false),
        NoticeAlert.announce,
      );
      expect(
        decideNoticeAlert(armed: true, announced: 3, count: 3, onScreen: false),
        NoticeAlert.none,
      );
      expect(
        decideNoticeAlert(armed: true, announced: 3, count: 2, onScreen: false),
        NoticeAlert.none,
      );
    });

    test('⚠ looking at the list, or nothing waiting, takes it down', () {
      expect(
        decideNoticeAlert(armed: true, announced: 0, count: 4, onScreen: true),
        NoticeAlert.clear,
      );
      expect(
        decideNoticeAlert(armed: true, announced: 4, count: 0, onScreen: false),
        NoticeAlert.clear,
      );
    });
  });

  group('the wire', () {
    test('a notice parses, and an unknown kind is still shown', () {
      final AppNotice n = _notices()[1];
      expect(n.kind, NoticeKind.disbursement);
      expect(n.toEveryone, isFalse);
      expect(n.adeelCode, 'A-03');
      expect(
        NoticeKind.fromWire('something_added_later'),
        NoticeKind.broadcast,
      );
      expect(NoticeKind.paymentCancelled.isCancellation, isTrue);
    });

    test(
      'RUL18 — an empty or over-long message — is a 422, not a 500',
      () async {
        // Its Arabic sentence reaches the screen either way (the RUL prefix
        // decides that); the status decides whether it reads as a server fault.
        try {
          await SupabaseFailures.guard<void>(
            () => throw const PostgrestException(
              message: 'اكتب نصَّ الرسالة قبل الإرسال',
              code: 'RUL18',
            ),
          );
          fail('guard must rethrow as ApiException');
        } on ApiException catch (e) {
          expect(e.statusCode, 422);
          expect(e.serverMessage, 'اكتب نصَّ الرسالة قبل الإرسال');
        }
      },
    );

    test('the admin reaches it from «المزيد»; a member only by a push', () {
      expect(destinationForRoute(AppRoutes.notifications), isNotNull);
      expect(destinationForRoute(AppRoutes.notifications)!.primary, isFalse);
      expect(
        portalMayOpen(AppRoutes.notifications),
        isFalse,
        reason: 'the member reaches it by Navigator.push from his bar',
      );
    });
  });

  group('a member', () {
    testWidgets('sees his notices, with no composer and no recipients', (
      WidgetTester tester,
    ) async {
      await _pump(tester, user: _member, portal: true);

      expect(find.text('رسالة من الإدارة'), findsOneWidget);
      expect(find.text('صرف لك من الصندوق'), findsOneWidget);
      // Titles only (15/09): the sentences are behind a tap.
      expect(find.textContaining('12,345.00'), findsNothing);
      expect(find.textContaining('اجتماع الجمعية العمومية'), findsNothing);
      expect(find.text(l.broadcastHeading), findsNothing);
      expect(find.byType(TextField), findsNothing);
      // The red button is the admin's alone.
      expect(find.text(l.noticesClearAll), findsNothing);
      // The recipient chip is staff-only: a member knows whom his notices are for.
      expect(find.text(l.noticeToEveryone), findsNothing);
      expect(find.textContaining('A-03'), findsNothing);
    });

    testWidgets('what arrived since he last looked is marked «جديد»', (
      WidgetTester tester,
    ) async {
      await _pump(tester, user: _member, portal: true, seen: 10);
      // ids 12 and 11 are above his mark; 9 is not.
      expect(find.text(l.noticeNew), findsNWidgets(2));
    });

    testWidgets('⚠ opening the list marks everything on it seen', (
      WidgetTester tester,
    ) async {
      final ({_StubUnread unread, _FakeRepo repo}) r = await _pump(
        tester,
        user: _member,
        portal: true,
      );
      expect(r.unread.marked, <int>[12]);
    });

    testWidgets('an empty list says what will arrive here', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        user: _member,
        portal: true,
        notices: const <AppNotice>[],
      );
      expect(find.text(l.noticesEmpty), findsOneWidget);
      expect(find.text(l.noticesEmptyBody), findsOneWidget);
    });
  });

  group('the admin', () {
    testWidgets('sees the composer and whom each notice went to', (
      WidgetTester tester,
    ) async {
      final ({_StubUnread unread, _FakeRepo repo}) r = await _pump(
        tester,
        user: _admin,
        portal: false,
      );
      expect(find.text(l.broadcastHeading), findsOneWidget);
      expect(find.text(l.noticeNew), findsNothing);
      expect(r.unread.marked, isEmpty, reason: 'the admin has no read mark');

      // The row is the title; whom it went to is on the notice itself.
      expect(
        find.text('A-03 · عبدالرحمن محمد عبدالسلام الشيباني'),
        findsNothing,
      );
      await tester.ensureVisible(find.text('صرف لك من الصندوق'));
      await tester.tap(find.text('صرف لك من الصندوق'));
      await tester.pumpAndSettle();
      expect(find.text(l.noticeDetailTitle), findsOneWidget);
      expect(
        find.text('A-03 · عبدالرحمن محمد عبدالسلام الشيباني'),
        findsOneWidget,
      );
      await tester.tap(find.text(l.backAction));
      await tester.pumpAndSettle();

      // By its row: the composer's hint says «رسالة من الإدارة» too.
      final Finder broadcast = find.widgetWithText(
        NoticeTile,
        'رسالة من الإدارة',
      );
      await tester.ensureVisible(broadcast);
      await tester.tap(broadcast);
      await tester.pumpAndSettle();
      expect(find.text(l.noticeToEveryone), findsOneWidget);
      await tester.tap(find.text(l.backAction));
      await tester.pumpAndSettle();
    });

    testWidgets('⚠ «مسح كل الإشعارات» is red, and asks before deleting', (
      WidgetTester tester,
    ) async {
      final ({_StubUnread unread, _FakeRepo repo}) r = await _pump(
        tester,
        user: _admin,
        portal: false,
      );
      final Finder button = find.widgetWithText(
        FilledButton,
        l.noticesClearAll,
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

      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(l.noticesClearTitle), findsOneWidget);
      expect(find.text(l.noticesClearBody(3)), findsOneWidget);
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(r.repo.cleared, 0, reason: 'cancelling deletes nothing');

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(l.noticesClearConfirm),
        ),
      );
      await tester.pumpAndSettle();
      expect(r.repo.cleared, 1);
      expect(find.text(l.noticesCleared(3)), findsOneWidget);
    });

    testWidgets('nothing to clear, no button', (WidgetTester tester) async {
      await _pump(
        tester,
        user: _admin,
        portal: false,
        notices: const <AppNotice>[],
      );
      expect(find.text(l.noticesClearAll), findsNothing);
    });

    testWidgets('an empty message is refused before anything is sent', (
      WidgetTester tester,
    ) async {
      final ({_StubUnread unread, _FakeRepo repo}) r = await _pump(
        tester,
        user: _admin,
        portal: false,
      );
      await tester.tap(find.text(l.broadcastSend));
      await tester.pumpAndSettle();
      expect(find.text(l.broadcastEmpty), findsOneWidget);
      expect(r.repo.sent, isEmpty);
    });

    testWidgets('⚠ sending asks first, and cancelling sends nothing', (
      WidgetTester tester,
    ) async {
      final ({_StubUnread unread, _FakeRepo repo}) r = await _pump(
        tester,
        user: _admin,
        portal: false,
      );
      await tester.enterText(find.byType(TextField).last, 'اجتماع يوم الجمعة');
      await tester.tap(find.text(l.broadcastSend));
      await tester.pumpAndSettle();

      expect(find.text(l.broadcastConfirmTitle), findsOneWidget);
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(r.repo.sent, isEmpty);

      await tester.tap(find.text(l.broadcastSend));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(l.broadcastSend),
        ),
      );
      await tester.pumpAndSettle();

      expect(r.repo.sent.single.body, 'اجتماع يوم الجمعة');
      expect(find.text(l.broadcastSent), findsOneWidget);
      // The box empties once it has gone, so a second tap cannot resend it.
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
    });
  });

  // ⚠ THE MEMBER'S BAR WENT FROM THREE ITEMS TO FOUR. At 320px that is 72px a
  //   slot, with «الإشعارات» the longest label on it and a «+99» badge riding
  //   the icon — the case that would break first.
  for (final AppThemeMode mode in AppThemeMode.values) {
    testWidgets('the member bar holds four items at 320px in ${mode.name}', (
      WidgetTester tester,
    ) async {
      applyAppTheme(mode);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: const Locale('ar'),
          localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
          supportedLocales: L.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: NavPillBar(
              items: <NavPillItem>[
                NavPillItem(
                  icon: Icons.grid_view_outlined,
                  selectedIcon: Icons.grid_view,
                  label: l.navMore,
                  onTap: () {},
                ),
                NavPillItem(
                  icon: Icons.forum_outlined,
                  selectedIcon: Icons.forum,
                  label: l.navChat,
                  badge: 120,
                  onTap: () {},
                ),
                NavPillItem(
                  icon: Icons.notifications_outlined,
                  selectedIcon: Icons.notifications,
                  label: l.navNotifications,
                  badge: 120,
                  onTap: () {},
                ),
                NavPillItem(
                  icon: Icons.insights_outlined,
                  selectedIcon: Icons.insights,
                  label: l.valueTitle,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // ⚠ AND NOT CUT SHORT. The label is one line with an ellipsis, so an
      //   overflow would never throw — it would print «الإشعا…» instead.
      for (final String label in <String>[
        l.navMore,
        l.navChat,
        l.navNotifications,
        l.valueTitle,
      ]) {
        final RenderParagraph p = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(p.didExceedMaxLines, isFalse, reason: '«$label» was truncated');
      }
    });
  }

  // «لا اريد اي حرف يخرج خارج اطار الديزاين» — and on a 320-wide phone, with a
  // four-word name and a sentence-long note, in both themes.
  for (final double width in <double>[320, 360, 411]) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      for (final bool portal in <bool>[true, false]) {
        testWidgets('الإشعارات (${portal ? 'member' : 'admin'}) fit at '
            '${width.toInt()}px in ${mode.name}', (WidgetTester tester) async {
          applyAppTheme(mode);
          await _pump(
            tester,
            user: portal ? _member : _admin,
            portal: portal,
            width: width,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: 'something left the frame at ${width.toInt()}px',
          );
        });
      }
    }
  }
}
