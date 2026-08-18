import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../finance/domain/models.dart';
import '../../finance/presentation/adeel_aid_screen.dart';
import '../../finance/presentation/providers.dart';
import '../domain/models.dart';
import 'providers.dart';

/// Column shares, summing to 100: البيان | مدين | دائن | الرصيد.
///
/// Shares, not pixels: four fixed columns needed 448dp and a Galaxy Note 10 has
/// 360, so the table used to scroll sideways. Proportions fit every screen and
/// every system font size by construction, and the table is exactly as wide as
/// the card — never one pixel more, whatever the figures are.
///
/// مدين and دائن were briefly ONE column, on the grounds that a movement is
/// never both and the screen had no width to spare. That is true of the rows
/// and false of the LEDGER: a statement is read down its columns — everything
/// charged on one side, everything received on the other — and a merged column
/// where colour carries the distinction cannot be read that way at all. It also
/// left the totals row with four cells above three, so the closing figures did
/// not line up with the column they belonged to.
///
/// The width is bought back from the particulars, which hold short text (a
/// month name, a payment method) rather than figures, and from the subtitle,
/// which no longer repeats a movement's type now that the column it sits in
/// says it.
const int _particularsFlex = 34;
const int _moneyFlex = 22;

/// The ledger runs SMALLER than the rest of the portal, on purpose.
///
/// Everywhere else the type was raised for legibility. A four-column table on a
/// 360dp phone is a different constraint from prose: at 15pt a four-figure
/// amount overflows its 22% column, FittedBox shrinks that ONE cell, and a
/// column of figures where some rows are smaller than others is harder to read
/// down than a column that is uniformly a point smaller.
///
/// So the size is chosen to fit the widest amount the association will
/// realistically show — thousands, with separators — at full size, which makes
/// the shrink path a genuine last resort rather than the normal case.
const double _ledgerMoneySize = 12;

/// What stands in the money column a movement did not touch.
///
/// An em dash, not an empty cell: blank reads as a figure that failed to load,
/// and on a statement that is the worst possible ambiguity. Not a localised
/// string either — it is punctuation, identical in both languages, and putting
/// it in the ARB would invite it being "translated".
const String _absent = '—';
const double _ledgerHeadSize = 12;
const double _ledgerTitleSize = 14;
const double _ledgerNoteSize = 12;

/// What an عديل sees: his own record and his own money, and nothing of the
/// association's.
///
/// Deliberately NOT an AppScaffold. That widget carries the navigation bar, and
/// every destination on it is a screen he must not reach — the router refuses
/// him anyway, so offering the tabs and then bouncing him back would be a worse
/// interface than not offering them at all.
///
/// It reuses `api_adeel_detail` and `api_adeel_statement` rather than adding
/// portal-only endpoints. Both are SECURITY INVOKER, so the very call an admin
/// makes returns only what RLS allows THIS caller — one عديل. A separate
/// endpoint would be a second place for the scoping to be got wrong, and only
/// one of them would be covered by supabase/tests/45_adeel_portal.sql.
class AdeelPortalScreen extends ConsumerWidget {
  const AdeelPortalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AuthState auth = ref.watch(authControllerProvider);
    final int? adeelId = auth.user?.adeelId;

    // The router guarantees this. Without it, the frame between redeeming a
    // code and the redirect landing would be a crash rather than a spinner.
    if (adeelId == null) return const LoadingStateView();

