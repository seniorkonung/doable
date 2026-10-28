// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Doable';

  @override
  String get navigationActiveIntentions => 'Активные намерения';

  @override
  String get navigationArchive => 'Архив';

  @override
  String get appDestinationHome => 'Главная';

  @override
  String get appDestinationDailyChoices => 'Дневные выборы';

  @override
  String get appDestinationIntentionGraph => 'Граф намерений';

  @override
  String get statisticsSourceIntentions => 'Исходные намерения';

  @override
  String get statisticsIntermediateIntentions => 'Промежуточные намерения';

  @override
  String get statisticsSelectedActions => 'Выбранные действия';

  @override
  String get statisticsThroughRelations => 'Весь вклад';

  @override
  String get statisticsMonthTab => 'Месяц';

  @override
  String get statisticsYearTab => 'Год';

  @override
  String statisticsMonthPeriod(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMM(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String statisticsYearPeriod(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.y(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String statisticsMonthName(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.MMMM(localeName);
    final String dateString = dateDateFormat.format(date);

    return '$dateString';
  }

  @override
  String get statisticsPreviousMonth => 'Предыдущий месяц';

  @override
  String get statisticsNextMonth => 'Следующий месяц';

  @override
  String get statisticsPreviousYear => 'Предыдущий год';

  @override
  String get statisticsNextYear => 'Следующий год';

  @override
  String get statisticsExpandPeriodSelector => 'Развернуть выбор периода';

  @override
  String get statisticsCollapsePeriodSelector => 'Свернуть выбор периода';

  @override
  String get statisticsCurrentPeriod => 'Текущий период';

  @override
  String get statisticsPeriodSummary => 'Сводка периода';

  @override
  String get statisticsViewLabel => 'Вид статистики';

  @override
  String statisticsTotalItems(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString элемента',
      many: '$countString элементов',
      few: '$countString элемента',
      one: '$countString элемент',
    );
    return '$_temp0';
  }

  @override
  String statisticsPlannedContribution(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Запланированный вклад: $countString';
  }

  @override
  String statisticsContribution(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Вклад: $countString';
  }

  @override
  String statisticsMissed(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Пропущено: $countString';
  }

  @override
  String statisticsUpcoming(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Предстоит: $countString';
  }

  @override
  String statisticsContributionCounts(int contribution, int planned) {
    final intl.NumberFormat contributionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String contributionString = contributionNumberFormat.format(
      contribution,
    );
    final intl.NumberFormat plannedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String plannedString = plannedNumberFormat.format(planned);

    return '$contributionString из $plannedString';
  }

  @override
  String statisticsContributionCountsSemantics(int contribution, int planned) {
    final intl.NumberFormat contributionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String contributionString = contributionNumberFormat.format(
      contribution,
    );
    final intl.NumberFormat plannedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String plannedString = plannedNumberFormat.format(planned);

    return 'Вклад: $contributionString. Запланированный вклад: $plannedString';
  }

  @override
  String statisticsContributionShare(num share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return 'Доля вклада периода: $shareString';
  }

  @override
  String get statisticsNoContributionShare =>
      'Доля отсутствует: вклад периода равен нулю';

  @override
  String get statisticsLoading => 'Загружаем статистику…';

  @override
  String get statisticsEmpty =>
      'За выбранный период нет засчитанных дневных выборов для этого вида.';

  @override
  String get statisticsRefreshing => 'Обновляем статистику…';

  @override
  String get statisticsLoadingMore => 'Загружаем ещё элементы…';

  @override
  String get statisticsUnavailable =>
      'Не удалось загрузить статистику. Повторите попытку.';

  @override
  String get statisticsCorruption =>
      'Сохранённые данные повреждены. Статистика недоступна.';

  @override
  String get statisticsUnexpectedFailure =>
      'Не удалось загрузить статистику из-за непредвиденной ошибки.';

  @override
  String get statisticsRefreshUnavailable =>
      'Статистика не обновлена: не удалось получить изменения. Повторите попытку.';

  @override
  String get statisticsRefreshCorruption =>
      'Статистика не обновлена: сохранённые данные повреждены.';

  @override
  String get statisticsRefreshUnexpectedFailure =>
      'Статистика не обновлена из-за непредвиденной ошибки.';

  @override
  String get statisticsLoadMoreUnavailable =>
      'Не удалось загрузить следующие элементы. Повторите попытку.';

  @override
  String get statisticsLoadMoreCorruption =>
      'Следующие элементы недоступны: сохранённые данные повреждены.';

  @override
  String get statisticsLoadMoreUnexpectedFailure =>
      'Не удалось загрузить следующие элементы из-за непредвиденной ошибки.';

  @override
  String get statisticsSectionTitle => 'Статистика';

  @override
  String get statisticsBreakdownSourceIntentions => 'По исходным намерениям';

  @override
  String get statisticsBreakdownSelectedActions => 'По выбранным действиям';

  @override
  String get statisticsBreakdownRelations => 'По связям';

  @override
  String statisticsExplicitPathChoices(int count, int planned) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);
    final intl.NumberFormat plannedNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String plannedString = plannedNumberFormat.format(planned);

    return 'Дневные выборы с намерением на сохранённом пути выбора: $countString из $plannedString';
  }

  @override
  String statisticsBreakdownContributionShare(num share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return 'Доля вклада намерения в этом виде: $shareString';
  }

  @override
  String get statisticsBreakdownNoContributionShare =>
      'Доля отсутствует: вклад намерения в этом виде равен нулю';

  @override
  String get statisticsRefreshUnavailableShort => 'Нет обновления.';

  @override
  String get statisticsRefreshCorruptionShort => 'Данные повреждены.';

  @override
  String get statisticsRefreshUnexpectedShort => 'Ошибка обновления.';

  @override
  String get statisticsCalendarDayAllCompleted =>
      'Все засчитанные дневные выборы выполнены';

  @override
  String get statisticsCalendarDayHasIncomplete =>
      'Есть невыполненный засчитанный дневной выбор';

  @override
  String get statisticsCalendarDayNoChoices =>
      'Нет засчитанных дневных выборов';

  @override
  String statisticsCalendarDaySemantics(DateTime date, String dayStatus) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMMEEEEd(
      localeName,
    );
    final String dateString = dateDateFormat.format(date);

    return '$dateString. $dayStatus';
  }

  @override
  String statisticsMonthBarSemantics(DateTime month, String counts) {
    final intl.DateFormat monthDateFormat = intl.DateFormat.yMMMM(localeName);
    final String monthString = monthDateFormat.format(month);

    return '$monthString. $counts';
  }

  @override
  String statisticsViewCardSemantics(
    String view,
    String period,
    String counts,
  ) {
    return '$view. $period. $counts';
  }

  @override
  String get quickCreationLabel => 'Быстрое создание';

  @override
  String get quickCreationChangeMode => 'Сменить режим';

  @override
  String get quickCreationMenuTitle => 'Что создаёт кнопка';

  @override
  String get quickCreationMenuPrompt => 'Нажатие на плюс создаст выбранное';

  @override
  String get quickCreationLongPressHint =>
      'Нажмите и удерживайте, чтобы сменить режим';

  @override
  String get quickCreationModeIntention => 'Новое намерение';

  @override
  String get quickCreationModeIntentionHint =>
      'То, что вы хотите сделать или изменить';

  @override
  String get quickCreationModeRelation => 'Новая связь';

  @override
  String get quickCreationModeRelationHint => 'Чтобы …, нужно или можно …';

  @override
  String get quickCreationModeDailyChoice => 'Новый дневной выбор';

  @override
  String get quickCreationModeDailyChoiceHint =>
      'Действие для намерения в выбранный день';

  @override
  String get quickCreationDailyChoiceStartPrompt => 'С чего начать';

  @override
  String get quickCreationDailyChoiceFromIntention => 'От намерения';

  @override
  String get quickCreationDailyChoiceFromIntentionHint =>
      'Сначала намерение, затем действие для него';

  @override
  String get quickCreationDailyChoiceFromAction => 'От действия';

  @override
  String get quickCreationDailyChoiceFromActionHint =>
      'Сначала действие, затем намерение, которому оно служит';

  @override
  String get commonLoading => 'Загрузка…';

  @override
  String get commonEmpty => 'Пока здесь ничего нет';

  @override
  String get commonError => 'Что-то пошло не так';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get bootstrapLoading => 'Подготавливаем локальные данные…';

  @override
  String get bootstrapMigrationFailure =>
      'Не удалось подготовить локальные данные. Данные не изменены. Повторите попытку.';

  @override
  String get bootstrapCorruption =>
      'Локальные данные повреждены и не могут быть открыты.';

  @override
  String get bootstrapIncompatibleSchema =>
      'Чтобы продолжить, установите совместимое обновление Doable.';

  @override
  String get bootstrapUnexpectedFailure =>
      'Не удалось открыть локальные данные из-за непредвиденной ошибки.';

  @override
  String get catalogLoading => 'Загружаем намерения…';

  @override
  String get catalogScopeLabel => 'Охват';

  @override
  String get catalogScopeActive => 'Активные';

  @override
  String get catalogScopeArchived => 'Архивные';

  @override
  String get catalogScopeAll => 'Все';

  @override
  String get catalogFilterLabel => 'Фильтр по названию';

  @override
  String get catalogFilterInvalidUnicode =>
      'Введите корректный Unicode-текст без NUL.';

  @override
  String get catalogFilterTooLong => 'Используйте не более 255 символов.';

  @override
  String get catalogOrderLabel => 'Порядок';

  @override
  String get catalogOrderCreatedNewest => 'По созданию: сначала новые';

  @override
  String get catalogOrderCreatedOldest => 'По созданию: сначала старые';

  @override
  String get catalogOrderUpdatedNewest => 'По изменению: сначала новые';

  @override
  String get catalogOrderUpdatedOldest => 'По изменению: сначала старые';

  @override
  String catalogTotalCount(int count) {
    return 'Всего намерений: $count';
  }

  @override
  String get catalogActiveEmpty => 'Активных намерений пока нет.';

  @override
  String get catalogArchivedEmpty => 'Архивных намерений пока нет.';

  @override
  String get catalogAllEmpty => 'Намерений пока нет.';

  @override
  String get catalogTagConditionsEmpty =>
      'По условиям по тегам совпадений нет.';

  @override
  String get catalogUnavailable =>
      'Не удалось загрузить намерения. Повторите попытку.';

  @override
  String get catalogCorruption =>
      'Сохранённые данные намерений повреждены и не могут быть показаны.';

  @override
  String get catalogUnexpectedFailure =>
      'Не удалось загрузить намерения из-за непредвиденной ошибки.';

  @override
  String get catalogLoadingMore => 'Загружаем ещё намерения…';

  @override
  String get catalogLoadMoreUnavailable =>
      'Не удалось загрузить следующие намерения.';

  @override
  String get catalogLoadMoreCorruption =>
      'Сохранённые данные повреждены; следующие намерения нельзя показать.';

  @override
  String get catalogLoadMoreUnexpected =>
      'Не удалось загрузить следующие намерения из-за непредвиденной ошибки.';

  @override
  String get catalogReady => 'Готово к действию';

  @override
  String get catalogNotReady => 'Не готово к действию';

  @override
  String get catalogHasDescription => 'Есть описание';

  @override
  String get catalogNoDescription => 'Нет описания';

  @override
  String intentionSummaryTags(String tags) {
    return 'Теги: $tags';
  }

  @override
  String get intentionSummaryNoTags => 'Без тегов';

  @override
  String get relationNeighborhoodTitle => 'Связи';

  @override
  String get relationNeighborhoodSummaryLoading => 'Загружаем связи и сводку…';

  @override
  String get relationNeighborhoodSummaryUnavailable =>
      'Не удалось загрузить сводку связей.';

  @override
  String get relationNeighborhoodSavedSummaryRefreshing =>
      'Обновляем сохранённые числа связей…';

  @override
  String get relationNeighborhoodSavedSummaryStale =>
      'Сохранённые числа связей устарели: обновить данные не удалось.';

  @override
  String relationNeighborhoodTotal(int count) {
    return 'Всего связей: $count';
  }

  @override
  String relationNeighborhoodActiveTotal(int count) {
    return 'Активных связей: $count';
  }

  @override
  String relationNeighborhoodArchivedTotal(int count) {
    return 'Архивных связей: $count';
  }

  @override
  String relationNeighborhoodNeedTotal(int count) {
    return 'Нужно: $count';
  }

  @override
  String relationNeighborhoodCanTotal(int count) {
    return 'Можно: $count';
  }

  @override
  String relationNeighborhoodDailyTotal(int count) {
    return 'Дневных выборов: $count';
  }

  @override
  String get relationNeighborhoodDailySourceRole => 'Исходное намерение';

  @override
  String get relationNeighborhoodDailySelectedRole => 'Выбранное действие';

  @override
  String get relationNeighborhoodLongTermGroups => 'Долговременные связи';

  @override
  String get relationNeighborhoodScopeLabel => 'Состояние связей';

  @override
  String get relationNeighborhoodScopeActive => 'Активные связи';

  @override
  String get relationNeighborhoodScopeArchived => 'Архивные связи';

  @override
  String get relationNeighborhoodTypeLabel => 'Тип связи';

  @override
  String get relationNeighborhoodTypeNeed => 'Нужно';

  @override
  String get relationNeighborhoodTypeCan => 'Можно';

  @override
  String get relationNeighborhoodDirectionLabel => 'Направление';

  @override
  String get relationNeighborhoodDirectionIncoming => 'Входящие';

  @override
  String get relationNeighborhoodDirectionOutgoing => 'Исходящие';

  @override
  String relationNeighborhoodSelectedGroupCount(int count) {
    return 'Во всей выбранной группе: $count';
  }

  @override
  String get relationNeighborhoodInitialUnavailable =>
      'Не удалось загрузить связи и сводку. Повторите попытку.';

  @override
  String get relationNeighborhoodInitialCorruption =>
      'Сохранённые данные связей повреждены и не могут быть показаны.';

  @override
  String get relationNeighborhoodInitialUnexpected =>
      'Не удалось загрузить связи из-за непредвиденной ошибки.';

  @override
  String get relationNeighborhoodInitialInvalid =>
      'Выбранную группу связей больше нельзя открыть.';

  @override
  String get relationNeighborhoodIntentionNotFound =>
      'Намерение для просмотра связей больше не существует.';

  @override
  String get relationNeighborhoodEmpty => 'В этой группе связей нет.';

  @override
  String get relationNeighborhoodLoadingMore => 'Загружаем ещё связи…';

  @override
  String get relationNeighborhoodLoadMoreUnavailable =>
      'Не удалось загрузить следующие связи.';

  @override
  String get relationNeighborhoodLoadMoreCorruption =>
      'Сохранённые данные повреждены; следующие связи нельзя показать.';

  @override
  String get relationNeighborhoodLoadMoreUnexpected =>
      'Не удалось загрузить следующие связи из-за непредвиденной ошибки.';

  @override
  String get relationNeighborhoodLoadMoreInvalid =>
      'Продолжение этой группы больше недействительно.';

  @override
  String get relationNeighborhoodRefreshing => 'Обновляем связи…';

  @override
  String get relationNeighborhoodRefreshFailed =>
      'Не удалось обновить связи. Ранее загруженные данные по-прежнему показаны.';

  @override
  String get relationNeighborhoodConfirmedEnd =>
      'Все связи этой группы загружены.';

  @override
  String get relationNeighborhoodRelationActive => 'Активная связь';

  @override
  String get relationNeighborhoodRelationArchived => 'Связь в архиве';

  @override
  String relationNeighborhoodPriority(String priority) {
    return 'Приоритет $priority';
  }

  @override
  String get relationNeighborhoodSourceParticipant => 'Исходное намерение';

  @override
  String get relationNeighborhoodRelatedParticipant => 'Связанное намерение';

  @override
  String relationNeighborhoodNeedPhrase(String source, String related) {
    return 'Чтобы $source, нужно $related';
  }

  @override
  String relationNeighborhoodCanPhrase(String source, String related) {
    return 'Чтобы $source, можно $related';
  }

  @override
  String get detailsTabsLabel => 'Разделы намерения';

  @override
  String get detailsOverviewTab => 'Обзор';

  @override
  String get detailsRelationsTab => 'Связи';

  @override
  String detailsRelationsTabSemantic(int active, int archived) {
    return 'Связи: активных — $active, архивированных — $archived';
  }

  @override
  String get detailsTitle => 'Подробности намерения';

  @override
  String get detailsTypeIntention => 'Намерение';

  @override
  String get detailsTypeAction => 'Действие';

  @override
  String get detailsLoading => 'Загрузка намерения…';

  @override
  String get detailsNotFound => 'Намерение не найдено.';

  @override
  String get detailsUnavailable =>
      'Не удалось загрузить намерение. Повторите попытку.';

  @override
  String get detailsCorruption =>
      'Сохранённые данные намерения повреждены, их нельзя показать.';

  @override
  String get detailsUnexpected =>
      'Не удалось загрузить намерение из-за непредвиденной ошибки.';

  @override
  String get detailsOperationRunning => 'Сохранение изменений…';

  @override
  String get detailsDescriptionLabel => 'Описание';

  @override
  String get detailsNoDescription => 'Нет описания';

  @override
  String get detailsReadinessLabel => 'Готовность к действию';

  @override
  String get detailsArchiveStateLabel => 'Состояние';

  @override
  String get detailsActive => 'Активно';

  @override
  String get detailsArchived => 'В архиве';

  @override
  String get detailsEditAction => 'Изменить';

  @override
  String get detailsSaveAction => 'Сохранить изменения';

  @override
  String get detailsCancelEditAction => 'Отмена';

  @override
  String get detailsEnableReadinessAction => 'Отметить готовым к действию';

  @override
  String get detailsDisableReadinessAction => 'Отметить неготовым к действию';

  @override
  String get detailsReadinessConfirmationTitle => 'Готово к действию?';

  @override
  String get detailsReadinessOneDayCriterion =>
      'Его можно полностью выполнить в течение одного дня.';

  @override
  String get detailsReadinessClarityCriterion =>
      'Человеку достаточно понятно, что именно нужно сделать.';

  @override
  String get detailsConfirmReadinessAction => 'Отметить готовым';

  @override
  String get detailsArchiveAction => 'Архивировать';

  @override
  String get detailsRestoreAction => 'Восстановить';

  @override
  String get detailsDeleteAction => 'Удалить навсегда';

  @override
  String get detailsDeleteConfirmationTitle => 'Удалить намерение навсегда?';

  @override
  String get detailsDeleteConfirmationMessage =>
      'Это действие нельзя отменить. Намерение, его описание и все назначения тегов, включая не показанные сейчас, будут удалены навсегда. Сами теги сохранятся.';

  @override
  String get detailsConfirmDeleteAction => 'Удалить навсегда';

  @override
  String get detailsDeleted => 'Намерение удалено.';

  @override
  String get detailsReadinessEnabled =>
      'Намерение отмечено готовым к действию.';

  @override
  String get detailsReadinessDisabled =>
      'Намерение отмечено неготовым к действию.';

  @override
  String get detailsArchivedSuccess => 'Намерение архивировано.';

  @override
  String get detailsRestoredSuccess => 'Намерение восстановлено.';

  @override
  String get detailsStateChangeInvalid =>
      'Не удалось изменить состояние намерения.';

  @override
  String get detailsStateChangeNotFound =>
      'Намерение больше не существует. Его состояние не изменено.';

  @override
  String get detailsStateChangeConflict =>
      'Намерение было изменено в другом месте. Его состояние не изменено.';

  @override
  String get detailsStateChangeUnavailable =>
      'Не удалось изменить состояние намерения. Повторите попытку.';

  @override
  String get detailsStateChangeCorruption =>
      'Сохранённые данные повреждены. Состояние намерения не изменено.';

  @override
  String get detailsStateChangeUnexpected =>
      'Не удалось изменить состояние намерения из-за непредвиденной ошибки.';

  @override
  String get detailsDeleteInvalid => 'Не удалось удалить намерение.';

  @override
  String get detailsDeleteNotFound =>
      'Намерение больше не существует. Оно не удалено.';

  @override
  String get detailsDeleteConflict =>
      'Намерение изменено в другом месте и не удалено.';

  @override
  String get detailsDeleteBlockedByRelations =>
      'Намерение не удалено: его связи блокируют удаление. Архивные и ещё не загруженные связи тоже блокируют.';

  @override
  String get detailsArchiveCascadeExplanation =>
      'Архивирование также архивирует непосредственные связи намерения. Соседние намерения и их остальные связи не изменяются.';

  @override
  String detailsRestoreRelationsExplanation(int count) {
    return 'Восстановление возвращает только само намерение. Его связи остаются в архиве: $count.';
  }

  @override
  String get detailsShowArchivedRelationsAction => 'Показать архив связей';

  @override
  String get detailsDeleteUnavailable =>
      'Не удалось удалить намерение. Повторите попытку.';

  @override
  String get detailsDeleteCorruption =>
      'Сохранённые данные повреждены. Намерение не удалено.';

  @override
  String get detailsDeleteUnexpected =>
      'Не удалось удалить намерение из-за непредвиденной ошибки.';

  @override
  String get detailsUpdateInvalidInput => 'Проверьте введённые данные.';

  @override
  String get detailsUpdateNotFound =>
      'Намерение больше не существует. Изменения не сохранены.';

  @override
  String get detailsUpdateConflict =>
      'Намерение было изменено в другом месте. Ваши изменения не сохранены.';

  @override
  String get detailsUpdateUnavailable =>
      'Не удалось сохранить изменения. Повторите попытку.';

  @override
  String get detailsUpdateCorruption =>
      'Сохранённые данные повреждены. Изменения не сохранены.';

  @override
  String get detailsUpdateUnexpected =>
      'Не удалось сохранить изменения из-за непредвиденной ошибки.';

  @override
  String get intentionEditTitle => 'Изменить намерение';

  @override
  String get intentionEditSaveAction => 'Сохранить';

  @override
  String get intentionEditNameLabel => 'Название';

  @override
  String get intentionEditDescriptionLabel => 'Описание';

  @override
  String get intentionEditDescriptionPlaceholder => 'Добавить описание';

  @override
  String get editorTitle => 'Создать намерение';

  @override
  String get editorCreateAction => 'Создать намерение';

  @override
  String get editorSaveAction => 'Сохранить';

  @override
  String get editorSaving => 'Сохраняем…';

  @override
  String get editorTitleLabel => 'Название';

  @override
  String get editorDescriptionLabel => 'Описание (необязательно)';

  @override
  String get editorTitleEmpty => 'Введите название.';

  @override
  String get editorTitleTooLong => 'Используйте не более 255 символов.';

  @override
  String get editorTitleInvalidUnicode =>
      'Введите корректный Unicode-текст без NUL.';

  @override
  String get editorDescriptionTooLong => 'Используйте не более 4096 символов.';

  @override
  String get editorDescriptionInvalidUnicode =>
      'Введите корректный Unicode-текст без NUL.';

  @override
  String get editorInvalidInput => 'Проверьте введённые данные.';

  @override
  String get editorCreateConflict =>
      'Не удалось создать намерение из-за конфликта.';

  @override
  String get editorCreateUnavailable =>
      'Не удалось создать намерение. Повторите попытку.';

  @override
  String get editorCreateCorruption =>
      'Сохранённые данные повреждены. Намерение не создано.';

  @override
  String get editorCreateUnexpected =>
      'Не удалось создать намерение из-за непредвиденной ошибки.';

  @override
  String get editorCreated => 'Намерение создано.';

  @override
  String get editorCloseDiscardTitle => 'Сбросить черновик?';

  @override
  String get editorCloseDiscardMessage =>
      'Введённые данные нового намерения не сохранены и будут потеряны.';

  @override
  String get editorCloseContinueAction => 'Продолжить ввод';

  @override
  String get editorCloseDiscardAction => 'Сбросить';

  @override
  String get editorCloseSavingTitle => 'Закрыть форму?';

  @override
  String get editorCloseSavingMessage =>
      'Сохранение уже выполняется и продолжится после закрытия формы. Если сохранить не удастся, введённые данные не восстановятся.';

  @override
  String get editorCloseSavingStayAction => 'Остаться';

  @override
  String get editorCloseSavingLeaveAction => 'Закрыть';

  @override
  String get editorCloseFormAction => 'Закрыть форму';

  @override
  String get editorReadinessOption => 'Создать готовым к действию';

  @override
  String get editorReadinessOptionOn => 'Создать готовым к действию: включено';

  @override
  String get editorReadinessOptionOff =>
      'Создать готовым к действию: выключено';

  @override
  String get editorReadinessConfirmationTitle => 'Создать готовым к действию?';

  @override
  String get editorReadinessOneDayCriterion =>
      'Его можно полностью выполнить в течение одного дня.';

  @override
  String get editorReadinessClarityCriterion =>
      'Человеку достаточно понятно, что именно нужно сделать.';

  @override
  String get editorReadinessCancelAction => 'Отмена';

  @override
  String get editorReadinessConfirmAction => 'Отметить готовым';

  @override
  String get editorChooseTags => 'Выбрать теги';

  @override
  String editorRemoveDraftTag(String tagName) {
    return 'Убрать тег «$tagName» из черновика';
  }

  @override
  String get editorDraftTagChecking => 'Проверяем тег';

  @override
  String get editorDraftTagReadUnavailable => 'Не удалось проверить тег';

  @override
  String get editorDraftTagReadCorruption => 'Данные тега повреждены';

  @override
  String get editorDraftTagReadUnexpected =>
      'Тег не проверен из-за непредвиденной ошибки';

  @override
  String editorRetryDraftTag(String tagName) {
    return 'Повторить проверку тега «$tagName»';
  }

  @override
  String editorCreateTagsMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Удалено из каталога выбранных тегов: $count. Они убраны из черновика. Сохраните намерение ещё раз.',
      one: 'Выбранный тег удалён из каталога и убран из черновика. Сохраните намерение ещё раз.',
    );
    return '$_temp0';
  }

  @override
  String get graphOperationCreate => 'Создание';

  @override
  String get graphOperationUpdate => 'Изменение';

  @override
  String get graphOperationEnableReadiness => 'Включение готовности';

  @override
  String get graphOperationDisableReadiness => 'Отключение готовности';

  @override
  String get graphOperationArchive => 'Архивирование';

  @override
  String get graphOperationRestore => 'Восстановление';

  @override
  String get graphOperationDelete => 'Удаление';

  @override
  String get graphOperationNewIntention => 'новое намерение';

  @override
  String get graphOperationIntention => 'намерение';

  @override
  String graphOperationMessage(
    String operation,
    String target,
    String outcome,
  ) {
    return '$operation — «$target»: $outcome';
  }

  @override
  String graphOperationMessageWithOthers(String message, int count) {
    return '$message · ещё $count';
  }

  @override
  String get graphOperationNewRelation => 'новая связь';

  @override
  String get graphOperationRelation => 'связь';

  @override
  String get graphOperationDailyChoice => 'дневной выбор';

  @override
  String get graphOperationTag => 'тег';

  @override
  String get graphOperationMoveTag => 'Перестановка';

  @override
  String get graphOperationAssignTag => 'Назначение';

  @override
  String get graphOperationRemoveTagAssignment => 'Снятие';

  @override
  String get graphOperationTagAssignment => 'назначение тега';

  @override
  String get dataExportSaved => 'Данные сохранены в файл';

  @override
  String get dataExportFailed => 'Не удалось сохранить файл';

  @override
  String get dataExportExistingFile =>
      'Такой файл уже есть. Сохраните копию под новым именем';

  @override
  String get dataBackupRestored => 'Копия восстановлена';

  @override
  String get dataBackupRestoreFailed =>
      'Не удалось восстановить копию. Ничего не изменено';

  @override
  String get dataReplacementStorageFull =>
      'Недостаточно места на устройстве. Освободите место и повторите. Ничего не изменено';

  @override
  String get dataImported => 'Данные импортированы';

  @override
  String get dataImportInvalidFile =>
      'Не удалось импортировать файл. Это не экспорт Doable, или он повреждён. Ничего не изменено';

  @override
  String get dataImportNewerVersion =>
      'Файл создан более новой версией Doable. Обновите приложение, чтобы импортировать его. Ничего не изменено';

  @override
  String get dataImportUnreadable =>
      'Не удалось прочитать файл. Проверьте доступ к нему и повторите. Ничего не изменено';

  @override
  String get dataImportFailed =>
      'Не удалось импортировать данные. Ничего не изменено';

  @override
  String get dataManualBackupFailed => 'Не удалось сделать копию';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get dataSectionTitle => 'Данные';

  @override
  String get dataSectionLocalOnly =>
      'Всё, что вы пишете, хранится только на этом устройстве.';

  @override
  String get dataExportTitle => 'Экспорт данных';

  @override
  String get dataExportHint => 'Сохранить копию всего в файл';

  @override
  String get dataExportNothing => 'Пока нечего экспортировать';

  @override
  String get dataExportRunning => 'Сохраняется в файл…';

  @override
  String dataExportProgress(double share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return '$shareString';
  }

  @override
  String dataExportComposition(
    int intentions,
    int relations,
    int dailyChoices,
    int tags,
  ) {
    final intl.NumberFormat intentionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String intentionsString = intentionsNumberFormat.format(intentions);
    final intl.NumberFormat relationsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String relationsString = relationsNumberFormat.format(relations);
    final intl.NumberFormat dailyChoicesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String dailyChoicesString = dailyChoicesNumberFormat.format(
      dailyChoices,
    );
    final intl.NumberFormat tagsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String tagsString = tagsNumberFormat.format(tags);

    String _temp0 = intl.Intl.pluralLogic(
      intentions,
      locale: localeName,
      other: '$intentionsString намерения',
      many: '$intentionsString намерений',
      few: '$intentionsString намерения',
      one: '$intentionsString намерение',
    );
    String _temp1 = intl.Intl.pluralLogic(
      relations,
      locale: localeName,
      other: '$relationsString связи',
      many: '$relationsString связей',
      few: '$relationsString связи',
      one: '$relationsString связь',
    );
    String _temp2 = intl.Intl.pluralLogic(
      dailyChoices,
      locale: localeName,
      other: '$dailyChoicesString дневного выбора',
      many: '$dailyChoicesString дневных выборов',
      few: '$dailyChoicesString дневных выбора',
      one: '$dailyChoicesString дневной выбор',
    );
    String _temp3 = intl.Intl.pluralLogic(
      tags,
      locale: localeName,
      other: '$tagsString тега',
      many: '$tagsString тегов',
      few: '$tagsString тега',
      one: '$tagsString тег',
    );
    return '$_temp0, $_temp1, $_temp2 и $_temp3 в одном файле';
  }

  @override
  String get dataExportUnprotected =>
      'Файл не защищён. Любой, у кого он есть, сможет прочитать написанное.';

  @override
  String get dataExportSave => 'Сохранить в файл';

  @override
  String get dataImportTitle => 'Импорт данных';

  @override
  String get dataImportHint => 'Заменить всё копией из файла';

  @override
  String get dataImportHintEmptyGraph => 'Вернуть копию из файла';

  @override
  String get dataImportChooseAnotherFile => 'Выбрать другой файл';

  @override
  String get dataBackupsTitle => 'Резервные копии';

  @override
  String get dataBackupsExplanation =>
      'Копия делается каждый день, если данные менялись, и хранится на этом устройстве. Остаются 7 последних ежедневных копий. Выберите копию, чтобы восстановить её.';

  @override
  String get dataBackupsMakeNow => 'Сделать копию сейчас';

  @override
  String get dataBackupsReadFailed => 'Не удалось загрузить копии';

  @override
  String get dataBackupsExpand => 'Раскрыть панель резервных копий';

  @override
  String get dataBackupsCollapse => 'Свернуть панель резервных копий';

  @override
  String get dataBackupsLastJustNow => 'Последняя копия только что';

  @override
  String dataBackupsLastToday(String time) {
    return 'Последняя копия сегодня в $time';
  }

  @override
  String dataBackupsLastYesterday(String time) {
    return 'Последняя копия вчера в $time';
  }

  @override
  String dataBackupsLastOn(String date, String time) {
    return 'Последняя копия $date в $time';
  }

  @override
  String get dataBackupsNone => 'Пока нет копий';

  @override
  String get dataBackupsNothing => 'Пока нечего копировать';

  @override
  String dataBackupMadeToday(String time) {
    return 'Сегодня, $time';
  }

  @override
  String dataBackupMadeYesterday(String time) {
    return 'Вчера, $time';
  }

  @override
  String dataBackupMadeOn(String date, String time) {
    return '$date, $time';
  }

  @override
  String dataBackupRestoreMadeToday(String time) {
    return 'Восстановить копию от сегодня, $time';
  }

  @override
  String dataBackupRestoreMadeYesterday(String time) {
    return 'Восстановить копию от вчера, $time';
  }

  @override
  String dataBackupRestoreMadeOn(String date, String time) {
    return 'Восстановить копию от $date, $time';
  }

  @override
  String dataBackupAdded(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString добавлено';
  }

  @override
  String dataBackupChanged(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString изменено';
  }

  @override
  String dataBackupDeleted(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString удалено';
  }

  @override
  String get dataBackupNoChanges => 'Нет изменений';

  @override
  String get dataBackupDataReplaced => 'Данные заменены';

  @override
  String get dataRestoreRunning => 'Восстановление копии…';

  @override
  String get dataImportRunning => 'Импорт данных…';

  @override
  String dataReplacementProgress(double share) {
    final intl.NumberFormat shareNumberFormat =
        intl.NumberFormat.percentPattern(localeName);
    final String shareString = shareNumberFormat.format(share);

    return '$shareString';
  }

  @override
  String get dataReplacementCancel => 'Отменить';

  @override
  String get dataReplacementCancelling => 'Отмена…';

  @override
  String get dataRestoreConfirmationTitle => 'Восстановить эту копию?';

  @override
  String dataRestoreMadeToday(String time) {
    return 'Она сделана сегодня в $time.';
  }

  @override
  String dataRestoreMadeYesterday(String time) {
    return 'Она сделана вчера в $time.';
  }

  @override
  String dataRestoreMadeOn(String date, String time) {
    return 'Она сделана $date в $time.';
  }

  @override
  String dataRestoreChangesSince(String changes) {
    return 'С тех пор: $changes. Восстановление отменит всё это.';
  }

  @override
  String get dataRestoreNoChangesSince => 'С тех пор ничего не изменилось.';

  @override
  String get dataRestoreReplacedSince =>
      'С тех пор данные заменялись. Восстановление отменит все изменения.';

  @override
  String get dataReplacementReplacesEverything =>
      'Она заменит всё, что сейчас есть в Doable. Сначала текущее состояние сохраняется как резервная копия.';

  @override
  String get dataReplacementConfirmationCancel => 'Отмена';

  @override
  String get dataRestoreConfirm => 'Восстановить копию';

  @override
  String get dataImportConfirmationTitle => 'Импортировать эту копию?';

  @override
  String dataImportConfirmationFacts(
    String date,
    int intentions,
    int relations,
    int dailyChoices,
    int tags,
  ) {
    final intl.NumberFormat intentionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String intentionsString = intentionsNumberFormat.format(intentions);
    final intl.NumberFormat relationsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String relationsString = relationsNumberFormat.format(relations);
    final intl.NumberFormat dailyChoicesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String dailyChoicesString = dailyChoicesNumberFormat.format(
      dailyChoices,
    );
    final intl.NumberFormat tagsNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String tagsString = tagsNumberFormat.format(tags);

    String _temp0 = intl.Intl.pluralLogic(
      intentions,
      locale: localeName,
      other: '$intentionsString намерения',
      many: '$intentionsString намерений',
      few: '$intentionsString намерения',
      one: '$intentionsString намерение',
    );
    String _temp1 = intl.Intl.pluralLogic(
      relations,
      locale: localeName,
      other: '$relationsString связи',
      many: '$relationsString связей',
      few: '$relationsString связи',
      one: '$relationsString связь',
    );
    String _temp2 = intl.Intl.pluralLogic(
      dailyChoices,
      locale: localeName,
      other: '$dailyChoicesString дневного выбора',
      many: '$dailyChoicesString дневных выборов',
      few: '$dailyChoicesString дневных выбора',
      one: '$dailyChoicesString дневной выбор',
    );
    String _temp3 = intl.Intl.pluralLogic(
      tags,
      locale: localeName,
      other: '$tagsString тега',
      many: '$tagsString тегов',
      few: '$tagsString тега',
      one: '$tagsString тег',
    );
    return 'Она сохранена $date года и содержит $_temp0, $_temp1, $_temp2 и $_temp3.';
  }

  @override
  String get dataImportConfirm => 'Импортировать и заменить';

  @override
  String intentionTagConditionAbsent(String tagName) {
    return 'не $tagName';
  }

  @override
  String intentionTagConditionPresentSemantics(String tagName) {
    return '$tagName, должен быть';
  }

  @override
  String intentionTagConditionAbsentSemantics(String tagName) {
    return '$tagName, должен отсутствовать';
  }

  @override
  String get intentionTagConditionToggleHint =>
      'Переключить надобность: должен быть или должен отсутствовать';

  @override
  String intentionTagConditionRemove(String tagName) {
    return 'Снять условие: $tagName';
  }

  @override
  String get intentionTagConditionsAdd => 'Тег';

  @override
  String get intentionTagConditionsAddSemantics => 'Добавить условие по тегу';

  @override
  String get tagsPanelTitle => 'Теги';

  @override
  String get tagsPanelAssignmentHint => 'Выберите сколько нужно';

  @override
  String get tagsPanelFilterTitle => 'Фильтр по тегам';

  @override
  String get tagsPanelFilterHint =>
      'Нажмите, чтобы потребовать тег, ещё раз — чтобы исключить';

  @override
  String get tagsPanelResetConditions => 'Сбросить';

  @override
  String get tagsPanelResetConditionsLabel => 'Сбросить условия по тегам';

  @override
  String tagsPanelFilterPresentLabel(String tagName) {
    return '$tagName, должен быть';
  }

  @override
  String tagsPanelFilterAbsentLabel(String tagName) {
    return '$tagName, должен отсутствовать';
  }

  @override
  String get tagsPanelSearchPlaceholder => 'Найти или создать тег';

  @override
  String get tagsPanelSearchLabel => 'Поиск тегов';

  @override
  String get tagsPanelClearSearch => 'Очистить поиск тегов';

  @override
  String get tagsPanelInvalidSearch =>
      'Недопустимые символы показаны как �. Ввод сохранён, но не применён; показаны результаты последнего корректного запроса.';

  @override
  String get tagsPanelDone => 'Готово';

  @override
  String get tagsPanelExpand => 'Раскрыть панель тегов';

  @override
  String get tagsPanelCollapse => 'Свернуть панель тегов';

  @override
  String get tagsPanelLoading => 'Загружаем теги…';

  @override
  String get tagsPanelLoadUnavailable => 'Не удалось загрузить теги.';

  @override
  String get tagsPanelLoadCorruption =>
      'Сохранённые данные тегов повреждены и не могут быть показаны.';

  @override
  String get tagsPanelLoadUnexpected =>
      'Не удалось загрузить теги из-за непредвиденной ошибки.';

  @override
  String get tagsPanelRefreshUnavailable =>
      'Не удалось обновить теги. Список может быть устаревшим.';

  @override
  String get tagsPanelRefreshCorruption =>
      'Не удалось обновить теги: сохранённые данные повреждены. Список может быть устаревшим.';

  @override
  String get tagsPanelRefreshUnexpected =>
      'Не удалось обновить теги из-за непредвиденной ошибки. Список может быть устаревшим.';

  @override
  String get tagsPanelIntentionMissing => 'Этого намерения больше нет.';

  @override
  String get tagsPanelEmptyTitle => 'Тегов пока нет';

  @override
  String get tagsPanelEmptyText =>
      'Введите название в поиске, чтобы создать первый';

  @override
  String tagsPanelCreateTag(String query) {
    return 'Создать тег «$query»';
  }

  @override
  String tagsPanelTagMenu(String tagName) {
    return 'Тег: $tagName';
  }

  @override
  String get tagsPanelTagHoldHint => 'Удерживайте, чтобы открыть действия тега';

  @override
  String get tagsPanelEditTag => 'Изменить тег';

  @override
  String get tagsPanelDuplicateTag => 'Дублировать тег';

  @override
  String get tagsPanelDeleteTag => 'Удалить тег';

  @override
  String get tagsPanelDeleteTitle => 'Удалить тег?';

  @override
  String get tagsPanelDeleteTextBefore => 'Будут необратимо удалены тег ';

  @override
  String get tagsPanelDeleteTextAfter =>
      ' и все его назначения активным и архивированным намерениям. Сами намерения, связи, дневные выборы и их пути сохранятся.';

  @override
  String get tagsPanelDeleteCancel => 'Отмена';

  @override
  String get tagsPanelDeleteConfirm => 'Удалить';

  @override
  String get tagSheetNamePlaceholder => 'Название';

  @override
  String get tagSheetEditTitle => 'Изменить тег';

  @override
  String get tagEditorCreateTitle => 'Новый тег';

  @override
  String get tagEditorNameLabel => 'Название тега';

  @override
  String get tagColorNone => 'Без цвета';

  @override
  String get tagColorBrown => 'Коричневый';

  @override
  String get tagColorOrange => 'Оранжевый';

  @override
  String get tagColorOlive => 'Оливковый';

  @override
  String get tagColorGreen => 'Зелёный';

  @override
  String get tagColorTeal => 'Бирюзовый';

  @override
  String get tagColorBlue => 'Синий';

  @override
  String get tagColorViolet => 'Сиреневый';

  @override
  String get tagColorPurple => 'Фиолетовый';

  @override
  String get tagColorPink => 'Розовый';

  @override
  String get tagColorLabel => 'Цвет';

  @override
  String get tagColorGroupLabel => 'Цвет тега';

  @override
  String get tagEditorCreateAction => 'Создать тег';

  @override
  String get tagEditorRenameAction => 'Сохранить';

  @override
  String get tagEditorSaving => 'Сохраняем тег…';

  @override
  String get tagEditorAlreadyRunning =>
      'Сохранение этого тега уже выполняется. Дождитесь результата.';

  @override
  String get tagAssignmentAlreadyRunning =>
      'Изменение назначения тега уже выполняется. Дождитесь результата.';

  @override
  String get tagAssignmentIntentionNotFound =>
      'Этого намерения больше нет. Обновите подробности.';

  @override
  String get tagAssignmentUnavailable =>
      'Не удалось изменить назначение тега. Повторите попытку.';

  @override
  String get tagAssignmentCorruption =>
      'Сохранённые данные назначения тега повреждены. Назначение не изменено.';

  @override
  String get tagAssignmentUnexpected =>
      'Назначение тега не изменено из-за непредвиденной ошибки.';

  @override
  String get tagAssignmentsTitle => 'Назначенные теги';

  @override
  String get tagAssignmentsIntention => 'намерение';

  @override
  String get tagAssignmentsActive => 'не в архиве';

  @override
  String get tagAssignmentsArchived => 'в архиве';

  @override
  String tagAssignmentsContext(String targetKind, String archiveState) {
    return 'Назначения тегов: $targetKind, $archiveState';
  }

  @override
  String get tagAssignmentsLoading => 'Загружаем назначения…';

  @override
  String get tagAssignmentsEmpty => 'Назначений тегов пока нет.';

  @override
  String get tagAssignmentsRefreshing => 'Обновляем назначения…';

  @override
  String get tagAssignmentsUnavailable =>
      'Не удалось загрузить назначения. Повторите попытку.';

  @override
  String get tagAssignmentsCorruption =>
      'Сохранённые данные назначений повреждены и не могут быть показаны.';

  @override
  String get tagAssignmentsUnexpected =>
      'Не удалось загрузить назначения из-за непредвиденной ошибки.';

  @override
  String get tagAssignmentsChoose => 'Выбрать тег';

  @override
  String tagAssignmentsChooseSemantic(String targetKind, String archiveState) {
    return 'Выбрать тег для получателя: $targetKind, $archiveState';
  }

  @override
  String get tagAssignmentsRemove => 'Снять назначение';

  @override
  String tagAssignmentsRemoveNamed(String tagName) {
    return 'Снять назначение: $tagName';
  }

  @override
  String get tagAssignmentsRemoving => 'Снимаем назначение…';

  @override
  String get tagNameInvalidUnicode =>
      'Название тега содержит недопустимые символы.';

  @override
  String get tagNameEmpty => 'Введите название тега.';

  @override
  String get tagNameTooLong =>
      'Название тега должно содержать не более 255 отображаемых символов.';

  @override
  String get tagNameNonCanonical => 'Удалите пробелы по краям названия тега.';

  @override
  String get tagNameOccupied => 'Тег с таким названием уже есть.';

  @override
  String get tagNotFound => 'Этого тега больше нет. Обновите каталог.';

  @override
  String get tagUnavailable =>
      'Не удалось выполнить действие с тегом. Повторите попытку.';

  @override
  String get tagCorruption =>
      'Сохранённые данные тега повреждены. Тег не изменён.';

  @override
  String get tagUnexpected =>
      'Действие с тегом не выполнено из-за непредвиденной ошибки.';

  @override
  String get dailyChoiceCreated => 'Дневной выбор создан.';

  @override
  String get dailyChoiceUpdated => 'Дневной выбор изменён.';

  @override
  String get dailyChoicePathReplaced => 'Путь дневного выбора заменён.';

  @override
  String get dailyChoiceDeleted => 'Дневной выбор удалён.';

  @override
  String get dailyChoiceDeleteAction => 'Удалить дневной выбор навсегда';

  @override
  String get dailyChoiceDeleteConfirmationTitle =>
      'Удалить дневной выбор навсегда?';

  @override
  String dailyChoiceDeleteConfirmationMessage(
    String phrase,
    String date,
    String choiceId,
  ) {
    return 'Выбор: $phrase\nДата: $date\nИдентификатор выбора: $choiceId\n\nЭто действие нельзя отменить. Намерения, долговременные связи и другие дневные выборы сохранятся.';
  }

  @override
  String get dailyChoiceDeleteConfirmAction => 'Удалить навсегда';

  @override
  String get dailyChoiceSourceInvalid =>
      'Проверьте исходное намерение дневного выбора.';

  @override
  String get dailyChoiceSelectedInvalid =>
      'Проверьте выбранное намерение дневного выбора.';

  @override
  String get dailyChoiceDateInvalid => 'Проверьте дату дневного выбора.';

  @override
  String get dailyChoiceDescriptionInvalid =>
      'Проверьте описание дневного выбора.';

  @override
  String get dailyChoiceOperationNotFound =>
      'Дневной выбор больше не существует.';

  @override
  String get dailyChoiceOperationConflict =>
      'Данные изменились. Обновите их и подтвердите снова.';

  @override
  String get dailyChoiceOperationUnavailable =>
      'Не удалось выполнить действие с дневным выбором. Повторите попытку.';

  @override
  String get dailyChoiceOperationCorruption =>
      'Сохранённые данные повреждены. Дневной выбор не изменён.';

  @override
  String get dailyChoiceOperationUnexpected =>
      'Действие с дневным выбором не выполнено из-за непредвиденной ошибки.';

  @override
  String get relationEditorCreated => 'Связь создана.';

  @override
  String get relationEditorCreateInvalidInput =>
      'Проверьте выбранные намерения и данные связи.';

  @override
  String get relationEditorCreatePairOccupied =>
      'Связь этого направления между выбранными намерениями уже есть.';

  @override
  String get relationEditorCreateParticipantNotFound =>
      'Одно из выбранных намерений больше не существует.';

  @override
  String get relationEditorCreateParticipantArchived =>
      'Связать можно только активные намерения.';

  @override
  String get relationEditorCreateUnavailable =>
      'Не удалось создать связь. Повторите попытку.';

  @override
  String get relationEditorCreateCorruption =>
      'Сохранённые данные повреждены. Связь не создана.';

  @override
  String get relationEditorCreateUnexpected =>
      'Не удалось создать связь из-за непредвиденной ошибки.';

  @override
  String get relationEditorUpdated => 'Связь изменена.';

  @override
  String get relationEditorUpdateInvalidInput =>
      'Проверьте выбранные намерения и изменения связи.';

  @override
  String get relationEditorUpdatePairOccupied =>
      'Связь этого направления между выбранными намерениями уже есть.';

  @override
  String get relationEditorUpdateNotFound => 'Эта связь больше не существует.';

  @override
  String get relationEditorUpdateParticipantNotFound =>
      'Одно из выбранных намерений больше не существует.';

  @override
  String get relationEditorUpdateParticipantArchived =>
      'Активная связь может соединять только активные намерения.';

  @override
  String get relationEditorUpdateReferencedByDailyPath =>
      'Связь используется в сохранённом дневном пути. Её тип и участников нельзя изменить.';

  @override
  String get relationEditorPathProtection =>
      'Связь используется в сохранённом дневном пути. Её тип и участников нельзя изменить. Описание и приоритет остаются доступными.';

  @override
  String get relationEditorPathProtectionWithDraft =>
      'Связь используется в сохранённом дневном пути. Верните прежние тип и участников, чтобы сохранить изменения описания и приоритета.';

  @override
  String get relationEditorUpdateUnavailable =>
      'Не удалось изменить связь. Повторите попытку.';

  @override
  String get relationEditorUpdateCorruption =>
      'Сохранённые данные повреждены. Связь не изменена.';

  @override
  String get relationEditorUpdateUnexpected =>
      'Не удалось изменить связь из-за непредвиденной ошибки.';

  @override
  String get relationArchived => 'Связь архивирована.';

  @override
  String get relationArchiveNotFound => 'Эта связь больше не существует.';

  @override
  String get relationArchiveConflict =>
      'Связь не удалось архивировать из-за конфликта актуального состояния.';

  @override
  String get relationArchiveUnavailable =>
      'Не удалось архивировать связь. Повторите попытку.';

  @override
  String get relationArchiveCorruption =>
      'Сохранённые данные повреждены. Связь не архивирована.';

  @override
  String get relationArchiveUnexpected =>
      'Не удалось архивировать связь из-за непредвиденной ошибки.';

  @override
  String get relationRestored => 'Связь восстановлена.';

  @override
  String get relationRestoreNotFound => 'Эта связь больше не существует.';

  @override
  String get relationRestoreConflict =>
      'Связь не удалось восстановить из-за конфликта актуального состояния.';

  @override
  String get relationRestoreSourceNotFound =>
      'Исходное намерение больше не существует. Связь не восстановлена.';

  @override
  String get relationRestoreRelatedNotFound =>
      'Связанное намерение больше не существует. Связь не восстановлена.';

  @override
  String get relationRestoreSourceArchived =>
      'Сначала восстановите исходное намерение, затем восстановите эту связь.';

  @override
  String get relationRestoreRelatedArchived =>
      'Сначала восстановите связанное намерение, затем восстановите эту связь.';

  @override
  String get relationRestoreUnavailable =>
      'Не удалось восстановить связь. Повторите попытку.';

  @override
  String get relationRestoreCorruption =>
      'Сохранённые данные повреждены. Связь не восстановлена.';

  @override
  String get relationRestoreUnexpected =>
      'Не удалось восстановить связь из-за непредвиденной ошибки.';

  @override
  String get relationDeleted => 'Связь удалена.';

  @override
  String get relationDeleteNotFound => 'Эта связь больше не существует.';

  @override
  String get relationDeleteConflict =>
      'Связь не удалось удалить из-за конфликта актуального состояния.';

  @override
  String get relationDeleteReferencedByDailyPath =>
      'Связь используется в сохранённом дневном пути. Сначала удалите или замените использующие её дневные выборы.';

  @override
  String get relationDeleteUnavailable =>
      'Не удалось удалить связь. Повторите попытку.';

  @override
  String get relationDeleteCorruption =>
      'Сохранённые данные повреждены. Связь не удалена.';

  @override
  String get relationDeleteUnexpected =>
      'Не удалось удалить связь из-за непредвиденной ошибки.';

  @override
  String get relationNeighborhoodOpenRelation =>
      'Открывает подробные данные связи';

  @override
  String get relationNeighborhoodOpenDailyChoice =>
      'Открыть полный путь дневного выбора';

  @override
  String get relationDetailsTitle => 'Связь';

  @override
  String get relationDetailsLoading => 'Загружаем связь…';

  @override
  String get relationDetailsNotFound => 'Эта связь больше не существует.';

  @override
  String get relationDetailsUnavailable =>
      'Не удалось загрузить связь. Повторите попытку.';

  @override
  String get relationDetailsCorruption =>
      'Сохранённые данные связи повреждены и не могут быть показаны.';

  @override
  String get relationDetailsUnexpected =>
      'Не удалось загрузить связь из-за непредвиденной ошибки.';

  @override
  String get relationDetailsRefreshing => 'Обновляем подробные данные связи…';

  @override
  String get relationDetailsRefreshUnavailable =>
      'Не удалось обновить подробные данные связи. Ранее подтверждённые данные по-прежнему показаны.';

  @override
  String get relationDetailsRefreshCorruption =>
      'Сохранённые данные повреждены. Ранее подтверждённые подробные данные связи по-прежнему показаны.';

  @override
  String get relationDetailsRefreshUnexpected =>
      'Не удалось обновить подробные данные связи из-за непредвиденной ошибки. Ранее подтверждённые данные по-прежнему показаны.';

  @override
  String get relationDetailsTypeLabel => 'Тип связи';

  @override
  String get relationDetailsPriorityLabel => 'Приоритет';

  @override
  String get relationDetailsScopeLabel => 'Состояние связи';

  @override
  String get relationDetailsDescriptionLabel => 'Описание';

  @override
  String get relationDetailsNoDescription => 'Описания нет';

  @override
  String get relationDetailsOpenParticipant =>
      'Открывает намерение и его собственные связи';

  @override
  String get relationDetailsEditAction => 'Редактировать связь';

  @override
  String get relationDetailsArchiveAction => 'Архивировать связь';

  @override
  String get relationDetailsRestoreAction => 'Восстановить связь';

  @override
  String get relationDetailsDeleteAction => 'Удалить связь навсегда';

  @override
  String get relationDetailsPathProtection =>
      'Связь используется в сохранённом дневном пути. Удалить её или изменить тип и участников нельзя. Описание, приоритет и архивное состояние остаются доступными.';

  @override
  String get relationDetailsDeletionChecking =>
      'Удаление недоступно, пока не подтверждены зависимости связи.';

  @override
  String get relationDetailsDeleteConfirmationTitle =>
      'Удалить связь навсегда?';

  @override
  String relationDetailsDeleteConfirmationMessage(
    String phrase,
    String sourceTitle,
    String relatedTitle,
    String scope,
  ) {
    return 'Связь: $phrase\nИсходное намерение: $sourceTitle\nСвязанное намерение: $relatedTitle\nСостояние связи: $scope\n\nЭто действие нельзя отменить. Связь и её описание будут удалены навсегда. Сами теги, все их назначения намерениям, оба намерения и все остальные связи сохранятся.';
  }

  @override
  String get relationDetailsConfirmDeleteAction => 'Удалить навсегда';

  @override
  String get relationDetailsOpenSourceParticipantAction =>
      'Открыть исходное намерение';

  @override
  String get relationDetailsOpenRelatedParticipantAction =>
      'Открыть связанное намерение';

  @override
  String get actionPickerCancel => 'Отменить выбор действия';

  @override
  String get actionPickerLoading => 'Загружаем действия…';

  @override
  String get actionPickerEmpty => 'Доступных активных действий нет.';

  @override
  String get actionPickerUnavailable =>
      'Не удалось загрузить действия. Повторите попытку.';

  @override
  String get actionPickerCorruption =>
      'Сохранённые данные действий повреждены и не могут быть показаны.';

  @override
  String get actionPickerUnexpected =>
      'Не удалось загрузить действия из-за непредвиденной ошибки.';

  @override
  String get sourcePickerCancel => 'Отменить выбор намерения';

  @override
  String get sourcePickerEmpty => 'Доступных активных намерений нет.';

  @override
  String get dailyChoicePickerPurposeCreationSource =>
      'Новый дневной выбор: исходное намерение';

  @override
  String get dailyChoicePickerPurposeCreationAction =>
      'Новый дневной выбор: конечное действие';

  @override
  String get dailyChoicePickerPurposeReplacementSource =>
      'Замена пути: исходное намерение';

  @override
  String get dailyChoicePickerPurposeReplacementAction =>
      'Замена пути: конечное действие';

  @override
  String get dailyChoicePickerFlowCreationFromSource =>
      'Новый дневной выбор, от намерения';

  @override
  String get dailyChoicePickerFlowCreationFromAction =>
      'Новый дневной выбор, от действия';

  @override
  String get dailyChoicePickerFlowReplacementFromSource =>
      'Замена пути, от намерения';

  @override
  String get dailyChoicePickerFlowReplacementFromAction =>
      'Замена пути, от действия';

  @override
  String get dailyChoicePickerStepCurrent => 'Вы здесь';

  @override
  String get dailyChoicePickerStepSource => 'Исходное намерение';

  @override
  String get dailyChoicePickerStepAction => 'Конечное действие';

  @override
  String get dailyChoicePickerStepPathDown => 'Путь вниз к действию';

  @override
  String get dailyChoicePickerStepPathDownNote =>
      'Каждый следующий шаг — то, что нужно или можно для предыдущего';

  @override
  String get dailyChoicePickerStepPathUp => 'Путь вверх к исходному намерению';

  @override
  String get dailyChoicePickerStepPathUpNote => 'Нужен хотя бы один шаг';

  @override
  String get dailyChoicePickerStepDetails =>
      'Дата, время, приоритет и описание';

  @override
  String get dailyChoicePickerStepReplacement => 'Подтверждение замены';

  @override
  String get dailyChoicePickerStepReplacementNote =>
      'Дата, запланированное время, приоритет, описание и выполнение останутся прежними';

  @override
  String get intentionPickerArchived => 'в архиве';

  @override
  String get intentionPickerKindAction => 'действие';

  @override
  String get intentionPickerKindIntention => 'намерение';

  @override
  String intentionPickerOpenActionPage(String title) {
    return 'Открыть страницу действия «$title»';
  }

  @override
  String intentionPickerOpenIntentionPage(String title) {
    return 'Открыть страницу намерения «$title»';
  }

  @override
  String get intentionPickerShowAndSortTitle => 'Показать и упорядочить';

  @override
  String get intentionPickerShowAndSortHint => 'Список меняется по мере выбора';

  @override
  String get intentionPickerShowAndSortReset => 'Сбросить';

  @override
  String intentionPickerPurposeLabel(String title, String subtitle) {
    return '$title. $subtitle. Показать, что выбирается';
  }

  @override
  String get intentionPickerPurposeSheetTitle => 'Что вы выбираете';

  @override
  String get intentionPickerPurposeSheetBack => 'Вернуться к списку';

  @override
  String get intentionPickerTypeCaption => 'Тип';

  @override
  String get intentionPickerTypeAll => 'Всё';

  @override
  String get intentionPickerTypeIntentionsOnly => 'Только намерения';

  @override
  String get intentionPickerTypeActionsOnly => 'Только действия';

  @override
  String get intentionPickerActionTypeNote =>
      'Конечным в дневном выборе может быть только действие';

  @override
  String get intentionPickerSortCaption => 'Сортировка';

  @override
  String get intentionPickerSortCreated => 'Дата создания';

  @override
  String get intentionPickerSortChanged => 'Дата изменения';

  @override
  String get intentionPickerSortName => 'Название';

  @override
  String get intentionPickerOrderNewest => 'Сначала новые';

  @override
  String get intentionPickerOrderOldest => 'Сначала старые';

  @override
  String get intentionPickerOrderAToZ => 'От А до Я';

  @override
  String get intentionPickerOrderZToA => 'От Я до А';

  @override
  String intentionPickerOrderButtonSemantics(
    String currentOrder,
    String nextOrder,
  ) {
    return 'Текущий порядок: $currentOrder. Переключить на: $nextOrder';
  }

  @override
  String get intentionPickerAllHeader => 'Все';

  @override
  String get intentionPickerOrderCreatedNewest => 'Создание, сначала новые';

  @override
  String get intentionPickerOrderCreatedOldest => 'Создание, сначала старые';

  @override
  String get intentionPickerOrderUpdatedNewest => 'Изменение, сначала новые';

  @override
  String get intentionPickerOrderUpdatedOldest => 'Изменение, сначала старые';

  @override
  String get intentionPickerOrderTitleAscending => 'Название, от А до Я';

  @override
  String get intentionPickerOrderTitleDescending => 'Название, от Я до А';

  @override
  String intentionPickerHeaderLabel(String type, String summary) {
    return 'Показать и упорядочить. Тип: $type. Сортировка: $summary.';
  }

  @override
  String intentionPickerHeaderCountLabel(
    String type,
    int count,
    String summary,
  ) {
    return 'Показать и упорядочить. Тип: $type, $count. Сортировка: $summary.';
  }

  @override
  String get intentionPickerActionsHeader => 'Действия';

  @override
  String get intentionPickerIntentionsHeader => 'Намерения';

  @override
  String get intentionPickerLoadingMoreActions => 'Загружаем ещё действия';

  @override
  String get intentionPickerLoadingMoreIntentions => 'Загружаем ещё намерения';

  @override
  String get intentionPickerEmptyScopeTitle => 'Выбрать не из чего';

  @override
  String get intentionPickerEmptyTypeTitle => 'Намерений этого типа нет';

  @override
  String get intentionPickerEmptyTypeText =>
      'Покажите оба типа, чтобы выбрать из доступных намерений.';

  @override
  String get intentionPickerShowBothTypes => 'Показать оба типа';

  @override
  String get intentionPickerActionTitle => 'Выбор действия';

  @override
  String get intentionPickerIntentionTitle => 'Выбор намерения';

  @override
  String get intentionPickerSearchPlaceholder => 'Поиск по названию';

  @override
  String get intentionPickerClearSearch => 'Очистить название';

  @override
  String intentionPickerFilterLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Фильтр по тегам, $count условия',
      many: 'Фильтр по тегам, $count условий',
      few: 'Фильтр по тегам, $count условия',
      one: 'Фильтр по тегам, $count условие',
      zero: 'Фильтр по тегам',
    );
    return '$_temp0';
  }

  @override
  String get intentionPickerNoActionsByTitle =>
      'Нет действий с таким названием';

  @override
  String get intentionPickerNoIntentionsByTitle =>
      'Нет намерений с таким названием';

  @override
  String get intentionPickerTryShorterTitle => 'Попробуйте название короче.';

  @override
  String get intentionPickerNoActionsByTags => 'Нет действий под эти теги';

  @override
  String get intentionPickerNoIntentionsByTags => 'Нет намерений под эти теги';

  @override
  String get intentionPickerChangeTags =>
      'Измените теги в фильтре или сбросьте его.';

  @override
  String get intentionPickerNoActionsFound => 'Действия не найдены';

  @override
  String get intentionPickerNoIntentionsFound => 'Намерения не найдены';

  @override
  String get intentionPickerChangeTitleOrTags =>
      'Измените название или условия по тегам.';

  @override
  String get intentionPickerResetFilters => 'Сбросить фильтры';

  @override
  String get participantPickerCancel => 'Отменить выбор намерения';

  @override
  String get participantPickerEmpty => 'Других намерений для выбора нет.';

  @override
  String get participantPickerOpenDetails =>
      'Открыть подробные данные намерения';

  @override
  String get participantPickerPurposeCreationSource =>
      'Новая связь: исходное намерение';

  @override
  String get participantPickerPurposeCreationRelated =>
      'Новая связь: связанное намерение';

  @override
  String get participantPickerPurposeChangeSource =>
      'Изменение связи: исходное намерение';

  @override
  String get participantPickerPurposeChangeRelated =>
      'Изменение связи: связанное намерение';

  @override
  String get participantPickerFlowCreation => 'Новая связь';

  @override
  String get participantPickerFlowChange => 'Изменение связи';

  @override
  String get participantPickerRoleSourceNote =>
      'Исходное намерение — то, для чего нужно или можно связанное.';

  @override
  String get participantPickerRoleRelatedNeedNote =>
      'Связанное намерение — то, что нужно для исходного.';

  @override
  String get participantPickerRoleRelatedCanNote =>
      'Связанное намерение — то, что можно для исходного.';

  @override
  String get participantPickerRoleRelatedUndeterminedNote =>
      'Связанное намерение — то, что нужно или можно для исходного.';

  @override
  String get participantPickerFieldChoosing => 'Сейчас выбирается';

  @override
  String get participantPickerFieldFromList => 'Из этого списка';

  @override
  String participantPickerFieldReplacing(String title) {
    return 'Вместо: $title';
  }

  @override
  String get participantPickerFieldNotChosen => 'Ещё не выбрано';

  @override
  String get participantPickerFieldArchived => 'В архиве';

  @override
  String get participantPickerKindUndetermined =>
      'Нужно или можно: ещё не выбрано';

  @override
  String get relationEditorTitle => 'Новая связь';

  @override
  String get relationEditorEditTitle => 'Редактирование связи';

  @override
  String get relationEditorPhraseLabel => 'Формулировка связи';

  @override
  String get relationEditorSourceLabel => 'Исходное намерение';

  @override
  String get relationEditorRelatedLabel => 'Связанное намерение';

  @override
  String get relationEditorParticipantSelected => 'Выбрано';

  @override
  String get relationEditorParticipantNotSelected => 'Не выбрано';

  @override
  String get relationEditorSelectSourceAction => 'Выбрать исходное намерение';

  @override
  String get relationEditorChangeSourceAction => 'Изменить исходное намерение';

  @override
  String get relationEditorSelectRelatedAction => 'Выбрать связанное намерение';

  @override
  String get relationEditorChangeRelatedAction =>
      'Изменить связанное намерение';

  @override
  String get relationEditorTypeLabel => 'Тип связи';

  @override
  String get relationEditorTypeNeed => 'Нужно';

  @override
  String get relationEditorTypeCan => 'Можно';

  @override
  String get relationEditorPriorityLabel => 'Приоритет';

  @override
  String get relationEditorDescriptionLabel => 'Описание (необязательно)';

  @override
  String get relationEditorDescriptionTooLong =>
      'Используйте не более 4096 символов.';

  @override
  String get relationEditorDescriptionInvalidUnicode =>
      'Введите корректный Unicode-текст без NUL.';

  @override
  String get relationEditorCreateSameParticipants =>
      'Намерение нельзя связать с самим собой.';

  @override
  String get relationEditorMissingTitle => 'Чтобы создать связь, укажите:';

  @override
  String get relationEditorMissingSource => 'исходное намерение';

  @override
  String get relationEditorMissingRelated => 'связанное намерение';

  @override
  String get relationEditorMissingType => 'тип связи';

  @override
  String get relationEditorMissingPriority => 'приоритет от P1 до P4';

  @override
  String get relationEditorOpenExistingRelation => 'Открыть существующую связь';

  @override
  String get relationEditorSubmitAction => 'Создать связь';

  @override
  String get relationEditorCreating => 'Создаём…';

  @override
  String get relationEditorSaveAction => 'Сохранить изменения';

  @override
  String get relationEditorSaving => 'Сохраняем…';

  @override
  String get relationNeighborhoodCreateOutgoingAction =>
      'Создать исходящую связь';

  @override
  String get relationNeighborhoodCreateIncomingAction =>
      'Создать входящую связь';

  @override
  String relationEditorPriorityOption(String priority) {
    return 'Приоритет $priority';
  }

  @override
  String get detailsChoosePathAction => 'Выбрать действие по пути';

  @override
  String get choicePathTitle => 'Выбор пути к действию';

  @override
  String get choicePathBottomTitle => 'Выбор основания для действия';

  @override
  String get choicePathBottomTraversal => 'Обход: от действия к основанию';

  @override
  String get choicePathBottomPathDirection =>
      'Направление связей: от основания к действию';

  @override
  String choicePathFixedAction(String action) {
    return 'Выбранное действие: $action';
  }

  @override
  String get choicePathActionPending => 'Загружаем выбранное действие…';

  @override
  String choicePathCurrentSource(String source) {
    return 'Основание: $source';
  }

  @override
  String get choicePathSourceSelected => 'Основание подтверждено';

  @override
  String choicePathSelectSource(String source) {
    return 'Подтвердить основание «$source»';
  }

  @override
  String get choicePathBottomNoPath =>
      'Для этого действия сейчас нет допустимых входящих связей. Выберите другое действие.';

  @override
  String get choicePathDirection => 'Путь от исходного намерения к действию';

  @override
  String choicePathSource(String source) {
    return 'Исходное намерение: $source';
  }

  @override
  String get choicePathSourcePending => 'Загружаем исходное намерение…';

  @override
  String choicePathReturnTo(String source) {
    return 'Вернуться к «$source»';
  }

  @override
  String choicePathStepSemantics(int index, String phrase, String priority) {
    return 'Шаг $index: $phrase. Приоритет $priority';
  }

  @override
  String get choicePathActionSelected => 'Действие выбрано';

  @override
  String choicePathSelectAction(String action) {
    return 'Выбрать действие «$action»';
  }

  @override
  String get choicePathSelectionNotSaved => 'Связь «я сегодня» ещё не создана.';

  @override
  String get choicePathContinuations => 'Доступные продолжения';

  @override
  String get choicePathLoading => 'Проверяем доступные продолжения…';

  @override
  String get choicePathNoPath =>
      'Из этого намерения сейчас нет допустимого пути к другому действию.';

  @override
  String get choicePathNoFurtherPath =>
      'Дальнейших допустимых продолжений нет.';

  @override
  String get choicePathConflict =>
      'Граф изменился. Актуализируйте путь перед дальнейшим выбором.';

  @override
  String get choicePathRefresh => 'Актуализировать путь';

  @override
  String get choicePathNotFound => 'Намерение пути больше не существует.';

  @override
  String get choicePathUnavailable =>
      'Продолжения временно недоступны. Повторите попытку.';

  @override
  String get choicePathCorruption =>
      'Сохранённые данные пути повреждены. Продолжение недоступно.';

  @override
  String get choicePathUnexpected =>
      'Не удалось проверить продолжения из-за непредвиденной ошибки.';

  @override
  String get choicePathLoadMore => 'Показать ещё продолжения';

  @override
  String get choicePathLoadingMore => 'Загружаем следующую порцию…';

  @override
  String choicePathContinueSemantics(String phrase, String priority) {
    return 'Продолжить по связи: $phrase. Приоритет $priority';
  }

  @override
  String get dailyChoiceCreationTitle => 'Подтвердить дневной выбор';

  @override
  String get dailyChoiceScheduleLabel => 'Запланированное время';

  @override
  String get dailyChoiceAllDay => 'Весь день';

  @override
  String get dailyChoiceSetTime => 'Указать время';

  @override
  String dailyChoiceTimeLabel(String time) {
    return 'Время: $time';
  }

  @override
  String get dailyChoicePriorityLabel => 'Приоритет';

  @override
  String dailyChoicePriorityOption(String priority) {
    return 'Приоритет $priority';
  }

  @override
  String get dailyChoiceCatalogTitle => 'Дневные выборы';

  @override
  String get dailyChoiceCreateFromAction => 'Создать выбор от действия';

  @override
  String get dailyChoiceCatalogLoading => 'Загружаем дневные выборы…';

  @override
  String get dailyChoiceCalendarToday => 'Сегодня';

  @override
  String get dailyChoiceCalendarDayAllCompleted =>
      'Все дневные выборы выполнены';

  @override
  String get dailyChoiceCalendarDayHasIncomplete =>
      'Есть невыполненный дневной выбор';

  @override
  String get dailyChoiceCalendarDayMarksUnavailable =>
      'Отметки дней не загружены.';

  @override
  String get dailyChoiceCalendarExpand => 'Развернуть календарь';

  @override
  String get dailyChoiceCalendarCollapse => 'Свернуть календарь';

  @override
  String get dailyChoiceCalendarPreviousMonth => 'Предыдущий месяц';

  @override
  String get dailyChoiceCalendarNextMonth => 'Следующий месяц';

  @override
  String get dailyChoiceCalendarChooseYearAndMonth => 'Выбрать год и месяц';

  @override
  String get dailyChoiceCalendarBackToMonthDays => 'Вернуться к дням месяца';

  @override
  String get dailyChoiceCalendarPreviousYears => 'Предыдущие годы';

  @override
  String get dailyChoiceCalendarNextYears => 'Следующие годы';

  @override
  String get dailyChoiceCalendarPreviousYear => 'Предыдущий год';

  @override
  String get dailyChoiceCalendarNextYear => 'Следующий год';

  @override
  String get dailyChoiceCatalogIncomplete => 'Не выполненные';

  @override
  String get dailyChoiceCatalogCompleted => 'Выполненные';

  @override
  String dailyChoiceCatalogTotalCount(int count) {
    return 'Всего дневных выборов: $count';
  }

  @override
  String get dailyChoiceCatalogEmpty => 'На этот день нет дневных выборов.';

  @override
  String get dailyChoiceCatalogRefreshing => 'Обновляем дневные выборы…';

  @override
  String get dailyChoiceCatalogLoadingMore => 'Загружаем ещё дневные выборы…';

  @override
  String get dailyChoiceCatalogLoadMore => 'Показать ещё дневные выборы';

  @override
  String get dailyChoiceCatalogUnavailable =>
      'Не удалось загрузить дневные выборы. Повторите попытку.';

  @override
  String get dailyChoiceCatalogCorruption =>
      'Сохранённые данные дневных выборов повреждены и не могут быть показаны.';

  @override
  String get dailyChoiceCatalogExpired =>
      'Каталог изменился. Обновите его, чтобы продолжить.';

  @override
  String get dailyChoiceCatalogUnexpected =>
      'Не удалось загрузить дневные выборы из-за непредвиденной ошибки.';

  @override
  String dailyChoiceCatalogPathIntentionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count намерения в пути',
      many: '$count намерений в пути',
      few: '$count намерения в пути',
      one: '$count намерение в пути',
    );
    return '$_temp0';
  }

  @override
  String dailyChoiceCatalogCompletionLabel(
    int number,
    String phrase,
    String date,
  ) {
    return 'Выполнение выбора № $number. $phrase. $date';
  }

  @override
  String get dailyChoiceCompletionSaving => 'Сохраняем выполнение…';

  @override
  String get dailyChoiceCompletionSynchronizing =>
      'Выполнение сохранено. Обновляем каталог…';

  @override
  String get dailyChoiceCompletionRefresh => 'Обновить выбор';

  @override
  String dailyChoiceCatalogRowLabel(
    int number,
    String phrase,
    String date,
    String completion,
  ) {
    return 'Выбор № $number. $phrase. $date. $completion';
  }

  @override
  String get dailyChoiceDetailsTitle => 'Дневной выбор';

  @override
  String get dailyChoiceEditTitle => 'Редактировать дневной выбор';

  @override
  String get dailyChoiceEditSave => 'Сохранить изменения';

  @override
  String get dailyChoiceEditRefresh =>
      'Вернуться к подробностям и обновить данные';

  @override
  String get dailyChoiceDetailsLoading => 'Загружаем дневной выбор…';

  @override
  String get dailyChoiceDetailsNotFound =>
      'Дневной выбор больше не существует.';

  @override
  String get dailyChoiceDetailsUnavailable =>
      'Не удалось загрузить дневной выбор. Повторите попытку.';

  @override
  String get dailyChoiceDetailsCorruption =>
      'Сохранённый путь повреждён и не может быть показан.';

  @override
  String get dailyChoiceDetailsUnexpected =>
      'Не удалось загрузить дневной выбор из-за непредвиденной ошибки.';

  @override
  String dailyChoiceDetailsPhrase(String source, String selected) {
    return 'Чтобы $source, я сегодня $selected';
  }

  @override
  String dailyChoiceDetailsDate(String date) {
    return 'Дата дневного выбора: $date';
  }

  @override
  String get dailyChoiceDetailsCompleted => 'Выполнено';

  @override
  String get dailyChoiceDetailsNotCompleted => 'Не выполнено';

  @override
  String get dailyChoiceDetailsDescription => 'Описание';

  @override
  String get dailyChoiceDetailsPath => 'Сохранённый путь';

  @override
  String get dailyChoiceDetailsSource => 'Основание';

  @override
  String get dailyChoiceDetailsIntermediate => 'Промежуточное намерение';

  @override
  String get dailyChoiceDetailsSelectedAction => 'Выбранное действие';

  @override
  String get dailyChoiceDetailsArchived => 'Архивировано';

  @override
  String get dailyChoiceDetailsActive => 'Активно';

  @override
  String get dailyChoiceDetailsReady => 'Готово к действию';

  @override
  String get dailyChoiceDetailsNotReady => 'Не готово к действию';

  @override
  String dailyChoiceDetailsStep(int number) {
    return 'Переход $number';
  }

  @override
  String get dailyChoiceCreationPath => 'Подтверждаемый путь';

  @override
  String dailyChoiceCreationAction(String action) {
    return 'Выбранное действие: $action';
  }

  @override
  String get dailyChoiceCreationDate => 'Дата дневного выбора';

  @override
  String get dailyChoiceCreationDateHint =>
      'Введите дату в формате ГГГГ-ММ-ДД (0001–9999)';

  @override
  String get dailyChoiceCreationDescription => 'Описание (необязательно)';

  @override
  String get dailyChoiceCreationCompleted => 'Уже выполнено';

  @override
  String get dailyChoiceCreationCompletedHint =>
      'Отметьте, если действие уже выполнено для этой даты';

  @override
  String get dailyChoiceCreationSave => 'Сохранить дневной выбор';

  @override
  String get dailyChoiceCreationSaving => 'Сохраняем…';

  @override
  String get dailyChoiceCreationCancel => 'Отмена';

  @override
  String get dailyChoiceCreationRefreshPath =>
      'Вернуться к пути и актуализировать его';

  @override
  String get dailyChoiceReplaceTitle => 'Подтвердить замену пути';

  @override
  String get dailyChoiceReplacePreparing =>
      'Готовим подтверждение нового пути…';

  @override
  String get dailyChoiceReplaceCurrent => 'Заменяемый дневной выбор';

  @override
  String get dailyChoiceReplaceNewPath => 'Новый путь от основания к действию';

  @override
  String get dailyChoiceReplaceNoDescription => 'Без описания';

  @override
  String get dailyChoiceReplaceFieldsPreserved =>
      'Дата, описание и выполнение сохранятся без изменений при замене пути.';

  @override
  String get dailyChoiceReplaceCompletionPreserved =>
      'Выполнение останется включённым, даже если выбрано другое действие.';

  @override
  String get dailyChoiceReplaceConfirm => 'Заменить только путь';

  @override
  String get dailyChoiceReplaceSubmitting => 'Заменяем путь…';

  @override
  String get dailyChoiceReplaceChooseAgain => 'Вернуться к выбору пути';

  @override
  String get dailyChoiceReplaceOpen => 'Заменить путь';

  @override
  String get dailyChoiceReplaceChooseDirection =>
      'Выбрать направление нового пути';

  @override
  String get dailyChoiceReplaceChooseDirectionDescription =>
      'Выберите новое основание или действие для замены сохранённого пути.';

  @override
  String get dailyChoiceReplaceFromSource => 'Начать с нового основания';

  @override
  String get dailyChoiceReplaceFromAction => 'Начать с нового действия';

  @override
  String get dailyChoiceReplaceSelectPath => 'Выбрать путь для замены';

  @override
  String get dailyChoiceReplaceOpenConfirmation => 'Подтвердить замену пути';

  @override
  String get choicePathOpenConfirmation => 'Перейти к подтверждению выбора';

  @override
  String get creationCancelAction => 'Отменить создание';

  @override
  String get creationLeaveAction => 'Выйти из создания';

  @override
  String get creationSavingContinues =>
      'Сохранение продолжится после выхода из создания.';
}
