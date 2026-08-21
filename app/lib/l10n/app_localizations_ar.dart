// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class LAr extends L {
  LAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'جمعية العدايل';

  @override
  String get appTagline => 'نظام إدارة المشتركين والاشتراكات والصندوق';

  @override
  String get loginTitle => 'أهلاً بك';

  @override
  String get loginSubtitle => 'سجّل الدخول بحساب Google الخاص بك للمتابعة';

  @override
  String get signInWithGoogle => 'الدخول بحساب Google';

  @override
  String get signingIn => 'جارٍ تسجيل الدخول...';

  @override
  String get signInCancelled => 'تم إلغاء تسجيل الدخول';

  @override
  String get googleNotConfigured =>
      'لم يتم إعداد الدخول بحساب Google على الخادم بعد. يرجى مراجعة مسؤول النظام.';

  @override
  String get devSignIn => 'دخول تطويري بدون Google';

  @override
  String get devSignInWarning =>
      'للتطوير المحلي فقط. لا يتم التحقق من الهوية، ويجب تعطيله قبل التشغيل الفعلي.';

  @override
  String get devSignInEmail => 'البريد الإلكتروني';

  @override
  String get devSignInConfirm => 'دخول';

  @override
  String get pendingTitle => 'بانتظار الموافقة';

  @override
  String get pendingBody =>
      'تم إرسال طلبك إلى مسؤول النظام. ستتمكن من الدخول فور اعتماد حسابك.';

  @override
  String pendingSignedInAs(String email) {
    return 'تم تسجيل الدخول باسم $email';
  }

  @override
  String get forbiddenTitle => 'لا توجد صلاحية';

  @override
  String get forbiddenBody =>
      'ليس لديك صلاحية للوصول إلى هذه الصفحة. تواصل مع مسؤول النظام إذا كنت تعتقد أن هذا خطأ.';

  @override
  String get backToHome => 'العودة إلى الرئيسية';

  @override
  String get suspendedTitle => 'الحساب موقوف';

  @override
  String get suspendedBody => 'تم إيقاف هذا الحساب. يرجى مراجعة مسؤول النظام.';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get refreshData => 'تحديث البيانات';

  @override
  String get refreshedData => 'تم تحديث البيانات من قاعدة البيانات';

  @override
  String get restartApp => 'إعادة تشغيل التطبيق';

  @override
  String get restartAppBody => 'تعود إلى الشاشة الأولى ويضيع ما لم تحفظه.';

  @override
  String get restartConfirm => 'إعادة التشغيل';

  @override
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get copy => 'نسخ';

  @override
  String get copied => 'تم النسخ';

  @override
  String get officialNeedsRegister =>
      'سجل العدايل فارغ — أضف المشتركين أولاً ليمكن اختيار المسؤولين منهم';

  @override
  String get bankAccountSection => 'الحساب المصرفي للجمعية';

  @override
  String get bankNameField => 'اسم المصرف';

  @override
  String get previouslyUsed => 'المستعملة سابقاً';

  @override
  String get bankAccountNoField => 'رقم الحساب';

  @override
  String get bankAccountNameField => 'اسم صاحب الحساب';

  @override
  String get bankAccountNotSetYet =>
      'لم تُسجَّل بيانات حساب الجمعية بعد، راجع إدارة الجمعية قبل التحويل';

  @override
  String get treasuryReadOnlyNote =>
      'أرقام الجمعية للاطلاع فقط — لا توجد أي عملية يمكنك إجراؤها من هنا';

  @override
  String get bankAccountNotConfigured =>
      'لم يُسجَّل الحساب المصرفي للجمعية بعد — أضفه من الإعدادات. يمكنك تسجيل الحوالة الآن، لكن الإيصال لن يذكر حساباً.';

  @override
  String get loading => 'جارٍ التحميل...';

  @override
  String get errorGeneric => 'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً';

  @override
  String get errorSchemaMismatch =>
      'قاعدة البيانات لا تطابق هذا الإصدار من التطبيق. لن تنجح المحاولة مرة أخرى — يلزم تطبيق مخطط قاعدة البيانات.';

  @override
  String get errorProfileMissing =>
      'تم تسجيل الدخول، لكن لا يوجد سجل لهذا الحساب في قاعدة البيانات. لن تنجح المحاولة مرة أخرى — راجع إدارة الجمعية.';

  @override
  String get errorNetwork => 'لا يوجد اتصال بالإنترنت';

  @override
  String get errorNetworkBody =>
      'تعذّر الوصول إلى الخادم. تحقق من اتصالك ثم أعد المحاولة.';

  @override
  String get errorTimeout => 'انتهت مهلة الاتصال بالخادم';

  @override
  String get offlineBanner => 'لا يوجد اتصال بالإنترنت';

  @override
  String get navChat => 'المحادثات';

  @override
  String get chatHall => 'محادثة جماعية';

  @override
  String get chatToBoard => 'مراسلة الإدارة';

  @override
  String get chatInbox => 'الرسائل الخاصة';

  @override
  String get chatPrivateEmpty =>
      'لا رسائل خاصة بعد — اكتب للإدارة وسيصلك الرد هنا';

  @override
  String get chatInboxEmpty => 'لا رسائل خاصة من المشتركين';

  @override
  String get chatHint => 'اكتب رسالتك…';

  @override
  String get chatSend => 'إرسال';

  @override
  String get chatEmoji => 'رموز';

  @override
  String chatUnreadCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count رسالة جديدة',
      few: '$count رسائل جديدة',
      two: 'رسالتان جديدتان',
      one: 'رسالة جديدة',
    );
    return '$_temp0';
  }

  @override
  String get chatUnreadMany => '٩٩+';

  @override
  String get chatNewMessages => 'رسائل جديدة';

  @override
  String get emojiFaces => 'وجوه';

  @override
  String get emojiHands => 'إيماءات ودعاء';

  @override
  String get emojiHearts => 'قلوب';

  @override
  String get emojiOccasions => 'مناسبات';

  @override
  String get emojiBackspace => 'حذف حرف';

  @override
  String get chatEmpty => 'لا رسائل بعد — كن أول من يتحدث';

  @override
  String get chatDeleted => 'حُذفت الرسالة';

  @override
  String get chatFromBoard => 'الإدارة';

  @override
  String get chatDeleteTitle => 'حذف الرسالة؟';

  @override
  String get chatDeleteBody =>
      'ستختفي الكلمات نهائياً ويبقى مكانها ظاهراً في المحادثة.';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navReceivables => 'الاستحقاقات';

  @override
  String get navPayments => 'العمليات';

  @override
  String get navPaymentsShort => 'العمليات';

  @override
  String get opsCollections => 'التحصيل';

  @override
  String get opsDisbursements => 'الصرف';

  @override
  String get opsDisbursementsSoon =>
      'نظام الصرف قيد الإنشاء — لم تُحدَّد بعد بيانات إيصال الصرف';

  @override
  String get navCash => 'الصندوق';

  @override
  String get navStatements => 'كشوف الحساب';

  @override
  String get navReports => 'التقارير';

  @override
  String get navOfficials => 'المسؤولون';

  @override
  String get navAudit => 'سجل العمليات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get navUsers => 'إدارة المستخدمين';

  @override
  String get navMore => 'المزيد';

  @override
  String get roleAdmin => 'مدير النظام';

  @override
  String get roleFinanceManager => 'المدير المالي';

  @override
  String get roleTreasurer => 'أمين الصندوق';

  @override
  String get roleViewer => 'مطّلع';

  @override
  String get comingSoon => 'قيد الإنشاء';

  @override
  String get comingSoonBody => 'سيتم بناء هذه الشاشة في مرحلة لاحقة.';

  @override
  String get noSearchResults => 'لا توجد نتائج لبحثك';

  @override
  String debtBadge(String amount) {
    return 'مديونية $amount';
  }

  @override
  String ageYears(int count) {
    return '$count سنة';
  }

  @override
  String get familySummary => 'ملخص المشترك';

  @override
  String get debt => 'المديونية';

  @override
  String get totalPaid => 'إجمالي المدفوع المعتمد';

  @override
  String get personalData => 'البيانات الشخصية';

  @override
  String get totalDue => 'المستحق';

  @override
  String get phone => 'الهاتف';

  @override
  String get dateOfBirth => 'تاريخ الميلاد';

  @override
  String get registeredAt => 'تاريخ التسجيل';

  @override
  String get age => 'العمر';

  @override
  String get notProvided => '—';

  @override
  String get noReceivables => 'لم يتم إنشاء استحقاقات بعد';

  @override
  String get period => 'الشهر';

  @override
  String get totalAmount => 'الإجمالي';

  @override
  String get paidAmount => 'المسدد';

  @override
  String get remainingAmount => 'المتبقي';

  @override
  String get statusLabel => 'الحالة';

  @override
  String get issuedTotal => 'الاستحقاقات المنشأة';

  @override
  String get collectedTotal => 'المحصل';

  @override
  String get outstandingTotal => 'المديونية القائمة';

  @override
  String get allPeriods => 'كل الأشهر';

  @override
  String get statementsIntro => 'عرض تسلسلي للاستحقاقات والدفعات والرصيد.';

  @override
  String get selectFamily => 'اختر المشترك';

  @override
  String get selectFamilyToView => 'اختر مشتركاً لعرض كشف الحساب';

  @override
  String get noMovements => 'لا توجد حركات';

  @override
  String get movementDate => 'التاريخ';

  @override
  String get movementRef => 'المرجع';

  @override
  String get movementType => 'الحركة';

  @override
  String get movementDebit => 'استحقاق';

  @override
  String get movementCredit => 'سداد';

  @override
  String get movementBalance => 'الرصيد';

  @override
  String get movementNote => 'ملاحظات';

  @override
  String get closingBalance => 'الرصيد الختامي';

  @override
  String get notAssigned => 'غير محدد';

  @override
  String get noPayments => 'لم تُسجَّل أي دفعة بعد';

  @override
  String get registerPayment => 'تسجيل سداد';

  @override
  String get receiptNo => 'رقم الإيصال';

  @override
  String get amount => 'المبلغ';

  @override
  String get method => 'طريقة الدفع';

  @override
  String get methodCash => 'نقداً';

  @override
  String get methodTransfer => 'تحويل مصرفي';

  @override
  String get reference => 'رقم مرجع التحويل';

  @override
  String get receiver => 'المستلم';

  @override
  String get receiverNotConfigured =>
      'لم تُسجَّل أسماء المسؤولين بعد — أضفها من الإعدادات';

  @override
  String get notesField => 'ملاحظات';

  @override
  String get allocation => 'التوزيع';

  @override
  String get currentDebt => 'المديونية الحالية';

  @override
  String get payFullAmount => 'سداد كامل المديونية';

  @override
  String get allocationPreview => 'سيُوزَّع هذا المبلغ على:';

  @override
  String get confirmPayment => 'اعتماد السداد';

  @override
  String get paymentSaved => 'تم تسجيل السداد وتوزيعه على أقدم الاستحقاقات';

  @override
  String get noDebtForFamily =>
      'هذا المشترك لا توجد عليه مديونية، لذلك لا يمكن تسجيل سداد.';

  @override
  String amountTooHigh(String amount) {
    return 'الحد الأقصى $amount';
  }

  @override
  String get cancelAndReverse => 'إلغاء وعكس';

  @override
  String get cancelReason => 'سبب الإلغاء';

  @override
  String get cancelReasonHint => 'اذكر سبب إلغاء هذه الدفعة';

  @override
  String get cancelPaymentWarning =>
      'سيتم إلغاء الدفعة وعكس أثرها على الاستحقاقات والصندوق مع بقاء السجل التاريخي.';

  @override
  String get confirmCancel => 'تأكيد الإلغاء';

  @override
  String get paymentCancelled => 'تم إلغاء الدفعة وعكس أثرها';

  @override
  String get registerDisbursement => 'تسجيل صرف';

  @override
  String get confirmDisbursement => 'اعتماد الصرف';

  @override
  String get kindMember => 'صرف لمشترك';

  @override
  String get kindCollective => 'صرف جماعي';

  @override
  String get expenseCategory => 'بند الصرف';

  @override
  String get categoryRequired => 'اختر بند الصرف';

  @override
  String get payee => 'المستفيد';

  @override
  String get payeeRequired => 'اختر المشترك المستفيد';

  @override
  String get recipient => 'المستلم';

  @override
  String get handedBy => 'المُسلِّم';

  @override
  String get disbursementDate => 'تاريخ الصرف';

  @override
  String get disbursementDateAuto => 'التاريخ يُسجَّل تلقائياً بساعة الجمعية';

  @override
  String get change => 'تغيير';

  @override
  String get voucherNo => 'رقم الإيصال';

  @override
  String get noDisbursements => 'لم يُسجَّل أي صرف بعد';

  @override
  String get totalDisbursed => 'إجمالي المصروف';

  @override
  String get expenseByCategory => 'المصروف حسب البند';

  @override
  String overTreasuryBalance(String amount) {
    return 'رصيد الصندوق $amount فقط';
  }

  @override
  String disbursementSaved(String voucher, String balance) {
    return 'تم تسجيل الصرف $voucher — رصيد الصندوق الآن $balance';
  }

  @override
  String get cancelDisbursement => 'إلغاء الصرف';

  @override
  String get cancelDisbursementWarning =>
      'سيتم إلغاء إيصال الصرف وإعادة قيمته إلى رصيد الجمعية، مع بقاء السجل التاريخي.';

  @override
  String get disbursementCancelled =>
      'تم إلغاء الصرف وأُعيدت قيمته إلى الصندوق';

  @override
  String get aidTitle => 'مصروفات للمشترك';

  @override
  String get myAidTitle => 'أسلافي';

  @override
  String get aidSearchHint => 'بحث';

  @override
  String get aidOthersTitle => 'أسلاف للغير';

  @override
  String get aidOthersEmpty => 'لا صرف جماعي بعد';

  @override
  String get aidOthersRecipients => 'حسب الوجه';

  @override
  String get aidOthersAll => 'كل السندات';

  @override
  String get valueTitle => 'الجدوى';

  @override
  String get valuePaid => 'دفعتَ';

  @override
  String get valueReceived => 'استلمتَ';

  @override
  String get valueAhead => 'أعطتك الجمعية أكثر مما دفعتَ بـ';

  @override
  String get valueSurplus => 'فائض تكافلك';

  @override
  String get valueEven => 'دفعتَ واستلمتَ سواءً';

  @override
  String get valueFund => 'الجمعية';

  @override
  String get valueMonths => 'حركتك خلال 12 شهراً';

  @override
  String valueBackToMembers(String rate) {
    return 'من كل 100 محصَّلة، صُرف $rate على المشتركين';
  }

  @override
  String valueHelped(int helped, int members) {
    return 'وقفت خلف $helped من $members مشتركين';
  }

  @override
  String get valueLargest => 'أكبر ما صُرف لمشترك واحد';

  @override
  String get aidColDate => 'التاريخ';

  @override
  String get aidColSerial => '#';

  @override
  String get aidColCategory => 'البند';

  @override
  String get aidColAmount => 'القيمة';

  @override
  String get aidColRunning => 'الإجمالي';

  @override
  String get aidNoMatch => 'لا يوجد سند يطابق بحثك';

  @override
  String aidShowing(int shown, int total) {
    return '$shown من $total';
  }

  @override
  String get disbursementNoteHint => 'اسم المولود، أو صاحب المناسبة';

  @override
  String get disbursementNoteHelp =>
      'تظهر هذه الملاحظة في كشف المشترك بجانب البند، فيُعرف لماذا صُرف له.';

  @override
  String get aidNoteLabel => 'الملاحظات';

  @override
  String get openAid => 'سجل الأسلاف';

  @override
  String get aidTotal => 'إجمالي ما صُرف له';

  @override
  String get aidCount => 'عدد السندات';

  @override
  String get aidByYear => 'حسب السنة';

  @override
  String get aidVouchers => 'السندات';

  @override
  String get aidPanelTitle => 'الإجمالي';

  @override
  String aidVoucherCount(int count) {
    return '$count سند';
  }

  @override
  String get noAid => 'لم يُصرف له شيء من الجمعية بعد';

  @override
  String get noMyAid => 'لم يُصرف لك شيء من الجمعية بعد';

  @override
  String get totalCollected => 'إجمالي المحصل';

  @override
  String get collectedCash => 'المحصل نقداً';

  @override
  String get collectedTransfer => 'المحصل بتحويل';

  @override
  String get dueFromMembers => 'المستحقات';

  @override
  String get totalOutstanding => 'اشتراكات مستحقة';

  @override
  String get heldForMembers => 'عهد المشتركين';

  @override
  String get adeelCredit => 'العهدة';

  @override
  String get associationBalance => 'رصيد الجمعية';

  @override
  String voucherCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سند صرف',
      few: '$count سندات صرف',
      two: 'سندا صرف',
      one: 'سند صرف واحد',
    );
    return '$_temp0';
  }

  @override
  String receiptCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count إيصالاً',
      few: '$count إيصالات',
      two: 'إيصالان',
      one: 'إيصال واحد',
      zero: 'لا إيصالات',
    );
    return '$_temp0';
  }

  @override
  String get cashMovements => 'حركة الصندوق';

  @override
  String get noCashMovements => 'لم تُسجَّل أي حركة صندوق بعد';

  @override
  String get todayLabel => 'اليوم';

  @override
  String get thisMonthLabel => 'الشهر';

  @override
  String get movementTypeLabel => 'النوع';

  @override
  String get voided => 'ملغي';

  @override
  String get generateReceivables => 'إنشاء استحقاقات الشهر';

  @override
  String generateConfirmTitle(String period) {
    return 'إنشاء استحقاقات $period';
  }

  @override
  String get generateConfirmBody =>
      'سيتم إنشاء استحقاق لكل مشترك نشط لهذا الشهر. لا يمكن إنشاء استحقاق مكرر لنفس المشترك والشهر.';

  @override
  String get generateConfirm => 'إنشاء';

  @override
  String generateResult(int created, int skipped) {
    return 'تم إنشاء $created استحقاق، وتم تجاوز $skipped';
  }

  @override
  String get autoClose => 'إقفال الأشهر السابقة';

  @override
  String autoCloseResult(int count) {
    return 'تم إقفال $count شهراً';
  }

  @override
  String get nothingToGenerate => 'لا توجد استحقاقات جديدة لهذا الشهر';

  @override
  String get statAdeels => 'عدد المشتركين';

  @override
  String get statTotalDebt => 'إجمالي المديونية';

  @override
  String get statTotalCollected => 'إجمالي المحصل';

  @override
  String subActive(int count) {
    return '$count نشط';
  }

  @override
  String subIndebtedAdeels(int count) {
    return '$count مشترك مدين';
  }

  @override
  String subCashTransfer(String cash, String transfer) {
    return 'نقدي $cash • تحويل $transfer';
  }

  @override
  String heldOfWhich(String amount) {
    return 'منها عهد للمشتركين $amount';
  }

  @override
  String get topDebtors => 'أعلى المديونيات';

  @override
  String get noDebtsNow => 'لا توجد مديونيات حالية';

  @override
  String get closeMonth => 'إقفال شهر';

  @override
  String get selectPeriodTitle => 'اختر الشهر';

  @override
  String get noPeriodsToClose => 'لا توجد أشهر قابلة للإقفال بعد.';

  @override
  String get periodClosedBadge => 'مُقفل';

  @override
  String get periodClosedNote => 'أُقفل من قبل';

  @override
  String get periodBlockedNote => 'أقفل ما قبله أولاً';

  @override
  String get fromDate => 'من تاريخ';

  @override
  String get toDate => 'إلى تاريخ';

  @override
  String get presetThisMonth => 'هذا الشهر';

  @override
  String get presetLastMonth => 'الشهر الماضي';

  @override
  String get presetThisYear => 'هذه السنة';

  @override
  String get collectionDetail => 'تفصيل التحصيل';

  @override
  String issuedCount(int count) {
    return '$count سجل';
  }

  @override
  String collectedCount(int count) {
    return '$count دفعة';
  }

  @override
  String get partiallyPaidCount => 'السداد الجزئي';

  @override
  String get openPartially => 'استحقاقات مفتوحة جزئياً';

  @override
  String get noReportRows => 'لا توجد حركات في الفترة المحددة';

  @override
  String get noAuditEntries => 'لا توجد عمليات مسجلة';

  @override
  String get auditActor => 'المستخدم';

  @override
  String get allEvents => 'كل العمليات';

  @override
  String get settingsWarning =>
      'قاعدة محاسبية: تعديل قيمة الاشتراك هنا لا يغيّر أي استحقاق سبق إنشاؤه.';

  @override
  String get generalSection => 'الإعدادات العامة';

  @override
  String get treasurerSection => 'أمين الصندوق';

  @override
  String get financeManagerSection => 'المدير المالي';

  @override
  String get associationNameField => 'اسم الجمعية';

  @override
  String get currencyField => 'العملة';

  @override
  String get memberFeeField => 'اشتراك العضو الشهري';

  @override
  String get feeExceptionLabel => 'ماعدا';

  @override
  String get backAction => 'رجوع';

  @override
  String get feeExceptionAdd => 'إضافة شهر مستثنى';

  @override
  String get systemStartField => 'تاريخ بداية العمل بالنظام';

  @override
  String get fullNameField => 'الاسم';

  @override
  String get save => 'حفظ';

  @override
  String invalidNumberField(String field) {
    return '«$field» يجب أن يكون رقماً، أو اتركه فارغاً لإبقائه كما هو';
  }

  @override
  String invalidDateField(String field) {
    return '«$field» يجب أن يكون تاريخاً بالصيغة YYYY-MM-DD، أو اتركه فارغاً لإبقائه كما هو';
  }

  @override
  String get settingsSaved =>
      'تم حفظ الإعدادات، ولن تتغير الاستحقاقات التاريخية';

  @override
  String get confirmChangesTitle => 'تأكيد التغييرات';

  @override
  String get noChanges => 'لا توجد تغييرات';

  @override
  String get familyCodeTitle => 'لديك رمز اشتراك؟';

  @override
  String get familyCodeBody =>
      'إن أعطاك مسؤول الجمعية رمز دخول خاصاً بك، اكتبه هنا لترى بيانات اشتراكك مباشرة.';

  @override
  String get familyCodeField => 'رمز الاشتراك';

  @override
  String get familyCodeHint => 'XXXX-XXXX-XXXX';

  @override
  String get familyCodeAction => 'دخول برمز الاشتراك';

  @override
  String get myFamilyTitle => 'اشتراكي';

  @override
  String get myFamilyIntro => 'بيانات اشتراكك ومدفوعاتك. للاطلاع فقط.';

  @override
  String get myStatementSection => 'كشف الحساب';

  @override
  String get statementSearchHint => 'بحث';

  @override
  String get clearSearch => 'مسح البحث';

  @override
  String statementShowing(int shown, int total) {
    return 'عرض $shown من $total حركة';
  }

  @override
  String statementShowMore(int count) {
    return 'عرض $count أخرى';
  }

  @override
  String get statementShowAll => 'عرض الكل';

  @override
  String get ledgerParticulars => 'البيان';

  @override
  String get ledgerDebit => 'مدين';

  @override
  String get ledgerCredit => 'دائن';

  @override
  String get ledgerDebitCredit => 'مدين / دائن';

  @override
  String get ledgerBalance => 'الرصيد';

  @override
  String get ledgerTotals => 'الإجمالي';

  @override
  String get balanceDueLabel => 'الرصيد المستحق عليك';

  @override
  String get balanceSettledLabel => 'لا يوجد رصيد مستحق';

  @override
  String get issueCodeTitle => 'رمز دخول المشترك';

  @override
  String get issueCodeBody =>
      'أعطِ هذا الرمز للمشترك ليدخل ويرى بياناته فقط. إصدار رمز جديد يلغي القديم.';

  @override
  String get issueCodeAction => 'إصدار رمز دخول';

  @override
  String get issueCodeRegenerate => 'إصدار رمز جديد';

  @override
  String get issueCodeCopied => 'تم نسخ الرمز';

  @override
  String get dangerZoneSection => 'منطقة الخطر';

  @override
  String get purgeTitle => 'مسح البيانات المالية';

  @override
  String get purgeIntro =>
      'يحذف نهائياً كل الاستحقاقات والتحصيلات وحركات الخزينة وسجل العمليات. يُستعمل مرة واحدة لتصفير بيانات التجربة قبل بدء العمل الفعلي.';

  @override
  String get purgeKeeps =>
      'لا يُحذف: المشتركون وإعدادات الجمعية وحسابات المستخدمين.';

  @override
  String get purgeIrreversible =>
      'لا يمكن التراجع عن هذه العملية، ولا يبقى منها أثر في سجل العمليات.';

  @override
  String get purgeButton => 'مسح البيانات المالية';

  @override
  String get purgeConfirmTitle => 'مسح نهائي للبيانات المالية';

  @override
  String purgeConfirmPrompt(String phrase) {
    return 'للتأكيد، اكتب: $phrase';
  }

  @override
  String get purgeConfirmField => 'عبارة التأكيد';

  @override
  String get purgeConfirmAction => 'مسح نهائي';

  @override
  String purgeDone(int count) {
    return 'تم مسح $count سجل، وأصبح الترقيم يبدأ من جديد';
  }

  @override
  String get purgeNothingToDo => 'لا توجد بيانات مالية لمسحها';

  @override
  String get purgeAllTitle => 'مسح بيانات المشتركين';

  @override
  String get purgeAllIntro =>
      'يحذف نهائياً كل المشتركين، ومعهم كل البيانات المالية. تعود قاعدة البيانات فارغة تماماً كما لو أن النظام لم يُستعمل بعد.';

  @override
  String get purgeAllWhyFinancial =>
      'لماذا تُحذف البيانات المالية معهم: كل استحقاق وكل إيصال مرتبط بمشترك، فلا يمكن حذف المشترك وإبقاء إيصاله.';

  @override
  String get purgeAllKeeps =>
      'لا يُحذف: إعدادات الجمعية وحسابات المستخدمين، فيبقى دخولك للتطبيق كما هو.';

  @override
  String get purgeAllButton => 'مسح كل البيانات';

  @override
  String get purgeAllConfirmTitle => 'مسح نهائي لكل البيانات';

  @override
  String get purgeAllConfirmAction => 'مسح كل البيانات';

  @override
  String get purgeAllNothingToDo => 'لا توجد بيانات لمسحها';

  @override
  String get pendingRequests => 'طلبات معلقة';

  @override
  String get allUsers => 'المستخدمون';

  @override
  String get approve => 'اعتماد';

  @override
  String get suspend => 'إيقاف';

  @override
  String get reactivate => 'إعادة التنشيط';

  @override
  String get changeRole => 'تغيير الدور';

  @override
  String get lastLogin => 'آخر دخول';

  @override
  String get never => 'لم يدخل بعد';

  @override
  String get noUsers => 'لا يوجد مستخدمون';

  @override
  String get userUpdated => 'تم تحديث الحساب';

  @override
  String get cannotModifySelfNote => 'لا يمكنك تعديل حسابك الشخصي';

  @override
  String get requiredField => 'هذا الحقل مطلوب';

  @override
  String get membershipStatusField => 'حالة العضوية';

  @override
  String get statusActive => 'نشط';

  @override
  String get statusSuspended => 'موقوف';

  @override
  String get statusDeceased => 'متوفى';

  @override
  String get discardChangesTitle => 'تجاهل التغييرات؟';

  @override
  String get discardChangesBody =>
      'لديك تغييرات غير محفوظة، هل تريد الخروج بدون حفظ؟';

  @override
  String get discard => 'تجاهل';

  @override
  String get delete => 'حذف';

  @override
  String get navRegister => 'المشتركين';

  @override
  String get addAdeel => 'إضافة مشترك';

  @override
  String get editAdeel => 'تعديل مشترك';

  @override
  String get noAdeels => 'لا يوجد مشتركون مسجلون بعد';

  @override
  String get registerIntro => 'كل مشترك يُسجَّل باسمه ويُحاسَب باشتراكه.';

  @override
  String get adeelSaved => 'تم حفظ بيانات المشترك';

  @override
  String get adeelDeleted => 'تم حذف المشترك';

  @override
  String get deleteAdeelTitle => 'حذف المشترك؟';

  @override
  String get deleteAdeelBody =>
      'لا يمكن التراجع. المشترك الذي له سجل مالي لا يُحذف — غيّر حالته إلى موقوف بدلاً من ذلك.';

  @override
  String get monthlyFeeLabel => 'الاشتراك الشهري';

  @override
  String openPeriodsBadge(int count) {
    return '$count فترة مفتوحة';
  }

  @override
  String get issuedLabel => 'إجمالي المستحق';

  @override
  String get myBalanceNow => 'المستحق عليك';

  @override
  String get myIssuedTotal => 'الاشتراكات';

  @override
  String get myPaidTotal => 'المسدد';

  @override
  String get myRemainingTotal => 'المتبقي';

  @override
  String get myWalletTitle => 'عهدتك لدى الجمعية';

  @override
  String get myWalletBody =>
      'مبلغ مدفوع مقدماً، يُخصم تلقائياً من اشتراك كل شهر جديد';

  @override
  String creditNotice(String amount) {
    return 'أكثر من المستحق بـ $amount — تُضاف إلى رصيده وتُخصم من الأشهر القادمة';
  }

  @override
  String get deviceLockedTitle => 'هذا الاشتراك مرتبط بجهاز آخر';

  @override
  String get deviceLockedBody =>
      'رمز دخولك مفتوح على جهاز واحد فقط، وهذا ليس هو. إن كان جهازك قد تغيّر أو ضاع، راجع إدارة الجمعية لإصدار رمز جديد.';

  @override
  String get portalDetailsHint => 'اسمك ورقمك وحالتك وقيمة اشتراكك الشهري';

  @override
  String get portalBankHint => 'إلى أين تُرسل الحوالة، ورقم الحساب لنسخه';

  @override
  String get portalOfficialsHint => 'بمن تتصل، وأرقام هواتفهم';

  @override
  String get portalTreasuryHint => 'أين يقف مال الجمعية — للاطلاع فقط';

  @override
  String get myDetailsTitle => 'تفاصيل اشتراكي';

  @override
  String ofTotal(String amount) {
    return 'من $amount';
  }

  @override
  String get settledUpTitle => 'لا مستحقات عليك';

  @override
  String get settledUpBody => 'كل اشتراكاتك مسدَّدة. شكراً لالتزامك.';

  @override
  String openMonthsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count شهراً غير مسدَّد',
      few: '$count أشهر غير مسدَّدة',
      two: 'شهران غير مسدَّدين',
      one: 'شهر واحد غير مسدَّد',
    );
    return '$_temp0';
  }

  @override
  String get myDuesTitle => 'اشتراكاتي';

  @override
  String openPeriodsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count شهراً',
      few: '$count أشهر',
      two: 'شهران',
      one: 'شهر واحد',
      zero: 'لا مستحقات',
    );
    return '$_temp0';
  }

  @override
  String get duesSection => 'الاشتراكات';
}
