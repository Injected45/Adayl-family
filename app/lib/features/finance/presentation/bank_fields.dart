import 'package:flutter/material.dart';

import '../../../core/config/theme.dart';
import '../../../l10n/app_localizations.dart';

/// One account, as it was actually used once before.
///
/// Deliberately three bare strings rather than a payment or a voucher: the two
/// sheets that need this have nothing else in common, and the moment this type
/// knew about either of them the other would have to carry a shape it does not
/// have.
class BankUsage {
  const BankUsage({
    required this.bank,
    required this.holder,
    required this.account,
  });

  final String bank;
  final String holder;
  final String account;
}

/// A bank, the name on the account, and its number — typed, but offered from
/// what has been used before for THIS counterparty.
///
/// ── Why these are not settings ──────────────────────────────────────────────
/// A man may transfer from more than one account and more than one bank, and
/// the association may pay a supplier into a different one each time. Which was
/// used is a fact about THIS transaction, so fixing it anywhere would be wrong.
/// But retyping three fields every time is slow and is exactly where a digit
/// goes missing, and a mistyped account number is the one thing here that makes
/// a receipt impossible to match against the bank's own statement.
///
/// ── The cascade ─────────────────────────────────────────────────────────────
/// Each field narrows the one below it, against that counterparty's own history:
///
///   bank        → every bank ever used with him
///   holder      → only the names used AT THAT BANK
///   account no. → only the numbers used by THAT NAME at THAT BANK
///
/// and when a field has exactly ONE candidate left, it fills itself. So the
/// second time المهدي pays through المصرف التجاري and the treasurer picks علي,
/// the account number appears on its own — because nothing else it could be has
/// ever been recorded.
///
/// Free text throughout. A new bank or a new account is typed once and is then
/// on the list for ever; the suggestions never refuse anything.
///
/// ── Where the history comes from ────────────────────────────────────────────
/// The CALLER supplies it, already scoped, from a list the app has loaded and
/// RLS has already filtered — `v_payments` for a collection, `v_disbursements`
/// for a voucher. No new endpoint either way, and nothing here is trusted: the
/// server stores exactly the three strings it is sent, and only for a transfer.
/// ── Why this is STATEFUL ────────────────────────────────────────────────────
/// The cascade only exists if the fields BELOW the one being edited are rebuilt
/// with fresh options, and `options` is computed here. When each field owned its
/// own `setState`, that setState rebuilt only that field — so `holders` and
/// `accounts` stayed at whatever they were when this widget last built, which
/// for an untouched form is empty. Picking a bank then offered no names, and
/// the account number never filled itself: the whole feature stopped at the
/// first field, silently, in a way no test looked at.
///
/// So the change notification comes UP to here and the rebuild goes back DOWN.
class BankFields extends StatefulWidget {
  const BankFields({
    super.key,
    required this.history,
    required this.bank,
    required this.holder,
    required this.account,
    required this.enabled,
  });

  /// Every account previously used with this counterparty, in any order. A
  /// cancelled row belongs here: it still describes an account really used, and
  /// the suggestion is about typing, not about money.
  final List<BankUsage> history;
  final TextEditingController bank;
  final TextEditingController holder;
  final TextEditingController account;
  final bool enabled;

  @override
  State<BankFields> createState() => _BankFieldsState();
}

class _BankFieldsState extends State<BankFields> {
  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final TextEditingController bank = widget.bank;
    final TextEditingController holder = widget.holder;
    final TextEditingController account = widget.account;
    final bool enabled = widget.enabled;

    String norm(String s) => s.trim().toLowerCase();

    List<String> distinct(
      String Function(BankUsage) pick,
      bool Function(BankUsage) where,
    ) {
      final Map<String, String> seen = <String, String>{};
      for (final BankUsage u in widget.history) {
        if (!where(u)) continue;
        final String v = pick(u).trim();
        if (v.isNotEmpty) seen.putIfAbsent(norm(v), () => v);
      }
      return seen.values.toList()..sort();
    }

    final List<String> banks = distinct((BankUsage u) => u.bank, (_) => true);
    final List<String> holders = distinct(
      (BankUsage u) => u.holder,
      (BankUsage u) => norm(u.bank) == norm(bank.text),
    );
    final List<String> accounts = distinct(
      (BankUsage u) => u.account,
      (BankUsage u) =>
          norm(u.bank) == norm(bank.text) &&
          norm(u.holder) == norm(holder.text),
    );

    // "Exactly one candidate left" is the whole point — but only fill a field
    // that has not been typed into, or this would overwrite mid-keystroke.
    void autofill(TextEditingController c, List<String> options) {
      if (options.length == 1 && c.text.trim().isEmpty) c.text = options.single;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SuggestingField(
          label: l.bankNameField,
          controller: bank,
          options: banks,
          enabled: enabled,
          // Changing the bank invalidates both fields below it: the name and
          // number that belonged to the old bank are almost certainly wrong for
          // the new one, and leaving them looks like they were confirmed.
          onChanged: () => setState(() {
            holder.clear();
            account.clear();
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        _SuggestingField(
          label: l.bankAccountNameField,
          controller: holder,
          options: holders,
          enabled: enabled && bank.text.trim().isNotEmpty,
          onChanged: () => setState(account.clear),
        ),
        const SizedBox(height: AppSpacing.md),
        Builder(
          builder: (BuildContext context) {
            autofill(account, accounts);
            return _SuggestingField(
              label: l.bankAccountNoField,
              controller: account,
              options: accounts,
              enabled: enabled && holder.text.trim().isNotEmpty,
              onChanged: () => setState(() {}),
            );
          },
        ),
      ],
    );
  }
}

/// A text field that also offers what has been used before.
///
/// Typing is always allowed — the list narrows it, never restricts it. The
/// suffix button opens the whole list, because someone who has not started
/// typing has nothing to filter by and would otherwise not know the history is
/// there at all.
class _SuggestingField extends StatefulWidget {
  const _SuggestingField({
    required this.label,
    required this.controller,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final List<String> options;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  State<_SuggestingField> createState() => _SuggestingFieldState();
}

class _SuggestingFieldState extends State<_SuggestingField> {
  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    // The callback rebuilds BankFields, which rebuilds this — a local setState
    // here would repaint this one field with the same stale `widget.options`
    // and leave the fields below it untouched, which is the bug described above.
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      onChanged: (_) => widget.onChanged(),
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: widget.options.isEmpty
            ? null
            : PopupMenuButton<String>(
                icon: const Icon(Icons.history, size: 20),
                tooltip: l.previouslyUsed,
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  for (final String option in widget.options)
                    PopupMenuItem<String>(
                      value: option,
                      child: Text(option, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onSelected: (String value) {
                  widget.controller.text = value;
                  widget.onChanged();
                },
              ),
      ),
    );
  }
}
