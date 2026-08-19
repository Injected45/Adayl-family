-- ═════════════════════════════════════════════════════════════════════════════
-- مجلس العدايل — the first table BOTH ways in reach
--
-- Every other table in this schema belongs to one audience: staff read the
-- association through `has_role()`, an عديل reads himself through
-- `my_adeel_id()`, and `my_role()` returning NULL for a bound portal account is
-- what keeps the two apart without either set of policies knowing about the
-- other.
--
-- The chat deliberately breaks that symmetry — it is one room and everyone is
-- in it — so it is the one place where a mistake in either direction is a
-- silent failure rather than a visible one:
--
--   • too NARROW and an عديل sees an empty room with nothing saying why. That
--     is what a naive `has_role('viewer')` policy would have produced, and it
--     would have passed every test written by someone holding a staff account.
--   • too WIDE and a pending applicant — or an عديل whose handset was released
--     — is sitting in the association's private conversation.
--
-- Both are checked below, from both sides. So is the rule that a man may erase
-- his own words and nobody else's, and the cap that stops one phone filling the
-- association's storage.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── A portal account of this file's OWN ─────────────────────────────────────
-- 45_adeel_portal deletes its b1/b2 at the bottom, so by the time this runs
-- there is no bound عديل in the database at all. Reusing the fixture's staff
-- accounts instead would test the room with nobody in it who is not staff —
-- which is precisely the case that cannot be got wrong.
--
-- Created here, deleted at the bottom, so nothing after this file knows it
-- existed.
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT public.issue_adeel_code(1);
CREATE TEMP TABLE chatcode AS
  SELECT code FROM public.adeel_access_codes WHERE adeel_id = 1;
GRANT SELECT ON chatcode TO authenticated;

SELECT probe.become(NULL);
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'chat@fam.test',    '{"full_name":"عضو المجلس"}'),
  -- A pending account of this file's OWN, for the same reason c1 is: the
  -- fixture's a5 is seeded pending and EARLIER files approve, suspend and
  -- re-approve it, so by the time this runs "pending" is whatever 30_rules and
  -- 40_rls happened to leave behind. The trigger on auth.users creates this one
  -- viewer/pending and nothing here touches it.
  ('00000000-0000-0000-0000-0000000000c2', 'waiting@fam.test', '{"full_name":"ينتظر الموافقة"}');

SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000c1');
SELECT public.redeem_adeel_code((SELECT code FROM chatcode));
RESET ROLE;

-- ⚠ EVERY CHECK BELOW RUNS AS `authenticated`, and the whole file is worthless
--   without this line. probe.become sets the JWT claims, not the database role,
--   and psql is connected as the owner — who BYPASSES row-level security. Read
--   checks would then pass for a pending applicant and for the wrong handset,
--   reporting an open door as closed. 45_adeel_portal does the same for the same
--   reason; this is the shape all RLS probing in this suite takes.
SET ROLE authenticated;
-- ── STAFF ───────────────────────────────────────────────────────────────────
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin

SELECT probe.succeeds('chat', 'an admin may speak in the room', $sql$
  SELECT public.send_chat_message('السلام عليكم، اجتماع الجمعية يوم الجمعة')
$sql$);
SELECT probe.eq('chat', '...and it is marked as coming from the board',
  $sql$ SELECT "fromStaff"::text FROM public.v_chat_messages
         ORDER BY "id" DESC LIMIT 1 $sql$, 'true');
-- The name the ROOM knows, not the one the account carries. For staff that is
-- the profile's display name; the check that matters is that it is never blank,
-- because a nameless bubble is worse than an ugly one.
SELECT probe.note('chat', '...under a name, never a blank',
  (SELECT btrim("authorName") <> '' FROM public.v_chat_messages
    ORDER BY "id" DESC LIMIT 1));

-- ── THE عديل, which is the whole point of the feature ───────────────────────
SELECT probe.become('00000000-0000-0000-0000-0000000000c1');  -- a bound عديل

SELECT probe.note('chat', 'an عديل is in the room, not looking at an empty one',
  (SELECT count(*) FROM public.v_chat_messages) > 0,
  'rows=' || (SELECT count(*)::text FROM public.v_chat_messages));
