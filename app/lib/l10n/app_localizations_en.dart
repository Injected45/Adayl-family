// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Adayl Family Association';

  @override
  String get appTagline => 'Subscribers, subscriptions and treasury management';

  @override
  String get loginTitle => 'Welcome';

  @override
  String get loginSubtitle => 'Sign in with your Google account to continue';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signingIn => 'Signing in...';

  @override
  String get signInCancelled => 'Sign-in was cancelled';

  @override
  String get googleNotConfigured =>
      'Google sign-in is not configured on the server yet. Please contact your administrator.';

  @override
  String get devSignIn => 'Development sign-in (no Google)';

  @override
  String get devSignInWarning =>
      'Local development only. No identity is verified, and this must be disabled before real use.';

  @override
  String get devSignInEmail => 'Email address';

  @override
  String get devSignInConfirm => 'Sign in';

  @override
  String get pendingTitle => 'Awaiting approval';

  @override
  String get pendingBody =>
      'Your request has been sent to the administrator. You will be able to sign in once your account is approved.';

  @override
  String pendingSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get forbiddenTitle => 'No permission';

  @override
  String get forbiddenBody =>
      'You do not have permission to view this page. Contact your administrator if you believe this is a mistake.';

  @override
  String get backToHome => 'Back to home';

  @override
  String get suspendedTitle => 'Account suspended';

  @override
  String get suspendedBody =>
      'This account has been suspended. Please contact your administrator.';

  @override
  String get signOut => 'Sign out';

  @override
  String get retry => 'Retry';

  @override
  String get refreshData => 'Refresh data';

  @override
  String get refreshedData => 'Data refreshed from the database';

  @override
  String get restartApp => 'Restart the app';

  @override
  String get restartAppBody =>
      'The app will start over: every loaded figure is discarded and re-read, you return to the first screen, and anything unsaved is lost. Note: this does NOT pick up code changes — those need a hot reload from the host.';

  @override
  String get restartConfirm => 'Restart';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get loading => 'Loading...';

  @override
  String get errorGeneric => 'Something went wrong. Please try again later.';

  @override
  String get errorSchemaMismatch =>
      'The database does not match this build of the app. Retrying will not help — the schema needs to be applied.';

  @override
  String get errorNetwork => 'No internet connection';

  @override
  String get errorNetworkBody =>
      'Could not reach the server. Check your connection and try again.';

  @override
  String get errorTimeout => 'The server took too long to respond';

  @override
  String get offlineBanner => 'No internet connection';

  @override
  String get navHome => 'Home';

  @override
  String get navReceivables => 'Receivables';

  @override
  String get navPayments => 'Collections';

  @override
  String get navPaymentsShort => 'Pay';

  @override
  String get navCash => 'Treasury';

  @override
  String get navStatements => 'Statements';

  @override
  String get navAlerts => 'Alerts';

  @override
  String get navReports => 'Reports';

  @override
  String get navOfficials => 'Officials';

  @override
  String get navAudit => 'Audit log';

  @override
  String get navSettings => 'Settings';

  @override
  String get navUsers => 'User management';

  @override
  String get navMore => 'More';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleFinanceManager => 'Finance manager';

  @override
  String get roleTreasurer => 'Treasurer';

  @override
  String get roleViewer => 'Viewer';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get comingSoonBody => 'This screen will be built in a later phase.';

  @override
  String get noSearchResults => 'No results for your search';

  @override
  String debtBadge(String amount) {
    return 'Owes $amount';
  }

  @override
  String ageYears(int count) {
    return '$count years';
  }

  @override
  String get familySummary => 'Subscriber summary';

  @override
  String get debt => 'Outstanding';

  @override
  String get totalPaid => 'Total approved payments';

  @override
  String get personalData => 'Personal details';

  @override
  String get totalDue => 'Charged';

  @override
  String get phone => 'Phone';

  @override
  String get dateOfBirth => 'Date of birth';

  @override
  String get registeredAt => 'Registered on';

  @override
  String get age => 'Age';

  @override
  String get notProvided => '—';

  @override
  String get receivablesIntro =>
      'Each receivable keeps the values in force when it was raised; changing settings later does not alter these records.';

  @override
  String get noReceivables => 'No receivables raised yet';

  @override
  String get period => 'Month';

  @override
  String get totalAmount => 'Total';

  @override
  String get paidAmount => 'Paid';

  @override
  String get remainingAmount => 'Remaining';

  @override
  String get statusLabel => 'Status';

  @override
  String get issuedTotal => 'Receivables raised';

  @override
  String get collectedTotal => 'Collected';

  @override
  String get outstandingTotal => 'Outstanding';

  @override
  String get allPeriods => 'All months';

  @override
  String get statementsIntro =>
      'A chronological view of receivables, payments and balance.';

  @override
  String get selectFamily => 'Select a subscriber';

  @override
  String get selectFamilyToView =>
      'Select a subscriber to view their statement';

  @override
  String get noMovements => 'No movements';

  @override
  String get movementDate => 'Date';

  @override
  String get movementRef => 'Reference';

  @override
  String get movementType => 'Movement';

  @override
  String get movementDebit => 'Charge';

  @override
  String get movementCredit => 'Payment';

  @override
  String get movementBalance => 'Balance';

  @override
  String get movementNote => 'Notes';

  @override
  String get closingBalance => 'Closing balance';

  @override
  String get officialsIntro => 'Taken from the association settings.';

  @override
  String get notAssigned => 'Not set';

  @override
  String get paymentsIntro =>
      'Each payment is applied to the oldest receivables first, and posted to the treasury in the same instant.';

  @override
  String get noPayments => 'No payments recorded yet';

  @override
  String get registerPayment => 'Register payment';

  @override
  String get receiptNo => 'Receipt no.';

  @override
  String get amount => 'Amount';

  @override
  String get method => 'Payment method';

  @override
  String get methodCash => 'Cash';

  @override
  String get methodTransfer => 'Bank transfer';

  @override
  String get reference => 'Transfer reference';

  @override
  String get receiver => 'Received by';

  @override
  String get notesField => 'Notes';

  @override
  String get allocation => 'Allocation';

  @override
  String get currentDebt => 'Outstanding balance';

  @override
  String get payFullAmount => 'Pay the full balance';

  @override
  String get allocationPreview => 'This amount will be applied to:';

  @override
  String get confirmPayment => 'Confirm payment';

  @override
  String get paymentSaved =>
      'Payment recorded and applied to the oldest receivables';

  @override
  String get noDebtForFamily =>
      'This subscriber has no outstanding balance, so no payment can be recorded.';

  @override
  String amountTooHigh(String amount) {
    return 'Maximum $amount';
  }

  @override
  String get cancelAndReverse => 'Cancel and reverse';

  @override
  String get cancelReason => 'Reason for cancelling';

  @override
  String get cancelReasonHint => 'State why this payment is being cancelled';

  @override
  String get cancelPaymentWarning =>
      'The payment will be cancelled and its effect on receivables and the treasury reversed, while the historical record is kept.';

  @override
  String get confirmCancel => 'Confirm cancellation';

  @override
  String get paymentCancelled => 'Payment cancelled and its effect reversed';

  @override
  String get cashIntro =>
      'Every approved collection appears here automatically.';

  @override
  String get totalCollected => 'Total collected';

  @override
  String get collectedCash => 'Collected in cash';

  @override
  String get collectedTransfer => 'Bank transfers';

  @override
  String get collectedThisYear => 'Collected this year';

  @override
  String get cashMovements => 'Treasury movements';

  @override
  String get noCashMovements => 'No treasury movements yet';

  @override
  String get todayLabel => 'Today';

  @override
  String get thisMonthLabel => 'This month';

  @override
  String get movementTypeLabel => 'Type';

  @override
  String get voided => 'Voided';

  @override
  String get generateReceivables => 'Raise this month\'s receivables';

  @override
  String generateConfirmTitle(String period) {
    return 'Raise receivables for $period';
  }

  @override
  String get generateConfirmBody =>
      'A receivable will be raised for every active subscriber this month. A duplicate for the same subscriber and month is not possible.';

  @override
  String get generateConfirm => 'Raise';

  @override
  String generateResult(int created, int skipped) {
    return '$created raised, $skipped skipped';
  }

  @override
  String get autoClose => 'Close previous months';

  @override
  String autoCloseResult(int count) {
    return '$count months closed';
  }

  @override
  String get nothingToGenerate => 'No new receivables for this month';

  @override
  String get dashboardIntro =>
      'The association\'s administrative and financial position.';

  @override
  String get statAdeels => 'Subscribers';

  @override
  String get statInactive => 'Not billed';

  @override
  String get statTotalDebt => 'Total outstanding';

  @override
  String get statTotalCollected => 'Total collected';

  @override
  String subActive(int count) {
    return '$count active';
  }

  @override
  String subDeceased(int count) {
    return '$count deceased';
  }

  @override
  String subIndebtedAdeels(int count) {
    return '$count subscribers owing';
  }

  @override
  String subCashTransfer(String cash, String transfer) {
    return 'Cash $cash • Transfer $transfer';
  }

  @override
  String get topDebtors => 'Largest balances';

  @override
  String get noDebtsNow => 'No outstanding balances';

  @override
  String get closeMonth => 'Close a month';

  @override
  String get selectPeriodTitle => 'Choose a month';

  @override
  String get noPeriodsToClose => 'No months are closable yet.';

  @override
  String get periodClosedBadge => 'Closed';

  @override
  String get periodClosedNote => 'Already closed';

  @override
  String get periodBlockedNote => 'Close the earlier month first';

  @override
  String get alertsIntro =>
      'Age, balance and payment matters needing follow-up.';

  @override
  String get noAlerts => 'No alerts at the moment';

  @override
  String get allTypes => 'All types';

  @override
  String get reportsIntro => 'Financial summary for the selected period.';

  @override
  String get fromDate => 'From';

  @override
  String get toDate => 'To';

  @override
  String get presetThisMonth => 'This month';

  @override
  String get presetLastMonth => 'Last month';

  @override
  String get presetThisYear => 'This year';

  @override
  String get collectionDetail => 'Collection detail';

  @override
  String issuedCount(int count) {
    return '$count records';
  }

  @override
  String collectedCount(int count) {
    return '$count payments';
  }

  @override
  String get partiallyPaidCount => 'Partially paid';

  @override
  String get openPartially => 'receivables partly settled';

  @override
  String get noReportRows => 'No movements in the selected period';

  @override
  String get auditIntro =>
      'An audit trail of every significant administrative and financial action.';

  @override
  String get noAuditEntries => 'No actions recorded';

  @override
  String get auditActor => 'User';

  @override
  String get allEvents => 'All actions';

  @override
  String get settingsIntro =>
      'These values govern the future only; they never recalculate past receivables.';

  @override
  String get settingsWarning =>
      'Accounting rule: changing the fee here does not alter any receivable already raised.';

  @override
  String get generalSection => 'General';

  @override
  String get treasurerSection => 'Treasurer';

  @override
  String get financeManagerSection => 'Finance manager';

  @override
  String get associationNameField => 'Association name';

  @override
  String get currencyField => 'Currency';

  @override
  String get memberFeeField => 'Monthly member fee';

  @override
  String get systemStartField => 'System start date';

  @override
  String get fullNameField => 'Name';

  @override
  String get save => 'Save';

  @override
  String get settingsSaved =>
      'Settings saved; historical receivables are unchanged';

  @override
  String get confirmChangesTitle => 'Confirm changes';

  @override
  String get noChanges => 'No changes';

  @override
  String get familyCodeTitle => 'Have a subscription code?';

  @override
  String get familyCodeBody =>
      'If an administrator gave you an access code, type it here to see your own subscription straight away.';

  @override
  String get familyCodeField => 'Subscription code';

  @override
  String get familyCodeHint => 'XXXX-XXXX-XXXX';

  @override
  String get familyCodeAction => 'Sign in with a subscription code';

  @override
  String get myFamilyTitle => 'My subscription';

  @override
  String get myFamilyIntro => 'Your subscription and payments. Read-only.';

  @override
  String get myStatementSection => 'Statement';

  @override
  String get issueCodeTitle => 'Subscriber access code';

  @override
  String get issueCodeBody =>
      'Give this code to the subscriber so he can sign in and see only his own figures. Issuing a new code revokes the old one.';

  @override
  String get issueCodeAction => 'Issue access code';

  @override
  String get issueCodeRegenerate => 'Issue a new code';

  @override
  String get issueCodeCopied => 'Code copied';

  @override
  String get dangerZoneSection => 'Danger zone';

  @override
  String get purgeTitle => 'Erase financial data';

  @override
  String get purgeIntro =>
      'Permanently deletes every receivable, payment, cash movement and audit entry. Intended to be used once, to clear trial figures before going live.';

  @override
  String get purgeKeeps =>
      'Kept: subscribers, association settings and user accounts.';

  @override
  String get purgeIrreversible =>
      'This cannot be undone, and no trace of it is left in the audit trail.';

  @override
  String get purgeButton => 'Erase financial data';

  @override
  String get purgeConfirmTitle => 'Permanently erase financial data';

  @override
  String purgeConfirmPrompt(String phrase) {
    return 'To confirm, type: $phrase';
  }

  @override
  String get purgeConfirmField => 'Confirmation phrase';

  @override
  String get purgeConfirmAction => 'Erase permanently';

  @override
  String purgeDone(int count) {
    return 'Erased $count rows; numbering starts over';
  }

  @override
  String get purgeNothingToDo => 'There is no financial data to erase';

  @override
  String get purgeAllTitle => 'Erase the subscriber register';

  @override
  String get purgeAllIntro =>
      'Permanently deletes every subscriber, and all financial data with them. The database returns to empty, as if the system had never been used.';

  @override
  String get purgeAllWhyFinancial =>
      'Why the financial data goes too: every receivable and receipt belongs to a subscriber, so a subscriber cannot be deleted while his receipt survives.';

  @override
  String get purgeAllKeeps =>
      'Kept: association settings and user accounts, so your own sign-in still works.';

  @override
  String get purgeAllButton => 'Erase everything';

  @override
  String get purgeAllConfirmTitle => 'Permanently erase everything';

  @override
  String get purgeAllConfirmAction => 'Erase everything';

  @override
  String get purgeAllNothingToDo => 'There is no data to erase';

  @override
  String get usersIntro => 'Approve new accounts and manage permissions.';

  @override
  String get pendingRequests => 'Pending requests';

  @override
  String get allUsers => 'Users';

  @override
  String get approve => 'Approve';

  @override
  String get suspend => 'Suspend';

  @override
  String get reactivate => 'Reactivate';

  @override
  String get changeRole => 'Change role';

  @override
  String get lastLogin => 'Last sign-in';

  @override
  String get never => 'Never signed in';

  @override
  String get noUsers => 'No users';

  @override
  String get userUpdated => 'Account updated';

  @override
  String get cannotModifySelfNote => 'You cannot modify your own account';

  @override
  String get requiredField => 'This field is required';

  @override
  String get membershipStatusField => 'Membership status';

  @override
  String get statusActive => 'Active';

  @override
  String get statusSuspended => 'Suspended';

  @override
  String get statusDeceased => 'Deceased';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discardChangesBody =>
      'You have unsaved changes. Leave without saving?';

  @override
  String get discard => 'Discard';

  @override
  String get delete => 'Delete';

  @override
  String get navRegister => 'Subscribers';

  @override
  String get addAdeel => 'Add subscriber';

  @override
  String get editAdeel => 'Edit subscriber';

  @override
  String get searchAdeelsHint => 'Search by name or code...';

  @override
  String get noAdeels => 'No subscribers registered yet';

  @override
  String get registerIntro =>
      'Every subscriber is registered in his own name and billed his own subscription.';

  @override
  String get adeelSaved => 'Subscriber saved';

  @override
  String get adeelDeleted => 'Subscriber removed';

  @override
  String get deleteAdeelTitle => 'Remove this subscriber?';

  @override
  String get deleteAdeelBody =>
      'This cannot be undone. A subscriber with any financial history cannot be removed — suspend him instead.';

  @override
  String get monthlyFeeLabel => 'Monthly subscription';

  @override
  String openPeriodsBadge(int count) {
    return '$count open periods';
  }

  @override
  String get issuedLabel => 'Total charged';

  @override
  String get myDuesTitle => 'My subscriptions';

  @override
  String get duesSection => 'Subscriptions';
}
