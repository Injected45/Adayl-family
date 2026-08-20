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
      'You return to the first screen and anything unsaved is lost.';

  @override
  String get restartConfirm => 'Restart';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get officialNeedsRegister =>
      'The register is empty — add subscribers first so officials can be chosen from them';

  @override
  String get bankAccountSection => 'Association bank account';

  @override
  String get bankNameField => 'Bank name';

  @override
  String get previouslyUsed => 'Used before';

  @override
  String get bankAccountNoField => 'Account number';

  @override
  String get bankAccountNameField => 'Account holder name';

  @override
  String get bankAccountNotSetYet =>
      'The association has not recorded its bank details yet — ask before transferring';

  @override
  String get treasuryReadOnlyNote =>
      'The association figures are for information only — there is nothing to do from here';

  @override
  String get bankAccountNotConfigured =>
      'No association bank account set yet — add it in Settings. You can still record the transfer, but the receipt will name no account.';

  @override
  String get loading => 'Loading...';

  @override
  String get errorGeneric => 'Something went wrong. Please try again later.';

  @override
  String get errorSchemaMismatch =>
      'The database does not match this build of the app. Retrying will not help — the schema needs to be applied.';

  @override
  String get errorProfileMissing =>
      'Signed in, but this account has no row in the database. Retrying will not help — contact the association\'s administrator.';

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
  String get navChat => 'Conversations';

  @override
  String get chatHall => 'Group conversation';

  @override
  String get chatToBoard => 'Message the board';

  @override
  String get chatInbox => 'Private messages';

  @override
  String get chatPrivateEmpty =>
      'No private messages yet — write to the board and the reply lands here';

  @override
  String get chatInboxEmpty => 'No private messages from members';

  @override
  String get chatHint => 'Write a message…';

  @override
  String get chatSend => 'Send';

  @override
  String get chatEmoji => 'Emoji';

  @override
  String chatUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new messages',
      one: '1 new message',
    );
    return '$_temp0';
  }

  @override
  String get chatUnreadMany => '99+';

  @override
  String get chatNewMessages => 'New messages';

  @override
  String get emojiFaces => 'Faces';

  @override
  String get emojiHands => 'Gestures';

  @override
  String get emojiHearts => 'Hearts';

  @override
  String get emojiOccasions => 'Occasions';

  @override
  String get emojiBackspace => 'Delete character';

  @override
  String get chatEmpty => 'No messages yet — be the first to speak';

  @override
  String get chatDeleted => 'Message deleted';

  @override
  String get chatFromBoard => 'Board';

  @override
  String get chatDeleteTitle => 'Delete this message?';

  @override
  String get chatDeleteBody =>
      'The words go permanently; the gap stays visible in the conversation.';

  @override
  String get navHome => 'Home';

  @override
  String get navReceivables => 'Receivables';

  @override
  String get navPayments => 'Operations';

  @override
  String get navPaymentsShort => 'Ops';

  @override
  String get opsCollections => 'Collections';

  @override
  String get opsDisbursements => 'Disbursements';

  @override
  String get opsDisbursementsSoon =>
      'The disbursement system is being built — the voucher fields are not settled yet';

  @override
  String get navCash => 'Treasury';

  @override
  String get navStatements => 'Statements';

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
  String get notAssigned => 'Not set';

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
  String get receiverNotConfigured =>
      'No officials named yet — add them in Settings';

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
  String get registerDisbursement => 'Record a disbursement';

  @override
  String get confirmDisbursement => 'Confirm disbursement';

  @override
  String get kindMember => 'To a member';

  @override
  String get kindCollective => 'Collective';

  @override
  String get expenseCategory => 'Expense heading';

  @override
  String get categoryRequired => 'Choose an expense heading';

  @override
  String get payee => 'Beneficiary';

  @override
  String get payeeRequired => 'Choose the beneficiary';

  @override
  String get recipient => 'Recipient';

  @override
  String get handedBy => 'Handed over by';

  @override
  String get disbursementDate => 'Date of disbursement';

  @override
  String get change => 'Change';

  @override
  String get voucherNo => 'Voucher no.';

  @override
  String get noDisbursements => 'No disbursements recorded yet';

  @override
  String get totalDisbursed => 'Total disbursed';

  @override
  String get expenseByCategory => 'Spend by heading';

  @override
  String overTreasuryBalance(String amount) {
    return 'The treasury holds only $amount';
  }

  @override
  String disbursementSaved(String voucher, String balance) {
    return 'Disbursement $voucher recorded — the treasury now holds $balance';
  }

  @override
  String get cancelDisbursement => 'Cancel disbursement';

  @override
  String get cancelDisbursementWarning =>
      'The voucher will be cancelled and its amount returned to the association\'s balance, while the historical record is kept.';

  @override
  String get disbursementCancelled =>
      'Disbursement cancelled and its amount returned to the treasury';

  @override
  String get aidTitle => 'Member expenses';

  @override
  String get myAidTitle => 'My aid';

  @override
  String get aidSearchHint => 'Search';

  @override
  String get aidOthersTitle => 'Aid to others';

  @override
  String get aidOthersEmpty => 'No aid to others yet';

  @override
  String get aidOthersRecipients => 'Recipients';

  @override
  String get aidOthersAll => 'All vouchers';

  @override
  String get valueTitle => 'What it is worth';

  @override
  String get valuePaid => 'You paid';

  @override
  String get valueReceived => 'You received';

  @override
  String get valueAhead => 'The association gave you more than you paid, by';

  @override
  String get valueSurplus => 'Your share of others\' need';

  @override
  String get valueSurplusNote =>
      'It went to helping others, and it is what stands behind you';

  @override
  String get valueEven => 'You paid and received the same';

  @override
  String get valueFund => 'The association';

  @override
  String valueBackToMembers(String rate) {
    return 'Of every 100 collected, $rate went to members';
  }

  @override
  String valueHelped(int helped, int members) {
    return 'It stood behind $helped of $members members';
  }

  @override
  String get valueLargest => 'Largest single payment to one member';

  @override
  String get aidColDate => 'Date';

  @override
  String get aidColSerial => '#';

  @override
  String get aidColCategory => 'Heading';

  @override
  String get aidColAmount => 'Amount';

  @override
  String get aidColRunning => 'Total';

  @override
  String get aidNoMatch => 'No voucher matches your search';

  @override
  String aidShowing(int shown, int total) {
    return '$shown of $total';
  }

  @override
  String get disbursementNoteHint =>
      'Name of the newborn, or whose occasion it was';

  @override
  String get disbursementNoteHelp =>
      'This note appears on the member\'s statement beside the heading, so it is known what the money was for.';

  @override
  String get aidNoteLabel => 'Notes';

  @override
  String get openAid => 'Aid history';

  @override
  String get aidTotal => 'Total paid to him';

  @override
  String get aidCount => 'Vouchers';

  @override
  String get aidByYear => 'By year';

  @override
  String get aidVouchers => 'Vouchers';

  @override
  String get aidPanelTitle => 'Total';

  @override
  String aidVoucherCount(int count) {
    return '$count voucher(s)';
  }

  @override
  String get noAid => 'Nothing has been paid to him yet';

  @override
  String get noMyAid => 'Nothing has been paid to you yet';

  @override
  String get totalCollected => 'Total collected';

  @override
  String get collectedCash => 'Collected in cash';

  @override
  String get collectedTransfer => 'Collected by transfer';

  @override
  String get dueFromMembers => 'Due from members';

  @override
  String get totalOutstanding => 'Dues outstanding';

  @override
  String get heldForMembers => 'Held for members';

  @override
  String get associationBalance => 'Association balance';

  @override
  String voucherCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vouchers',
      one: 'One voucher',
    );
    return '$_temp0';
  }

  @override
  String receiptCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count receipts',
      one: 'One receipt',
      zero: 'No receipts',
    );
    return '$_temp0';
  }

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
  String get statAdeels => 'Subscribers';

  @override
  String get statTotalDebt => 'Total outstanding';

  @override
  String get statTotalCollected => 'Total collected';

  @override
  String subActive(int count) {
    return '$count active';
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
  String heldOfWhich(String amount) {
    return 'of which $amount is held for members';
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
  String get noAuditEntries => 'No actions recorded';

  @override
  String get auditActor => 'User';

  @override
  String get allEvents => 'All actions';

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
  String get feeExceptionLabel => 'Except';

  @override
  String get feeExceptionAdd => 'Add an excepted month';

  @override
  String get systemStartField => 'System start date';

  @override
  String get fullNameField => 'Name';

  @override
  String get save => 'Save';

  @override
  String invalidNumberField(String field) {
    return '\"$field\" must be a number, or leave it empty to keep it as it is';
  }

  @override
  String invalidDateField(String field) {
    return '\"$field\" must be a date in YYYY-MM-DD form, or leave it empty to keep it as it is';
  }

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
  String get statementSearchHint => 'Search';

  @override
  String get clearSearch => 'Clear search';

  @override
  String statementShowing(int shown, int total) {
    return 'Showing $shown of $total movements';
  }

  @override
  String statementShowMore(int count) {
    return 'Show $count more';
  }

  @override
  String get statementShowAll => 'Show all';

  @override
  String get ledgerParticulars => 'Particulars';

  @override
  String get ledgerDebit => 'Debit';

  @override
  String get ledgerCredit => 'Credit';

  @override
  String get ledgerDebitCredit => 'Debit / Credit';

  @override
  String get ledgerBalance => 'Balance';

  @override
  String get ledgerTotals => 'Totals';

  @override
  String get balanceDueLabel => 'Balance you owe';

  @override
  String get balanceSettledLabel => 'Nothing outstanding';

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
  String get myBalanceNow => 'You owe';

  @override
  String get myIssuedTotal => 'Subscriptions';

  @override
  String get myPaidTotal => 'Paid';

  @override
  String get myRemainingTotal => 'Remaining';

  @override
  String get myWalletTitle => 'Held for you';

  @override
  String get myWalletBody =>
      'Paid in advance; each new month is deducted from it automatically';

  @override
  String creditNotice(String amount) {
    return '$amount more than owed — it goes to his credit and covers coming months';
  }

  @override
  String get deviceLockedTitle => 'This subscription is tied to another device';

  @override
  String get deviceLockedBody =>
      'Your access code opens on one device only, and this is not it. If your phone changed or was lost, ask the association to issue a new code.';

  @override
  String get portalDetailsHint => 'Your name, number, status and monthly fee';

  @override
  String get portalBankHint =>
      'Where to send a transfer, with the account number to copy';

  @override
  String get portalOfficialsHint => 'Who to call, and their numbers';

  @override
  String get portalTreasuryHint =>
      'Where the association\'s money stands — to read only';

  @override
  String get myDetailsTitle => 'My subscription details';

  @override
  String ofTotal(String amount) {
    return 'of $amount';
  }

  @override
  String get settledUpTitle => 'Nothing outstanding';

  @override
  String get settledUpBody => 'Every subscription is settled. Thank you.';

  @override
  String openMonthsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months unpaid',
      one: '1 month unpaid',
    );
    return '$_temp0';
  }

  @override
  String get myDuesTitle => 'My subscriptions';

  @override
  String openPeriodsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months',
      one: 'One month',
      zero: 'Nothing due',
    );
    return '$_temp0';
  }

  @override
  String get duesSection => 'Subscriptions';
}
