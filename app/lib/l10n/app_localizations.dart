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
  /// **'جمعية العدايل'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In ar, this message translates to:
  /// **'نظام إدارة المشتركين والاشتراكات والصندوق'**
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

  /// No description provided for @refreshData.
  ///
  /// In ar, this message translates to:
  /// **'تحديث البيانات'**
  String get refreshData;

  /// No description provided for @refreshedData.
  ///
  /// In ar, this message translates to:
  /// **'تم تحديث البيانات من قاعدة البيانات'**
  String get refreshedData;

  /// No description provided for @restartApp.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تشغيل التطبيق'**
  String get restartApp;

  /// No description provided for @restartAppBody.
  ///
  /// In ar, this message translates to:
  /// **'تعود إلى الشاشة الأولى ويضيع ما لم تحفظه.'**
  String get restartAppBody;

  /// No description provided for @restartConfirm.
  ///
  /// In ar, this message translates to:
  /// **'إعادة التشغيل'**
  String get restartConfirm;

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

  /// No description provided for @copied.
  ///
  /// In ar, this message translates to:
  /// **'تم النسخ'**
  String get copied;

  /// No description provided for @officialNeedsRegister.
  ///
  /// In ar, this message translates to:
  /// **'سجل العدايل فارغ — أضف المشتركين أولاً ليمكن اختيار المسؤولين منهم'**
  String get officialNeedsRegister;

  /// No description provided for @bankAccountSection.
  ///
  /// In ar, this message translates to:
  /// **'الحساب المصرفي للجمعية'**
  String get bankAccountSection;

  /// No description provided for @bankNameField.
  ///
  /// In ar, this message translates to:
  /// **'اسم المصرف'**
  String get bankNameField;

  /// No description provided for @previouslyUsed.
  ///
  /// In ar, this message translates to:
  /// **'المستعملة سابقاً'**
  String get previouslyUsed;

  /// No description provided for @bankAccountNoField.
  ///
  /// In ar, this message translates to:
  /// **'رقم الحساب'**
  String get bankAccountNoField;

  /// No description provided for @bankAccountNameField.
  ///
  /// In ar, this message translates to:
  /// **'اسم صاحب الحساب'**
  String get bankAccountNameField;

  /// No description provided for @bankAccountNotSetYet.
  ///
  /// In ar, this message translates to:
  /// **'لم تُسجَّل بيانات حساب الجمعية بعد، راجع إدارة الجمعية قبل التحويل'**
  String get bankAccountNotSetYet;

  /// Under the treasury figures in the عديل portal's المزيد sheet. A member seeing the association's money for the first time will reasonably wonder whether he is meant to act on it; the answer is no, and saying so is cheaper than letting him hunt for a button.
  ///
  /// In ar, this message translates to:
  /// **'أرقام الجمعية للاطلاع فقط — لا توجد أي عملية يمكنك إجراؤها من هنا'**
  String get treasuryReadOnlyNote;

  /// No description provided for @bankAccountNotConfigured.
  ///
  /// In ar, this message translates to:
  /// **'لم يُسجَّل الحساب المصرفي للجمعية بعد — أضفه من الإعدادات. يمكنك تسجيل الحوالة الآن، لكن الإيصال لن يذكر حساباً.'**
  String get bankAccountNotConfigured;

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

  /// No description provided for @errorSchemaMismatch.
  ///
  /// In ar, this message translates to:
  /// **'قاعدة البيانات لا تطابق هذا الإصدار من التطبيق. لن تنجح المحاولة مرة أخرى — يلزم تطبيق مخطط قاعدة البيانات.'**
  String get errorSchemaMismatch;

  /// No description provided for @errorProfileMissing.
  ///
  /// In ar, this message translates to:
  /// **'تم تسجيل الدخول، لكن لا يوجد سجل لهذا الحساب في قاعدة البيانات. لن تنجح المحاولة مرة أخرى — راجع إدارة الجمعية.'**
  String get errorProfileMissing;

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

  /// The screen, from the outside. It was «المجلس» — the word a Libyan association uses for where its people sit — but the screen holds TWO rooms now, and a name that describes one of them cannot also name the container. «المحادثات» is the container; «محادثة جماعية» is the room inside it.
  ///
  /// In ar, this message translates to:
  /// **'المحادثات'**
  String get navChat;

  /// The open room, as the segment that selects it. Named for what it IS — everyone together — rather than for the hall, so it pairs plainly with «مراسلة الإدارة» beside it: one conversation with everybody, one with the board.
  ///
  /// In ar, this message translates to:
  /// **'محادثة جماعية'**
  String get chatHall;

  /// The member's side of the private segment. He writes to الإدارة as an institution, never to a named officer, so whoever is on duty answers.
  ///
  /// In ar, this message translates to:
  /// **'مراسلة الإدارة'**
  String get chatToBoard;

  /// The same segment as chatToBoard, read from the board's side: the inbox of every member's private thread.
  ///
  /// In ar, this message translates to:
  /// **'الرسائل الخاصة'**
  String get chatInbox;

  /// No description provided for @chatPrivateEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا رسائل خاصة بعد — اكتب للإدارة وسيصلك الرد هنا'**
  String get chatPrivateEmpty;

  /// No description provided for @chatInboxEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا رسائل خاصة من المشتركين'**
  String get chatInboxEmpty;

  /// No description provided for @chatHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب رسالتك…'**
  String get chatHint;

  /// No description provided for @chatSend.
  ///
  /// In ar, this message translates to:
  /// **'إرسال'**
  String get chatSend;

  /// The button that opens the in-app emoji panel. «رموز» rather than «إيموجي»: the association writes Arabic and the word is already in use for symbols.
  ///
  /// In ar, this message translates to:
  /// **'رموز'**
  String get chatEmoji;

  /// No description provided for @chatUnreadCount.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{رسالة جديدة} =2{رسالتان جديدتان} few{{count} رسائل جديدة} other{{count} رسالة جديدة}}'**
  String chatUnreadCount(int count);

  /// No description provided for @chatUnreadMany.
  ///
  /// In ar, this message translates to:
  /// **'٩٩+'**
  String get chatUnreadMany;

  /// No description provided for @chatNewMessages.
  ///
  /// In ar, this message translates to:
  /// **'رسائل جديدة'**
  String get chatNewMessages;

  /// No description provided for @emojiFaces.
  ///
  /// In ar, this message translates to:
  /// **'وجوه'**
  String get emojiFaces;

  /// No description provided for @emojiHands.
  ///
  /// In ar, this message translates to:
  /// **'إيماءات ودعاء'**
  String get emojiHands;

  /// No description provided for @emojiHearts.
  ///
  /// In ar, this message translates to:
  /// **'قلوب'**
  String get emojiHearts;

  /// No description provided for @emojiOccasions.
  ///
  /// In ar, this message translates to:
  /// **'مناسبات'**
  String get emojiOccasions;

  /// No description provided for @emojiBackspace.
  ///
  /// In ar, this message translates to:
  /// **'حذف حرف'**
  String get emojiBackspace;

  /// No description provided for @chatEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا رسائل بعد — كن أول من يتحدث'**
  String get chatEmpty;

  /// The inbox stamp for a conversation whose last message was yesterday. Today shows the clock instead, and anything older shows the date — the rule every messaging app on these handsets already uses.
  ///
  /// In ar, this message translates to:
  /// **'أمس'**
  String get chatYesterday;

  /// The tombstone left where a message was. The row survives so a gap in a conversation is visible rather than silent; the words themselves are erased in the database.
  ///
  /// In ar, this message translates to:
  /// **'حُذفت الرسالة'**
  String get chatDeleted;

  /// Badge beside the name of anyone who spoke as staff. An announcement about a meeting reads differently from a member's opinion of it.
  ///
  /// In ar, this message translates to:
  /// **'الإدارة'**
  String get chatFromBoard;

  /// No description provided for @chatDeleteTitle.
  ///
  /// In ar, this message translates to:
  /// **'حذف الرسالة؟'**
  String get chatDeleteTitle;

  /// No description provided for @chatDeleteBody.
  ///
  /// In ar, this message translates to:
  /// **'ستختفي الكلمات نهائياً ويبقى مكانها ظاهراً في المحادثة.'**
  String get chatDeleteBody;

  /// No description provided for @navHome.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get navHome;

  /// No description provided for @navReceivables.
  ///
  /// In ar, this message translates to:
  /// **'الاستحقاقات'**
  String get navReceivables;

  /// Was التحصيل والسداد. Renamed because the screen is becoming the home of BOTH directions of money — collections in, and disbursements out of the treasury.
  ///
  /// In ar, this message translates to:
  /// **'العمليات'**
  String get navPayments;

  /// No description provided for @navPaymentsShort.
  ///
  /// In ar, this message translates to:
  /// **'العمليات'**
  String get navPaymentsShort;

  /// No description provided for @opsCollections.
  ///
  /// In ar, this message translates to:
  /// **'التحصيل'**
  String get opsCollections;

  /// No description provided for @opsDisbursements.
  ///
  /// In ar, this message translates to:
  /// **'الصرف'**
  String get opsDisbursements;

  /// No description provided for @opsDisbursementsSoon.
  ///
  /// In ar, this message translates to:
  /// **'نظام الصرف قيد الإنشاء — لم تُحدَّد بعد بيانات إيصال الصرف'**
  String get opsDisbursementsSoon;

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

  /// Runs on ONE phone and answers the question that otherwise needs two: will a call connect to somebody on a different network. It gathers ICE candidates and reports which kinds came back.
  ///
  /// In ar, this message translates to:
  /// **'فحص مسار الاتصال'**
  String get iceCheck;

  /// No description provided for @iceRunning.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الفحص… قد يستغرق ١٢ ثانية'**
  String get iceRunning;

  /// No description provided for @iceHost.
  ///
  /// In ar, this message translates to:
  /// **'الشبكة المحلية'**
  String get iceHost;

  /// No description provided for @iceStun.
  ///
  /// In ar, this message translates to:
  /// **'عنوانك العام (STUN)'**
  String get iceStun;

  /// No description provided for @iceRelay.
  ///
  /// In ar, this message translates to:
  /// **'خادم التحويل (TURN)'**
  String get iceRelay;

  /// No description provided for @iceGood.
  ///
  /// In ar, this message translates to:
  /// **'المكالمات تعمل بين شبكتين مختلفتين'**
  String get iceGood;

  /// No relay candidate came back. Two phones on different mobile networks will not connect. The fix is association_settings.ice_servers — a paid TURN — not a change to the app.
  ///
  /// In ar, this message translates to:
  /// **'المكالمات ستعمل على نفس الشبكة فقط'**
  String get iceWifiOnly;

  /// No description provided for @iceNone.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد اتصال بالشبكة'**
  String get iceNone;

  /// No description provided for @iceRelayNote.
  ///
  /// In ar, this message translates to:
  /// **'إن لم يظهر خادم التحويل، الإصلاح في إعدادات قاعدة البيانات لا في التطبيق'**
  String get iceRelayNote;

  /// No description provided for @callTitle.
  ///
  /// In ar, this message translates to:
  /// **'مكالمة صوتية'**
  String get callTitle;

  /// No description provided for @callStart.
  ///
  /// In ar, this message translates to:
  /// **'اتصال صوتي'**
  String get callStart;

  /// No description provided for @callIncoming.
  ///
  /// In ar, this message translates to:
  /// **'{name} يتصل'**
  String callIncoming(String name);

  /// No description provided for @callOngoing.
  ///
  /// In ar, this message translates to:
  /// **'مكالمة جارية — {name}'**
  String callOngoing(String name);

  /// No description provided for @callAnswer.
  ///
  /// In ar, this message translates to:
  /// **'ردّ'**
  String get callAnswer;

  /// No description provided for @callDecline.
  ///
  /// In ar, this message translates to:
  /// **'رفض'**
  String get callDecline;

  /// No description provided for @callHangUp.
  ///
  /// In ar, this message translates to:
  /// **'إنهاء'**
  String get callHangUp;

  /// No description provided for @callConnecting.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الاتصال…'**
  String get callConnecting;

  /// No description provided for @callRinging.
  ///
  /// In ar, this message translates to:
  /// **'يرنّ…'**
  String get callRinging;

  /// No description provided for @callTalking.
  ///
  /// In ar, this message translates to:
  /// **'متصل'**
  String get callTalking;

  /// No description provided for @callEnded.
  ///
  /// In ar, this message translates to:
  /// **'انتهت المكالمة'**
  String get callEnded;

  /// Shown when the media path never came up. Almost always TURN: the two handsets are behind carrier NAT and no relay answered. The fix is association_settings.ice_servers, not the app — see PATCH_20260821d.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الاتصال'**
  String get callFailed;

  /// No description provided for @callMute.
  ///
  /// In ar, this message translates to:
  /// **'كتم'**
  String get callMute;

  /// No description provided for @callUnmute.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الكتم'**
  String get callUnmute;

  /// No description provided for @callSpeaker.
  ///
  /// In ar, this message translates to:
  /// **'مكبر الصوت'**
  String get callSpeaker;

  /// No description provided for @callMicDenied.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن الاتصال بدون إذن الميكروفون'**
  String get callMicDenied;

  /// No description provided for @noSearchResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج لبحثك'**
  String get noSearchResults;

  /// The dues search box. It names the four things it matches, because a bare «بحث» leaves the user guessing whether a code or a month will work — and this box exists precisely because they do.
  ///
  /// In ar, this message translates to:
  /// **'ابحث باسم أو كود أو شهر أو حالة'**
  String get receivableSearchHint;

  /// Shown only while a search narrows the list. ⚠ The three totals above it do NOT change — they are the server's figures for the whole period — so without this line a filtered list under an unfiltered total reads as a fault.
  ///
  /// In ar, this message translates to:
  /// **'يعرض {shown} من {total}'**
  String receivableSearchCount(int shown, int total);

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
  /// **'ملخص المشترك'**
  String get familySummary;

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

  /// No description provided for @personalData.
  ///
  /// In ar, this message translates to:
  /// **'البيانات الشخصية'**
  String get personalData;

  /// No description provided for @totalDue.
  ///
  /// In ar, this message translates to:
  /// **'المستحق'**
  String get totalDue;

  /// No description provided for @phone.
  ///
  /// In ar, this message translates to:
  /// **'الهاتف'**
  String get phone;

  /// No description provided for @dateOfBirth.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الميلاد'**
  String get dateOfBirth;

  /// No description provided for @registeredAt.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ التسجيل'**
  String get registeredAt;

  /// No description provided for @age.
  ///
  /// In ar, this message translates to:
  /// **'العمر'**
  String get age;

  /// No description provided for @notProvided.
  ///
  /// In ar, this message translates to:
  /// **'—'**
  String get notProvided;

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
  /// **'اختر المشترك'**
  String get selectFamily;

  /// No description provided for @selectFamilyToView.
  ///
  /// In ar, this message translates to:
  /// **'اختر مشتركاً لعرض كشف الحساب'**
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

  /// No description provided for @notAssigned.
  ///
  /// In ar, this message translates to:
  /// **'غير محدد'**
  String get notAssigned;

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

  /// No description provided for @receiverNotConfigured.
  ///
  /// In ar, this message translates to:
  /// **'لم تُسجَّل أسماء المسؤولين بعد — أضفها من الإعدادات'**
  String get receiverNotConfigured;

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
  /// **'هذا المشترك لا توجد عليه مديونية، لذلك لا يمكن تسجيل سداد.'**
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

  /// No description provided for @registerDisbursement.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل صرف'**
  String get registerDisbursement;

  /// No description provided for @confirmDisbursement.
  ///
  /// In ar, this message translates to:
  /// **'اعتماد الصرف'**
  String get confirmDisbursement;

  /// One of the two shapes a voucher takes. The عديل IS the heading, so this kind asks WHO and never which category.
  ///
  /// In ar, this message translates to:
  /// **'صرف لمشترك'**
  String get kindMember;

  /// The other shape: money spent on an occasion for everybody. Asks WHAT FOR, and records no payee at all — nobody receives فطور رمضان the way a member receives aid.
  ///
  /// In ar, this message translates to:
  /// **'صرف جماعي'**
  String get kindCollective;

  /// No description provided for @expenseCategory.
  ///
  /// In ar, this message translates to:
  /// **'بند الصرف'**
  String get expenseCategory;

  /// No description provided for @categoryRequired.
  ///
  /// In ar, this message translates to:
  /// **'اختر بند الصرف'**
  String get categoryRequired;

  /// No description provided for @payee.
  ///
  /// In ar, this message translates to:
  /// **'المستفيد'**
  String get payee;

  /// No description provided for @payeeRequired.
  ///
  /// In ar, this message translates to:
  /// **'اختر المشترك المستفيد'**
  String get payeeRequired;

  /// Who RECEIVED a disbursement, in the aid ledger's detail block. ⚠ The voucher FORM calls the same person «المستفيد» (see `payee`) — two words for one role, kept only because the association asked for «المستلم» here by name. Unifying them is one value change in this file. Distinct from handedBy («المُسلِّم»), which is the officer who handed the money over; those two genuinely are different people and sit on adjacent lines.
  ///
  /// In ar, this message translates to:
  /// **'المستلم'**
  String get recipient;

  /// No description provided for @handedBy.
  ///
  /// In ar, this message translates to:
  /// **'المُسلِّم'**
  String get handedBy;

  /// No description provided for @disbursementDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الصرف'**
  String get disbursementDate;

  /// No description provided for @disbursementDateAuto.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ يُسجَّل تلقائياً بساعة الجمعية'**
  String get disbursementDateAuto;

  /// No description provided for @change.
  ///
  /// In ar, this message translates to:
  /// **'تغيير'**
  String get change;

  /// No description provided for @voucherNo.
  ///
  /// In ar, this message translates to:
  /// **'رقم الإيصال'**
  String get voucherNo;

  /// No description provided for @noDisbursements.
  ///
  /// In ar, this message translates to:
  /// **'لم يُسجَّل أي صرف بعد'**
  String get noDisbursements;

  /// No description provided for @totalDisbursed.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المصروف'**
  String get totalDisbursed;

  /// No description provided for @expenseByCategory.
  ///
  /// In ar, this message translates to:
  /// **'المصروف حسب البند'**
  String get expenseByCategory;

  /// Shown under the amount when a disbursement would overdraw the treasury. Mirrors rule 7's cap on the collection side, in the other direction: the association cannot pay out money it does not hold.
  ///
  /// In ar, this message translates to:
  /// **'رصيد الصندوق {amount} فقط'**
  String overTreasuryBalance(String amount);

  /// The balance is restated with the voucher number so an admin who has just emptied the fund learns it now rather than on the next attempt.
  ///
  /// In ar, this message translates to:
  /// **'تم تسجيل الصرف {voucher} — رصيد الصندوق الآن {balance}'**
  String disbursementSaved(String voucher, String balance);

  /// No description provided for @cancelDisbursement.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الصرف'**
  String get cancelDisbursement;

  /// No description provided for @cancelDisbursementWarning.
  ///
  /// In ar, this message translates to:
  /// **'سيتم إلغاء إيصال الصرف وإعادة قيمته إلى رصيد الجمعية، مع بقاء السجل التاريخي.'**
  String get cancelDisbursementWarning;

  /// No description provided for @disbursementCancelled.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء الصرف وأُعيدت قيمته إلى الصندوق'**
  String get disbursementCancelled;

  /// Staff heading, third person: the association looking at one man's aid history.
  ///
  /// In ar, this message translates to:
  /// **'مصروفات للمشترك'**
  String get aidTitle;

  /// The same page in the member's own voice, inside his portal. The association's own wording.
  ///
  /// In ar, this message translates to:
  /// **'أسلافي'**
  String get myAidTitle;

  /// No description provided for @aidSearchHint.
  ///
  /// In ar, this message translates to:
  /// **'بحث'**
  String get aidSearchHint;

  /// What the association gave every OTHER member, in a member’s portal, beside «أسلافي». The association chose full transparency — «كل شيء بالأسماء» — and the widening is a policy on the table, not a filter in the app: drop read_all_disbursements_adeel and this screen empties itself.
  ///
  /// In ar, this message translates to:
  /// **'أسلاف للغير'**
  String get aidOthersTitle;

  /// No description provided for @aidOthersEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا صرف جماعي بعد'**
  String get aidOthersEmpty;

  /// No description provided for @aidOthersRecipients.
  ///
  /// In ar, this message translates to:
  /// **'حسب الوجه'**
  String get aidOthersRecipients;

  /// No description provided for @aidOthersAll.
  ///
  /// In ar, this message translates to:
  /// **'كل السندات'**
  String get aidOthersAll;

  /// The heading of the membership-value screen. «الجدوى» and not «الربح»: a mutual fund is not an investment, and the word chosen here is the one the whole screen depends on.
  ///
  /// In ar, this message translates to:
  /// **'الجدوى'**
  String get valueTitle;

  /// No description provided for @valuePaid.
  ///
  /// In ar, this message translates to:
  /// **'دفعتَ'**
  String get valuePaid;

  /// No description provided for @valueReceived.
  ///
  /// In ar, this message translates to:
  /// **'استلمتَ'**
  String get valueReceived;

  /// Shown when a member has received MORE than he paid. States the fact and nothing else — no «ربح», which would make the next man expect one.
  ///
  /// In ar, this message translates to:
  /// **'أعطتك الجمعية أكثر مما دفعتَ بـ'**
  String get valueAhead;

  /// Shown when he has paid MORE than he received, and the most important string in the app. It is NOT a loss and NOT a debt the association owes him: in a mutual fund the surplus of the men nothing happened to is exactly what covers the man something happened to. Calling it anything else would teach members to stop paying once they are «ahead».
  ///
  /// In ar, this message translates to:
  /// **'فائض تكافلك'**
  String get valueSurplus;

  /// No description provided for @valueEven.
  ///
  /// In ar, this message translates to:
  /// **'دفعتَ واستلمتَ سواءً'**
  String get valueEven;

  /// No description provided for @valueFund.
  ///
  /// In ar, this message translates to:
  /// **'الجمعية'**
  String get valueFund;

  /// No description provided for @valueMonths.
  ///
  /// In ar, this message translates to:
  /// **'حركتك خلال 12 شهراً'**
  String get valueMonths;

  /// No description provided for @valueBackToMembers.
  ///
  /// In ar, this message translates to:
  /// **'من كل 100 محصَّلة، صُرف {rate} على المشتركين'**
  String valueBackToMembers(String rate);

  /// No description provided for @valueHelped.
  ///
  /// In ar, this message translates to:
  /// **'وقفت خلف {helped} من {members} مشتركين'**
  String valueHelped(int helped, int members);

  /// No description provided for @valueLargest.
  ///
  /// In ar, this message translates to:
  /// **'أكبر ما صُرف لمشترك واحد'**
  String get valueLargest;

  /// No description provided for @aidColDate.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get aidColDate;

  /// The ledger's leading column — first in the children list, which in RTL puts it at the FAR RIGHT. «#» rather than «تسلسل»: the symbol is read as 'number' in an Arabic table without translation, and the word was five letters wide over a column of one to three digits, so it was sizing the column for its own heading and taking that width from البند. It numbers the voucher in the man's FULL history, oldest as 1, so the number stays attached to the voucher while a search or a period narrows the list — the same rule the الإجمالي column follows. Numbering the visible rows instead would put a «1» beside a running total of 600.
  ///
  /// In ar, this message translates to:
  /// **'#'**
  String get aidColSerial;

  /// No description provided for @aidColCategory.
  ///
  /// In ar, this message translates to:
  /// **'البند'**
  String get aidColCategory;

  /// No description provided for @aidColAmount.
  ///
  /// In ar, this message translates to:
  /// **'القيمة'**
  String get aidColAmount;

  /// No description provided for @aidColRunning.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get aidColRunning;

  /// No description provided for @aidNoMatch.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد سند يطابق بحثك'**
  String get aidNoMatch;

  /// Shown above the ledger while a search filters it, so a reader knows the running-total column still belongs to the FULL history and not to what is on screen.
  ///
  /// In ar, this message translates to:
  /// **'{shown} من {total}'**
  String aidShowing(int shown, int total);

  /// No description provided for @disbursementNoteHint.
  ///
  /// In ar, this message translates to:
  /// **'اسم المولود، أو صاحب المناسبة'**
  String get disbursementNoteHint;

  /// No description provided for @disbursementNoteHelp.
  ///
  /// In ar, this message translates to:
  /// **'تظهر هذه الملاحظة في كشف المشترك بجانب البند، فيُعرف لماذا صُرف له.'**
  String get disbursementNoteHelp;

  /// No description provided for @aidNoteLabel.
  ///
  /// In ar, this message translates to:
  /// **'الملاحظات'**
  String get aidNoteLabel;

  /// Opens the aid ledger from a member's page. «سجل الأسلاف» is the association's own word for it, given by name. ⚠ Note for whoever reads this next: the record is of money the association GAVE and never deducts — a voucher writes no receivable, no payment and no allocation, and api_adeel_statement cannot reach it. The word «سلف» carries a sense of an advance to be repaid; nothing in the schema does. The label is the association's to choose, but it does not describe a debt and no code should ever start treating it as one.
  ///
  /// In ar, this message translates to:
  /// **'سجل الأسلاف'**
  String get openAid;

  /// No description provided for @aidTotal.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي ما صُرف له'**
  String get aidTotal;

  /// No description provided for @aidCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد السندات'**
  String get aidCount;

  /// No description provided for @aidByYear.
  ///
  /// In ar, this message translates to:
  /// **'حسب السنة'**
  String get aidByYear;

  /// No description provided for @aidVouchers.
  ///
  /// In ar, this message translates to:
  /// **'السندات'**
  String get aidVouchers;

  /// No description provided for @aidPanelTitle.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get aidPanelTitle;

  /// No description provided for @aidVoucherCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} سند'**
  String aidVoucherCount(int count);

  /// No description provided for @noAid.
  ///
  /// In ar, this message translates to:
  /// **'لم يُصرف له شيء من الجمعية بعد'**
  String get noAid;

  /// No description provided for @noMyAid.
  ///
  /// In ar, this message translates to:
  /// **'لم يُصرف لك شيء من الجمعية بعد'**
  String get noMyAid;

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
  /// **'المحصل بتحويل'**
  String get collectedTransfer;

  /// Treasury tile: every subscriber's unpaid balance, summed. Distinct from outstandingTotal (المديونية القائمة), which the admin receivables and reports screens use — the treasury asks a shorter question and the tile is narrow.
  ///
  /// In ar, this message translates to:
  /// **'المستحقات'**
  String get dueFromMembers;

  /// No description provided for @totalOutstanding.
  ///
  /// In ar, this message translates to:
  /// **'اشتراكات مستحقة'**
  String get totalOutstanding;

  /// Cash the association holds but has not earned: prepayments not yet settled against a billed month. It is subtracted from associationBalance, and register_disbursement refuses to spend past the same figure.
  ///
  /// In ar, this message translates to:
  /// **'عهد المشتركين'**
  String get heldForMembers;

  /// No description provided for @adeelCredit.
  ///
  /// In ar, this message translates to:
  /// **'العهدة'**
  String get adeelCredit;

  /// The treasury total, renamed. It is the LAST tile because it is the conclusion of the three above it — cash in, transfers in, still owed — rather than a fourth independent fact. `collectedThisYear` was removed with it: in an association's first year that tile showed the same number as this one.
  ///
  /// In ar, this message translates to:
  /// **'رصيد الجمعية'**
  String get associationBalance;

  /// How many vouchers made out to this subscriber are folded into his treasury card. Shown in red beside the receipt count, so a closed card says there is an outgoing side inside it. A COUNT and never an amount: two money figures side by side on one row invite the reader to subtract, and aid is never netted against what a member paid.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{سند صرف واحد} =2{سندا صرف} few{{count} سندات صرف} other{{count} سند صرف}}'**
  String voucherCount(int count);

  /// How many live receipts are folded into one subscriber's row on the treasury screen. It is what tells a reader the row opens at all.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{لا إيصالات} =1{إيصال واحد} =2{إيصالان} few{{count} إيصالات} other{{count} إيصالاً}}'**
  String receiptCount(int count);

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
  /// **'سيتم إنشاء استحقاق لكل مشترك نشط لهذا الشهر. لا يمكن إنشاء استحقاق مكرر لنفس المشترك والشهر.'**
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

  /// No description provided for @statAdeels.
  ///
  /// In ar, this message translates to:
  /// **'عدد المشتركين'**
  String get statAdeels;

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

  /// No description provided for @subActive.
  ///
  /// In ar, this message translates to:
  /// **'{count} نشط'**
  String subActive(int count);

  /// No description provided for @subIndebtedAdeels.
  ///
  /// In ar, this message translates to:
  /// **'{count} مشترك مدين'**
  String subIndebtedAdeels(int count);

  /// No description provided for @subCashTransfer.
  ///
  /// In ar, this message translates to:
  /// **'نقدي {cash} • تحويل {transfer}'**
  String subCashTransfer(String cash, String transfer);

  /// No description provided for @heldOfWhich.
  ///
  /// In ar, this message translates to:
  /// **'منها عهد للمشتركين {amount}'**
  String heldOfWhich(String amount);

  /// No description provided for @topDebtors.
  ///
  /// In ar, this message translates to:
  /// **'أعلى المديونيات'**
  String get topDebtors;

  /// No description provided for @noDebtsNow.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد مديونيات حالية'**
  String get noDebtsNow;

  /// No description provided for @closeMonth.
  ///
  /// In ar, this message translates to:
  /// **'إقفال شهر'**
  String get closeMonth;

  /// No description provided for @selectPeriodTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر الشهر'**
  String get selectPeriodTitle;

  /// No description provided for @noPeriodsToClose.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد أشهر قابلة للإقفال بعد.'**
  String get noPeriodsToClose;

  /// No description provided for @periodClosedBadge.
  ///
  /// In ar, this message translates to:
  /// **'مُقفل'**
  String get periodClosedBadge;

  /// No description provided for @periodClosedNote.
  ///
  /// In ar, this message translates to:
  /// **'أُقفل من قبل'**
  String get periodClosedNote;

  /// No description provided for @periodBlockedNote.
  ///
  /// In ar, this message translates to:
  /// **'أقفل ما قبله أولاً'**
  String get periodBlockedNote;

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

  /// No description provided for @settingsWarning.
  ///
  /// In ar, this message translates to:
  /// **'قاعدة محاسبية: تعديل قيمة الاشتراك هنا لا يغيّر أي استحقاق سبق إنشاؤه.'**
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

  /// No description provided for @memberFeeField.
  ///
  /// In ar, this message translates to:
  /// **'اشتراك العضو الشهري'**
  String get memberFeeField;

  /// Heads each month-exception row in Settings, directly under the monthly fee it is the exception TO. One word, because the row that follows it — a month and an amount — is the sentence.
  ///
  /// In ar, this message translates to:
  /// **'ماعدا'**
  String get feeExceptionLabel;

  /// No description provided for @backAction.
  ///
  /// In ar, this message translates to:
  /// **'رجوع'**
  String get backAction;

  /// No description provided for @feeExceptionAdd.
  ///
  /// In ar, this message translates to:
  /// **'إضافة شهر مستثنى'**
  String get feeExceptionAdd;

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

  /// Shown instead of sending a value Postgres cannot cast to numeric. Naming the field is the whole point: the server answers 22P02, which has no wording at all, so the admin was told 'something went wrong' about a box he may not have touched.
  ///
  /// In ar, this message translates to:
  /// **'«{field}» يجب أن يكون رقماً، أو اتركه فارغاً لإبقائه كما هو'**
  String invalidNumberField(String field);

  /// Same as invalidNumberField, for a date cast.
  ///
  /// In ar, this message translates to:
  /// **'«{field}» يجب أن يكون تاريخاً بالصيغة YYYY-MM-DD، أو اتركه فارغاً لإبقائه كما هو'**
  String invalidDateField(String field);

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
  /// **'لديك رمز اشتراك؟'**
  String get familyCodeTitle;

  /// No description provided for @familyCodeBody.
  ///
  /// In ar, this message translates to:
  /// **'إن أعطاك مسؤول الجمعية رمز دخول خاصاً بك، اكتبه هنا لترى بيانات اشتراكك مباشرة.'**
  String get familyCodeBody;

  /// No description provided for @familyCodeField.
  ///
  /// In ar, this message translates to:
  /// **'رمز الاشتراك'**
  String get familyCodeField;

  /// No description provided for @familyCodeHint.
  ///
  /// In ar, this message translates to:
  /// **'XXXX-XXXX-XXXX'**
  String get familyCodeHint;

  /// No description provided for @familyCodeAction.
  ///
  /// In ar, this message translates to:
  /// **'دخول برمز الاشتراك'**
  String get familyCodeAction;

  /// No description provided for @myFamilyTitle.
  ///
  /// In ar, this message translates to:
  /// **'اشتراكي'**
  String get myFamilyTitle;

  /// No description provided for @myFamilyIntro.
  ///
  /// In ar, this message translates to:
  /// **'بيانات اشتراكك ومدفوعاتك. للاطلاع فقط.'**
  String get myFamilyIntro;

  /// No description provided for @myStatementSection.
  ///
  /// In ar, this message translates to:
  /// **'كشف الحساب'**
  String get myStatementSection;

  /// No description provided for @statementSearchHint.
  ///
  /// In ar, this message translates to:
  /// **'بحث'**
  String get statementSearchHint;

  /// No description provided for @clearSearch.
  ///
  /// In ar, this message translates to:
  /// **'مسح البحث'**
  String get clearSearch;

  /// No description provided for @statementShowing.
  ///
  /// In ar, this message translates to:
  /// **'عرض {shown} من {total} حركة'**
  String statementShowing(int shown, int total);

  /// No description provided for @statementShowMore.
  ///
  /// In ar, this message translates to:
  /// **'عرض {count} أخرى'**
  String statementShowMore(int count);

  /// No description provided for @statementShowAll.
  ///
  /// In ar, this message translates to:
  /// **'عرض الكل'**
  String get statementShowAll;

  /// No description provided for @ledgerParticulars.
  ///
  /// In ar, this message translates to:
  /// **'البيان'**
  String get ledgerParticulars;

  /// No description provided for @ledgerDebit.
  ///
  /// In ar, this message translates to:
  /// **'مدين'**
  String get ledgerDebit;

  /// No description provided for @ledgerCredit.
  ///
  /// In ar, this message translates to:
  /// **'دائن'**
  String get ledgerCredit;

  /// No description provided for @ledgerDebitCredit.
  ///
  /// In ar, this message translates to:
  /// **'مدين / دائن'**
  String get ledgerDebitCredit;

  /// No description provided for @ledgerBalance.
  ///
  /// In ar, this message translates to:
  /// **'الرصيد'**
  String get ledgerBalance;

  /// No description provided for @ledgerTotals.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get ledgerTotals;

  /// No description provided for @balanceDueLabel.
  ///
  /// In ar, this message translates to:
  /// **'الرصيد المستحق عليك'**
  String get balanceDueLabel;

  /// No description provided for @balanceSettledLabel.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد رصيد مستحق'**
  String get balanceSettledLabel;

  /// No description provided for @issueCodeTitle.
  ///
  /// In ar, this message translates to:
  /// **'رمز دخول المشترك'**
  String get issueCodeTitle;

  /// No description provided for @issueCodeBody.
  ///
  /// In ar, this message translates to:
  /// **'أعطِ هذا الرمز للمشترك ليدخل ويرى بياناته فقط. إصدار رمز جديد يلغي القديم.'**
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
  /// **'لا يُحذف: المشتركون وإعدادات الجمعية وحسابات المستخدمين.'**
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
  /// **'مسح بيانات المشتركين'**
  String get purgeAllTitle;

  /// No description provided for @purgeAllIntro.
  ///
  /// In ar, this message translates to:
  /// **'يحذف نهائياً كل المشتركين، ومعهم كل البيانات المالية. تعود قاعدة البيانات فارغة تماماً كما لو أن النظام لم يُستعمل بعد.'**
  String get purgeAllIntro;

  /// No description provided for @purgeAllWhyFinancial.
  ///
  /// In ar, this message translates to:
  /// **'لماذا تُحذف البيانات المالية معهم: كل استحقاق وكل إيصال مرتبط بمشترك، فلا يمكن حذف المشترك وإبقاء إيصاله.'**
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

  /// No description provided for @requiredField.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل مطلوب'**
  String get requiredField;

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

  /// No description provided for @delete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @navRegister.
  ///
  /// In ar, this message translates to:
  /// **'المشتركين'**
  String get navRegister;

  /// No description provided for @addAdeel.
  ///
  /// In ar, this message translates to:
  /// **'إضافة مشترك'**
  String get addAdeel;

  /// No description provided for @editAdeel.
  ///
  /// In ar, this message translates to:
  /// **'تعديل مشترك'**
  String get editAdeel;

  /// No description provided for @noAdeels.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد مشتركون مسجلون بعد'**
  String get noAdeels;

  /// No description provided for @registerIntro.
  ///
  /// In ar, this message translates to:
  /// **'كل مشترك يُسجَّل باسمه ويُحاسَب باشتراكه.'**
  String get registerIntro;

  /// No description provided for @adeelSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ بيانات المشترك'**
  String get adeelSaved;

  /// No description provided for @adeelDeleted.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف المشترك'**
  String get adeelDeleted;

  /// No description provided for @deleteAdeelTitle.
  ///
  /// In ar, this message translates to:
  /// **'حذف المشترك؟'**
  String get deleteAdeelTitle;

  /// No description provided for @deleteAdeelBody.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن التراجع. المشترك الذي له سجل مالي لا يُحذف — غيّر حالته إلى موقوف بدلاً من ذلك.'**
  String get deleteAdeelBody;

  /// No description provided for @monthlyFeeLabel.
  ///
  /// In ar, this message translates to:
  /// **'الاشتراك الشهري'**
  String get monthlyFeeLabel;

  /// No description provided for @openPeriodsBadge.
  ///
  /// In ar, this message translates to:
  /// **'{count} فترة مفتوحة'**
  String openPeriodsBadge(int count);

  /// No description provided for @issuedLabel.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المستحق'**
  String get issuedLabel;

  /// No description provided for @myBalanceNow.
  ///
  /// In ar, this message translates to:
  /// **'المستحق عليك'**
  String get myBalanceNow;

  /// The portal's own word for what the association has charged him, with myPaidTotal and myRemainingTotal beside it. The staff screens keep issuedTotal — the accounting term, and the name of a whole admin screen. A member is not reading an accounts ledger; he is reading what he was asked to pay, what he paid, and what is left.
  ///
  /// In ar, this message translates to:
  /// **'الاشتراكات'**
  String get myIssuedTotal;

  /// No description provided for @myPaidTotal.
  ///
  /// In ar, this message translates to:
  /// **'المسدد'**
  String get myPaidTotal;

  /// No description provided for @myRemainingTotal.
  ///
  /// In ar, this message translates to:
  /// **'المتبقي'**
  String get myRemainingTotal;

  /// Heads the hero when netBalance is NEGATIVE — the association is holding prepaid money for him. The LABEL changes with the sign, not only the colour, so red-green is never the only thing carrying the meaning.
  ///
  /// In ar, this message translates to:
  /// **'عهدتك لدى الجمعية'**
  String get myWalletTitle;

  /// No description provided for @myWalletBody.
  ///
  /// In ar, this message translates to:
  /// **'مبلغ مدفوع مقدماً، يُخصم تلقائياً من اشتراك كل شهر جديد'**
  String get myWalletBody;

  /// Shown in the payment sheet the moment the typed amount passes what the member owes. Overpaying is allowed now; this is what stops a treasurer who typed 5000 for 500 finding out from the receipt.
  ///
  /// In ar, this message translates to:
  /// **'أكثر من المستحق بـ {amount} — تُضاف إلى رصيده وتُخصم من الأشهر القادمة'**
  String creditNotice(String amount);

  /// Shown to an عديل whose access code was redeemed on a different handset. my_adeel_id() already refuses him; this is the sentence that keeps an empty screen from reading as a broken app.
  ///
  /// In ar, this message translates to:
  /// **'هذا الاشتراك مرتبط بجهاز آخر'**
  String get deviceLockedTitle;

  /// No description provided for @deviceLockedBody.
  ///
  /// In ar, this message translates to:
  /// **'رمز دخولك مفتوح على جهاز واحد فقط، وهذا ليس هو. إن كان جهازك قد تغيّر أو ضاع، راجع إدارة الجمعية لإصدار رمز جديد.'**
  String get deviceLockedBody;

  /// No description provided for @portalDetailsHint.
  ///
  /// In ar, this message translates to:
  /// **'اسمك ورقمك وحالتك وقيمة اشتراكك الشهري'**
  String get portalDetailsHint;

  /// No description provided for @portalBankHint.
  ///
  /// In ar, this message translates to:
  /// **'إلى أين تُرسل الحوالة، ورقم الحساب لنسخه'**
  String get portalBankHint;

  /// No description provided for @portalOfficialsHint.
  ///
  /// In ar, this message translates to:
  /// **'بمن تتصل، وأرقام هواتفهم'**
  String get portalOfficialsHint;

  /// The one-line summary on the الصندوق menu card. It says «للاطلاع فقط» on the card itself, not only inside: a member should know before he opens it that there is nothing here for him to act on.
  ///
  /// In ar, this message translates to:
  /// **'أين يقف مال الجمعية — للاطلاع فقط'**
  String get portalTreasuryHint;

  /// Heading of the collapsed panel at the foot of the عديل portal. It holds what is left after the name, code and status moved up into the balance card: phone, join date, monthly fee.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل اشتراكي'**
  String get myDetailsTitle;

  /// No description provided for @ofTotal.
  ///
  /// In ar, this message translates to:
  /// **'من {amount}'**
  String ofTotal(String amount);

  /// No description provided for @settledUpTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا مستحقات عليك'**
  String get settledUpTitle;

  /// No description provided for @settledUpBody.
  ///
  /// In ar, this message translates to:
  /// **'كل اشتراكاتك مسدَّدة. شكراً لالتزامك.'**
  String get settledUpBody;

  /// No description provided for @openMonthsCount.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =1{شهر واحد غير مسدَّد} =2{شهران غير مسدَّدين} few{{count} أشهر غير مسدَّدة} other{{count} شهراً غير مسدَّد}}'**
  String openMonthsCount(int count);

  /// No description provided for @myDuesTitle.
  ///
  /// In ar, this message translates to:
  /// **'اشتراكاتي'**
  String get myDuesTitle;

  /// How many months are still outstanding, carried on the CLOSED row of the folded «الاشتراكات» section. A fold that hides the answer costs a tap to learn what a glance used to tell, so the heading keeps the one figure the section is opened for. «لا مستحقات» at zero is an ANSWER, not a count of nothing.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{لا مستحقات} =1{شهر واحد} =2{شهران} few{{count} أشهر} other{{count} شهراً}}'**
  String openPeriodsCount(int count);

  /// No description provided for @duesSection.
  ///
  /// In ar, this message translates to:
  /// **'الاشتراكات'**
  String get duesSection;
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
