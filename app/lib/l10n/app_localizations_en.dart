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
  String get chatBoardHint =>
      'Ask about your subscription or anything about the association';

  @override
  String get chatConversations => 'Private';

  @override
  String get chatDirect => 'Members';

  @override
  String get chatDirectEmpty =>
      'No conversations yet — pick a member and start one';

  @override
  String get chatDirectNew => 'Message a member';

  @override
  String get chatDirectPrivate =>
      'This conversation is between the two of you — the board cannot read it';

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
  String get chatYesterday => 'Yesterday';

  @override
  String get chatDeleted => 'Message deleted';

  @override
  String get chatFromBoard => 'Board';

  @override
  String get chatDeleteTitle => 'Delete this message?';

  @override
  String get chatDeleteThisMessage => 'Delete this message';

  @override
  String get chatSelectMessages => 'Select messages to delete';

  @override
  String chatSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get chatSelectAll => 'Select all';

  @override
  String get chatCancelSelection => 'Cancel selection';

  @override
  String chatDeleteManyTitle(int count) {
    return 'Delete $count messages?';
  }

  @override
  String chatDeletedMany(int count) {
    return '$count messages deleted';
  }

  @override
  String get chatClearThread => 'Clear conversation';

  @override
  String chatClearThreadTitle(String name) {
    return 'Clear the conversation with $name?';
  }

  @override
  String get chatClearThreadBody =>
      'Every message in this conversation will be deleted permanently, for you and for the member. This cannot be undone.';

  @override
  String chatClearedThread(int count) {
    return 'Conversation cleared ($count messages)';
  }

  @override
  String get chatClearAllThreads => 'Clear all private messages';

  @override
  String get chatClearAllTitle => 'Clear all private messages?';

  @override
  String chatClearAllBody(int count) {
    return 'Every conversation between the board and the members ($count) will be deleted permanently, for you and for them. This cannot be undone. The group conversation is not affected.';
  }

  @override
  String chatClearedAll(int count) {
    return 'All private messages cleared ($count messages)';
  }

  @override
  String get chatClearConfirm => 'Clear';

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
  String get iceCheck => 'Check the call path';

  @override
  String get iceRunning => 'Checking… up to 12 seconds';

  @override
  String get iceHost => 'Local network';

  @override
  String get iceStun => 'Your public address (STUN)';

  @override
  String get iceRelay => 'Relay server (TURN)';

  @override
  String get iceGood => 'Calls will work between different networks';

  @override
  String get iceWifiOnly => 'Calls will only work on the same network';

  @override
  String get iceNone => 'No network connection';

  @override
  String get iceRelayNote =>
      'If the relay is missing, the fix is in the database settings, not the app';

  @override
  String get callTitle => 'Voice call';

  @override
  String get callStart => 'Voice call';

  @override
  String callIncoming(String name) {
    return '$name is calling';
  }

  @override
  String get notifyServiceTitle => 'Adayl Association';

  @override
  String get notifyServiceBody => 'Listening for calls and messages';

  @override
  String get notifyServiceChannel => 'Background activity';

  @override
  String get notifyCallChannel => 'Calls';

  @override
  String get notifyCallChannelDesc => 'Incoming call ringing';

  @override
  String get notifyChatChannel => 'Messages';

  @override
  String get notifyChatChannelDesc => 'Council and private messages';

  @override
  String get callDirectoryTitle => 'Call a member';

  @override
  String get callDirectoryEmpty => 'No member has activated the app yet';

  @override
  String get callIncomingBody => 'Incoming call — tap to answer';

  @override
  String get chatNewMessagesBody => 'You have new messages';

  @override
  String callOngoing(String name) {
    return 'Call in progress — $name';
  }

  @override
  String get callAnswer => 'Answer';

  @override
  String get callDecline => 'Decline';

  @override
  String get callHangUp => 'End';

  @override
  String get callConnecting => 'Connecting…';

  @override
  String get callRinging => 'Ringing…';

  @override
  String get callTalking => 'Connected';

  @override
  String get callEnded => 'Call ended';

  @override
  String get callFailed => 'Could not connect';

  @override
  String get callMute => 'Mute';

  @override
  String get callUnmute => 'Unmute';

  @override
  String get callSpeaker => 'Speaker';

  @override
  String get callMicDenied => 'A call needs microphone permission';

  @override
  String get noSearchResults => 'No results for your search';

  @override
  String get receivableSearchHint => 'Search by name, code, month or status';

  @override
  String receivableSearchCount(int shown, int total) {
    return 'Showing $shown of $total';
  }

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
  String get kindCollectiveForm => 'For the extended family';

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
  String get disbursementDateAuto =>
      'The date is stamped automatically by the association clock';

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
  String get aidOthersTitle => 'Shared spending';

  @override
  String get aidOthersEmpty => 'No collective spending yet';

  @override
  String get aidOthersRecipients => 'By occasion';

  @override
  String get aidOthersAll => 'All vouchers';

  @override
  String get valueTitle => 'What it is worth';

  @override
  String get valuePaid => 'You paid';

  @override
  String get valueReceived => 'You received';

  @override
  String get valueEven => 'You paid and received the same';

  @override
  String get valueShareTitle => 'What came back to you';

  @override
  String valueShareOf(String percent) {
    return '$percent% of what you paid came back to you';
  }

  @override
  String valueShareOver(String percent) {
    return '$percent% of what you paid came back — more than you paid';
  }

  @override
  String get valueMonths => 'Paid and received, year by year';

  @override
  String get valueYearsHint => 'Tap a year to see its detail';

  @override
  String valueOpeningYear(String year) {
    return 'Up to $year';
  }

  @override
  String get valueColMonth => 'Month';

  @override
  String get valueColYear => 'Year';

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
  String get adeelCredit => 'Credit held';

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
  String get membersMovementTitle => 'Members\' movement';

  @override
  String get memberNetOwedToHim => 'Net balance in his favour';

  @override
  String get memberNetOwedByHim => 'Balance against him';

  @override
  String get memberNetEven => 'Even';

  @override
  String get membersNetOwedToThem => 'Net balance in their favour';

  @override
  String get membersNetOwedByThem => 'Balance against them';

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
  String get periodLastClosed => 'Last closed month';

  @override
  String get periodShowAll => 'Tap to show every month';

  @override
  String get periodHideAll => 'Tap to hide the list';

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
  String get backAction => 'Back';

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
  String get deviceLockedTitle => 'A new key is needed';

  @override
  String get deviceLockedBody =>
      'After signing out, or on a phone other than the registered one, the app opens only with a new key from the association. Ask for one and type it below.';

  @override
  String get portalDetailsHint => '';

  @override
  String get portalBankHint => '';

  @override
  String get portalOfficialsHint => '';

  @override
  String get portalTreasuryHint => '';

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

  @override
  String get unbindTitle => 'Unlink account';

  @override
  String get unbindBody =>
      'This releases the member\'s email and handset and deletes his key. Afterwards any other email can claim him when a new key is issued. Only do this if his email changed or he was linked by mistake.';

  @override
  String get unbindConfirm => 'Unlink';

  @override
  String get unbindDone => 'Unlinked. Issue a new key so he can sign in.';

  @override
  String get unbindNothing => 'No account is linked to this member.';

  @override
  String get arrearsBoardTitle => 'In arrears';

  @override
  String get arrearsBoardClear =>
      'Nobody is in arrears, and nobody holds credit.';

  @override
  String get arrearsBoardNote => 'Red: he owes · Green: he has paid ahead';

  @override
  String get arrearsMine => 'me';

  @override
  String get arrearsHeldLabel => 'paid ahead';

  @override
  String arrearsAlsoHeld(String amount) {
    return 'also holds $amount';
  }

  @override
  String get currency => 'LYD';

  @override
  String chatNotifyHallFrom(String who) {
    return 'The hall · $who';
  }

  @override
  String chatNotifyAndMore(String body, int more) {
    return '$body  (+$more more)';
  }

  @override
  String get valueOwedByHim => 'Balance against him';

  @override
  String get valueOwedToHim => 'Balance in your favour';

  @override
  String get themeLabel => 'Appearance';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get voicePlay => 'Play';

  @override
  String get voiceStop => 'Stop';

  @override
  String get voiceRecord => 'Voice note';

  @override
  String get voiceRecording => 'Recording…';

  @override
  String get voiceCancel => 'Cancel';

  @override
  String get voiceNoMic => 'Recording needs microphone permission';

  @override
  String get voiceTooShort => 'That clip was too short';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get noticesTitle => 'Notifications';

  @override
  String get noticesEmpty => 'No notifications yet';

  @override
  String get noticesEmptyBody =>
      'Everything about you arrives here: payments, monthly dues, disbursements and messages from the board.';

  @override
  String noticesUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new notifications',
      one: '1 new notification',
    );
    return '$_temp0';
  }

  @override
  String get noticeNew => 'New';

  @override
  String get noticeToEveryone => 'Everyone';

  @override
  String get noticeFallbackBody =>
      'You have a new notification from the association';

  @override
  String noticeAndMore(String body, int more) {
    return '$body  (+$more more)';
  }

  @override
  String get notifyNoticeChannel => 'Association notices';

  @override
  String get notifyNoticeChannelDesc =>
      'Payments, dues, disbursements and board messages';

  @override
  String get noticeDetailTitle => 'Notification';

  @override
  String get noticePeekDismiss => 'Dismiss notification';

  @override
  String noticesMoreWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count more in the tab',
      one: '+1 more in the tab',
    );
    return '$_temp0';
  }

  @override
  String get bylawsTitle => 'Association bylaws';

  @override
  String get bylawsCamera => 'Take a photo';

  @override
  String get bylawsFromDevice => 'Upload from device';

  @override
  String bylawsUploading(int current, int total) {
    return 'Uploading page $current of $total';
  }

  @override
  String bylawsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages added',
      one: '1 page added',
      zero: 'No page added',
    );
    return '$_temp0';
  }

  @override
  String bylawsAddedSomeRefused(int added, int refused) {
    return '$added added, $refused skipped: not an image or over 3 MB';
  }

  @override
  String get bylawsPickFailed => 'Could not open the camera or photos';

  @override
  String bylawsPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String get bylawsDelete => 'Delete page';

  @override
  String bylawsDeleteTitle(int number) {
    return 'Delete page $number?';
  }

  @override
  String get bylawsDeleteConfirm => 'Delete';

  @override
  String get bylawsDeleted => 'Page deleted';

  @override
  String get bylawsEmpty => 'No bylaw pages have been uploaded yet';

  @override
  String get proposalsTitle => 'Member proposals';

  @override
  String get proposalAddTitle => 'Add a proposal';

  @override
  String get proposalTitleLabel => 'Proposal title';

  @override
  String get proposalBodyLabel => 'Proposal';

  @override
  String get proposalSend => 'Send proposal';

  @override
  String get proposalTitleEmpty => 'Write the proposal\'s title';

  @override
  String get proposalBodyEmpty => 'Write the proposal';

  @override
  String get proposalSent => 'Proposal sent to the board';

  @override
  String get myProposalsHeading => 'My proposals';

  @override
  String get myProposalsEmpty => 'You have not sent a proposal yet';

  @override
  String get proposalAccepted => 'Accepted';

  @override
  String get proposalPending => 'Under review';

  @override
  String get proposalDetailTitle => 'Proposal';

  @override
  String get proposalAccept => 'Accept';

  @override
  String get proposalReject => 'Reject';

  @override
  String get proposalRejectTitle => 'Reject this proposal?';

  @override
  String get proposalRejectBody =>
      'The proposal will be deleted permanently, for you and for the member.';

  @override
  String get proposalAcceptedDone => 'Proposal accepted and kept';

  @override
  String get proposalRejectedDone => 'Proposal rejected and deleted';

  @override
  String get proposalsEmpty => 'No proposals';

  @override
  String proposalNewFrom(String name) {
    return 'New proposal from $name';
  }

  @override
  String proposalsWaitingHeading(int count) {
    return 'Awaiting a decision ($count)';
  }

  @override
  String proposalsAcceptedHeading(int count) {
    return 'Accepted ($count)';
  }

  @override
  String get noticesClearAll => 'Clear all notifications';

  @override
  String get noticesClearTitle => 'Clear all notifications?';

  @override
  String noticesClearBody(int count) {
    return 'All notifications ($count) will be deleted permanently, for you and for every member. This cannot be undone.';
  }

  @override
  String get noticesClearConfirm => 'Clear';

  @override
  String noticesCleared(int count) {
    return 'All notifications cleared ($count)';
  }

  @override
  String get noticesLogHeading => 'Everything sent';

  @override
  String get noticesAdminRule =>
      'Payments, dues and individual disbursements reach their member only; collective disbursements and board messages reach everyone.';

  @override
  String get broadcastHeading => 'Message to all members';

  @override
  String get broadcastTitleLabel => 'Title (optional)';

  @override
  String get broadcastTitleHint => 'A message from the board';

  @override
  String get broadcastBodyLabel => 'Message';

  @override
  String get broadcastSend => 'Send';

  @override
  String get broadcastEmpty => 'Write the message first';

  @override
  String get broadcastConfirmTitle => 'Send to everyone?';

  @override
  String get broadcastConfirmBody =>
      'This message reaches every member at once and cannot be withdrawn once sent.';

  @override
  String get broadcastSent => 'Message sent to all members';
}
