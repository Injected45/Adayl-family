import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/notify/notifier.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/notifications/data/notice_read_state.dart';
import 'package:family_app/features/notifications/data/notifications_repository.dart';
import 'package:family_app/features/notifications/domain/models.dart';
import 'package:family_app/features/notifications/presentation/notice_detail_screen.dart';
import 'package:family_app/features/notifications/presentation/notice_peek.dart';
import 'package:family_app/features/notifications/presentation/notifications_screen.dart';
import 'package:family_app/features/notifications/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// الإشعار على الشاشة عشرين ثانية، والتفاصيل تُغلق بعد ثلاثين ثانية سكون (15/09).
///
/// «عند ارسال رسالة من الادمن او وصول اشعار … يظهر على شاشة الهاتف الرئيسية
/// ويضل 20 ثانية على ان يكون بيه ايضاح لمحتوى الرساله واذا تم الضغط على الاشعار
/// قبل ان يختفي يفتح محتوي الرساله … اي اشعار موجود في تبويب الاشعار اجعله يظهر
/// في حقل يظهر العنوان فقط وعند الضغط عليه يظهر تفاصيل الاشعار … ويرجع كما كان
/// بعدة فتره 30 ثانية اذا ترك ساكن. او ارجاعه فورا من قبل المشترك».
///
/// ⚠ NOT ONE FINANCIAL PATH IS TOUCHED. Everything here reads `v_notifications`
///   rows the database already wrote; the only write is the read mark on the
///   handset.
class _StubAuth extends AuthController {
  _StubAuth(this._user);
  final AppUser _user;
  @override
  AuthState build() => AuthState(stage: AuthStage.signedIn, user: _user);
}

const AppUser _member = AppUser(
  id: '00000000-0000-0000-0000-0000000000b1',
  email: 'adeel@fam.test',
  displayName: 'هيثم مفتاح عبدالعظيم',
  role: AppRole.viewer,
  status: AccountStatus.approved,
  adeelId: 3,
);

class _StubUnread extends NoticesUnread {
  final List<int> readOnes = <int>[];
  @override
  Future<int> build() async => 1;
  @override
  Future<void> readOne(int id) async => readOnes.add(id);
  @override
  Future<void> markSeen(int newestId) async {}
}

class _FakeReads extends NoticeReadState {
  _FakeReads() : super(const FlutterSecureStorage());
  @override
  Future<int> lastSeen(String userId) async => 0;
  @override
  Future<void> markSeen(String userId, int id) async {}
}

class _FakeRepo implements NotificationsRepository {
  final List<int> asked = <int>[];

  @override
  Future<AppNotice?> byId(int id) async {
    asked.add(id);
    for (final AppNotice n in _notices) {
      if (n.id == id) return n;
    }
    return null;
  }

  @override
  Future<List<AppNotice>> list({int limit = 200}) async => _notices;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const String _longBody =
    'اجتماع الجمعية العمومية يوم الجمعة القادم بعد صلاة العصر في بيت الحاج '
    'عبدالرحمن محمد عبدالسلام الشيباني، والحضور مهمّ لجميع الأعضاء، ومن تعذّر '
    'عليه الحضور فليبلغ أمين الصندوق قبل الموعد بيوم على الأقل، وجزاكم الله '
    'خيرًا على تعاونكم الدائم مع الجمعية';

final List<AppNotice> _notices = <AppNotice>[
  AppNotice.fromJson(<String, dynamic>{
    'id': 12,
    'audience': 'all',
    'kind': 'broadcast',
    'title': 'رسالة من الإدارة بخصوص اجتماع الجمعية العمومية القادم للأعضاء',
    'body': _longBody,
    'createdAt': '2026-09-15T10:15:00Z',
  }),
  AppNotice.fromJson(<String, dynamic>{
    'id': 11,
    'audience': 'member',
    'kind': 'payment',
    'title': 'تم تسجيل سداد',
    'body': 'استُلم منك 12,345.00 د.ل — إيصال رقم PAY-201.',
    'ref': 'PAY-201',
    'createdAt': '2026-09-15T09:00:00Z',
    'adeelCode': 'A-03',
    'adeelName': 'هيثم مفتاح عبدالعظيم',
  }),
];

class _Host {
  _Host(this.container, this.router, this.unread, this.repo);
  final ProviderContainer container;
  final GoRouter router;
  final _StubUnread unread;
  final _FakeRepo repo;

