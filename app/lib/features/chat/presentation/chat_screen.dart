import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/chat_read_state.dart';
import '../domain/models.dart';
import 'chat_flourishes.dart';
import 'emoji_panel.dart';
import 'providers.dart';
import 'unread_bell.dart';

/// مجلس العدايل — the open room, and the private thread beside it.
///
/// The first screen in this app that both kinds of account reach. Staff open it
/// from the navigation; an عديل opens it from his portal, and the router lets
/// him leave `/my-dues` for exactly this one destination and no other.
///
/// ── TWO ROOMS, ONE SCREEN ───────────────────────────────────────────────────
/// المجلس is open: everyone in the association reads everything in it. الخاص is
/// a thread with الإدارة as an institution — never with a named officer, so a
/// question is answered by whoever is on duty rather than waiting for one man to
/// come back.
///
/// What each account sees under «الخاص» differs, and it is the same view either
/// way: a member sees HIS conversation, staff see the INBOX of everyone's. That
/// is the policy speaking, not a branch — `read_chat` hands each reader only the
/// threads he is a side of.
///
/// ── WHAT THE SCREEN DOES NOT DECIDE ─────────────────────────────────────────
/// Whose message it is, whether it may be deleted, and which private threads
/// exist. `v_chat_messages` answers `mine` from `auth.uid()`,
/// `delete_chat_message` refuses anyone but the author or an admin, and the wall
/// between two members is one clause in `read_chat`. Nothing here filters for
/// privacy — and nothing here could be trusted to.
///
/// It is used by an عديل who may be reading it as a WhatsApp replacement, so the
/// shape is the one he already knows: his own words on one side, the room's on
/// the other, the sender's name over each group, and the day printed once
/// between days rather than on every line.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

