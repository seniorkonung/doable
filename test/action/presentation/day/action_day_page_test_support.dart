import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action.dart' as domain;
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/action/presentation/day/action_day_body.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/controlled_local_date.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';
import '../../../support/tag_positions.dart';
import '../../../support/tag_read_contract_test_fallback.dart';

/// Открывает экран дня в оболочке приложения, как его видит
/// человек: с панелью основной навигации и общей кнопкой быстрого создания.
///
/// Приложение собрано с делегатами локализации и правилами выбора локали
/// приложения, поэтому [locale] — системная локаль устройства, а
/// неподдерживаемый язык даёт английский. [size] — логический размер экрана;
/// [today] — локальное сегодня.
/// [catalogDate] открывает отдельный экран дня на дату вместо корневого.
/// Чтения экрана дня предоставляет [repository].
Future<AppRouter> pumpActionDay(
  WidgetTester tester,
  PersonalGraphRepository repository, {
  required CalendarDate today,
  required Locale locale,
  required Size size,
  CalendarDate? catalogDate,
}) async {
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = AppRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inMemoryQuickCreationModeOverride,
        personalGraphRepositoryProvider.overrideWithValue(repository),
        ControlledLocalDate(today).override,
      ],
      retry: (count, error) => null,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: resolveAppLocale,
        routerConfig: router.config(),
      ),
    ),
  );
  if (catalogDate == null) {
    openActionsOn(router);
  } else {
    unawaited(router.push(ActionDayDateRoute(date: catalogDate)));
  }
  await tester.pump();
  // Переход к экрану дня заканчивается без анимации, а первое чтение выдачи
  // остаётся незавершённым до решения сценария.
  await tester.pump(const Duration(milliseconds: 400));
  return router;
}

