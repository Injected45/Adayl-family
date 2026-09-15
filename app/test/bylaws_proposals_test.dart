import 'dart:convert';

import 'package:family_app/core/config/palette.dart';
import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/core/notify/notifier.dart';
import 'package:family_app/core/notify/notify_text.dart';
import 'package:family_app/core/router/destinations.dart';
import 'package:family_app/core/widgets/nav_pill_bar.dart';
import 'package:family_app/features/auth/domain/app_user.dart';
import 'package:family_app/features/auth/presentation/auth_controller.dart';
import 'package:family_app/features/bylaws/data/bylaws_repository.dart';
import 'package:family_app/features/bylaws/data/page_picker.dart';
import 'package:family_app/features/bylaws/domain/models.dart';
import 'package:family_app/features/bylaws/presentation/bylaws_screen.dart';
import 'package:family_app/features/bylaws/presentation/providers.dart';
import 'package:family_app/features/directory/presentation/portal_sections.dart';
import 'package:family_app/features/notifications/presentation/providers.dart';
import 'package:family_app/features/proposals/data/proposals_repository.dart';
import 'package:family_app/features/proposals/domain/models.dart';
import 'package:family_app/features/proposals/presentation/proposal_composer.dart';
import 'package:family_app/features/proposals/presentation/proposal_detail_screen.dart';
import 'package:family_app/features/proposals/presentation/proposals_screen.dart';
import 'package:family_app/features/proposals/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:family_app/l10n/app_localizations_ar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// قانون الجمعية ومقترحات المشتركين (15/09).
///
/// ⚠ WHO MAY DO WHAT IS PROVED IN POSTGRES, not here — 52 checks on a replica
///   before PATCH_20260915d was handed over: a member reads pages and cannot
///   add or delete one, a title of 21 letters is refused, an accepted proposal
///   cannot be edited or deleted even by the database owner, a rejected one is
///   gone for everyone. What this file pins is the SCREENS' half.
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

/// A real 1×1 PNG, so Image.memory decodes it.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _FakeBylaws implements BylawsRepository {
  _FakeBylaws(this.pages);
  List<BylawPage> pages;
  final List<(int, String)> added = <(int, String)>[];
  final List<int> deleted = <int>[];

  @override
  Future<List<BylawPage>> list() async => pages;
  @override
  Future<Uint8List> image(int id) async => _png;
  @override
  Future<void> add(Uint8List bytes, String mime) async =>
      added.add((bytes.length, mime));
  @override
  Future<void> delete(int id) async => deleted.add(id);
}

class _FakePicker extends PagePicker {
  const _FakePicker(this.files);
  final List<Uint8List> files;
  @override
  Future<List<Uint8List>> camera() async => files;
  @override
  Future<List<Uint8List>> device() async => files;
}

List<BylawPage> _pages(int n) => <BylawPage>[
  for (int i = 1; i <= n; i++)
    BylawPage(
      id: 40 + i,
      mime: 'image/png',
      sizeBytes: 68,
      createdAt: '2026-09-15T10:00:00Z',
    ),
];

class _FakeProposals implements ProposalsRepository {
  _FakeProposals(this.rows);
  List<Proposal> rows;
  final List<(String, String)> submitted = <(String, String)>[];
  final List<int> accepted = <int>[];
  final List<int> rejected = <int>[];

  @override
  Future<List<Proposal>> list() async => rows;
  @override
  Future<void> submit({required String title, required String body}) async =>
      submitted.add((title, body));
  @override
  Future<void> accept(int id) async => accepted.add(id);
  @override
  Future<void> reject(int id) async => rejected.add(id);
  @override
  Future<List<int>> waitingIds({int cap = 99}) async => <int>[
    for (final Proposal p in rows)
      if (!p.accepted) p.id,
  ]..sort((int a, int b) => b.compareTo(a));
  @override
  Future<Proposal?> byId(int id) async {
    for (final Proposal p in rows) {
      if (p.id == id) return p;
    }
    return null;
  }
}

const String _longBody =
    'أقترح أن تُخصَّص نسبةٌ ثابتة من اشتراك كلّ شهر لصندوق طوارئ مستقلّ، '
    'يُصرف منه على الحالات العاجلة دون انتظار اجتماع، على أن يُعرض ما صُرف منه '
    'على الجمعية العمومية في آخر كلّ سنة، وأن يتولّى أمين الصندوق متابعته.';