    // ── The wrong handset ────────────────────────────────────────────────────
    // His code opens on ONE device. `my_adeel_id()` already returns NULL here,
    // so RLS would hand this screen an empty register, an empty ledger and a
    // zero balance — a page that looks broken rather than closed.
    //
    // Said in words instead, with the sign-out button kept: the man holding the
    // wrong phone needs a way out of this screen, and telling him to ring the
    // association is the only action that can actually resolve it. Only an
    // admin reissuing his code releases the lock.
    if (auth.user?.deviceLocked ?? false) {
      return CenteredMessage(
        icon: Icons.phonelink_lock_outlined,
        iconColor: AppColors.warning,
        title: l.deviceLockedTitle,
        body: l.deviceLockedBody,
        footnote: auth.user?.adeelCode,
        actions: <Widget>[
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: Text(l.signOut),
          ),
        ],
      );
    }

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        l.myFamilyTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    // ── المزيد ──────────────────────────────────────────────
                    // Everything about HIM that is not a figure: his own
                    // details, where to send a transfer, who to ring, and the
                    // way out. Signing out moved inside it — it is the least
                    // used control on the screen and it was occupying the only
                    // action slot the header has.
                    //
                    // The sheet holds nothing the association owns. Every item
                    // in it is already readable to him under RLS: his own row
                    // through my_adeel_id(), and the bank account and officials
                    // through read_settings_adeel, which exists precisely
                    // because he is the man being asked to pay.
                    IconButton(
                      onPressed: () => _showPortalMore(context, adeelId),
                      icon: const Icon(Icons.grid_view_rounded),
                      tooltip: l.navMore,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AsyncView<AdeelDetail>(
                  value: ref.watch(adeelDetailProvider(adeelId)),
                  onRetry: () => ref.invalidate(adeelDetailProvider(adeelId)),
                  builder: (AdeelDetail data) => RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(adeelDetailProvider(adeelId));
                      ref.invalidate(statementProvider(adeelId));
                    },
                    child: _PortalBody(adeelId: adeelId, detail: data),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The subscriber's account, arranged the way an account is actually read.
///
/// ── What was wrong with showing everything at once ──────────────────────────
/// The page used to be one scroll: an identity card, then every receivable he
/// has ever had, then the whole ledger. Three things of equal visual weight,
/// none of them answering first. A member opening this has ONE question, and
/// the old layout made him assemble the answer himself by adding tiles.
///
/// ── The order an account is read in ─────────────────────────────────────────
/// An account statement answers three questions, and their urgency is not
/// equal:
///
///   1. WHAT DO I OWE, right now.        → one figure, unmissable
///   2. WHAT IS IT MADE OF.              → the months still open
///   3. SHOW ME EVERYTHING.              → the full ledger, on request
///
/// So the balance is the hero, the identity — which he confirmed the moment he
/// redeemed his code and never needs again — is demoted to something he can
/// open, and (2) and (3) share the space through a segmented control instead of
/// stacking. One question is answered at a time, which is the difference
/// between a statement and a pile of figures.
///
/// The totals strip under the hero is deliberate accounting: `مستحق − مدفوع =
/// الرصيد` reads left to right as the identity it is, so the hero figure is not
/// a number he has to trust but one he can see derived.
class _PortalBody extends ConsumerStatefulWidget {
  const _PortalBody({required this.adeelId, required this.detail});

  final int adeelId;
  final AdeelDetail detail;

  @override
  ConsumerState<_PortalBody> createState() => _PortalBodyState();
}

enum _PortalTab { dues, ledger }

class _PortalBodyState extends ConsumerState<_PortalBody> {
  /// Dues first: "what do I owe" is why he opened the app. The ledger is the
  /// follow-up question, and it is one tap away rather than a scroll away.
  _PortalTab _tab = _PortalTab.dues;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AdeelDetail detail = widget.detail;
    final AsyncValue<Statement> statement = ref.watch(
      statementProvider(widget.adeelId),
    );

    // Only what is still owed. A settled month is history: it belongs in the
    // ledger, where it sits in date order beside the payment that settled it,
    // not in a list headed "your dues" where it reads as an outstanding demand.
    final List<ReceivableItem> open = <ReceivableItem>[
      for (final ReceivableItem r in detail.receivables)
        if (r.status != ReceivableStatusWire.fullyPaid &&
            r.status != ReceivableStatusWire.cancelled)
          r,
    ];

    return ListView(
      // The عديل pulls this to refresh after paying, and his page is SHORT —
      // one hero, one strip, a handful of months. Without always-scrollable
      // physics that is precisely the page whose pull does nothing.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: screenPadding(context),
      children: <Widget>[
        _BalanceHero(detail: detail, openCount: open.length),
        const SizedBox(height: AppSpacing.md),
        _TotalsStrip(detail: detail),
        const SizedBox(height: AppSpacing.md),

        // ── ما صُرف لك ────────────────────────────────────────────────────────
        // A button on the FACE of the portal, not a row inside the more-sheet.
        // What the association has given a man over the years is one of the two
        // things he comes to this app to look up, and burying it two taps deep
        // beside the bank account would have said it was incidental.
        //
        // It opens a screen rather than expanding in place, and that is the
        // whole reason it is a button: this page answers «ما عليك», and putting
        // «ما صُرف لك» underneath it in the same scroll invites the eye to
        // subtract one from the other. الجمعية خيرية — aid is never deducted
        // from a subscription, and the two figures must not share a column.
        _MyAidButton(adeelId: widget.adeelId),
        const SizedBox(height: AppSpacing.xl),

        SegmentedButton<_PortalTab>(
          segments: <ButtonSegment<_PortalTab>>[
            ButtonSegment<_PortalTab>(
              value: _PortalTab.dues,
              label: Text(l.myDuesTitle),
              icon: const Icon(Icons.event_note_outlined, size: 18),
            ),
            ButtonSegment<_PortalTab>(
              value: _PortalTab.ledger,
              label: Text(l.myStatementSection),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
            ),
          ],
          selected: <_PortalTab>{_tab},
          showSelectedIcon: false,
          onSelectionChanged: (Set<_PortalTab> value) =>
              setState(() => _tab = value.first),
        ),
        const SizedBox(height: AppSpacing.lg),

        if (_tab == _PortalTab.dues)
          if (open.isEmpty)
            // Not an empty list but an ANSWER. "Nothing is owed" is the best
            // news this screen can carry and it should read like it, rather
            // than like a section that failed to load.
            EmptyStateView(
              icon: Icons.verified_outlined,
              title: l.settledUpTitle,
              message: l.settledUpBody,
            )
          else
            for (final ReceivableItem item in open) _DueTile(item: item)
        else
          statement.when(
            loading: () => const LoadingStateView(),
            error: (Object error, StackTrace _) =>
                ErrorStateView(message: describeApiFailure(l, error)),
            data: (Statement data) => _Ledger(statement: data, detail: detail),
          ),

      ],
    );
  }
}