/// Which of the two the screen is showing.
enum _Room { hall, private }

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  _Room _room = _Room.hall;

  /// The private conversation currently open.
  ///
  /// For a member it is fixed to his own id the moment his record loads — he has
  /// exactly one thread and never chooses. For staff it is null until they pick
  /// somebody out of the inbox, and null is what MAKES it the inbox.
  int? _thread;

  /// The read mark as it stood when this screen OPENED, frozen.
  ///
  /// ⚠ FROZEN IS THE WHOLE DESIGN. Read it live and the «رسائل جديدة» line
  ///   marches down the list as the mark advances, and by the time the eye finds
  ///   it there is nothing under it — a line that says «you were here» has to go
  ///   on saying where «here» was for as long as the screen is open.
  int _unreadFrom = 0;

  /// ⚠ HELD AS OBJECTS, NOT READ THROUGH `ref` WHEN NEEDED.
  ///
  ///   The mark has to be written on the way OUT as well as on the way in —
  ///   messages arrive by poll while a man sits here, and without the second
  ///   write they are unread the moment he leaves and the bell rings for a
  ///   conversation he watched happen. But `ref` throws inside dispose(), so
  ///   the two collaborators are captured while the widget is alive.
  ///
  ///   It also keeps this screen from touching chatUnreadProvider at all, which
  ///   matters more: that provider owns a thirty-second timer, and merely
  ///   reading it here would start one for every test that opens the room.
  late final ChatReadState _reads;

  /// The newest id this screen has actually RENDERED.
  ///
  /// ⚠ THE MARK IS TAKEN FROM THE LIST, NOT FROM A SECOND REQUEST. Asking the
  ///   server for its newest id would be a shade more accurate and would drag
  ///   the Supabase client into this widget's initState — where a test that
  ///   overrides the message provider has no client to give it, and where the
  ///   screen would fail to open for a reason that has nothing to do with the
  ///   room. The room polls every four seconds and fetches newest-first, so
  ///   this value is the server's newest for every practical purpose.
  int _newestSeen = 0;

  @override
  void initState() {
    super.initState();
    _reads = ref.read(chatReadStateProvider);

    // Read the mark, THEN clear it. In that order: the «رسائل جديدة» line needs
    // the old value and the bell needs the new one, and the other way round
    // loses the only copy of where he had reached.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final int from = await _reads.lastRead();
      if (!mounted) return;
      setState(() => _unreadFrom = from);
      if (!mounted) return;
      // Refreshes the bell if one is on screen, and creates nothing if not —
      // invalidating a provider that was never built is a no-op.
      ref.invalidate(chatUnreadProvider);
    });
  }

  /// Opening the room IS reading it, and so is watching it, and so is leaving.
  ///
  /// Called from the list as rows arrive, and once more from dispose — because
  /// messages land by poll while a man sits here, and without the second write
  /// they are unread the moment he leaves and the bell rings for a conversation
  /// he watched happen.
  void _markRead(int newest) {
    if (newest <= _newestSeen) return;
    _newestSeen = newest;
    // Fire and forget. A failed write leaves the mark where it was, and the
    // next glance at the room writes it again.
    unawaited(_reads.markRead(newest).catchError((Object _) {}));
  }

  @override
  void dispose() {
    // No ref and no setState — the widget is going.
    _markRead(_newestSeen);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// To the newest message, which is where a conversation is read from.
  ///
  /// After the frame, because the list has not been laid out at the moment the
  /// data arrives and `maxScrollExtent` is still zero.
  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send(L l) async {
    final String body = _input.text.trim();
    if (body.isEmpty || _sending) return;

    setState(() => _sending = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatProvider(_key).notifier).send(body);
      // Cleared only on success. A message that was refused — by the rate limit,
      // or by a dropped connection — must still be in the box, or the man has
      // lost what he typed and has no idea whether it was sent.
      _input.clear();
      _toBottom();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(L l, ChatMessage message) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        title: Text(l.chatDeleteTitle),
        content: Text(l.chatDeleteBody, style: const TextStyle(height: 1.5)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatProvider(_key).notifier).remove(message.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, e))));
    }
  }

  /// Which room the reads and writes go to. Null is المجلس.
  int? get _key => _room == _Room.hall ? null : _thread;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AppUser? me = ref.watch(authControllerProvider).user;
    final bool isAdmin = me?.role.atLeast(AppRole.admin) ?? false;
    final bool isMember = me?.isAdeelPortal ?? false;

    // A member has exactly ONE thread and never chooses it. Pinned here rather
    // than on the segment tap, so switching back and forth cannot land him on
    // an inbox he has no business seeing — the server would give him nothing
    // anyway, and an empty screen is a worse way to be told.
    if (isMember && _thread != me!.adeelId) _thread = me.adeelId;

    final bool inbox = _room == _Room.private && _thread == null;

    ref.listen<AsyncValue<List<ChatMessage>>>(chatProvider(_key), (
      AsyncValue<List<ChatMessage>>? before,
      AsyncValue<List<ChatMessage>> after,
    ) {
      final int had = before?.valueOrNull?.length ?? 0;
      final int has = after.valueOrNull?.length ?? 0;
      if (has > had) _toBottom();
    });

    return AppScaffold(
      title: l.navChat,
      currentRoute: AppRoutes.chat,
      body: (BuildContext context) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: SegmentedButton<_Room>(
              segments: <ButtonSegment<_Room>>[
                ButtonSegment<_Room>(
                  value: _Room.hall,
                  label: Text(l.chatHall),
                  icon: const Icon(Icons.forum_outlined, size: 18),
                ),
                ButtonSegment<_Room>(
                  // The same segment reads differently to the two accounts and
                  // that is the honest label in both: a member is writing TO the
                  // board, the board is reading FROM everyone.
                  value: _Room.private,
                  label: Text(isMember ? l.chatToBoard : l.chatInbox),
                  icon: const Icon(Icons.lock_outline, size: 18),
                ),
              ],
              selected: <_Room>{_room},
              showSelectedIcon: false,
              onSelectionChanged: (Set<_Room> value) => setState(() {
                _room = value.first;
                // Back to the inbox each time staff leave the private side, so
                // a conversation opened yesterday is not still on screen with
                // no indication of whose it is.
                if (!isMember && _room == _Room.private) _thread = null;
              }),
            ),
          ),
          if (inbox)
            Expanded(child: _Inbox(onOpen: _openThread))
          else ...<Widget>[
            if (_room == _Room.private && !isMember)
              _ThreadHeader(
                name: _threadName,
                onBack: () => setState(() => _thread = null),
              ),
            Expanded(
              child: AsyncView<List<ChatMessage>>(
                value: ref.watch(chatProvider(_key)),
                onRetry: () => ref.read(chatProvider(_key).notifier).refresh(),
                builder: (List<ChatMessage> messages) {
                  if (messages.isEmpty) {
                    return EmptyStateView(
                      icon: _room == _Room.hall
                          ? Icons.forum_outlined
                          : Icons.lock_outline,
                      title: _room == _Room.hall
                          ? l.chatEmpty
                          : l.chatPrivateEmpty,
                    );
                  }
                  // ⚠ AFTER the frame, never during build: marking read writes
                  //   to storage and invalidates a provider, and both are
                  //   forbidden while a widget tree is being built.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    final int newest = messages.last.id;
                    if (newest <= _newestSeen) return;
                    _markRead(newest);
                    ref.invalidate(chatUnreadProvider);
                  });
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (BuildContext context, int i) {
                      final ChatMessage m = messages[i];
                      final ChatMessage? prev = i == 0 ? null : messages[i - 1];
                      return ChatEntrance(
                        key: ValueKey<int>(m.id),
                        child: _Bubble(
                          message: m,
                          // Above the first message newer than the frozen mark.
                          firstUnread:
                              _unreadFrom > 0 &&
                              m.id > _unreadFrom &&
                              (prev == null || prev.id <= _unreadFrom),
                          // The name is printed once per RUN, not once per
                          // message: four lines from one man read as one turn in
                          // the conversation rather than four announcements.
                          showAuthor:
                              prev == null || prev.authorName != m.authorName,
                          // And the day once between days, never on a line.
                          dayBreak:
                              prev == null ||
                              formatDate(prev.createdAt) !=
                                  formatDate(m.createdAt),
                          canDelete: m.mine || isAdmin,
                          onDelete: () => _delete(l, m),
                          // ⚠ STAFF ONLY, IN THE OPEN ROOM, AND ONLY FOR A
                          //   MESSAGE THAT HAS AN عديل BEHIND IT.
                          //
                          //   A member has exactly one thread and never chooses
                          //   it; pointing him at another man's would open a
                          //   screen read_chat refuses to fill — an empty room
                          //   with nothing on it saying why. Inside a private
                          //   thread there is nowhere to go, he is already
                          //   there. And a message from الإدارة carries no
                          //   عديل, so there is no thread to open.
                          //
                          //   Null in every one of those cases, so no tap
                          //   target exists rather than one that does nothing.
                          onOpenThread:
                              !isMember &&
                                  _room == _Room.hall &&
                                  m.authorAdeelId != null
                              ? () => _openThreadFor(m)
                              : null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(
              controller: _input,
              sending: _sending,
              onSend: () => _send(l),
            ),
          ],
        ],
      ),
    );
  }

  String _threadName = '';

  void _openThread(ChatThread thread) => setState(() {
    _thread = thread.adeelId;
    _threadName = thread.adeelName;
  });

  /// From a man's message in المحادثة الجماعية straight into his private one.
  ///
  /// ── WHY THIS IS STAFF-ONLY, AND NOT A MATTER OF TASTE ───────────────────
  /// A private thread has exactly two sides — the man it is about, and
  /// الإدارة. read_chat enforces that with
  /// thread_adeel_id = my_adeel_id() OR has_role('viewer'), and the second
  /// clause is FALSE for a bound portal account because my_role() returns NULL
  /// while adeel_id is set.
  ///
  /// So a member tapping another member here would arrive at a screen the
  /// SERVER refuses to fill: an empty room with nothing on it saying why,
  /// which is the worst of the three possible answers. He is given no
  /// affordance at all instead — see where onOpenThread is passed.
  ///
  /// ── AND WHY THE NAME COMES OFF THE MESSAGE ──────────────────────────────
  /// author_name is SNAPSHOT onto the row precisely so that reading the room
  /// needs no access to the register. Taking the heading from it keeps that
  /// true; a lookup would make opening a thread depend on a second request
  /// that can fail.
  void _openThreadFor(ChatMessage m) {
    final int? id = m.authorAdeelId;
    if (id == null) return;
    setState(() {
      _room = _Room.private;
      _thread = id;
      _threadName = m.authorName;
    });
  }
}

