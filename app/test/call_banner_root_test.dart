import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/call/domain/models.dart';
import 'package:family_app/features/call/presentation/call_ui.dart';
import 'package:family_app/features/call/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── اللافتة فوق التطبيق كلّه، لا داخل شاشةٍ منه ────────────────────────────
///
/// The banner moved out of [AppScaffold] and into `MaterialApp.builder`,
/// because the عديل portal is deliberately not an AppScaffold — so on the one
/// screen a member sits on, there was no banner AND no call poll at all. See
/// app.dart.
///
/// ⚠ AND THAT MOVE CHANGED WHAT IS ABOVE IT, WHICH IS THE WHOLE REASON THIS
///   FILE EXISTS. `call_ui_smoke_test` mounts the banner inside a `Scaffold`,
///   so it has always been tested with a Material ancestor, a DefaultTextStyle
///   and a theme in scope. `MaterialApp.builder` runs ABOVE the Navigator:
///   Localizations and Directionality are there, **a Scaffold is not** — and
///   the banner draws `IconButton`s, which throw «No Material widget found»
///   without one.
///
///   That failure would appear only when a call actually rang, on whatever
///   screen the man happened to be on, and would take the app down with it.
///   Exactly the shape of the FilledButton-in-a-Row bug this project already
///   paid for once.
CallView _call({bool mine = false, String status = 'ترن'}) =>
    CallView.fromJson(<String, dynamic>{
      'id': 1,
      'threadAdeelId': null,
      'callerName': 'المهدي',
      'mine': mine,
      'status': status,
      'startedAt': '2026-08-21T10:00:00Z',
      'answeredAt': null,
      'endedAt': null,
    });

class _Stub extends IncomingCall {
  _Stub(this._call);
  final CallView? _call;

  @override
  Future<CallView?> build() async => _call;
}

/// The real root: exactly what app.dart builds.
Future<void> _pumpRoot(WidgetTester tester, CallView? call) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        incomingCallProvider.overrideWith(() => _Stub(call)),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('ar'),
        localizationsDelegates: latinDigitDelegates(L.localizationsDelegates),
        supportedLocales: L.supportedLocales,
        // ⚠ THE BANNER ABOVE THE NAVIGATOR, WITH NO SCAFFOLD OVER IT — the
        //   shape app.dart actually ships. A `Scaffold` here would test the
        //   old arrangement and prove nothing about the new one.
        builder: (BuildContext context, Widget? child) => Column(
          children: <Widget>[
            const IncomingCallBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        ),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // ⚠ A PHONE WIDTH, for the same reason call_ui_smoke_test uses one: the
  //   banner's buttons are themed full-width, and a Row only fails when it has
  //   to share a real width.
  setUp(() {
    // 411 × 890 is an ordinary Android handset.
  });

  testWidgets('⚠ it renders at the app root, with no Scaffold above it', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 890 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpRoot(tester, _call());

    expect(tester.takeException(), isNull, reason: 'the banner threw at root');
    expect(find.textContaining('المهدي'), findsOneWidget);
  });

  testWidgets('and draws nothing at all when no call is live', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 890 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpRoot(tester, null);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('المهدي'), findsNothing);
    // ⚠ AND IT MUST OCCUPY NO HEIGHT. It now sits above EVERY screen including
    //   /login and /pending; a banner that reserved even a few pixels when
    //   silent would push the whole app down by them, on every screen, forever.
    expect(
      tester.getSize(find.byType(IncomingCallBanner)).height,
      0,
      reason: 'a silent banner must take no space at the app root',
    );
  });

  // ── ⚠ اسمُ المتصل: حجمُه مذكورٌ لا موروث ──────────────────────────────────
  //
  //   The banner's Text carried a weight and no SIZE, so it took whatever
  //   DefaultTextStyle happened to be in scope. Inside AppScaffold that was
  //   the Material body style; at the app root it is whatever
  //   MaterialApp.builder leaves above it — today about the same, tomorrow
  //   whatever the next change to that builder decides.
  //
  // ⚠ NOT A DIAGNOSIS OF THE ASSOCIATION'S «الاسم يظهر بشكل كبير جدا» — that
  //   was the NOTIFICATION's full-screen intent, and measuring this banner at
  //   the root is what ruled it out (14sp with and without the fix). See
  //   call_notification_shape_test. This assertion is what makes ruling it out
  //   possible NEXT time: a size that is stated can be read, and a size that
  //   is inherited can only be guessed at.
  //
  // ⚠ AND THE TWO TESTS ABOVE BOTH PASS THROUGH IT. «it renders» and «it takes
  //   no space when silent» are both true of a banner whose text is three
  //   times too big. A purely visual regression needs an assertion that reads
  //   the PIXELS.
  testWidgets('⚠ the caller name is body-sized, not the root fallback', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 890 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpRoot(tester, _call());

    final RichText name = tester.widget<RichText>(
      // ⚠ THE NAME'S OWN RichText — every Icon in the row is one too, so
      //   asking the banner for 'its' RichText finds five.
      find.descendant(
        of: find.textContaining('المهدي'),
        matching: find.byType(RichText),
      ),
    );
    final double? size = (name.text as TextSpan).style?.fontSize;

    expect(
      size,
      isNotNull,
      reason: 'the name must state its size, never inherit it at the root',
    );
    expect(
      size,
      lessThanOrEqualTo(16),
      reason:
          'the caller name rendered at $size — this banner sits above every '
          'Material in the app, so it must carry its own text style.',
    );

    // AND THE WHOLE BANNER STAYS A BANNER. One line of oversized text pushes
    // every screen in the app down by its height.
    expect(
      tester.getSize(find.byType(IncomingCallBanner)).height,
      lessThan(110),
      reason: 'a call banner is one row, not a header',
    );
  });

  // The other three silent states, at the root this time.
  testWidgets('nothing for a call I raised myself', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411 * 3, 890 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpRoot(tester, _call(mine: true));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('المهدي'), findsNothing);
  });

  testWidgets('nothing once the call has ended', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(411 * 3, 890 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await _pumpRoot(tester, _call(status: 'انتهت'));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('المهدي'), findsNothing);
  });
}