SELECT probe.succeeds('chat', '...and he may speak in it', $sql$
  SELECT public.send_chat_message('وعليكم السلام، إن شاء الله نحضر')
$sql$);
-- His REGISTER name. «أيمن صالح بلها» is who the association knows; the string
-- Google put on the account is frequently not the same, and the room should not
-- be the one place a man appears under a different name.
SELECT probe.eq('chat', '...under the name the REGISTER holds for him',
  $sql$ SELECT ("authorName" = (SELECT a.full_name FROM public.adeels a
                                 WHERE a.id = public.my_adeel_id()))::text
          FROM public.v_chat_messages ORDER BY "id" DESC LIMIT 1 $sql$, 'true');
SELECT probe.eq('chat', '...and NOT marked as coming from the board',
  $sql$ SELECT "fromStaff"::text FROM public.v_chat_messages
         ORDER BY "id" DESC LIMIT 1 $sql$, 'false');
-- One room: he sees what the admin said, not only his own line. A chat where
-- each reader sees a different subset is not a chat, and per-person scoping is
-- what every other policy in this schema does.
SELECT probe.note('chat', '...and he sees the STAFF message too, not just his own',
  (SELECT count(*) FROM public.v_chat_messages WHERE "fromStaff") > 0);
-- And `mine` is computed server-side, so the client never holds anyone's user id
-- and never decides whose bubble it is looking at.
SELECT probe.eq('chat', 'his own message comes back marked as his',
  $sql$ SELECT "mine"::text FROM public.v_chat_messages
         ORDER BY "id" DESC LIMIT 1 $sql$, 'true');
SELECT probe.eq('chat', '...and the staff message does not',
  $sql$ SELECT "mine"::text FROM public.v_chat_messages
         WHERE "fromStaff" ORDER BY "id" LIMIT 1 $sql$, 'false');

-- ── THE SAME MAN ON A SECOND HANDSET IS NOBODY ──────────────────────────────
-- The device lock is not a portal feature that stops at the portal. my_adeel_id()
-- returns NULL for an unrecognised handset, so in_association() is false and the
-- room is closed to it — with the SAME account and the SAME JWT.
SELECT probe.become('00000000-0000-0000-0000-0000000000c1', 'authenticated',
                    'a-different-handset');
SELECT probe.eq('chat', 'the same عديل on a SECOND device sees no room at all',
  $sql$ SELECT count(*)::text FROM public.v_chat_messages $sql$, '0');
SELECT probe.raises('chat', '...and cannot speak into it', $sql$
  SELECT public.send_chat_message('من جهاز آخر')
$sql$, 'RUL00');

-- ── A PENDING ACCOUNT IS NOT IN THE ASSOCIATION ─────────────────────────────
-- Approval is what admits someone, and it is checked in ONE place —
-- my_role()/my_adeel_id() both require it — so the room inherits it without
-- naming it.
SELECT probe.become('00000000-0000-0000-0000-0000000000c2');  -- pending, never approved
SELECT probe.eq('chat', 'a pending applicant sees nothing in the room',
  $sql$ SELECT count(*)::text FROM public.v_chat_messages $sql$, '0');
SELECT probe.raises('chat', '...and cannot speak into it', $sql$
  SELECT public.send_chat_message('أهلاً')
$sql$, 'RUL00');

-- And a caller with no session at all.
SELECT probe.become(NULL, 'anon');
SELECT probe.raises('chat', 'anon cannot speak into the room', $sql$
  SELECT public.send_chat_message('spam')
$sql$, 'RUL00');

-- ═════════════════════════════════════════════════════════════════════════════
-- الخاص — a thread with الإدارة, and the wall between two members
--
-- The room above is deliberately open: everyone in the association reads
-- everything in it. A private thread is the opposite claim, and a claim of
-- privacy is only worth what the checks below are worth — so each is asserted
-- from the side that would be violated, not from the side that owns the row.
--
-- The wall is ONE clause in read_chat: `has_role('viewer')`, which is FALSE for
-- a bound portal account because my_role() returns NULL while adeel_id is set.
-- A member therefore matches only `thread_adeel_id = my_adeel_id()`. If that
-- clause were ever loosened to something like "is signed in", every member
-- would read every other member's private messages and NOTHING on any screen
-- would look different.
-- ═════════════════════════════════════════════════════════════════════════════

-- A SECOND bound عديل, because a wall needs two sides to be tested at all.
RESET ROLE;
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');
SELECT public.issue_adeel_code(2);
CREATE TEMP TABLE chatcode2 AS
  SELECT code FROM public.adeel_access_codes WHERE adeel_id = 2;
