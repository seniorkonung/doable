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

  /// Название пункта основной навигации и заголовок Главной
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get appDestinationHome;

  /// Название пункта основной навигации и заголовок экрана дня как корневой страницы
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get appDestinationActions;

  /// Название пункта основной навигации и заголовок каталога намерений как корневой страницы
  ///
  /// In en, this message translates to:
  /// **'Intention graph'**
  String get appDestinationIntentionGraph;

  /// Вид статистики по исходным намерениям дневных выборов
  ///
  /// In en, this message translates to:
  /// **'Source intentions'**
  String get statisticsSourceIntentions;

  /// Вид статистики по промежуточным намерениям сохранённого пути
  ///
  /// In en, this message translates to:
  /// **'Intermediate intentions'**
  String get statisticsIntermediateIntentions;

  /// Вид статистики по выбранным действиям
  ///
  /// In en, this message translates to:
  /// **'Selected actions'**
  String get statisticsSelectedActions;

  /// Вид статистики по сохранённому пути и текущим активным связям
  ///
  /// In en, this message translates to:
  /// **'Total contribution'**
  String get statisticsThroughRelations;

  /// Вкладка статистики календарного месяца
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get statisticsMonthTab;

  /// Вкладка статистики календарного года
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get statisticsYearTab;

  /// Название выбранного месяца с годом в локали приложения
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String statisticsMonthPeriod(DateTime date);

  /// Название выбранного или просматриваемого года в локали приложения
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String statisticsYearPeriod(DateTime date);

  /// Название месяца в раскрытом выборе периода в локали приложения
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String statisticsMonthName(DateTime date);

  /// Команда выбора предыдущего месяца
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get statisticsPreviousMonth;

  /// Команда выбора следующего месяца
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get statisticsNextMonth;

  /// Команда выбора предыдущего года или его просмотра в раскрытом выборе
  ///
  /// In en, this message translates to:
  /// **'Previous year'**
  String get statisticsPreviousYear;

  /// Команда выбора следующего года или его просмотра в раскрытом выборе
  ///
  /// In en, this message translates to:
  /// **'Next year'**
  String get statisticsNextYear;

  /// Команда раскрытия выбора месяцев или годов
  ///
  /// In en, this message translates to:
  /// **'Expand period selection'**
  String get statisticsExpandPeriodSelector;

  /// Команда явного сворачивания выбора месяцев или годов
  ///
  /// In en, this message translates to:
  /// **'Collapse period selection'**
  String get statisticsCollapsePeriodSelector;

  /// Видимая и доступная отметка периода, содержащего текущую местную дату
  ///
  /// In en, this message translates to:
  /// **'Current period'**
  String get statisticsCurrentPeriod;

  /// Заголовок сводки дневных выборов всего периода
  ///
  /// In en, this message translates to:
  /// **'Period summary'**
  String get statisticsPeriodSummary;

  /// Подпись выбора вида статистики
  ///
  /// In en, this message translates to:
  /// **'Statistics view'**
  String get statisticsViewLabel;

  /// Точное число элементов выбранного вида с числовой формой локали
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} item} other{{count} items}}'**
  String statisticsTotalItems(int count);

  /// Запланированный вклад сводки периода
  ///
  /// In en, this message translates to:
  /// **'Planned contribution: {count}'**
  String statisticsPlannedContribution(int count);

  /// Вклад сводки периода
  ///
  /// In en, this message translates to:
  /// **'Contribution: {count}'**
  String statisticsContribution(int count);

  /// Число невыполненных выборов раньше текущей местной даты
  ///
  /// In en, this message translates to:
  /// **'Missed: {count}'**
  String statisticsMissed(int count);

  /// Число невыполненных выборов текущей местной даты и позже
  ///
  /// In en, this message translates to:
  /// **'Upcoming: {count}'**
  String statisticsUpcoming(int count);

  /// Компактный видимый вклад элемента из запланированного
  ///
  /// In en, this message translates to:
  /// **'{contribution} of {planned}'**
  String statisticsContributionCounts(int contribution, int planned);

  /// Доступная подпись тех же чисел, что в компактном вкладе элемента; название намерения передаётся без перевода, архивная отметка использует detailsArchived
  ///
  /// In en, this message translates to:
  /// **'Contribution: {contribution}. Planned contribution: {planned}'**
  String statisticsContributionCountsSemantics(int contribution, int planned);

  /// Видимая и доступная доля вклада элемента; отношение к вкладу периода передаётся без умножения на 100
  ///
  /// In en, this message translates to:
  /// **'Share of the period’s contribution: {share}'**
  String statisticsContributionShare(num share);

  /// Доступное объяснение отсутствия доли при нулевом вкладе периода; видимая доля в этом случае не показывается
  ///
  /// In en, this message translates to:
  /// **'No share: the period’s contribution is zero'**
  String get statisticsNoContributionShare;

  /// Начальное получение статистики выбранных условий
  ///
  /// In en, this message translates to:
  /// **'Loading statistics…'**
  String get statisticsLoading;

  /// Подтверждённый пустой вид, в том числе при непустой сводке периода
  ///
  /// In en, this message translates to:
  /// **'No daily choices are credited to this view for the selected period.'**
  String get statisticsEmpty;

  /// Обновление статистики с сохранением прежних подтверждённых чисел
  ///
  /// In en, this message translates to:
  /// **'Updating statistics…'**
  String get statisticsRefreshing;

  /// Получение следующей порции элементов выбранного вида
  ///
  /// In en, this message translates to:
  /// **'Loading more items…'**
  String get statisticsLoadingMore;

  /// Первичный отказ из-за доказанной недоступности; допускает commonRetry
  ///
  /// In en, this message translates to:
  /// **'Could not load statistics. Try again.'**
  String get statisticsUnavailable;

  /// Первичный отказ из-за повреждения данных без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. Statistics cannot be shown.'**
  String get statisticsCorruption;

  /// Первичный неизвестный отказ без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'Could not load statistics because of an unexpected error.'**
  String get statisticsUnexpectedFailure;

  /// Отказ обновления из-за недоступности над прежними числами; допускает commonRetry
  ///
  /// In en, this message translates to:
  /// **'Statistics are out of date: changes could not be loaded. Try again.'**
  String get statisticsRefreshUnavailable;

  /// Отказ обновления из-за повреждения над прежними числами без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'Statistics are out of date: stored data is damaged.'**
  String get statisticsRefreshCorruption;

  /// Неизвестный отказ обновления над прежними числами без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'Statistics are out of date because of an unexpected error.'**
  String get statisticsRefreshUnexpectedFailure;

  /// Отказ следующей порции из-за недоступности в конце сохранённого списка; допускает commonRetry
  ///
  /// In en, this message translates to:
  /// **'Could not load more items. Try again.'**
  String get statisticsLoadMoreUnavailable;

  /// Отказ следующей порции из-за повреждения в конце сохранённого списка без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'More items cannot be shown: stored data is damaged.'**
  String get statisticsLoadMoreCorruption;

  /// Неизвестный отказ следующей порции в конце сохранённого списка без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'Could not load more items because of an unexpected error.'**
  String get statisticsLoadMoreUnexpectedFailure;

  /// Название раздела статистики на странице намерения
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsSectionTitle;

  /// Заголовок разбивки вклада намерения по исходным намерениям
  ///
  /// In en, this message translates to:
  /// **'By source intentions'**
  String get statisticsBreakdownSourceIntentions;

  /// Заголовок разбивки вклада намерения по выбранным действиям
  ///
  /// In en, this message translates to:
  /// **'By selected actions'**
  String get statisticsBreakdownSelectedActions;

  /// Заголовок разбивки вклада по исходящим связям намерения; архивная отметка связи использует relationNeighborhoodRelationArchived, намерения — detailsArchived
  ///
  /// In en, this message translates to:
  /// **'By relations'**
  String get statisticsBreakdownRelations;

  /// Число запланированных выборов вида «Весь вклад», в сохранённом пути которых есть намерение; учитываются выполненные и невыполненные выборы
  ///
  /// In en, this message translates to:
  /// **'Daily choices with this intention on the saved selection path: {count} of {planned}'**
  String statisticsExplicitPathChoices(int count, int planned);

  /// Доля строки разбивки относительно вклада намерения в выбранном виде, а не всего периода; отношение передаётся без умножения на 100
  ///
  /// In en, this message translates to:
  /// **'Share of this intention’s contribution in this view: {share}'**
  String statisticsBreakdownContributionShare(num share);

  /// Доступное объяснение отсутствия доли строки разбивки при нулевом вкладе намерения в выбранном виде
  ///
  /// In en, this message translates to:
  /// **'No share: this intention’s contribution in this view is zero'**
  String get statisticsBreakdownNoContributionShare;

  /// Краткий статус неудачного обновления рядом с прежними строками; допускает повтор
  ///
  /// In en, this message translates to:
  /// **'Update unavailable.'**
  String get statisticsRefreshUnavailableShort;

  /// Краткий статус повреждения данных при обновлении; без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'Damaged data.'**
  String get statisticsRefreshCorruptionShort;

  /// Краткий статус неизвестного отказа обновления; без обычного повтора
  ///
  /// In en, this message translates to:
  /// **'Update error.'**
  String get statisticsRefreshUnexpectedShort;

  /// Значение галочки календаря статистики: выполнены все выборы дня, засчитанные намерению в выбранном виде; остальные выборы дня не учитываются
  ///
  /// In en, this message translates to:
  /// **'All credited daily choices are completed'**
  String get statisticsCalendarDayAllCompleted;

  /// Значение кружка календаря статистики: среди засчитанных намерению выборов дня есть невыполненный
  ///
  /// In en, this message translates to:
  /// **'There is an incomplete credited daily choice'**
  String get statisticsCalendarDayHasIncomplete;

  /// Доступное состояние дня без отметки: выбранный вид не засчитывает намерению выборов этой даты
  ///
  /// In en, this message translates to:
  /// **'No credited daily choices'**
  String get statisticsCalendarDayNoChoices;

  /// Доступная подпись дня статистики с полной датой и локализованным состоянием; календарь раздела не выбирает день
  ///
  /// In en, this message translates to:
  /// **'{date}. {dayStatus}'**
  String statisticsCalendarDaySemantics(DateTime date, String dayStatus);

  /// Доступная подпись столбика года: месяц с годом и обе меры; текущий период обозначается существующей statisticsCurrentPeriod
  ///
  /// In en, this message translates to:
  /// **'{month}. {counts}'**
  String statisticsMonthBarSemantics(DateTime month, String counts);

  /// Доступная подпись карточки вида: локализованные вид, период и обе меры; выбранное состояние передаётся свойством Semantics.selected. Доля выбранного вида использует statisticsContributionShare или statisticsNoContributionShare; название намерения не переводится, архивная отметка использует detailsArchived
  ///
  /// In en, this message translates to:
  /// **'{view}. {period}. {counts}'**
  String statisticsViewCardSemantics(String view, String period, String counts);

  /// Доступное название кнопки быстрого создания
  ///
  /// In en, this message translates to:
  /// **'Quick create'**
  String get quickCreationLabel;

  /// Отдельное доступное действие открытия меню режимов быстрого создания
  ///
  /// In en, this message translates to:
  /// **'Change mode'**
  String get quickCreationChangeMode;

  /// Заголовок меню выбора режима быстрого создания
  ///
  /// In en, this message translates to:
  /// **'What the button creates'**
  String get quickCreationMenuTitle;

  /// Пояснение меню выбора режима кнопки быстрого создания
  ///
  /// In en, this message translates to:
  /// **'A tap on plus will create the selected item'**
  String get quickCreationMenuPrompt;

  /// Подсказка долгого нажатия на кнопку быстрого создания для экранного диктора
  ///
  /// In en, this message translates to:
  /// **'Touch and hold to change mode'**
  String get quickCreationLongPressHint;

  /// Название режима создания намерения
  ///
  /// In en, this message translates to:
  /// **'New intention'**
  String get quickCreationModeIntention;

  /// Пояснение режима создания намерения
  ///
  /// In en, this message translates to:
  /// **'Something you want to do or change'**
  String get quickCreationModeIntentionHint;

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

  /// Строка собственных тегов намерения в результате поиска; названия перечислены через запятую
  ///
  /// In en, this message translates to:
  /// **'Tags: {tags}'**
  String intentionSummaryTags(String tags);

  /// Подтверждённое отсутствие тегов у намерения в результате поиска
  ///
  /// In en, this message translates to:
  /// **'No tags'**
  String get intentionSummaryNoTags;

  /// Первоначальная загрузка соседства и полной сводки
  ///
  /// In en, this message translates to:
  /// **'Loading relations and summary…'**
  String get relationNeighborhoodSummaryLoading;

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

  /// Доступное название полосы вкладок страницы намерения
  ///
  /// In en, this message translates to:
  /// **'Intention sections'**
  String get detailsTabsLabel;

  /// Вкладка прежних данных и действий намерения
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get detailsOverviewTab;

  /// Вкладка соседства намерения
  ///
  /// In en, this message translates to:
  /// **'Relations'**
  String get detailsRelationsTab;

  /// Числа долговременных связей на вкладке для диктора
  ///
  /// In en, this message translates to:
  /// **'Relations: {active} active, {archived} archived'**
  String detailsRelationsTabSemantic(int active, int archived);

  /// Причина занятости пары в поиске участника
  ///
  /// In en, this message translates to:
  /// **'Already added'**
  String get relationPairAlreadyAdded;

  /// Причина занятости пары в поиске участника
  ///
  /// In en, this message translates to:
  /// **'Already added, archived'**
  String get relationPairAlreadyAddedArchived;

  /// Причина занятости пары в поиске участника
  ///
  /// In en, this message translates to:
  /// **'Already in group \"{group}\"'**
  String relationPairOtherGroup(String group);

  /// Причина занятости пары в поиске участника
  ///
  /// In en, this message translates to:
  /// **'Already in group \"{group}\", archived'**
  String relationPairOtherGroupArchived(String group);

  /// Доступное название плиток групп связей на вкладке «Связи»
  ///
  /// In en, this message translates to:
  /// **'Relation groups'**
  String get detailsRelationsGroupsLabel;

  /// Группа исходящих связей «нужно» на вкладке «Связи»
  ///
  /// In en, this message translates to:
  /// **'Needs'**
  String get detailsRelationsGroupNeeds;

  /// Группа исходящих связей «можно» на вкладке «Связи»
  ///
  /// In en, this message translates to:
  /// **'Can use'**
  String get detailsRelationsGroupCanUse;

  /// Группа входящих связей «нужно» на вкладке «Связи»
  ///
  /// In en, this message translates to:
  /// **'Needed for'**
  String get detailsRelationsGroupNeededFor;

  /// Группа входящих связей «можно» на вкладке «Связи»
  ///
  /// In en, this message translates to:
  /// **'Can be used for'**
  String get detailsRelationsGroupCanBeUsedFor;

  /// Доступное название плитки группы без архивированных связей
  ///
  /// In en, this message translates to:
  /// **'{group}: {count} active'**
  String detailsRelationsGroupTileSemantic(String group, int count);

  /// Доступное название плитки группы, в которой есть архивированные связи
  ///
  /// In en, this message translates to:
  /// **'{group}: {count} active, some archived'**
  String detailsRelationsGroupTileArchivedSemantic(String group, int count);

  /// Подпись типа и приоритета над названием соседа в строке связи «нужно»
  ///
  /// In en, this message translates to:
  /// **'need · {priority}'**
  String detailsRelationsRowNeed(String priority);

  /// Подпись типа и приоритета над названием соседа в строке связи «можно»
  ///
  /// In en, this message translates to:
  /// **'can · {priority}'**
  String detailsRelationsRowCan(String priority);

  /// Часть доступного названия строки связи с архивированным соседом
  ///
  /// In en, this message translates to:
  /// **'“{title}” is archived'**
  String detailsRelationsNeighborArchived(String title);

  /// Доступное название стрелки строки связи, когда сосед — намерение
  ///
  /// In en, this message translates to:
  /// **'Open the intention page: {title}'**
  String detailsRelationsWalkIntention(String title);

  /// Доступное название стрелки строки связи, когда сосед — действие
  ///
  /// In en, this message translates to:
  /// **'Open the action page: {title}'**
  String detailsRelationsWalkAction(String title);

  /// Подсказка о смысле группы «Нужно» под плитками вкладки «Связи»
  ///
  /// In en, this message translates to:
  /// **'To get there, you need each of these.'**
  String get detailsRelationsNeedsHint;

  /// Подсказка о смысле группы «Можно использовать» под плитками вкладки «Связи»
  ///
  /// In en, this message translates to:
  /// **'To get there, you can do any of these.'**
  String get detailsRelationsCanUseHint;

  /// Подсказка о смысле группы «Нужно для» под плитками вкладки «Связи»
  ///
  /// In en, this message translates to:
  /// **'Each of these needs it.'**
  String get detailsRelationsNeededForHint;

  /// Подсказка о смысле группы «Можно использовать для» под плитками вкладки «Связи»
  ///
  /// In en, this message translates to:
  /// **'Each of these can use it, as one of the ways.'**
  String get detailsRelationsCanBeUsedForHint;

  /// Видимая подпись начала создания связи на вкладке «Связи»
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get detailsRelationsAdd;

  /// Доступное название «Добавить» у группы «Нужно»
  ///
  /// In en, this message translates to:
  /// **'Add what it needs'**
  String get detailsRelationsAddNeedsLabel;

  /// Доступное название «Добавить» у группы «Можно использовать»
  ///
  /// In en, this message translates to:
  /// **'Add what it can use'**
  String get detailsRelationsAddCanUseLabel;

  /// Доступное название «Добавить» у группы «Нужно для»
  ///
  /// In en, this message translates to:
  /// **'Add an intention that needs it'**
  String get detailsRelationsAddNeededForLabel;

  /// Доступное название «Добавить» у группы «Можно использовать для»
  ///
  /// In en, this message translates to:
  /// **'Add an intention that can use it'**
  String get detailsRelationsAddCanBeUsedForLabel;

  /// Заголовок пустой группы «Нужно»
  ///
  /// In en, this message translates to:
  /// **'Needs nothing yet'**
  String get detailsRelationsEmptyNeedsTitle;

  /// Текст пустой группы «Нужно» у намерения, которое не действие
  ///
  /// In en, this message translates to:
  /// **'Add what this intention cannot do without.'**
  String get detailsRelationsEmptyNeedsIntentionText;

  /// Текст пустой группы «Нужно» у действия
  ///
  /// In en, this message translates to:
  /// **'An action can stand alone. Add what it needs if it has steps of its own.'**
  String get detailsRelationsEmptyNeedsActionText;

  /// Заголовок пустой группы «Можно использовать»
  ///
  /// In en, this message translates to:
  /// **'Nothing to use yet'**
  String get detailsRelationsEmptyCanUseTitle;

  /// Текст пустой группы «Можно использовать»
  ///
  /// In en, this message translates to:
  /// **'Add what helps to get there without being required.'**
  String get detailsRelationsEmptyCanUseText;

  /// Заголовок пустой группы «Нужно для»
  ///
  /// In en, this message translates to:
  /// **'Nothing needs it yet'**
  String get detailsRelationsEmptyNeededForTitle;

  /// Текст пустой группы «Нужно для»
  ///
  /// In en, this message translates to:
  /// **'Intentions that cannot do without this one will appear here.'**
  String get detailsRelationsEmptyNeededForText;

  /// Заголовок пустой группы «Можно использовать для»
  ///
  /// In en, this message translates to:
  /// **'Nothing can use it yet'**
  String get detailsRelationsEmptyCanBeUsedForTitle;

  /// Текст пустой группы «Можно использовать для»
  ///
  /// In en, this message translates to:
  /// **'Intentions that this one is a way to will appear here.'**
  String get detailsRelationsEmptyCanBeUsedForText;

  /// Текст пустой группы архивированного намерения вместо объяснения, что появится в группе
  ///
  /// In en, this message translates to:
  /// **'Restore the intention to add relations.'**
  String get detailsRelationsEmptyArchivedText;

  /// Подпись строки свёрнутого архива группы связей после её активных связей
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get detailsRelationsArchiveFold;

  /// Доступное название кнопки архива группы связей: группа и число архивированных связей
  ///
  /// In en, this message translates to:
  /// **'Archived in {group}: {count}'**
  String detailsRelationsArchiveFoldSemantic(String group, int count);

  /// Вкладка дневных выборов, прямо использующих намерение
  ///
  /// In en, this message translates to:
  /// **'Choices'**
  String get detailsChoicesTab;

  /// Подсказка над непустым списком роли «исходное» на вкладке «Выборы»
  ///
  /// In en, this message translates to:
  /// **'Daily choices that start from this intention.'**
  String get detailsChoicesSourceHint;

  /// Подсказка над непустым списком роли «выбранное» на вкладке «Выборы»
  ///
  /// In en, this message translates to:
  /// **'Daily choices that end in this intention.'**
  String get detailsChoicesSelectedHint;

  /// Доступное имя страницы намерения при загрузке и отказе чтения
  ///
  /// In en, this message translates to:
  /// **'Intention details'**
  String get detailsTitle;

  /// Тип неготового намерения в верхней панели его страницы
  ///
  /// In en, this message translates to:
  /// **'Intention'**
  String get detailsTypeIntention;

  /// Тип готового к действию намерения в верхней панели его страницы
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get detailsTypeAction;

  /// Доступное название пары плиток выбора готовности к действию на обзоре намерения
  ///
  /// In en, this message translates to:
  /// **'Intention or action'**
  String get detailsTypeChoiceLabel;

  /// Пояснение плитки неготового намерения на обзоре
  ///
  /// In en, this message translates to:
  /// **'Any size. It may take more than a day.'**
  String get detailsTypeIntentionHint;

  /// Оба критерия действия на плитке готового намерения на обзоре
  ///
  /// In en, this message translates to:
  /// **'Doable within one day, and clear what to do.'**
  String get detailsTypeActionHint;

  /// Метка архива после названия в шапке страницы архивированного намерения
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get detailsArchivedBadge;

  /// Строка о смысле архива под названием в шапке страницы архивированного намерения
  ///
  /// In en, this message translates to:
  /// **'Archived intentions stay in saved paths and are not offered in new ones.'**
  String get detailsArchivedNote;

  /// Кнопка восстановления намерения из архива в шапке его страницы
  ///
  /// In en, this message translates to:
  /// **'Restore from archive'**
  String get detailsRestoreFromArchiveAction;

  /// Доступное название кнопки «⋯» в верхней панели страницы намерения
  ///
  /// In en, this message translates to:
  /// **'Options of the intention'**
  String get detailsOptionsLabel;

  /// Заголовок листа параметров намерения: вид предмета
  ///
  /// In en, this message translates to:
  /// **'Intention'**
  String get detailsOptionsTitle;

  /// Пункт параметров намерения, открывающий экран изменения
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get detailsOptionEdit;

  /// Пункт параметров активного намерения, архивирующий его
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get detailsOptionArchive;

  /// Опасный пункт параметров намерения, открывающий подтверждение удаления
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get detailsOptionDelete;

  /// Пояснение архивирования намерения с активными связями
  ///
  /// In en, this message translates to:
  /// **'Its relations are archived with it'**
  String get detailsOptionArchiveWithRelations;

  /// Пояснение архивирования намерения без активных связей
  ///
  /// In en, this message translates to:
  /// **'It stays in saved paths, new ones will not use it'**
  String get detailsOptionArchiveAlone;

  /// Пояснение восстановления намерения, у которого есть связи
  ///
  /// In en, this message translates to:
  /// **'Its relations stay archived until you restore them'**
  String get detailsOptionRestoreWithRelations;

  /// Пояснение восстановления намерения без связей
  ///
  /// In en, this message translates to:
  /// **'New paths can use it again'**
  String get detailsOptionRestoreAlone;

  /// Пояснение доступного удаления намерения
  ///
  /// In en, this message translates to:
  /// **'Its tags stay'**
  String get detailsOptionDeleteKeepsTags;

  /// Причина выключенного удаления намерения с долговременными связями
  ///
  /// In en, this message translates to:
  /// **'Delete its relations first'**
  String get detailsOptionDeleteRelationsFirst;

  /// Причина выключенного удаления намерения с дневными выборами
  ///
  /// In en, this message translates to:
  /// **'Delete its daily choices first'**
  String get detailsOptionDeleteDailyChoicesFirst;

  /// Причина выключенного удаления намерения со связями и дневными выборами
  ///
  /// In en, this message translates to:
  /// **'Delete its relations and daily choices first'**
  String get detailsOptionDeleteRelationsAndDailyChoicesFirst;

  /// Причина недоступности пунктов параметров во время изменяющей операции
  ///
  /// In en, this message translates to:
  /// **'Wait for the current change to finish'**
  String get detailsOptionWait;

  /// Вопрос подтверждения удаления намерения из параметров
  ///
  /// In en, this message translates to:
  /// **'Delete intention?'**
  String get detailsDeleteDialogTitle;

  /// Текст подтверждения удаления до выделенного названия намерения
  ///
  /// In en, this message translates to:
  /// **'This removes the intention '**
  String get detailsDeleteDialogTextBefore;

  /// Текст подтверждения удаления после выделенного названия намерения
  ///
  /// In en, this message translates to:
  /// **' with its description and cannot be undone. Its tags stay.'**
  String get detailsDeleteDialogTextAfter;

  /// Отмена удаления намерения
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get detailsDeleteDialogCancel;

  /// Подтверждение удаления намерения
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get detailsDeleteDialogConfirm;

  /// Доступное название кнопки-названия в шапке страницы намерения, которая открывает экран изменения; название намерения не переводится
  ///
  /// In en, this message translates to:
  /// **'Edit the name: {title}'**
  String detailsEditTitleLabel(String title);

  /// Доступное название сохранённого описания намерения на вкладке «Обзор» и описания на панели связи; нажатие открывает его изменение, а само описание не переводится
  ///
  /// In en, this message translates to:
  /// **'Edit the description: {description}'**
  String detailsEditDescriptionLabel(String description);

  /// Приглашение добавить описание на вкладке «Обзор» намерения и на панели связи без описания; нажатие открывает его изменение
  ///
  /// In en, this message translates to:
  /// **'Add a description'**
  String get detailsAddDescription;

  /// Метка даты создания намерения в строке дат в конце вкладки «Обзор»
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get detailsCreatedLabel;

  /// Метка даты последнего изменения намерения в строке дат в конце вкладки «Обзор»
  ///
  /// In en, this message translates to:
  /// **'Changed'**
  String get detailsChangedLabel;

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

  /// Архивное состояние намерения в подробных данных
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get detailsArchived;

  /// Действие отмены изменения намерения до отправки
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get detailsCancelEditAction;

  /// Подтверждение физического удаления намерения после ухода из подробного просмотра
  ///
  /// In en, this message translates to:
  /// **'Intention deleted.'**
  String get detailsDeleted;

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

  /// Заголовок экрана изменения названия и описания намерения
  ///
  /// In en, this message translates to:
  /// **'Edit intention'**
  String get intentionEditTitle;

  /// Действие сохранения в верхней панели экрана изменения намерения
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get intentionEditSaveAction;

  /// Заполнитель и доступное название поля названия на экране изменения намерения
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get intentionEditNameLabel;

  /// Доступное название поля описания на экране изменения намерения
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get intentionEditDescriptionLabel;

  /// Заполнитель пустого поля описания на экране изменения намерения
  ///
  /// In en, this message translates to:
  /// **'Add a description'**
  String get intentionEditDescriptionPlaceholder;

  /// Вопрос перед уходом с экрана изменения намерения с несохранённым текстом
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get intentionEditDiscardTitle;

  /// Объяснение, что несохранённые изменения намерения будут потеряны при уходе с экрана
  ///
  /// In en, this message translates to:
  /// **'Your changes to the intention won’t be saved.'**
  String get intentionEditDiscardMessage;

  /// Действие вопроса об отмене изменений, закрывающее экран изменения намерения без сохранения
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get intentionEditDiscardAction;

  /// Действие вопроса об отмене изменений, возвращающее к полям экрана изменения намерения
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get intentionEditContinueAction;

  /// Заголовок формы создания намерения
  ///
  /// In en, this message translates to:
  /// **'Create intention'**
  String get editorTitle;

  /// Пояснение панели создания намерения из поиска участника
  ///
  /// In en, this message translates to:
  /// **'Selected right away for new relations'**
  String get editorSearchSubtitle;

  /// Действие создания намерения
  ///
  /// In en, this message translates to:
  /// **'Create intention'**
  String get editorCreateAction;

  /// Основное действие панели создания: сохраняет весь черновик нового намерения одной операцией
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editorSaveAction;

  /// Индикатор выполняющегося сохранения черновика нового намерения на основном действии панели
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get editorSaving;

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

  /// Успех создания намерения для поиска участника
  ///
  /// In en, this message translates to:
  /// **'Intention created and selected.'**
  String get editorCreatedAndChosen;

  /// Заголовок подтверждения закрытия изменённого черновика создания до отправки
  ///
  /// In en, this message translates to:
  /// **'Discard the draft?'**
  String get editorCloseDiscardTitle;

  /// Объяснение потери несохранённого черновика создания при закрытии формы
  ///
  /// In en, this message translates to:
  /// **'The new intention’s entered data hasn’t been saved and will be lost.'**
  String get editorCloseDiscardMessage;

  /// Действие подтверждения закрытия, сохраняющее форму и черновик создания
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get editorCloseContinueAction;

  /// Действие подтверждения закрытия, сбрасывающее черновик и закрывающее форму
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get editorCloseDiscardAction;

  /// Заголовок подтверждения закрытия формы во время принятого сохранения
  ///
  /// In en, this message translates to:
  /// **'Close the form?'**
  String get editorCloseSavingTitle;

  /// Объяснение, что закрытие формы не отменяет выполняющееся сохранение, а черновик не восстановится после отказа
  ///
  /// In en, this message translates to:
  /// **'Saving is already in progress and will continue after the form closes. If saving fails, the entered data won’t be restored.'**
  String get editorCloseSavingMessage;

  /// Действие подтверждения закрытия во время сохранения, оставляющее форму открытой
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get editorCloseSavingStayAction;

  /// Действие подтверждения закрытия во время сохранения, закрывающее форму без отмены сохранения
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get editorCloseSavingLeaveAction;

  /// Подсказка кнопки закрытия панели создания намерения и доступное название её модального фона
  ///
  /// In en, this message translates to:
  /// **'Close the form'**
  String get editorCloseFormAction;

  /// Доступное название быстрой отметки начальной готовности к действию в черновике нового намерения
  ///
  /// In en, this message translates to:
  /// **'Create as ready for action'**
  String get editorReadinessOption;

  /// Подсказка включённой быстрой отметки готовности: новое намерение будет создано готовым к действию, готовность ещё не сохранена
  ///
  /// In en, this message translates to:
  /// **'Create as ready for action: on'**
  String get editorReadinessOptionOn;

  /// Подсказка выключенной быстрой отметки готовности к действию в черновике нового намерения
  ///
  /// In en, this message translates to:
  /// **'Create as ready for action: off'**
  String get editorReadinessOptionOff;

  /// Заголовок объяснения критериев действия перед включением начальной готовности в черновике
  ///
  /// In en, this message translates to:
  /// **'Create as ready for action?'**
  String get editorReadinessConfirmationTitle;

  /// Критерий действия в объяснении начальной готовности: полная выполнимость в рамках одного дня
  ///
  /// In en, this message translates to:
  /// **'It can be completed fully within one day.'**
  String get editorReadinessOneDayCriterion;

  /// Критерий действия в объяснении начальной готовности: операционная понятность человеку
  ///
  /// In en, this message translates to:
  /// **'It is clear enough for a person to carry out.'**
  String get editorReadinessClarityCriterion;

  /// Отказ от включения начальной готовности; черновик остаётся неготовым
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get editorReadinessCancelAction;

  /// Явное подтверждение обоих критериев действия, включающее начальную готовность только в черновике
  ///
  /// In en, this message translates to:
  /// **'Mark as ready'**
  String get editorReadinessConfirmAction;

  /// Подсказка и доступное название быстрого действия, открывающего общий выбор тегов для черновика нового намерения
  ///
  /// In en, this message translates to:
  /// **'Choose tags'**
  String get editorChooseTags;

  /// Подсказка и доступное название снятия выбранного тега из черновика нового намерения без записи назначений
  ///
  /// In en, this message translates to:
  /// **'Remove tag {tagName} from draft'**
  String editorRemoveDraftTag(String tagName);

  /// Доступное состояние выбранного тега черновика, пока наблюдение ещё не подтвердило тег
  ///
  /// In en, this message translates to:
  /// **'Checking tag'**
  String get editorDraftTagChecking;

  /// Устранимый отказ чтения выбранного тега черновика; не означает удаление тега
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check tag'**
  String get editorDraftTagReadUnavailable;

  /// Отказ чтения выбранного тега черновика из-за повреждённых данных; повтор не предлагается
  ///
  /// In en, this message translates to:
  /// **'Tag data is corrupted'**
  String get editorDraftTagReadCorruption;

  /// Непредвиденный отказ чтения выбранного тега черновика; повтор не предлагается
  ///
  /// In en, this message translates to:
  /// **'Tag not checked due to an unexpected error'**
  String get editorDraftTagReadUnexpected;

  /// Подсказка и доступное название повтора проверки выбранного тега черновика после устранимого отказа чтения
  ///
  /// In en, this message translates to:
  /// **'Check tag {tagName} again'**
  String editorRetryDraftTag(String tagName);

  /// Отказ создания намерения: выбранные теги черновика отсутствуют при сохранении; они уже убраны из черновика, и сохранение снова доступно
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{A selected tag was deleted from the catalog and removed from the draft. Save the intention again.} other{{count} selected tags were deleted from the catalog and removed from the draft. Save the intention again.}}'**
  String editorCreateTagsMissing(int count);

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

  /// Сообщение общей поверхности с числом остальных результатов
  ///
  /// In en, this message translates to:
  /// **'{message} · {count} more'**
  String graphOperationMessageWithOthers(String message, int count);

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

  /// Безопасное обозначение действия в сообщении операции
  ///
  /// In en, this message translates to:
  /// **'action'**
  String get graphOperationAction;

  /// Обозначение тега в общем сообщении операции
  ///
  /// In en, this message translates to:
  /// **'tag'**
  String get graphOperationTag;

  /// Перестановка тега в ручном порядке в общем сообщении
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get graphOperationMoveTag;

  /// Назначение тега получателю в общем сообщении
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get graphOperationAssignTag;

  /// Снятие назначения тега в общем сообщении
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get graphOperationRemoveTagAssignment;

  /// Безопасное обозначение назначения без личных данных
  ///
  /// In en, this message translates to:
  /// **'tag assignment'**
  String get graphOperationTagAssignment;

  /// Сообщение общей поверхности об успешном экспорте графа в файл
  ///
  /// In en, this message translates to:
  /// **'Data saved to a file'**
  String get dataExportSaved;

  /// Сообщение общей поверхности об отказе экспорта графа с действием commonRetry
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the file'**
  String get dataExportFailed;

  /// Сообщение общей поверхности с действием commonRetry, когда в диалоге сохранения выбран файл с данными и экспорт не начат
  ///
  /// In en, this message translates to:
  /// **'That file already exists. Save the copy under a new name'**
  String get dataExportExistingFile;

  /// Сообщение общей поверхности об успешном восстановлении резервной копии
  ///
  /// In en, this message translates to:
  /// **'Copy restored'**
  String get dataBackupRestored;

  /// Сообщение об отказе восстановления резервной копии: под строкой «Резервные копии» или на общей поверхности
  ///
  /// In en, this message translates to:
  /// **'Couldn’t restore the copy. Nothing was changed'**
  String get dataBackupRestoreFailed;

  /// Сообщение об отказе замены графа из-за нехватки места на устройстве
  ///
  /// In en, this message translates to:
  /// **'Not enough space on the device. Free up space and try again. Nothing was changed'**
  String get dataReplacementStorageFull;

  /// Сообщение общей поверхности об успешном импорте файла экспорта
  ///
  /// In en, this message translates to:
  /// **'Data imported'**
  String get dataImported;

  /// Сообщение об отказе импорта: файл не является экспортом Doable или повреждён; под строкой «Импорт данных» или на общей поверхности
  ///
  /// In en, this message translates to:
  /// **'Couldn’t import the file. It isn’t a Doable export, or it’s damaged. Nothing was changed'**
  String get dataImportInvalidFile;

  /// Сообщение об отказе импорта файла более новой версии формата; под строкой «Импорт данных» или на общей поверхности
  ///
  /// In en, this message translates to:
  /// **'The file was created by a newer version of Doable. Update the app to import it. Nothing was changed'**
  String get dataImportNewerVersion;

  /// Сообщение об отказе импорта: выбранный файл не удалось прочитать; под строкой «Импорт данных» или на общей поверхности
  ///
  /// In en, this message translates to:
  /// **'Couldn’t read the file. Check that you can access it and try again. Nothing was changed'**
  String get dataImportUnreadable;

  /// Сообщение об отказе импорта по неизвестной причине; под строкой «Импорт данных» или на общей поверхности
  ///
  /// In en, this message translates to:
  /// **'Couldn’t import the data. Nothing was changed'**
  String get dataImportFailed;

  /// Сообщение общей поверхности без действия об отказе ручной резервной копии
  ///
  /// In en, this message translates to:
  /// **'Couldn’t back up'**
  String get dataManualBackupFailed;

  /// Заголовок страницы «Настройки» и доступное название перехода к ней с Главной
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Заголовок раздела «Данные» страницы настроек
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get dataSectionTitle;

  /// Пояснение раздела «Данные» о том, что граф хранится только на устройстве
  ///
  /// In en, this message translates to:
  /// **'Everything you write is stored only on this device.'**
  String get dataSectionLocalOnly;

  /// Название строки экспорта в разделе «Данные» и заголовок панели экспорта графа в файл
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get dataExportTitle;

  /// Подпись строки экспорта, когда экспорт можно начать или состав графа неизвестен
  ///
  /// In en, this message translates to:
  /// **'Save a copy of everything to a file'**
  String get dataExportHint;

  /// Подпись недоступной строки экспорта при пустом графе
  ///
  /// In en, this message translates to:
  /// **'Nothing to export yet'**
  String get dataExportNothing;

  /// Подпись строки экспорта, пока идёт экспорт
  ///
  /// In en, this message translates to:
  /// **'Saving to a file…'**
  String get dataExportRunning;

  /// Ход идущего экспорта для экранного диктора: доля записанных записей в процентах
  ///
  /// In en, this message translates to:
  /// **'{share}'**
  String dataExportProgress(double share);

  /// Состав будущего файла экспорта: числа всех намерений, долговременных связей, действий и тегов вместе с архивированными
  ///
  /// In en, this message translates to:
  /// **'{intentions, plural, one{{intentions} intention} other{{intentions} intentions}}, {relations, plural, one{{relations} relation} other{{relations} relations}}, {actions, plural, one{{actions} action} other{{actions} actions}} and {tags, plural, one{{tags} tag} other{{tags} tags}} in one file'**
  String dataExportComposition(
    int intentions,
    int relations,
    int actions,
    int tags,
  );

  /// Предупреждение панели экспорта о том, что файл не зашифрован
  ///
  /// In en, this message translates to:
  /// **'The file is not protected. Anyone who has it can read what you wrote.'**
  String get dataExportUnprotected;

  /// Кнопка панели экспорта, открывающая системный диалог сохранения
  ///
  /// In en, this message translates to:
  /// **'Save to a file'**
  String get dataExportSave;

  /// Название строки импорта в разделе «Данные»
  ///
  /// In en, this message translates to:
  /// **'Import data'**
  String get dataImportTitle;

  /// Подпись строки импорта, когда граф не пуст или его состав неизвестен
  ///
  /// In en, this message translates to:
  /// **'Replace everything with a copy from a file'**
  String get dataImportHint;

  /// Подпись строки импорта при пустом графе
  ///
  /// In en, this message translates to:
  /// **'Bring back a copy from a file'**
  String get dataImportHintEmptyGraph;

  /// Действие под строкой «Импорт данных» после отказа импорта файла, который не является экспортом Doable или повреждён; снова открывает системный диалог выбора файла
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get dataImportChooseAnotherFile;

  /// Заголовок панели «Резервные копии»
  ///
  /// In en, this message translates to:
  /// **'Backups'**
  String get dataBackupsTitle;

  /// Пояснение панели «Резервные копии»: когда делаются и сколько хранятся копии; число совпадает с окном хранения ежедневных копий
  ///
  /// In en, this message translates to:
  /// **'A copy is made each day your data changes and stays on this device. The 7 most recent daily copies are kept. Choose a copy to restore it.'**
  String get dataBackupsExplanation;

  /// Кнопка панели «Резервные копии», делающая ручную копию
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get dataBackupsMakeNow;

  /// Сообщение панели «Резервные копии» вместо списка, когда копии прочитать не удалось
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load backups'**
  String get dataBackupsReadFailed;

  /// Доступное название ручки панели «Резервные копии» в компактном размере
  ///
  /// In en, this message translates to:
  /// **'Expand backups panel'**
  String get dataBackupsExpand;

  /// Доступное название ручки панели «Резервные копии» в полном размере
  ///
  /// In en, this message translates to:
  /// **'Collapse backups panel'**
  String get dataBackupsCollapse;

  /// Подпись строки «Резервные копии», когда последняя копия сделана меньше минуты назад
  ///
  /// In en, this message translates to:
  /// **'Last copy just now'**
  String get dataBackupsLastJustNow;

  /// Подпись строки «Резервные копии», когда последняя копия сделана сегодня
  ///
  /// In en, this message translates to:
  /// **'Last copy today at {time}'**
  String dataBackupsLastToday(String time);

  /// Подпись строки «Резервные копии», когда последняя копия сделана вчера
  ///
  /// In en, this message translates to:
  /// **'Last copy yesterday at {time}'**
  String dataBackupsLastYesterday(String time);

  /// Подпись строки «Резервные копии», когда последняя копия сделана раньше вчерашнего дня
  ///
  /// In en, this message translates to:
  /// **'Last copy on {date} at {time}'**
  String dataBackupsLastOn(String date, String time);

  /// Подпись доступной строки «Резервные копии», когда копий нет, а граф не пуст
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get dataBackupsNone;

  /// Подпись недоступной строки «Резервные копии», когда копий нет и граф пуст
  ///
  /// In en, this message translates to:
  /// **'Nothing to back up yet'**
  String get dataBackupsNothing;

  /// Момент копии, сделанной сегодня, в списке копий
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String dataBackupMadeToday(String time);

  /// Момент копии, сделанной вчера, в списке копий
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String dataBackupMadeYesterday(String time);

  /// Момент копии, сделанной раньше вчерашнего дня, в списке копий
  ///
  /// In en, this message translates to:
  /// **'{date}, {time}'**
  String dataBackupMadeOn(String date, String time);

  /// Доступное название копии, сделанной сегодня, в списке копий
  ///
  /// In en, this message translates to:
  /// **'Restore the copy from today, {time}'**
  String dataBackupRestoreMadeToday(String time);

  /// Доступное название копии, сделанной вчера, в списке копий
  ///
  /// In en, this message translates to:
  /// **'Restore the copy from yesterday, {time}'**
  String dataBackupRestoreMadeYesterday(String time);

  /// Доступное название копии, сделанной раньше вчерашнего дня, в списке копий
  ///
  /// In en, this message translates to:
  /// **'Restore the copy from {date}, {time}'**
  String dataBackupRestoreMadeOn(String date, String time);

  /// Часть сводки изменений: число добавленных намерений, тегов, долговременных связей и дневных выборов
  ///
  /// In en, this message translates to:
  /// **'{count} added'**
  String dataBackupAdded(int count);

  /// Часть сводки изменений: число изменённых намерений, тегов, долговременных связей и дневных выборов
  ///
  /// In en, this message translates to:
  /// **'{count} changed'**
  String dataBackupChanged(int count);

  /// Часть сводки изменений: число удалённых намерений, тегов, долговременных связей и дневных выборов
  ///
  /// In en, this message translates to:
  /// **'{count} removed'**
  String dataBackupDeleted(int count);

  /// Сводка копии, с предыдущей копии которой граф не изменился
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get dataBackupNoChanges;

  /// Сводка копии, между которой и предыдущей копией граф заменялся импортом или восстановлением
  ///
  /// In en, this message translates to:
  /// **'Data replaced'**
  String get dataBackupDataReplaced;

  /// Заголовок модального прогресса, пока идёт восстановление резервной копии
  ///
  /// In en, this message translates to:
  /// **'Restoring the copy…'**
  String get dataRestoreRunning;

  /// Заголовок модального прогресса импорта с выбора файла до исхода замены графа
  ///
  /// In en, this message translates to:
  /// **'Importing data…'**
  String get dataImportRunning;

  /// Ход замены графа для экранного диктора: выполненная доля в процентах
  ///
  /// In en, this message translates to:
  /// **'{share}'**
  String dataReplacementProgress(double share);

  /// Кнопка модального прогресса замены графа, откатывающая замену
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dataReplacementCancel;

  /// Состояние модального прогресса замены графа после «Отменить», пока замена откатывается
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get dataReplacementCancelling;

  /// Заголовок подтверждения восстановления резервной копии
  ///
  /// In en, this message translates to:
  /// **'Restore this copy?'**
  String get dataRestoreConfirmationTitle;

  /// Момент копии, сделанной сегодня, в подтверждении её восстановления
  ///
  /// In en, this message translates to:
  /// **'It was made today at {time}.'**
  String dataRestoreMadeToday(String time);

  /// Момент копии, сделанной вчера, в подтверждении её восстановления
  ///
  /// In en, this message translates to:
  /// **'It was made yesterday at {time}.'**
  String dataRestoreMadeYesterday(String time);

  /// Момент копии, сделанной раньше вчерашнего дня, в подтверждении её восстановления
  ///
  /// In en, this message translates to:
  /// **'It was made on {date} at {time}.'**
  String dataRestoreMadeOn(String date, String time);

  /// Изменения графа после копии, которые отменит её восстановление
  ///
  /// In en, this message translates to:
  /// **'Since then: {changes}. Restoring undoes all of it.'**
  String dataRestoreChangesSince(String changes);

  /// Подтверждение восстановления копии, после которой граф не изменялся
  ///
  /// In en, this message translates to:
  /// **'Nothing has changed since then.'**
  String get dataRestoreNoChangesSince;

  /// Подтверждение восстановления копии, после которой граф заменялся импортом или восстановлением
  ///
  /// In en, this message translates to:
  /// **'The data has been replaced since then. Restoring undoes every change.'**
  String get dataRestoreReplacedSince;

  /// Предупреждение подтверждений восстановления копии и импорта: копия заменит весь граф, а текущее состояние сначала сохраняется копией
  ///
  /// In en, this message translates to:
  /// **'It will replace everything now in Doable. A backup of the current state is made first.'**
  String get dataReplacementReplacesEverything;

  /// Действие подтверждений восстановления копии и импорта, закрывающее подтверждение без изменений
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dataReplacementConfirmationCancel;

  /// Действие подтверждения восстановления копии, начинающее восстановление
  ///
  /// In en, this message translates to:
  /// **'Restore copy'**
  String get dataRestoreConfirm;

  /// Заголовок подтверждения импорта файла экспорта в непустой граф
  ///
  /// In en, this message translates to:
  /// **'Import this copy?'**
  String get dataImportConfirmationTitle;

  /// Дата сохранения файла импорта по местному времени и числа его намерений, долговременных связей, действий и тегов из заголовка файла
  ///
  /// In en, this message translates to:
  /// **'It was saved on {date} and holds {intentions, plural, one{{intentions} intention} other{{intentions} intentions}}, {relations, plural, one{{relations} relation} other{{relations} relations}}, {actions, plural, one{{actions} action} other{{actions} actions}} and {tags, plural, one{{tags} tag} other{{tags} tags}}.'**
  String dataImportConfirmationFacts(
    String date,
    int intentions,
    int relations,
    int actions,
    int tags,
  );

  /// Действие подтверждения импорта, начинающее замену графа содержимым файла
  ///
  /// In en, this message translates to:
  /// **'Import and replace'**
  String get dataImportConfirm;

  /// Заголовок панели тегов при выборе тегов намерения
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsPanelTitle;

  /// Строка под заголовком панели тегов при выборе тегов намерения
  ///
  /// In en, this message translates to:
  /// **'Choose as many as you need'**
  String get tagsPanelAssignmentHint;

  /// Заголовок панели тегов в режиме фильтра поиска намерений
  ///
  /// In en, this message translates to:
  /// **'Filter by tags'**
  String get tagsPanelFilterTitle;

  /// Строка под заголовком панели тегов в режиме фильтра: нажатия переключают надобность по кругу
  ///
  /// In en, this message translates to:
  /// **'Tap to require a tag, tap again to exclude it'**
  String get tagsPanelFilterHint;

  /// Действие шапки панели фильтра, снимающее все условия по тегам
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get tagsPanelResetConditions;

  /// Доступное название действия «Сбросить» в панели фильтра
  ///
  /// In en, this message translates to:
  /// **'Reset tag conditions'**
  String get tagsPanelResetConditionsLabel;

  /// Доступное название строки панели фильтра с условием «должен быть»
  ///
  /// In en, this message translates to:
  /// **'{tagName}, must be present'**
  String tagsPanelFilterPresentLabel(String tagName);

  /// Доступное название строки панели фильтра с условием «должен отсутствовать»
  ///
  /// In en, this message translates to:
  /// **'{tagName}, must be absent'**
  String tagsPanelFilterAbsentLabel(String tagName);

  /// Заполнитель поля поиска панели тегов
  ///
  /// In en, this message translates to:
  /// **'Find or create a tag'**
  String get tagsPanelSearchPlaceholder;

  /// Доступное название поля поиска панели тегов
  ///
  /// In en, this message translates to:
  /// **'Search tags'**
  String get tagsPanelSearchLabel;

  /// Доступное название очистки поиска панели тегов
  ///
  /// In en, this message translates to:
  /// **'Clear tag search'**
  String get tagsPanelClearSearch;

  /// Ошибка некорректного Unicode в поиске панели с объяснением сохранения последнего корректного фильтра
  ///
  /// In en, this message translates to:
  /// **'Invalid characters are shown as �. Your input is retained but wasn’t applied; results use the last valid query.'**
  String get tagsPanelInvalidSearch;

  /// Кнопка, которая только закрывает панель тегов
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tagsPanelDone;

  /// Доступное название ручки панели тегов в половинном размере
  ///
  /// In en, this message translates to:
  /// **'Expand tags panel'**
  String get tagsPanelExpand;

  /// Доступное название ручки панели тегов в полном размере
  ///
  /// In en, this message translates to:
  /// **'Collapse tags panel'**
  String get tagsPanelCollapse;

  /// Первоначальная загрузка каталога панели тегов
  ///
  /// In en, this message translates to:
  /// **'Loading tags…'**
  String get tagsPanelLoading;

  /// Устранимый отказ первоначального чтения каталога панели; рядом действие повтора
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load tags.'**
  String get tagsPanelLoadUnavailable;

  /// Повреждение данных при первоначальном чтении каталога панели; без повтора
  ///
  /// In en, this message translates to:
  /// **'Saved tag data is corrupted and can’t be shown.'**
  String get tagsPanelLoadCorruption;

  /// Неизвестный отказ первоначального чтения каталога панели; без повтора
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load tags because of an unexpected error.'**
  String get tagsPanelLoadUnexpected;

  /// Устранимый отказ фонового обновления над неактуальным списком; рядом действие повтора
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update tags. The list may be out of date.'**
  String get tagsPanelRefreshUnavailable;

  /// Повреждение данных при фоновом обновлении над неактуальным списком; без повтора
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update tags: saved data is corrupted. The list may be out of date.'**
  String get tagsPanelRefreshCorruption;

  /// Неизвестный отказ фонового обновления над неактуальным списком; без повтора
  ///
  /// In en, this message translates to:
  /// **'Couldn’t update tags because of an unexpected error. The list may be out of date.'**
  String get tagsPanelRefreshUnexpected;

  /// Намерения, для которого открыта панель тегов, больше нет
  ///
  /// In en, this message translates to:
  /// **'This intention no longer exists.'**
  String get tagsPanelIntentionMissing;

  /// Заголовок пустого каталога в панели тегов
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get tagsPanelEmptyTitle;

  /// Подсказка пустого каталога в панели тегов
  ///
  /// In en, this message translates to:
  /// **'Type a name in search to create the first one'**
  String get tagsPanelEmptyText;

  /// Строка панели тегов, создающая тег с названием из поиска
  ///
  /// In en, this message translates to:
  /// **'Create tag “{query}”'**
  String tagsPanelCreateTag(String query);

  /// Доступное название меню тега, открытого удержанием строки панели
  ///
  /// In en, this message translates to:
  /// **'Tag: {tagName}'**
  String tagsPanelTagMenu(String tagName);

  /// Подсказка диктора на строке тега: удержание открывает действия тега
  ///
  /// In en, this message translates to:
  /// **'Long press to open tag actions'**
  String get tagsPanelTagHoldHint;

  /// Действие меню тега, открывающее лист изменения тега
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get tagsPanelEditTag;

  /// Действие меню тега, открывающее лист создания копии тега
  ///
  /// In en, this message translates to:
  /// **'Duplicate tag'**
  String get tagsPanelDuplicateTag;

  /// Разрушительное действие меню тега, открывающее подтверждение удаления самого тега
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get tagsPanelDeleteTag;

  /// Заголовок подтверждения удаления тега
  ///
  /// In en, this message translates to:
  /// **'Delete tag?'**
  String get tagsPanelDeleteTitle;

  /// Текст подтверждения удаления до выделенного названия тега
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the tag '**
  String get tagsPanelDeleteTextBefore;

  /// Текст подтверждения удаления после выделенного названия тега: полный охват удаления и что сохраняется
  ///
  /// In en, this message translates to:
  /// **' and all its assignments to active and archived intentions. The intentions, relations, daily choices and their paths remain.'**
  String get tagsPanelDeleteTextAfter;

  /// Отмена удаления тега
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get tagsPanelDeleteCancel;

  /// Подтверждение удаления тега и всех его назначений
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get tagsPanelDeleteConfirm;

  /// Заполнитель поля названия в листе тега
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get tagSheetNamePlaceholder;

  /// Заголовок листа изменения тега
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get tagSheetEditTitle;

  /// Заголовок формы создания тега
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get tagEditorCreateTitle;

  /// Подпись поля названия тега
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get tagEditorNameLabel;

  /// Название варианта цвета тега: Без цвета
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get tagColorNone;

  /// Название варианта цвета тега: Коричневый
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get tagColorBrown;

  /// Название варианта цвета тега: Оранжевый
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get tagColorOrange;

  /// Название варианта цвета тега: Оливковый
  ///
  /// In en, this message translates to:
  /// **'Olive'**
  String get tagColorOlive;

  /// Название варианта цвета тега: Зелёный
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get tagColorGreen;

  /// Название варианта цвета тега: Бирюзовый
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get tagColorTeal;

  /// Название варианта цвета тега: Синий
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get tagColorBlue;

  /// Название варианта цвета тега: Сиреневый
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get tagColorViolet;

  /// Название варианта цвета тега: Фиолетовый
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get tagColorPurple;

  /// Название варианта цвета тега: Розовый
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get tagColorPink;

  /// Заголовок выбора цвета тега
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get tagColorLabel;

  /// Доступное название группы цветов тега
  ///
  /// In en, this message translates to:
  /// **'Tag color'**
  String get tagColorGroupLabel;

  /// Подтвердить создание тега
  ///
  /// In en, this message translates to:
  /// **'Create tag'**
  String get tagEditorCreateAction;

  /// Подтвердить изменение тега
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get tagEditorRenameAction;

  /// Выполняется запись тега
  ///
  /// In en, this message translates to:
  /// **'Saving tag…'**
  String get tagEditorSaving;

  /// Повторное сохранение при занятом ключе формы тега
  ///
  /// In en, this message translates to:
  /// **'Saving this tag is already in progress. Wait for its result.'**
  String get tagEditorAlreadyRunning;

  /// Занятость ключей назначения при повторном действии
  ///
  /// In en, this message translates to:
  /// **'A tag assignment change is already in progress. Wait for its result.'**
  String get tagAssignmentAlreadyRunning;

  /// Отсутствие намерения, которому назначают или с которого снимают тег
  ///
  /// In en, this message translates to:
  /// **'This intention no longer exists. Refresh its details.'**
  String get tagAssignmentIntentionNotFound;

  /// Временная недоступность назначения или снятия
  ///
  /// In en, this message translates to:
  /// **'Could not complete the tag assignment operation. Try again.'**
  String get tagAssignmentUnavailable;

  /// Повреждение при назначении или снятии
  ///
  /// In en, this message translates to:
  /// **'Stored tag assignment data is damaged. The assignment was not changed.'**
  String get tagAssignmentCorruption;

  /// Неизвестный отказ назначения или снятия
  ///
  /// In en, this message translates to:
  /// **'The tag assignment operation failed because of an unexpected error.'**
  String get tagAssignmentUnexpected;

  /// Заголовок блока тегов намерения
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagAssignmentsTitle;

  /// Вид получателя: намерение
  ///
  /// In en, this message translates to:
  /// **'intention'**
  String get tagAssignmentsIntention;

  /// Активное состояние получателя
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get tagAssignmentsActive;

  /// Архивное состояние получателя
  ///
  /// In en, this message translates to:
  /// **'archived'**
  String get tagAssignmentsArchived;

  /// Контекст блока для экранного диктора
  ///
  /// In en, this message translates to:
  /// **'Tag assignments: {targetKind}, {archiveState}'**
  String tagAssignmentsContext(String targetKind, String archiveState);

  /// Начальная загрузка назначений
  ///
  /// In en, this message translates to:
  /// **'Loading assignments…'**
  String get tagAssignmentsLoading;

  /// Актуализация открытых назначений
  ///
  /// In en, this message translates to:
  /// **'Refreshing assignments…'**
  String get tagAssignmentsRefreshing;

  /// Устранимый отказ чтения назначений
  ///
  /// In en, this message translates to:
  /// **'Could not load assignments. Try again.'**
  String get tagAssignmentsUnavailable;

  /// Повреждение данных назначений
  ///
  /// In en, this message translates to:
  /// **'Stored assignment data is damaged and cannot be shown.'**
  String get tagAssignmentsCorruption;

  /// Неизвестный отказ чтения назначений
  ///
  /// In en, this message translates to:
  /// **'Could not load assignments because of an unexpected error.'**
  String get tagAssignmentsUnexpected;

  /// Видимая подпись открытия панели тегов намерения
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get tagAssignmentsAdd;

  /// Доступная подпись «Добавить» с перечнем назначенных тегов
  ///
  /// In en, this message translates to:
  /// **'Tags: {tagNames}. Add or remove'**
  String tagAssignmentsAddLabel(String tagNames);

  /// Доступная подпись «Добавить» у намерения без тегов
  ///
  /// In en, this message translates to:
  /// **'Add tags'**
  String get tagAssignmentsAddEmptyLabel;

  /// Доступная подпись крестика, который снимает тег с намерения
  ///
  /// In en, this message translates to:
  /// **'Remove the tag: {tagName}'**
  String tagAssignmentsRemoveNamed(String tagName);

  /// Ожидание подтверждения снятия
  ///
  /// In en, this message translates to:
  /// **'Removing assignment…'**
  String get tagAssignmentsRemoving;

  /// Недопустимые символы в названии тега
  ///
  /// In en, this message translates to:
  /// **'Tag name contains invalid characters.'**
  String get tagNameInvalidUnicode;

  /// Пустое название тега
  ///
  /// In en, this message translates to:
  /// **'Enter a tag name.'**
  String get tagNameEmpty;

  /// Превышена длина названия тега
  ///
  /// In en, this message translates to:
  /// **'Tag name must contain no more than 255 visible characters.'**
  String get tagNameTooLong;

  /// Неканоничное название тега
  ///
  /// In en, this message translates to:
  /// **'Remove whitespace around the tag name.'**
  String get tagNameNonCanonical;

  /// Название тега уже занято
  ///
  /// In en, this message translates to:
  /// **'A tag with this name already exists.'**
  String get tagNameOccupied;

  /// Тег отсутствует при изменении
  ///
  /// In en, this message translates to:
  /// **'This tag no longer exists. Refresh the catalog.'**
  String get tagNotFound;

  /// Временная недоступность команды тега
  ///
  /// In en, this message translates to:
  /// **'Could not complete the tag operation. Try again.'**
  String get tagUnavailable;

  /// Повреждение сохранённых данных тега
  ///
  /// In en, this message translates to:
  /// **'Stored tag data is damaged. The tag was not changed.'**
  String get tagCorruption;

  /// Неизвестный отказ команды тега
  ///
  /// In en, this message translates to:
  /// **'The tag operation failed because of an unexpected error.'**
  String get tagUnexpected;

  /// Подтверждение создания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice created.'**
  String get dailyChoiceCreated;

  /// Подтверждение удаления дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice deleted.'**
  String get dailyChoiceDeleted;

  /// Пункт меню дневного выбора, открывающий изменение имеющегося описания
  ///
  /// In en, this message translates to:
  /// **'Edit the description'**
  String get dailyChoiceSheetOptionEditDescription;

  /// Пункт удаления дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Delete daily choice'**
  String get dailyChoiceSheetOptionDelete;

  /// Вопрос перед удалением дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Delete daily choice?'**
  String get dailyChoiceDeleteDialogTitle;

  /// Текст перед названием выбора
  ///
  /// In en, this message translates to:
  /// **'The choice '**
  String get dailyChoiceDeleteDialogBefore;

  /// Дата и необратимость удаления
  ///
  /// In en, this message translates to:
  /// **' for {date} will be deleted. This cannot be undone.'**
  String dailyChoiceDeleteDialogAfter(String date);

  /// Подтвердить удаление дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get dailyChoiceDeleteDialogAction;

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

  /// Подтверждение удаления действия
  ///
  /// In en, this message translates to:
  /// **'Action deleted.'**
  String get actionDeleted;

  /// Ошибка названия действия
  ///
  /// In en, this message translates to:
  /// **'Check the action title.'**
  String get actionTitleInvalid;

  /// Ошибка описания действия
  ///
  /// In en, this message translates to:
  /// **'Check the action description.'**
  String get actionDescriptionInvalid;

  /// Действие отсутствует при выполнении команды
  ///
  /// In en, this message translates to:
  /// **'This action no longer exists.'**
  String get actionOperationNotFound;

  /// Конфликт актуальности действия
  ///
  /// In en, this message translates to:
  /// **'The data changed. Refresh it and confirm again.'**
  String get actionOperationConflict;

  /// Временная недоступность команды действия
  ///
  /// In en, this message translates to:
  /// **'Could not complete the action operation. Try again.'**
  String get actionOperationUnavailable;

  /// Повреждение данных действия
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. The action was not changed.'**
  String get actionOperationCorruption;

  /// Неожиданный отказ команды действия
  ///
  /// In en, this message translates to:
  /// **'The action operation failed because of an unexpected error.'**
  String get actionOperationUnexpected;

  /// Заголовок и доступное название панели действия
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get actionPanelTitle;

  /// Доступное название ручки компактной панели действия
  ///
  /// In en, this message translates to:
  /// **'Expand action sheet'**
  String get actionPanelExpand;

  /// Доступное название ручки раскрытой панели действия
  ///
  /// In en, this message translates to:
  /// **'Collapse action sheet'**
  String get actionPanelCollapse;

  /// Начальная загрузка панели действия
  ///
  /// In en, this message translates to:
  /// **'Loading the action…'**
  String get actionPanelLoading;

  /// Доказанно временный отказ чтения действия в панели
  ///
  /// In en, this message translates to:
  /// **'Could not load the action. Try again.'**
  String get actionPanelUnavailable;

  /// Повреждённые данные действия в панели
  ///
  /// In en, this message translates to:
  /// **'The saved action is corrupted and cannot be shown.'**
  String get actionPanelCorruption;

  /// Неизвестный отказ чтения действия в панели
  ///
  /// In en, this message translates to:
  /// **'Could not load the action because of an unexpected error.'**
  String get actionPanelUnexpected;

  /// Доступное название флажка в шапке панели; состояние сообщает сам флажок
  ///
  /// In en, this message translates to:
  /// **'Completion of the action. {action}. {priority}'**
  String actionPanelCompletionLabel(String action, String priority);

  /// Действие уведомления об отказе изменения выполнения без явного повтора: перечитывает действие и возвращает флажок
  ///
  /// In en, this message translates to:
  /// **'Refresh the action'**
  String get actionRefresh;

  /// Название поля даты действия
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get actionFieldDate;

  /// Название поля времени действия
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get actionFieldTime;

  /// Название поля приоритета действия
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get actionFieldPriority;

  /// Доступное название поля даты: название поля, полное значение и действие
  ///
  /// In en, this message translates to:
  /// **'Date: {date}. Change date'**
  String actionFieldDateLabel(String date);

  /// Доступное название поля времени: название поля, значение и действие
  ///
  /// In en, this message translates to:
  /// **'Time: {time}. Change time'**
  String actionFieldTimeLabel(String time);

  /// Планирование на весь день без конкретного времени
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get actionAllDay;

  /// Вариант приоритета действия
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String actionPriorityOption(String priority);

  /// Дата действия, совпадающая с текущим локальным днём устройства
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get actionDateToday;

  /// Дата действия, которая наступит завтра
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get actionDateTomorrow;

  /// Дата действия, которая была вчера
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get actionDateYesterday;

  /// Доступное название листа даты действия
  ///
  /// In en, this message translates to:
  /// **'Action date'**
  String get actionDateSheetLabel;

  /// Доступное название листа времени действия
  ///
  /// In en, this message translates to:
  /// **'Action time'**
  String get actionTimeSheetLabel;

  /// Доступное название переключателя половины суток на 12-часовом циферблате
  ///
  /// In en, this message translates to:
  /// **'Half of the day'**
  String get actionTimeHalfSwitchLabel;

  /// Доступное название половины суток до полудня
  ///
  /// In en, this message translates to:
  /// **'Before noon'**
  String get actionTimeAmLabel;

  /// Доступное название половины суток после полудня
  ///
  /// In en, this message translates to:
  /// **'After noon'**
  String get actionTimePmLabel;

  /// Команда просмотра предыдущего месяца в листе даты действия
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get actionCalendarPreviousMonth;

  /// Команда просмотра следующего месяца в листе даты действия
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get actionCalendarNextMonth;

  /// Доступное состояние дня с отметкой: все действия этой даты выполнены
  ///
  /// In en, this message translates to:
  /// **'All actions are completed'**
  String get actionCalendarDayAllCompleted;

  /// Доступное состояние дня с отметкой: на эту дату есть хотя бы одно невыполненное действие
  ///
  /// In en, this message translates to:
  /// **'There is an incomplete action'**
  String get actionCalendarDayHasIncomplete;

  /// Доступное название кнопки параметров в шапке панели действия
  ///
  /// In en, this message translates to:
  /// **'Action options'**
  String get actionPanelOptionsLabel;

  /// Пункт меню «Действие», открывающий изменение названия и описания действия
  ///
  /// In en, this message translates to:
  /// **'Edit the name and description'**
  String get actionOptionEditText;

  /// Опасный пункт меню «Действие», открывающий подтверждение удаления
  ///
  /// In en, this message translates to:
  /// **'Delete the action'**
  String get actionOptionDelete;

  /// Пояснение пункта удаления действия
  ///
  /// In en, this message translates to:
  /// **'Its intentions and relations stay'**
  String get actionOptionDeleteHint;

  /// Вопрос перед удалением действия
  ///
  /// In en, this message translates to:
  /// **'Delete the action?'**
  String get actionDeleteDialogTitle;

  /// Текст перед названием действия
  ///
  /// In en, this message translates to:
  /// **'The action '**
  String get actionDeleteDialogBefore;

  /// Дата, необратимость удаления и то, что намерения и связи пути остаются
  ///
  /// In en, this message translates to:
  /// **' for {date} will be deleted. This cannot be undone. The intentions and relations of its path stay.'**
  String actionDeleteDialogAfter(String date);

  /// Дата удаляемого действия, совпадающая с текущим локальным днём устройства
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get actionDeleteDialogToday;

  /// Подтвердить удаление действия
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDeleteDialogAction;

  /// Заголовок полосы изменения названия и описания действия
  ///
  /// In en, this message translates to:
  /// **'Edit the action'**
  String get actionTextEditTitle;

  /// Доступное название стрелки назад из изменения названия и описания действия
  ///
  /// In en, this message translates to:
  /// **'Back to the action'**
  String get actionTextEditBack;

  /// Кнопка сохранения названия и описания действия
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionTextEditSave;

  /// Доступное название и заполнитель поля названия действия при изменении
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get actionTextEditNameLabel;

  /// Доступное название поля описания действия при изменении
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get actionTextEditDescriptionLabel;

  /// Вопрос перед уходом с несохранёнными названием и описанием действия
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get actionTextEditDiscardTitle;

  /// Пояснение вопроса перед уходом с несохранёнными названием и описанием действия
  ///
  /// In en, this message translates to:
  /// **'Your changes to the name and description won’t be saved.'**
  String get actionTextEditDiscardMessage;

  /// Действие, которое отменяет изменение названия и описания действия
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get actionTextEditDiscardAction;

  /// Действие, которое возвращает к изменению названия и описания действия
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get actionTextEditContinueAction;

  /// Доступное название полосы вкладок панели действия
  ///
  /// In en, this message translates to:
  /// **'Action sections'**
  String get actionPanelTabsLabel;

  /// Вкладка сохранённого пути действия
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get actionPanelPathTab;

  /// Доступное название вкладки пути с числом намерений
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Path, {count} intention} other{Path, {count} intentions}}'**
  String actionPanelPathTabLabel(int count);

  /// Доступное название вкладки пути, в котором есть архивное намерение или связь
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Path, {count} intention, the path has archived items} other{Path, {count} intentions, the path has archived items}}'**
  String actionPanelPathTabArchivedLabel(int count);

  /// Доступное название кнопки корневого намерения с цепочкой в шапке панели, которая открывает вкладку пути
  ///
  /// In en, this message translates to:
  /// **'Open the action path'**
  String get actionPanelPathButtonLabel;

  /// Метка после удалённого намерения или связи сохранённого пути и после удалённого корневого намерения в шапке
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get actionPathDeletedBadge;

  /// Строка под путём, в котором есть только архивные намерения или связи
  ///
  /// In en, this message translates to:
  /// **'Archived intentions and relations stay in the saved path.'**
  String get actionPathNoteArchived;

  /// Строка под путём, в котором есть только удалённые намерения или связи
  ///
  /// In en, this message translates to:
  /// **'Deleted intentions and relations stay in the saved path as they were.'**
  String get actionPathNoteDeleted;

  /// Строка под путём, в котором есть и архивные, и удалённые намерения или связи
  ///
  /// In en, this message translates to:
  /// **'Archived and deleted intentions and relations stay in the saved path.'**
  String get actionPathNoteArchivedAndDeleted;

  /// Роль первого намерения сохранённого пути в доступном названии его кнопки
  ///
  /// In en, this message translates to:
  /// **'Root intention'**
  String get actionPathRoleRoot;

  /// Роль промежуточного намерения сохранённого пути в доступном названии его кнопки
  ///
  /// In en, this message translates to:
  /// **'Intermediate intention'**
  String get actionPathRoleIntermediate;

  /// Роль последнего намерения сохранённого пути из двух и более в доступном названии его кнопки
  ///
  /// In en, this message translates to:
  /// **'Final intention'**
  String get actionPathRoleFinal;

  /// Доступное название кнопки существующей связи сохранённого пути: тип, намерения звена и приоритет
  ///
  /// In en, this message translates to:
  /// **'Relation {kind}. {source}, {related}. {priority}'**
  String actionPathRelationLabel(
    String kind,
    String source,
    String related,
    String priority,
  );

  /// Вид операции добавления связей
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get graphOperationAddRelations;

  /// Обозначение добавляемой пачки связей
  ///
  /// In en, this message translates to:
  /// **'relations'**
  String get graphOperationRelations;

  /// Число добавленных связей
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} relation added.} other{{count} relations added.}}'**
  String relationsAdded(int count);

  /// Занятая пара при добавлении связей
  ///
  /// In en, this message translates to:
  /// **'Some selected intentions are already linked to this intention. No relations were created.'**
  String get relationsAdditionPairOccupied;

  /// Отсутствующий участник при добавлении связей
  ///
  /// In en, this message translates to:
  /// **'A selected intention no longer exists. No relations were created.'**
  String get relationsAdditionParticipantNotFound;

  /// Архивированный участник при добавлении связей
  ///
  /// In en, this message translates to:
  /// **'Only active intentions can be linked. No relations were created.'**
  String get relationsAdditionParticipantArchived;

  /// Недоступность добавления связей
  ///
  /// In en, this message translates to:
  /// **'No relations were created. Try again.'**
  String get relationsAdditionUnavailable;

  /// Повреждение данных при добавлении связей
  ///
  /// In en, this message translates to:
  /// **'Stored data is damaged. No relations were created.'**
  String get relationsAdditionCorruption;

  /// Неожиданный отказ добавления связей
  ///
  /// In en, this message translates to:
  /// **'No relations were created because of an unexpected error.'**
  String get relationsAdditionUnexpected;

  /// Отсутствие изменяемой связи
  ///
  /// In en, this message translates to:
  /// **'This relation no longer exists.'**
  String get relationEditorUpdateNotFound;

  /// Конфликт изменения типа архивированной связи
  ///
  /// In en, this message translates to:
  /// **'This relation is archived, so its type can’t be changed.'**
  String get relationEditorUpdateArchivedTypeChange;

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
  /// **'This relation is used by a saved daily path. Delete the daily choices that use it first.'**
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

  /// Причина недоступности удаления связи в подробностях
  ///
  /// In en, this message translates to:
  /// **'This relation is used in a saved daily path, so it cannot be deleted.'**
  String get relationDetailsPathProtection;

  /// Доступное название панели архивированной связи; phrase — полная формулировка связи
  ///
  /// In en, this message translates to:
  /// **'{phrase}. Archived'**
  String relationSheetArchivedLabel(String phrase);

  /// Строка о смысле архива под шапкой панели архивированной связи
  ///
  /// In en, this message translates to:
  /// **'Archived relations stay in saved paths and are not offered in new ones.'**
  String get relationSheetArchivedNote;

  /// Доступное название кнопки-названия участника в шапке панели связи; название намерения не переводится
  ///
  /// In en, this message translates to:
  /// **'Open the page of the intention: {title}'**
  String relationSheetOpenParticipant(String title);

  /// Доступное название кнопки-названия архивированного участника в шапке панели связи; название намерения не переводится
  ///
  /// In en, this message translates to:
  /// **'Open the page of the intention: {title}. Archived'**
  String relationSheetOpenArchivedParticipant(String title);

  /// Доступное название пилюли высшего приоритета на панели связи
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}, the highest'**
  String relationSheetPriorityHighest(String priority);

  /// Доступное название пилюли низшего приоритета на панели связи
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}, the lowest'**
  String relationSheetPriorityLowest(String priority);

  /// Заголовок полосы изменения описания на панели связи и название поля
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get relationSheetDescriptionTitle;

  /// Доступное название панели связи во время изменения описания
  ///
  /// In en, this message translates to:
  /// **'Relation description'**
  String get relationSheetDescriptionLabel;

  /// Доступное название стрелки назад при изменении описания связи
  ///
  /// In en, this message translates to:
  /// **'Back to the relation'**
  String get relationSheetDescriptionBack;

  /// Кнопка сохранения описания на панели связи
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get relationSheetDescriptionSave;

  /// Вопрос перед уходом с несохранённым описанием связи
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get relationSheetDescriptionDiscardTitle;

  /// Пояснение вопроса перед уходом с несохранённым описанием связи
  ///
  /// In en, this message translates to:
  /// **'Your changes to the description won’t be saved.'**
  String get relationSheetDescriptionDiscardMessage;

  /// Действие, которое отменяет изменение описания связи
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get relationSheetDescriptionDiscardAction;

  /// Действие, которое возвращает к изменению описания связи
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get relationSheetDescriptionContinueAction;

  /// Доступное название кнопки параметров в шапке панели связи
  ///
  /// In en, this message translates to:
  /// **'Relation options'**
  String get relationSheetOptionsLabel;

  /// Пункт параметров панели активной связи: архивировать
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get relationSheetOptionArchive;

  /// Пункт параметров панели архивированной связи: восстановить
  ///
  /// In en, this message translates to:
  /// **'Restore from archive'**
  String get relationSheetOptionRestore;

  /// Пункт параметров панели связи: удалить
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get relationSheetOptionDelete;

  /// Причина недоступности восстановления связи, когда архивированы оба участника
  ///
  /// In en, this message translates to:
  /// **'Restore the source and related intentions before restoring this relation.'**
  String get relationSheetOptionRestoreBothArchived;

  /// Вопрос подтверждения удаления связи из параметров панели
  ///
  /// In en, this message translates to:
  /// **'Delete relation?'**
  String get relationSheetDeleteDialogTitle;

  /// Текст подтверждения удаления связи до выделенной формулировки связи
  ///
  /// In en, this message translates to:
  /// **'This removes the relation “'**
  String get relationSheetDeleteDialogTextBefore;

  /// Текст подтверждения удаления связи после выделенной формулировки связи
  ///
  /// In en, this message translates to:
  /// **'” with its description and cannot be undone. Both intentions stay.'**
  String get relationSheetDeleteDialogTextAfter;

  /// Отмена удаления связи
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get relationSheetDeleteDialogCancel;

  /// Подтверждение удаления связи
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get relationSheetDeleteDialogConfirm;

  /// Архивное состояние намерения в доступном названии строки экрана выбора
  ///
  /// In en, this message translates to:
  /// **'archived'**
  String get intentionPickerArchived;

  /// Вид намерения с готовностью к действию в доступном названии строки экрана выбора
  ///
  /// In en, this message translates to:
  /// **'action'**
  String get intentionPickerKindAction;

  /// Вид намерения без готовности к действию в доступном названии строки экрана выбора
  ///
  /// In en, this message translates to:
  /// **'intention'**
  String get intentionPickerKindIntention;

  /// Доступное название стрелки строки экрана выбора, которая открывает страницу действия
  ///
  /// In en, this message translates to:
  /// **'Open the page of action {title}'**
  String intentionPickerOpenActionPage(String title);

  /// Доступное название стрелки строки экрана выбора, которая открывает страницу намерения
  ///
  /// In en, this message translates to:
  /// **'Open the page of intention {title}'**
  String intentionPickerOpenIntentionPage(String title);

  /// Доступное название строки каталога, которая открывает страницу намерения; content — содержание строки
  ///
  /// In en, this message translates to:
  /// **'Open: {content}'**
  String intentionCatalogRowLabel(String content);

  /// Заголовок листа параметров показа поиска
  ///
  /// In en, this message translates to:
  /// **'Show and sort'**
  String get intentionPickerShowAndSortTitle;

  /// Пояснение немедленного применения параметров поиска
  ///
  /// In en, this message translates to:
  /// **'The list changes as you choose'**
  String get intentionPickerShowAndSortHint;

  /// Сброс типа и сортировки поиска к начальному показу
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get intentionPickerShowAndSortReset;

  /// Доступное название кнопки заголовка и подзаголовка назначения экрана выбора
  ///
  /// In en, this message translates to:
  /// **'{title}. {subtitle}. Show what you are choosing'**
  String intentionPickerPurposeLabel(String title, String subtitle);

  /// Заголовок листа, который напоминает назначение экрана выбора
  ///
  /// In en, this message translates to:
  /// **'What you are choosing'**
  String get intentionPickerPurposeSheetTitle;

  /// Кнопка, которая закрывает лист назначения и возвращает к выдаче поиска
  ///
  /// In en, this message translates to:
  /// **'Back to the list'**
  String get intentionPickerPurposeSheetBack;

  /// Название группы охвата в листе параметров показа каталога
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get intentionPickerScopeCaption;

  /// Вариант активных намерений в строке и меню охвата листа параметров показа
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get intentionPickerScopeActive;

  /// Вариант архивированных намерений в строке и меню охвата листа параметров показа
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get intentionPickerScopeArchived;

  /// Вариант активных и архивированных намерений в строке и меню охвата листа параметров показа
  ///
  /// In en, this message translates to:
  /// **'All, archived included'**
  String get intentionPickerScopeAll;

  /// Название группы типа намерения
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get intentionPickerTypeCaption;

  /// Вариант без ограничения по типу в строке и меню листа параметров поиска
  ///
  /// In en, this message translates to:
  /// **'Intentions and actions'**
  String get intentionPickerTypeAll;

  /// Вариант намерений без готовности к действию в строке и меню листа параметров поиска
  ///
  /// In en, this message translates to:
  /// **'Intentions only'**
  String get intentionPickerTypeIntentionsOnly;

  /// Вариант действий в строке и меню листа параметров поиска
  ///
  /// In en, this message translates to:
  /// **'Actions only'**
  String get intentionPickerTypeActionsOnly;

  /// Название группы поля сортировки
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get intentionPickerSortCaption;

  /// Сортировка по времени создания
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get intentionPickerSortCreated;

  /// Сортировка по времени изменения
  ///
  /// In en, this message translates to:
  /// **'Date changed'**
  String get intentionPickerSortChanged;

  /// Сортировка по названию
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get intentionPickerSortName;

  /// Убывающий порядок по времени
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get intentionPickerOrderNewest;

  /// Возрастающий порядок по времени
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get intentionPickerOrderOldest;

  /// Прямой порядок по названию
  ///
  /// In en, this message translates to:
  /// **'A to Z'**
  String get intentionPickerOrderAToZ;

  /// Обратный порядок по названию
  ///
  /// In en, this message translates to:
  /// **'Z to A'**
  String get intentionPickerOrderZToA;

  /// Доступное название кнопки направления сортировки в листе параметров поиска: текущий порядок и результат нажатия
  ///
  /// In en, this message translates to:
  /// **'Current order: {currentOrder}. Switch to: {nextOrder}'**
  String intentionPickerOrderButtonSemantics(
    String currentOrder,
    String nextOrder,
  );

  /// Показываемый тип без ограничения в заголовке списка поиска для выбора
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get intentionPickerAllHeader;

  /// Сводка сортировки в заголовке списка поиска для выбора
  ///
  /// In en, this message translates to:
  /// **'Created, newest first'**
  String get intentionPickerOrderCreatedNewest;

  /// Сводка сортировки в заголовке списка поиска для выбора
  ///
  /// In en, this message translates to:
  /// **'Created, oldest first'**
  String get intentionPickerOrderCreatedOldest;

  /// Сводка сортировки в заголовке списка поиска для выбора
  ///
  /// In en, this message translates to:
  /// **'Changed, newest first'**
  String get intentionPickerOrderUpdatedNewest;

  /// Сводка сортировки в заголовке списка поиска для выбора
  ///
  /// In en, this message translates to:
  /// **'Changed, oldest first'**
  String get intentionPickerOrderUpdatedOldest;

  /// Сводка сортировки в заголовке списка поиска для выбора
  ///
  /// In en, this message translates to:
  /// **'Name, A to Z'**
  String get intentionPickerOrderTitleAscending;

  /// Сводка сортировки в заголовке списка поиска для выбора
  ///
  /// In en, this message translates to:
  /// **'Name, Z to A'**
  String get intentionPickerOrderTitleDescending;

  /// Доступное название кнопки заголовка поиска до подтверждения количества
  ///
  /// In en, this message translates to:
  /// **'Show and sort. Type: {type}. Sorted by: {summary}.'**
  String intentionPickerHeaderLabel(String type, String summary);

  /// Доступное название кнопки заголовка поиска с подтверждённым количеством
  ///
  /// In en, this message translates to:
  /// **'Show and sort. Type: {type}, {count}. Sorted by: {summary}.'**
  String intentionPickerHeaderCountLabel(
    String type,
    int count,
    String summary,
  );

  /// Охват и тип словами в заголовке списка каталога намерений; значения select — имена IntentionScope и IntentionTypeChoice
  ///
  /// In en, this message translates to:
  /// **'{scope, select, active{{type, select, all{Active} intentions{Active intentions} actions{Active actions} other{}}} archived{{type, select, all{Archived} intentions{Archived intentions} actions{Archived actions} other{}}} all{{type, select, all{All} intentions{All intentions} actions{All actions} other{}}} other{}}'**
  String intentionPickerScopeHeader(String scope, String type);

  /// Доступное название кнопки заголовка списка каталога до подтверждения количества
  ///
  /// In en, this message translates to:
  /// **'Show and sort. Showing: {title}. Sorted by: {summary}.'**
  String intentionPickerScopeHeaderLabel(String title, String summary);

  /// Доступное название кнопки заголовка списка каталога с подтверждённым количеством
  ///
  /// In en, this message translates to:
  /// **'Show and sort. Showing: {title}, {count}. Sorted by: {summary}.'**
  String intentionPickerScopeHeaderCountLabel(
    String title,
    int count,
    String summary,
  );

  /// Заголовок выдачи поиска действия на экране выбора
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get intentionPickerActionsHeader;

  /// Заголовок выдачи поиска намерения на экране выбора
  ///
  /// In en, this message translates to:
  /// **'Intentions'**
  String get intentionPickerIntentionsHeader;

  /// Доступное название подгрузки следующей порции в поиске намерения
  ///
  /// In en, this message translates to:
  /// **'Loading more intentions'**
  String get intentionPickerLoadingMoreIntentions;

  /// Заголовок пустой выдачи экрана выбора, когда допустимый охват пуст без фильтров
  ///
  /// In en, this message translates to:
  /// **'Nothing to choose from'**
  String get intentionPickerEmptyScopeTitle;

  /// Заголовок пустого выбранного типа, когда в допустимом охвате есть намерения другого типа
  ///
  /// In en, this message translates to:
  /// **'No intentions of this type'**
  String get intentionPickerEmptyTypeTitle;

  /// Совет показать оба типа при пустом выбранном типе
  ///
  /// In en, this message translates to:
  /// **'Show both types to choose from the available intentions.'**
  String get intentionPickerEmptyTypeText;

  /// Действие пустого выбранного типа, которое выбирает тип «Все»
  ///
  /// In en, this message translates to:
  /// **'Show both types'**
  String get intentionPickerShowBothTypes;

  /// Заголовок пустого выбранного типа в каталоге с открытым охватом, который называет охват; значения select — имена IntentionScope и IntentionTypeChoice
  ///
  /// In en, this message translates to:
  /// **'{scope, select, active{{type, select, actions{No active actions} intentions{No active intentions} other{}}} archived{{type, select, actions{No actions in the archive} intentions{No intentions in the archive} other{}}} all{{type, select, actions{No actions yet} intentions{No intentions yet} other{}}} other{}}'**
  String intentionPickerEmptyScopedTypeTitle(String scope, String type);

  /// Текст пустого выбранного типа «Только действия» в каталоге с открытым охватом
  ///
  /// In en, this message translates to:
  /// **'An intention marked as an action is shown here.'**
  String get intentionPickerEmptyActionsText;

  /// Текст пустого выбранного типа «Только намерения» в каталоге с открытым охватом
  ///
  /// In en, this message translates to:
  /// **'Everything here is marked as an action.'**
  String get intentionPickerEmptyIntentionsText;

  /// Заголовок пустого активного охвата каталога, когда в архиве есть намерения
  ///
  /// In en, this message translates to:
  /// **'No active intentions'**
  String get intentionCatalogNoActiveTitle;

  /// Текст пустого активного охвата каталога, когда в архиве есть намерения
  ///
  /// In en, this message translates to:
  /// **'Tap the plus below to create a new one. The Show row brings up the archived ones.'**
  String get intentionCatalogNoActiveText;

  /// Заголовок пустого каталога, когда намерений нет совсем
  ///
  /// In en, this message translates to:
  /// **'No intentions yet'**
  String get intentionCatalogNoIntentionsTitle;

  /// Текст пустого каталога, когда намерений нет совсем
  ///
  /// In en, this message translates to:
  /// **'Your intentions will appear here. Tap the plus below to create the first one.'**
  String get intentionCatalogNoIntentionsText;

  /// Заголовок пустого архивного охвата каталога
  ///
  /// In en, this message translates to:
  /// **'Nothing in the archive'**
  String get intentionCatalogEmptyArchiveTitle;

  /// Текст пустого архивного охвата каталога
  ///
  /// In en, this message translates to:
  /// **'An intention you archive leaves the active list and stays here.'**
  String get intentionCatalogEmptyArchiveText;

  /// Заголовок поиска участников связи
  ///
  /// In en, this message translates to:
  /// **'Choose intentions'**
  String get participantPickerTitle;

  /// Заполнитель и доступное название поля поиска по названию на экране выбора
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get intentionPickerSearchPlaceholder;

  /// Доступное название крестика очистки поля поиска на экране выбора
  ///
  /// In en, this message translates to:
  /// **'Clear the name'**
  String get intentionPickerClearSearch;

  /// Доступное название плюса в шапке поиска участника
  ///
  /// In en, this message translates to:
  /// **'Create intention'**
  String get intentionPickerCreateIntention;

  /// Строка над выдачей поиска участника, которая создаёт намерение с названием из подстроки
  ///
  /// In en, this message translates to:
  /// **'Create “{title}”'**
  String intentionPickerCreateNamed(String title);

  /// Доступное название кнопки фильтра по тегам на экране выбора с числом условий
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Filter by tags} =1{Filter by tags, 1 condition} other{Filter by tags, {count} conditions}}'**
  String intentionPickerFilterLabel(int count);

  /// Заголовок пустой выдачи выбора действия из-за фильтра названия
  ///
  /// In en, this message translates to:
  /// **'No actions with this name'**
  String get intentionPickerNoActionsByTitle;

  /// Заголовок пустой выдачи выбора намерения из-за фильтра названия
  ///
  /// In en, this message translates to:
  /// **'No intentions with this name'**
  String get intentionPickerNoIntentionsByTitle;

  /// Совет пустой выдачи экрана выбора из-за фильтра названия
  ///
  /// In en, this message translates to:
  /// **'Try a shorter name.'**
  String get intentionPickerTryShorterTitle;

  /// Заголовок пустой выдачи выбора действия из-за условий по тегам
  ///
  /// In en, this message translates to:
  /// **'No actions match these tags'**
  String get intentionPickerNoActionsByTags;

  /// Заголовок пустой выдачи выбора намерения из-за условий по тегам
  ///
  /// In en, this message translates to:
  /// **'No intentions match these tags'**
  String get intentionPickerNoIntentionsByTags;

  /// Совет пустой выдачи экрана выбора из-за условий по тегам
  ///
  /// In en, this message translates to:
  /// **'Change the tags in the filter or reset it.'**
  String get intentionPickerChangeTags;

  /// Заголовок пустой выдачи действий из-за фильтра названия и условий по тегам
  ///
  /// In en, this message translates to:
  /// **'No actions found'**
  String get intentionPickerNoActionsFound;

  /// Заголовок пустой выдачи намерений из-за фильтра названия и условий по тегам
  ///
  /// In en, this message translates to:
  /// **'No intentions found'**
  String get intentionPickerNoIntentionsFound;

  /// Совет пустой выдачи экрана выбора из-за фильтра названия и условий по тегам
  ///
  /// In en, this message translates to:
  /// **'Change the name or the tag conditions.'**
  String get intentionPickerChangeTitleOrTags;

  /// Действие пустой выдачи экрана выбора, которое снимает фильтр названия и все условия по тегам
  ///
  /// In en, this message translates to:
  /// **'Reset filters'**
  String get intentionPickerResetFilters;

  /// Отмена выбора участника долговременной связи
  ///
  /// In en, this message translates to:
  /// **'Cancel intention selection'**
  String get participantPickerCancel;

  /// Отсутствие намерений, доступных для выбора участником
  ///
  /// In en, this message translates to:
  /// **'No other intentions are available to select.'**
  String get participantPickerEmpty;

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

  /// Планирование на весь день без конкретного времени
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get dailyChoiceAllDay;

  /// Собственный приоритет дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get dailyChoicePriorityLabel;

  /// Вариант приоритета дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Priority {priority}'**
  String dailyChoicePriorityOption(String priority);

  /// Заголовок раздела дневных выборов в соседстве намерения, пока их количество не получено
  ///
  /// In en, this message translates to:
  /// **'Daily choices'**
  String get dailyChoiceCatalogTitle;

  /// Вход в создание дневного выбора от действия
  ///
  /// In en, this message translates to:
  /// **'Create a choice from an action'**
  String get dailyChoiceCreateFromAction;

  /// Начальная загрузка экрана дня
  ///
  /// In en, this message translates to:
  /// **'Loading actions…'**
  String get actionDayLoading;

  /// Доступное состояние дня календаря, совпадающего с текущим локальным днём устройства, а не с выбранной датой
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dailyChoiceCalendarToday;

  /// Единая пассивная строка отказа получения отметок дней под шапкой календаря, без предложения повтора или другого действия
  ///
  /// In en, this message translates to:
  /// **'Day marks could not be loaded.'**
  String get actionCalendarDayMarksUnavailable;

  /// Команда раскрытия календаря из недели в сетку месяца даты просмотра
  ///
  /// In en, this message translates to:
  /// **'Expand calendar'**
  String get actionCalendarExpand;

  /// Команда сворачивания календаря из сетки месяца в неделю даты просмотра
  ///
  /// In en, this message translates to:
  /// **'Collapse calendar'**
  String get actionCalendarCollapse;

  /// Доступное название команды заголовка месяца, открывающей выбор года и месяца
  ///
  /// In en, this message translates to:
  /// **'Choose year and month'**
  String get actionCalendarChooseYearAndMonth;

  /// Доступное название команды заголовка, закрывающей выбор года и месяца и возвращающей сетку дней месяца просмотра
  ///
  /// In en, this message translates to:
  /// **'Back to the days of the month'**
  String get actionCalendarBackToMonthDays;

  /// Доступное название команды перехода к предыдущей странице из двенадцати лет в выборе года
  ///
  /// In en, this message translates to:
  /// **'Previous years'**
  String get actionCalendarPreviousYears;

  /// Доступное название команды перехода к следующей странице из двенадцати лет в выборе года
  ///
  /// In en, this message translates to:
  /// **'Next years'**
  String get actionCalendarNextYears;

  /// Доступное название команды перехода к месяцам предыдущего года в выборе месяца
  ///
  /// In en, this message translates to:
  /// **'Previous year'**
  String get actionCalendarPreviousYear;

  /// Доступное название команды перехода к месяцам следующего года в выборе месяца
  ///
  /// In en, this message translates to:
  /// **'Next year'**
  String get actionCalendarNextYear;

  /// Заголовок секции невыполненных действий дня
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get actionDaySectionIncomplete;

  /// Заголовок секции выполненных действий дня
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get actionDaySectionCompleted;

  /// Заголовок пустого состояния дня без действий
  ///
  /// In en, this message translates to:
  /// **'No actions for this date'**
  String get actionDayEmptyTitle;

  /// Текст пустого состояния дня без действий
  ///
  /// In en, this message translates to:
  /// **'Every action here serves one of your intentions.'**
  String get actionDayEmptyText;

  /// Обновление подтверждённого снимка экрана дня
  ///
  /// In en, this message translates to:
  /// **'Refreshing…'**
  String get actionDayRefreshing;

  /// Доступное название кнопки возврата выдачи к заголовку дня
  ///
  /// In en, this message translates to:
  /// **'Back to top'**
  String get actionDayScrollToTop;

  /// Загрузка следующей порции
  ///
  /// In en, this message translates to:
  /// **'Loading more actions…'**
  String get actionDayLoadingMore;

  /// Временная ошибка чтения действий дня
  ///
  /// In en, this message translates to:
  /// **'Could not load actions.'**
  String get actionDayUnavailable;

  /// Повреждение данных действий дня
  ///
  /// In en, this message translates to:
  /// **'Stored action data is damaged and cannot be shown.'**
  String get actionDayCorruption;

  /// Устаревший снимок выдачи дня
  ///
  /// In en, this message translates to:
  /// **'The list changed. Refresh it to continue.'**
  String get actionDayExpired;

  /// Непредвиденная ошибка чтения действий дня
  ///
  /// In en, this message translates to:
  /// **'Could not load actions because of an unexpected error.'**
  String get actionDayUnexpected;

  /// Число намерений сохранённого пути в доступном названии строки
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} intention in path} other{{count} intentions in path}}'**
  String actionDayPathIntentionCount(int count);

  /// Доступное название отдельного флажка с принадлежностью действию и приоритетом; состояние сообщает сам флажок
  ///
  /// In en, this message translates to:
  /// **'Completion of action #{number}. {action}. {priority}'**
  String actionDayCompletionLabel(int number, String action, String priority);

  /// Начало доступного названия строки с порядковым номером текущей выдачи
  ///
  /// In en, this message translates to:
  /// **'Action #{number}. {action}'**
  String actionDayRowLabel(int number, String action);

  /// Корневое намерение в доступном названии строки
  ///
  /// In en, this message translates to:
  /// **'Root intention: {root}'**
  String actionDayRowRoot(String root);

  /// Запланированное время в доступном названии строки
  ///
  /// In en, this message translates to:
  /// **'At {time}'**
  String actionDayRowTime(String time);

  /// Заголовок подробностей дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice'**
  String get dailyChoiceDetailsTitle;

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

  /// Действие выполнено
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get actionCompleted;

  /// Действие не выполнено
  ///
  /// In en, this message translates to:
  /// **'Not completed'**
  String get actionNotCompleted;

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

  /// Порядковый номер перехода пути
  ///
  /// In en, this message translates to:
  /// **'Transition {number}'**
  String dailyChoiceDetailsStep(int number);

  /// Доступное название ручки компактной панели дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Expand daily choice sheet'**
  String get dailyChoiceSheetExpand;

  /// Доступное название ручки раскрытой панели дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Collapse daily choice sheet'**
  String get dailyChoiceSheetCollapse;

  /// Доступное название флажка в шапке панели; состояние сообщает сам флажок
  ///
  /// In en, this message translates to:
  /// **'Completion of the choice. {action}. {priority}'**
  String dailyChoiceSheetCompletionLabel(String action, String priority);

  /// Доступное название кнопки параметров в шапке панели дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice options'**
  String get dailyChoiceSheetOptionsLabel;

  /// Доступное название полосы вкладок панели дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice sections'**
  String get dailyChoiceSheetTabsLabel;

  /// Вкладка сохранённого пути в панели дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get dailyChoiceSheetPathTab;

  /// Доступное название вкладки пути с числом шагов
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Path, {count} step} other{Path, {count} steps}}'**
  String dailyChoiceSheetPathTabLabel(int count);

  /// Доступное название вкладки пути, в котором что-то архивировано
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Path, {count} step, something in it is archived} other{Path, {count} steps, something in it is archived}}'**
  String dailyChoiceSheetPathTabArchivedLabel(int count);

  /// Пояснение под путём с архивированными намерениями или связями
  ///
  /// In en, this message translates to:
  /// **'The path contains archived intentions or relations.'**
  String get dailyChoiceSheetPathArchivedNote;

  /// Заголовок полосы изменения описания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get dailyChoiceSheetDescriptionTitle;

  /// Доступное название стрелки назад из изменения описания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Back to the daily choice'**
  String get dailyChoiceSheetDescriptionBack;

  /// Кнопка сохранения описания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get dailyChoiceSheetDescriptionSave;

  /// Вопрос перед уходом с несохранённым описанием дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get dailyChoiceSheetDescriptionDiscardTitle;

  /// Пояснение вопроса перед уходом с несохранённым описанием дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Your changes to the description won’t be saved.'**
  String get dailyChoiceSheetDescriptionDiscardMessage;

  /// Действие, которое отменяет изменение описания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get dailyChoiceSheetDescriptionDiscardAction;

  /// Действие, которое возвращает к изменению описания дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get dailyChoiceSheetDescriptionContinueAction;

  /// Название поля даты дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dailyChoiceFieldDate;

  /// Название поля времени дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get dailyChoiceFieldTime;

  /// Доступное название поля даты: название поля, полное значение и действие
  ///
  /// In en, this message translates to:
  /// **'Date: {date}. Change date'**
  String dailyChoiceFieldDateLabel(String date);

  /// Доступное название поля времени: название поля, значение и действие
  ///
  /// In en, this message translates to:
  /// **'Time: {time}. Change time'**
  String dailyChoiceFieldTimeLabel(String time);

  /// Доступное название листа даты дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice date'**
  String get dailyChoiceDateSheetLabel;

  /// Доступное название листа времени дневного выбора
  ///
  /// In en, this message translates to:
  /// **'Daily choice time'**
  String get dailyChoiceTimeSheetLabel;

  /// Доступное название переключателя половины суток на 12-часовом циферблате
  ///
  /// In en, this message translates to:
  /// **'Half of the day'**
  String get dailyChoiceTimeHalfSwitchLabel;

  /// Доступное название половины суток до полудня
  ///
  /// In en, this message translates to:
  /// **'Before noon'**
  String get dailyChoiceTimeAmLabel;

  /// Доступное название половины суток после полудня
  ///
  /// In en, this message translates to:
  /// **'After noon'**
  String get dailyChoiceTimePmLabel;

  /// Дата выбора, которая наступит завтра
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dailyChoiceDateTomorrow;

  /// Дата выбора, которая была вчера
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dailyChoiceDateYesterday;

  /// Отмена всего создания до принятия команды или после отказа
  ///
  /// In en, this message translates to:
  /// **'Cancel creation'**
  String get creationCancelAction;

  /// Выход из создания после принятия команды или завершения потока без обещания отменить запись
  ///
  /// In en, this message translates to:
  /// **'Leave creation'**
  String get creationLeaveAction;

  /// Объяснение выхода из создания во время принятой записи
  ///
  /// In en, this message translates to:
  /// **'Saving will continue after you leave creation.'**
  String get creationSavingContinues;

  /// No description provided for @batchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add to \"{group}\"'**
  String batchSubtitle(String group);

  /// No description provided for @batchSubtitleSelected.
  ///
  /// In en, this message translates to:
  /// **'Add to \"{group}\" · selected {count}'**
  String batchSubtitleSelected(String group, int count);

  /// No description provided for @batchSheetLine.
  ///
  /// In en, this message translates to:
  /// **'New relations in \"{group}\"'**
  String batchSheetLine(String group);

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'Each selected intention will become a relation: this intention needs it'**
  String get batchNoteNeeds;

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'Each selected intention will become a relation: this intention can use it'**
  String get batchNoteCanUse;

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'Each selected intention will become a relation: it needs this intention'**
  String get batchNoteNeededFor;

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'Each selected intention will become a relation: it can use this intention'**
  String get batchNoteCanBeUsedFor;

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'Relations will have priority P4 and no description; both can be changed on the page'**
  String get batchDefaults;

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'The intention whose page you came from'**
  String get batchAnchorNote;

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'Nothing selected yet'**
  String get batchEmpty;

  /// Текст поиска участников группы
  ///
  /// In en, this message translates to:
  /// **'Selected intentions'**
  String get batchSelected;

  /// No description provided for @batchSourceSemantic.
  ///
  /// In en, this message translates to:
  /// **'Source intention: {name}'**
  String batchSourceSemantic(String name);

  /// No description provided for @batchRelatedSemantic.
  ///
  /// In en, this message translates to:
  /// **'Related intention: {name}'**
  String batchRelatedSemantic(String name);

  /// No description provided for @batchRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove selection: {name}'**
  String batchRemove(String name);

  /// Кнопка внизу поиска участника группы
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Add {count} relation} other{Add {count} relations}}'**
  String batchAddCount(int count);

  /// Недоступная кнопка поиска участника группы без отметок
  ///
  /// In en, this message translates to:
  /// **'Add relations'**
  String get batchAddNone;

  /// Кнопка поиска участника группы во время добавления
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get batchAdding;

  /// Вопрос перед сбросом отметок поиска
  ///
  /// In en, this message translates to:
  /// **'Discard selected intentions?'**
  String get batchDiscardTitle;

  /// Число связей при сбросе отметок поиска
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} relation will not be added.} other{{count} relations will not be added.}}'**
  String batchDiscardMessage(int count);

  /// При сбросе отметок созданные намерения сохраняются
  ///
  /// In en, this message translates to:
  /// **'Created intentions will remain in the catalog.'**
  String get batchCreatedRemain;

  /// Сбросить отметки поиска
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get batchDiscardAction;

  /// Продолжить отмечать намерения
  ///
  /// In en, this message translates to:
  /// **'Continue selecting'**
  String get batchContinueAction;
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
