// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class LAr extends L {
  LAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مشروع جمعية العدايل';

  @override
  String get appTagline => 'نظام إدارة العائلات والاشتراكات والصندوق';

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
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get copy => 'نسخ';

  @override
  String get loading => 'جارٍ التحميل...';

  @override
  String get errorGeneric => 'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً';

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
  String get navHome => 'الرئيسية';

  @override
  String get navFamilies => 'العائلات';

  @override
  String get navMembers => 'الأعضاء';

  @override
  String get navReceivables => 'الاستحقاقات';

  @override
  String get navPayments => 'التحصيل والسداد';

  @override
  String get navPaymentsShort => 'السداد';

  @override
  String get navCash => 'الصندوق';

  @override
  String get navStatements => 'كشوف الحساب';

  @override
  String get navAlerts => 'التنبيهات';

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
  String get searchFamiliesHint =>
      'بحث بالاسم، الرقم الوطني، الهاتف، الاكتتاب، جهة العمل...';

  @override
  String get searchMembersHint =>
      'بحث بالاسم أو الرقم الوطني أو الهاتف أو جهة العمل...';

  @override
  String get noFamilies => 'لا توجد عائلات مسجلة بعد';

  @override
  String get noSearchResults => 'لا توجد نتائج لبحثك';

  @override
  String get noMembers => 'لا يوجد أعضاء مسجلون';

  @override
  String get familiesIntro =>
      'كل عائلة تبدأ بالأب وتندرج تحتها أسماء الأبناء الذكور.';

  @override
  String get membersIntro => 'بحث موحد في الآباء والأبناء الذكور.';

  @override
  String sonsBadge(int count) {
    return '$count أبناء';
  }

  @override
  String eligibleBadge(int count) {
    return '$count مستحقون';
  }

  @override
  String debtBadge(String amount) {
    return 'مديونية $amount';
  }

  @override
  String ageYears(int count) {
    return '$count سنة';
  }

  @override
  String get familySummary => 'ملخص العائلة';

  @override
  String get sonsCount => 'عدد الأبناء';

  @override
  String get eligibleCount => 'المستحقون';

  @override
  String get soonCount => 'قريبون من السن';

  @override
  String get monthlyExpected => 'الاستحقاق الشهري الحالي';

  @override
  String get debt => 'المديونية';

  @override
  String get totalPaid => 'إجمالي المدفوع المعتمد';

  @override
  String get fatherData => 'بيانات الأب';

  @override
  String get sonsSection => 'الأبناء';

  @override
  String get statementShort => 'كشف مختصر';

  @override
  String get phone => 'الهاتف';

  @override
  String get subscriptionNo => 'رقم الاكتتاب';

  @override
  String get dateOfBirth => 'تاريخ الميلاد';

  @override
  String get nationality => 'الجنسية';

  @override
  String get workplace => 'جهة العمل';

  @override
  String get registeredAt => 'تاريخ التسجيل';

  @override
  String get nationalId => 'الرقم الوطني';

  @override
  String get age => 'العمر';

  @override
  String get relation => 'الصفة';

  @override
  String get family => 'العائلة';

  @override
  String get notProvided => '—';

  @override
  String get currentValue => 'القيمة الحالية';

  @override
  String get receivablesIntro =>
      'كل استحقاق يحتفظ بقيمه التاريخية كما كانت وقت الإنشاء، وتغيير الإعدادات لاحقاً لا يغيّر هذه السجلات.';

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
  String get billedSons => 'الأبناء المحتسبون';

  @override
  String get noneBilled => 'لا يوجد';

  @override
  String get fatherFee => 'اشتراك الأب';

  @override
  String get sonFee => 'اشتراك الابن';

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
  String get selectFamily => 'اختر العائلة';

  @override
  String get selectFamilyToView => 'اختر عائلة لعرض كشف الحساب';

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
  String get officialsIntro => 'البيانات المعرفة من إعدادات الجمعية.';

  @override
  String get notAssigned => 'غير محدد';

  @override
  String get paymentsIntro =>
      'يتم توزيع كل دفعة تلقائياً على أقدم الاستحقاقات أولاً، ويتم تسجيل أثرها في الصندوق في نفس اللحظة.';

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
      'هذه العائلة لا توجد عليها مديونية، لذلك لا يمكن تسجيل سداد.';

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
  String get cashIntro => 'كل عملية تحصيل معتمدة تنعكس هنا تلقائياً.';

  @override
  String get totalCollected => 'إجمالي المحصل';

  @override
  String get collectedCash => 'المحصل نقداً';

  @override
  String get collectedTransfer => 'التحويل المصرفي';

  @override
  String get collectedThisYear => 'تحصيل السنة';

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
      'سيتم إنشاء استحقاق لكل عائلة عليها اشتراك مستحق لهذا الشهر. لا يمكن إنشاء استحقاق مكرر لنفس العائلة والشهر.';

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
  String get dashboardIntro => 'ملخص الوضع الإداري والمالي للجمعية.';

  @override
  String get statFamilies => 'عدد العائلات';

  @override
  String get statEligibleSons => 'الأبناء المستحقون';

  @override
  String get statTotalDebt => 'إجمالي المديونية';

  @override
  String get statTotalCollected => 'إجمالي المحصل';

  @override
  String subSons(int count) {
    return 'الأبناء $count';
  }

  @override
  String subApproaching(int count) {
    return 'قريبون من الاستحقاق $count';
  }

  @override
  String subIndebtedFamilies(int count) {
    return '$count عائلة مدينة';
  }

  @override
  String subCashTransfer(String cash, String transfer) {
    return 'نقدي $cash • تحويل $transfer';
  }

  @override
  String get topDebtors => 'أعلى المديونيات';

  @override
  String get upcomingAlerts => 'تنبيهات قريبة';

  @override
  String get noDebtsNow => 'لا توجد مديونيات حالية';

  @override
  String get noAgeAlerts => 'لا توجد تنبيهات عمرية حالياً';

  @override
  String closeMonth(String period) {
    return 'إقفال $period';
  }

  @override
  String get approachingBadge => 'قريب من السن';

  @override
  String sonOf(String father) {
    return 'ابن $father';
  }

  @override
  String get alertsIntro =>
      'تنبيهات العمر والمديونيات والحالات المالية التي تحتاج متابعة.';

  @override
  String get noAlerts => 'لا توجد تنبيهات حالية';

  @override
  String get allTypes => 'كل الأنواع';

  @override
  String get reportsIntro => 'ملخص مالي حسب الفترة المحددة.';

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
  String get auditIntro => 'أثر رقابي لجميع العمليات الإدارية والمالية المهمة.';

  @override
  String get noAuditEntries => 'لا توجد عمليات مسجلة';

  @override
  String get auditActor => 'المستخدم';

  @override
  String get allEvents => 'كل العمليات';

  @override
  String get settingsIntro =>
      'تتحكم هذه القيم في المستقبل فقط، ولا تعيد حساب الاستحقاقات القديمة.';

  @override
  String get settingsWarning =>
      'قاعدة محاسبية: تعديل قيمة الاشتراك أو سن الاستحقاق هنا لا يغيّر أي استحقاق سبق إنشاؤه.';

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
  String get fatherFeeField => 'اشتراك الأب الشهري';

  @override
  String get sonFeeField => 'اشتراك الابن الشهري';

  @override
  String get eligibilityAgeField => 'سن بداية الاشتراك';

  @override
  String get warningMonthsField => 'التنبيه قبل الاستحقاق بالأشهر';

  @override
  String get systemStartField => 'تاريخ بداية العمل بالنظام';

  @override
  String get fullNameField => 'الاسم';

  @override
  String get save => 'حفظ';

  @override
  String get settingsSaved =>
      'تم حفظ الإعدادات، ولن تتغير الاستحقاقات التاريخية';

  @override
  String get confirmChangesTitle => 'تأكيد التغييرات';

  @override
  String get noChanges => 'لا توجد تغييرات';

  @override
  String get familyCodeTitle => 'لديك رمز عائلة؟';

  @override
  String get familyCodeBody =>
      'إن أعطاك مسؤول الجمعية رمز دخول خاصاً بعائلتك، اكتبه هنا لترى بيانات عائلتك مباشرة.';

  @override
  String get familyCodeField => 'رمز العائلة';

  @override
  String get familyCodeHint => 'XXXX-XXXX-XXXX';

  @override
  String get familyCodeAction => 'دخول بحساب العائلة';

  @override
  String get myFamilyTitle => 'عائلتي';

  @override
  String get myFamilyIntro =>
      'بيانات عائلتك واشتراكاتك ومدفوعاتك. للاطلاع فقط.';

  @override
  String get myMembersSection => 'أفراد العائلة';

  @override
  String get myStatementSection => 'كشف الحساب';

  @override
  String get issueCodeTitle => 'رمز دخول العائلة';

  @override
  String get issueCodeBody =>
      'أعطِ هذا الرمز لرب العائلة ليدخل ويرى بيانات عائلته فقط. إصدار رمز جديد يلغي القديم.';

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
      'لا يُحذف: العائلات والأعضاء وإعدادات الجمعية وحسابات المستخدمين.';

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
  String get purgeAllTitle => 'مسح بيانات العائلات والأعضاء';

  @override
  String get purgeAllIntro =>
      'يحذف نهائياً كل العائلات والأعضاء، ومعها كل البيانات المالية. تعود قاعدة البيانات فارغة تماماً كما لو أن النظام لم يُستعمل بعد.';

  @override
  String get purgeAllWhyFinancial =>
      'لماذا تُحذف البيانات المالية معها: كل استحقاق وكل إيصال مرتبط بعائلة، فلا يمكن حذف العائلة وإبقاء إيصالها.';

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
  String get usersIntro => 'اعتماد الحسابات الجديدة وإدارة الصلاحيات.';

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
  String get addFamily => 'إضافة عائلة';

  @override
  String get editFamily => 'تعديل العائلة';

  @override
  String get addSon => 'إضافة ابن';

  @override
  String get removeSon => 'حذف الابن';

  @override
  String sonNumber(int number) {
    return 'الابن رقم $number';
  }

  @override
  String get requiredField => 'هذا الحقل مطلوب';

  @override
  String get familySaved => 'تم حفظ بيانات العائلة';

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
}
