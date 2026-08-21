import 'package:family_app/core/config/theme.dart';
import 'package:family_app/core/l10n/latin_digit_localizations.dart';
import 'package:family_app/features/call/domain/models.dart';
import 'package:family_app/features/call/presentation/call_ui.dart';
import 'package:family_app/features/call/presentation/providers.dart';
import 'package:family_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── شريط «فلان يتصل» — أرخص اختبار وأكثره مردوداً ──────────────────────────
///
/// This banner is mounted inside [AppScaffold], which every screen in the app
/// builds — staff and portal alike. A widget that throws on build there takes
/// EVERY SCREEN down with it, and nothing else in the suite would have caught
/// it: the call feature has no other test that renders anything.
///
/// ⚠ AND ITS FOUR SILENT STATES ARE THE POINT. It must draw NOTHING when there
///   is no call, when the call is mine, when I am already on it, and when the
///   call is no longer ringing. Each of those is a separate `if`, and getting
///   any one wrong puts a permanent «فلان يتصل» band across the top of the app.
CallView _call({
  required bool mine,
  String status = 'ترن',
  String name = 'المهدي',
}) => CallView.fromJson(<String, dynamic>{
  'id': 1,
  'threadAdeelId': null,
  'callerName': name,
  'mine': mine,
  'status': status,
  'startedAt': '2026-08-21T10:00:00Z',
  'answeredAt': null,
  'endedAt': null,
});

Future<void> _pump(WidgetTester tester, CallView? call) async {
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
        // ⚠ A PHONE-WIDTH BOX, not the 800px test surface. The banner sits in
        //   a Row and its buttons are themed FULL WIDTH; the bug this test
        //   caught only shows when the Row has to share a real phone width.
        home: const Scaffold(
          body: SizedBox(width: 411, child: IncomingCallBanner()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Stub extends IncomingCall {
  _Stub(this._call);
  final CallView? _call;

  @override
  Future<CallView?> build() async => _call;
}

void main() {
  testWidgets('a ringing call from somebody else is announced by name', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _call(mine: false));

    expect(find.textContaining('المهدي'), findsOneWidget);
    expect(find.byIcon(Icons.phone_callback), findsOneWidget);
  });

  testWidgets('⚠ nothing at all when there is no call', (
    WidgetTester tester,
  ) async {
    await _pump(tester, null);
    expect(find.byIcon(Icons.phone_callback), findsNothing);
  });

  // ⚠ A MAN MUST NOT BE OFFERED HIS OWN CALL. He is already in the sheet that
  //   raised it; a banner underneath saying he is calling would be the app
  //   ringing itself.
  testWidgets('⚠ nor for a call I raised myself', (WidgetTester tester) async {
    await _pump(tester, _call(mine: true));
    expect(find.byIcon(Icons.phone_callback), findsNothing);
  });

  // ⚠ AND NOT ONCE IT HAS STOPPED RINGING. v_calls turns a «ترن» older than
  //   sixty seconds into «فائتة» on the server, so this is the state a handset
  //   sees when nobody answered — and a banner offering to answer it would
  //   open a call that has already gone.
  testWidgets('⚠ nor for one that is over', (WidgetTester tester) async {
    await _pump(tester, _call(mine: false, status: 'فائتة'));
    expect(find.byIcon(Icons.phone_callback), findsNothing);

    await _pump(tester, _call(mine: false, status: 'انتهت'));
    expect(find.byIcon(Icons.phone_callback), findsNothing);
  });

  // ⚠ BUT A CALL IN PROGRESS IS OFFERED. المجلس is a group call that stays
  //   live for as long as people are on it, so a man who opens the app five
  //   minutes in must still be able to join — a banner that showed only the
  //   first sixty seconds would make it a call you can catch only at the
  //   start.
  //
  // ⚠ Safe only because v_calls now ENDS a «جارية» call whose seats are all
  //   empty. Before PATCH_20260821i an abandoned call stayed live forever, and
  //   this banner would have offered it for ever after.
  testWidgets('⚠ and a live call IS offered, so المجلس can be joined late', (
    WidgetTester tester,
  ) async {
    await _pump(tester, _call(mine: false, status: 'جارية'));
    expect(find.byIcon(Icons.phone_callback), findsOneWidget);
  });
}
