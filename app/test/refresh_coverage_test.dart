import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EVERY read is in refreshAll, and a new one cannot quietly stay out.
///
/// ── WHAT THIS COSTS WHEN IT IS WRONG ────────────────────────────────────────
/// A voucher for 150 was recorded for a member. The admin saw it in الصندوق; the
/// member's «مصروفات للمشترك» stayed empty — through the refresh button, through
/// the automatic refresh, and through closing and reopening the screen. Four
/// read-only probes were written against the live database and every one came
/// back healthy, because the database WAS healthy: `api_adeel_aid` returned his
/// five vouchers and the right total the whole time.
///
/// `adeelAidProvider` is a `.family` and not autoDispose, so once it had
/// answered «no vouchers» it went on answering that for the life of the app —
/// and it was not in refreshAll, so nothing ever threw the answer away. The bug
/// was one missing line, and it looked exactly like a database fault.
///
/// ── WHY A SOURCE SCAN AND NOT A UNIT TEST ───────────────────────────────────
/// The failure is a provider that EXISTS and is not mentioned. Nothing can
/// observe that at runtime — there is no list of "all providers" to compare
/// against — so the check has to read the files, exactly as the two custom lints
/// in tool/ do.
void main() {
  /// Providers that are deliberately NOT refreshed, each for a stated reason.
  ///
  /// ⚠ ADDING A NAME HERE IS A DECISION. The whole point of the test is that
  ///   silence is not an option: a provider is either thrown away with the rest
  ///   or it is written down here with why.
  const Map<String, String> exempt = <String, String>{
    // Repositories. They hold a client, not an answer — invalidating one would
    // rebuild the object and change nothing anybody can see.
    'directoryRepositoryProvider': 'a client, not data',
    'financeRepositoryProvider': 'a client, not data',
    'oversightRepositoryProvider': 'a client, not data',
    'chatRepositoryProvider': 'a client, not data',

    // UI state the user is holding. Refreshing these would clear a search box
    // or a filter mid-use, which is the opposite of what a refresh is for.
    'adeelSearchProvider': 'what the user typed',
    'selectedStatementAdeelProvider': 'which man the user picked',
    'auditTypeProvider': 'a filter the user chose',
    'receivablePeriodProvider': 'a filter the user chose',
    'reportRangeProvider': 'a date range the user chose',

    // The room has its own clock — one second while it is live — so a
    // forty-five-second sweep would be both redundant and a scroll-position
    // fight in the middle of a conversation.
    'chatProvider': 'polls itself, faster',
    'chatUnreadProvider': 'polls itself, and owns its own timer',
    'threadUnreadProvider': 'rides the bell it watches',
    'roomUnreadProvider': 'rides the bell it watches',
    'chatReadStateProvider': 'device storage, not a read',

    // ⚠ NEITHER OF THESE HOLDS AN ANSWER, and throwing them away would do
    //   real harm rather than nothing. chatChimeProvider owns the audio player
    //   AND the baseline count the chime compares against — reset it every
    //   forty-five seconds and the next tick reads as «first count», so a
    //   message arriving right after a sweep rings nothing at all.
    //   chatScreenOpenProvider is «is he looking at the room this second»,
    //   written by the screen itself; a sweep clearing it would ring the bell
    //   for a message he is watching land.
    'chatChimeProvider': 'a player and a baseline, not data',
    'chatScreenOpenProvider': 'written by the screen, not fetched',

    // ── نظام الاتصال الصوتي ──────────────────────────────────────────
    // ⚠ ALL THREE WOULD BE ACTIVELY HARMFUL TO SWEEP, not merely pointless.
    //   incomingCall owns a three-second timer of its own — the bell cannot
    //   carry it, because a call changes no unread count and a provider
    //   watching the bell would be built once and never asked again.
    //   activeCall holds the LIVE SESSION: the microphone, the peer
    //   connection and the signalling poll. Throwing that away every
    //   forty-five seconds would hang up on a call in progress.
    //   And callRingtone owns the platform AudioPlayer that is LOOPING while a
    //   call rings. A sweep disposes it — so a call arriving forty-five seconds
    //   before one would ring for a moment and then fall silent with the banner
    //   still on screen, which is the very symptom this feature was built to
    //   end: «تري رنين فقط لا تسمع اي صوت».
    'callRepositoryProvider': 'a client, not data',
    'incomingCallProvider': 'polls itself, and owns its own timer',
    'activeCallProvider': 'the live call — sweeping it would hang up',
    'callRingtoneProvider': 'a looping player — sweeping it would go silent',

    // ⚠ THE DOORBELL OWNS A WEBSOCKET AND A LISTENER SET. Sweeping it would
    //   tear down the channel and every subscription on it every forty-five
    //   seconds — and the room, the bell and the call poll each hold one. The
    //   app would go on working, on the polls alone, and the speed this exists
    //   for would vanish with nothing on screen to show it had.
    'doorbellProvider': 'a websocket, not an answer',

    // ⚠ THE SESSION ITSELF. Throwing this away would re-read who is signed in
    //   on every sweep — and it is the provider the router guard watches, so a
    //   moment of «not signed in yet» every forty-five seconds would bounce a
    //   man off the screen he was reading. It has its own listener on GoTrue.
    'authControllerProvider': 'the session, watched live by the router',

    // ── ما تحت التطبيق كلّه ────────────────────────────────────────────────
    // ⚠ THESE FIVE WERE NEVER CHECKED BY ANYTHING. The scan below used to read
    //   `lib/features` only, so every provider declared in `lib/core` — the
    //   client, the router, the session plumbing — escaped this guard
    //   entirely. That is precisely the blind spot the «مصروفات للمشترك» bug
    //   lived in, moved one directory over: a provider that caches and is
    //   mentioned nowhere.
    //
    //   Widening the scan to `lib` surfaced them, and every one is a genuine
    //   exemption — but they are written down now rather than unseen, and the
    //   NEXT provider added under core will be asked the question.
    'supabaseClientProvider': 'the client itself, not an answer',
    'supabaseConfiguredProvider': 'a boot fact, decided once',
    'authRepositoryProvider': 'a client, not data',
    'googleAuthServiceProvider': 'a client, not data',
    // ⚠ AND SWEEPING THIS ONE WOULD REBUILD NAVIGATION MID-TAP. GoRouter holds
    //   the current location and the redirect guard; a new instance every
    //   forty-five seconds would drop whatever screen the man was on.
    'routerProvider': 'the router — sweeping it would restart navigation',
  };

  _pullRefreshTests();

  test('every data provider is thrown away by refreshAll', () {
    final String refresh = File(
      'lib/core/state/refresh.dart',
    ).readAsStringSync();

    final List<String> missing = <String>[];

    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;

      for (final RegExpMatch m in RegExp(
        r'^final\s+[A-Za-z<>,\s?]+\s+([a-zA-Z]+Provider)\s*=',
        multiLine: true,
      ).allMatches(e.readAsStringSync())) {
        final String name = m.group(1)!;
        if (exempt.containsKey(name)) continue;
        if (refresh.contains('.$name)')) continue;
        missing.add('$name  (${e.path})');
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'These providers cache an answer that nothing throws away — the exact '
          'shape of the «مصروفات للمشترك» bug. Add each to refreshAll, or add it '
          'to `exempt` above with the reason:\n  ${missing.join('\n  ')}',
    );
  });

  test('and every exemption still names a provider that exists', () {
    // An exemption for a deleted provider is a note that has stopped being
    // read — and the next provider to take that name inherits the excuse.
    final Set<String> declared = <String>{};
    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      for (final RegExpMatch m in RegExp(
        r'^final\s+[A-Za-z<>,\s?]+\s+([a-zA-Z]+Provider)\s*=',
        multiLine: true,
      ).allMatches(e.readAsStringSync())) {
        declared.add(m.group(1)!);
      }
    }

    final List<String> stale = exempt.keys
        .where((String k) => !declared.contains(k))
        .toList();

    expect(stale, isEmpty, reason: 'exemptions for providers that are gone');
  });
}

