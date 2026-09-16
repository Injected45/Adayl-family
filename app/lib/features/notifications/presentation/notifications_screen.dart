import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/destinations.dart';
import '../../../core/state/refresh.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../directory/domain/models.dart';
import '../../directory/presentation/providers.dart' as directory;
import '../data/notifications_repository.dart';
import '../domain/models.dart';
import 'notice_detail_screen.dart';
import 'providers.dart';

/// الإشعارات — one screen, two readers.
///
/// ── WHAT A MEMBER SEES ──────────────────────────────────────────────────────
/// Everything the association told HIM: his receipts and their cancellations,
/// each month he was billed, a voucher paid to him — and what it told
/// everyone: collective spending and the admin's messages. Pushed from his bar,
/// like «الجدوى», because the router pins a portal account to /my-dues and a
/// push changes no location for it to redirect.
///
/// ── WHAT THE ADMIN SEES ─────────────────────────────────────────────────────
/// The box to write to everyone, and beneath it the log of every notice that
/// went out and to whom. He needs no permission beyond the one he has: the
/// database's `read_notifications_staff` and `send_broadcast` decide it.
///
/// ⚠ NOTHING HERE DECIDES WHO READS WHAT. The same query runs for both, and RLS
///   returns a member's own rows and the association's — never another man's
///   voucher. Delete the member policy and his list empties with no code change.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({this.portal = false, super.key});

  /// True when pushed from the member's portal, which has no AppScaffold.
  final bool portal;

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// ⚠ CAPTURED, NOT READ THROUGH ref IN dispose() — reading a ref there
  ///   asserts and aborts the rest of dispose. Same reason as the chat room.
  late final StateController<bool> _open;
  late final NoticesUnread _unread;

  /// The mark as it stood when he opened the screen, so the rows that were new
  /// stay marked as new while he reads them — even though opening the screen is
  /// what marks them read.
  int? _seenAtOpen;
  int _markedUpTo = 0;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _open = ref.read(noticesScreenOpenProvider.notifier);
    _unread = ref.read(noticesUnreadProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _open.state = true;
    });

    final String? uid = ref.read(authControllerProvider).user?.id;
    if (widget.portal && uid != null) {
      unawaited(
        ref
            .read(noticeReadStateProvider)
            .lastSeen(uid)
            .then((int seen) {
              if (mounted) setState(() => _seenAtOpen = seen);
            })
            .catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    // ⚠ AFTER THIS FRAME, NOT NOW. dispose() runs while the tree is locked,
    //   and writing a provider there asserts in a debug build — which aborted
    //   the rest of dispose the moment he backed out of the tab. Nobody went
    //   back out of it often enough to see that until a notice's page began
    //   returning him here (15/09).
    final StateController<bool> open = _open;
    Future<void>.microtask(() {
      if (open.mounted) open.state = false;
    });
    super.dispose();
  }

  /// Everything on screen has been seen. After the frame, and only when the
  /// newest id actually moved — the list re-renders on every tick.
  void _markSeen(List<AppNotice> notices) {
    if (!widget.portal || notices.isEmpty) return;
    final int newest = notices.first.id;
    if (newest <= _markedUpTo) return;
    _markedUpTo = newest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_unread.markSeen(newest));
    });
  }

  /// «مسح كل الإشعارات» — asks first, in red, with the count, then clears
  /// them for everyone.
  Future<void> _clearAll(int count) async {
    final L l = L.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        destructive: true,
        icon: const Icon(Icons.delete_sweep_outlined),
        title: Text(l.noticesClearTitle),
        content: Text(
          l.noticesClearBody(count),
          style: const TextStyle(height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.noticesClearConfirm),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      final int deleted = await ref
          .read(notificationsRepositoryProvider)
          .clearAll();
      ref.invalidate(noticesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(l.noticesCleared(deleted))),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, e))));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AppUser? user = ref.watch(authControllerProvider).user;
    final bool canBroadcast =
        !widget.portal &&
        user != null &&
        !user.isAdeelPortal &&
        user.role.atLeast(AppRole.admin);

    Widget list(BuildContext context) => RefreshIndicator(
      // The whole app, as every pull in it must be — and for a member the pull
      // is the only refresh there is. See core/state/refresh.dart.
      onRefresh: () async => refreshAll(ref),
      child: AsyncView<List<AppNotice>>(
        value: ref.watch(noticesProvider),
        onRetry: () => ref.invalidate(noticesProvider),
        builder: (List<AppNotice> notices) {
          _markSeen(notices);
          return _NoticeList(
            notices: notices,
            staff: !widget.portal,
            seenAtOpen: widget.portal ? _seenAtOpen : null,
            header: canBroadcast ? const _BroadcastComposer() : null,
            // The admin's red button, only while there is anything to clear.
            onClearAll: canBroadcast && notices.isNotEmpty
                ? (_clearing ? null : () => _clearAll(notices.length))
                : null,
            showClearAll: canBroadcast && notices.isNotEmpty,
          );
        },
      ),
    );

    if (widget.portal) {
      return AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(l.noticesTitle)),
          body: Builder(builder: list),
        ),
      );
    }

    return AppScaffold(
      title: l.noticesTitle,
      currentRoute: AppRoutes.notifications,
      body: list,
    );
  }
}

