// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'متتبع المطالبات';

  @override
  String get navDashboard => 'لوحة التحكم';

  @override
  String get navClaims => 'المطالبات';

  @override
  String get navReminders => 'المتابعات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get addClaim => 'إضافة مطالبة';

  @override
  String get edit => 'تعديل';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get close => 'إغلاق';

  @override
  String get confirm => 'تأكيد';

  @override
  String get search => 'بحث';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get dashTotalClaims => 'إجمالي المطالبات';

  @override
  String get dashOpenClaims => 'مطالبات مفتوحة';

  @override
  String get dashClosedClaims => 'مطالبات منتهية';

  @override
  String get dashDueToday => 'متابعة مستحقة اليوم';

  @override
  String get dashOverdue => 'متابعات متأخرة';

  @override
  String get dashAwaitingApproval => 'مطالبات بانتظار الموافقة';

  @override
  String get dashNeedsAttention => 'تحتاج إلى انتباهك';

  @override
  String get dashRecentlyUpdated => 'آخر المطالبات المحدثة';

  @override
  String get dashEmpty => 'لا توجد مطالبات بعد. ابدأ بإضافة أول مطالبة.';

  @override
  String get filterAll => 'الكل';

  @override
  String get filterOpen => 'المفتوحة';

  @override
  String get filterFollowUp => 'تحتاج متابعة';

  @override
  String get filterOverdue => 'متأخرة';

  @override
  String get sortTooltip => 'ترتيب';

  @override
  String get sortDefault => 'الترتيب الافتراضي';

  @override
  String get sortSubmissionNewest => 'تاريخ التقديم: الأحدث أولاً';

  @override
  String get sortSubmissionOldest => 'تاريخ التقديم: الأقدم أولاً';

  @override
  String get sortUpdatedNewest => 'آخر تحديث: الأحدث أولاً';

  @override
  String get sortUpdatedOldest => 'آخر تحديث: الأقدم أولاً';

  @override
  String get lastUpdateLabel => 'آخر تحديث';

  @override
  String get filterClosed => 'المنتهية';

  @override
  String get clearFilters => 'مسح المرشحات';

  @override
  String get searchHint => 'ابحث باللوحة، الاسم، رقم المطالبة، المركبة…';

  @override
  String get claimsEmpty => 'لا توجد مطالبات مطابقة.';

  @override
  String get loadFailed => 'تعذّر تحميل البيانات الآن. يرجى المحاولة مرة أخرى.';

  @override
  String get selectClaims => 'تحديد المطالبات';

  @override
  String get selectAll => 'تحديد الكل';

  @override
  String get deselectAll => 'إلغاء تحديد الكل';

  @override
  String selectedCount(int count) {
    return 'المحددة: $count';
  }

  @override
  String get claimNumberLabel => 'رقم المطالبة';

  @override
  String get customerNameLabel => 'اسم العميل';

  @override
  String get mobileLabel => 'رقم الجوال';

  @override
  String get nationalIdLabel => 'الهوية الوطنية';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get accidentNumberLabel => 'رقم الحادث';

  @override
  String get accidentDateLabel => 'تاريخ الحادث';

  @override
  String get cityLabel => 'المدينة';

  @override
  String get accidentTypeLabel => 'نوع الحادث';

  @override
  String get noPlate => 'بدون لوحة';

  @override
  String get vehicleTypeLabel => 'نوع المركبة';

  @override
  String get sectionCustomerInfo => 'معلومات العميل';

  @override
  String get sectionAccidentInfo => 'معلومات الحادث والمركبة';

  @override
  String get sectionClaimInfo => 'معلومات المطالبة وشركة التأمين';

  @override
  String get insurerOther => 'أخرى';

  @override
  String get insurerOtherLabel => 'اسم شركة التأمين';

  @override
  String get vehiclePlateLabel => 'رقم اللوحة';

  @override
  String get customerInsurerLabel => 'شركة التأمين';

  @override
  String get insuranceMobileLabel => 'جوال الشركة';

  @override
  String get liabilityPercentLabel => 'نسبة المسؤولية';

  @override
  String get liabilityNotSet => 'غير محدد';

  @override
  String get csvCardTitle => 'ملف إكسل (CSV)';

  @override
  String get csvExportAction => 'تصدير إلى ملف CSV';

  @override
  String get csvImportAction => 'استيراد من ملف CSV';

  @override
  String get csvExportedOk => 'تم تصدير ملف CSV.';

  @override
  String get csvExportFailed => 'تعذّر تصدير ملف CSV.';

  @override
  String csvImportedOk(int created, int updated) {
    return 'تم الاستيراد: $created جديدة، و$updated محدّثة.';
  }

  @override
  String get csvImportRejected =>
      'لم يُحفظ شيء. صحّح هذه الصفوف في الملف ثم أعد الاستيراد:';

  @override
  String get csvImportFailed =>
      'توقف الاستيراد بسبب خطأ في قاعدة البيانات، وقد تكون بعض الصفوف حُفظت.';

  @override
  String get csvReminderWarning => 'تعذّر جدولة بعض التذكيرات على هذا الجهاز.';

  @override
  String get csvErrorEncoding => 'احفظ الملف بصيغة CSV UTF-8 ثم أعد المحاولة.';

  @override
  String get csvErrorMalformed => 'تعذّر قراءة الملف. تحقق من علامات الاقتباس.';

  @override
  String get csvErrorMissingColumns => 'أعمدة ناقصة:';

  @override
  String get csvRowLabel => 'صف';

  @override
  String get csvErrorBadId =>
      'يجب أن يكون العمود id رقماً صحيحاً من الملف المصدّر.';

  @override
  String get csvErrorUnknownId => 'لا توجد مطالبة بهذا الرقم في التطبيق.';

  @override
  String get csvErrorDuplicateId => 'هذا الرقم مكرر في الملف.';

  @override
  String get csvErrorAmount => 'المبلغ يجب أن يكون رقماً.';

  @override
  String get csvErrorLiability =>
      'نسبة المسؤولية يجب أن تكون فارغة أو 0 أو 25 أو 50 أو 75 أو 100.';

  @override
  String get csvErrorDate =>
      'تاريخ غير مفهوم. استخدم مثلاً 2026-03-31 أو 31/03/2026 (وأضف 14:30 لوقت المتابعة).';

  @override
  String get csvErrorStatus =>
      'حالة غير معروفة. استخدم اسم الحالة كما يظهر في التطبيق أو رمزها.';

  @override
  String csvImportUnchanged(int count) {
    return '$count بدون تغيير.';
  }

  @override
  String get csvNothingChanged =>
      'لم يتغير شيء: محتوى الملف مطابق لما في التطبيق. إذا عدّلت الملف في WPS أو Excel فتأكد من حفظه قبل استيراده.';

  @override
  String csvUnknownIdsAdded(int count) {
    return '$count صف برقم id غير موجود في التطبيق أُضيف كمطالبة جديدة.';
  }

  @override
  String get csvNoRows => 'الملف لا يحتوي على أي مطالبات.';

  @override
  String get csvDatesMonthFirst =>
      'قُرئت التواريخ بصيغة شهر/يوم/سنة (‎11/4/2026‎ = 4 نوفمبر 2026).';

  @override
  String csvExtraColumnsSaved(String columns) {
    return 'حُفظت الأعمدة الإضافية مع المطالبات: $columns';
  }

  @override
  String get extraFieldsLabel => 'حقول إضافية';

  @override
  String get submissionDateLabel => 'تاريخ تقديم المطالبة';

  @override
  String get insurerRefLabel => 'المرجع لدى شركة التأمين';

  @override
  String get claimAmountLabel => 'مبلغ المطالبة (ر.س)';

  @override
  String get notesLabel => 'ملاحظات';

  @override
  String get statusLabel => 'الحالة الحالية';

  @override
  String get lastStatusUpdateLabel => 'آخر تحديث للحالة';

  @override
  String get nextFollowUpLabel => 'المتابعة القادمة';

  @override
  String get reminderEnabled => 'التذكير مفعّل';

  @override
  String get reminderDisabled => 'التذكير متوقف';

  @override
  String get attachmentsLabel => 'المرفقات';

  @override
  String get attachmentsEmpty => 'لا توجد مرفقات بعد.';

  @override
  String get attachmentAdd => 'إضافة مرفق';

  @override
  String get attachmentOpenFailed =>
      'تعذّر فتح الملف. قد لا يوجد تطبيق على جهازك يفتح هذا النوع.';

  @override
  String get attachmentMissing => 'الملف غير موجود على الجهاز.';

  @override
  String get deleteAttachmentTitle => 'حذف المرفق؟';

  @override
  String get deleteAttachmentBody =>
      'سيُحذف الملف من التخزين الخاص بالتطبيق نهائيًا.';

  @override
  String get attachmentPickFailed => 'تعذّر فتح منتقي الملفات.';

  @override
  String get attachmentStoreError => 'تعذّر الوصول إلى تخزين المرفقات.';

  @override
  String get claimNotFound =>
      'لم يتم العثور على المطالبة. ربما حُذفت من مكان آخر.';

  @override
  String get statusHistoryLabel => 'سجل تغييرات الحالة';

  @override
  String get historyEmpty => 'لا توجد تغييرات مسجلة بعد.';

  @override
  String get changeStatus => 'تغيير الحالة';

  @override
  String get changeStatusTitle => 'تغيير حالة المطالبة';

  @override
  String get statusNoteHint => 'ملاحظة اختيارية على التغيير';

  @override
  String get setNextFollowUp => 'تحديد موعد المتابعة القادمة';

  @override
  String get keepExistingFollowUp => 'إبقاء الموعد الحالي';

  @override
  String get clearFollowUp => 'إلغاء الموعد';

  @override
  String get reminderTitle => 'تذكير المطالبة';

  @override
  String get reminderWhenLabel => 'موعد التذكير';

  @override
  String get reminderSet => 'تحديد موعد التذكير';

  @override
  String get reminderDisable => 'إلغاء التذكير';

  @override
  String get reminderRepeatLabel => 'التكرار';

  @override
  String get repeatNone => 'مرة واحدة';

  @override
  String repeatEveryHours(int n) {
    return 'كل $n ساعة';
  }

  @override
  String repeatEveryDays(int n) {
    return 'كل $n يوم';
  }

  @override
  String get notificationsPermissionTitle => 'السماح بالإشعارات';

  @override
  String get notificationsPermissionBody =>
      'نحتاج إذن الإشعارات لتذكيرك بمواعيد متابعة المطالبات في الوقت المحدد.';

  @override
  String get notificationsDeniedTitle => 'الإشعارات موقوفة';

  @override
  String get notificationsDeniedBody =>
      'فعّل إشعارات التطبيق من إعدادات الجهاز ليصلك تذكير المتابعة في وقته.';

  @override
  String get requiredField => 'هذا الحقل مطلوب';

  @override
  String get invalidNumber => 'أدخل رقمًا صحيحًا';

  @override
  String get invalidDate => 'أدخل تاريخًا صالحًا';

  @override
  String get futureFollowUpRequired => 'موعد المتابعة يجب أن يكون في المستقبل';

  @override
  String get pickFromContacts => 'إضافة من جهات الاتصال';

  @override
  String get contactPickFailed => 'تعذّر فتح جهات الاتصال';

  @override
  String get callFailed => 'تعذّر فتح الهاتف';

  @override
  String get deleteClaimTitle => 'حذف المطالبة؟';

  @override
  String get deleteClaimBody =>
      'سيتم حذف المطالبة وسجل حالاتها وتذكيراتها ومرفقاتها نهائيًا.';

  @override
  String deleteClaimsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حذف $count من المطالبات؟',
      many: 'حذف $count من المطالبات؟',
      few: 'حذف $count مطالبات؟',
      two: 'حذف المادتين؟',
      one: 'حذف المطالبة؟',
      zero: 'حذف جميع المطالبات؟',
    );
    return '$_temp0';
  }

  @override
  String get deleteClaimsBody =>
      'سيتم حذف هذه المطالبات وسجلات حالاتها وتذكيراتها ومرفقاتها نهائيًا.';

  @override
  String get closeClaimTitle => 'إغلاق المطالبة؟';

  @override
  String get closeClaimBody =>
      'ستُغيَّر الحالة إلى «مغلقة» وستُلغى التذكيرات المجدولة القادمة.';

  @override
  String get settingsTheme => 'المظهر';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get themeSystem => 'اتبع النظام';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get languageEnglish => 'English (الإنجليزية)';

  @override
  String get languageArabic => 'العربية (Arabic)';

  @override
  String get settingsNotifications => 'الإشعارات والتذكيرات';

  @override
  String get notificationsStatusEnabled => 'الإشعارات مفعّلة';

  @override
  String get notificationsStatusDisabled =>
      'الإشعارات غير مفعّلة على هذا الجهاز';

  @override
  String get exactAlarmHint =>
      'قد لا تصل التذكيرات في وقتها الدقيق إذا كانت أوقات التنبيه الدقيقة (Exact Alarms) مقيّدة على جهازك.';

  @override
  String get notificationsRequestAction => 'طلب إذن الإشعارات';

  @override
  String get notificationsOpenSettingsAction => 'فتح إعدادات الإشعارات';

  @override
  String get exactAlarmsStatusGranted =>
      'أوقات التنبيه الدقيقة مسموح بها — التذكيرات تصل في وقتها.';

  @override
  String get exactAlarmsStatusDenied =>
      'أوقات التنبيه الدقيقة غير مسموحة — قد تتأخر التذكيرات عن موعدها.';

  @override
  String get exactAlarmsRequestAction => 'السماح بالتنبيهات الدقيقة';

  @override
  String get exactAlarmExplainTitle => 'التنبيهات الدقيقة';

  @override
  String get exactAlarmExplainBody =>
      'نحتاج إذن أوقات التنبيه الدقيقة حتى تصلك تذكيرات المتابعة في وقتها المحدد، خاصة عندما يكون التطبيق مغلقًا.';

  @override
  String get batteryStatusExempt =>
      'التطبيق مستثنى من تحسين البطارية — التذكيرات تعمل حتى مع إغلاق التطبيق.';

  @override
  String get batteryStatusNotExempt =>
      'التطبيق غير مستثنى من تحسين البطارية — قد تمنع سياسة البطارية وصول التذكيرات عند إغلاق التطبيق.';

  @override
  String get batteryRequestAction => 'طلب الاستثناء';

  @override
  String get batteryExplainBody =>
      'تقوم بعض أجهزة Android بإيقاف تطبيقات الخلفية لتوفير البطارية، مما يمنع وصول التذكيرات في وقتها. السماح بالاستثناء يضمن وصول تذكيرك حتى عندما يكون التطبيق مغلقًا.';

  @override
  String get reminderScheduleFailed =>
      'تم حفظ الموعد، لكن تعذّر جدولة التذكير على النظام. حاول مجددًا أو تحقق من أذونات الإشعارات.';

  @override
  String get reminderInexactWarning =>
      'لم يُسمح بالتنبيهات الدقيقة — قد يتأخر هذا التذكير عن موعده. فعّل الإذن من الإعدادات ليصل في وقته.';

  @override
  String get settingsBackupRestore => 'النسخ الاحتياطي والاستعادة';

  @override
  String get settingsAbout => 'حول التطبيق';

  @override
  String appVersion(String version, String build) {
    return 'إصدار $version (بناء $build)';
  }

  @override
  String get backupExportTitle => 'نسخ احتياطي';

  @override
  String get backupRestoreTitle => 'استعادة نسخة احتياطية';

  @override
  String get backupPassphraseHint => 'عبارة مرور تشفير النسخة';

  @override
  String get backupExportAction => 'تصدير نسخة احتياطية مشفّرة';

  @override
  String get backupRestoreAction => 'استعادة من نسخة احتياطية';

  @override
  String get backupPassphraseTitle => 'عبارة مرور التشفير';

  @override
  String get backupPassphraseConfirmTitle => 'تأكيد عبارة المرور';

  @override
  String get backupPassphraseMismatch => 'كلمتا المرور غير متطابقتين';

  @override
  String get backupExportedOk => 'تم إنشاء النسخة الاحتياطية بنجاح.';

  @override
  String get backupWorking => 'جارٍ العمل…';

  @override
  String get restoreWarningTitle => 'استبدال البيانات الحالية؟';

  @override
  String get restoreWarningBody =>
      'سيستبدل هذا الإجراء كل المطالبات والمرفقات الحالية بمحتوى النسخة. لا يمكن التراجع بعد التأكيد.';

  @override
  String restoredOk(int claims, int attachments) {
    return 'تمت الاستعادة: $claims مطالبة و$attachments مرفقًا.';
  }

  @override
  String get backupFailedWrongPassphrase =>
      'عبارة المرور غير صحيحة أو النسخة تالفة. لم تُعدَّل بياناتك الحالية.';

  @override
  String get backupFailedCorrupt =>
      'النسخة الاحتياطية تالفة أو غير متوافقة مع هذا الإصدار. لم تُعدَّل بياناتك الحالية.';

  @override
  String get backupExportFailed => 'تعذّر إنشاء النسخة الاحتياطية.';

  @override
  String get backupRestoreFailed =>
      'تعذّرت الاستعادة. لم تُعدَّل بياناتك الحالية.';

  @override
  String get securityInfoTitle => 'الخصوصية والأمان';

  @override
  String get securityInfoBody =>
      'تُخزَّن جميع البيانات محليًا على جهازك فقط، دون أي إرسال عبر الشبكة أو تحليلات. النسخ الاحتياطي مشفَّر بعبارة مرورك (PBKDF2 + AES-256). تأكد قبل إدخال بيانات حقيقية من توافق التخزين المحلي مع سياسات جهة عملك ومتطلبات الخصوصية السعودية (PDPL) حيث ينطبق.';

  @override
  String get statusNew => 'جديدة';

  @override
  String get statusSubmitted => 'تم تقديم المطالبة';

  @override
  String get statusAwaitingReview => 'بانتظار المراجعة';

  @override
  String get statusAwaitingDocuments => 'بانتظار مستندات';

  @override
  String get statusProcessing => 'تحت المعالجة';

  @override
  String get statusAwaitingApproval => 'بانتظار الموافقة';

  @override
  String get statusApproved => 'تمت الموافقة';

  @override
  String get statusCompensated => 'تم التعويض';

  @override
  String get statusRejected => 'مرفوضة';

  @override
  String get statusClosed => 'مغلقة';

  @override
  String get followUpOverdue => 'متأخرة';

  @override
  String get followUpToday => 'اليوم';

  @override
  String get currencySar => 'ر.س';

  @override
  String get reminderChannelName => 'تذكيرات المطالبات';

  @override
  String get reminderChannelDescription =>
      'تنبيهات متابعة مطالبات التأمين على الحوادث المرورية';

  @override
  String get genericReminderTitle => 'تذكير متابعة مطالبة';

  @override
  String get genericReminderBody => 'لديك مطالبة تستحق المتابعة الآن.';
}