/// Everything about him that is not a figure.
///
/// The portal answers one question on its face — what do I owe — and the rest
/// of what a member occasionally needs was either crowding that answer or had
/// nowhere to live at all. This is where it went:
///
///   • his own details, which used to be a panel at the foot of the page;
///   • the association's bank account, which he had NO way to see and is the
///     man being asked to transfer to it;
///   • the treasurer and the finance manager, with their numbers, so "who do I
///     ring about this" has an answer inside the app;
///   • signing out.
///
/// ── Nothing here is a new privilege ─────────────────────────────────────────
/// Every item is already readable to him under the policies in
/// 20260811090500_rls.sql. His own row comes through `my_adeel_id()`, and the
/// bank account and the officials come through `read_settings_adeel`, which was
/// written for exactly this reason: "he is being billed by these figures, so
/// withholding them would make his own statement unreadable... that is who he
/// pays." Not one line of SQL changed to build this screen, and if a policy
/// ever tightened, these sections would empty out rather than leak.
///
/// There is deliberately no "settings" section. A member has nothing he can
/// configure — every writable setting belongs to the association — and a page
/// of controls that save nothing is worse than no page.
void _showPortalMore(BuildContext context, int adeelId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.ink.withValues(alpha: 0.22),
    builder: (BuildContext sheetContext) => _PortalMoreSheet(adeelId: adeelId),
  );
}

/// «ما صُرف لك» — the way into his aid ledger, carrying the figure.
///
/// The total is on the button on purpose. A button labelled only «ما صُرف لك»
/// makes a man tap it to find out whether the answer is "nothing", and for most
/// members it will be; carrying the figure answers the common case without a
/// navigation, and turns the tap into "show me the detail" rather than "tell me
/// if there is any".
///
/// It shows even at zero. Hiding it would leave him wondering whether the
/// association keeps such a record at all — and «0.00» is an answer.
///
/// Navigator.push, not go_router: a portal account is pinned to /my-dues by the
/// route guard, and an imperative push does not change the location, so the
/// guard has nothing to redirect. That is presentation either way — RLS scopes
/// the rows to him whatever screen he reaches.
class _MyAidButton extends ConsumerWidget {
  const _MyAidButton({required this.adeelId});

  final int adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<AdeelAid> aid = ref.watch(adeelAidProvider(adeelId));

    return OutlinedButton(
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => AdeelAidScreen(adeelId: adeelId, mine: true),
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.volunteer_activism_outlined, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l.myAidTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          // Silent while it loads or fails: the button's job is to open the
          // screen, and a spinner or an error string on a label would make an
          // aside look like the point.
          Text(
            formatMoney(aid.valueOrNull?.total ?? '0.00'),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Icon(Icons.chevron_left, size: 18),
        ],
      ),
    );
  }
}

class _PortalMoreSheet extends ConsumerWidget {
  const _PortalMoreSheet({required this.adeelId});

  final int adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<AdeelDetail> detail = ref.watch(
      adeelDetailProvider(adeelId),
    );
    final AsyncValue<AssociationSettingsView> settings = ref.watch(
      settingsProvider,
    );
    final AsyncValue<List<Official>> officials = ref.watch(officialsProvider);
    final AsyncValue<AssociationFinance> finance = ref.watch(
      associationFinanceProvider,
    );

