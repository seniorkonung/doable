import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
    Locale('en'),
    Locale('ru'),
  ];

  /// Название приложения
  ///
  /// In en, this message translates to:
  /// **'Doable'**
  String get appTitle;

  /// Пункт навигации к каталогу активных намерений
  ///
  /// In en, this message translates to:
  /// **'Active intentions'**
  String get navigationActiveIntentions;

  /// Пункт навигации к архиву намерений
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get navigationArchive;

  /// Общее состояние загрузки
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// Общее состояние пустого результата
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonEmpty;

  /// Общее безопасное сообщение об ошибке
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonError;

  /// Действие явной повторной попытки
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonRetry;

  /// Состояние подготовки локального хранилища при запуске
  ///
  /// In en, this message translates to:
  /// **'Preparing local data…'**
  String get bootstrapLoading;

  /// Безопасное сообщение об устранимой ошибке открытия или миграции
  ///
  /// In en, this message translates to:
  /// **'Local data couldn’t be prepared. Your data wasn’t changed. Try again.'**
  String get bootstrapMigrationFailure;

  /// Терминальное состояние повреждённого локального хранилища
  ///
  /// In en, this message translates to:
  /// **'Local data is damaged and can’t be opened.'**
  String get bootstrapCorruption;

  /// Требование обновить приложение при более новой версии локального хранилища
  ///
  /// In en, this message translates to:
  /// **'Install a compatible Doable update to continue.'**
  String get bootstrapIncompatibleSchema;

  /// Терминальное состояние непредвиденной ошибки локального хранилища
  ///
  /// In en, this message translates to:
  /// **'Local data couldn’t be opened because of an unexpected error.'**
  String get bootstrapUnexpectedFailure;

  /// Начальная загрузка каталога намерений
  ///
  /// In en, this message translates to:
  /// **'Loading intentions…'**
  String get catalogLoading;

  /// Заголовок единого каталога намерений
  ///
  /// In en, this message translates to:
  /// **'Intentions'**
  String get catalogTitle;

  /// Подпись выбора охвата каталога
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get catalogScopeLabel;

  /// Охват активных намерений
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get catalogScopeActive;

  /// Охват архивированных намерений
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get catalogScopeArchived;

  /// Охват всех существующих намерений
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get catalogScopeAll;

  /// Подпись поля фильтра каталога по названию
  ///
  /// In en, this message translates to:
  /// **'Filter by title'**
  String get catalogFilterLabel;

  /// Ошибка недопустимого Unicode в фильтре каталога
  ///
  /// In en, this message translates to:
  /// **'Enter valid Unicode text without NUL.'**
  String get catalogFilterInvalidUnicode;

  /// Ошибка превышения длины фильтра каталога
  ///
  /// In en, this message translates to:
  /// **'Use no more than 255 characters.'**
  String get catalogFilterTooLong;

  /// Подпись выбора порядка каталога
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get catalogOrderLabel;

  /// Убывающий порядок по времени создания
  ///
  /// In en, this message translates to:
  /// **'Created: newest first'**
  String get catalogOrderCreatedNewest;

  /// Возрастающий порядок по времени создания
  ///
  /// In en, this message translates to:
  /// **'Created: oldest first'**
  String get catalogOrderCreatedOldest;

  /// Убывающий порядок по времени изменения
  ///
  /// In en, this message translates to:
  /// **'Updated: newest first'**
  String get catalogOrderUpdatedNewest;

  /// Возрастающий порядок по времени изменения
  ///
  /// In en, this message translates to:
  /// **'Updated: oldest first'**
  String get catalogOrderUpdatedOldest;

  /// Точное количество намерений в текущей выдаче
  ///
  /// In en, this message translates to:
  /// **'Total intentions: {count}'**
  String catalogTotalCount(int count);

  /// Пустой каталог активных намерений
  ///
  /// In en, this message translates to:
  /// **'No active intentions yet.'**
  String get catalogActiveEmpty;

  /// Пустой каталог архивированных намерений
  ///
  /// In en, this message translates to:
  /// **'No archived intentions yet.'**
  String get catalogArchivedEmpty;

  /// Пустой каталог всех намерений
  ///
  /// In en, this message translates to:
  /// **'No intentions yet.'**
  String get catalogAllEmpty;

  /// Устранимая недоступность первой страницы каталога
  ///
  /// In en, this message translates to:
  /// **'Intentions couldn’t be loaded. Try again.'**
  String get catalogUnavailable;

  /// Терминальное состояние повреждённых данных каталога
  ///
  /// In en, this message translates to:
  /// **'Stored intention data is damaged and can’t be shown.'**
  String get catalogCorruption;

  /// Терминальное состояние непредвиденной ошибки каталога
  ///
  /// In en, this message translates to:
  /// **'Intentions couldn’t be loaded because of an unexpected error.'**
  String get catalogUnexpectedFailure;

  /// Загрузка следующей порции каталога
  ///
  /// In en, this message translates to:
  /// **'Loading more intentions…'**
  String get catalogLoadingMore;

  /// Устранимая недоступность следующей порции каталога
  ///
  /// In en, this message translates to:
  /// **'More intentions couldn’t be loaded.'**
  String get catalogLoadMoreUnavailable;

  /// Терминальное повреждение при загрузке следующей порции
  ///
  /// In en, this message translates to:
  /// **'Stored intention data is damaged; no more intentions can be shown.'**
  String get catalogLoadMoreCorruption;

  /// Терминальная непредвиденная ошибка следующей порции
  ///
  /// In en, this message translates to:
  /// **'More intentions couldn’t be loaded because of an unexpected error.'**
  String get catalogLoadMoreUnexpected;

  /// Недопустимый cursor следующей порции
  ///
  /// In en, this message translates to:
  /// **'The saved catalog position is no longer valid.'**
  String get catalogLoadMoreValidation;

  /// Явное восстановление каталога с первой страницы
  ///
  /// In en, this message translates to:
  /// **'Reload catalog'**
  String get catalogReload;

  /// Восстановление каталога с первой страницы
  ///
  /// In en, this message translates to:
  /// **'Reloading catalog…'**
  String get catalogReloading;

  /// Признак готовности намерения к действию
  ///
  /// In en, this message translates to:
  /// **'Ready for action'**
  String get catalogReady;

  /// Признак отсутствия готовности намерения к действию
  ///
  /// In en, this message translates to:
  /// **'Not ready for action'**
  String get catalogNotReady;

  /// Признак наличия описания намерения
  ///
  /// In en, this message translates to:
  /// **'Has description'**
  String get catalogHasDescription;

  /// Признак отсутствия описания намерения
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get catalogNoDescription;

  /// Количество активных связей намерения в его представлении
  ///
  /// In en, this message translates to:
  /// **'Active relations: {count}'**
  String intentionActiveRelationCount(int count);

  /// Ошибка обновления количества активных связей при сохранённом прежнем числе
  ///
  /// In en, this message translates to:
  /// **'The active relation count couldn’t be refreshed.'**
  String get intentionActiveRelationCountRefreshFailed;

  /// Количество активных связей ещё не получено
  ///
  /// In en, this message translates to:
  /// **'Loading the active relation count…'**
  String get intentionActiveRelationCountLoading;

  /// Количество активных связей неизвестно из-за ошибки получения
  ///
  /// In en, this message translates to:
  /// **'The active relation count is unknown.'**
  String get intentionActiveRelationCountUnknown;

  /// Заголовок соседства намерения
  ///
  /// In en, this message translates to:
  /// **'Relations'**
  String get relationNeighborhoodTitle;

  /// Первоначальная загрузка соседства и полной сводки
  ///
  /// In en, this message translates to:
  /// **'Loading relations and summary…'**
  String get relationNeighborhoodSummaryLoading;

  /// Полная сводка ещё не подтверждена из-за ошибки
  ///
  /// In en, this message translates to:
  /// **'The relation summary couldn’t be loaded.'**
  String get relationNeighborhoodSummaryUnavailable;

  /// Состояние обновления сохранённой согласованной сводки рядом с её числами
  ///
  /// In en, this message translates to:
  /// **'Updating saved relation numbers…'**
  String get relationNeighborhoodSavedSummaryRefreshing;

  /// Состояние устаревшей сохранённой сводки рядом с её числами
  ///
  /// In en, this message translates to:
  /// **'Saved relation numbers are out of date because the refresh failed.'**
  String get relationNeighborhoodSavedSummaryStale;

  /// No description provided for @relationNeighborhoodTotal.
  ///
  /// In en, this message translates to:
  /// **'Total relations: {count}'**
  String relationNeighborhoodTotal(int count);

  /// No description provided for @relationNeighborhoodActiveTotal.
  ///
  /// In en, this message translates to:
  /// **'Active relations: {count}'**
  String relationNeighborhoodActiveTotal(int count);

  /// No description provided for @relationNeighborhoodArchivedTotal.
  ///
  /// In en, this message translates to:
  /// **'Archived relations: {count}'**
  String relationNeighborhoodArchivedTotal(int count);

  /// No description provided for @relationNeighborhoodNeedTotal.
  ///
  /// In en, this message translates to:
  /// **'Need: {count}'**
  String relationNeighborhoodNeedTotal(int count);

  /// No description provided for @relationNeighborhoodCanTotal.
  ///
  /// In en, this message translates to:
  /// **'Can: {count}'**
  String relationNeighborhoodCanTotal(int count);

  /// Подпись выбора активных или архивных связей
  ///
  /// In en, this message translates to:
  /// **'Relation state'**
  String get relationNeighborhoodScopeLabel;

  /// Активный охват соседства
  ///
  /// In en, this message translates to:
  /// **'Active relations'**
  String get relationNeighborhoodScopeActive;

  /// Архивный охват соседства
  ///
  /// In en, this message translates to:
  /// **'Archived relations'**
  String get relationNeighborhoodScopeArchived;

  /// Подпись выбора типа долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Relation type'**
  String get relationNeighborhoodTypeLabel;

  /// Тип долговременной связи нужно
  ///
  /// In en, this message translates to:
  /// **'Need'**
  String get relationNeighborhoodTypeNeed;

  /// Тип долговременной связи можно
  ///
  /// In en, this message translates to:
  /// **'Can'**
  String get relationNeighborhoodTypeCan;

  /// Подпись выбора направления связи
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get relationNeighborhoodDirectionLabel;

  /// Входящее направление относительно намерения
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get relationNeighborhoodDirectionIncoming;

  /// Исходящее направление относительно намерения
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get relationNeighborhoodDirectionOutgoing;

  /// No description provided for @relationNeighborhoodSelectedGroupCount.
  ///
  /// In en, this message translates to:
  /// **'In the whole selected group: {count}'**
  String relationNeighborhoodSelectedGroupCount(int count);

  /// Устранимая ошибка начального чтения группы
  ///
  /// In en, this message translates to:
  /// **'The relations and summary couldn’t be loaded. Try again.'**
  String get relationNeighborhoodInitialUnavailable;

  /// Повреждение при начальном чтении группы
  ///
  /// In en, this message translates to:
  /// **'Stored relation data is damaged and can’t be shown.'**
  String get relationNeighborhoodInitialCorruption;

  /// Непредвиденная ошибка начального чтения группы
  ///
  /// In en, this message translates to:
  /// **'The relations couldn’t be loaded because of an unexpected error.'**
  String get relationNeighborhoodInitialUnexpected;

  /// Недействительный запрос начальной группы
  ///
  /// In en, this message translates to:
  /// **'The selected relation group can no longer be opened.'**
  String get relationNeighborhoodInitialInvalid;

  /// Владелец соседства подтверждённо отсутствует
  ///
  /// In en, this message translates to:
  /// **'The intention whose relations were being viewed no longer exists.'**
  String get relationNeighborhoodIntentionNotFound;

  /// Подтверждённо пустая выбранная группа
  ///
  /// In en, this message translates to:
  /// **'There are no relations in this group.'**
  String get relationNeighborhoodEmpty;

  /// Подгрузка следующей порции выбранной группы
  ///
  /// In en, this message translates to:
  /// **'Loading more relations…'**
  String get relationNeighborhoodLoadingMore;

  /// Устранимая ошибка подгрузки
  ///
  /// In en, this message translates to:
  /// **'The next relations couldn’t be loaded.'**
  String get relationNeighborhoodLoadMoreUnavailable;

  /// Повреждение при подгрузке
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged; the next relations can’t be shown.'**
  String get relationNeighborhoodLoadMoreCorruption;

  /// Непредвиденная ошибка подгрузки
  ///
  /// In en, this message translates to:
  /// **'The next relations couldn’t be loaded because of an unexpected error.'**
  String get relationNeighborhoodLoadMoreUnexpected;

  /// Недействительное продолжение группы
  ///
  /// In en, this message translates to:
  /// **'The continuation for this group is no longer valid.'**
  String get relationNeighborhoodLoadMoreInvalid;

  /// Согласованное обновление сводки и выбранной группы
  ///
  /// In en, this message translates to:
  /// **'Refreshing relations…'**
  String get relationNeighborhoodRefreshing;

  /// Ошибка обновления при сохранённых прежних данных
  ///
  /// In en, this message translates to:
  /// **'The relations couldn’t be refreshed. Previously loaded data is still shown.'**
  String get relationNeighborhoodRefreshFailed;

  /// Подтверждённый конец выбранной группы
  ///
  /// In en, this message translates to:
  /// **'All relations in this group are loaded.'**
  String get relationNeighborhoodConfirmedEnd;

  /// Активное состояние строки связи
  ///
  /// In en, this message translates to:
  /// **'Active relation'**
  String get relationNeighborhoodRelationActive;

  /// Архивное состояние строки связи
  ///
  /// In en, this message translates to:
  /// **'Archived relation'**
  String get relationNeighborhoodRelationArchived;

  /// No description provided for @relationNeighborhoodPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String relationNeighborhoodPriority(String priority);

  /// Подпись исходного участника связи
  ///
  /// In en, this message translates to:
  /// **'Source intention'**
  String get relationNeighborhoodSourceParticipant;

  /// Подпись связанного участника связи
  ///
  /// In en, this message translates to:
  /// **'Related intention'**
  String get relationNeighborhoodRelatedParticipant;

  /// No description provided for @relationNeighborhoodNeedPhrase.
  ///
  /// In en, this message translates to:
  /// **'To {source}, you need {related}'**
  String relationNeighborhoodNeedPhrase(String source, String related);

  /// No description provided for @relationNeighborhoodCanPhrase.
  ///
  /// In en, this message translates to:
  /// **'To {source}, you can {related}'**
  String relationNeighborhoodCanPhrase(String source, String related);

  /// Заголовок подробного просмотра намерения
  ///
  /// In en, this message translates to:
  /// **'Intention details'**
  String get detailsTitle;

  /// Начальная загрузка подробных данных намерения
  ///
  /// In en, this message translates to:
  /// **'Loading intention…'**
  String get detailsLoading;

  /// Подтверждённое отсутствие намерения
  ///
  /// In en, this message translates to:
  /// **'Intention not found.'**
  String get detailsNotFound;

  /// Устранимая недоступность подробных данных намерения
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be loaded. Try again.'**
  String get detailsUnavailable;

  /// Терминальное повреждение подробных данных намерения
  ///
  /// In en, this message translates to:
  /// **'Stored intention data is damaged and can’t be shown.'**
  String get detailsCorruption;

  /// Терминальная непредвиденная ошибка подробного чтения
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be loaded because of an unexpected error.'**
  String get detailsUnexpected;

  /// Сохраняющаяся между экранами выполняющаяся операция намерения
  ///
  /// In en, this message translates to:
  /// **'Saving changes…'**
  String get detailsOperationRunning;

  /// Подпись описания в подробных данных намерения
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get detailsDescriptionLabel;

  /// Отсутствующее описание в подробных данных намерения
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get detailsNoDescription;

  /// Подпись готовности к действию в подробных данных
  ///
  /// In en, this message translates to:
  /// **'Readiness'**
  String get detailsReadinessLabel;

  /// Подпись архивного состояния в подробных данных
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get detailsArchiveStateLabel;

  /// Активное состояние намерения в подробных данных
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get detailsActive;

  /// Архивное состояние намерения в подробных данных
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get detailsArchived;

  /// Действие перехода к изменению намерения
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get detailsEditAction;

  /// Действие сохранения изменённых данных намерения
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get detailsSaveAction;

  /// Действие отмены изменения намерения до отправки
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get detailsCancelEditAction;

  /// Подтверждение успешного изменения намерения
  ///
  /// In en, this message translates to:
  /// **'Changes saved.'**
  String get detailsSaved;

  /// Действие начала явного включения готовности намерения
  ///
  /// In en, this message translates to:
  /// **'Mark as ready for action'**
  String get detailsEnableReadinessAction;

  /// Явное действие выключения готовности намерения
  ///
  /// In en, this message translates to:
  /// **'Mark as not ready for action'**
  String get detailsDisableReadinessAction;

  /// Заголовок объяснения критериев готовности к действию
  ///
  /// In en, this message translates to:
  /// **'Ready for action?'**
  String get detailsReadinessConfirmationTitle;

  /// Критерий полной однодневной выполнимости действия
  ///
  /// In en, this message translates to:
  /// **'It can be completed fully within one day.'**
  String get detailsReadinessOneDayCriterion;

  /// Критерий операционной понятности действия человеку
  ///
  /// In en, this message translates to:
  /// **'It is clear enough for a person to carry out.'**
  String get detailsReadinessClarityCriterion;

  /// Подтверждение соответствия обоим критериям действия
  ///
  /// In en, this message translates to:
  /// **'Mark as ready'**
  String get detailsConfirmReadinessAction;

  /// Явное действие архивирования намерения
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get detailsArchiveAction;

  /// Явное действие восстановления намерения из архива
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get detailsRestoreAction;

  /// Действие начала физического удаления намерения
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get detailsDeleteAction;

  /// Заголовок подтверждения необратимого удаления намерения
  ///
  /// In en, this message translates to:
  /// **'Delete intention permanently?'**
  String get detailsDeleteConfirmationTitle;

  /// Объяснение необратимости физического удаления намерения
  ///
  /// In en, this message translates to:
  /// **'This can’t be undone. The intention and its description will be permanently deleted.'**
  String get detailsDeleteConfirmationMessage;

  /// Явное подтверждение физического удаления намерения
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get detailsConfirmDeleteAction;

  /// Подтверждение физического удаления намерения после ухода из подробного просмотра
  ///
  /// In en, this message translates to:
  /// **'Intention deleted.'**
  String get detailsDeleted;

  /// Подтверждение включённой готовности к действию
  ///
  /// In en, this message translates to:
  /// **'Marked as ready for action.'**
  String get detailsReadinessEnabled;

  /// Подтверждение выключенной готовности к действию
  ///
  /// In en, this message translates to:
  /// **'Marked as not ready for action.'**
  String get detailsReadinessDisabled;

  /// Подтверждение архивирования намерения
  ///
  /// In en, this message translates to:
  /// **'Intention archived.'**
  String get detailsArchivedSuccess;

  /// Подтверждение восстановления намерения
  ///
  /// In en, this message translates to:
  /// **'Intention restored.'**
  String get detailsRestoredSuccess;

  /// Безопасная ошибка недопустимого перехода состояния
  ///
  /// In en, this message translates to:
  /// **'The intention state couldn’t be changed.'**
  String get detailsStateChangeInvalid;

  /// Безопасная ошибка перехода отсутствующего намерения
  ///
  /// In en, this message translates to:
  /// **'The intention no longer exists. Its state wasn’t changed.'**
  String get detailsStateChangeNotFound;

  /// Безопасная ошибка конфликта перехода состояния
  ///
  /// In en, this message translates to:
  /// **'The intention changed elsewhere. Its state wasn’t changed.'**
  String get detailsStateChangeConflict;

  /// Устранимая недоступность перехода состояния намерения
  ///
  /// In en, this message translates to:
  /// **'The intention state couldn’t be changed. Try again.'**
  String get detailsStateChangeUnavailable;

  /// Терминальное повреждение при переходе состояния
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The intention state wasn’t changed.'**
  String get detailsStateChangeCorruption;

  /// Терминальная непредвиденная ошибка перехода состояния
  ///
  /// In en, this message translates to:
  /// **'The intention state couldn’t be changed because of an unexpected error.'**
  String get detailsStateChangeUnexpected;

  /// Безопасная ошибка недопустимого физического удаления
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be deleted.'**
  String get detailsDeleteInvalid;

  /// Безопасная ошибка удаления отсутствующего намерения
  ///
  /// In en, this message translates to:
  /// **'The intention no longer exists. It wasn’t deleted.'**
  String get detailsDeleteNotFound;

  /// Безопасная ошибка конфликта при удалении намерения
  ///
  /// In en, this message translates to:
  /// **'The intention changed elsewhere. It wasn’t deleted.'**
  String get detailsDeleteConflict;

  /// Объяснение блокировки удаления намерения его связями
  ///
  /// In en, this message translates to:
  /// **'The intention wasn’t deleted: its relations still block deletion. Archived relations and relations that aren’t loaded yet block it too.'**
  String get detailsDeleteBlockedByRelations;

  /// Переход к актуальным группам связей, блокирующих удаление
  ///
  /// In en, this message translates to:
  /// **'Show blocking relations'**
  String get detailsShowBlockingRelationsAction;

  /// Объяснение каскада непосредственных связей перед архивированием
  ///
  /// In en, this message translates to:
  /// **'Archiving also archives the intention’s direct relations. Neighbouring intentions and their other relations stay unchanged.'**
  String get detailsArchiveCascadeExplanation;

  /// Объяснение сохранённого архива связей перед восстановлением
  ///
  /// In en, this message translates to:
  /// **'Restoring returns only the intention. Its relations stay archived: {count}.'**
  String detailsRestoreRelationsExplanation(int count);

  /// Переход к архивным группам связей намерения
  ///
  /// In en, this message translates to:
  /// **'Show archived relations'**
  String get detailsShowArchivedRelationsAction;

  /// Устранимая недоступность физического удаления намерения
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be deleted. Try again.'**
  String get detailsDeleteUnavailable;

  /// Терминальное повреждение при физическом удалении намерения
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The intention wasn’t deleted.'**
  String get detailsDeleteCorruption;

  /// Терминальная непредвиденная ошибка физического удаления
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be deleted because of an unexpected error.'**
  String get detailsDeleteUnexpected;

  /// Общая ошибка проверки формы изменения
  ///
  /// In en, this message translates to:
  /// **'Check the entered data.'**
  String get detailsUpdateInvalidInput;

  /// Безопасное сообщение об отсутствующем изменяемом намерении
  ///
  /// In en, this message translates to:
  /// **'The intention no longer exists. Your changes weren’t saved.'**
  String get detailsUpdateNotFound;

  /// Безопасное сообщение о конфликте изменения намерения
  ///
  /// In en, this message translates to:
  /// **'The intention changed elsewhere. Your changes weren’t saved.'**
  String get detailsUpdateConflict;

  /// Устранимая недоступность изменения намерения
  ///
  /// In en, this message translates to:
  /// **'The changes couldn’t be saved. Try again.'**
  String get detailsUpdateUnavailable;

  /// Терминальное повреждение данных при изменении намерения
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The changes weren’t saved.'**
  String get detailsUpdateCorruption;

  /// Терминальная непредвиденная ошибка изменения намерения
  ///
  /// In en, this message translates to:
  /// **'The changes couldn’t be saved because of an unexpected error.'**
  String get detailsUpdateUnexpected;

  /// Заголовок формы создания намерения
  ///
  /// In en, this message translates to:
  /// **'Create intention'**
  String get editorTitle;

  /// Действие создания намерения
  ///
  /// In en, this message translates to:
  /// **'Create intention'**
  String get editorCreateAction;

  /// Состояние выполняющегося создания намерения
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get editorCreating;

  /// Подпись поля названия намерения
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get editorTitleLabel;

  /// Подпись необязательного поля описания намерения
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get editorDescriptionLabel;

  /// Ошибка пустого названия намерения
  ///
  /// In en, this message translates to:
  /// **'Enter a title.'**
  String get editorTitleEmpty;

  /// Ошибка превышения длины названия намерения
  ///
  /// In en, this message translates to:
  /// **'Use no more than 255 characters.'**
  String get editorTitleTooLong;

  /// Ошибка недопустимого Unicode в названии намерения
  ///
  /// In en, this message translates to:
  /// **'Enter valid Unicode text without NUL.'**
  String get editorTitleInvalidUnicode;

  /// Ошибка превышения длины описания намерения
  ///
  /// In en, this message translates to:
  /// **'Use no more than 4096 characters.'**
  String get editorDescriptionTooLong;

  /// Ошибка недопустимого Unicode в описании намерения
  ///
  /// In en, this message translates to:
  /// **'Enter valid Unicode text without NUL.'**
  String get editorDescriptionInvalidUnicode;

  /// Общая ошибка проверки формы создания
  ///
  /// In en, this message translates to:
  /// **'Check the entered data.'**
  String get editorInvalidInput;

  /// Безопасное сообщение о конфликте создания намерения
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be created because of a conflict.'**
  String get editorCreateConflict;

  /// Устранимая недоступность создания намерения
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be created. Try again.'**
  String get editorCreateUnavailable;

  /// Терминальное повреждение данных при создании намерения
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The intention wasn’t created.'**
  String get editorCreateCorruption;

  /// Терминальная непредвиденная ошибка создания намерения
  ///
  /// In en, this message translates to:
  /// **'The intention couldn’t be created because of an unexpected error.'**
  String get editorCreateUnexpected;

  /// Подтверждение успешного создания намерения
  ///
  /// In en, this message translates to:
  /// **'Intention created.'**
  String get editorCreated;

  /// Вид операции создания намерения в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get graphOperationCreate;

  /// Вид операции изменения намерения в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get graphOperationUpdate;

  /// Вид операции включения готовности в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Mark ready'**
  String get graphOperationEnableReadiness;

  /// Вид операции отключения готовности в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Mark not ready'**
  String get graphOperationDisableReadiness;

  /// Вид операции архивирования намерения в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get graphOperationArchive;

  /// Вид операции восстановления намерения в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get graphOperationRestore;

  /// Вид операции удаления намерения в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get graphOperationDelete;

  /// Безопасное обозначение создаваемого намерения до подтверждения
  ///
  /// In en, this message translates to:
  /// **'new intention'**
  String get graphOperationNewIntention;

  /// Безопасное обозначение намерения без доступного названия
  ///
  /// In en, this message translates to:
  /// **'intention'**
  String get graphOperationIntention;

  /// Сообщение оболочки о результате принятой операции
  ///
  /// In en, this message translates to:
  /// **'{operation} — “{target}”: {outcome}'**
  String graphOperationMessage(String operation, String target, String outcome);

  /// Безопасное обозначение создаваемой связи до подтверждения
  ///
  /// In en, this message translates to:
  /// **'new relation'**
  String get graphOperationNewRelation;

  /// Безопасное обозначение существующей связи
  ///
  /// In en, this message translates to:
  /// **'relation'**
  String get graphOperationRelation;

  /// Подтверждение успешного создания долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Relation created.'**
  String get relationEditorCreated;

  /// Ошибка проверки данных создания связи
  ///
  /// In en, this message translates to:
  /// **'Check the selected intentions and relation details.'**
  String get relationEditorCreateInvalidInput;

  /// Конфликт занятой направленной пары при создании связи
  ///
  /// In en, this message translates to:
  /// **'A relation with this direction already exists between the selected intentions.'**
  String get relationEditorCreatePairOccupied;

  /// Отсутствие участника при создании связи
  ///
  /// In en, this message translates to:
  /// **'One of the selected intentions no longer exists.'**
  String get relationEditorCreateParticipantNotFound;

  /// Конфликт архивного состояния участника при создании связи
  ///
  /// In en, this message translates to:
  /// **'Only active intentions can be linked.'**
  String get relationEditorCreateParticipantArchived;

  /// Устранимая недоступность создания связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be created. Try again.'**
  String get relationEditorCreateUnavailable;

  /// Терминальное повреждение данных при создании связи
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The relation wasn’t created.'**
  String get relationEditorCreateCorruption;

  /// Терминальная непредвиденная ошибка создания связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be created because of an unexpected error.'**
  String get relationEditorCreateUnexpected;

  /// Подтверждение успешного изменения долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Relation updated.'**
  String get relationEditorUpdated;

  /// Ошибка проверки данных изменения связи
  ///
  /// In en, this message translates to:
  /// **'Check the selected intentions and relation changes.'**
  String get relationEditorUpdateInvalidInput;

  /// Конфликт занятой направленной пары при изменении связи
  ///
  /// In en, this message translates to:
  /// **'A relation with this direction already exists between the selected intentions.'**
  String get relationEditorUpdatePairOccupied;

  /// Отсутствие изменяемой связи
  ///
  /// In en, this message translates to:
  /// **'This relation no longer exists.'**
  String get relationEditorUpdateNotFound;

  /// Отсутствие участника при изменении связи
  ///
  /// In en, this message translates to:
  /// **'One of the selected intentions no longer exists.'**
  String get relationEditorUpdateParticipantNotFound;

  /// Конфликт архивного состояния участника при изменении активной связи
  ///
  /// In en, this message translates to:
  /// **'An active relation can only link active intentions.'**
  String get relationEditorUpdateParticipantArchived;

  /// Устранимая недоступность изменения связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be updated. Try again.'**
  String get relationEditorUpdateUnavailable;

  /// Терминальное повреждение данных при изменении связи
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The relation wasn’t updated.'**
  String get relationEditorUpdateCorruption;

  /// Терминальная непредвиденная ошибка изменения связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be updated because of an unexpected error.'**
  String get relationEditorUpdateUnexpected;

  /// Назначение перехода из строки соседства в подробный просмотр связи
  ///
  /// In en, this message translates to:
  /// **'Opens the relation details'**
  String get relationNeighborhoodOpenRelation;

  /// Заголовок подробного просмотра связи
  ///
  /// In en, this message translates to:
  /// **'Relation'**
  String get relationDetailsTitle;

  /// Первое чтение подробных данных связи
  ///
  /// In en, this message translates to:
  /// **'Loading the relation…'**
  String get relationDetailsLoading;

  /// Подтверждённое отсутствие связи в подробном просмотре
  ///
  /// In en, this message translates to:
  /// **'This relation no longer exists.'**
  String get relationDetailsNotFound;

  /// Устранимая недоступность чтения подробных данных связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be loaded. Try again.'**
  String get relationDetailsUnavailable;

  /// Повреждение сохранённых данных связи в подробном просмотре
  ///
  /// In en, this message translates to:
  /// **'Stored relation data is damaged and can’t be shown.'**
  String get relationDetailsCorruption;

  /// Безопасный непредвиденный отказ чтения подробных данных связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be loaded because of an unexpected error.'**
  String get relationDetailsUnexpected;

  /// Согласование сохранённого подробного просмотра связи с новой ревизией
  ///
  /// In en, this message translates to:
  /// **'Refreshing relation details…'**
  String get relationDetailsRefreshing;

  /// Устранимая ошибка обновления при сохранённых подробных данных связи
  ///
  /// In en, this message translates to:
  /// **'The relation details couldn’t be refreshed. Previously confirmed data is still shown.'**
  String get relationDetailsRefreshUnavailable;

  /// Повреждение при обновлении с сохранением прежних подробных данных связи
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. Previously confirmed relation details are still shown.'**
  String get relationDetailsRefreshCorruption;

  /// Непредвиденная ошибка обновления с сохранением прежних подробных данных связи
  ///
  /// In en, this message translates to:
  /// **'The relation details couldn’t be refreshed because of an unexpected error. Previously confirmed data is still shown.'**
  String get relationDetailsRefreshUnexpected;

  /// Подпись типа связи в подробном просмотре
  ///
  /// In en, this message translates to:
  /// **'Relation type'**
  String get relationDetailsTypeLabel;

  /// Подпись приоритета связи в подробном просмотре
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get relationDetailsPriorityLabel;

  /// Подпись собственного архивного состояния связи
  ///
  /// In en, this message translates to:
  /// **'Relation state'**
  String get relationDetailsScopeLabel;

  /// Подпись полного описания связи
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get relationDetailsDescriptionLabel;

  /// Отсутствие описания у связи
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get relationDetailsNoDescription;

  /// Назначение перехода к участнику связи
  ///
  /// In en, this message translates to:
  /// **'Opens the intention and its own relations'**
  String get relationDetailsOpenParticipant;

  /// Заголовок выбора участника долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Select a participant'**
  String get participantPickerTitle;

  /// Назначение отмены выбора участника
  ///
  /// In en, this message translates to:
  /// **'Cancel the selection'**
  String get participantPickerCancel;

  /// Отсутствие намерений, доступных для выбора участником
  ///
  /// In en, this message translates to:
  /// **'No other intentions are available to select.'**
  String get participantPickerEmpty;

  /// Назначение выбора строки участником связи
  ///
  /// In en, this message translates to:
  /// **'Selects this intention as a relation participant'**
  String get participantPickerSelectHint;

  /// Назначение перехода к подробным данным намерения из выбора
  ///
  /// In en, this message translates to:
  /// **'Open intention details'**
  String get participantPickerOpenDetails;

  /// Заголовок формы создания долговременной связи
  ///
  /// In en, this message translates to:
  /// **'New relation'**
  String get relationEditorTitle;

  /// Подпись исходного участника в форме создания связи
  ///
  /// In en, this message translates to:
  /// **'Source intention'**
  String get relationEditorSourceLabel;

  /// Подпись связанного участника в форме создания связи
  ///
  /// In en, this message translates to:
  /// **'Related intention'**
  String get relationEditorRelatedLabel;

  /// Состояние выбранного участника связи
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get relationEditorParticipantSelected;

  /// Состояние невыбранного участника связи
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get relationEditorParticipantNotSelected;

  /// Переход к выбору исходного участника
  ///
  /// In en, this message translates to:
  /// **'Select the source intention'**
  String get relationEditorSelectSourceAction;

  /// Замена выбранного исходного участника
  ///
  /// In en, this message translates to:
  /// **'Change the source intention'**
  String get relationEditorChangeSourceAction;

  /// Переход к выбору связанного участника
  ///
  /// In en, this message translates to:
  /// **'Select the related intention'**
  String get relationEditorSelectRelatedAction;

  /// Замена выбранного связанного участника
  ///
  /// In en, this message translates to:
  /// **'Change the related intention'**
  String get relationEditorChangeRelatedAction;

  /// Подпись выбора типа связи в форме создания
  ///
  /// In en, this message translates to:
  /// **'Relation type'**
  String get relationEditorTypeLabel;

  /// Тип связи «нужно» в форме создания
  ///
  /// In en, this message translates to:
  /// **'Need'**
  String get relationEditorTypeNeed;

  /// Тип связи «можно» в форме создания
  ///
  /// In en, this message translates to:
  /// **'Can'**
  String get relationEditorTypeCan;

  /// Подпись выбора приоритета связи
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get relationEditorPriorityLabel;

  /// Подпись описания создаваемой связи
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get relationEditorDescriptionLabel;

  /// Превышение предела описания связи
  ///
  /// In en, this message translates to:
  /// **'Use no more than 4096 characters.'**
  String get relationEditorDescriptionTooLong;

  /// Недопустимый Unicode в описании связи
  ///
  /// In en, this message translates to:
  /// **'Enter valid Unicode text without NUL.'**
  String get relationEditorDescriptionInvalidUnicode;

  /// Отказ создания связи намерения с самим собой
  ///
  /// In en, this message translates to:
  /// **'An intention can’t be related to itself.'**
  String get relationEditorCreateSameParticipants;

  /// Объяснение недостающего обязательного выбора
  ///
  /// In en, this message translates to:
  /// **'To create the relation, provide:'**
  String get relationEditorMissingTitle;

  /// Недостающий исходный участник связи
  ///
  /// In en, this message translates to:
  /// **'the source intention'**
  String get relationEditorMissingSource;

  /// Недостающий связанный участник связи
  ///
  /// In en, this message translates to:
  /// **'the related intention'**
  String get relationEditorMissingRelated;

  /// Недостающий тип связи
  ///
  /// In en, this message translates to:
  /// **'the relation type'**
  String get relationEditorMissingType;

  /// Недостающий приоритет связи
  ///
  /// In en, this message translates to:
  /// **'a priority from P1 to P4'**
  String get relationEditorMissingPriority;

  /// Переход к связи, занявшей направленную пару
  ///
  /// In en, this message translates to:
  /// **'Open the existing relation'**
  String get relationEditorOpenExistingRelation;

  /// Команда создания долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Create relation'**
  String get relationEditorSubmitAction;

  /// Выполняемое создание долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Creating…'**
  String get relationEditorCreating;

  /// Создание связи из исходящей группы соседства
  ///
  /// In en, this message translates to:
  /// **'Create an outgoing relation'**
  String get relationNeighborhoodCreateOutgoingAction;

  /// Создание связи из входящей группы соседства
  ///
  /// In en, this message translates to:
  /// **'Create an incoming relation'**
  String get relationNeighborhoodCreateIncomingAction;

  /// Вариант приоритета P1–P4 в форме создания связи
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String relationEditorPriorityOption(String priority);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
