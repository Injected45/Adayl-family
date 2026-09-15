import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notify/notifier.dart';
import '../../../core/notify/notify_text.dart';
import '../../../core/router/destinations.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../auth/domain/app_user.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../notifications/domain/models.dart';
import '../../notifications/presentation/providers.dart';
import '../data/proposals_repository.dart';
import '../domain/models.dart';

final Provider<ProposalsRepository> proposalsRepositoryProvider =
    Provider<ProposalsRepository>(
      (Ref ref) => ProposalsRepository(ref.watch(supabaseClientProvider)),
    );

/// For the admin every proposal; for a member his own. In `refreshAll`, so a
/// decision reaches the member's list on the next sweep.
final FutureProvider<List<Proposal>> proposalsProvider =
    FutureProvider<List<Proposal>>((Ref ref) {
      // ⚠ AND RE-READ WHEN THE WAITING COUNT MOVES, so a proposal arriving
      //   while the admin has the tab open appears on it without a pull. For a
      //   member the count is always zero and this watches nothing that moves.
      ref.watch(
        proposalsWaitingProvider.select((AsyncValue<int> v) => v.valueOrNull),
      );
      return ref.watch(proposalsRepositoryProvider).list();
    });

/// Whether «مقترحات المشتركين» is the screen in front of the admin — nothing
/// is announced about a proposal he is watching arrive.
final StateProvider<bool> proposalsScreenOpenProvider = StateProvider<bool>(
  (Ref ref) => false,
);

/// What one reading of the waiting proposals means for the admin's alert.
enum ProposalAlert {
  /// The first reading after (re)building: it learns what was already
  /// waiting, and announcing that would greet every launch with old news.
  arm,

  /// A proposal newer than any seen before has arrived.
  announce,

  /// Nothing new — or he is looking at the tab.
  none,
}

/// ⚠ BY THE NEWEST ID, NOT BY THE COUNT. A count cannot tell «one decided and
///   one arrived in the same ten seconds» from «nothing happened»; the newest
///   waiting id can.
ProposalAlert decideProposalAlert({
  required bool armed,
  required int lastSeenId,
  required int newestId,
  required bool onScreen,
}) {
  if (!armed) return ProposalAlert.arm;
  if (onScreen || newestId <= lastSeenId) return ProposalAlert.none;
  return ProposalAlert.announce;
}

class _OnResume with WidgetsBindingObserver {
  _OnResume(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}

/// How many proposals wait for the admin's decision — the red number on
/// «المزيد» and on «مقترحات المشتركين» — and the alert when a new one lands.
///
/// «مقترح جديد من فلان»: the in-app banner for twenty seconds while the app is
/// in front of him, the phone's notification when it is not. A tap on either
/// opens the tab.
///
/// ⚠ THE ADMIN ONLY. A member's own proposals need no alert — he sent them.
///
/// ⚠ NOT AUTO-DISPOSED, for the notices' reason: the badge must survive the
///   screens that show it, and the background heartbeat pokes it in a pocket.
///   It watches only WHO is signed in, because the session emits a new state
///   every forty-five seconds and a rebuild re-arms silently.
///
/// ⚠ A POLL, TEN SECONDS, NO DOORBELL. Nothing in the database rings when a
///   proposal is sent, and a proposal is not a call: ten seconds is prompt, and
///   the query is one capped column.
class ProposalsWaiting extends AsyncNotifier<int> {
  static const Duration interval = Duration(seconds: 10);

  Timer? _timer;
  int _generation = 0;
  bool _admin = false;
  bool _armed = false;
  bool _busy = false;
  int _lastSeenId = 0;

  @override
  Future<int> build() async {
    _stop();
    final int generation = ++_generation;
    _armed = false;
    _lastSeenId = 0;

    final ({String? id, AccountStatus? status, bool admin}) who = ref.watch(
      authControllerProvider.select(
        (AuthState s) => (
          id: s.user?.id,
          status: s.user?.status,
          admin:
              s.user != null &&
              !s.user!.isAdeelPortal &&
              s.user!.role.atLeast(AppRole.admin),
        ),
      ),
    );
    _admin =
        who.id != null && who.status == AccountStatus.approved && who.admin;
    if (!_admin) return 0;

    // Initialising is what hears a tap on the phone's alert.
    unawaited(AppNotifier.init());

    final _OnResume resume = _OnResume(() => _tick(generation));
    WidgetsBinding.instance.addObserver(resume);
    ref.onDispose(() {
      _stop();
      WidgetsBinding.instance.removeObserver(resume);
    });
    _timer = Timer.periodic(interval, (_) => _tick(generation));

    final List<int> ids = await ref
        .read(proposalsRepositoryProvider)
        .waitingIds();
    if (generation == _generation) {
      _armed = true;
      _lastSeenId = ids.isEmpty ? 0 : ids.first;
    }
    return ids.length;
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick(int generation) async {
    if (!_admin || _busy || generation != _generation) return;
    _busy = true;
    try {
      final List<int> ids = await ref
          .read(proposalsRepositoryProvider)
          .waitingIds();
      if (generation != _generation) return;
      final int newest = ids.isEmpty ? 0 : ids.first;

      switch (decideProposalAlert(
        armed: _armed,
        lastSeenId: _lastSeenId,
        newestId: newest,
        onScreen: ref.read(proposalsScreenOpenProvider),
      )) {
        case ProposalAlert.arm:
          _armed = true;
        case ProposalAlert.announce:
          final int fresh = ids.where((int id) => id > _lastSeenId).length;
          unawaited(_announce(newest, fresh, generation));
        case ProposalAlert.none:
          break;
      }
      if (newest > _lastSeenId) _lastSeenId = newest;
      state = AsyncValue<int>.data(ids.length);
    } on Object {
      // A failed poll leaves the badge as it was.
    } finally {
      _busy = false;
    }
  }

  Future<void> _announce(int id, int fresh, int generation) async {
    Proposal? p;
    try {
      p = await ref.read(proposalsRepositoryProvider).byId(id);
    } on Object {
      p = null;
    }
    if (p == null || generation != _generation) return;

    final String title = NotifyText.proposalFrom(p.adeelName);
    switch (decideNoticeDelivery(
      foreground: appInForeground(),
      haveNotice: true,
    )) {
      case NoticeDelivery.banner:
        ref
            .read(noticePeekProvider.notifier)
            .show(
              AppNotice(
                id: -p.id,
                audience: 'staff',
                kind: NoticeKind.proposal,
                title: title,
                body: p.title,
                createdAt: p.createdAt,
              ),
              more: fresh - 1,
              route: AppRoutes.proposals,
            );
      case NoticeDelivery.phone:
        unawaited(
          AppNotifier.proposal(
            title,
            fresh > 1 ? NotifyText.noticeAndMore(p.title, fresh - 1) : p.title,
            AppRoutes.proposals,
          ),
        );
    }
  }

  /// اسأل الآن — from the background heartbeat, and after a decision.
  Future<void> refresh() => _tick(_generation);
}

final AsyncNotifierProvider<ProposalsWaiting, int> proposalsWaitingProvider =
    AsyncNotifierProvider<ProposalsWaiting, int>(ProposalsWaiting.new);
