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

  // The other three silent states, at the root this time.
  testWidgets('nothing for a call I raised myself', (WidgetTester tester) async {
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