/// Хранилище личного графа для страничных проверок экрана дня.
///
/// Записывает запросы выдачи в [queries], а отметок — в [dayStatusQueries].
/// Ответы остаются незавершёнными до решения сценария по номеру запроса.
final class ActionDayRepository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  // Управляемые чтения невыполненных; completeFirst задаёт обе секции дня.
  final queries = <ActionDayQuery>[];
  final _requests = <Completer<ActionDayPageResult>>[];
  final _completedPages = <CalendarDate, ActionDayFirstPage>{};
  final dayStatusQueries = <ActionDayStatusQuery>[];
  final _dayStatusRequests = <Completer<ActionDayStatusesReadResult>>[];
  late TagCommandResult _tagCommandResult;
  final completionCommands = <UpdateActionFields>[];
  final _completionRequests = <Completer<ActionCommandResult>>[];

  void failCompletion(int index, ActionCommandFailure failure) =>
      _completionRequests[index].complete(GraphCommandFailed(failure));

  void confirmCompletion(
    int index,
    ActionListItem item, {
    required bool isCompleted,
    required int revision,
  }) {
    final before = _action(item, isCompleted: item.isCompleted);
    final after = _action(item, isCompleted: isCompleted);
    final graphRevision = _Revision(revision);
    _completionRequests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: ActionFieldsUpdated(
            action: after,
            changes: [
              ActionUpdatedChange(
                revision: graphRevision,
                before: before,
                after: after,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) {
    dayStatusQueries.add(query);
    final request = Completer<ActionDayStatusesReadResult>();
    _dayStatusRequests.add(request);
    return request.future;
  }

  /// Завершает отдельное чтение отметками только запрошенного диапазона,
  /// без изменения выдачи каталога.
  void completeDayStatuses(
    int index,
    Map<CalendarDate, ActionDayStatus> statuses, {
    int revision = 0,
  }) {
    final query = dayStatusQueries[index];
    final first = query.firstDate.toCanonicalString();
    final last = query.lastDate.toCanonicalString();
    _dayStatusRequests[index].complete(
      GraphResultSuccess(
        GraphSnapshot(
          value: ActionDayStatuses(
            query: query,
            statuses: {
              for (final entry in statuses.entries)
                if (entry.key.toCanonicalString().compareTo(first) >= 0 &&
                    entry.key.toCanonicalString().compareTo(last) <= 0)
                  entry.key: entry.value,
            },
          ),
          revision: _Revision(revision),
        ),
      ),
    );
  }

  /// Завершает отдельное чтение отметок отказом, не затрагивая выдачу.
  void failDayStatuses(int index) => _dayStatusRequests[index].complete(
    const ActionDayStatusesReadError(ActionDayStatusesUnexpectedFailure()),
  );

  /// Подтверждает новую ревизию через настоящий координатор, не меняя
  /// действия: восстановление отметок не зависит от вида изменения.
  Future<void> confirmTagRename(
    GraphCommandCoordinator coordinator, {
    required int revision,
  }) async {
    final id = (TagId.decode(_uuid(1)) as TagIdDecodingSuccess).id;
    final before = Tag(
      id: id,
      name: TagName.fromInput('Тег ${revision - 1}'),
      color: null,
      position: tagPositionAt(1000),
    );
    final after = Tag(
      id: id,
      name: TagName.fromInput('Тег $revision'),
      color: before.color,
      position: before.position,
    );
    final graphRevision = _Revision(revision);
    _tagCommandResult = TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: graphRevision,
        value: TagUpdated(
          TagUpdatedChange(
            revision: graphRevision,
            before: before,
            after: after,
          ),
        ),
      ),
    );
    final accepted = coordinator.acceptTagUpdate(
      UpdateTag(tagId: id, name: after.name, color: null),
    ) as TagCommandAccepted;
    await accepted.future;
  }

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    if (command is UpdateTag) {
      return _tagCommandResult as GraphCommandResult<T, F>;
    }
    if (command is UpdateActionFields) {
      completionCommands.add(command as UpdateActionFields);
      final request = Completer<ActionCommandResult>();
      _completionRequests.add(request);
      return await request.future as GraphCommandResult<T, F>;
    }
    throw UnsupportedError('Команда не предусмотрена сценарием.');
  }

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) {
    if (query.section == ActionDaySection.completed && query.cursor == null) {
      final completed = _completedPages[query.date];
      return Future.value(
        ActionDayPageSuccess(
          ActionDayFirstPage(
            items: completed?.items ?? const [],
            incompleteCount: completed?.incompleteCount ?? 0,
            completedCount: completed?.completedCount ?? 0,
            hasTimedActions: completed?.hasTimedActions ?? false,
            nextCursor: completed?.nextCursor,
            revision: completed?.revision ?? const _Revision(),
          ),
        ),
      );
    }
    queries.add(query);
    final request = Completer<ActionDayPageResult>();
    _requests.add(request);
    return request.future;
  }

  /// Завершает запрос первой порции номер [index] строками [items] из
  /// [total] записей; [cursor] — продолжение выдачи. Признак времени дня
  /// [hasTimedActions] по умолчанию следует за строками, а явное значение
  /// выражает время в ещё не полученной порции.
  void completeFirst(
    int index,
    List<ActionListItem> items, {
    required int total,
    ActionDayCursor? cursor,
    bool? hasTimedActions,
    int revision = 0,
  }) {
    final completed = items.where((item) => item.isCompleted).toList();
    final incomplete = items.where((item) => !item.isCompleted).toList();
    final completedOnly = items.isNotEmpty && incomplete.isEmpty;
    final completedCount = completedOnly ? total : completed.length;
    final incompleteCount = completedOnly ? 0 : total - completed.length;
    final timed =
        hasTimedActions ?? items.any((item) => item.schedule is ActionAtHour);
    _completedPages[queries[index].date] = ActionDayFirstPage(
      items: completed,
      incompleteCount: incompleteCount,
      completedCount: completedCount,
      hasTimedActions: timed,
      nextCursor: completedOnly ? cursor : null,
      revision: _Revision(revision),
    );
    _requests[index].complete(
      ActionDayPageSuccess(
        ActionDayFirstPage(
          items: incomplete,
          incompleteCount: incompleteCount,
          completedCount: completedCount,
          hasTimedActions: timed,
          nextCursor: completedOnly ? null : cursor,
          revision: _Revision(revision),
        ),
      ),
    );
  }

  /// Завершает продолжение номер [index]; [cursor] оставляет следующую порцию.
  void completeMore(
    int index,
    List<ActionListItem> items, {
    ActionDayCursor? cursor,
  }) => _requests[index].complete(
    ActionDayPageSuccess(
      ActionDayContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: const _Revision(),
      ),
    ),
  );

  /// Завершает запрос номер [index] доказанно временной недоступностью
  /// хранилища: каталог предлагает повтор.
  void failUnavailable(int index) =>
      fail(index, const ActionDayUnavailableFailure());

  /// Завершает запрос номер [index] отказом [failure].
  void fail(int index, ActionDayReadFailure failure) =>
      _requests[index].complete(ActionDayPageError(failure));

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => ResultSuccess(
    IntentionCatalogFirstPage(
      items: const [],
      totalCount: 0,
      nextCursor: null,
      revision: const _Revision(),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Подтверждает изменение видимого действия [item], начатое не его строкой,
/// и начинает обновление выдачи. Поля действия остаются прежними, поэтому
/// обновление может вернуть те же строки.
Future<void> confirmOutsideActionChange(
  WidgetTester tester,
  ActionDayRepository repository,
  ActionListItem item, {
  required int revision,
}) async {
  final coordinator = ProviderScope.containerOf(
    tester.element(find.byType(ActionDayBody)),
  ).read(graphCommandCoordinatorProvider.notifier);
  coordinator.acceptActionUpdate(
    UpdateActionFields(
      actionId: item.id,
      patch: ActionFieldsPatch(isCompleted: ActionFieldSet(item.isCompleted)),
    ),
  );
  await tester.pump();
  repository.confirmCompletion(
    repository.completionCommands.length - 1,
    item,
    isCompleted: item.isCompleted,
    revision: revision,
  );
  await tester.pump();
  await tester.pump();
}

/// Продолжение выдачи экрана дня после завершённой первой порции.
final class ActionDayTestCursor implements ActionDayCursor {
  const ActionDayTestCursor();
}

/// Действие номер [number] на дату [date] с корневым намерением «Основание»;
/// выполнение задаёт [isCompleted]. Название действия — «Действие».
ActionListItem actionDayItem(
  int number, {
  required CalendarDate date,
  bool isCompleted = false,
  ActionSchedule schedule = const ActionAllDay(),
  ActionPriority priority = ActionPriority.p4,
  ActionDescription? description,
  int pathIntentionCount = 2,
}) => ActionListItem(
  id: _actionId(number),
  title: ActionTitle('Действие'),
  description: description,
  date: date,
  schedule: schedule,
  priority: priority,
  isCompleted: isCompleted,
  rootIntentionId: _intentionId(1),
  rootTitle: 'Основание',
  pathIntentionCount: pathIntentionCount,
);

/// Полное действие строки: путь из [ActionListItem.pathIntentionCount]
/// намерений с корнем [ActionListItem.rootIntentionId].
domain.Action _action(ActionListItem item, {required bool isCompleted}) =>
    domain.Action(
      id: item.id,
      title: item.title,
      description: item.description,
      path: ActionPath([
        item.rootIntentionId,
        for (var step = 1; step < item.pathIntentionCount; step++)
          _intentionId(1 + step),
      ]),
      date: item.date,
      schedule: item.schedule,
      priority: item.priority,
      isCompleted: isCompleted,
      creationSequence: domain.ActionCreationSequence(1),
      createdAt: domain.ActionTimestamp(DateTime.utc(2026, 10, 1)),
      updatedAt: domain.ActionTimestamp(DateTime.utc(2026, 10, 1)),
    );

ActionId _actionId(int number) =>
    (ActionId.decode(_uuid(number)) as ActionIdDecodingSuccess).id;

IntentionId _intentionId(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;

String _uuid(int number) =>
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}';

final class _Revision implements GraphRevision {
  const _Revision([this.value = 0]);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is! _Revision
      ? GraphRevisionOrder.differentEpoch
      : value < other.value
      ? GraphRevisionOrder.older
      : value > other.value
      ? GraphRevisionOrder.newer
      : GraphRevisionOrder.same;
}