  NoticePeekController get peek => container.read(noticePeekProvider.notifier);
}

Future<_Host> _pump(
  WidgetTester tester, {
  double width = 411,
  String at = AppRoutes.myDues,
  AppUser user = _member,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final _StubUnread unread = _StubUnread();
  final _FakeRepo repo = _FakeRepo();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      authControllerProvider.overrideWith(() => _StubAuth(user)),
      noticesUnreadProvider.overrideWith(() => unread),
      noticeReadStateProvider.overrideWithValue(_FakeReads()),
      notificationsRepositoryProvider.overrideWithValue(repo),
      noticesProvider.overrideWith((Ref ref) async => _notices),
    ],
  );
  addTearDown(container.dispose);

  final GoRouter router = GoRouter(
    initialLocation: at,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.myDues,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('portal-home'))),
      ),
      GoRoute(
        path: AppRoutes.pending,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('pending-home'))),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('admin-home'))),
      ),
      GoRoute(
        path: AppRoutes.proposals,
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('proposals-home'))),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => NoticePeekHost(
          router: router,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Host(container, router, unread, repo);
}

void main() {
  final L l = LAr();
  tearDown(() {
    applyAppTheme(AppThemeMode.light);
    AppNotifier.tappedNotice.value = null;
    AppNotifier.tappedRoute.value = null;
  });

  group('the phone notification', () {
    test('stays twenty seconds, then lives only on the tab', () {
      final AndroidNotificationDetails d = AppNotifier.noticeDetails;
      expect(d.timeoutAfter, 20000);
      expect(AppNotifier.noticeVisibleFor, const Duration(seconds: 20));
      // HIGH is the level at which Android pops it over the screen; the
      // channel id is the one phones already hold, so nothing is re-created.
      expect(d.importance, Importance.high);
      expect(d.channelId, 'association_notices');
    });

    test('carries the notice it is about, and nothing else parses as one', () {
      expect(AppNotifier.noticePayload(42), 'notice:42');
      expect(AppNotifier.noticeIdFromPayload('notice:42'), 42);
      expect(AppNotifier.noticeIdFromPayload(null), isNull);
      expect(AppNotifier.noticeIdFromPayload(''), isNull);
      expect(AppNotifier.noticeIdFromPayload('call:7'), isNull);
      expect(AppNotifier.noticeIdFromPayload('notice:'), isNull);
      expect(AppNotifier.noticeIdFromPayload('notice:0'), isNull);
      expect(AppNotifier.noticeIdFromPayload('notice:-3'), isNull);
    });

    test('in front → the app banner; away, or no notice → the phone', () {
      expect(
        decideNoticeDelivery(foreground: true, haveNotice: true),
        NoticeDelivery.banner,
      );
      expect(
        decideNoticeDelivery(foreground: false, haveNotice: true),
        NoticeDelivery.phone,
      );
      expect(
        decideNoticeDelivery(foreground: true, haveNotice: false),
        NoticeDelivery.phone,
        reason: 'a banner needs the notice; the generic alert still goes out',
      );
    });
  });

  group('the banner clock', () {
    test('twenty seconds, and a newer notice starts them again', () {
      fakeAsync((FakeAsync async) {
        final ProviderContainer c = ProviderContainer();
        final NoticePeekController peek = c.read(noticePeekProvider.notifier);

        peek.show(_notices[1]);
        expect(c.read(noticePeekProvider)?.notice.id, 11);
        async.elapse(const Duration(seconds: 10));
        peek.show(_notices[0], more: 1);
        async.elapse(const Duration(seconds: 19));
        expect(c.read(noticePeekProvider)?.notice.id, 12);
        expect(c.read(noticePeekProvider)?.more, 1);
        async.elapse(const Duration(seconds: 1));
        expect(c.read(noticePeekProvider), isNull);

        peek.show(_notices[1]);
        peek.dismiss();
        expect(c.read(noticePeekProvider), isNull);
        c.dispose();
      });
    });
  });

  group('over every screen', () {
    testWidgets('shows the title and the sentence, then goes at 20 s', (
      WidgetTester tester,
    ) async {
      final _Host h = await _pump(tester);
      h.peek.show(_notices[1], more: 2);
      await tester.pumpAndSettle();

      expect(find.text('تم تسجيل سداد'), findsOneWidget);
      expect(find.textContaining('12,345.00'), findsOneWidget);
      expect(find.text(l.noticesMoreWaiting(2)), findsOneWidget);
      // A layer, not a row: the screen beneath did not move.
      expect(find.text('portal-home'), findsOneWidget);

      await tester.pump(const Duration(seconds: 19));
      expect(find.text('تم تسجيل سداد'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('تم تسجيل سداد'), findsNothing);
    });

    testWidgets('✕ puts it away at once', (WidgetTester tester) async {
      final _Host h = await _pump(tester);
      h.peek.show(_notices[1]);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('تم تسجيل سداد'), findsNothing);
      expect(find.text(l.noticeDetailTitle), findsNothing);
    });

    testWidgets('a tap opens the whole notice, full screen', (
      WidgetTester tester,
    ) async {
      final _Host h = await _pump(tester);
      h.peek.show(_notices[0]);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NoticePeekBanner));
      await tester.pumpAndSettle();

      expect(find.byType(NoticeDetailScreen), findsOneWidget);
      expect(find.text(l.noticeDetailTitle), findsOneWidget);
      expect(find.text(_longBody), findsOneWidget);
      expect(find.byType(NoticePeekBanner), findsNothing);
      expect(h.unread.readOnes, <int>[12]);
    });
  });

  group('the detail page', () {
    Future<void> openDetail(WidgetTester tester, _Host h) async {
      h.peek.show(_notices[1]);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NoticePeekBanner));
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsOneWidget);
    }

    testWidgets('left alone for thirty seconds, it goes back', (
      WidgetTester tester,
    ) async {
      final _Host h = await _pump(tester);
      await openDetail(tester, h);

      await tester.pump(const Duration(seconds: 29));
      expect(find.byType(NoticeDetailScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsNothing);
      expect(find.text('portal-home'), findsOneWidget);
    });

    testWidgets('a touch starts the thirty seconds again', (
      WidgetTester tester,
    ) async {
      final _Host h = await _pump(tester);
      await openDetail(tester, h);

      await tester.pump(const Duration(seconds: 20));
      await tester.tap(find.textContaining('12,345.00'));
      await tester.pump(const Duration(seconds: 20));
      expect(
        find.byType(NoticeDetailScreen),
        findsOneWidget,
        reason: 'forty seconds open, but only twenty since he touched it',
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsNothing);
    });

    testWidgets('«رجوع» goes back at once', (WidgetTester tester) async {
      final _Host h = await _pump(tester);
      await openDetail(tester, h);
      await tester.tap(find.text(l.backAction));
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsNothing);
      expect(find.text('portal-home'), findsOneWidget);
    });

    testWidgets('from the tab: a title-only row, and the same page', (
      WidgetTester tester,
    ) async {
      final _Host h = await _pump(tester);
      final NavigatorState nav =
          h.router.routerDelegate.navigatorKey.currentState!;
      unawaited(
        nav.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const NotificationsScreen(portal: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('تم تسجيل سداد'), findsOneWidget);
      expect(find.textContaining('12,345.00'), findsNothing);

      await tester.tap(find.text('تم تسجيل سداد'));
      await tester.pumpAndSettle();
      expect(find.textContaining('12,345.00'), findsOneWidget);

      await tester.pump(NoticeDetailScreen.idleFor);
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsNothing);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(h.container.read(noticesScreenOpenProvider), isTrue);

      // ⚠ And out of the tab. Its dispose() wrote a provider while the tree
      //   was locked and asserted — found here, once a notice's page began
      //   returning him to the tab.
      nav.pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('portal-home'), findsOneWidget);
      expect(h.container.read(noticesScreenOpenProvider), isFalse);
    });
  });

  group('a tap on the phone', () {
    testWidgets('opens that notice', (WidgetTester tester) async {
      final _Host h = await _pump(tester);
      AppNotifier.tappedNotice.value = 11;
      await tester.pumpAndSettle();

      expect(h.repo.asked, <int>[11]);
      expect(find.byType(NoticeDetailScreen), findsOneWidget);
      expect(find.textContaining('12,345.00'), findsOneWidget);
      expect(AppNotifier.tappedNotice.value, isNull);
      expect(h.unread.readOnes, <int>[11]);
    });

    testWidgets('⚠ waits until he is on his own screens', (
      WidgetTester tester,
    ) async {
      final _Host h = await _pump(tester, at: AppRoutes.pending);
      AppNotifier.tappedNotice.value = 11;
      await tester.pumpAndSettle();

      expect(find.byType(NoticeDetailScreen), findsNothing);
      expect(AppNotifier.tappedNotice.value, 11, reason: 'still waiting');

      h.router.go(AppRoutes.myDues);
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsOneWidget);
      expect(AppNotifier.tappedNotice.value, isNull);
    });

    testWidgets('a revoked key opens nothing', (WidgetTester tester) async {
      await _pump(
        tester,
        user: const AppUser(
          id: '00000000-0000-0000-0000-0000000000b1',
          email: 'adeel@fam.test',
          displayName: 'هيثم مفتاح عبدالعظيم',
          role: AppRole.viewer,
          status: AccountStatus.approved,
          adeelId: 3,
          deviceLocked: true,
        ),
      );
      AppNotifier.tappedNotice.value = 11;
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsNothing);
    });

    testWidgets('a notice that cannot be read opens the tab instead', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      AppNotifier.tappedNotice.value = 999;
      await tester.pumpAndSettle();
      expect(find.byType(NoticeDetailScreen), findsNothing);
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  });

  // ── مقترح جديد: عند الأدمن تفتح اللافتةُ والإشعارُ تبويبَ المقترحات ─────────
  group('a new proposal, on the admin’s phone', () {
    const AppUser admin = AppUser(
      id: '00000000-0000-0000-0000-0000000000f1',
      email: 'admin@fam.test',
      displayName: 'المهدي',
      role: AppRole.admin,
      status: AccountStatus.approved,
    );

    testWidgets('the banner opens «مقترحات المشتركين»', (
      WidgetTester tester,
    ) async {
      final _Host h = await _pump(tester, at: AppRoutes.home, user: admin);
      h.peek.show(
        AppNotice(
          id: -12,
          audience: 'staff',
          kind: NoticeKind.proposal,
          title: 'مقترح جديد من سالم صالح الشيخي',
          body: 'ملعب للأطفال',
          createdAt: '2026-09-15T10:00:00Z',
        ),
        route: AppRoutes.proposals,
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);

      await tester.tap(find.byType(NoticePeekBanner));
      await tester.pumpAndSettle();
      expect(find.text('proposals-home'), findsOneWidget);
      expect(find.byType(NoticeDetailScreen), findsNothing);
      expect(find.byType(NoticePeekBanner), findsNothing);
      expect(h.unread.readOnes, isEmpty, reason: 'not a member notice');
    });

    testWidgets('a tap on the phone alert opens it too', (
      WidgetTester tester,
    ) async {
      await _pump(tester, at: AppRoutes.home, user: admin);
      AppNotifier.tappedRoute.value = AppRoutes.proposals;
      await tester.pumpAndSettle();
      expect(find.text('proposals-home'), findsOneWidget);
      expect(AppNotifier.tappedRoute.value, isNull);
    });

    testWidgets('⚠ but never for a member', (WidgetTester tester) async {
      await _pump(tester);
      AppNotifier.tappedRoute.value = AppRoutes.proposals;
      await tester.pumpAndSettle();
      expect(find.text('portal-home'), findsOneWidget);
      expect(find.text('proposals-home'), findsNothing);
    });
  });

  // «لا اريد اي حرف يخرج خارج اطار الديزاين».
  for (final double width in <double>[320, 411]) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      testWidgets('banner and page fit at ${width.toInt()}px in ${mode.name}', (
        WidgetTester tester,
      ) async {
        applyAppTheme(mode);
        final _Host h = await _pump(tester, width: width);
        h.peek.show(_notices[0], more: 12);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.byType(NoticePeekBanner));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The whole sentence, and «رجوع» at its end, reachable by scrolling.
        await tester.scrollUntilVisible(
          find.text(l.backAction),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text(l.backAction));
        await tester.pumpAndSettle();
        expect(find.byType(NoticeDetailScreen), findsNothing);
      });
    }
  }
}
