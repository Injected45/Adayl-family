import 'package:family_app/features/chat/data/chat_chime.dart';
import 'package:flutter_test/flutter_test.dart';

/// ── متى يرنّ الجرس ومتى يسكت ───────────────────────────────────────────────
///
/// «اريد ان يصدر صوت جرس عند كل وصول رسالة جديدة … يظهر الصوت مع الايقونه
/// الحمره وعدد الارقام / بمعنى صوت الجرس لما يكون غير فاتح الرسائل / اما اذا
/// فاتح الرسائل فتصل الرسائل بدون جرس نفس نظام واتساب».
///
/// Three rules, and each of them is a way the chime could be WRONG rather than
/// merely absent — which is why they are pinned here instead of being left to
/// the ear. A chime that rings once too often gets muted by the person holding
/// the phone, and then it is off for the one message it existed for.
///
/// ⚠ THE SOUND ITSELF IS NOT TESTED, and cannot be: playing it needs a platform
///   channel no test binding provides. What IS tested is the DECISION — every
///   branch that leads to a play, and every branch that must not. The play call
///   is a single line at the end of that decision, wrapped in a catch.
class _Spy extends ChatChime {
  int rings = 0;

  @override
  Future<void> play() async => rings++;
}

void main() {
  test('a rise in the count rings', () {
    final _Spy c = _Spy();
    c.onCount(0, suppressed: false); // arming read
    c.onCount(1, suppressed: false);

    expect(c.rings, 1);
  });

  // ⚠ THE FIRST READING IS NOT AN ARRIVAL. The bell's opening question is «how
  //   many were waiting before the app was opened», and that is almost never
  //   zero — so ringing on it would greet every launch with a sound for
  //   messages that arrived yesterday, which teaches the user the sound means
  //   nothing.
  test('⚠ but the very first count never rings, however large', () {
    final _Spy c = _Spy();
    c.onCount(7, suppressed: false);

    expect(c.rings, 0);
  });

  // ⚠ WHATSAPP'S RULE, ASKED FOR IN THOSE WORDS. The badge still advances —
  //   only the sound is withheld — because a count that lied to keep quiet
  //   would be a second bug wearing the first one's clothes.
  test('⚠ and nothing rings while he is looking at the room', () {
    final _Spy c = _Spy();
    c.onCount(0, suppressed: false);
    c.onCount(3, suppressed: true);

    expect(c.rings, 0);

    // He leaves; the next arrival is audible again, and it is measured against
    // the count he already saw rather than against the one he last HEARD.
    c.onCount(4, suppressed: false);
    expect(c.rings, 1);
  });

  test('a falling count is silent — reading messages is not an event', () {
    final _Spy c = _Spy();
    c.onCount(5, suppressed: false);
    c.onCount(0, suppressed: false); // he opened the room and read them
    c.onCount(0, suppressed: false); // and the next quiet tick

    expect(c.rings, 0);
  });

  // ⚠ AND A QUIET TICK IS THE COMMONEST ONE. The bell asks every four seconds
  //   whether the app is open or not; the same number arriving fifteen times a
  //   minute must be silent fifteen times.
  test('an unchanged count is silent', () {
    final _Spy c = _Spy();
    c.onCount(2, suppressed: false);
    for (int i = 0; i < 15; i++) {
      c.onCount(2, suppressed: false);
    }

    expect(c.rings, 0);
  });

  // ⚠ TWO MESSAGES IN ONE TICK ARE ONE SOUND. The poll returns a count, not an
  //   arrival, so a burst is a jump of three — and three overlapping pops on a
  //   phone speaker is a noise, not a notification.
  test('a jump of three is one ring, not three', () {
    final _Spy c = _Spy();
    c.onCount(0, suppressed: false);
    c.onCount(3, suppressed: false);

    expect(c.rings, 1);
  });

  // ⚠ A NEW ACCOUNT MUST RE-ARM. Without reset, the next man's first count is
  //   compared against the previous man's — and a smaller number would leave
  //   the chime armed at a baseline that was never his.
  test('⚠ reset re-arms, so a sign-out cannot ring for the next account', () {
    final _Spy c = _Spy();
    c.onCount(9, suppressed: false);
    c.reset();
    c.onCount(4, suppressed: false);

    expect(c.rings, 0, reason: 'the first count of a new session rang');

    c.onCount(5, suppressed: false);
    expect(c.rings, 1);
  });
}