/// And no screen refreshes only ITSELF.
///
/// ── THE SECOND HALF OF THE SAME BUG ─────────────────────────────────────────
/// refresh.dart argues this for the ⟳ button in the app bar: nothing in this app
/// is only local, so a refresh that reloads the screen in front of you leaves
/// five others quietly stale. The PULL gesture was never held to the same rule —
/// each screen invalidated the two or three providers its author had in mind.
///
/// So a member could pull his portal down, watch the spinner, and still be shown
/// an aid ledger from before the voucher existed: the pull reloaded his detail
/// and his statement and touched nothing else. That is worse than no refresh at
/// all, because the gesture told him he was up to date.
///
/// ⚠ AND A MEMBER HAS NO ⟳ BUTTON. The portal is not an AppScaffold — he has one
///   destination, so he gets no navigation bar and no app bar with it. The pull
///   is the ONLY refresh he has, which is why it has to be the whole one.
void _pullRefreshTests() {
  test('every pull-to-refresh calls refreshAll and nothing narrower', () {
    final List<String> narrow = <String>[];

    for (final FileSystemEntity e in Directory(
      'lib',
    ).listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final String src = e.readAsStringSync();
      if (!src.contains('onRefresh:')) continue;

      // Everything from each `onRefresh:` to the end of its callback — good
      // enough to tell «refreshAll(ref)» from a hand-picked list, which is the
      // only distinction being made.
      for (final RegExpMatch m in RegExp(
        r'onRefresh:[\s\S]{0,400}?\n\s*(child:|\))',
      ).allMatches(src)) {
        final String block = m.group(0)!;
        if (block.contains('refreshAll')) continue;
        narrow.add(
          '${e.path}\n      ${block.split('\n').take(3).join('\n      ')}',
        );
      }
    }

    expect(
      narrow,
      isEmpty,
      reason:
          'A pull that reloads part of the app tells the user he is up to date '
          'when he is not — and for a member it is the only refresh there is. '
          'Use refreshAll(ref):\n  ${narrow.join('\n  ')}',
    );
  });
}