class _NoticeList extends StatelessWidget {
  const _NoticeList({
    required this.notices,
    required this.staff,
    required this.seenAtOpen,
    this.header,
    this.onClearAll,
    this.showClearAll = false,
  });

  final List<AppNotice> notices;
  final bool staff;
  final int? seenAtOpen;
  final Widget? header;

  /// «مسح كل الإشعارات». Null while a clear is running — the button stays,
  /// greyed, so a second tap cannot send it twice.
  final VoidCallback? onClearAll;
  final bool showClearAll;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xl + bottomInset(context),
      ),
      children: <Widget>[
        if (header != null) ...<Widget>[
          header!,
          const SizedBox(height: AppSpacing.xl),
          Text(
            l.noticesLogHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.noticesAdminRule,
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          // ── مسح كل الإشعارات ──────────────────────────────────────────
          // ⚠ RED, AND IT ASKS FIRST: it empties every member's list too, and
          //   nothing brings a deleted notice back. Alone in the column —
          //   a filled button is full width in this theme and asserts in a Row.
          if (showClearAll) ...<Widget>[
            FilledButton.icon(
              onPressed: onClearAll,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.onFill,
              ),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(l.noticesClearAll),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
        if (notices.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: _Empty(),
          )
        else
          for (final AppNotice n in notices)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: NoticeTile(
                notice: n,
                staff: staff,
                fresh: seenAtOpen != null && n.id > seenAtOpen!,
              ),
            ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return Column(
      children: <Widget>[
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(AppRadius.pane),
          ),
          child: Icon(
            Icons.notifications_none,
            size: 30,
            color: AppColors.brandDeep,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l.noticesEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l.noticesEmptyBody,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// One notice on the tab: its title, and nothing of what it says.
///
/// «اي اشعار موجود في تبويب الاشعار اجعله يظهر في حقل يظهر العنوان فقط وعند
/// الضغط عليه يظهر تفاصيل الاشعار» (15/09). The sentence, the full date and —
/// for the admin — whom it went to are all on [NoticeDetailScreen], one tap
/// away.
///
/// ⚠ THE DAY STAMP STAYS UNDER THE TITLE, small and muted, and that is the one
///   thing kept beside it. The database writes the SAME title for every notice
///   of a kind — «تم تسجيل سداد» for every receipt — so without it the tab is a
///   column of identical words with nothing to tell one from the next.
///
/// ⚠ THE TITLE WRAPS TO TWO LINES, THEN ENDS «…». The admin's own title may be
///   120 characters; the whole of it is on the detail page.
class NoticeTile extends StatelessWidget {
  const NoticeTile({
    required this.notice,
    required this.staff,
    this.fresh = false,
    super.key,
  });

  final AppNotice notice;
  final bool staff;
  final bool fresh;

  static (IconData, Color) look(NoticeKind kind) => switch (kind) {
    NoticeKind.receivable => (Icons.event_note_outlined, AppColors.dues),
    NoticeKind.payment => (Icons.check_circle_outline, AppColors.success),
    NoticeKind.disbursement => (
      Icons.volunteer_activism_outlined,
      AppColors.danger,
    ),
    NoticeKind.paymentCancelled ||
    NoticeKind.disbursementCancelled => (Icons.undo, AppColors.warning),
    NoticeKind.broadcast => (Icons.campaign_outlined, AppColors.brand),
    NoticeKind.proposal => (Icons.lightbulb_outline, AppColors.accent),
  };

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final (IconData icon, Color tone) = look(notice.kind);

    return GlassCard(
      borderColor: fresh ? AppColors.brand : null,
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      onTap: () => Navigator.of(
        context,
      ).push<void>(NoticeDetailScreen.route(notice, staff: staff)),
      child: Row(
        children: <Widget>[
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(icon, size: 20, color: tone),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  notice.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDayStamp(notice.createdAt, yesterday: l.chatYesterday),
                  style: TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (fresh) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(label: l.noticeNew, tone: AppColors.brand),
          ],
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_left, size: 20, color: AppColors.muted),
        ],
      ),
    );
  }
}

/// «رسالة إلى جميع المشتركين» — the admin's box.
///
/// ⚠ A CONFIRMATION, because this is the one button in the app that reaches
///   every member's phone at once and cannot be taken back. The notice is a
///   row other people have already read by the time a mistake is noticed.
///
/// ⚠ THE LIMITS ARE THE DATABASE'S, REPEATED FOR CONVENIENCE ONLY: 120 for the
///   title, 1000 for the text, both trimmed. `send_broadcast` enforces them
///   and its RUL18 sentence is what reaches the screen if they ever disagree.
class _BroadcastComposer extends ConsumerStatefulWidget {
  const _BroadcastComposer();

  @override
  ConsumerState<_BroadcastComposer> createState() => _BroadcastComposerState();
}

class _BroadcastComposerState extends ConsumerState<_BroadcastComposer> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _sending = false;

  /// ── إلى مَن ────────────────────────────────────────────────────────────────
  /// «كل المشتركين» أو «مشتركون محدَّدون». The association asked for the second
  /// to demand a subscription from one man without telling the other seven, and
  /// the first is untouched: two different RPCs, `send_broadcast` writing ONE
  /// row for everybody and `send_notice` writing one row per man.
  bool _toAll = true;

  /// Ids, not names: the RPC takes ids and the register is the only thing that
  /// turns one into the other. Kept here rather than in a provider so leaving
  /// the tab forgets a half-made selection.
  final Set<int> _picked = <int>{};

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// The picker, over the register the admin already reads.
  Future<void> _pick(L l, List<AdeelListItem> members) async {
    final Set<int>? chosen = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) =>
          _MemberPickerSheet(members: members, initial: _picked),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _picked
        ..clear()
        ..addAll(chosen);
    });
  }

  Future<void> _send(L l) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (_body.text.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.broadcastEmpty)));
      return;
    }
    if (!_toAll && _picked.isEmpty) {
      // ⚠ Cleared first: a second refusal queues behind the first and is read
      //   as the button doing nothing.
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.noticePickNone)));
      return;
    }

    final int count = _picked.length;
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        icon: Icon(_toAll ? Icons.campaign_outlined : Icons.person_outline),
        title: Text(_toAll ? l.broadcastConfirmTitle : l.noticeSendTitle),
        content: Text(
          _toAll ? l.broadcastConfirmBody : l.noticeSendBody(count),
          style: const TextStyle(height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.broadcastSend),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final NotificationsRepository repo = ref.read(
        notificationsRepositoryProvider,
      );
      if (_toAll) {
        await repo.sendBroadcast(title: _title.text, body: _body.text);
      } else {
        await repo.sendNotice(
          adeelIds: _picked.toList(),
          title: _title.text,
          body: _body.text,
        );
      }
      if (!mounted) return;
      _title.clear();
      _body.clear();
      setState(_picked.clear);
      ref.invalidate(noticesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_toAll ? l.broadcastSent : l.noticeSentTo(count)),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    // The register, read only to turn a tick into an id and a name onto a chip.
    // The admin already holds it; this adds no endpoint and no provider.
    final AsyncValue<List<AdeelListItem>> members = ref.watch(
      directory.adeelsProvider(''),
    );
    final List<AdeelListItem> list =
        members.valueOrNull ?? const <AdeelListItem>[];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.campaign_outlined, color: AppColors.brand),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l.broadcastHeading,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── إلى مَن ──────────────────────────────────────────────────────
          // Explicit, never inferred from whether anyone is ticked: a message
          // meant for one man and sent to eight cannot be recalled.
          SegmentedButton<bool>(
            segments: <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: true,
                label: Text(l.noticeToAll),
                icon: const Icon(Icons.groups_outlined, size: 18),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text(l.noticeToPicked),
                icon: const Icon(Icons.person_outline, size: 18),
              ),
            ],
            selected: <bool>{_toAll},
            showSelectedIcon: false,
            onSelectionChanged: _sending
                ? null
                : (Set<bool> v) => setState(() => _toAll = v.first),
          ),
          if (!_toAll) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            // ⚠ Alone in the column: an outlined button is full width in this
            //   theme and asserts inside a Row. See CLAUDE.md.
            OutlinedButton.icon(
              onPressed: _sending || list.isEmpty ? null : () => _pick(l, list),
              icon: const Icon(Icons.checklist_rtl),
              label: Text(
                _picked.isEmpty
                    ? l.noticePickMembers
                    : l.noticePickedCount(_picked.length),
              ),
            ),
            if (_picked.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: list
                    .where((AdeelListItem a) => _picked.contains(a.id))
                    .map(
                      (AdeelListItem a) => InputChip(
                        label: Text(a.fullName),
                        isEnabled: !_sending,
                        onDeleted: _sending
                            ? null
                            : () => setState(() => _picked.remove(a.id)),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _title,
            enabled: !_sending,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: l.broadcastTitleLabel,
              hintText: l.broadcastTitleHint,
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _body,
            enabled: !_sending,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: l.broadcastBodyLabel,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // ⚠ ALONE IN THE COLUMN, NEVER IN A ROW: a filled button is full
          //   width in this theme and asserts inside a Row. See CLAUDE.md.
          FilledButton.icon(
            onPressed: _sending ? null : () => _send(l),
            icon: _sending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onFill,
                    ),
                  )
                : const Icon(Icons.send),
            label: Text(l.broadcastSend),
          ),
        ],
      ),
    );
  }
}