GRANT SELECT ON chatcode2 TO authenticated;
SELECT probe.become(NULL);
INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000c3', 'other-chat@fam.test',
   '{"full_name":"عديل آخر"}');
SET ROLE authenticated;
SELECT probe.become('00000000-0000-0000-0000-0000000000c3');
SELECT public.redeem_adeel_code((SELECT code FROM chatcode2));

-- ── HE WRITES TO الإدارة ────────────────────────────────────────────────────
SELECT probe.become('00000000-0000-0000-0000-0000000000c1');
SELECT probe.succeeds('priv', 'a member may write privately to the board', $sql$
  SELECT public.send_chat_message('عندي ظرف، هل أؤجل الاشتراك؟',
                                  public.my_adeel_id())
$sql$);
SELECT probe.eq('priv', '...and it lands in HIS thread, not in the room',
  $sql$ SELECT ("threadAdeelId" = public.my_adeel_id())::text
          FROM public.v_chat_messages ORDER BY "id" DESC LIMIT 1 $sql$, 'true');
-- The pair to every wall check below: he can still read what he wrote.
SELECT probe.note('priv', '...and he can read his own thread',
  (SELECT count(*) FROM public.v_chat_messages
    WHERE "threadAdeelId" = public.my_adeel_id()) > 0);

-- ── HE MAY NOT WRITE INTO ANOTHER MAN'S THREAD ──────────────────────────────
-- The clause that stops a member addressing another member through a thread
-- that is not his. Refused at the function, and unreadable even if it landed.
SELECT probe.raises('priv', 'a member cannot write into a thread not his own',
  $sql$ SELECT public.send_chat_message('مرحبا', 2) $sql$, 'RUL00');

-- ── AND HE MAY NOT READ ONE ────────────────────────────────────────────────
SELECT probe.become('00000000-0000-0000-0000-0000000000c3');
SELECT probe.succeeds('priv', 'the second member writes privately too', $sql$
  SELECT public.send_chat_message('سؤال خاص بي', public.my_adeel_id())
$sql$);
-- ⚠ THE CHECK THE WHOLE FEATURE RESTS ON.
SELECT probe.eq('priv', 'a member sees NO private message but his own',
  $sql$ SELECT count(*)::text FROM public.v_chat_messages
         WHERE "threadAdeelId" IS NOT NULL
           AND "threadAdeelId" <> public.my_adeel_id() $sql$, '0');
-- Said the other way, because "zero rows" can also mean "the query was wrong":
-- he sees exactly one thread, and it is his.
SELECT probe.eq('priv', '...and the only thread he sees is his own',
  $sql$ SELECT count(DISTINCT "threadAdeelId")::text
          FROM public.v_chat_messages WHERE "threadAdeelId" IS NOT NULL $sql$,
  '1');
-- And المجلس is untouched by any of it: privacy did not narrow the open room.
SELECT probe.note('priv', 'while المجلس is still open to him in full',
  (SELECT count(*) FROM public.v_chat_messages
    WHERE "threadAdeelId" IS NULL) > 1);
-- The inbox is staff-only, and it is scoped by the same policy rather than by a
-- rule of its own — so a member reading it gets his own conversation, never a
-- list of who else has written to the board.
SELECT probe.eq('priv', 'the inbox shows a member only himself',
  $sql$ SELECT count(*)::text FROM public.v_chat_threads
         WHERE "adeelId" <> public.my_adeel_id() $sql$, '0');

-- ── الإدارة IS THE OTHER SIDE OF EVERY THREAD ──────────────────────────────
SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.eq('priv', 'the board sees BOTH conversations',
  $sql$ SELECT count(*)::text FROM public.v_chat_threads $sql$, '2');
SELECT probe.note('priv', 'with the name and the last words on each',
  (SELECT bool_and(btrim("adeelName") <> '' AND btrim("lastBody") <> '')
     FROM public.v_chat_threads));
SELECT probe.succeeds('priv', 'and may answer one', $sql$
  SELECT public.send_chat_message('أبشر، مرّ على المكتب', 1)
$sql$);
SELECT probe.eq('priv', 'as الإدارة, not as a member',
  $sql$ SELECT "fromStaff"::text FROM public.v_chat_messages
         ORDER BY "id" DESC LIMIT 1 $sql$, 'true');
