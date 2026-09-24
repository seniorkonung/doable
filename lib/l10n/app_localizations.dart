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

  /// No description provided for @relationNeighborhoodSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'Selected relations: {count}'**
  String relationNeighborhoodSelectedCount(int count);

  /// Действие выбора конкретной блокирующей связи
  ///
  /// In en, this message translates to:
  /// **'Add to selection'**
  String get relationNeighborhoodAddToSelection;

  /// Действие снятия выбора конкретной блокирующей связи
  ///
  /// In en, this message translates to:
  /// **'Remove from selection'**
  String get relationNeighborhoodRemoveFromSelection;

  /// Открыть полный набор выбранных связей для подтверждения
  ///
  /// In en, this message translates to:
  /// **'Review selected relations'**
  String get blockingRelationsReviewAction;

  /// Заголовок подтверждения массового удаления
  ///
  /// In en, this message translates to:
  /// **'Delete selected relations permanently?'**
  String get blockingRelationsConfirmationTitle;

  /// Необратимость удаления связей и сохранность намерения
  ///
  /// In en, this message translates to:
  /// **'Review every selected relation. This can’t be undone. The intention will remain; deleting it requires separate confirmation.'**
  String get blockingRelationsConfirmationWarning;

  /// Число связей в подтверждённом наборе
  ///
  /// In en, this message translates to:
  /// **'To delete: {count}'**
  String blockingRelationsConfirmationCount(int count);

  /// Идентификатор участника для различения одноимённых намерений
  ///
  /// In en, this message translates to:
  /// **'Identifier: {id}'**
  String blockingRelationsParticipantId(String id);

  /// Состояние принятого массового удаления
  ///
  /// In en, this message translates to:
  /// **'Deleting selected relations…'**
  String get blockingRelationsDeleting;

  /// Отказ при занятом намерении или выбранной связи
  ///
  /// In en, this message translates to:
  /// **'Another change to these relations or the intention is already running.'**
  String get blockingRelationsBusy;

  /// Отказ при завершении работы приложения
  ///
  /// In en, this message translates to:
  /// **'The app is closing. The change was not accepted.'**
  String get blockingRelationsDraining;

  /// Вернуться к сохранённому выбору после ошибки
  ///
  /// In en, this message translates to:
  /// **'Return to selection'**
  String get blockingRelationsEditSelectionAction;

  /// Явная актуализация выбранного набора после конфликта или перед просмотром
  ///
  /// In en, this message translates to:
  /// **'Refresh selection'**
  String get blockingRelationsRefreshSelectionAction;

  /// Состояние проверки выбранных связей
  ///
  /// In en, this message translates to:
  /// **'Checking selected relations…'**
  String get blockingRelationsRefreshingSelection;

  /// Идентификатор недоступной выбранной связи
  ///
  /// In en, this message translates to:
  /// **'Relation: {id}'**
  String blockingRelationsInvalidSelectedRelationId(String id);

  /// Причина устаревания выбранной связи: удалена
  ///
  /// In en, this message translates to:
  /// **'This relation no longer exists. Remove it from the selection and confirm the remaining set again.'**
  String get blockingRelationsInvalidMissing;

  /// Причина устаревания выбранной связи: заменён участник
  ///
  /// In en, this message translates to:
  /// **'This relation no longer belongs to this intention. Remove it from the selection and confirm the remaining set again.'**
  String get blockingRelationsInvalidMoved;

  /// Защита выбранной связи сохранённым дневным путём
  ///
  /// In en, this message translates to:
  /// **'This relation is used in a saved daily path. First delete the daily choice separately, then select and confirm deletion of the freed long-term relation again. The entire selected set remains unchanged.'**
  String get blockingRelationsInvalidProtected;

  /// Безопасное отсутствие намерения при проверке выбора
  ///
  /// In en, this message translates to:
  /// **'This intention no longer exists. Its relations cannot be deleted here.'**
  String get blockingRelationsRefreshIntentionNotFound;

  /// Устранимая ошибка чтения выбранного набора
  ///
  /// In en, this message translates to:
  /// **'Selected relations could not be checked. Your selection is unchanged; try checking again.'**
  String get blockingRelationsRefreshUnavailable;

  /// Повреждение данных при чтении выбранного набора
  ///
  /// In en, this message translates to:
  /// **'Selected relations could not be checked because the data is damaged. Deletion was not started.'**
  String get blockingRelationsRefreshCorruption;

  /// Неожиданная ошибка чтения выбранного набора
  ///
  /// In en, this message translates to:
  /// **'Selected relations could not be checked. Deletion was not started.'**
  String get blockingRelationsRefreshUnexpected;

  /// Конфликт массового удаления: выбранная связь отсутствует
  ///
  /// In en, this message translates to:
  /// **'A selected relation no longer exists. Refresh the selection and confirm it again.'**
  String get blockingRelationsDeleteMissing;

  /// Конфликт массового удаления: связь сменила участников
  ///
  /// In en, this message translates to:
  /// **'A selected relation no longer belongs to this intention. Refresh the selection and confirm it again.'**
  String get blockingRelationsDeleteMoved;

  /// Конфликт массового удаления: связь заблокирована
  ///
  /// In en, this message translates to:
  /// **'A selected relation is now used in a saved daily path. The entire set remains unchanged. First delete the daily choice separately, then select and confirm deletion of the freed long-term relation again.'**
  String get blockingRelationsDeleteProhibited;

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

  /// No description provided for @relationNeighborhoodDailyTotal.
  ///
  /// In en, this message translates to:
  /// **'Daily choices: {count}'**
  String relationNeighborhoodDailyTotal(int count);

  /// Роль намерения как источника дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Source intention'**
  String get relationNeighborhoodDailySourceRole;

  /// Роль намерения как выбранного действия
  ///
  /// In en, this message translates to:
  /// **'Selected action'**
  String get relationNeighborhoodDailySelectedRole;

  /// Подпись групп долговременных связей в соседстве
  ///
  /// In en, this message translates to:
  /// **'Long-term relations'**
  String get relationNeighborhoodLongTermGroups;

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

  /// Вид массовой операции в сообщении оболочки
  ///
  /// In en, this message translates to:
  /// **'Delete selected relations'**
  String get graphOperationDeleteBlockingRelations;

  /// Успешное массовое удаление выбранных связей
  ///
  /// In en, this message translates to:
  /// **'Selected relations deleted.'**
  String get blockingRelationsDeleted;

  /// Намерение исчезло до массового удаления
  ///
  /// In en, this message translates to:
  /// **'This intention no longer exists. Relations weren’t deleted.'**
  String get blockingRelationsDeleteIntentionNotFound;

  /// Устаревший набор массового удаления
  ///
  /// In en, this message translates to:
  /// **'The selected relations changed. Refresh the selection and confirm again.'**
  String get blockingRelationsDeleteConflict;

  /// Временная недоступность массового удаления
  ///
  /// In en, this message translates to:
  /// **'Selected relations couldn’t be deleted. Try again.'**
  String get blockingRelationsDeleteUnavailable;

  /// Повреждение данных при массовом удалении
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. Selected relations weren’t deleted.'**
  String get blockingRelationsDeleteCorruption;

  /// Непредвиденная ошибка массового удаления
  ///
  /// In en, this message translates to:
  /// **'Selected relations couldn’t be deleted because of an unexpected error.'**
  String get blockingRelationsDeleteUnexpected;

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

  /// Безопасное обозначение дневного выбора в сообщении операции
  ///
  /// In en, this message translates to:
  /// **'daily choice'**
  String get graphOperationDailyChoice;

  /// Подтверждение создания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice created.'**
  String get dailyChoiceCreated;

  /// Подтверждение изменения дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice updated.'**
  String get dailyChoiceUpdated;

  /// Подтверждение замены пути дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice path replaced.'**
  String get dailyChoicePathReplaced;

  /// Подтверждение удаления дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice deleted.'**
  String get dailyChoiceDeleted;

  /// Открытие отдельного подтверждения удаления дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Delete daily choice permanently'**
  String get dailyChoiceDeleteAction;

  /// Заголовок отдельного подтверждения удаления дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Delete daily choice permanently?'**
  String get dailyChoiceDeleteConfirmationTitle;

  /// Конкретный выбор, дата, идентификатор и необратимость удаления
  ///
  /// In en, this message translates to:
  /// **'Choice: {phrase}\nDate: {date}\nChoice ID: {choiceId}\n\nThis cannot be undone. Intentions, long-term relations, and other daily choices will remain.'**
  String dailyChoiceDeleteConfirmationMessage(
    String phrase,
    String date,
    String choiceId,
  );

  /// Отправить подтверждённое удаление дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get dailyChoiceDeleteConfirmAction;

  /// Ошибка исходного намерения дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Check the source intention of the daily choice.'**
  String get dailyChoiceSourceInvalid;

  /// Ошибка выбранного намерения дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Check the selected intention of the daily choice.'**
  String get dailyChoiceSelectedInvalid;

  /// Ошибка даты дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Check the daily choice date.'**
  String get dailyChoiceDateInvalid;

  /// Ошибка описания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Check the daily choice description.'**
  String get dailyChoiceDescriptionInvalid;

  /// Ошибка пути дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Check the daily choice path.'**
  String get dailyChoicePathInvalid;

  /// Дневной выбор отсутствует при выполнении команды
  ///
  /// In en, this message translates to:
  /// **'This daily choice no longer exists.'**
  String get dailyChoiceOperationNotFound;

  /// Конфликт актуальности дневного выбора
  ///
  /// In en, this message translates to:
  /// **'The data changed. Refresh it and confirm again.'**
  String get dailyChoiceOperationConflict;

  /// Временная недоступность дневной команды
  ///
  /// In en, this message translates to:
  /// **'Could not complete the daily choice operation. Try again.'**
  String get dailyChoiceOperationUnavailable;

  /// Повреждение данных дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The daily choice was not changed.'**
  String get dailyChoiceOperationCorruption;

  /// Неожиданный отказ команды дневного выбора
  ///
  /// In en, this message translates to:
  /// **'The daily choice operation failed because of an unexpected error.'**
  String get dailyChoiceOperationUnexpected;

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

  /// Конфликт изменения смысла используемой дневным путём связи
  ///
  /// In en, this message translates to:
  /// **'This relation is used by a saved daily path. Its type and participants can’t be changed.'**
  String get relationEditorUpdateReferencedByDailyPath;

  /// Ограничение смысла связи сохранённым дневным путём
  ///
  /// In en, this message translates to:
  /// **'This relation is used in a saved daily path. Its type and participants cannot be changed. Its description and priority remain editable.'**
  String get relationEditorPathProtection;

  /// Исправление черновика при новом ограничении пути
  ///
  /// In en, this message translates to:
  /// **'This relation is used in a saved daily path. Restore the original type and participants to save description and priority changes.'**
  String get relationEditorPathProtectionWithDraft;

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

  /// Подтверждение успешного архивирования долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Relation archived.'**
  String get relationArchived;

  /// Отсутствие архивируемой связи
  ///
  /// In en, this message translates to:
  /// **'This relation no longer exists.'**
  String get relationArchiveNotFound;

  /// Конфликт актуального состояния при архивировании связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be archived because its current state conflicts with the operation.'**
  String get relationArchiveConflict;

  /// Устранимая недоступность архивирования связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be archived. Try again.'**
  String get relationArchiveUnavailable;

  /// Терминальное повреждение данных при архивировании связи
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The relation wasn’t archived.'**
  String get relationArchiveCorruption;

  /// Терминальная непредвиденная ошибка архивирования связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be archived because of an unexpected error.'**
  String get relationArchiveUnexpected;

  /// Подтверждение успешного восстановления долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Relation restored.'**
  String get relationRestored;

  /// Отсутствие восстанавливаемой связи
  ///
  /// In en, this message translates to:
  /// **'This relation no longer exists.'**
  String get relationRestoreNotFound;

  /// Конфликт актуального состояния при восстановлении связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be restored because its current state conflicts with the operation.'**
  String get relationRestoreConflict;

  /// Отсутствие исходного участника при восстановлении связи
  ///
  /// In en, this message translates to:
  /// **'The source intention no longer exists. The relation wasn’t restored.'**
  String get relationRestoreSourceNotFound;

  /// Отсутствие связанного участника при восстановлении связи
  ///
  /// In en, this message translates to:
  /// **'The related intention no longer exists. The relation wasn’t restored.'**
  String get relationRestoreRelatedNotFound;

  /// Архивное состояние исходного участника при восстановлении связи
  ///
  /// In en, this message translates to:
  /// **'Restore the source intention before restoring this relation.'**
  String get relationRestoreSourceArchived;

  /// Архивное состояние связанного участника при восстановлении связи
  ///
  /// In en, this message translates to:
  /// **'Restore the related intention before restoring this relation.'**
  String get relationRestoreRelatedArchived;

  /// Устранимая недоступность восстановления связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be restored. Try again.'**
  String get relationRestoreUnavailable;

  /// Терминальное повреждение данных при восстановлении связи
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The relation wasn’t restored.'**
  String get relationRestoreCorruption;

  /// Терминальная непредвиденная ошибка восстановления связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be restored because of an unexpected error.'**
  String get relationRestoreUnexpected;

  /// Подтверждение успешного физического удаления долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Relation deleted.'**
  String get relationDeleted;

  /// Отсутствие удаляемой связи
  ///
  /// In en, this message translates to:
  /// **'This relation no longer exists.'**
  String get relationDeleteNotFound;

  /// Конфликт актуального состояния при удалении связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be deleted because its current state conflicts with the operation.'**
  String get relationDeleteConflict;

  /// Конфликт удаления используемой дневным путём связи
  ///
  /// In en, this message translates to:
  /// **'This relation is used by a saved daily path. Delete or replace the daily choices that use it first.'**
  String get relationDeleteReferencedByDailyPath;

  /// Устранимая недоступность удаления связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be deleted. Try again.'**
  String get relationDeleteUnavailable;

  /// Терминальное повреждение данных при удалении связи
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The relation wasn’t deleted.'**
  String get relationDeleteCorruption;

  /// Терминальная непредвиденная ошибка удаления связи
  ///
  /// In en, this message translates to:
  /// **'The relation couldn’t be deleted because of an unexpected error.'**
  String get relationDeleteUnexpected;

  /// Назначение перехода из строки соседства в подробный просмотр связи
  ///
  /// In en, this message translates to:
  /// **'Opens the relation details'**
  String get relationNeighborhoodOpenRelation;

  /// Назначение перехода к полному пути дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Open the full saved daily path'**
  String get relationNeighborhoodOpenDailyChoice;

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

  /// Переход из подробного просмотра к изменению связи
  ///
  /// In en, this message translates to:
  /// **'Edit relation'**
  String get relationDetailsEditAction;

  /// Действие самостоятельного архивирования связи
  ///
  /// In en, this message translates to:
  /// **'Archive relation'**
  String get relationDetailsArchiveAction;

  /// Действие самостоятельного восстановления связи
  ///
  /// In en, this message translates to:
  /// **'Restore relation'**
  String get relationDetailsRestoreAction;

  /// Действие начала физического удаления конкретной долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Delete relation permanently'**
  String get relationDetailsDeleteAction;

  /// Причина недоступности удаления связи в подробностях
  ///
  /// In en, this message translates to:
  /// **'This relation is used in a saved daily path. It cannot be deleted, and its type and participants cannot be changed. Its description, priority, and archive state remain editable.'**
  String get relationDetailsPathProtection;

  /// Неизвестные разрешения на удаление связи
  ///
  /// In en, this message translates to:
  /// **'Deletion is unavailable until this relation’s dependencies are confirmed.'**
  String get relationDetailsDeletionChecking;

  /// Заголовок подтверждения необратимого удаления конкретной связи
  ///
  /// In en, this message translates to:
  /// **'Delete relation permanently?'**
  String get relationDetailsDeleteConfirmationTitle;

  /// Контекст и объяснение необратимости удаления конкретной связи
  ///
  /// In en, this message translates to:
  /// **'Relation: {phrase}\nSource intention: {sourceTitle}\nRelated intention: {relatedTitle}\nRelation state: {scope}\n\nThis can’t be undone. Both intentions and all other relations will remain.'**
  String relationDetailsDeleteConfirmationMessage(
    String phrase,
    String sourceTitle,
    String relatedTitle,
    String scope,
  );

  /// Явное подтверждение физического удаления конкретной связи
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get relationDetailsConfirmDeleteAction;

  /// Переход к архивному исходному участнику, блокирующему восстановление связи
  ///
  /// In en, this message translates to:
  /// **'Open source intention'**
  String get relationDetailsOpenSourceParticipantAction;

  /// Переход к архивному связанному участнику, блокирующему восстановление связи
  ///
  /// In en, this message translates to:
  /// **'Open related intention'**
  String get relationDetailsOpenRelatedParticipantAction;

  /// Заголовок выбора участника долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Select a participant'**
  String get participantPickerTitle;

  /// Заголовок выбора действия для нижнего обхода
  ///
  /// In en, this message translates to:
  /// **'Select an action'**
  String get actionPickerTitle;

  /// Отмена выбора действия
  ///
  /// In en, this message translates to:
  /// **'Cancel action selection'**
  String get actionPickerCancel;

  /// Чтение первой порции действий
  ///
  /// In en, this message translates to:
  /// **'Loading actions…'**
  String get actionPickerLoading;

  /// Пустой выбор активных действий
  ///
  /// In en, this message translates to:
  /// **'No active actions are available.'**
  String get actionPickerEmpty;

  /// Пустой результат поиска действий по названию
  ///
  /// In en, this message translates to:
  /// **'No actions match this title.'**
  String get actionPickerNoMatches;

  /// Устранимый отказ чтения действий
  ///
  /// In en, this message translates to:
  /// **'Actions couldn’t be loaded. Try again.'**
  String get actionPickerUnavailable;

  /// Повреждённые данные действий
  ///
  /// In en, this message translates to:
  /// **'Saved action data is damaged and can’t be shown.'**
  String get actionPickerCorruption;

  /// Непредвиденный отказ чтения действий
  ///
  /// In en, this message translates to:
  /// **'Actions couldn’t be loaded because of an unexpected error.'**
  String get actionPickerUnexpected;

  /// Семантическая подсказка выбора действия
  ///
  /// In en, this message translates to:
  /// **'Selects this action to find its reason'**
  String get actionPickerSelectHint;

  /// Переход к подробностям действия
  ///
  /// In en, this message translates to:
  /// **'Open action details'**
  String get actionPickerOpenDetails;

  /// Точное количество доступных действий
  ///
  /// In en, this message translates to:
  /// **'Total actions: {count}'**
  String actionPickerTotalCount(int count);

  /// Заголовок выбора нового основания
  ///
  /// In en, this message translates to:
  /// **'Select a reason'**
  String get sourcePickerTitle;

  /// Отмена выбора основания
  ///
  /// In en, this message translates to:
  /// **'Cancel reason selection'**
  String get sourcePickerCancel;

  /// Чтение первой порции намерений
  ///
  /// In en, this message translates to:
  /// **'Loading intentions…'**
  String get sourcePickerLoading;

  /// Пустой выбор активных оснований
  ///
  /// In en, this message translates to:
  /// **'No active intentions are available.'**
  String get sourcePickerEmpty;

  /// Пустой результат буквального фильтра
  ///
  /// In en, this message translates to:
  /// **'No intentions match this title.'**
  String get sourcePickerNoMatches;

  /// Устранимый отказ чтения намерений
  ///
  /// In en, this message translates to:
  /// **'Intentions couldn’t be loaded. Try again.'**
  String get sourcePickerUnavailable;

  /// Повреждённые данные намерений
  ///
  /// In en, this message translates to:
  /// **'Saved intention data is damaged and can’t be shown.'**
  String get sourcePickerCorruption;

  /// Непредвиденный отказ чтения намерений
  ///
  /// In en, this message translates to:
  /// **'Intentions couldn’t be loaded because of an unexpected error.'**
  String get sourcePickerUnexpected;

  /// Семантическая подсказка выбора основания
  ///
  /// In en, this message translates to:
  /// **'Selects this intention as the new reason'**
  String get sourcePickerSelectHint;

  /// Переход к подробностям намерения
  ///
  /// In en, this message translates to:
  /// **'Open intention details'**
  String get sourcePickerOpenDetails;

  /// Число доступных активных намерений
  ///
  /// In en, this message translates to:
  /// **'Total intentions: {count}'**
  String sourcePickerTotalCount(int count);

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

  /// Заголовок формы изменения долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Edit relation'**
  String get relationEditorEditTitle;

  /// Доступная подпись текущей формулировки связи
  ///
  /// In en, this message translates to:
  /// **'Relation phrase'**
  String get relationEditorPhraseLabel;

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

  /// Команда сохранения изменений долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get relationEditorSaveAction;

  /// Выполняемое изменение долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get relationEditorSaving;

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

  /// Открыть верхний обход из активного намерения
  ///
  /// In en, this message translates to:
  /// **'Choose an action along a path'**
  String get detailsChoosePathAction;

  /// Заголовок верхнего обхода
  ///
  /// In en, this message translates to:
  /// **'Choose a path to an action'**
  String get choicePathTitle;

  /// Заголовок нижнего обхода
  ///
  /// In en, this message translates to:
  /// **'Choose a source for the action'**
  String get choicePathBottomTitle;

  /// Порядок нижнего обхода
  ///
  /// In en, this message translates to:
  /// **'Exploration: from the action to a source'**
  String get choicePathBottomTraversal;

  /// Направление связей нижнего пути
  ///
  /// In en, this message translates to:
  /// **'Relation direction: from the source to the action'**
  String get choicePathBottomPathDirection;

  /// Фиксированное действие нижнего обхода
  ///
  /// In en, this message translates to:
  /// **'Selected action: {action}'**
  String choicePathFixedAction(String action);

  /// Загрузка действия нижнего обхода
  ///
  /// In en, this message translates to:
  /// **'Loading the selected action…'**
  String get choicePathActionPending;

  /// Достигнутое основание нижнего пути
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String choicePathCurrentSource(String source);

  /// Состояние подтверждения основания
  ///
  /// In en, this message translates to:
  /// **'Source confirmed'**
  String get choicePathSourceSelected;

  /// Явное подтверждение основания
  ///
  /// In en, this message translates to:
  /// **'Confirm source “{source}”'**
  String choicePathSelectSource(String source);

  /// У выбранного действия нет входящего пути
  ///
  /// In en, this message translates to:
  /// **'There are no valid incoming relations for this action right now. Choose another action.'**
  String get choicePathBottomNoPath;

  /// Направление верхнего обхода
  ///
  /// In en, this message translates to:
  /// **'Path from the source intention to an action'**
  String get choicePathDirection;

  /// Исходное намерение пути
  ///
  /// In en, this message translates to:
  /// **'Source intention: {source}'**
  String choicePathSource(String source);

  /// Загрузка исходного намерения
  ///
  /// In en, this message translates to:
  /// **'Loading the source intention…'**
  String get choicePathSourcePending;

  /// Возврат к выбранному префиксу пути
  ///
  /// In en, this message translates to:
  /// **'Return to “{source}”'**
  String choicePathReturnTo(String source);

  /// Семантика направленного шага пути
  ///
  /// In en, this message translates to:
  /// **'Step {index}: {phrase}. Priority {priority}'**
  String choicePathStepSemantics(int index, String phrase, String priority);

  /// Состояние выбора достигнутого действия
  ///
  /// In en, this message translates to:
  /// **'Action selected'**
  String get choicePathActionSelected;

  /// Выбрать достигнутое действие
  ///
  /// In en, this message translates to:
  /// **'Choose action “{action}”'**
  String choicePathSelectAction(String action);

  /// Выбор действия ещё не создаёт дневную связь
  ///
  /// In en, this message translates to:
  /// **'The daily choice has not been created yet.'**
  String get choicePathSelectionNotSaved;

  /// Заголовок допустимых продолжений
  ///
  /// In en, this message translates to:
  /// **'Available continuations'**
  String get choicePathContinuations;

  /// Загрузка допустимых продолжений
  ///
  /// In en, this message translates to:
  /// **'Checking available continuations…'**
  String get choicePathLoading;

  /// Из исходного намерения нет допустимого пути
  ///
  /// In en, this message translates to:
  /// **'There is no valid path from this intention to another action right now.'**
  String get choicePathNoPath;

  /// У достигнутого шага нет продолжений
  ///
  /// In en, this message translates to:
  /// **'There are no further valid continuations.'**
  String get choicePathNoFurtherPath;

  /// Устаревший префикс пути
  ///
  /// In en, this message translates to:
  /// **'The graph has changed. Refresh the path before continuing.'**
  String get choicePathConflict;

  /// Актуализировать путь после конфликта
  ///
  /// In en, this message translates to:
  /// **'Refresh path'**
  String get choicePathRefresh;

  /// Намерение пути отсутствует
  ///
  /// In en, this message translates to:
  /// **'An intention on this path no longer exists.'**
  String get choicePathNotFound;

  /// Недопустимый запрос продолжений
  ///
  /// In en, this message translates to:
  /// **'Continuations could not be checked because of an invalid request.'**
  String get choicePathInvalid;

  /// Временная недоступность продолжений
  ///
  /// In en, this message translates to:
  /// **'Continuations are temporarily unavailable. Try again.'**
  String get choicePathUnavailable;

  /// Повреждение данных пути
  ///
  /// In en, this message translates to:
  /// **'Saved path data is damaged. Continuation is unavailable.'**
  String get choicePathCorruption;

  /// Неизвестная ошибка чтения продолжений
  ///
  /// In en, this message translates to:
  /// **'Continuations could not be checked because of an unexpected error.'**
  String get choicePathUnexpected;

  /// Загрузить следующую порцию продолжений
  ///
  /// In en, this message translates to:
  /// **'Show more continuations'**
  String get choicePathLoadMore;

  /// Загрузка следующей порции продолжений
  ///
  /// In en, this message translates to:
  /// **'Loading the next page…'**
  String get choicePathLoadingMore;

  /// Доступная связь для следующего шага
  ///
  /// In en, this message translates to:
  /// **'Continue along relation: {phrase}. Priority {priority}'**
  String choicePathContinueSemantics(String phrase, String priority);

  /// Заголовок подтверждения дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Confirm daily choice'**
  String get dailyChoiceCreationTitle;

  /// Заголовок каталога дневных выборов и вход из основной навигации
  ///
  /// In en, this message translates to:
  /// **'Daily choices'**
  String get dailyChoiceCatalogTitle;

  /// Вход в создание дневного выбора от действия
  ///
  /// In en, this message translates to:
  /// **'Create a choice from an action'**
  String get dailyChoiceCreateFromAction;

  /// Начальная загрузка дневного каталога
  ///
  /// In en, this message translates to:
  /// **'Loading daily choices…'**
  String get dailyChoiceCatalogLoading;

  /// Фильтр по календарной дате
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dailyChoiceCatalogDateFilter;

  /// Применить фильтр даты
  ///
  /// In en, this message translates to:
  /// **'Apply date'**
  String get dailyChoiceCatalogApplyDate;

  /// Некорректная дата фильтра
  ///
  /// In en, this message translates to:
  /// **'Enter a valid date as YYYY-MM-DD.'**
  String get dailyChoiceCatalogDateInvalid;

  /// Фильтр по выполнению
  ///
  /// In en, this message translates to:
  /// **'Completion'**
  String get dailyChoiceCatalogCompletionFilter;

  /// Оба состояния выполнения
  ///
  /// In en, this message translates to:
  /// **'All states'**
  String get dailyChoiceCatalogAllStates;

  /// Фильтр невыполненных выборов
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get dailyChoiceCatalogIncomplete;

  /// Фильтр выполненных выборов
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get dailyChoiceCatalogCompleted;

  /// Вернуть все даты и оба состояния выполнения
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get dailyChoiceCatalogClearFilters;

  /// Полное количество подходящих дневных выборов
  ///
  /// In en, this message translates to:
  /// **'Total daily choices: {count}'**
  String dailyChoiceCatalogTotalCount(int count);

  /// Пустой дневной каталог
  ///
  /// In en, this message translates to:
  /// **'No daily choices match the filters.'**
  String get dailyChoiceCatalogEmpty;

  /// Обновление подтверждённого снимка каталога
  ///
  /// In en, this message translates to:
  /// **'Refreshing daily choices…'**
  String get dailyChoiceCatalogRefreshing;

  /// Загрузка следующей порции
  ///
  /// In en, this message translates to:
  /// **'Loading more daily choices…'**
  String get dailyChoiceCatalogLoadingMore;

  /// Открыть следующую порцию
  ///
  /// In en, this message translates to:
  /// **'Show more daily choices'**
  String get dailyChoiceCatalogLoadMore;

  /// Временная ошибка чтения дневного каталога
  ///
  /// In en, this message translates to:
  /// **'Could not load daily choices. Try again.'**
  String get dailyChoiceCatalogUnavailable;

  /// Повреждение данных дневного каталога
  ///
  /// In en, this message translates to:
  /// **'Stored daily choice data is damaged and cannot be shown.'**
  String get dailyChoiceCatalogCorruption;

  /// Устаревший снимок каталога
  ///
  /// In en, this message translates to:
  /// **'The catalog changed. Refresh it to continue.'**
  String get dailyChoiceCatalogExpired;

  /// Недопустимая позиция каталога
  ///
  /// In en, this message translates to:
  /// **'The catalog position is no longer valid.'**
  String get dailyChoiceCatalogInvalid;

  /// Непредвиденная ошибка чтения дневного каталога
  ///
  /// In en, this message translates to:
  /// **'Could not load daily choices because of an unexpected error.'**
  String get dailyChoiceCatalogUnexpected;

  /// Доступная подпись строки с порядковым номером текущей выдачи
  ///
  /// In en, this message translates to:
  /// **'Choice #{number}. {phrase}. {date}. {completion}'**
  String dailyChoiceCatalogRowLabel(
    int number,
    String phrase,
    String date,
    String completion,
  );

  /// Заголовок подробностей дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice'**
  String get dailyChoiceDetailsTitle;

  /// Заголовок редактора дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Edit daily choice'**
  String get dailyChoiceEditTitle;

  /// Сохранение правок дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get dailyChoiceEditSave;

  /// Возврат к актуальным подробностям после конфликта
  ///
  /// In en, this message translates to:
  /// **'Return to details and refresh'**
  String get dailyChoiceEditRefresh;

  /// Загрузка подробностей дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Loading daily choice…'**
  String get dailyChoiceDetailsLoading;

  /// Дневной выбор отсутствует
  ///
  /// In en, this message translates to:
  /// **'This daily choice no longer exists.'**
  String get dailyChoiceDetailsNotFound;

  /// Временный отказ чтения дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Could not load this daily choice. Try again.'**
  String get dailyChoiceDetailsUnavailable;

  /// Повреждённый сохранённый путь
  ///
  /// In en, this message translates to:
  /// **'The stored path is damaged and cannot be shown.'**
  String get dailyChoiceDetailsCorruption;

  /// Неизвестный отказ чтения дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Could not load this daily choice because of an unexpected error.'**
  String get dailyChoiceDetailsUnexpected;

  /// Формулировка дневной связи из текущих названий
  ///
  /// In en, this message translates to:
  /// **'To {source}, today I {selected}'**
  String dailyChoiceDetailsPhrase(String source, String selected);

  /// Дата дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice date: {date}'**
  String dailyChoiceDetailsDate(String date);

  /// Дневной выбор выполнен
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get dailyChoiceDetailsCompleted;

  /// Дневной выбор не выполнен
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get dailyChoiceDetailsNotCompleted;

  /// Описание дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get dailyChoiceDetailsDescription;

  /// Заголовок сохранённого пути
  ///
  /// In en, this message translates to:
  /// **'Stored path'**
  String get dailyChoiceDetailsPath;

  /// Роль исходного намерения
  ///
  /// In en, this message translates to:
  /// **'Source intention'**
  String get dailyChoiceDetailsSource;

  /// Роль промежуточного намерения
  ///
  /// In en, this message translates to:
  /// **'Intermediate intention'**
  String get dailyChoiceDetailsIntermediate;

  /// Роль конечного выбранного действия
  ///
  /// In en, this message translates to:
  /// **'Selected action'**
  String get dailyChoiceDetailsSelectedAction;

  /// Архивное состояние участника или связи
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get dailyChoiceDetailsArchived;

  /// Активное состояние участника или связи
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get dailyChoiceDetailsActive;

  /// Готовность конечного действия
  ///
  /// In en, this message translates to:
  /// **'Ready for action'**
  String get dailyChoiceDetailsReady;

  /// Утрата готовности конечного действия
  ///
  /// In en, this message translates to:
  /// **'Not ready for action'**
  String get dailyChoiceDetailsNotReady;

  /// Порядковый номер перехода пути
  ///
  /// In en, this message translates to:
  /// **'Transition {number}'**
  String dailyChoiceDetailsStep(int number);

  /// Заголовок подтверждаемого пути
  ///
  /// In en, this message translates to:
  /// **'Path to confirm'**
  String get dailyChoiceCreationPath;

  /// Конечное выбранное действие
  ///
  /// In en, this message translates to:
  /// **'Selected action: {action}'**
  String dailyChoiceCreationAction(String action);

  /// Подпись даты выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice date'**
  String get dailyChoiceCreationDate;

  /// Подсказка полного диапазона дат
  ///
  /// In en, this message translates to:
  /// **'Enter YYYY-MM-DD (0001–9999)'**
  String get dailyChoiceCreationDateHint;

  /// Подпись необязательного описания
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get dailyChoiceCreationDescription;

  /// Явная отметка выполнения
  ///
  /// In en, this message translates to:
  /// **'Already completed'**
  String get dailyChoiceCreationCompleted;

  /// Пояснение отметки выполнения
  ///
  /// In en, this message translates to:
  /// **'Mark if the action was already done for this date'**
  String get dailyChoiceCreationCompletedHint;

  /// Подтверждение сохранения выбора
  ///
  /// In en, this message translates to:
  /// **'Save daily choice'**
  String get dailyChoiceCreationSave;

  /// Сохранение выбора выполняется
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get dailyChoiceCreationSaving;

  /// Отмена без изменения графа
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dailyChoiceCreationCancel;

  /// Возврат к актуализации пути после конфликта
  ///
  /// In en, this message translates to:
  /// **'Return to the path and refresh it'**
  String get dailyChoiceCreationRefreshPath;

  /// Заголовок отдельного подтверждения замены пути
  ///
  /// In en, this message translates to:
  /// **'Confirm path replacement'**
  String get dailyChoiceReplaceTitle;

  /// Подготовка подтверждения после чтения выбора
  ///
  /// In en, this message translates to:
  /// **'Preparing the new path confirmation…'**
  String get dailyChoiceReplacePreparing;

  /// Заменяемый дневной выбор
  ///
  /// In en, this message translates to:
  /// **'Daily choice to replace'**
  String get dailyChoiceReplaceCurrent;

  /// Заголовок полного предлагаемого пути
  ///
  /// In en, this message translates to:
  /// **'New path from source to action'**
  String get dailyChoiceReplaceNewPath;

  /// Пустое описание заменяемого выбора
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get dailyChoiceReplaceNoDescription;

  /// Независимые поля не меняются при замене пути
  ///
  /// In en, this message translates to:
  /// **'The date, description, and completion will stay unchanged when the path is replaced.'**
  String get dailyChoiceReplaceFieldsPreserved;

  /// Сохранение выполнения при смене действия
  ///
  /// In en, this message translates to:
  /// **'Completion stays on even if a different action is selected.'**
  String get dailyChoiceReplaceCompletionPreserved;

  /// Явное подтверждение только замены пути
  ///
  /// In en, this message translates to:
  /// **'Replace path only'**
  String get dailyChoiceReplaceConfirm;

  /// Ожидание результата команды замены
  ///
  /// In en, this message translates to:
  /// **'Replacing path…'**
  String get dailyChoiceReplaceSubmitting;

  /// Возврат к выбору нового пути после конфликта
  ///
  /// In en, this message translates to:
  /// **'Return to path selection'**
  String get dailyChoiceReplaceChooseAgain;

  /// Переход от выбранного действия к форме подтверждения
  ///
  /// In en, this message translates to:
  /// **'Continue to choice confirmation'**
  String get choicePathOpenConfirmation;

  /// Заголовок подсказок прежних маршрутов
  ///
  /// In en, this message translates to:
  /// **'Previous routes'**
  String get choiceSuggestionTitle;

  /// Начальная загрузка подсказок
  ///
  /// In en, this message translates to:
  /// **'Loading previous route suggestions…'**
  String get choiceSuggestionLoading;

  /// Подтверждённо пустая выдача подсказок
  ///
  /// In en, this message translates to:
  /// **'No previous routes for this participant.'**
  String get choiceSuggestionEmpty;

  /// Обновление подсказок перед выбором
  ///
  /// In en, this message translates to:
  /// **'Refreshing suggestions. Route selection is temporarily unavailable.'**
  String get choiceSuggestionUpdating;

  /// Отсутствие выбранного участника
  ///
  /// In en, this message translates to:
  /// **'The selected intention no longer exists.'**
  String get choiceSuggestionNotFound;

  /// Временная недоступность подсказок
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load suggestions. Try again.'**
  String get choiceSuggestionUnavailable;

  /// Повреждение данных подсказок
  ///
  /// In en, this message translates to:
  /// **'Stored suggestion data is damaged and can’t be confirmed.'**
  String get choiceSuggestionCorruption;

  /// Непредвиденная ошибка подсказок
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load suggestions because of an unexpected error.'**
  String get choiceSuggestionUnexpected;

  /// Номер подсказки в выдаче
  ///
  /// In en, this message translates to:
  /// **'Suggestion {index} of {total}'**
  String choiceSuggestionPosition(int index, int total);

  /// Исходное намерение подсказки
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String choiceSuggestionSource(String source);

  /// Конечное действие подсказки
  ///
  /// In en, this message translates to:
  /// **'Selected action: {action}'**
  String choiceSuggestionAction(String action);

  /// Открыть полный текущий маршрут
  ///
  /// In en, this message translates to:
  /// **'View full route'**
  String get choiceSuggestionView;

  /// Выбрать допустимый маршрут
  ///
  /// In en, this message translates to:
  /// **'Select route'**
  String get choiceSuggestionSelect;

  /// Причина недоступности архивного намерения
  ///
  /// In en, this message translates to:
  /// **'Route unavailable: an intention is archived.'**
  String get choiceSuggestionArchivedIntention;

  /// Причина недоступности архивной связи
  ///
  /// In en, this message translates to:
  /// **'Route unavailable: a relation in the route is archived.'**
  String get choiceSuggestionArchivedRelation;

  /// Причина недоступности неготового действия
  ///
  /// In en, this message translates to:
  /// **'Route unavailable: the final action is no longer ready for action.'**
  String get choiceSuggestionActionNotReady;

  /// Заголовок просмотра всего маршрута
  ///
  /// In en, this message translates to:
  /// **'Full route'**
  String get choiceSuggestionPreviewTitle;

  /// Направление переходов в просмотре
  ///
  /// In en, this message translates to:
  /// **'Route direction: from source to action'**
  String get choiceSuggestionDirection;

  /// Порядок перехода маршрута
  ///
  /// In en, this message translates to:
  /// **'Step {index} of {total}'**
  String choiceSuggestionStep(int index, int total);
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
