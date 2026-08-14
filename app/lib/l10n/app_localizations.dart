import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ar, this message translates to:
  /// **'مشروع جمعية العدايل'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In ar, this message translates to:
  /// **'نظام إدارة العائلات والاشتراكات والصندوق'**
  String get appTagline;

  /// No description provided for @loginTitle.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بك'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'سجّل الدخول بحساب Google الخاص بك للمتابعة'**
  String get loginSubtitle;

  /// No description provided for @signInWithGoogle.
  ///
  /// In ar, this message translates to:
  /// **'الدخول بحساب Google'**
  String get signInWithGoogle;

  /// No description provided for @signingIn.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ تسجيل الدخول...'**
  String get signingIn;

  /// No description provided for @signInCancelled.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء تسجيل الدخول'**
  String get signInCancelled;

  /// No description provided for @googleNotConfigured.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم إعداد الدخول بحساب Google على الخادم بعد. يرجى مراجعة مسؤول النظام.'**
  String get googleNotConfigured;

  /// No description provided for @devSignIn.
  ///
  /// In ar, this message translates to:
  /// **'دخول تطويري بدون Google'**
  String get devSignIn;

  /// No description provided for @devSignInWarning.
  ///
  /// In ar, this message translates to:
  /// **'للتطوير المحلي فقط. لا يتم التحقق من الهوية، ويجب تعطيله قبل التشغيل الفعلي.'**
  String get devSignInWarning;

  /// No description provided for @devSignInEmail.
  ///
  /// In ar, this message translates to:
  /// **'البريد الإلكتروني'**
  String get devSignInEmail;

  /// No description provided for @devSignInConfirm.
  ///
  /// In ar, this message translates to:
  /// **'دخول'**
  String get devSignInConfirm;

  /// No description provided for @pendingTitle.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار الموافقة'**
  String get pendingTitle;

  /// No description provided for @pendingBody.
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال طلبك إلى مسؤول النظام. ستتمكن من الدخول فور اعتماد حسابك.'**
  String get pendingBody;

  /// No description provided for @pendingSignedInAs.
  ///
  /// In ar, this message translates to:
  /// **'تم تسجيل الدخول باسم {email}'**
  String pendingSignedInAs(String email);

  /// No description provided for @forbiddenTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد صلاحية'**
  String get forbiddenTitle;

  /// No description provided for @forbiddenBody.
  ///
  /// In ar, this message translates to:
  /// **'ليس لديك صلاحية للوصول إلى هذه الصفحة. تواصل مع مسؤول النظام إذا كنت تعتقد أن هذا خطأ.'**
  String get forbiddenBody;

  /// No description provided for @backToHome.
  ///
  /// In ar, this message translates to:
  /// **'العودة إلى الرئيسية'**
  String get backToHome;

  /// No description provided for @suspendedTitle.
  ///
  /// In ar, this message translates to:
  /// **'الحساب موقوف'**
  String get suspendedTitle;

  /// No description provided for @suspendedBody.
  ///
  /// In ar, this message translates to:
  /// **'تم إيقاف هذا الحساب. يرجى مراجعة مسؤول النظام.'**
  String get suspendedBody;

  /// No description provided for @signOut.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get signOut;

  /// No description provided for @retry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق'**
  String get close;

  /// No description provided for @copy.
  ///
  /// In ar, this message translates to:
  /// **'نسخ'**
  String get copy;

  /// No description provided for @loading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التحميل...'**
  String get loading;

  /// No description provided for @errorGeneric.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع، يرجى المحاولة لاحقاً'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد اتصال بالإنترنت'**
  String get errorNetwork;

  /// No description provided for @errorNetworkBody.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الوصول إلى الخادم. تحقق من اتصالك ثم أعد المحاولة.'**
  String get errorNetworkBody;

  /// No description provided for @errorTimeout.
  ///
  /// In ar, this message translates to:
  /// **'انتهت مهلة الاتصال بالخادم'**
  String get errorTimeout;

  /// No description provided for @offlineBanner.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد اتصال بالإنترنت'**
  String get offlineBanner;

  /// No description provided for @navHome.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get navHome;

  /// No description provided for @navFamilies.
  ///
  /// In ar, this message translates to:
  /// **'العائلات'**
  String get navFamilies;

  /// No description provided for @navMembers.
  ///
  /// In ar, this message translates to:
  /// **'الأعضاء'**
  String get navMembers;

  /// No description provided for @navReceivables.
  ///
  /// In ar, this message translates to:
  /// **'الاستحقاقات'**
  String get navReceivables;

  /// No description provided for @navPayments.
  ///
  /// In ar, this message translates to:
  /// **'التحصيل والسداد'**
  String get navPayments;

  /// No description provided for @navPaymentsShort.
  ///
  /// In ar, this message translates to:
  /// **'السداد'**
  String get navPaymentsShort;

  /// No description provided for @navCash.
  ///
  /// In ar, this message translates to:
  /// **'الصندوق'**
  String get navCash;

  /// No description provided for @navStatements.
  ///
  /// In ar, this message translates to:
  /// **'كشوف الحساب'**
  String get navStatements;

  /// No description provided for @navAlerts.
  ///
  /// In ar, this message translates to:
  /// **'التنبيهات'**
  String get navAlerts;

  /// No description provided for @navReports.
  ///
  /// In ar, this message translates to:
  /// **'التقارير'**
  String get navReports;

  /// No description provided for @navOfficials.
  ///
  /// In ar, this message translates to:
  /// **'المسؤولون'**
  String get navOfficials;

  /// No description provided for @navAudit.
  ///
  /// In ar, this message translates to:
  /// **'سجل العمليات'**
  String get navAudit;

  /// No description provided for @navSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get navSettings;

  /// No description provided for @navUsers.
  ///
  /// In ar, this message translates to:
  /// **'إدارة المستخدمين'**
  String get navUsers;

  /// No description provided for @navMore.
  ///
  /// In ar, this message translates to:
  /// **'المزيد'**
  String get navMore;

  /// No description provided for @roleAdmin.
  ///
  /// In ar, this message translates to:
  /// **'مدير النظام'**
  String get roleAdmin;

  /// No description provided for @roleFinanceManager.
  ///
  /// In ar, this message translates to:
  /// **'المدير المالي'**
  String get roleFinanceManager;

  /// No description provided for @roleTreasurer.
  ///
  /// In ar, this message translates to:
  /// **'أمين الصندوق'**
  String get roleTreasurer;

  /// No description provided for @roleViewer.
  ///
  /// In ar, this message translates to:
  /// **'مطّلع'**
  String get roleViewer;

  /// No description provided for @comingSoon.
  ///
  /// In ar, this message translates to:
  /// **'قيد الإنشاء'**
  String get comingSoon;

  /// No description provided for @comingSoonBody.
  ///
  /// In ar, this message translates to:
  /// **'سيتم بناء هذه الشاشة في مرحلة لاحقة.'**
  String get comingSoonBody;

  /// No description provided for @searchFamiliesHint.
  ///
  /// In ar, this message translates to:
  /// **'بحث بالاسم، الرقم الوطني، الهاتف، الاكتتاب، جهة العمل...'**
  String get searchFamiliesHint;

  /// No description provided for @searchMembersHint.
  ///
  /// In ar, this message translates to:
  /// **'بحث بالاسم أو الرقم الوطني أو الهاتف أو جهة العمل...'**
  String get searchMembersHint;

  /// No description provided for @noFamilies.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد عائلات مسجلة بعد'**
  String get noFamilies;

  /// No description provided for @noSearchResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج لبحثك'**
  String get noSearchResults;

  /// No description provided for @noMembers.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد أعضاء مسجلون'**
  String get noMembers;

  /// No description provided for @familiesIntro.
  ///
  /// In ar, this message translates to:
  /// **'كل عائلة تبدأ بالأب وتندرج تحتها أسماء الأبناء الذكور.'**
  String get familiesIntro;

  /// No description provided for @membersIntro.
  ///
  /// In ar, this message translates to:
  /// **'بحث موحد في الآباء والأبناء الذكور.'**
  String get membersIntro;

  /// No description provided for @sonsBadge.
  ///
  /// In ar, this message translates to:
  /// **'{count} أبناء'**
  String sonsBadge(int count);

  /// No description provided for @eligibleBadge.
  ///
  /// In ar, this message translates to:
  /// **'{count} مستحقون'**
  String eligibleBadge(int count);

  /// No description provided for @debtBadge.
  ///
  /// In ar, this message translates to:
  /// **'مديونية {amount}'**
  String debtBadge(String amount);

  /// No description provided for @ageYears.
  ///
  /// In ar, this message translates to:
  /// **'{count} سنة'**
  String ageYears(int count);

  /// No description provided for @familySummary.
  ///
  /// In ar, this message translates to:
  /// **'ملخص العائلة'**
  String get familySummary;

  /// No description provided for @sonsCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد الأبناء'**
  String get sonsCount;

  /// No description provided for @eligibleCount.
  ///
  /// In ar, this message translates to:
  /// **'المستحقون'**
  String get eligibleCount;

  /// No description provided for @soonCount.
  ///
  /// In ar, this message translates to:
  /// **'قريبون من السن'**
  String get soonCount;

  /// No description provided for @monthlyExpected.
  ///
  /// In ar, this message translates to:
  /// **'الاستحقاق الشهري الحالي'**
  String get monthlyExpected;

  /// No description provided for @debt.
  ///
  /// In ar, this message translates to:
  /// **'المديونية'**
  String get debt;

  /// No description provided for @totalPaid.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المدفوع المعتمد'**
  String get totalPaid;

  /// No description provided for @fatherData.
  ///
  /// In ar, this message translates to:
  /// **'بيانات الأب'**
  String get fatherData;

  /// No description provided for @sonsSection.
  ///
  /// In ar, this message translates to:
  /// **'الأبناء'**
  String get sonsSection;

  /// No description provided for @statementShort.
  ///
  /// In ar, this message translates to:
  /// **'كشف مختصر'**
  String get statementShort;

  /// No description provided for @phone.
  ///
  /// In ar, this message translates to:
  /// **'الهاتف'**
  String get phone;

  /// No description provided for @subscriptionNo.
  ///
  /// In ar, this message translates to:
  /// **'رقم الاكتتاب'**
  String get subscriptionNo;

  /// No description provided for @dateOfBirth.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الميلاد'**
  String get dateOfBirth;

  /// No description provided for @nationality.
  ///
  /// In ar, this message translates to:
  /// **'الجنسية'**
  String get nationality;

  /// No description provided for @workplace.
  ///
  /// In ar, this message translates to:
  /// **'جهة العمل'**
  String get workplace;

  /// No description provided for @registeredAt.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ التسجيل'**
  String get registeredAt;

  /// No description provided for @nationalId.
  ///
  /// In ar, this message translates to:
  /// **'الرقم الوطني'**
  String get nationalId;

  /// No description provided for @age.
  ///
  /// In ar, this message translates to:
  /// **'العمر'**
  String get age;

  /// No description provided for @relation.
  ///
  /// In ar, this message translates to:
  /// **'الصفة'**
  String get relation;

  /// No description provided for @family.
  ///
  /// In ar, this message translates to:
  /// **'العائلة'**
  String get family;

  /// No description provided for @notProvided.
  ///
  /// In ar, this message translates to:
  /// **'—'**
  String get notProvided;

  /// No description provided for @currentValue.
  ///
  /// In ar, this message translates to:
  /// **'القيمة الحالية'**
  String get currentValue;

  /// No description provided for @receivablesIntro.
  ///
  /// In ar, this message translates to:
  /// **'كل استحقاق يحتفظ بقيمه التاريخية كما كانت وقت الإنشاء، وتغيير الإعدادات لاحقاً لا يغيّر هذه السجلات.'**
  String get receivablesIntro;

  /// No description provided for @noReceivables.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم إنشاء استحقاقات بعد'**
  String get noReceivables;

  /// No description provided for @period.
  ///
  /// In ar, this message translates to:
  /// **'الشهر'**
  String get period;

  /// No description provided for @totalAmount.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get totalAmount;

  /// No description provided for @paidAmount.
  ///
  /// In ar, this message translates to:
  /// **'المسدد'**
  String get paidAmount;

  /// No description provided for @remainingAmount.
  ///
  /// In ar, this message translates to:
  /// **'المتبقي'**
  String get remainingAmount;

  /// No description provided for @statusLabel.
  ///
  /// In ar, this message translates to:
  /// **'الحالة'**
  String get statusLabel;

  /// No description provided for @billedSons.
  ///
  /// In ar, this message translates to:
  /// **'الأبناء المحتسبون'**
  String get billedSons;

  /// No description provided for @noneBilled.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد'**
  String get noneBilled;

  /// No description provided for @fatherFee.
  ///
  /// In ar, this message translates to:
  /// **'اشتراك الأب'**
  String get fatherFee;

  /// No description provided for @sonFee.
  ///
  /// In ar, this message translates to:
  /// **'اشتراك الابن'**
  String get sonFee;

  /// No description provided for @issuedTotal.
  ///
  /// In ar, this message translates to:
  /// **'الاستحقاقات المنشأة'**
  String get issuedTotal;

  /// No description provided for @collectedTotal.
  ///
  /// In ar, this message translates to:
  /// **'المحصل'**
  String get collectedTotal;

  /// No description provided for @outstandingTotal.
  ///
  /// In ar, this message translates to:
  /// **'المديونية القائمة'**
  String get outstandingTotal;

  /// No description provided for @allPeriods.
  ///
  /// In ar, this message translates to:
  /// **'كل الأشهر'**
  String get allPeriods;

  /// No description provided for @statementsIntro.
  ///
  /// In ar, this message translates to:
  /// **'عرض تسلسلي للاستحقاقات والدفعات والرصيد.'**
  String get statementsIntro;

  /// No description provided for @selectFamily.
  ///
  /// In ar, this message translates to:
  /// **'اختر العائلة'**
  String get selectFamily;

  /// No description provided for @selectFamilyToView.
  ///
  /// In ar, this message translates to:
  /// **'اختر عائلة لعرض كشف الحساب'**
  String get selectFamilyToView;

  /// No description provided for @noMovements.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حركات'**
  String get noMovements;

  /// No description provided for @movementDate.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get movementDate;

  /// No description provided for @movementRef.
  ///
  /// In ar, this message translates to:
  /// **'المرجع'**
  String get movementRef;

  /// No description provided for @movementType.
  ///
  /// In ar, this message translates to:
  /// **'الحركة'**
  String get movementType;

  /// No description provided for @movementDebit.
  ///
  /// In ar, this message translates to:
  /// **'استحقاق'**
  String get movementDebit;

  /// No description provided for @movementCredit.
  ///
  /// In ar, this message translates to:
  /// **'سداد'**
  String get movementCredit;

  /// No description provided for @movementBalance.
  ///
  /// In ar, this message translates to:
  /// **'الرصيد'**
  String get movementBalance;

  /// No description provided for @movementNote.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات'**
  String get movementNote;

  /// No description provided for @closingBalance.
  ///
  /// In ar, this message translates to:
  /// **'الرصيد الختامي'**
  String get closingBalance;

  /// No description provided for @officialsIntro.
  ///
  /// In ar, this message translates to:
  /// **'البيانات المعرفة من إعدادات الجمعية.'**
  String get officialsIntro;

  /// No description provided for @notAssigned.
  ///
  /// In ar, this message translates to:
  /// **'غير محدد'**
  String get notAssigned;

  /// No description provided for @paymentsIntro.
  ///
  /// In ar, this message translates to:
  /// **'يتم توزيع كل دفعة تلقائياً على أقدم الاستحقاقات أولاً، ويتم تسجيل أثرها في الصندوق في نفس اللحظة.'**
  String get paymentsIntro;

  /// No description provided for @noPayments.
  ///
  /// In ar, this message translates to:
  /// **'لم تُسجَّل أي دفعة بعد'**
  String get noPayments;

  /// No description provided for @registerPayment.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل سداد'**
  String get registerPayment;

  /// No description provided for @receiptNo.
  ///
  /// In ar, this message translates to:
  /// **'رقم الإيصال'**
  String get receiptNo;

  /// No description provided for @amount.
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get amount;

  /// No description provided for @method.
  ///
  /// In ar, this message translates to:
  /// **'طريقة الدفع'**
  String get method;

  /// No description provided for @methodCash.
  ///
  /// In ar, this message translates to:
  /// **'نقداً'**
  String get methodCash;

  /// No description provided for @methodTransfer.
  ///
  /// In ar, this message translates to:
  /// **'تحويل مصرفي'**
  String get methodTransfer;

  /// No description provided for @reference.
  ///
  /// In ar, this message translates to:
  /// **'رقم مرجع التحويل'**
  String get reference;

  /// No description provided for @receiver.
  ///
  /// In ar, this message translates to:
  /// **'المستلم'**
  String get receiver;

  /// No description provided for @notesField.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظات'**
  String get notesField;

  /// No description provided for @allocation.
  ///
  /// In ar, this message translates to:
  /// **'التوزيع'**
  String get allocation;

  /// No description provided for @currentDebt.
  ///
  /// In ar, this message translates to:
  /// **'المديونية الحالية'**
  String get currentDebt;

  /// No description provided for @payFullAmount.
  ///
  /// In ar, this message translates to:
  /// **'سداد كامل المديونية'**
  String get payFullAmount;

  /// No description provided for @allocationPreview.
  ///
  /// In ar, this message translates to:
  /// **'سيُوزَّع هذا المبلغ على:'**
  String get allocationPreview;

  /// No description provided for @confirmPayment.
  ///
  /// In ar, this message translates to:
  /// **'اعتماد السداد'**
  String get confirmPayment;

  /// No description provided for @paymentSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم تسجيل السداد وتوزيعه على أقدم الاستحقاقات'**
  String get paymentSaved;

  /// No description provided for @noDebtForFamily.
  ///
  /// In ar, this message translates to:
  /// **'هذه العائلة لا توجد عليها مديونية، لذلك لا يمكن تسجيل سداد.'**
  String get noDebtForFamily;

  /// No description provided for @amountTooHigh.
  ///
  /// In ar, this message translates to:
  /// **'الحد الأقصى {amount}'**
  String amountTooHigh(String amount);

  /// No description provided for @cancelAndReverse.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء وعكس'**
  String get cancelAndReverse;

  /// No description provided for @cancelReason.
  ///
  /// In ar, this message translates to:
  /// **'سبب الإلغاء'**
  String get cancelReason;

  /// No description provided for @cancelReasonHint.
  ///
  /// In ar, this message translates to:
  /// **'اذكر سبب إلغاء هذه الدفعة'**
  String get cancelReasonHint;

  /// No description provided for @cancelPaymentWarning.
  ///
  /// In ar, this message translates to:
  /// **'سيتم إلغاء الدفعة وعكس أثرها على الاستحقاقات والصندوق مع بقاء السجل التاريخي.'**
  String get cancelPaymentWarning;

  /// No description provided for @confirmCancel.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الإلغاء'**
  String get confirmCancel;

  /// No description provided for @paymentCancelled.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء الدفعة وعكس أثرها'**
  String get paymentCancelled;

  /// No description provided for @cashIntro.
  ///
  /// In ar, this message translates to:
  /// **'كل عملية تحصيل معتمدة تنعكس هنا تلقائياً.'**
  String get cashIntro;

  /// No description provided for @totalCollected.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المحصل'**
  String get totalCollected;

  /// No description provided for @collectedCash.
  ///
  /// In ar, this message translates to:
  /// **'المحصل نقداً'**
  String get collectedCash;

  /// No description provided for @collectedTransfer.
  ///
  /// In ar, this message translates to:
  /// **'التحويل المصرفي'**
  String get collectedTransfer;

  /// No description provided for @collectedThisYear.
  ///
  /// In ar, this message translates to:
  /// **'تحصيل السنة'**
  String get collectedThisYear;

  /// No description provided for @cashMovements.
  ///
  /// In ar, this message translates to:
  /// **'حركة الصندوق'**
  String get cashMovements;

  /// No description provided for @noCashMovements.
  ///
  /// In ar, this message translates to:
  /// **'لم تُسجَّل أي حركة صندوق بعد'**
  String get noCashMovements;

  /// No description provided for @todayLabel.
  ///
  /// In ar, this message translates to:
  /// **'اليوم'**
  String get todayLabel;

  /// No description provided for @thisMonthLabel.
  ///
  /// In ar, this message translates to:
  /// **'الشهر'**
  String get thisMonthLabel;

  /// No description provided for @movementTypeLabel.
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get movementTypeLabel;

  /// No description provided for @voided.
  ///
  /// In ar, this message translates to:
  /// **'ملغي'**
  String get voided;

  /// No description provided for @generateReceivables.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء استحقاقات الشهر'**
  String get generateReceivables;

  /// No description provided for @generateConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء استحقاقات {period}'**
  String generateConfirmTitle(String period);

  /// No description provided for @generateConfirmBody.
  ///
  /// In ar, this message translates to:
  /// **'سيتم إنشاء استحقاق لكل عائلة عليها اشتراك مستحق لهذا الشهر. لا يمكن إنشاء استحقاق مكرر لنفس العائلة والشهر.'**
  String get generateConfirmBody;

  /// No description provided for @generateConfirm.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء'**
  String get generateConfirm;

  /// No description provided for @generateResult.
  ///
  /// In ar, this message translates to:
  /// **'تم إنشاء {created} استحقاق، وتم تجاوز {skipped}'**
  String generateResult(int created, int skipped);

  /// No description provided for @autoClose.
  ///
  /// In ar, this message translates to:
  /// **'إقفال الأشهر السابقة'**
  String get autoClose;

  /// No description provided for @autoCloseResult.
  ///
  /// In ar, this message translates to:
  /// **'تم إقفال {count} شهراً'**
  String autoCloseResult(int count);

  /// No description provided for @nothingToGenerate.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد استحقاقات جديدة لهذا الشهر'**
  String get nothingToGenerate;

  /// No description provided for @dashboardIntro.
  ///
  /// In ar, this message translates to:
  /// **'ملخص الوضع الإداري والمالي للجمعية.'**
  String get dashboardIntro;

  /// No description provided for @statFamilies.
  ///
  /// In ar, this message translates to:
  /// **'عدد العائلات'**
  String get statFamilies;

  /// No description provided for @statEligibleSons.
  ///
  /// In ar, this message translates to:
  /// **'الأبناء المستحقون'**
  String get statEligibleSons;

  /// No description provided for @statTotalDebt.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المديونية'**
  String get statTotalDebt;

  /// No description provided for @statTotalCollected.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المحصل'**
  String get statTotalCollected;

  /// No description provided for @subSons.
  ///
  /// In ar, this message translates to:
  /// **'الأبناء {count}'**
  String subSons(int count);

  /// No description provided for @subApproaching.
  ///
  /// In ar, this message translates to:
  /// **'قريبون من الاستحقاق {count}'**
  String subApproaching(int count);

  /// No description provided for @subIndebtedFamilies.
  ///
  /// In ar, this message translates to:
  /// **'{count} عائلة مدينة'**
  String subIndebtedFamilies(int count);

  /// No description provided for @subCashTransfer.
  ///
  /// In ar, this message translates to:
  /// **'نقدي {cash} • تحويل {transfer}'**
  String subCashTransfer(String cash, String transfer);

  /// No description provided for @topDebtors.
  ///
  /// In ar, this message translates to:
  /// **'أعلى المديونيات'**
  String get topDebtors;

  /// No description provided for @upcomingAlerts.
  ///
  /// In ar, this message translates to:
  /// **'تنبيهات قريبة'**
  String get upcomingAlerts;

  /// No description provided for @noDebtsNow.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد مديونيات حالية'**
  String get noDebtsNow;

  /// No description provided for @noAgeAlerts.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تنبيهات عمرية حالياً'**
  String get noAgeAlerts;

  /// No description provided for @closeMonth.
  ///
  /// In ar, this message translates to:
  /// **'إقفال {period}'**
  String closeMonth(String period);

  /// No description provided for @approachingBadge.
  ///
  /// In ar, this message translates to:
  /// **'قريب من السن'**
  String get approachingBadge;

  /// No description provided for @sonOf.
  ///
  /// In ar, this message translates to:
  /// **'ابن {father}'**
  String sonOf(String father);

  /// No description provided for @alertsIntro.
  ///
  /// In ar, this message translates to:
  /// **'تنبيهات العمر والمديونيات والحالات المالية التي تحتاج متابعة.'**
  String get alertsIntro;

  /// No description provided for @noAlerts.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تنبيهات حالية'**
  String get noAlerts;

  /// No description provided for @allTypes.
  ///
  /// In ar, this message translates to:
  /// **'كل الأنواع'**
  String get allTypes;

  /// No description provided for @reportsIntro.
  ///
  /// In ar, this message translates to:
  /// **'ملخص مالي حسب الفترة المحددة.'**
  String get reportsIntro;

  /// No description provided for @fromDate.
  ///
  /// In ar, this message translates to:
  /// **'من تاريخ'**
  String get fromDate;

  /// No description provided for @toDate.
  ///
  /// In ar, this message translates to:
  /// **'إلى تاريخ'**
  String get toDate;

  /// No description provided for @presetThisMonth.
  ///
  /// In ar, this message translates to:
  /// **'هذا الشهر'**
  String get presetThisMonth;

  /// No description provided for @presetLastMonth.
  ///
  /// In ar, this message translates to:
  /// **'الشهر الماضي'**
  String get presetLastMonth;

  /// No description provided for @presetThisYear.
  ///
  /// In ar, this message translates to:
  /// **'هذه السنة'**
  String get presetThisYear;

  /// No description provided for @collectionDetail.
  ///
  /// In ar, this message translates to:
  /// **'تفصيل التحصيل'**
  String get collectionDetail;

  /// No description provided for @issuedCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} سجل'**
  String issuedCount(int count);

  /// No description provided for @collectedCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} دفعة'**
  String collectedCount(int count);

  /// No description provided for @partiallyPaidCount.
  ///
  /// In ar, this message translates to:
  /// **'السداد الجزئي'**
  String get partiallyPaidCount;

  /// No description provided for @openPartially.
  ///
  /// In ar, this message translates to:
  /// **'استحقاقات مفتوحة جزئياً'**
  String get openPartially;

  /// No description provided for @noReportRows.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حركات في الفترة المحددة'**
  String get noReportRows;

  /// No description provided for @auditIntro.
  ///
  /// In ar, this message translates to:
  /// **'أثر رقابي لجميع العمليات الإدارية والمالية المهمة.'**
  String get auditIntro;

  /// No description provided for @noAuditEntries.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد عمليات مسجلة'**
  String get noAuditEntries;

  /// No description provided for @auditActor.
  ///
  /// In ar, this message translates to:
  /// **'المستخدم'**
  String get auditActor;

  /// No description provided for @allEvents.
  ///
  /// In ar, this message translates to:
  /// **'كل العمليات'**
  String get allEvents;

  /// No description provided for @settingsIntro.
  ///
  /// In ar, this message translates to:
  /// **'تتحكم هذه القيم في المستقبل فقط، ولا تعيد حساب الاستحقاقات القديمة.'**
  String get settingsIntro;

  /// No description provided for @settingsWarning.
  ///
  /// In ar, this message translates to:
  /// **'قاعدة محاسبية: تعديل قيمة الاشتراك أو سن الاستحقاق هنا لا يغيّر أي استحقاق سبق إنشاؤه.'**
  String get settingsWarning;

  /// No description provided for @generalSection.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات العامة'**
  String get generalSection;

  /// No description provided for @treasurerSection.
  ///
  /// In ar, this message translates to:
  /// **'أمين الصندوق'**
  String get treasurerSection;

  /// No description provided for @financeManagerSection.
  ///
  /// In ar, this message translates to:
  /// **'المدير المالي'**
  String get financeManagerSection;

  /// No description provided for @associationNameField.
  ///
  /// In ar, this message translates to:
  /// **'اسم الجمعية'**
  String get associationNameField;

  /// No description provided for @currencyField.
  ///
  /// In ar, this message translates to:
  /// **'العملة'**
  String get currencyField;

  /// No description provided for @fatherFeeField.
  ///
  /// In ar, this message translates to:
  /// **'اشتراك الأب الشهري'**
  String get fatherFeeField;

  /// No description provided for @sonFeeField.
  ///
  /// In ar, this message translates to:
  /// **'اشتراك الابن الشهري'**
  String get sonFeeField;

  /// No description provided for @eligibilityAgeField.
  ///
  /// In ar, this message translates to:
  /// **'سن بداية الاشتراك'**
  String get eligibilityAgeField;

  /// No description provided for @warningMonthsField.
  ///
  /// In ar, this message translates to:
  /// **'التنبيه قبل الاستحقاق بالأشهر'**
  String get warningMonthsField;

  /// No description provided for @systemStartField.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ بداية العمل بالنظام'**
  String get systemStartField;

  /// No description provided for @fullNameField.
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get fullNameField;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @settingsSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ الإعدادات، ولن تتغير الاستحقاقات التاريخية'**
  String get settingsSaved;

  /// No description provided for @confirmChangesTitle.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد التغييرات'**
  String get confirmChangesTitle;

  /// No description provided for @noChanges.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تغييرات'**
  String get noChanges;

  /// No description provided for @familyCodeTitle.
  ///
  /// In ar, this message translates to:
  /// **'لديك رمز عائلة؟'**
  String get familyCodeTitle;

  /// No description provided for @familyCodeBody.
  ///
  /// In ar, this message translates to:
  /// **'إن أعطاك مسؤول الجمعية رمز دخول خاصاً بعائلتك، اكتبه هنا لترى بيانات عائلتك مباشرة.'**
  String get familyCodeBody;

  /// No description provided for @familyCodeField.
  ///
  /// In ar, this message translates to:
  /// **'رمز العائلة'**
  String get familyCodeField;

  /// No description provided for @familyCodeHint.
  ///
  /// In ar, this message translates to:
  /// **'XXXX-XXXX-XXXX'**
  String get familyCodeHint;

  /// No description provided for @familyCodeAction.
  ///
  /// In ar, this message translates to:
  /// **'دخول بحساب العائلة'**
  String get familyCodeAction;

  /// No description provided for @myFamilyTitle.
  ///
  /// In ar, this message translates to:
  /// **'عائلتي'**
  String get myFamilyTitle;

  /// No description provided for @myFamilyIntro.
  ///
  /// In ar, this message translates to:
  /// **'بيانات عائلتك واشتراكاتك ومدفوعاتك. للاطلاع فقط.'**
  String get myFamilyIntro;

  /// No description provided for @myMembersSection.
  ///
  /// In ar, this message translates to:
  /// **'أفراد العائلة'**
  String get myMembersSection;

  /// No description provided for @myStatementSection.
  ///
  /// In ar, this message translates to:
  /// **'كشف الحساب'**
  String get myStatementSection;

  /// No description provided for @issueCodeTitle.
  ///
  /// In ar, this message translates to:
  /// **'رمز دخول العائلة'**
  String get issueCodeTitle;

  /// No description provided for @issueCodeBody.
  ///
  /// In ar, this message translates to:
  /// **'أعطِ هذا الرمز لرب العائلة ليدخل ويرى بيانات عائلته فقط. إصدار رمز جديد يلغي القديم.'**
  String get issueCodeBody;

  /// No description provided for @issueCodeAction.
  ///
  /// In ar, this message translates to:
  /// **'إصدار رمز دخول'**
  String get issueCodeAction;

  /// No description provided for @issueCodeRegenerate.
  ///
  /// In ar, this message translates to:
  /// **'إصدار رمز جديد'**
  String get issueCodeRegenerate;

  /// No description provided for @issueCodeCopied.
  ///
  /// In ar, this message translates to:
  /// **'تم نسخ الرمز'**
  String get issueCodeCopied;

  /// No description provided for @dangerZoneSection.
  ///
  /// In ar, this message translates to:
  /// **'منطقة الخطر'**
  String get dangerZoneSection;

  /// No description provided for @purgeTitle.
  ///
  /// In ar, this message translates to:
  /// **'مسح البيانات المالية'**
  String get purgeTitle;

  /// No description provided for @purgeIntro.
  ///
  /// In ar, this message translates to:
  /// **'يحذف نهائياً كل الاستحقاقات والتحصيلات وحركات الخزينة وسجل العمليات. يُستعمل مرة واحدة لتصفير بيانات التجربة قبل بدء العمل الفعلي.'**
  String get purgeIntro;

  /// No description provided for @purgeKeeps.
  ///
  /// In ar, this message translates to:
  /// **'لا يُحذف: العائلات والأعضاء وإعدادات الجمعية وحسابات المستخدمين.'**
  String get purgeKeeps;

  /// No description provided for @purgeIrreversible.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن التراجع عن هذه العملية، ولا يبقى منها أثر في سجل العمليات.'**
  String get purgeIrreversible;

  /// No description provided for @purgeButton.
  ///
  /// In ar, this message translates to:
  /// **'مسح البيانات المالية'**
  String get purgeButton;

  /// No description provided for @purgeConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'مسح نهائي للبيانات المالية'**
  String get purgeConfirmTitle;

  /// No description provided for @purgeConfirmPrompt.
  ///
  /// In ar, this message translates to:
  /// **'للتأكيد، اكتب: {phrase}'**
  String purgeConfirmPrompt(String phrase);

  /// No description provided for @purgeConfirmField.
  ///
  /// In ar, this message translates to:
  /// **'عبارة التأكيد'**
  String get purgeConfirmField;

  /// No description provided for @purgeConfirmAction.
  ///
  /// In ar, this message translates to:
  /// **'مسح نهائي'**
  String get purgeConfirmAction;

  /// No description provided for @purgeDone.
  ///
  /// In ar, this message translates to:
  /// **'تم مسح {count} سجل، وأصبح الترقيم يبدأ من جديد'**
  String purgeDone(int count);

  /// No description provided for @purgeNothingToDo.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد بيانات مالية لمسحها'**
  String get purgeNothingToDo;

  /// No description provided for @purgeAllTitle.
  ///
  /// In ar, this message translates to:
  /// **'مسح بيانات العائلات والأعضاء'**
  String get purgeAllTitle;

  /// No description provided for @purgeAllIntro.
  ///
  /// In ar, this message translates to:
  /// **'يحذف نهائياً كل العائلات والأعضاء، ومعها كل البيانات المالية. تعود قاعدة البيانات فارغة تماماً كما لو أن النظام لم يُستعمل بعد.'**
  String get purgeAllIntro;

  /// No description provided for @purgeAllWhyFinancial.
  ///
  /// In ar, this message translates to:
  /// **'لماذا تُحذف البيانات المالية معها: كل استحقاق وكل إيصال مرتبط بعائلة، فلا يمكن حذف العائلة وإبقاء إيصالها.'**
  String get purgeAllWhyFinancial;

  /// No description provided for @purgeAllKeeps.
  ///
  /// In ar, this message translates to:
  /// **'لا يُحذف: إعدادات الجمعية وحسابات المستخدمين، فيبقى دخولك للتطبيق كما هو.'**
  String get purgeAllKeeps;

  /// No description provided for @purgeAllButton.
  ///
  /// In ar, this message translates to:
  /// **'مسح كل البيانات'**
  String get purgeAllButton;

  /// No description provided for @purgeAllConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'مسح نهائي لكل البيانات'**
  String get purgeAllConfirmTitle;

  /// No description provided for @purgeAllConfirmAction.
  ///
  /// In ar, this message translates to:
  /// **'مسح كل البيانات'**
  String get purgeAllConfirmAction;

  /// No description provided for @purgeAllNothingToDo.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد بيانات لمسحها'**
  String get purgeAllNothingToDo;

  /// No description provided for @usersIntro.
  ///
  /// In ar, this message translates to:
  /// **'اعتماد الحسابات الجديدة وإدارة الصلاحيات.'**
  String get usersIntro;

  /// No description provided for @pendingRequests.
  ///
  /// In ar, this message translates to:
  /// **'طلبات معلقة'**
  String get pendingRequests;

  /// No description provided for @allUsers.
  ///
  /// In ar, this message translates to:
  /// **'المستخدمون'**
  String get allUsers;

  /// No description provided for @approve.
  ///
  /// In ar, this message translates to:
  /// **'اعتماد'**
  String get approve;

  /// No description provided for @suspend.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف'**
  String get suspend;

  /// No description provided for @reactivate.
  ///
  /// In ar, this message translates to:
  /// **'إعادة التنشيط'**
  String get reactivate;

  /// No description provided for @changeRole.
  ///
  /// In ar, this message translates to:
  /// **'تغيير الدور'**
  String get changeRole;

  /// No description provided for @lastLogin.
  ///
  /// In ar, this message translates to:
  /// **'آخر دخول'**
  String get lastLogin;

  /// No description provided for @never.
  ///
  /// In ar, this message translates to:
  /// **'لم يدخل بعد'**
  String get never;

  /// No description provided for @noUsers.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد مستخدمون'**
  String get noUsers;

  /// No description provided for @userUpdated.
  ///
  /// In ar, this message translates to:
  /// **'تم تحديث الحساب'**
  String get userUpdated;

  /// No description provided for @cannotModifySelfNote.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكنك تعديل حسابك الشخصي'**
  String get cannotModifySelfNote;

  /// No description provided for @addFamily.
  ///
  /// In ar, this message translates to:
  /// **'إضافة عائلة'**
  String get addFamily;

  /// No description provided for @editFamily.
  ///
  /// In ar, this message translates to:
  /// **'تعديل العائلة'**
  String get editFamily;

  /// No description provided for @addSon.
  ///
  /// In ar, this message translates to:
  /// **'إضافة ابن'**
  String get addSon;

  /// No description provided for @removeSon.
  ///
  /// In ar, this message translates to:
  /// **'حذف الابن'**
  String get removeSon;

  /// No description provided for @sonNumber.
  ///
  /// In ar, this message translates to:
  /// **'الابن رقم {number}'**
  String sonNumber(int number);

  /// No description provided for @requiredField.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل مطلوب'**
  String get requiredField;

  /// No description provided for @familySaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ بيانات العائلة'**
  String get familySaved;

  /// No description provided for @membershipStatusField.
  ///
  /// In ar, this message translates to:
  /// **'حالة العضوية'**
  String get membershipStatusField;

  /// No description provided for @statusActive.
  ///
  /// In ar, this message translates to:
  /// **'نشط'**
  String get statusActive;

  /// No description provided for @statusSuspended.
  ///
  /// In ar, this message translates to:
  /// **'موقوف'**
  String get statusSuspended;

  /// No description provided for @statusDeceased.
  ///
  /// In ar, this message translates to:
  /// **'متوفى'**
  String get statusDeceased;

  /// No description provided for @discardChangesTitle.
  ///
  /// In ar, this message translates to:
  /// **'تجاهل التغييرات؟'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesBody.
  ///
  /// In ar, this message translates to:
  /// **'لديك تغييرات غير محفوظة، هل تريد الخروج بدون حفظ؟'**
  String get discardChangesBody;

  /// No description provided for @discard.
  ///
  /// In ar, this message translates to:
  /// **'تجاهل'**
  String get discard;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return LAr();
    case 'en':
      return LEn();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