List<Proposal> _proposals() => <Proposal>[
  Proposal.fromJson(<String, dynamic>{
    'id': 7,
    'adeelId': 3,
    'adeelCode': 'A-03',
    'adeelName': 'عبدالرحمن محمد عبدالسلام الشيباني',
    'title': 'صندوق طوارئ مستقلّ',
    'body': _longBody,
    'status': 'pending',
    'createdAt': '2026-09-15T09:00:00Z',
  }),
  Proposal.fromJson(<String, dynamic>{
    'id': 5,
    'adeelId': 4,
    'adeelCode': 'A-04',
    'adeelName': 'ايمن صالح محمد صالح بلها',
    'title': 'رحلة عائلية',
    'body': 'رحلة لكلّ العائلات في الربيع.',
    'status': 'accepted',
    'createdAt': '2026-09-10T09:00:00Z',
    'decidedAt': '2026-09-11T09:00:00Z',
  }),
];

Future<void> _pump(
  WidgetTester tester, {
  required Widget home,
  required AppUser user,
  _FakeBylaws? bylaws,
  _FakeProposals? proposals,
  PagePicker picker = const _FakePicker(<Uint8List>[]),
  double width = 411,
  double height = 2400,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final _FakeBylaws b = bylaws ?? _FakeBylaws(_pages(2));
  final _FakeProposals p = proposals ?? _FakeProposals(_proposals());

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        authControllerProvider.overrideWith(() => _StubAuth(user)),
        bylawsRepositoryProvider.overrideWithValue(b),
        pagePickerProvider.overrideWithValue(picker),
        proposalsRepositoryProvider.overrideWithValue(p),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final L l = LAr();
  // The alert's words come from the ARB, filled before runApp in the app.
  setUpAll(() => NotifyText.fill(l));
  tearDown(() => applyAppTheme(AppThemeMode.light));

  group('what a page is', () {
    test('an image is known by its first bytes, never by its name', () {
      expect(imageMimeOf(_png), 'image/png');
      expect(
        imageMimeOf(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 0])),
        'image/jpeg',
      );
      expect(
        imageMimeOf(
          Uint8List.fromList(<int>[
            0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, //
            0x57, 0x45, 0x42, 0x50,
          ]),
        ),
        'image/webp',
      );
      expect(imageMimeOf(Uint8List.fromList(utf8.encode('%PDF-1.7'))), isNull);
      expect(imageMimeOf(Uint8List(0)), isNull);
    });

    test('the limit is the database’s three megabytes', () {
      expect(bylawMaxBytes, 3000000);
    });
  });

  group('قانون الجمعية — the admin', () {
    testWidgets('can photograph a page or pick them from the phone', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: const BylawsScreen(manage: true), user: _admin);
      expect(find.text(l.bylawsCamera), findsOneWidget);
      expect(find.text(l.bylawsFromDevice), findsOneWidget);
      expect(find.text(l.bylawsPageNumber(1)), findsOneWidget);
      expect(find.text(l.bylawsPageNumber(2)), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('uploads only real images within the limit, and says so', (
      WidgetTester tester,
    ) async {
      final _FakeBylaws repo = _FakeBylaws(_pages(0));
      await _pump(
        tester,
        home: const BylawsScreen(manage: true),
        user: _admin,
        bylaws: repo,
        picker: _FakePicker(<Uint8List>[
          _png,
          Uint8List.fromList(utf8.encode('%PDF-1.7 not a page')),
          Uint8List.fromList(<int>[
            0xFF,
            0xD8,
            0xFF,
            ...List<int>.filled(3000000, 0),
          ]),
        ]),
      );

      await tester.tap(find.text(l.bylawsFromDevice));
      await tester.pumpAndSettle();

      expect(repo.added, <(int, String)>[(_png.length, 'image/png')]);
      expect(find.text(l.bylawsAddedSomeRefused(1, 2)), findsOneWidget);
    });

    testWidgets('deleting asks first; cancelling deletes nothing', (
      WidgetTester tester,
    ) async {
      final _FakeBylaws repo = _FakeBylaws(_pages(2));
      await _pump(
        tester,
        home: const BylawsScreen(manage: true),
        user: _admin,
        bylaws: repo,
      );

      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pumpAndSettle();
      expect(find.text(l.bylawsDeleteTitle(2)), findsOneWidget);
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);

      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(l.bylawsDeleteConfirm),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.deleted, <int>[42]);
      expect(find.text(l.bylawsDeleted), findsOneWidget);
    });
  });

  group('قانون الجمعية — a member', () {
    testWidgets('sees the pages and nothing else: no button, number or hint', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: const BylawsScreen(), user: _member);

      expect(find.byType(BylawPageImage), findsNWidgets(2));
      expect(find.text(l.bylawsCamera), findsNothing);
      expect(find.text(l.bylawsFromDevice), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.text(l.bylawsPageNumber(1)), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      // «بدون ماتذكر ذلك في تلميح او ايحاء» — the screen's only words are its
      // title.
      final Iterable<String> words = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where((String s) => s.isNotEmpty);
      expect(words, <String>[l.bylawsTitle]);
    });

    testWidgets('a page opens on the whole screen to be read', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: const BylawsScreen(), user: _member);
      await tester.tap(find.byType(BylawPageImage).first);
      await tester.pumpAndSettle();
      expect(find.byType(BylawViewer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      // ⚠ ONE PAGE, NO SWIPE: on the emulator a quick swipe was taken by the
      //   zoom and the next page never came. See BylawViewer.
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('his «المزيد» opens the same pages, with no admin controls', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        home: Builder(
          builder: (BuildContext c) =>
              portalSectionPage(c, PortalSection.bylaws, 3),
        ),
        user: _member,
      );
      expect(find.byType(BylawsScreen), findsOneWidget);
      expect(find.text(l.bylawsCamera), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('and «إضافة مقترح» sits directly under «قانون الجمعية»', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        home: const Scaffold(
          body: SingleChildScrollView(child: PortalSectionMenu(adeelId: 3)),
        ),
        user: _member,
      );
      final double law = tester.getTopLeft(find.text(l.bylawsTitle)).dy;
      final double add = tester.getTopLeft(find.text(l.proposalAddTitle)).dy;
      final double fund = tester.getTopLeft(find.text(l.navCash)).dy;
      expect(law, greaterThan(fund));
      expect(add, greaterThan(law));
      expect(
        PortalSection.values.indexOf(PortalSection.proposal),
        PortalSection.values.indexOf(PortalSection.bylaws) + 1,
      );
    });
  });

  group('إضافة مقترح — a member', () {
    Widget composer() => Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[ProposalComposer()],
      ),
    );

    test('the title stops at twenty code points — Postgres’s count', () {
      const CodePointLimit limit = CodePointLimit(proposalTitleMax);
      final TextEditingValue cut = limit.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(text: 'ع' * 25),
      );
      expect(cut.text.runes.length, 20);
      // A letter with a mark is TWO code points, as char_length counts it.
      final TextEditingValue marked = limit.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(text: 'عَ' * 11),
      );
      expect(marked.text.runes.length, 20);
      expect(proposalTitleMax, 20);
    });

    testWidgets('a title of twenty-five letters becomes twenty', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: composer(), user: _member);
      await tester.enterText(find.byType(TextField).first, 'م' * 25);
      await tester.pump();
      final TextField title = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(title.controller!.text.runes.length, 20);
      expect(title.maxLength, 20);
    });

    testWidgets('an empty title or text is refused before anything is sent', (
      WidgetTester tester,
    ) async {
      final _FakeProposals repo = _FakeProposals(<Proposal>[]);
      await _pump(tester, home: composer(), user: _member, proposals: repo);

      await tester.tap(find.text(l.proposalSend));
      await tester.pumpAndSettle();
      expect(find.text(l.proposalTitleEmpty), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'صيانة المقر');
      await tester.tap(find.text(l.proposalSend));
      await tester.pumpAndSettle();
      expect(find.text(l.proposalBodyEmpty), findsWidgets);
      expect(repo.submitted, isEmpty);
    });

    testWidgets('sent, the box empties and says so', (
      WidgetTester tester,
    ) async {
      final _FakeProposals repo = _FakeProposals(<Proposal>[]);
      await _pump(tester, home: composer(), user: _member, proposals: repo);

      await tester.enterText(find.byType(TextField).first, 'صيانة المقر');
      await tester.enterText(find.byType(TextField).last, 'قبل الشتاء');
      await tester.tap(find.text(l.proposalSend));
      await tester.pumpAndSettle();

      expect(repo.submitted, <(String, String)>[('صيانة المقر', 'قبل الشتاء')]);
      expect(find.text(l.proposalSent), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
    });

    testWidgets('his own proposals list by title with where each stands', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: composer(), user: _member);
      expect(find.text(l.myProposalsHeading), findsOneWidget);
      expect(find.text('صندوق طوارئ مستقلّ'), findsOneWidget);
      expect(find.text(l.proposalPending), findsOneWidget);
      expect(find.text(l.proposalAccepted), findsOneWidget);
      expect(find.textContaining('نسبةٌ ثابتة'), findsNothing);

      await tester.tap(find.text('صندوق طوارئ مستقلّ'));
      await tester.pumpAndSettle();
      expect(find.text(_longBody), findsOneWidget);
      // He decides nothing.
      expect(find.text(l.proposalAccept), findsNothing);
      expect(find.text(l.proposalReject), findsNothing);
    });
  });

  group('مقترحات المشتركين — the admin', () {
    testWidgets('small cards: whose and what title, waiting first', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: const ProposalsScreen(), user: _admin);

      expect(find.text(l.proposalsWaitingHeading(1)), findsOneWidget);
      expect(find.text(l.proposalsAcceptedHeading(1)), findsOneWidget);
      expect(find.text('عبدالرحمن محمد عبدالسلام الشيباني'), findsOneWidget);
      expect(find.text('صندوق طوارئ مستقلّ'), findsOneWidget);
      expect(find.textContaining('نسبةٌ ثابتة'), findsNothing);
      expect(
        tester.getTopLeft(find.text('صندوق طوارئ مستقلّ')).dy,
        lessThan(tester.getTopLeft(find.text('رحلة عائلية')).dy),
      );
    });

    testWidgets(
      'a waiting proposal opens with «قبول» and «رفض»; accept keeps it',
      (WidgetTester tester) async {
        final _FakeProposals repo = _FakeProposals(_proposals());
        await _pump(
          tester,
          home: const ProposalsScreen(),
          user: _admin,
          proposals: repo,
        );

        await tester.tap(find.text('صندوق طوارئ مستقلّ'));
        await tester.pumpAndSettle();
        expect(find.text(_longBody), findsOneWidget);
        expect(
          find.text('عبدالرحمن محمد عبدالسلام الشيباني · A-03'),
          findsOneWidget,
        );

        await tester.tap(find.text(l.proposalAccept));
        await tester.pumpAndSettle();
        expect(repo.accepted, <int>[7]);
        expect(find.byType(ProposalDetailScreen), findsNothing);
        expect(find.text(l.proposalAcceptedDone), findsOneWidget);
      },
    );

    testWidgets('⚠ reject asks first, then deletes', (
      WidgetTester tester,
    ) async {
      final _FakeProposals repo = _FakeProposals(_proposals());
      await _pump(
        tester,
        home: const ProposalsScreen(),
        user: _admin,
        proposals: repo,
      );
      await tester.tap(find.text('صندوق طوارئ مستقلّ'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l.proposalReject));
      await tester.pumpAndSettle();
      expect(find.text(l.proposalRejectTitle), findsOneWidget);
      await tester.tap(find.text(l.cancel));
      await tester.pumpAndSettle();
      expect(repo.rejected, isEmpty);

      await tester.tap(find.text(l.proposalReject));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(l.proposalReject),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.rejected, <int>[7]);
      expect(find.byType(ProposalDetailScreen), findsNothing);
      expect(find.text(l.proposalRejectedDone), findsOneWidget);
    });

    testWidgets('an accepted proposal is for reading only: no decision left', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: const ProposalsScreen(), user: _admin);
      await tester.tap(find.text('رحلة عائلية'));
      await tester.pumpAndSettle();
      expect(find.text('رحلة لكلّ العائلات في الربيع.'), findsOneWidget);
      expect(find.text(l.proposalAccept), findsNothing);
      expect(find.text(l.proposalReject), findsNothing);
      expect(find.text(l.proposalAccepted), findsOneWidget);
    });

    testWidgets('left alone thirty seconds it closes; a touch starts again', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: const ProposalsScreen(), user: _admin);
      await tester.tap(find.text('رحلة عائلية'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 20));
      await tester.tap(find.text('رحلة لكلّ العائلات في الربيع.'));
      await tester.pump(const Duration(seconds: 20));
      expect(find.byType(ProposalDetailScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.byType(ProposalDetailScreen), findsNothing);
      expect(find.byType(ProposalsScreen), findsOneWidget);
    });

    testWidgets('«رجوع» closes it at once', (WidgetTester tester) async {
      await _pump(tester, home: const ProposalsScreen(), user: _admin);
      await tester.tap(find.text('رحلة عائلية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.backAction));
      await tester.pumpAndSettle();
      expect(find.byType(ProposalDetailScreen), findsNothing);
    });

    testWidgets('nothing sent yet says so', (WidgetTester tester) async {
      await _pump(
        tester,
        home: const ProposalsScreen(),
        user: _admin,
        proposals: _FakeProposals(<Proposal>[]),
      );
      expect(find.text(l.proposalsEmpty), findsOneWidget);
    });
  });

  // ── «مقترح جديد من فلان» — the admin is told ────────────────────────────
  group('a new proposal reaches the admin', () {
    test('by the newest id: first reading arms, a newer id announces', () {
      expect(
        decideProposalAlert(
          armed: false,
          lastSeenId: 0,
          newestId: 9,
          onScreen: false,
        ),
        ProposalAlert.arm,
      );
      expect(
        decideProposalAlert(
          armed: true,
          lastSeenId: 7,
          newestId: 9,
          onScreen: false,
        ),
        ProposalAlert.announce,
      );
      expect(
        decideProposalAlert(
          armed: true,
          lastSeenId: 9,
          newestId: 9,
          onScreen: false,
        ),
        ProposalAlert.none,
      );
      // ⚠ One decided and one arrived: the count is unchanged, the id is not.
      expect(
        decideProposalAlert(
          armed: true,
          lastSeenId: 9,
          newestId: 10,
          onScreen: false,
        ),
        ProposalAlert.announce,
      );
      expect(
        decideProposalAlert(
          armed: true,
          lastSeenId: 7,
          newestId: 9,
          onScreen: true,
        ),
        ProposalAlert.none,
        reason: 'he is looking at the tab',
      );
    });

    test('the phone alert opens the tab it names, and nothing else', () {
      expect(AppNotifier.routePayload('/proposals'), 'route:/proposals');
      expect(AppNotifier.routeFromPayload('route:/proposals'), '/proposals');
      expect(AppNotifier.routeFromPayload('notice:4'), isNull);
      expect(AppNotifier.routeFromPayload('route:'), isNull);
      expect(AppNotifier.routeFromPayload(null), isNull);
    });

    Future<ProviderContainer> watching(
      WidgetTester tester,
      _FakeProposals repo,
      AppUser user,
    ) async {
      final ProviderContainer c = ProviderContainer(
        overrides: <Override>[
          authControllerProvider.overrideWith(() => _StubAuth(user)),
          proposalsRepositoryProvider.overrideWithValue(repo),
        ],
      );
      await c.read(proposalsWaitingProvider.future);
      return c;
    }

    Proposal newOne() => Proposal.fromJson(<String, dynamic>{
      'id': 12,
      'adeelId': 6,
      'adeelCode': 'A-06',
      'adeelName': 'سالم صالح الشيخي',
      'title': 'ملعب للأطفال',
      'body': 'نص',
      'status': 'pending',
      'createdAt': '2026-09-15T10:00:00Z',
    });

    testWidgets('in the app: a banner naming the member, opening the tab', (
      WidgetTester tester,
    ) async {
      final _FakeProposals repo = _FakeProposals(_proposals());
      final ProviderContainer c = await watching(tester, repo, _admin);
      expect(c.read(proposalsWaitingProvider).valueOrNull, 1);
      // What was waiting at launch is not news.
      expect(c.read(noticePeekProvider), isNull);

      repo.rows = <Proposal>[newOne(), ...repo.rows];
      await c.read(proposalsWaitingProvider.notifier).refresh();
      await tester.pump();

      final NoticePeek? peek = c.read(noticePeekProvider);
      expect(peek?.notice.title, l.proposalNewFrom('سالم صالح الشيخي'));
      expect(peek?.notice.body, 'ملعب للأطفال');
      expect(peek?.route, AppRoutes.proposals);
      expect(c.read(proposalsWaitingProvider).valueOrNull, 2);
      // ⚠ Disposed in the body: its ten-second poll and the banner's clock
      //   must be gone before the test ends, or the binding reports a timer.
      c.dispose();
    });

    testWidgets('nothing is announced while he is on the tab', (
      WidgetTester tester,
    ) async {
      final _FakeProposals repo = _FakeProposals(_proposals());
      final ProviderContainer c = await watching(tester, repo, _admin);
      c.read(proposalsScreenOpenProvider.notifier).state = true;
      repo.rows = <Proposal>[newOne(), ...repo.rows];
      await c.read(proposalsWaitingProvider.notifier).refresh();
      expect(c.read(noticePeekProvider), isNull);
      expect(c.read(proposalsWaitingProvider).valueOrNull, 2);
      c.dispose();
    });

    testWidgets('a member is never counted or told', (
      WidgetTester tester,
    ) async {
      final _FakeProposals repo = _FakeProposals(_proposals());
      final ProviderContainer c = await watching(tester, repo, _member);
      repo.rows = <Proposal>[newOne(), ...repo.rows];
      await c.read(proposalsWaitingProvider.notifier).refresh();
      expect(c.read(proposalsWaitingProvider).valueOrNull, 0);
      expect(c.read(noticePeekProvider), isNull);
      c.dispose();
    });

    testWidgets('the count rides «المزيد» and the tab’s tile', (
      WidgetTester tester,
    ) async {
      await _pump(tester, home: const ProposalsScreen(), user: _admin);
      // One waiting in the fixture.
      final Finder pill = find.ancestor(
        of: find.text('1'),
        matching: find.byType(NavPillBar),
      );
      expect(pill, findsOneWidget);

      await tester.tap(find.text(l.navMore));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget,
      );
    });
  });

  // ── «المزيد» عند الأدمن، على هاتفٍ صغير ─────────────────────────────────
  // ⚠ ELEVEN TILES NOW, FOUR ROWS, and a bottom sheet is capped at
  //   nine-sixteenths of the screen — 360 pixels on a 640-high phone.
  for (final AppThemeMode mode in AppThemeMode.values) {
    testWidgets('the admin «المزيد» holds both new items at 360×640 in '
        '${mode.name}', (WidgetTester tester) async {
      applyAppTheme(mode);
      await _pump(
        tester,
        home: const ProposalsScreen(),
        user: _admin,
        width: 360,
        height: 640,
      );
      await tester.tap(find.text(l.navMore));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(l.bylawsTitle), findsOneWidget);
      expect(find.text(l.proposalsTitle), findsWidgets);
    });
  }

  // «لا اريد اي حرف يخرج خارج اطار الديزاين».
  for (final double width in <double>[320, 411]) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      final String tag = '${width.toInt()}px ${mode.name}';

      testWidgets('bylaws (admin and member) fit at $tag', (
        WidgetTester tester,
      ) async {
        applyAppTheme(mode);
        await _pump(
          tester,
          home: const BylawsScreen(manage: true),
          user: _admin,
          width: width,
          height: 800,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          home: const BylawsScreen(),
          user: _member,
          width: width,
          height: 800,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('proposals list, page and box fit at $tag', (
        WidgetTester tester,
      ) async {
        applyAppTheme(mode);
        await _pump(
          tester,
          home: const ProposalsScreen(),
          user: _admin,
          width: width,
          height: 800,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('صندوق طوارئ مستقلّ'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text(l.backAction),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text(l.backAction));
        await tester.pumpAndSettle();

        await _pump(
          tester,
          home: Builder(
            builder: (BuildContext c) =>
                portalSectionPage(c, PortalSection.proposal, 3),
          ),
          user: _member,
          width: width,
          height: 800,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