/// «اختر المشتركين» — the register with a tick beside each man.
///
/// ⚠ IT OWNS ITS OWN COPY AND RETURNS IT ON «تم». Ticking rows that write
///   straight into the composer's set would leave a half-made selection behind
///   when the sheet is dismissed by a swipe, and the admin would then send to
///   whoever he happened to have touched. Cancel means cancel.
///
/// ⚠ The search FILTERS and never unticks: a man ticked before a search is
///   still ticked after it, even while he is off screen — which is what the
///   count above the list is there to say.
class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.members, required this.initial});

  final List<AdeelListItem> members;
  final Set<int> initial;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  late final Set<int> _chosen = <int>{...widget.initial};
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AdeelListItem> get _shown {
    final String q = _query.trim();
    if (q.isEmpty) return widget.members;
    return widget.members
        .where(
          (AdeelListItem a) =>
              a.fullName.contains(q) ||
              a.adeelCode.contains(q) ||
              a.phone.contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final List<AdeelListItem> shown = _shown;

    return GlassSheet(
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l.noticePickerTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        // ⚠ IconButton, not a text button: a filled/outlined
                        //   button is full width in this theme and asserts in
                        //   a Row.
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: l.noticePickerSearch,
                      ),
                      onChanged: (String v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l.noticePickedCount(_chosen.length),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        // ⚠ ONE BUTTON THAT TURNS OVER, not two side by side:
                        //   «تحديد الكل» and «مسح التحديد» together overflowed
                        //   a 320-wide phone by 91px, and the second is only
                        //   ever wanted once the first has been used.
                        TextButton(
                          onPressed: () => setState(() {
                            if (_chosen.length == widget.members.length) {
                              _chosen.clear();
                            } else {
                              _chosen
                                ..clear()
                                ..addAll(
                                  widget.members.map((AdeelListItem a) => a.id),
                                );
                            }
                          }),
                          child: Text(
                            _chosen.length == widget.members.length
                                ? l.noticePickerNone
                                : l.noticePickerAll,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (BuildContext context, int index) {
                    final AdeelListItem a = shown[index];
                    return CheckboxListTile(
                      value: _chosen.contains(a.id),
                      onChanged: (bool? on) => setState(() {
                        if (on ?? false) {
                          _chosen.add(a.id);
                        } else {
                          _chosen.remove(a.id);
                        }
                      }),
                      title: Text(a.fullName),
                      subtitle: Text(
                        a.adeelCode,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_chosen),
                  icon: const Icon(Icons.check),
                  label: Text(l.noticePickerDone),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
