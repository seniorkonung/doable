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
  String get catalogFilterInvalidUnicode =>
      'Введите корректный Unicode-текст без NUL.';

  @override
  String get catalogFilterTooLong => 'Используйте не более 255 символов.';

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
  String get catalogLoadMoreUnavailable =>
      'Не удалось загрузить следующие намерения.';

  @override
  String get catalogLoadMoreCorruption =>
      'Сохранённые данные повреждены; следующие намерения нельзя показать.';

  @override
  String get catalogLoadMoreUnexpected =>
      'Не удалось загрузить следующие намерения из-за непредвиденной ошибки.';

  @override
  String intentionSummaryTags(String tags) {
    return 'Теги: $tags';
  }

  @override
  String get intentionSummaryNoTags => 'Без тегов';

  @override
  String get relationNeighborhoodSummaryLoading => 'Загружаем связи и сводку…';

  @override
  String relationNeighborhoodDailyTotal(int count) {
    return 'Дневных выборов: $count';
  }

  @override
  String get relationNeighborhoodDailySourceRole => 'Исходное намерение';

  @override
  String get relationNeighborhoodDailySelectedRole => 'Выбранное действие';

  @override
  String get relationNeighborhoodTypeNeed => 'Нужно';

  @override
  String get relationNeighborhoodTypeCan => 'Можно';

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
  String get relationNeighborhoodRelationArchived => 'Связь в архиве';

  @override
  String relationNeighborhoodPriority(String priority) {
    return 'Приоритет $priority';
  }

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
  String get relationPairAlreadyAdded => 'Уже добавлено';

  @override
  String get relationPairAlreadyAddedArchived => 'Уже добавлено, в архиве';

  @override
  String relationPairOtherGroup(String group) {
    return 'Уже в группе \"$group\"';
  }

  @override
  String relationPairOtherGroupArchived(String group) {
    return 'Уже в группе \"$group\", в архиве';
  }

  @override
  String get detailsRelationsGroupsLabel => 'Группы связей';

  @override
  String get detailsRelationsGroupNeeds => 'Нужно';

  @override
  String get detailsRelationsGroupCanUse => 'Можно использовать';

  @override
  String get detailsRelationsGroupNeededFor => 'Нужно для';

  @override
  String get detailsRelationsGroupCanBeUsedFor => 'Можно использовать для';

  @override
  String detailsRelationsGroupTileSemantic(String group, int count) {
    return '$group: активных — $count';
  }

  @override
  String detailsRelationsGroupTileArchivedSemantic(String group, int count) {
    return '$group: активных — $count, есть архивированные';
  }

  @override
  String detailsRelationsRowNeed(String priority) {
    return 'нужно · $priority';
  }

  @override
  String detailsRelationsRowCan(String priority) {
    return 'можно · $priority';
  }

  @override
  String detailsRelationsNeighborArchived(String title) {
    return '«$title» в архиве';
  }

  @override
  String detailsRelationsWalkIntention(String title) {
    return 'Открыть страницу намерения: $title';
  }

  @override
  String detailsRelationsWalkAction(String title) {
    return 'Открыть страницу действия: $title';
  }

  @override
  String get detailsRelationsNeedsHint =>
      'Чтобы достичь этого, нужно всё перечисленное.';

  @override
  String get detailsRelationsCanUseHint =>
      'Чтобы достичь этого, можно сделать любое из перечисленного.';

  @override
  String get detailsRelationsNeededForHint => 'Каждому из них это нужно.';

  @override
  String get detailsRelationsCanBeUsedForHint =>
      'Каждое из них может использовать это как один из путей.';

  @override
  String get detailsRelationsAdd => 'Добавить';

  @override
  String get detailsRelationsAddNeedsLabel => 'Добавить то, что нужно';

  @override
  String get detailsRelationsAddCanUseLabel =>
      'Добавить то, что можно использовать';

  @override
  String get detailsRelationsAddNeededForLabel =>
      'Добавить намерение, которому это нужно';

  @override
  String get detailsRelationsAddCanBeUsedForLabel =>
      'Добавить намерение, которое может это использовать';

  @override
  String get detailsRelationsEmptyNeedsTitle => 'Пока ничего не нужно';

  @override
  String get detailsRelationsEmptyNeedsIntentionText =>
      'Добавьте то, без чего этому намерению не обойтись.';

  @override
  String get detailsRelationsEmptyNeedsActionText =>
      'Действие может обходиться без других. Добавьте то, что ему нужно, если у него есть свои шаги.';

  @override
  String get detailsRelationsEmptyCanUseTitle => 'Пока нечего использовать';

  @override
  String get detailsRelationsEmptyCanUseText =>
      'Добавьте то, что помогает достичь этого, но не обязательно.';

  @override
  String get detailsRelationsEmptyNeededForTitle => 'Пока ни для чего не нужно';

  @override
  String get detailsRelationsEmptyNeededForText =>
      'Здесь появятся намерения, которым без этого не обойтись.';

  @override
  String get detailsRelationsEmptyCanBeUsedForTitle =>
      'Пока ни для чего не используется';

  @override
  String get detailsRelationsEmptyCanBeUsedForText =>
      'Здесь появятся намерения, к которым это — один из путей.';

  @override
  String get detailsRelationsEmptyArchivedText =>
      'Чтобы добавлять связи, восстановите намерение.';

  @override
  String get detailsRelationsArchiveFold => 'Архив';

  @override
  String detailsRelationsArchiveFoldSemantic(String group, int count) {
    return 'Архив группы «$group»: $count';
  }

  @override
  String get detailsChoicesTab => 'Выборы';

  @override
  String get detailsChoicesSourceHint =>
      'Дневные выборы, которые начинаются с этого намерения.';

  @override
  String get detailsChoicesSelectedHint =>
      'Дневные выборы, которые заканчиваются этим намерением.';

  @override
  String get detailsTitle => 'Подробности намерения';

  @override
  String get detailsTypeIntention => 'Намерение';

  @override
  String get detailsTypeAction => 'Действие';

  @override
  String get detailsTypeChoiceLabel => 'Намерение или действие';

  @override
  String get detailsTypeIntentionHint =>
      'Любого размера. Может занять больше дня.';

  @override
  String get detailsTypeActionHint =>
      'Выполнимо за один день, и понятно, что делать.';

  @override
  String get detailsArchivedBadge => 'Архив';

  @override
  String get detailsArchivedNote =>
      'Архивированные намерения остаются в сохранённых путях и не предлагаются в новых.';

  @override
  String get detailsRestoreFromArchiveAction => 'Восстановить из архива';

  @override
  String get detailsOptionsLabel => 'Параметры намерения';

  @override
  String get detailsOptionsTitle => 'Намерение';

  @override
  String get detailsOptionEdit => 'Изменить';

  @override
  String get detailsOptionArchive => 'Архивировать';

  @override
  String get detailsOptionDelete => 'Удалить';

  @override
  String get detailsOptionArchiveWithRelations =>
      'Его связи архивируются вместе с ним';

  @override
  String get detailsOptionArchiveAlone =>
      'Останется в сохранённых путях и не будет предлагаться в новых';

  @override
  String get detailsOptionRestoreWithRelations =>
      'Его связи останутся в архиве, пока вы их не восстановите';

  @override
  String get detailsOptionRestoreAlone =>
      'Новые пути снова смогут его использовать';

  @override
  String get detailsOptionDeleteKeepsTags => 'Его теги сохранятся';

  @override
  String get detailsOptionDeleteRelationsFirst => 'Сначала удалите его связи';

  @override
  String get detailsOptionDeleteDailyChoicesFirst =>
      'Сначала удалите его дневные выборы';

  @override
  String get detailsOptionDeleteRelationsAndDailyChoicesFirst =>
      'Сначала удалите его связи и дневные выборы';

  @override
  String get detailsOptionWait => 'Дождитесь окончания текущего изменения';

  @override
  String get detailsDeleteDialogTitle => 'Удалить намерение?';

  @override
  String get detailsDeleteDialogTextBefore => 'Намерение ';

  @override
  String get detailsDeleteDialogTextAfter =>
      ' будет безвозвратно удалено вместе с описанием. Его теги сохранятся.';

  @override
  String get detailsDeleteDialogCancel => 'Отмена';

  @override
  String get detailsDeleteDialogConfirm => 'Удалить';

  @override
  String detailsEditTitleLabel(String title) {
    return 'Изменить название: $title';
  }

  @override
  String detailsEditDescriptionLabel(String description) {
    return 'Изменить описание: $description';
  }

  @override
  String get detailsAddDescription => 'Добавить описание';

  @override
  String get detailsCreatedLabel => 'Создано';

  @override
  String get detailsChangedLabel => 'Изменено';

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
  String get detailsArchived => 'В архиве';

  @override
  String get detailsCancelEditAction => 'Отмена';

  @override
  String get detailsDeleted => 'Намерение удалено.';

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
  String get intentionEditDiscardTitle => 'Отменить изменения?';

  @override
  String get intentionEditDiscardMessage =>
      'Изменения намерения не сохранятся.';

  @override
  String get intentionEditDiscardAction => 'Отменить';

  @override
  String get intentionEditContinueAction => 'Продолжить правку';

  @override
  String get editorTitle => 'Создать намерение';

  @override
  String get editorSearchSubtitle => 'Сразу отмечается для новых связей';

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
  String get editorCreatedAndChosen => 'Намерение создано и отмечено.';

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
  String get graphOperationRelation => 'связь';

  @override
  String get graphOperationDailyChoice => 'дневной выбор';

  @override
  String get graphOperationAction => 'действие';

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
    int actions,
    int tags,
  ) {
    final intl.NumberFormat intentionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String intentionsString = intentionsNumberFormat.format(intentions);
    final intl.NumberFormat relationsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String relationsString = relationsNumberFormat.format(relations);
    final intl.NumberFormat actionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String actionsString = actionsNumberFormat.format(actions);
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
      actions,
      locale: localeName,
      other: '$actionsString действия',
      many: '$actionsString действий',
      few: '$actionsString действия',
      one: '$actionsString действие',
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
    int actions,
    int tags,
  ) {
    final intl.NumberFormat intentionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String intentionsString = intentionsNumberFormat.format(intentions);
    final intl.NumberFormat relationsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String relationsString = relationsNumberFormat.format(relations);
    final intl.NumberFormat actionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String actionsString = actionsNumberFormat.format(actions);
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
      actions,
      locale: localeName,
      other: '$actionsString действия',
      many: '$actionsString действий',
      few: '$actionsString действия',
      one: '$actionsString действие',
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
  String get tagAssignmentsTitle => 'Теги';

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
  String get tagAssignmentsAdd => 'Добавить';

  @override
  String tagAssignmentsAddLabel(String tagNames) {
    return 'Теги: $tagNames. Добавить или убрать';
  }

  @override
  String get tagAssignmentsAddEmptyLabel => 'Добавить теги';

  @override
  String tagAssignmentsRemoveNamed(String tagName) {
    return 'Убрать тег: $tagName';
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
  String get dailyChoiceDeleted => 'Дневной выбор удалён.';

  @override
  String get dailyChoiceSheetOptionEditDescription => 'Изменить описание';

  @override
  String get dailyChoiceSheetOptionDelete => 'Удалить дневной выбор';

  @override
  String get dailyChoiceDeleteDialogTitle => 'Удалить дневной выбор?';

  @override
  String get dailyChoiceDeleteDialogBefore => 'Выбор ';

  @override
  String dailyChoiceDeleteDialogAfter(String date) {
    return ' на $date будет удалён. Это действие нельзя отменить.';
  }

  @override
  String get dailyChoiceDeleteDialogAction => 'Удалить';

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
  String get actionDeleted => 'Действие удалено.';

  @override
  String get actionTitleInvalid => 'Проверьте название действия.';

  @override
  String get actionDescriptionInvalid => 'Проверьте описание действия.';

  @override
  String get actionOperationNotFound => 'Действие больше не существует.';

  @override
  String get actionOperationConflict =>
      'Данные изменились. Обновите их и подтвердите снова.';

  @override
  String get actionOperationUnavailable =>
      'Не удалось выполнить операцию с действием. Повторите попытку.';

  @override
  String get actionOperationCorruption =>
      'Сохранённые данные повреждены. Действие не изменено.';

  @override
  String get actionOperationUnexpected =>
      'Операция с действием не выполнена из-за непредвиденной ошибки.';

  @override
  String get actionPanelTitle => 'Действие';

  @override
  String get actionPanelExpand => 'Раскрыть панель действия';

  @override
  String get actionPanelCollapse => 'Свернуть панель действия';

  @override
  String get actionPanelLoading => 'Загружаем действие…';

  @override
  String get actionPanelUnavailable =>
      'Не удалось загрузить действие. Повторите попытку.';

  @override
  String get actionPanelCorruption =>
      'Сохранённое действие повреждено и не может быть показано.';

  @override
  String get actionPanelUnexpected =>
      'Не удалось загрузить действие из-за непредвиденной ошибки.';

  @override
  String actionPanelCompletionLabel(String action, String priority) {
    return 'Выполнение действия. $action. $priority';
  }

  @override
  String get actionRefresh => 'Обновить действие';

  @override
  String get actionFieldDate => 'Дата';

  @override
  String get actionFieldTime => 'Время';

  @override
  String get actionFieldPriority => 'Приоритет';

  @override
  String actionFieldDateLabel(String date) {
    return 'Дата: $date. Изменить дату';
  }

  @override
  String actionFieldTimeLabel(String time) {
    return 'Время: $time. Изменить время';
  }

  @override
  String get actionAllDay => 'Весь день';

  @override
  String actionPriorityOption(String priority) {
    return 'Приоритет $priority';
  }

  @override
  String get actionDateToday => 'Сегодня';

  @override
  String get actionDateTomorrow => 'Завтра';

  @override
  String get actionDateYesterday => 'Вчера';

  @override
  String get actionDateSheetLabel => 'Дата действия';

  @override
  String get actionTimeSheetLabel => 'Время действия';

  @override
  String get actionTimeHalfSwitchLabel => 'Половина суток';

  @override
  String get actionTimeAmLabel => 'До полудня';

  @override
  String get actionTimePmLabel => 'После полудня';

  @override
  String get actionCalendarPreviousMonth => 'Предыдущий месяц';

  @override
  String get actionCalendarNextMonth => 'Следующий месяц';

  @override
  String get actionCalendarDayAllCompleted => 'Все действия выполнены';

  @override
  String get actionCalendarDayHasIncomplete => 'Есть невыполненное действие';

  @override
  String get actionPanelOptionsLabel => 'Параметры действия';

  @override
  String get actionOptionEditText => 'Изменить название и описание';

  @override
  String get actionTextEditTitle => 'Изменить действие';

  @override
  String get actionTextEditBack => 'Назад к действию';

  @override
  String get actionTextEditSave => 'Сохранить';

  @override
  String get actionTextEditNameLabel => 'Название';

  @override
  String get actionTextEditDescriptionLabel => 'Описание';

  @override
  String get actionTextEditDiscardTitle => 'Отменить изменения?';

  @override
  String get actionTextEditDiscardMessage =>
      'Изменения названия и описания не сохранятся.';

  @override
  String get actionTextEditDiscardAction => 'Отменить';

  @override
  String get actionTextEditContinueAction => 'Продолжить правку';

  @override
  String get graphOperationAddRelations => 'Добавление';

  @override
  String get graphOperationRelations => 'связи';

  @override
  String relationsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавлено $count связи.',
      many: 'Добавлено $count связей.',
      few: 'Добавлено $count связи.',
      one: 'Добавлена $count связь.',
    );
    return '$_temp0';
  }

  @override
  String get relationsAdditionPairOccupied =>
      'Некоторые выбранные намерения уже связаны с этим намерением. Связи не созданы.';

  @override
  String get relationsAdditionParticipantNotFound =>
      'Одно из выбранных намерений больше не существует. Связи не созданы.';

  @override
  String get relationsAdditionParticipantArchived =>
      'Связать можно только активные намерения. Связи не созданы.';

  @override
  String get relationsAdditionUnavailable =>
      'Связи не созданы. Повторите попытку.';

  @override
  String get relationsAdditionCorruption =>
      'Сохранённые данные повреждены. Связи не созданы.';

  @override
  String get relationsAdditionUnexpected =>
      'Связи не созданы из-за непредвиденной ошибки.';

  @override
  String get relationEditorUpdateNotFound => 'Эта связь больше не существует.';

  @override
  String get relationEditorUpdateArchivedTypeChange =>
      'Связь архивирована, поэтому её тип нельзя изменить.';

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
      'Связь используется в сохранённом дневном пути. Сначала удалите использующие её дневные выборы.';

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
  String get relationDetailsPathProtection =>
      'Связь используется в сохранённом дневном пути, поэтому удалить её нельзя.';

  @override
  String relationSheetArchivedLabel(String phrase) {
    return '$phrase. Архив';
  }

  @override
  String get relationSheetArchivedNote =>
      'Архивные связи остаются в сохранённых путях и не предлагаются в новых.';

  @override
  String relationSheetOpenParticipant(String title) {
    return 'Открыть страницу намерения: $title';
  }

  @override
  String relationSheetOpenArchivedParticipant(String title) {
    return 'Открыть страницу намерения: $title. Архив';
  }

  @override
  String relationSheetPriorityHighest(String priority) {
    return 'Приоритет $priority, высший';
  }

  @override
  String relationSheetPriorityLowest(String priority) {
    return 'Приоритет $priority, низший';
  }

  @override
  String get relationSheetDescriptionTitle => 'Описание';

  @override
  String get relationSheetDescriptionLabel => 'Описание связи';

  @override
  String get relationSheetDescriptionBack => 'Назад к связи';

  @override
  String get relationSheetDescriptionSave => 'Сохранить';

  @override
  String get relationSheetDescriptionDiscardTitle => 'Отменить изменения?';

  @override
  String get relationSheetDescriptionDiscardMessage =>
      'Изменения описания не сохранятся.';

  @override
  String get relationSheetDescriptionDiscardAction => 'Отменить';

  @override
  String get relationSheetDescriptionContinueAction => 'Продолжить правку';

  @override
  String get relationSheetOptionsLabel => 'Параметры связи';

  @override
  String get relationSheetOptionArchive => 'Архивировать';

  @override
  String get relationSheetOptionRestore => 'Восстановить из архива';

  @override
  String get relationSheetOptionDelete => 'Удалить';

  @override
  String get relationSheetOptionRestoreBothArchived =>
      'Сначала восстановите исходное и связанное намерения, затем восстановите эту связь.';

  @override
  String get relationSheetDeleteDialogTitle => 'Удалить связь?';

  @override
  String get relationSheetDeleteDialogTextBefore => 'Связь «';

  @override
  String get relationSheetDeleteDialogTextAfter =>
      '» будет безвозвратно удалена вместе с описанием. Оба намерения сохранятся.';

  @override
  String get relationSheetDeleteDialogCancel => 'Отмена';

  @override
  String get relationSheetDeleteDialogConfirm => 'Удалить';

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
  String intentionCatalogRowLabel(String content) {
    return 'Открыть: $content';
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
  String get intentionPickerScopeCaption => 'Показать';

  @override
  String get intentionPickerScopeActive => 'Активные';

  @override
  String get intentionPickerScopeArchived => 'Архивные';

  @override
  String get intentionPickerScopeAll => 'Все, включая архивные';

  @override
  String get intentionPickerTypeCaption => 'Тип';

  @override
  String get intentionPickerTypeAll => 'Намерения и действия';

  @override
  String get intentionPickerTypeIntentionsOnly => 'Только намерения';

  @override
  String get intentionPickerTypeActionsOnly => 'Только действия';

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
  String intentionPickerScopeHeader(String scope, String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'all': 'Активные',
      'intentions': 'Активные намерения',
      'actions': 'Активные действия',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(type, {
      'all': 'Архивные',
      'intentions': 'Архивные намерения',
      'actions': 'Архивные действия',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(type, {
      'all': 'Все',
      'intentions': 'Все намерения',
      'actions': 'Все действия',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(scope, {
      'active': '$_temp0',
      'archived': '$_temp1',
      'all': '$_temp2',
      'other': '',
    });
    return '$_temp3';
  }

  @override
  String intentionPickerScopeHeaderLabel(String title, String summary) {
    return 'Показать и упорядочить. Показаны: $title. Сортировка: $summary.';
  }

  @override
  String intentionPickerScopeHeaderCountLabel(
    String title,
    int count,
    String summary,
  ) {
    return 'Показать и упорядочить. Показаны: $title, $count. Сортировка: $summary.';
  }

  @override
  String get intentionPickerActionsHeader => 'Действия';

  @override
  String get intentionPickerIntentionsHeader => 'Намерения';

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
  String intentionPickerEmptyScopedTypeTitle(String scope, String type) {
    String _temp0 = intl.Intl.selectLogic(type, {
      'actions': 'Нет активных действий',
      'intentions': 'Нет активных намерений',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(type, {
      'actions': 'Нет действий в архиве',
      'intentions': 'Нет намерений в архиве',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(type, {
      'actions': 'Действий пока нет',
      'intentions': 'Намерений пока нет',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(scope, {
      'active': '$_temp0',
      'archived': '$_temp1',
      'all': '$_temp2',
      'other': '',
    });
    return '$_temp3';
  }

  @override
  String get intentionPickerEmptyActionsText =>
      'Здесь появится намерение, отмеченное как действие.';

  @override
  String get intentionPickerEmptyIntentionsText =>
      'Здесь всё отмечено как действия.';

  @override
  String get intentionCatalogNoActiveTitle => 'Нет активных намерений';

  @override
  String get intentionCatalogNoActiveText =>
      'Новое создаётся кнопкой с плюсом внизу, а архивированные показывает строка «Показать».';

  @override
  String get intentionCatalogNoIntentionsTitle => 'Намерений пока нет';

  @override
  String get intentionCatalogNoIntentionsText =>
      'Ваши намерения появятся здесь. Первое создаётся кнопкой с плюсом внизу.';

  @override
  String get intentionCatalogEmptyArchiveTitle => 'В архиве ничего нет';

  @override
  String get intentionCatalogEmptyArchiveText =>
      'Архивированное намерение уходит из активного списка и остаётся здесь.';

  @override
  String get participantPickerTitle => 'Выбор намерений';

  @override
  String get intentionPickerSearchPlaceholder => 'Поиск по названию';

  @override
  String get intentionPickerClearSearch => 'Очистить название';

  @override
  String get intentionPickerCreateIntention => 'Создать намерение';

  @override
  String intentionPickerCreateNamed(String title) {
    return 'Создать «$title»';
  }

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
  String get relationEditorTypeNeed => 'Нужно';

  @override
  String get relationEditorTypeCan => 'Можно';

  @override
  String get relationEditorDescriptionTooLong =>
      'Используйте не более 4096 символов.';

  @override
  String get relationEditorDescriptionInvalidUnicode =>
      'Введите корректный Unicode-текст без NUL.';

  @override
  String get dailyChoiceAllDay => 'Весь день';

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
  String get dailyChoiceCatalogIncomplete => 'Невыполненные';

  @override
  String get dailyChoiceCatalogCompleted => 'Выполненные';

  @override
  String get dailyChoiceCatalogEmptyTitle => 'Выборов на эту дату нет';

  @override
  String get dailyChoiceCatalogEmptyText =>
      'Создайте выбор из действия и назначьте эту дату. Он появится здесь.';

  @override
  String get dailyChoiceCatalogRefreshing => 'Обновляем…';

  @override
  String get dailyChoiceCatalogScrollToTop => 'Вернуться к началу';

  @override
  String get dailyChoiceCatalogLoadingMore => 'Загружаем ещё дневные выборы…';

  @override
  String get dailyChoiceCatalogUnavailable =>
      'Не удалось загрузить дневные выборы.';

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
  String dailyChoiceCatalogPathStepCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count шага в пути',
      many: '$count шагов в пути',
      few: '$count шага в пути',
      one: '$count шаг в пути',
    );
    return '$_temp0';
  }

  @override
  String dailyChoiceCatalogCompletionLabel(
    int number,
    String action,
    String priority,
  ) {
    return 'Выполнение выбора № $number. $action. $priority';
  }

  @override
  String get dailyChoiceCompletionRefresh => 'Обновить выбор';

  @override
  String dailyChoiceCatalogRowLabel(int number, String action) {
    return 'Выбор № $number. $action';
  }

  @override
  String dailyChoiceCatalogRowSource(String source) {
    return 'Исходное намерение: $source';
  }

  @override
  String dailyChoiceCatalogRowTime(String time) {
    return 'В $time';
  }

  @override
  String get dailyChoiceDetailsTitle => 'Дневной выбор';

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
  String dailyChoiceDetailsStep(int number) {
    return 'Переход $number';
  }

  @override
  String get dailyChoiceSheetExpand => 'Раскрыть панель дневного выбора';

  @override
  String get dailyChoiceSheetCollapse => 'Свернуть панель дневного выбора';

  @override
  String dailyChoiceSheetCompletionLabel(String action, String priority) {
    return 'Выполнение выбора. $action. $priority';
  }

  @override
  String get dailyChoiceSheetOptionsLabel => 'Параметры дневного выбора';

  @override
  String get dailyChoiceSheetTabsLabel => 'Разделы дневного выбора';

  @override
  String get dailyChoiceSheetPathTab => 'Путь';

  @override
  String dailyChoiceSheetPathTabLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Путь, $count шага',
      many: 'Путь, $count шагов',
      few: 'Путь, $count шага',
      one: 'Путь, $count шаг',
    );
    return '$_temp0';
  }

  @override
  String dailyChoiceSheetPathTabArchivedLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Путь, $count шага, в пути есть архив',
      many: 'Путь, $count шагов, в пути есть архив',
      few: 'Путь, $count шага, в пути есть архив',
      one: 'Путь, $count шаг, в пути есть архив',
    );
    return '$_temp0';
  }

  @override
  String get dailyChoiceSheetPathArchivedNote =>
      'В пути есть архивированные намерения или связи.';

  @override
  String get dailyChoiceSheetDescriptionTitle => 'Описание';

  @override
  String get dailyChoiceSheetDescriptionBack => 'Назад к дневному выбору';

  @override
  String get dailyChoiceSheetDescriptionSave => 'Сохранить';

  @override
  String get dailyChoiceSheetDescriptionDiscardTitle => 'Отменить изменения?';

  @override
  String get dailyChoiceSheetDescriptionDiscardMessage =>
      'Изменения описания не сохранятся.';

  @override
  String get dailyChoiceSheetDescriptionDiscardAction => 'Отменить';

  @override
  String get dailyChoiceSheetDescriptionContinueAction => 'Продолжить правку';

  @override
  String get dailyChoiceFieldDate => 'Дата';

  @override
  String get dailyChoiceFieldTime => 'Время';

  @override
  String dailyChoiceFieldDateLabel(String date) {
    return 'Дата: $date. Изменить дату';
  }

  @override
  String dailyChoiceFieldTimeLabel(String time) {
    return 'Время: $time. Изменить время';
  }

  @override
  String get dailyChoiceDateSheetLabel => 'Дата дневного выбора';

  @override
  String get dailyChoiceTimeSheetLabel => 'Время дневного выбора';

  @override
  String get dailyChoiceTimeHalfSwitchLabel => 'Половина суток';

  @override
  String get dailyChoiceTimeAmLabel => 'До полудня';

  @override
  String get dailyChoiceTimePmLabel => 'После полудня';

  @override
  String get dailyChoiceDateTomorrow => 'Завтра';

  @override
  String get dailyChoiceDateYesterday => 'Вчера';

  @override
  String get creationCancelAction => 'Отменить создание';

  @override
  String get creationLeaveAction => 'Выйти из создания';

  @override
  String get creationSavingContinues =>
      'Сохранение продолжится после выхода из создания.';

  @override
  String batchSubtitle(String group) {
    return 'Добавить в \"$group\"';
  }

  @override
  String batchSubtitleSelected(String group, int count) {
    return 'Добавить в \"$group\" · выбрано $count';
  }

  @override
  String batchSheetLine(String group) {
    return 'Новые связи в \"$group\"';
  }

  @override
  String get batchNoteNeeds =>
      'Каждое отмеченное намерение станет связью: оно нужно этому намерению';

  @override
  String get batchNoteCanUse =>
      'Каждое отмеченное намерение станет связью: это намерение может его использовать';

  @override
  String get batchNoteNeededFor =>
      'Каждое отмеченное намерение станет связью: ему нужно это намерение';

  @override
  String get batchNoteCanBeUsedFor =>
      'Каждое отмеченное намерение станет связью: оно может использовать это намерение';

  @override
  String get batchDefaults =>
      'Связи получат приоритет P4 и не будут иметь описания; и то и другое меняется на странице';

  @override
  String get batchAnchorNote => 'Намерение, со страницы которого вы пришли';

  @override
  String get batchEmpty => 'Пока ничего не выбрано';

  @override
  String get batchSelected => 'Отмеченные намерения';

  @override
  String batchSourceSemantic(String name) {
    return 'Исходное намерение: $name';
  }

  @override
  String batchRelatedSemantic(String name) {
    return 'Связанное намерение: $name';
  }

  @override
  String batchRemove(String name) {
    return 'Снять отметку: $name';
  }

  @override
  String batchAddCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Добавить $count связи',
      many: 'Добавить $count связей',
      few: 'Добавить $count связи',
      one: 'Добавить $count связь',
    );
    return '$_temp0';
  }

  @override
  String get batchAddNone => 'Добавить связи';

  @override
  String get batchAdding => 'Добавляем…';

  @override
  String get batchDiscardTitle => 'Сбросить выбранные намерения?';

  @override
  String batchDiscardMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count связи не будут добавлены.',
      many: '$count связей не будут добавлены.',
      few: '$count связи не будут добавлены.',
      one: '$count связь не будет добавлена.',
    );
    return '$_temp0';
  }

  @override
  String get batchCreatedRemain => 'Созданные намерения останутся в каталоге.';

  @override
  String get batchDiscardAction => 'Сбросить';

  @override
  String get batchContinueAction => 'Продолжить выбор';
}
