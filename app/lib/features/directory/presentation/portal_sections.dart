import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/domain/wire_values.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

/// The four things the portal used to stack into one sheet, each on its own
/// page.
///
/// ── WHY THEY WERE SPLIT ─────────────────────────────────────────────────────
/// «تفاصيل اشتراكي»، «الحساب المصرفي»، «المسؤولون» و«الصندوق» arrived together
/// in a single scrolling sheet capped at three quarters of the phone. Four
/// unrelated answers in one column is not four answers — it is one long thing a
/// reader scrolls past looking for the part he came for, and the part he came
/// for is different every time. The bank account is read while standing at a
/// counter; the officials are read when something has gone wrong; الصندوق is
/// read out of curiosity. They share nothing but having been built on the same
/// afternoon.
///
/// ── WHAT "ثلاثي الأبعاد" MEANS IN THIS APP ──────────────────────────────────
/// Depth here is GLASS, not a bevel. `core/config/theme.dart` resolves the brief
/// explicitly: glass governs surfaces, FLAT governs the content inside them —
/// no gradients, no decorative shadows — and `test/design_system_test.dart`
/// fails the build on `boxShadow` or any `Gradient` in a screen. Those are not
/// arbitrary: the palette is contrast-tested to WCAG AA, and a shaded panel
/// invalidates the pairing it was tested at.
///
/// So the depth is real layering instead of a picture of it: a translucent pane
/// floating over the vibrant field, a RECESSED well cut into that pane for the
/// medallion, a hairline light border catching the edge, and a colour that is
/// this section's alone. Two genuine planes and an accent, which is what the
/// eye actually reads as depth — and which stays legible for someone who cannot
/// separate the hues.
///
/// ── PUSHED, NOT ROUTED ──────────────────────────────────────────────────────
/// `Navigator.push` rather than a `go_router` location, exactly as the aid
/// screen is reached: the router pins a portal account to `/my-dues` and
/// `/chat`, and a push changes no location for the guard to redirect. Four new
/// routes would have meant widening that set by four — and the test that pins it
/// at two exists precisely so that cannot happen quietly.

/// One section's identity, and the whole of what differs between the four.
class _Section {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
  });

  final IconData icon;
  final String title;

  /// One line saying what the page answers. It is on the MENU card as well as
  /// the page, because a menu of four nouns makes a reader open three of them
  /// to find the one he wanted.
  final String subtitle;

  /// The accent, and the only thing that is not shared. Not decoration: four
  /// identical pages differing by a heading are four pages nobody learns their
  /// way around.
  final Color tone;
}

/// The shell every section page wears.
///
/// The header is the depth: a lifted glass pane over the vibrant field, with the
/// medallion sunk into a well cut out of it. Two planes, one hairline, no paint
/// pretending to be either.
class _PortalSectionPage extends StatelessWidget {
  const _PortalSectionPage({required this.section, required this.child});

  final _Section section;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(section.title)),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: <Widget>[
            _Header(section: section),
            const SizedBox(height: AppSpacing.lg),
            child,
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.section});

  final _Section section;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(
        children: <Widget>[
          _Medallion(icon: section.icon, tone: section.tone, size: 56),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  section.subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The icon, sunk into the pane rather than sitting on it.
///
/// `GlassColors.well` is the app's recessed surface — the one it already uses
/// for inputs and totals rows — so this is the same plane those sit on rather
/// than a new invention. The hairline `wellEdge` is what makes it read as cut
/// INTO the card instead of drawn on top: an edge catches light on the inside
/// of a recess and on the outside of a boss, and that single line is the whole
/// difference.
class _Medallion extends StatelessWidget {
  const _Medallion({
    required this.icon,
    required this.tone,
    required this.size,
  });

  final IconData icon;
  final Color tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: GlassColors.well,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: GlassColors.wellEdge),
      ),
      child: Icon(icon, color: tone, size: size * 0.45),
    );
  }
}

/// A labelled fact.
///
/// Lifted out of the old sheet unchanged in behaviour, including the one detail
/// that matters: the account number is COPYABLE and almost nothing else is.
/// Retyping a digit on a transfer sends the association's money to a stranger.
class SectionRow extends StatelessWidget {
  const SectionRow({
    required this.label,
    required this.value,
    this.trailing,
    this.copyable = false,
    this.copyText,
    this.tone,
    super.key,
  });