-- Writing to somebody who is not on the register would open a thread with
-- nobody at the other end.
SELECT probe.raises('priv', 'but not to an عديل who does not exist', $sql$
  SELECT public.send_chat_message('مرحبا', 99999)
$sql$, 'RUL18');

-- The answer reaches the man it was for, and only him.
SELECT probe.become('00000000-0000-0000-0000-0000000000c1');
SELECT probe.note('priv', 'the answer reaches the member it was for',
  (SELECT count(*) FROM public.v_chat_messages
    WHERE "threadAdeelId" = public.my_adeel_id() AND "fromStaff") > 0);
SELECT probe.become('00000000-0000-0000-0000-0000000000c3');
SELECT probe.eq('priv', 'and nobody else',
  $sql$ SELECT count(*)::text FROM public.v_chat_messages
         WHERE "fromStaff" AND "threadAdeelId" IS NOT NULL
           AND "threadAdeelId" <> public.my_adeel_id() $sql$, '0');

-- ── A RELEASED HANDSET LOSES THE PRIVATE THREAD TOO ────────────────────────
-- Same account, same JWT, unrecognised device: my_adeel_id() is NULL, so the
-- thread clause matches nothing and has_role() is false. The private side
-- inherits the device lock without naming it.
SELECT probe.become('00000000-0000-0000-0000-0000000000c3', 'authenticated',
                    'some-other-handset');
SELECT probe.eq('priv', 'a second handset reads no private message either',
  $sql$ SELECT count(*)::text FROM public.v_chat_messages
         WHERE "threadAdeelId" IS NOT NULL $sql$, '0');

-- ── WHAT MAY BE SAID ────────────────────────────────────────────────────────
SELECT probe.become('00000000-0000-0000-0000-0000000000c1');
SELECT probe.raises('chat', 'an empty message is refused', $sql$
  SELECT public.send_chat_message('   ')
$sql$, 'RUL18');
SELECT probe.raises('chat', '...and one longer than the cap', $sql$
  SELECT public.send_chat_message(repeat('ا', 1001))
$sql$, 'RUL18');
-- The pair: exactly the cap goes through, so the limit is a limit and not an
-- off-by-one that quietly costs a character.
SELECT probe.succeeds('chat', '...but exactly the cap is fine', $sql$
  SELECT public.send_chat_message(repeat('ب', 1000))
$sql$);

-- ── THE RATE LIMIT ──────────────────────────────────────────────────────────
-- ⚠ NOT politeness. The anon key ships inside the APK and cannot be made
--   secret, so any member can call this in a loop from a script. Without a cap
--   one phone fills the association's free storage in minutes.
DO $flood$
BEGIN
  FOR i IN 1..25 LOOP
    BEGIN
      PERFORM public.send_chat_message('رسالة ' || i::text);
    EXCEPTION WHEN OTHERS THEN
      EXIT;  -- the cap bit; that is what the check below measures
    END;
  END LOOP;
END $flood$;
SELECT probe.note('chat', 'one phone cannot flood the room',
  (SELECT count(*) FROM public.chat_messages
    WHERE author_user_id = '00000000-0000-0000-0000-0000000000c1'
      AND created_at > now() - interval '1 minute') <= 20,
  'sent=' || (SELECT count(*)::text FROM public.chat_messages
               WHERE author_user_id = '00000000-0000-0000-0000-0000000000c1'
                 AND created_at > now() - interval '1 minute'));
SELECT probe.raises('chat', '...and says so rather than failing silently', $sql$
  SELECT public.send_chat_message('واحدة أخرى')
$sql$, 'RUL18');

-- ── DELETION: HIS OWN WORDS, AND NOBODY ELSE'S ──────────────────────────────
SELECT probe.raises('chat', 'a member cannot delete the board''s message', $sql$
  SELECT public.delete_chat_message(
    (SELECT min(id) FROM public.chat_messages WHERE from_staff))
$sql$, 'RUL00');
SELECT probe.succeeds('chat', '...but may delete his own', $sql$
  SELECT public.delete_chat_message(
    (SELECT min(id) FROM public.chat_messages
      WHERE author_user_id = '00000000-0000-0000-0000-0000000000c1'))
$sql$);
-- ⚠ THE WORDS ARE GONE, not merely flagged. Text no policy will ever return is
--   a liability with no reader — even an admin cannot see it — so storing it
--   protects nobody.
SELECT probe.eq('chat', '...and the words are ERASED, not just hidden',
  $sql$ SELECT body FROM public.chat_messages
         WHERE deleted_at IS NOT NULL ORDER BY id LIMIT 1 $sql$, '');
