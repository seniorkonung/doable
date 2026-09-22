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
  String get catalogTitle => 'Намерения';

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
  String get catalogLoadMoreValidation =>
      'Сохранённая позиция каталога больше недействительна.';

  @override
  String get catalogReload => 'Перезагрузить каталог';

  @override
  String get catalogReloading => 'Перезагружаем каталог…';

  @override
  String get catalogReady => 'Готово к действию';

  @override
  String get catalogNotReady => 'Не готово к действию';

  @override
  String get catalogHasDescription => 'Есть описание';

  @override
  String get catalogNoDescription => 'Нет описания';

  @override
  String intentionActiveRelationCount(int count) {
    return 'Активных связей: $count';
  }

  @override
  String get intentionActiveRelationCountRefreshFailed =>
      'Не удалось обновить количество активных связей.';

  @override
  String get intentionActiveRelationCountLoading =>
      'Загружаем количество активных связей…';

  @override
  String get intentionActiveRelationCountUnknown =>
      'Количество активных связей неизвестно.';

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
  String get detailsTitle => 'Подробности намерения';

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
  String get detailsSaved => 'Изменения сохранены.';

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
      'Это действие нельзя отменить. Намерение и его описание будут удалены навсегда.';

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
  String get detailsShowBlockingRelationsAction => 'Показать блокирующие связи';

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
  String get editorTitle => 'Создать намерение';

  @override
  String get editorCreateAction => 'Создать намерение';

  @override
  String get editorCreating => 'Создаём…';

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
  String get graphOperationNewRelation => 'новая связь';

  @override
  String get graphOperationRelation => 'связь';

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
  String get relationEditorUpdateUnavailable =>
      'Не удалось изменить связь. Повторите попытку.';

  @override
  String get relationEditorUpdateCorruption =>
      'Сохранённые данные повреждены. Связь не изменена.';

  @override
  String get relationEditorUpdateUnexpected =>
      'Не удалось изменить связь из-за непредвиденной ошибки.';

  @override
  String get relationNeighborhoodOpenRelation =>
      'Открывает подробные данные связи';

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
  String get participantPickerTitle => 'Выбор участника';

  @override
  String get participantPickerCancel => 'Отменить выбор';

  @override
  String get participantPickerEmpty => 'Других намерений для выбора нет.';

  @override
  String get participantPickerSelectHint =>
      'Выбирает это намерение участником связи';

  @override
  String get participantPickerOpenDetails =>
      'Открыть подробные данные намерения';

  @override
  String get relationEditorTitle => 'Новая связь';

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
  String get relationNeighborhoodCreateOutgoingAction =>
      'Создать исходящую связь';

  @override
  String get relationNeighborhoodCreateIncomingAction =>
      'Создать входящую связь';

  @override
  String relationEditorPriorityOption(String priority) {
    return 'Приоритет $priority';
  }
}