  final String label;
  final String value;
  final String? trailing;
  final bool copyable;
  final String? copyText;

  /// The value's colour. Null leaves it in the body tone, which is what almost
  /// every row here wants — the portal states facts and does not grade them.
  ///
  /// The exception is عهد المشتركين, which is less a fact about the association
  /// than a caution about one of its own figures, and which wears the same amber
  /// here as on the two staff screens that show it.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value.isEmpty ? '—' : value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    color: tone,
                  ),
                ),
                if (trailing != null && trailing!.isNotEmpty)
                  Text(
                    trailing!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: l.copy,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.copy_rounded, size: 16),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copyText ?? value));
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

/// A quiet line of prose under a section.
class SectionNote extends StatelessWidget {
  const SectionNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 11, height: 1.6, color: AppColors.muted),
  );
}

/// Everything one section page needs, in one place, so a new section is one
/// entry rather than four edits.
///
/// The MENU is generated from this list too, which is what stops the two from
/// disagreeing about what exists.
enum PortalSection { details, bank, officials, treasury }

_Section _describe(L l, PortalSection s) => switch (s) {
  PortalSection.details => _Section(
    icon: Icons.badge_outlined,
    title: l.myDetailsTitle,
    subtitle: l.portalDetailsHint,
    tone: AppColors.brand,
  ),
  PortalSection.bank => _Section(
    icon: Icons.account_balance_outlined,
    title: l.bankAccountSection,
    subtitle: l.portalBankHint,
    tone: AppColors.info,
  ),
  PortalSection.officials => _Section(
    icon: Icons.contact_phone_outlined,
    title: l.navOfficials,
    subtitle: l.portalOfficialsHint,
    tone: AppColors.success,
  ),
  PortalSection.treasury => _Section(
    icon: Icons.savings_outlined,
    title: l.navCash,
    subtitle: l.portalTreasuryHint,
    tone: AppColors.warning,
  ),
};

/// Opens one section as its own page. See the note on pushing rather than
/// routing at the top of this file.
void openPortalSection(
  BuildContext context,
  PortalSection section, {
  required int adeelId,
}) {
  final L l = L.of(context);
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _PortalSectionPage(
        section: _describe(l, section),
        child: switch (section) {
          PortalSection.details => _DetailsBody(adeelId: adeelId),
          PortalSection.bank => const _BankBody(),
          PortalSection.officials => const _OfficialsBody(),
          PortalSection.treasury => const _TreasuryBody(),
        },
      ),
    ),
  );
}

/// The four, as a menu.
///
/// One card each: the section's own medallion, its name, and the line that says
/// what it answers. A reader picks the one he came for instead of scrolling
/// through the other three to reach it.
class PortalSectionMenu extends StatelessWidget {
  const PortalSectionMenu({required this.adeelId, super.key});

  final int adeelId;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    return Column(
      children: <Widget>[
        for (final PortalSection s in PortalSection.values)
          _MenuCard(
            section: _describe(l, s),
            onTap: () => openPortalSection(context, s, adeelId: adeelId),
          ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.section, required this.onTap});

  final _Section section;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              _Medallion(icon: section.icon, tone: section.tone, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      section.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A section's contents, in the pane they belong to.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GlassCard(child: child);
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({required this.adeelId});

  final int adeelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return _Panel(
      child: ref
          .watch(adeelDetailProvider(adeelId))
          .when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (Object e, StackTrace _) =>
                SectionNote(describeApiFailure(l, e)),
            data: (AdeelDetail d) => Column(
              children: <Widget>[
                SectionRow(label: l.fullNameField, value: d.adeel.fullName),
                SectionRow(label: l.receiptNo, value: d.adeel.adeelCode),
                SectionRow(
                  label: l.statusLabel,
                  value: d.adeel.membershipStatus,
                ),
                SectionRow(label: l.phone, value: d.adeel.phone),
                SectionRow(
                  label: l.registeredAt,
                  value: formatDate(d.adeel.registeredAt),
                ),
                SectionRow(
                  label: l.monthlyFeeLabel,
                  value: formatMoney(d.monthlyExpected),
                ),
              ],
            ),
          ),
    );
  }
}

