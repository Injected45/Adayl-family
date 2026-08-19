import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/directory/presentation/providers.dart' as directory;
import '../../features/finance/presentation/providers.dart' as finance;
import '../../features/oversight/presentation/providers.dart' as oversight;

/// Throws away every cached read so the next build refetches from the database.
///
/// WHY ONE FUNCTION RATHER THAN A REFRESH PER SCREEN: nothing in this app is
/// only local. A treasurer registering a payment moves the دفعة list, the
/// treasury, the register's debt column, the dashboard, the alerts and the audit
/// trail in the same transaction — so a refresh that reloads only the screen in
/// front of you leaves five other screens quietly stale, and stale money reads
/// as a bug in the ledger rather than a bug in the cache.
///
/// It is also what makes the button in the app bar honest: pressing it means
/// "everything you can see is what the database says right now", and that is
/// only true if it covers everything.
///
/// Riverpod discards the value and refetches on next watch, so a screen nobody
/// is looking at costs nothing — the request is only issued when it is rebuilt.
///
/// WHAT IT DOES NOT DO: it does not reload the app's CODE. A code change needs
/// hot reload from the host (VS Code's ⚡, or `r` in the `flutter run` console).
/// An app cannot patch itself from inside — see .vscode/launch.json.
void refreshAll(WidgetRef ref) {
  // Directory. The two `.family` providers are invalidated wholesale rather than
  // per-argument: `ref.invalidate(p)` on a family clears every instance, which
  // is what is wanted here — the عديل whose detail is cached may be exactly the
  // one whose balance just moved.
  ref.invalidate(directory.adeelsProvider);
  ref.invalidate(directory.adeelDetailProvider);
  ref.invalidate(directory.statementProvider);
  ref.invalidate(directory.receivablesProvider);
  ref.invalidate(directory.settingsProvider);
  ref.invalidate(directory.officialsProvider);

  // Finance.
  ref.invalidate(finance.paymentsProvider);
  ref.invalidate(finance.cashSummaryProvider);
  ref.invalidate(finance.cashMovementsProvider);

  // Oversight.
  ref.invalidate(oversight.dashboardProvider);
  ref.invalidate(oversight.reportProvider);
  ref.invalidate(oversight.auditProvider);
  ref.invalidate(oversight.usersProvider);
  ref.invalidate(oversight.editableSettingsProvider);
}
