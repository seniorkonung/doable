import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/localization/app_locale_resolution.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
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
import '../../../support/catalog_reconciliation_test_fallback.dart';
import '../../../support/daily_choice_local_date.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

/// Открывает каталог дневных выборов в оболочке приложения, как его видит
/// человек: с панелью основной навигации и общей кнопкой быстрого создания.
///
/// Приложение собрано с делегатами локализации и правилами выбора локали
/// приложения, поэтому [locale] — системная локаль устройства, а
/// неподдерживаемый язык даёт английский. [size] — логический размер экрана;
/// [today] — локальное сегодня.
/// [catalogDate] открывает отдельный каталог на дату вместо корневого.
/// Чтения каталога предоставляет [repository].
Future<AppRouter> pumpCatalogPage(
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
        ControlledDailyChoiceLocalDate(today).override,
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
    openDailyChoicesOn(router);
  } else {
    unawaited(router.push(DailyChoiceDateCatalogRoute(date: catalogDate)));
  }
  await tester.pump();
  // Переход к каталогу заканчивается без анимации, а первое чтение каталога
  // остаётся незавершённым до решения сценария.
  await tester.pump(const Duration(milliseconds: 400));
  return router;
}

/// Хранилище личного графа для страничных проверок каталога дневных выборов.
///
/// Записывает запросы выдачи в [queries], а отметок — в [dayStatusQueries].
/// Ответы остаются незавершёнными до решения сценария по номеру запроса.
final class CatalogPageRepository
    with TagReadContractTestFallback, CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  // Управляемые чтения невыполненных; completeFirst задаёт обе секции дня.
  final queries = <DailyChoiceCatalogQuery>[];
  final _requests = <Completer<DailyChoiceCatalogPageResult>>[];
  final _completedPages = <CalendarDate, DailyChoiceCatalogFirstPage>{};
  final dayStatusQueries = <DailyChoiceDayStatusQuery>[];
  final _dayStatusRequests = <Completer<DailyChoiceDayStatusesReadResult>>[];
  late TagCommandResult _tagCommandResult;
  final completionCommands = <UpdateDailyChoiceFields>[];
  final _completionRequests = <Completer<DailyChoiceCommandResult>>[];

  void failCompletion(int index, DailyChoiceCommandFailure failure) =>
      _completionRequests[index].complete(GraphCommandFailed(failure));

  void confirmCompletion(
    int index,
    DailyChoiceCatalogItem item, {
    required bool isCompleted,
    required int revision,
  }) {
    DailyChoice choice(bool completed) => DailyChoice(
      id: item.id,
      sourceIntentionId: item.source.id,
      selectedIntentionId: item.selected.id,
      date: item.date,
      description: item.description,
      schedule: item.schedule,
      priority: item.priority,
      isCompleted: completed,
    );
    final before = choice(item.isCompleted);
    final after = choice(isCompleted);
    final graphRevision = _Revision(revision);
    final counts = RelationCounts(
      activeNeedIncoming: 0,
      activeNeedOutgoing: 0,
      activeCanIncoming: 0,
      activeCanOutgoing: 0,
      archivedNeedIncoming: 0,
      archivedNeedOutgoing: 0,
      archivedCanIncoming: 0,
      archivedCanOutgoing: 0,
    );
    _completionRequests[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: DailyChoiceFieldsUpdated(
            before: before,
            choice: after,
            path: StoredChoicePath([
              ChoicePathStep(
                id: (ChoicePathStepId.decode(
                  _uuid(1),
                ) as ChoicePathStepIdDecodingSuccess).id,
                dailyChoiceId: item.id,
                relationId: (LongTermRelationId.decode(
                  _uuid(1),
                ) as LongTermRelationIdDecodingSuccess).id,
                previousStepId: null,
              ),
            ]),
            changes: [
              DailyChoiceChange(
                revision: graphRevision,
                before: before,
                after: after,
                releasedRelationIds: const [],
                occupiedRelationIds: const [],
                intentionCounts: {
                  item.source.id: counts,
                  item.selected.id: counts,
                },
                relationPermissions: const {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) {
    dayStatusQueries.add(query);
    final request = Completer<DailyChoiceDayStatusesReadResult>();
    _dayStatusRequests.add(request);
    return request.future;
  }

  /// Завершает отдельное чтение отметками только запрошенного диапазона,
  /// без изменения выдачи каталога.
  void completeDayStatuses(
    int index,
    Map<CalendarDate, DailyChoiceDayStatus> statuses, {
    int revision = 0,
  }) {
    final query = dayStatusQueries[index];
    final first = query.firstDate.toCanonicalString();
    final last = query.lastDate.toCanonicalString();
    _dayStatusRequests[index].complete(
      GraphResultSuccess(
        GraphSnapshot(
          value: DailyChoiceDayStatuses(
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
    const DailyChoiceDayStatusesReadError(DailyChoiceDayStatusesReadFailure()),
  );

  /// Подтверждает новую ревизию через настоящий координатор, не меняя
  /// дневные выборы: восстановление отметок не зависит от вида изменения.
  Future<void> confirmTagRename(
    GraphCommandCoordinator coordinator, {
    required int revision,
  }) async {
    final id = (TagId.decode(_uuid(1)) as TagIdDecodingSuccess).id;
    final before = Tag(id: id, name: TagName.fromInput('Тег ${revision - 1}'));
    final after = Tag(id: id, name: TagName.fromInput('Тег $revision'));
    final graphRevision = _Revision(revision);
    _tagCommandResult = TagCommandSucceeded(
      ConfirmedGraphResult(
        revision: graphRevision,
        value: TagRenamed(
          TagRenamedChange(
            revision: graphRevision,
            before: before,
            after: after,
          ),
        ),
      ),
    );
    final accepted = coordinator.acceptTagRename(
      RenameTag(tagId: id, name: after.name),
    ) as TagCommandAccepted;
    await accepted.future;
  }

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    if (command is RenameTag) {
      return _tagCommandResult as GraphCommandResult<T, F>;
    }
    if (command is UpdateDailyChoiceFields) {
      completionCommands.add(command as UpdateDailyChoiceFields);
      final request = Completer<DailyChoiceCommandResult>();
      _completionRequests.add(request);
      return await request.future as GraphCommandResult<T, F>;
    }
    throw UnsupportedError('Команда не предусмотрена сценарием.');
  }

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    if (query.isCompleted == true && query.cursor == null) {
      return Future.value(
        DailyChoiceCatalogPageSuccess(
          DailyChoiceCatalogFirstPage(
            items: _completedPages[query.date]?.items ?? const [],
            totalCount: _completedPages[query.date]?.totalCount ?? 0,
            hasTimedChoices:
                _completedPages[query.date]?.hasTimedChoices ?? false,
            nextCursor: _completedPages[query.date]?.nextCursor,
            revision:
                _completedPages[query.date]?.revision ?? const _Revision(),
          ),
        ),
      );
    }
    queries.add(query);
    final request = Completer<DailyChoiceCatalogPageResult>();
    _requests.add(request);
    return request.future;
  }

  /// Завершает запрос первой порции номер [index] строками [items] из
  /// [total] записей; [cursor] — продолжение выдачи.
  void completeFirst(
    int index,
    List<DailyChoiceCatalogItem> items, {
    required int total,
    DailyChoiceCatalogCursor? cursor,
    bool? hasTimedChoices,
    int revision = 0,
  }) {
    final completed = items.where((item) => item.isCompleted).toList();
    final incomplete = items.where((item) => !item.isCompleted).toList();
    final completedOnly = items.isNotEmpty && incomplete.isEmpty;
    _completedPages[queries[index].date] = DailyChoiceCatalogFirstPage(
      items: completed,
      totalCount: completedOnly ? total : completed.length,
      hasTimedChoices: completed.any(
        (item) => item.schedule is DailyChoiceTime,
      ),
      nextCursor: completedOnly ? cursor : null,
      revision: _Revision(revision),
    );
    _requests[index].complete(
      DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogFirstPage(
          items: incomplete,
          totalCount: completedOnly ? 0 : total - completed.length,
          hasTimedChoices:
              hasTimedChoices ??
              incomplete.any((item) => item.schedule is DailyChoiceTime),
          nextCursor: completedOnly ? null : cursor,
          revision: _Revision(revision),
        ),
      ),
    );
  }

  /// Завершает продолжение номер [index]; [cursor] оставляет следующую порцию.
  void completeMore(
    int index,
    List<DailyChoiceCatalogItem> items, {
    DailyChoiceCatalogCursor? cursor,
  }) => _requests[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: const _Revision(),
      ),
    ),
  );

  /// Завершает запрос номер [index] доказанно временной недоступностью
  /// хранилища: каталог предлагает повтор.
  void failUnavailable(int index) => _requests[index].complete(
    const DailyChoiceCatalogPageError(DailyChoiceCatalogUnavailableFailure()),
  );

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
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Продолжение выдачи каталога после завершённой первой порции.
final class CatalogPageCursor implements DailyChoiceCatalogCursor {
  const CatalogPageCursor();
}

/// Дневной выбор номер [number] на дату [date]: «Чтобы Основание, я сегодня
/// Действие»; выполнение задаёт [isCompleted].
DailyChoiceCatalogItem catalogPageItem(
  int number, {
  required CalendarDate date,
  bool isCompleted = false,
  DailyChoiceSchedule schedule = const DailyChoiceAllDay(),
  DailyChoicePriority priority = DailyChoicePriority.p4,
  DailyChoiceDescription? description,
  int pathIntentionCount = 2,
}) => DailyChoiceCatalogItem(
  id: (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id,
  source: DailyChoiceCatalogParticipant(
    id: (IntentionId.decode(_uuid(1)) as IntentionIdDecodingSuccess).id,
    title: 'Основание',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.notReady,
  ),
  selected: DailyChoiceCatalogParticipant(
    id: (IntentionId.decode(_uuid(2)) as IntentionIdDecodingSuccess).id,
    title: 'Действие',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.ready,
  ),
  date: date,
  isCompleted: isCompleted,
  schedule: schedule,
  priority: priority,
  description: description,
  pathIntentionCount: pathIntentionCount,
);

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