/// Where to send a transfer.
///
/// He is the one being asked to pay and, before this existed, the app never told
/// him where. `read_settings_adeel` was written for it.
class _BankBody extends ConsumerWidget {
  const _BankBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return _Panel(
      child: ref
          .watch(settingsProvider)
          .when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (Object e, StackTrace _) =>
                SectionNote(describeApiFailure(l, e)),
            data: (AssociationSettingsView s) => !s.hasBankAccount
                ? SectionNote(l.bankAccountNotSetYet)
                : Column(
                    children: <Widget>[
                      SectionRow(label: l.bankNameField, value: s.bankName),
                      // COPYABLE, and only this one. An account number is the
                      // single field on this page where retyping a digit sends
                      // the money to a stranger.
                      SectionRow(
                        label: l.bankAccountNoField,
                        value: s.bankAccountNo,
                        copyable: true,
                      ),
                      SectionRow(
                        label: l.bankAccountNameField,
                        value: s.bankAccountName,
                      ),
                    ],
                  ),
          ),
    );
  }
}

/// Who to ring.
class _OfficialsBody extends ConsumerWidget {
  const _OfficialsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return _Panel(
      child: ref
          .watch(officialsProvider)
          .when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (Object e, StackTrace _) =>
                SectionNote(describeApiFailure(l, e)),
            data: (List<Official> people) => Column(
              children: <Widget>[
                for (final Official o in people)
                  SectionRow(
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
    );
  }
}

/// الصندوق, for a member to READ.
///
/// «شفافية مطلقة»: where the collective money stands, shown to the people it
/// belongs to.
///
/// ⚠ It comes from `api_association_finance()`, NOT from the treasury view the
///   admin screen uses. That view is SECURITY INVOKER and his RLS scopes
///   cash_movements to `adeel_id = my_adeel_id()`, so pointing this at it would
///   have shown him HIS OWN figures under headings that say "the association's"
///   — not a leak, something worse: a wrong answer he had no way to doubt.
///
/// Aggregates only: no name, no receipt, no per-member figure. And no action
/// anywhere on it — the note at the foot says so, because a member seeing the
/// treasury for the first time will reasonably wonder whether he is meant to do
/// something about it.
class _TreasuryBody extends ConsumerWidget {
  const _TreasuryBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);

    return ref
        .watch(associationFinanceProvider)
        .when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (Object e, StackTrace _) =>
              _Panel(child: SectionNote(describeApiFailure(l, e))),
          data: (AssociationFinance f) => Column(
            children: <Widget>[
              // The conclusion first and alone, because it is the figure the
              // page is opened for. The workings sit under it rather than
              // around it — the same arrangement the treasurer's own screen
              // uses, so the two read alike.
              _Headline(
                label: l.associationBalance,
                value: formatMoney(f.balance),
                tone: AppColors.warning,
              ),
              const SizedBox(height: AppSpacing.md),
              _Panel(
                child: Column(
                  children: <Widget>[
                    SectionRow(
                      label: l.collectedCash,
                      value: formatMoney(f.cash),
                    ),
                    SectionRow(
                      label: l.collectedTransfer,
                      value: formatMoney(f.transfer),
                    ),
                    // Money the association is holding and does not own: a
                    // member who paid a year ahead is owed it back until each
                    // month is billed. See members_held().
                    SectionRow(
                      label: l.heldForMembers,
                      value: formatMoney(f.heldForMembers),
                      tone: AppColors.warning,
                    ),
                    SectionRow(
                      label: l.dueFromMembers,
                      value: formatMoney(f.outstanding),
                    ),
                    // The outgoing side. Transparency that showed only what came
                    // in would overstate the fund by everything it has ever paid
                    // out — the opposite of transparency. The TOTAL is his to
                    // see; who received it is not.
                    SectionRow(
                      label: l.totalDisbursed,
                      value: formatMoney(f.disbursed),
                    ),
                    SectionRow(
                      label: l.statAdeels,
                      value: '${f.members}',
                      trailing: l.subActive(f.activeMembers),
                    ),
                    SectionNote(l.treasuryReadOnlyNote),
                  ],
                ),
              ),
            ],
          ),
        );
  }
}

/// One figure across the width, in its section's colour.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}