    return GlassSurface(
      lifted: true,
      fill: GlassColors.overlay,
      margin: const EdgeInsets.all(AppSpacing.md),
      child: SafeArea(
        child: ConstrainedBox(
          // Never taller than three quarters of the phone: a sheet that fills
          // the screen is a page wearing the wrong shape, and the balance
          // behind it is what tells him he has not left the portal.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.inkMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── His own details ────────────────────────────────────────────
              _SheetSection(icon: Icons.badge_outlined, title: l.myDetailsTitle),
              detail.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (Object e, StackTrace _) =>
                    _SheetNote(describeApiFailure(l, e)),
                data: (AdeelDetail d) => Column(
                  children: <Widget>[
                    _SheetRow(label: l.fullNameField, value: d.adeel.fullName),
                    _SheetRow(label: l.receiptNo, value: d.adeel.adeelCode),
                    _SheetRow(
                      label: l.statusLabel,
                      value: d.adeel.membershipStatus,
                    ),
                    _SheetRow(label: l.phone, value: d.adeel.phone),
                    _SheetRow(
                      label: l.registeredAt,
                      value: formatDate(d.adeel.registeredAt),
                    ),
                    _SheetRow(
                      label: l.monthlyFeeLabel,
                      value: formatMoney(d.monthlyExpected),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Where to send a transfer ───────────────────────────────────
              // He is the one being asked to pay and, until now, the app never
              // told him where. `read_settings_adeel` was written for this.
              _SheetSection(
                icon: Icons.account_balance_outlined,
                title: l.bankAccountSection,
              ),
              settings.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (Object e, StackTrace _) =>
                    _SheetNote(describeApiFailure(l, e)),
                data: (AssociationSettingsView s) => !s.hasBankAccount
                    ? _SheetNote(l.bankAccountNotSetYet)
                    : Column(
                        children: <Widget>[
                          _SheetRow(label: l.bankNameField, value: s.bankName),
                          // COPYABLE, and only this one. An account number is
                          // the single field here where retyping a digit sends
                          // the money to a stranger.
                          _SheetRow(
                            label: l.bankAccountNoField,
                            value: s.bankAccountNo,
                            copyable: true,
                          ),
                          _SheetRow(
                            label: l.bankAccountNameField,
                            value: s.bankAccountName,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Who to ring ────────────────────────────────────────────────
              _SheetSection(
                icon: Icons.contact_phone_outlined,
                title: l.navOfficials,
              ),
              officials.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (Object e, StackTrace _) =>
                    _SheetNote(describeApiFailure(l, e)),
                data: (List<Official> people) => Column(
                  children: <Widget>[
                    for (final Official o in people)
                      _SheetRow(
                        label: switch (o.role) {
                          OfficialRoleWire.treasurer => l.treasurerSection,
                          OfficialRoleWire.financeManager =>
                            l.financeManagerSection,
                          _ => o.role,
                        },
                        value: o.name.isEmpty ? l.notAssigned : o.name,
                        trailing: o.phone.isEmpty ? null : o.phone,
                        copyable: o.phone.isNotEmpty,
                        copyText: o.phone,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── الصندوق, for a member to READ ──────────────────────────────
              // "شفافية مطلقة": where the collective money stands, shown to the
              // people it belongs to.
              //
              // It comes from api_association_finance(), NOT from the treasury
              // view the admin screen uses. That view is SECURITY INVOKER and
              // his RLS scopes cash_movements to `adeel_id = my_adeel_id()`, so
              // pointing this at it would have shown him HIS OWN four figures
              // under headings that say "the association's" — not a leak,
              // something worse: a wrong answer he had no way to doubt.
              //
              // Aggregates only: no name, no receipt, no per-member figure. And
              // no action anywhere on it — the note under it says so, because a
              // member seeing the treasury for the first time will reasonably
              // wonder whether he is meant to do something about it.
              _SheetSection(
                icon: Icons.savings_outlined,
                title: l.navCash,
              ),
              finance.when(
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (Object e, StackTrace _) =>
                    _SheetNote(describeApiFailure(l, e)),
                data: (AssociationFinance f) => Column(
                  children: <Widget>[
                    _SheetRow(
                      label: l.collectedCash,
                      value: formatMoney(f.cash),
                    ),
                    _SheetRow(
                      label: l.collectedTransfer,
                      value: formatMoney(f.transfer),
                    ),
                    _SheetRow(
                      label: l.dueFromMembers,
                      value: formatMoney(f.outstanding),
                    ),
                    // The outgoing side. Transparency that showed only what
                    // came in would overstate the fund by everything it has
                    // ever paid out — which is the opposite of transparency.
                    // The TOTAL is his to see; who received it is not.
                    _SheetRow(
                      label: l.totalDisbursed,
                      value: formatMoney(f.disbursed),
                    ),
                    _SheetRow(
                      label: l.associationBalance,
                      value: formatMoney(f.balance),
                    ),
                    _SheetRow(
                      label: l.statAdeels,
                      value: '${f.members}',
                      trailing: l.subActive(f.activeMembers),
                    ),
                    _SheetNote(l.treasuryReadOnlyNote),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  ref.read(authControllerProvider.notifier).signOut();
                },
                icon: const Icon(Icons.logout, color: AppColors.danger),
                label: Text(
                  l.signOut,
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
    child: Row(
      children: <Widget>[
        Icon(icon, size: 18, color: AppColors.brandDeep),
        const SizedBox(width: AppSpacing.sm),
        // Expanded, because a section heading is the one thing here whose width
        // is not under this file's control: "الحساب المصرفي للجمعية" at a large
        // system font overflows the row by a pixel or two, and an overflow is a
        // rendering error rather than a cosmetic one.
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _SheetNote extends StatelessWidget {
  const _SheetNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.value,
    this.trailing,
    this.copyable = false,
    this.copyText,
  });

  final String label;
  final String value;
  final String? trailing;
  final bool copyable;
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final String shown = value.trim().isEmpty ? l.notProvided : value;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  shown,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailing != null && trailing!.trim().isNotEmpty)
                  Text(
                    trailing!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l.copy,
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: copyText ?? value),
                );
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(content: Text(l.copied)));
              },
            ),
        ],
      ),
    );
  }
}

/// WHO he is, then WHAT he owes — one card, in that order.
///
/// The name used to live in a collapsed panel at the FOOT of the page, under
/// the dues and the ledger, so the man reading his own statement had to scroll
/// past everything to find his own name and never saw it. A statement is
/// addressed to somebody; the figure means nothing until you know whose it is.
///
/// So the two are one block now, separated by a hairline rather than by the
/// length of the page: identity on top, the balance under it in the same
/// frame, aligned to the same edge. What stayed behind in the panel at the
/// bottom is detail — phone, join date, monthly fee — which is reference, not
/// address.
///
/// The figure keeps the whole width and a tone that states the answer before
/// the number is read: owing is warm, settled is green. The subtitle turns it
/// into a sentence — a balance with no count of months behind it invites
/// "since when?" and sends him to the ledger to find out.
class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.detail, required this.openCount});

  final AdeelDetail detail;
  final int openCount;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AdeelView adeel = detail.adeel;

    // ── THREE states now, not two ────────────────────────────────────────────
    // The association opened the door to prepayment, so a member is no longer
    // either in debt or square: he can be holding credit with the association,
    // and the figure that describes him has a SIGN.
    //
    //   owes      → red.    What he must pay.
    //   in credit → green.  What the association is holding for him, which the
    //                       next month's charge will draw on by itself.
    //   neither   → green.  Settled up; a different sentence from "you have
    //                       0.00 in credit", which is not an answer to anything.
    //
    // A comparison, not arithmetic: money stays text end to end. The server
    // computed `netBalance` as debt − credit, and all that happens here is
    // reading its sign and dropping the minus — "‑50 مستحق" is a puzzle, and
    // "50 لك" is the same fact stated so it can be acted on.
    final bool owes = detail.owes;
    final bool inCredit = detail.inCredit;
    final Color tone = owes ? AppColors.danger : AppColors.success;
    final String figure = inCredit
        ? formatMoney(detail.credit)
        : formatMoney(detail.netBalance);

    final Color statusTone = switch (adeel.membershipStatus) {
      MembershipStatusWire.active => AppColors.success,
      MembershipStatusWire.suspended => AppColors.warning,
      _ => AppColors.muted,
    };

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ── Whose statement this is, and the way into his own details ────
          // TAPPING THE NAME opens «تفاصيل اشتراكي». There used to be a panel
          // at the foot of the page carrying his phone, his registration date
          // and the monthly fee — and every one of those already sat in the
          // المزيد sheet, under a heading of that exact name. Two places, one
          // set of facts, and the copy at the foot was the one nobody scrolled
          // to.
          //
          // So the panel is gone and the name is the door. It is the right
          // door: a man looking for what the association holds ABOUT HIM
          // reaches for his own name, not for a card below his ledger.
          InkWell(
            onTap: () => _showPortalMore(context, adeel.id),
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      adeel.fullName.characters.take(1).toString(),
                      style: const TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandDeep,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          adeel.fullName,
                          // Two lines then ellipsis: a long Libyan name on a
                          // 360dp phone must not push the status badge off the
                          // card, and must not be silently truncated at one
                          // line either.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              adeel.adeelCode,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // The affordance. A name that opens something and
                            // does not say so is a feature nobody finds, and
                            // this one is now the ONLY way to his details.
                            const Icon(
                              Icons.info_outline,
                              size: 13,
                              color: AppColors.muted,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  // The status the database stores, verbatim — what he reads
                  // here and what the treasurer reads cannot diverge.
                  StatusBadge(label: adeel.membershipStatus, tone: statusTone),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(height: 1, thickness: 1, color: GlassColors.hairline),
          ),

          // ── And what it says ─────────────────────────────────────────────
          Row(
            children: <Widget>[
              Icon(
                owes
                    ? Icons.account_balance_wallet
                    : inCredit
                    ? Icons.savings_outlined
                    : Icons.verified,
                size: 18,
                color: tone,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                // The LABEL changes with the sign, not just the colour. Colour
                // alone would leave a member who cannot distinguish red from
                // green — or who is reading in sunlight — with a bare figure
                // and no way to tell whether it is his or theirs.
                owes
                    ? l.myBalanceNow
                    : inCredit
                    ? l.myWalletTitle
                    : l.myBalanceNow,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            figure,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 40,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            owes
                ? l.openMonthsCount(openCount)
                : inCredit
                ? l.myWalletBody
                : l.settledUpTitle,
            style: const TextStyle(fontSize: 15, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// مستحق − مدفوع = الرصيد, shown as the identity it is.
///
/// Three figures in a row rather than three cards: they are one statement, and
/// separating them into tiles is what made the old grid read as four unrelated
/// facts. The middle column carries the operator so the arithmetic is visible
/// — the hero figure above is then something he can check, not something he has
/// to accept.
class _TotalsStrip extends StatelessWidget {
  const _TotalsStrip({required this.detail});

  final AdeelDetail detail;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.neutralSoft,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: <Widget>[
          // The portal's own words, not the staff screens'. "الاستحقاقات
          // المنشأة" is the accounting term and the name of a whole admin
          // screen; the man reading this is not looking at an accounts ledger,
          // he is looking at what he was asked to pay, what he paid, and what
          // is left. Shorter labels also stop this strip — three figures and
          // two operators on a phone — reading as a wall.
          _StripCell(label: l.myIssuedTotal, value: detail.issued),
          const _StripOperator('−'),
          _StripCell(label: l.myPaidTotal, value: detail.paid),
          const _StripOperator('='),
          _StripCell(
            label: l.myRemainingTotal,
            value: detail.debt,
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _StripCell extends StatelessWidget {
  const _StripCell({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          const SizedBox(height: 2),
          Text(
            formatMoney(value),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: bold ? AppColors.ink : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StripOperator extends StatelessWidget {
  const _StripOperator(this.symbol);

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        symbol,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

/// The statement, as a ledger.
///
/// The data was always right: `api_adeel_statement` already returns a debit, a
/// credit and a RUNNING BALANCE for every movement, computed by a window
/// function in SQL. What was wrong was the reading — the old tile threw the
/// balance away and printed one coloured number per row, so a charge and a
/// receipt looked like the same kind of event and nothing showed how the two of
/// them met. Every figure below is the server's; none is added up here.
class _Ledger extends StatefulWidget {
  const _Ledger({required this.statement, required this.detail});

  final Statement statement;
  final AdeelDetail detail;

  /// How many movements one page holds.
  ///
  /// A statement is read top-down, so the cost of too many rows is not the
  /// scrolling — it is that the reader loses which balance belongs to which
  /// month. Ten is about what stays graspable on a phone without a scroll
  /// gesture between a movement and its balance. One constant, one place to
  /// change it.
  static const int rowsPerPage = 10;

  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  final TextEditingController _search = TextEditingController();

  /// Pages revealed so far. Pages after this exist and are simply not built —
  /// the statement is already in memory, so "loading" more is instant and the
  /// button is about how much is ASKED FOR, not about fetching.
  int _pagesShown = 1;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    // Back to one page on every keystroke. Without this, searching after
    // revealing six pages shows six pages of a two-row result and the "show
    // more" button vanishes with no explanation of what changed.
    setState(() => _pagesShown = 1);
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    if (widget.statement.movements.isEmpty) {
      return Column(
        children: <Widget>[
          _SectionTitle(l.myStatementSection),
          EmptyStateView(icon: Icons.receipt_long, title: l.noMovements),
        ],
      );
    }

    final List<StatementMovement> matches = _filter(
      widget.statement.movements,
      _search.text,
      widget.detail,
    );
    final int total = matches.length;
    final int shown = (_pagesShown * _Ledger.rowsPerPage).clamp(0, total);
    final int remaining = total - shown;

    // ── The search box earns its place, or it is not there ───────────────────
    // A search exists to find something you cannot see. A member three months
    // into his subscription has three movements, all of them on screen at once,
    // and a search field above them is a control that can only ever hide rows
    // he was already looking at — the definition of clutter on the narrowest
    // screen in the app.
    //
    // The threshold is the page size, not a taste: below it the whole statement
    // is on one page by construction, so there is nothing the box could reveal.
    // It appears the moment paging does, and once it is on screen it STAYS —
    // keyed off the unfiltered count, or typing a query that matches two rows
    // would make the box that produced them disappear under the reader's hand.
    final bool searchable =
        widget.statement.movements.length > _Ledger.rowsPerPage;

    return GlassPanel(
      title: l.myStatementSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (searchable) ...<Widget>[
            // OUTSIDE the horizontal scroller below on purpose: the table may
            // be wider than the panel and scroll sideways, and a search box
            // that slid away with it would be unreachable exactly when the
            // table is at its most crowded.
            TextField(
              controller: _search,
              onChanged: (_) => _onQueryChanged(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: l.statementSearchHint,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: l.clearSearch,
                        onPressed: () {
                          _search.clear();
                          _onQueryChanged();
                        },
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                l.noSearchResults,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: AppColors.muted),
              ),
            )
          else
            // No horizontal scroller, and that is the point. The columns are
            // shares of whatever width there is (see _Cell), so the table is
            // exactly as wide as the screen on a Galaxy Note 10's 360dp and on
            // anything else — a statement a reader has to drag sideways to
            // reach the balance is not one he can read.
            Column(
              children: <Widget>[
                const _LedgerHead(),
                for (int i = 0; i < shown; i++)
                  _LedgerRow(
                    movement: matches[i],
                    // Zebra striping. A four-column table of near-identical
                    // numbers is where the eye slips a line, and the stripe is
                    // what keeps a balance attached to its own movement.
                    shaded: i.isOdd,
                  ),
                // The totals stay the ACCOUNT's, never the filtered set's:
                // closingBalance is the server's window function over every
                // movement, and a bank statement narrowed by a search still
                // states what the account stands at. Summing the visible rows
                // here would invent a second, disagreeing figure.
                _LedgerTotals(
                  detail: widget.detail,
                  statement: widget.statement,
                ),
              ],
            ),

          // "عرض ٣ من ٣ حركة" under a table showing all three of them states
          // the obvious and costs a line. The counter is only informative while
          // something is HIDDEN — either paged away, or filtered out by a query
          // the reader can then see the effect of.
          if (total > 0 && (remaining > 0 || _search.text.isNotEmpty)) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _LedgerPager(
              shown: shown,
              total: total,
              remaining: remaining,
              pageSize: _Ledger.rowsPerPage,
              onMore: () => setState(() => _pagesShown++),
              onAll: () => setState(
                () => _pagesShown =
                    (total / _Ledger.rowsPerPage).ceil().clamp(1, 1 << 30),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Free-text search over a statement, matching ANY part of ANY movement.
///
/// ── Why this cannot be a plain `contains` ───────────────────────────────────
/// What the reader SEES and what the row HOLDS are different strings.
/// `formatMoney` renders through `ar_LY`, so 20.00 appears as ٢٠٫٠٠, and
/// `formatDate` renders 2026-03-15 as ١٥‏/٣‏/٢٠٢٦. A search box that matched
/// the raw values would fail for anyone typing what is on their screen, and one
/// that matched only the formatted values would fail for anyone typing on a
/// Latin keyboard. Both forms go into the haystack, and the query is folded to
/// one digit system, so either way of typing the same number finds the row.
///
/// The عديل's own name and phone are searchable too, as asked. They are the
/// same on every row of his statement, so typing his name matches everything —
/// which is the honest answer to "search by any part", not a bug.
List<StatementMovement> _filter(
  List<StatementMovement> movements,
  String query,
  AdeelDetail detail,
) {
  final String needle = _fold(query);
  if (needle.isEmpty) return movements;

  // Every term must match, in any field and in any order: "دفعة ٢٠" finds the
  // 20.00 payments without the reader having to know which column is which.
  final List<String> terms = needle.split(RegExp(r'\s+'))
    ..removeWhere((String t) => t.isEmpty);

  return <StatementMovement>[
    for (final StatementMovement m in movements)
      if (terms.every(_haystack(m, detail).contains)) m,
  ];
}

String _haystack(StatementMovement m, AdeelDetail detail) => _fold(
  <String>[
    m.date, formatDate(m.date),
    m.reference,
    m.type,
    m.debit ?? '', formatMoney(m.debit),
    m.credit ?? '', formatMoney(m.credit),
    m.balance, formatMoney(m.balance),
    m.note,
    detail.adeel.fullName,
    detail.adeel.phone,
    detail.adeel.adeelCode,
  ].join(' '),
);

/// Folds a string to one comparable form: Arabic-Indic digits become Latin,
/// the Arabic letters that are typed interchangeably are unified, and the marks
/// a reader never types are dropped.
///
/// Without the letter folding, someone searching for إبراهيم by typing ابراهيم
/// gets nothing — the two differ only in a hamza most keyboards make awkward.
/// Without the digit folding, no amount on screen is findable by typing it.
String _fold(String input) {
  final StringBuffer out = StringBuffer();
  for (final int rune in input.toLowerCase().runes) {
    // Arabic-Indic ٠-٩ (U+0660) and Extended Arabic-Indic ۰-۹ (U+06F0).
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + rune - 0x0660);
      continue;
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + rune - 0x06F0);
      continue;
    }
    switch (rune) {
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0622: // آ
        out.writeCharCode(0x0627); // ا
      case 0x0649: // ى
        out.writeCharCode(0x064A); // ي
      case 0x0629: // ة
        out.writeCharCode(0x0647); // ه
      // The Arabic decimal separator ٫ and thousands separator ٬ that
      // NumberFormat emits, plus the bidi marks it wraps dates in. A reader
      // types '.' or nothing at all for these.
      case 0x066B:
        out.writeCharCode(0x2E); // .
      case 0x066C:
      case 0x200E:
      case 0x200F:
      case 0x061C:
        break;
      // Arabic diacritics: never typed, always noise.
      default:
        if (rune >= 0x064B && rune <= 0x0652) break;
        out.writeCharCode(rune);
    }
  }
  return out.toString().trim();
}

/// "Showing 10 of 47", and the button that reveals the next page.
///
/// Progressive rather than numbered: a statement is read in order, so page 4 of
/// a ledger means nothing on its own — what the reader wants is more of the
/// same list, continuing from where it stopped. `عرض الكل` is there for the
/// reader who wants to scan or search the lot at once.
class _LedgerPager extends StatelessWidget {
  const _LedgerPager({
    required this.shown,
    required this.total,
    required this.remaining,
    required this.pageSize,
    required this.onMore,
    required this.onAll,
  });

  final int shown;
  final int total;
  final int remaining;
  final int pageSize;
  final VoidCallback onMore;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    // Column over Wrap, not a single Row: the count and two Arabic labels do not
    // fit one line on a narrow phone at a large text size, and a Row would
    // overflow rather than reflow.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l.statementShowing(shown, total),
          style: const TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        if (remaining > 0)
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              TextButton(
                onPressed: onMore,
                child: Text(
                  l.statementShowMore(
                    remaining < pageSize ? remaining : pageSize,
                  ),
                ),
              ),
              TextButton(onPressed: onAll, child: Text(l.statementShowAll)),
            ],
          ),
      ],
    );
  }
}

class _LedgerHead extends StatelessWidget {
  const _LedgerHead();

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    const TextStyle style = TextStyle(
      fontSize: _ledgerHeadSize,
      fontWeight: FontWeight.w800,
      color: AppColors.inkMuted,
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.neutralSoft,
        border: Border(bottom: BorderSide(color: AppColors.inkMuted, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          // Every heading shrinks to fit rather than clipping. A money column
          // is 22% of the screen — about 64dp on a Note 10 — and "الرصيد" at a
          // system font scale of 1.3 is wider than that. Ellipsis on a column
          // heading is worse than small type: "الرص…" names nothing.
          _HeadCell(flex: _particularsFlex, label: l.ledgerParticulars, style: style),
          _HeadCell(flex: _moneyFlex, label: l.ledgerDebit, style: style),
          _HeadCell(flex: _moneyFlex, label: l.ledgerCredit, style: style),
          _HeadCell(flex: _moneyFlex, label: l.ledgerBalance, style: style),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.movement,
    required this.shaded,
  });

  final StatementMovement movement;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final String? debit = movement.debit;
    final String? credit = movement.credit;
    final bool isCharge = debit != null && debit.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: shaded ? AppColors.neutralSoft : null,
        border: const Border(
          bottom: BorderSide(color: AppColors.line, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            flex: _particularsFlex,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  movement.note.isEmpty ? movement.reference : movement.note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: _ledgerTitleSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // The DATE alone. It used to read "دفعة • 16/08/2026", and
                  // the type half of that is now said by which of the two money
                  // columns the figure landed in — repeating it here would cost
                  // the width those columns were just given.
                  formatDate(movement.date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: _ledgerNoteSize,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          // ── مدين, then دائن, and the empty one shows a rule ────────────────
          // A movement is never both, so one of these is always blank — and the
          // blank is the point. It is what makes the two columns readable DOWN:
          // everything the association charged him in one, everything he paid
          // in the other, each summed on the closing line directly beneath.
          //
          // An em dash rather than nothing at all, because an empty cell reads
          // as a figure that failed to load. Colour still separates the two, so
          // the distinction survives for anyone reading a single row across.
          _Money(
            flex: _moneyFlex,
            text: isCharge ? formatMoney(debit) : _absent,
            tone: isCharge ? AppColors.danger : AppColors.muted,
          ),
          _Money(
            flex: _moneyFlex,
            text: isCharge ? _absent : formatMoney(credit),
            tone: isCharge ? AppColors.muted : AppColors.success,
          ),
          _Money(
            flex: _moneyFlex,
            text: formatMoney(movement.balance),
            tone: AppColors.ink,
            bold: true,
          ),
        ],
      ),
    );
  }
}

/// The closing line: what was charged, what was received, what is left.
///
/// All three come from the server — `issued` and `paid` off v_adeels, the
/// balance off the statement's own window function. Summing the rows in Dart
/// would put the association's totals on binary floating point, which is the
/// one thing the money-as-text rule exists to prevent.
class _LedgerTotals extends StatelessWidget {
  const _LedgerTotals({
    required this.detail,
    required this.statement,
  });

  final AdeelDetail detail;
  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool owes = (double.tryParse(statement.closingBalance) ?? 0) > 0;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.inkMuted, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: _particularsFlex,
            child: Text(
              l.ledgerTotals,
              style: const TextStyle(
                fontSize: _ledgerTitleSize,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          _Money(
            flex: _moneyFlex,
            text: formatMoney(detail.issued),
            tone: AppColors.danger,
            bold: true,
          ),
          _Money(
            flex: _moneyFlex,
            text: formatMoney(detail.paid),
            tone: AppColors.success,
            bold: true,
          ),
          _Money(
            flex: _moneyFlex,
            text: formatMoney(statement.closingBalance),
            tone: owes ? AppColors.danger : AppColors.success,
            bold: true,
          ),
        ],
      ),
    );
  }
}

/// One money column, sized as a SHARE of the row rather than in pixels.
///
/// It used to be a fixed 100dp, and four fixed columns need 448dp — more than a
/// Galaxy Note 10 has (360dp), so the table scrolled sideways and a reader had
/// to drag to see the balance he came for. A statement you have to scroll
/// horizontally is not a statement you can read.
///
/// Flex means the table is exactly as wide as the screen on every device and at
/// every system font size, and never one pixel more.
class _Cell extends StatelessWidget {
  const _Cell({required this.flex, required this.child});

  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) => Expanded(flex: flex, child: child);
}

/// A column heading, which never clips and never wraps.
class _HeadCell extends StatelessWidget {
  const _HeadCell({
    required this.flex,
    required this.label,
    required this.style,
  });

  final int flex;
  final String label;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => _Cell(
    flex: flex,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(label, maxLines: 1, style: style),
    ),
  );
}

/// A figure in a money column.
///
/// `TextAlign.start` looks wrong for a number until you follow it through: the
/// column is RTL, so start is the RIGHT edge, and digits render left-to-right
/// inside it — which puts the LAST character of every figure on that same edge.
/// With two decimal places on all of them, that is decimal alignment, and it is
/// what lets a column of figures be read down rather than one at a time.
class _Money extends StatelessWidget {
  const _Money({
    required this.flex,
    required this.text,
    required this.tone,
    this.bold = false,
  });

  final int flex;
  final String text;
  final Color tone;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return _Cell(
      flex: flex,
      // scaleDown, not ellipsis: an amount cut short reads as a DIFFERENT
      // amount, which is worse than one rendered a point smaller. It only
      // shrinks when the figure genuinely cannot fit — an ordinary 20.00 is
      // untouched.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
        text,
        textAlign: TextAlign.start,
        maxLines: 1,
        style: TextStyle(
          fontSize: _ledgerMoneySize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          color: tone,
        ),
      ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

class _DueTile extends StatelessWidget {
  const _DueTile({required this.item});

  final ReceivableItem item;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final bool settled = item.status == ReceivableStatusWire.fullyPaid;
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.periodLabel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                // The status label is the value the database stores, so what he
                // reads here and what the treasurer reads cannot diverge.
                StatusBadge(
                  label: item.status,
                  tone: settled ? AppColors.success : AppColors.warning,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // ── The REMAINING amount leads, not the month's total ─────────────
          // This tile used to show `total` — what the month cost. In a list
          // headed "what you owe" that is the wrong figure: a month half paid
          // showed 20.00 while 10.00 was actually due, and the only way to
          // learn the real number was to open the ledger and subtract.
          //
          // The total stays underneath, quieter, because "10 of 20" is what
          // makes a partial payment legible — and it is the whole reason the
          // two figures differ.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatMoney(item.balance),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: settled ? AppColors.success : AppColors.danger,
                ),
              ),
              if (!settled && item.balance != item.total) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  l.ofTotal(formatMoney(item.total)),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