-- But the ROW stays, so a gap in a conversation is visible rather than silent.
SELECT probe.eq('chat', '...while the tombstone stays in the room',
  $sql$ SELECT "deleted"::text FROM public.v_chat_messages
         WHERE "id" = (SELECT min(id) FROM public.chat_messages
                        WHERE deleted_at IS NOT NULL) $sql$, 'true');
SELECT probe.raises('chat', '...and deleting it twice is refused', $sql$
  SELECT public.delete_chat_message(
    (SELECT min(id) FROM public.chat_messages WHERE deleted_at IS NOT NULL))
$sql$, 'RUL18');

-- ── AN ADMIN MAY MODERATE, A FINANCE MANAGER MAY NOT ────────────────────────
-- Moderating what a member said is not a financial act. The association put the
-- whole outgoing side of the treasury a rung above finance for the same reason.
SELECT probe.become('00000000-0000-0000-0000-0000000000a2');  -- financeManager
SELECT probe.raises('chat', 'a finance manager cannot delete another''s message',
  $sql$ SELECT public.delete_chat_message(
    (SELECT min(id) FROM public.chat_messages
      WHERE author_user_id = '00000000-0000-0000-0000-0000000000c1'
        AND deleted_at IS NULL))
$sql$, 'RUL00');

SELECT probe.become('00000000-0000-0000-0000-0000000000a1');  -- admin
SELECT probe.succeeds('chat', '...an admin can', $sql$
  SELECT public.delete_chat_message(
    (SELECT min(id) FROM public.chat_messages
      WHERE author_user_id = '00000000-0000-0000-0000-0000000000c1'
        AND deleted_at IS NULL))
$sql$);
-- The ACT is in the trail, never the content. An admin reaching into the room
-- and removing somebody else's words is what rule 12 exists to leave a mark of.
SELECT probe.note('chat', '...and the trail records WHO removed WHOSE message',
  EXISTS (SELECT 1 FROM public.audit_log
           WHERE event_type = 'chat.delete' AND detail LIKE 'حذف رسالة %'));
-- And it does NOT record what was said: the trail is a record of acts.
SELECT probe.eq('chat', '...and never what it said',
  $sql$ SELECT count(*)::text FROM public.audit_log
         WHERE event_type = 'chat.delete'
           AND detail LIKE '%اجتماع الجمعية%' $sql$, '0');


SELECT probe.become('00000000-0000-0000-0000-0000000000c1');
-- ── NO WRITE REACHES THE TABLE EXCEPT THROUGH THE FUNCTIONS ────────────────
-- The policy set has SELECT and nothing else, so PostgREST cannot insert
-- whatever the client sends — which is where the rate limit and the identity
-- snapshot live, neither of which a row policy could express.
SELECT probe.raises('chat', 'no client role may INSERT a message directly', $sql$
  SET LOCAL ROLE authenticated;
  INSERT INTO public.chat_messages
    (author_user_id, author_name, from_staff, body)
  VALUES ('00000000-0000-0000-0000-0000000000a1', 'مزوَّر', true, 'تجاوز')
$sql$, '42501');
SELECT probe.raises('chat', '...nor UPDATE one to put words back', $sql$
  SET LOCAL ROLE authenticated;
  UPDATE public.chat_messages SET body = 'أعيدت' WHERE deleted_at IS NOT NULL
$sql$, '42501');

RESET ROLE;
SELECT probe.become(NULL);

-- Put the fixture back, exactly as 45_adeel_portal does: deleting the auth.users
-- row cascades to the profile and takes the binding with it, and the message
-- rows go with it too — chat_messages.author_user_id is ON DELETE CASCADE, which
-- is the only reason this cleanup is one line.
SELECT probe.become(NULL);
DELETE FROM public.adeel_access_codes;
DELETE FROM auth.users WHERE email IN ('chat@fam.test', 'waiting@fam.test', 'other-chat@fam.test');
DELETE FROM public.chat_messages;
DROP TABLE chatcode;
DROP TABLE chatcode2;