/// One message.
///
/// Mine on one side, the room's on the other — and in RTL "one side" has to be
/// written as start/end rather than left/right, or the whole conversation
/// mirrors itself the first time someone runs the app in English.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.showAuthor,
    required this.dayBreak,
    required this.firstUnread,
    required this.canDelete,
    required this.onDelete,
    this.onOpenThread,
  });

  final ChatMessage message;
  final bool showAuthor;
  final bool dayBreak;

  /// Whether the «رسائل جديدة» line belongs above this one.
  final bool firstUnread;

  /// Opens this author's private thread with الإدارة.
  ///
  /// Null when there is none to open, and the two cases are different: a
  /// message from الإدارة has no عديل behind it at all, and a member may not
  /// read another member's thread — the server would hand him an empty room.
  final VoidCallback? onOpenThread;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool mine = message.mine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (dayBreak) _DayDivider(iso: message.createdAt),
        if (firstUnread) const _UnreadDivider(),
        Row(
          // ── THE DISC SITS OUTSIDE THE BUBBLE ────────────────────────────
          // A Row rather than padding inside the Align, so the avatar does not
          // eat into the 78% the bubble is allowed: put it inside and every
          // line of every message loses thirty pixels of text to it.
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (!mine) ...<Widget>[
              // ⚠ RESERVED EVEN WHEN NOT DRAWN. Inside a run only the first
              //   message carries a disc, but every one of them keeps the space
              //   — otherwise the bubbles under it step sideways and the run
              //   stops reading as one person speaking.
              SizedBox(
                width: 30,
                child: showAuthor
                    ? GestureDetector(
                        // The disc is a target too. A board member reaching for
                        // a private word takes whichever of the three — disc,
                        // name, bubble — his thumb is nearest.
                        onTap: onOpenThread,
                        child: ChatAvatar(name: message.authorName),
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: ConstrainedBox(
                // A bubble that runs the full width stops reading as a bubble, and
                // the side it sits on stops carrying any meaning.
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                ),
                child: Column(
                  crossAxisAlignment: mine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: <Widget>[
                    if (showAuthor && !mine) ...<Widget>[
                      GestureDetector(
                        // ⚠ THE NAME IS THE DOOR, and it is null for everyone
                        //   who may not walk through it — a member looking at
                        //   another member, and anyone looking at a message from
                        //   الإدارة, which has no عديل behind it. A tap that
                        //   opened an empty room would be worse than a tap that
                        //   does nothing.
                        onTap: onOpenThread,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: AppSpacing.sm,
                            bottom: 2,
                            top: AppSpacing.xs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                message.authorName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  // The name in the SPEAKER'S OWN colour, so the
                                  // disc and the name are one signal rather than
                                  // two things a reader has to associate.
                                  color: ChatAvatar.toneFor(message.authorName),
                                ),
                              ),
                              // Who is speaking as the association, rather than as a
                              // member of it. An announcement about a meeting reads
                              // differently from a neighbour's opinion of it, and the
                              // room should not have to guess which it is looking at.
                              if (message.fromStaff) ...<Widget>[
                                const SizedBox(width: AppSpacing.xs),
                                _StaffTag(label: l.chatFromBoard),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    _Body(
                      message: message,
                      mine: mine,
                      canDelete: canDelete,
                      onDelete: onDelete,
                      onOpenThread: onOpenThread,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.message,
    required this.mine,
    required this.canDelete,
    required this.onDelete,
    this.onOpenThread,
  });

  final ChatMessage message;
  final bool mine;
  final bool canDelete;
  final VoidCallback onDelete;

  /// Tapping the bubble opens its author's private thread — null when there is
  /// none to open. See _openThreadFor.
  final VoidCallback? onOpenThread;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    // ── A DELETED MESSAGE LEAVES A MARK ───────────────────────────────────────
    // The row survives so a gap in a conversation is visible rather than silent
    // — «فلان حذف شيئاً هنا» is information; a message that simply vanishes
    // makes everyone who saw it doubt what they read. The words themselves are
    // gone from the database, not merely withheld here.
    if (message.deleted) {
      return Container(
        margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: GlassColors.well,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: GlassColors.wellEdge),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.do_not_disturb_on_outlined,
              size: 14,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l.chatDeleted,
              style: const TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      );
    }

    // ── A GESTURE, NOT A SENTENCE ────────────────────────────────────────────
    // «🙏» on its own is not a message with a bubble round it — it is the thing
    // people say without words, and every chat these members already use renders
    // it large and bare. The time still shows underneath, because a gesture is
    // as much a part of the record as a sentence.
    //
    // Capped at three glyphs in isEmojiOnly: without the cap forty pasted hearts
    // render at 40pt each and take a page of the room with them.
    if (isEmojiOnly(message.body)) {
      return GestureDetector(
        onTap: onOpenThread,
        onLongPress: canDelete ? onDelete : null,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            bottom: AppSpacing.xs,
            top: 2,
          ),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(message.body, style: const TextStyle(fontSize: 40)),
              Text(
                formatTime(message.createdAt),
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      // Long press, not a visible button on every bubble: the action is rare and
      // a delete icon beside four hundred messages is four hundred invitations
      // to press the wrong one.
      onTap: onOpenThread,
      onLongPress: canDelete ? onDelete : null,
      child: Container(
        margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: mine ? AppColors.brand : GlassColors.surface,
          borderRadius: BorderRadiusDirectional.only(
            topStart: const Radius.circular(AppRadius.card),
            topEnd: const Radius.circular(AppRadius.card),
            bottomStart: Radius.circular(mine ? AppRadius.card : 4),
            bottomEnd: Radius.circular(mine ? 4 : AppRadius.card),
          ).resolve(Directionality.of(context)),
          border: Border.all(
            color: mine ? AppColors.brand : GlassColors.stroke,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: mine ? AppColors.onFill : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatTime(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: mine
                    ? AppColors.onFill.withValues(alpha: 0.75)
                    : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «الإدارة» beside a name. Small, and it earns the room it takes: it is the
/// difference between an announcement and an opinion.
class _StaffTag extends StatelessWidget {
  const _StaffTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: AppColors.brandDeep,
        ),
      ),
    );
  }
}

/// The date, once, between two days of conversation.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.iso});

  final String iso;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider(color: GlassColors.wellEdge)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              formatDate(iso),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.muted,
              ),
            ),
          ),
          const Expanded(child: Divider(color: GlassColors.wellEdge)),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  /// Whether the emoji grid is showing INSTEAD of the system keyboard.
  ///
  /// The two are mutually exclusive on purpose: opening the panel dismisses the
  /// keyboard and tapping the text box closes the panel, so the message box
  /// never has two things fighting for the bottom half of a phone.
  bool _emoji = false;

  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// ⚠ AT THE CURSOR, not at the end. A member who taps back into the middle of
  ///   a sentence to add a heart expects it there, and appending would move his
  ///   caret to the end of a message he was not finished with.
  ///
  ///   The 1000-cap is re-checked here because writing to a controller skips the
  ///   TextField's maxLength formatter entirely — the picker would otherwise be
  ///   the one way to build a message the database refuses.
  void _insert(String emoji) {
    final TextEditingValue v = widget.controller.value;
    if (v.text.characters.length + emoji.characters.length > 1000) return;

    final int start = v.selection.start >= 0
        ? v.selection.start
        : v.text.length;
    final int end = v.selection.end >= 0 ? v.selection.end : v.text.length;

    widget.controller.value = TextEditingValue(
      text: v.text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  /// One CHARACTER, not one code unit. An emoji is two or more UTF-16 units and
  /// several of the ones in the panel are joined sequences — deleting by index
  /// would leave half a glyph behind, which renders as a replacement box.
  void _backspace() {
    final TextEditingValue v = widget.controller.value;
    final int end = v.selection.end >= 0 ? v.selection.end : v.text.length;
    if (end == 0) return;

    final int start = v.selection.start >= 0 ? v.selection.start : end;
    if (start != end) {
      widget.controller.value = TextEditingValue(
        text: v.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
      return;
    }

    final String before = v.text.substring(0, end);
    final int cut = before.characters.isEmpty
        ? 0
        : before.length - before.characters.last.length;
    widget.controller.value = TextEditingValue(
      text: v.text.replaceRange(cut, end, ''),
      selection: TextSelection.collapsed(offset: cut),
    );
  }

  void _toggleEmoji() {
    setState(() => _emoji = !_emoji);
    if (_emoji) {
      // Put the keyboard away rather than stacking the panel on top of it.
      FocusManager.instance.primaryFocus?.unfocus();
    } else {
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final TextEditingController controller = widget.controller;
    final bool sending = widget.sending;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            // ── THE SEND BUTTON WOULD SIT UNDER THE NAVIGATION PILL ─────────────
            // AppScaffold floats the bar over the body and publishes its height as
            // MediaQuery.padding.bottom; a screen that does not reserve it puts its
            // own controls beneath something the user cannot see through. Every
            // scrolling screen here already asks for it — a composer pinned to the
            // bottom needs it more than any of them, because a list can be scrolled
            // and a fixed row cannot.
            //
            // Caught by a widget test whose tap on the send button MISSED. Worth
            // saying out loud: the assertion that failed was about sending a
            // message, not about layout, and on a phone this reads as a button that
            // does nothing.
            // ⚠ AND THE SAME RESERVATION MOVES TO THE PANEL WHEN IT OPENS.
            //   The grid hangs BELOW this row, so with the pill's height still
            //   reserved here the panel is pushed down by it and its own last
            //   row — the backspace key — ends up underneath the floating bar.
            //   Exactly the bug the paragraph above describes, one widget
            //   further down, and caught the same way: by a test whose tap
            //   missed.
            AppSpacing.md +
                (_emoji ? 0 : bottomInset(context)) +
                MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              // ── The emoji key ────────────────────────────────────────────────
              // Before the field, where the system keyboard puts its own. The icon
              // says which state a second tap leads to, which is how every keyboard
              // toggle on the platform behaves.
              IconButton(
                onPressed: sending ? null : _toggleEmoji,
                icon: Icon(
                  _emoji
                      ? Icons.keyboard_alt_outlined
                      : Icons.emoji_emotions_outlined,
                ),
                tooltip: l.chatEmoji,
                color: AppColors.muted,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: _focus,
                  // Tapping the message box means "I want to type", so the grid
                  // gets out of the way by itself.
                  onTap: () {
                    if (_emoji) setState(() => _emoji = false);
                  },
                  enabled: !sending,
                  // Grows with the message and then stops. A composer that keeps
                  // growing pushes the conversation off the screen it belongs to.
                  minLines: 1,
                  maxLines: 4,
                  // The database refuses anything longer; stopping the keystroke is
                  // kinder than accepting six hundred more characters and then
                  // rejecting the lot.
                  maxLength: 1000,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    hintText: l.chatHint,
                    // The counter only matters near the cap, and a permanent
                    // «0/1000» under a chat box is clutter on every single screen.
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Send points the way the language reads: in Arabic, forward is
              // leftward, and `Directionality` is what makes the same icon correct
              // in both.
              IconButton.filled(
                onPressed: sending ? null : widget.onSend,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onFill,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                tooltip: l.chatSend,
              ),
            ],
          ),
        ),
        // ── The grid, where the keyboard would be ─────────────────────────────
        // Below the composer rather than above it, so the message box does not
        // jump when the panel opens — it occupies the space the keyboard just
        // left. Hidden entirely while a send is in flight: the controller is
        // read at that moment and a tap that edited it mid-send would put a
        // character into the room or lose one.
        if (_emoji && !sending)
          Padding(
            // The pill's height, handed over from the composer above.
            padding: EdgeInsets.only(bottom: bottomInset(context)),
            child: EmojiPanel(onPick: _insert, onBackspace: _backspace),
          ),
      ],
    );
  }
}

/// The board's inbox: who has written, and who is waiting for an answer.
///
/// Built from the MESSAGES rather than from the register, so a man who has never
/// written appears nowhere. An inbox listing every عديل with «لا رسائل» beside
/// him is a register, and the association already has one.
class _Inbox extends ConsumerWidget {
  const _Inbox({required this.onOpen});

  final void Function(ChatThread) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return AsyncView<List<ChatThread>>(
      value: ref.watch(chatThreadsProvider),
      onRetry: () => ref.invalidate(chatThreadsProvider),
      builder: (List<ChatThread> threads) {
        if (threads.isEmpty) {
          return EmptyStateView(
            icon: Icons.mark_email_read_outlined,
            title: l.chatInboxEmpty,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: threads.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (BuildContext context, int i) {
            final ChatThread t = threads[i];
            // WAITING is the question an inbox is opened with, and it is one
            // boolean: the last word was his, so nobody has answered yet.
            final bool waiting = !t.lastFromStaff;
            return GlassCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                onTap: () => onOpen(t),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                leading: Icon(
                  waiting
                      ? Icons.mark_email_unread_outlined
                      : Icons.mark_email_read_outlined,
                  color: waiting ? AppColors.brand : AppColors.muted,
                ),
                title: Text(
                  t.adeelName,
                  style: TextStyle(
                    fontWeight: waiting ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  // The last thing either side said — «هل ردّوا عليّ» and «من
                  // ينتظر رداً» are the same question from the two ends, and
                  // this line answers both.
                  t.lastBody.isEmpty ? l.chatDeleted : t.lastBody,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontStyle: t.lastBody.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
                trailing: Text(
                  formatDate(t.lastAt),
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Whose conversation the board is looking at, and the way back to the inbox.
///
/// Named on screen because a private thread has no other heading: the bubbles
/// carry «الإدارة» on one side and his name on the other only when he has
/// actually written, and an unanswered conversation would otherwise be a column
/// of one man's words with nothing saying who he is.
class _ThreadHeader extends StatelessWidget {
  const _ThreadHeader({required this.name, required this.onBack});

  final String name;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_forward, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

/// «رسائل جديدة» — the line where he stopped reading.
///
/// Red rather than muted, and it is the one place in this screen that uses the
/// alarm colour: everything else here is a conversation, and this is the only
/// mark that is about the READER rather than about what was said.
///
/// It appears once and does not move while the screen is open — see
/// `_unreadFrom`. A line that advanced as messages were marked read would end up
/// under the last bubble with nothing beneath it, which is worse than no line.
class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider(color: AppColors.danger, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.dangerSoft,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                l.chatNewMessages,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.danger,
                ),
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.danger, height: 1)),
        ],
      ),
    );
  }
}
