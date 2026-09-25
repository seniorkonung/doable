import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  test('фильтр меняет поколение и отклоняет позднюю первую порцию', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final date = CalendarDate.fromParts(2026, 9, 24);
    harness.model.selectDate(date);
    expect(harness.repository.queries[1].date, date);
    harness.repository.first(1, [_item(2, date: date)], total: 1);
    await pumpEventQueue();
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.single.id,
      _choiceId(2),
    );
    expect(harness.state.selection.date, date);
  });

  test(
    'изменение выбора пересобирает загруженную часть и количество вместе',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final cursor = _Cursor();
      harness.repository.first(
        0,
        [_item(1), _item(2)],
        total: 3,
        cursor: cursor,
      );
      await pumpEventQueue();
      final load = harness.model.loadMore();
      expect(harness.repository.queries[1].cursor, same(cursor));
      harness.repository.more(1, [_item(3)]);
      await load;

      final completion = harness.createChoice(4, revision: 2);
      harness.repository.succeedCreation(0, 4, revision: 2);
      await completion.future;
      await pumpEventQueue();
      expect(harness.state, isA<DailyChoiceCatalogLoaded>());
      expect(
        (harness.state as DailyChoiceCatalogLoaded).freshness,
        DailyChoiceCatalogFreshness.refreshing,
      );
      expect(
        (harness.state as DailyChoiceCatalogLoaded).items.map((e) => e.id),
        [_choiceId(1), _choiceId(2), _choiceId(3)],
      );

      final refreshedCursor = _Cursor();
      harness.repository.first(
        2,
        [_item(4), _item(1)],
        total: 4,
        cursor: refreshedCursor,
        revision: 2,
      );
      await pumpEventQueue();
      expect((harness.state as DailyChoiceCatalogLoaded).totalCount, 3);
      harness.repository.more(3, [_item(2), _item(3)], revision: 2);
      await pumpEventQueue();
      final current = harness.state as DailyChoiceCatalogLoaded;
      expect(current.freshness, DailyChoiceCatalogFreshness.current);
      expect(current.totalCount, 4);
      expect(current.items.map((e) => e.id), [
        _choiceId(4),
        _choiceId(1),
        _choiceId(2),
        _choiceId(3),
      ]);
    },
  );

  test(
    'ошибка сборки сохраняет прежний снимок и допускает только уместный повтор',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.first(0, [_item(1)], total: 1);
      await pumpEventQueue();
      final completion = harness.createChoice(2, revision: 2);
      harness.repository.succeedCreation(0, 2, revision: 2);
      await completion.future;
      await pumpEventQueue();
      harness.repository.fail(1, const DailyChoiceCatalogCorruptionFailure());
      await pumpEventQueue();
      final stale = harness.state as DailyChoiceCatalogLoaded;
      expect(stale.items.single.id, _choiceId(1));
      expect(stale.freshness, DailyChoiceCatalogFreshness.stale);
      expect(stale.refreshFailure, isA<DailyChoiceCatalogCorruptionFailure>());
      await harness.model.retryRefresh();
      expect(harness.repository.queries, hasLength(2));
    },
  );

  test(
    'посторонняя ревизия требует новой основы до следующей порции',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.first(0, [_item(1)], total: 2, cursor: _Cursor());
      await pumpEventQueue();
      final completion = harness.createChoice(2, revision: 2);
      harness.repository.succeedUnrelatedCreation(0, 2, revision: 2);
      await completion.future;
      await pumpEventQueue();
      final load = harness.model.loadMore();
      expect(harness.repository.queries[1].cursor, isNull);
      harness.repository.first(
        1,
        [_item(2)],
        total: 2,
        revision: 2,
        cursor: _Cursor(),
      );
      await pumpEventQueue();
      harness.repository.more(2, [_item(1)], revision: 2);
      await load;
      expect(
        (harness.state as DailyChoiceCatalogLoaded).revision.compareTo(
          const _Revision(2),
        ),
        GraphRevisionOrder.same,
      );
    },
  );

  test('удаление во время подгрузки не возвращает удалённую строку', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.first(
      0,
      [_item(1), _item(2)],
      total: 3,
      cursor: _Cursor(),
    );
    await pumpEventQueue();
    final oldLoad = harness.model.loadMore();
    final deletion = harness.coordinator.acceptDailyChoiceDelete(
      DeleteDailyChoice(_choiceId(1)),
    ) as DailyChoiceCommandAccepted;
    harness.repository.succeedDeletion(0, 1, revision: 2);
    await deletion.future;
    await pumpEventQueue();
    expect(
      (harness.state as DailyChoiceCatalogLoaded).freshness,
      DailyChoiceCatalogFreshness.refreshing,
    );
    harness.repository.more(1, [_item(3)]);
    await oldLoad;
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.first.id,
      _choiceId(1),
    );
    harness.repository.first(2, [_item(2), _item(3)], total: 2, revision: 2);
    await pumpEventQueue();
    final updated = harness.state as DailyChoiceCatalogLoaded;
    expect(updated.items.map((item) => item.id), [_choiceId(2), _choiceId(3)]);
    expect(updated.totalCount, 2);
    expect(updated.freshness, DailyChoiceCatalogFreshness.current);
  });

  test('выполнение не меняет фильтр и не скрывает остальные даты', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model.selectCompletion(false);
    harness.repository.first(1, [_item(1)], total: 1);
    await pumpEventQueue();
    harness.repository.first(0, [], total: 0);
    await pumpEventQueue();
    final creation = harness.createChoice(2, revision: 2);
    harness.repository.succeedCreation(0, 2, revision: 2, isCompleted: true);
    await creation.future;
    await pumpEventQueue();
    expect(harness.state.selection.isCompleted, false);
    expect((harness.state as DailyChoiceCatalogLoaded).needsRebase, isTrue);
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.single.id,
      _choiceId(1),
    );
    harness.model.clearFilters();
    expect(harness.repository.queries.last.isCompleted, isNull);
    expect(harness.repository.queries.last.date, isNull);
    harness.repository.first(2, [_item(2), _item(1)], total: 2, revision: 2);
    await pumpEventQueue();
    expect((harness.state as DailyChoiceCatalogLoaded).totalCount, 2);
  });

  test(
    'смена даты перемещает строку из выбранного дня в общий каталог',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final oldDate = CalendarDate.fromParts(2026, 9, 24);
      final newDate = CalendarDate.fromParts(2026, 9, 25);
      harness.model.selectDate(oldDate);
      harness.repository.first(1, [_item(1)], total: 1);
      await pumpEventQueue();
      harness.repository.first(0, [], total: 0);
      await pumpEventQueue();

      final update = harness.coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: _choiceId(1),
          patch: DailyChoiceFieldsPatch(date: DailyChoiceFieldSet(newDate)),
        ),
      ) as DailyChoiceCommandAccepted;
      harness.repository.succeedDateUpdate(0, 1, oldDate, newDate, revision: 2);
      await update.future;
      await pumpEventQueue();
      expect(
        (harness.state as DailyChoiceCatalogLoaded).freshness,
        DailyChoiceCatalogFreshness.refreshing,
      );
      harness.repository.first(2, [], total: 0, revision: 2);
      await pumpEventQueue();
      expect(harness.state, isA<DailyChoiceCatalogEmpty>());
      expect(harness.state.selection.date, oldDate);

      harness.model.clearFilters();
      harness.repository.first(
        3,
        [_item(1, date: newDate)],
        total: 1,
        revision: 2,
      );
      await pumpEventQueue();
      expect(
        (harness.state as DailyChoiceCatalogLoaded).items.single.date,
        newDate,
      );
    },
  );

  test('переименование участника обновляет показанную формулировку', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    final update = harness.coordinator.acceptExisting(
      UpdateIntention(
        id: _intentionId(1),
        title: 'Новое основание',
        description: null,
      ),
      presentationTitle: 'Основание',
    ) as IntentionCommandAccepted;
    harness.repository.succeedRename(1, revision: 2);
    await update.future;
    await pumpEventQueue();
    final newItem = DailyChoiceCatalogItem(
      id: _choiceId(1),
      source: DailyChoiceCatalogParticipant(
        id: _intentionId(1),
        title: 'Новое основание',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.notReady,
      ),
      selected: _item(1).selected,
      date: CalendarDate.fromParts(2026, 9, 24),
      isCompleted: false,
    );
    harness.repository.first(1, [newItem], total: 1, revision: 2);
    await pumpEventQueue();
    expect(
      (harness.state as DailyChoiceCatalogLoaded).items.single.source.title,
      'Новое основание',
    );
  });

  test('ответ прежней эпохи не заменяет подтверждённую новую основу', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final creation = harness.createChoice(2, revision: 1);
    harness.repository.succeedCreation(0, 2, revision: 1, epoch: 1);
    await creation.future;
    await pumpEventQueue();
    harness.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    expect(harness.state, isA<DailyChoiceCatalogInitialLoad>());
    expect(harness.repository.queries, hasLength(2));
    harness.repository.first(
      1,
      [_item(2), _item(1)],
      total: 2,
      revision: 1,
      epoch: 1,
    );
    await pumpEventQueue();
    final current = harness.state as DailyChoiceCatalogLoaded;
    expect(current.items.map((item) => item.id), [_choiceId(2), _choiceId(1)]);
    expect(
      current.revision.compareTo(const _Revision(1, epoch: 1)),
      GraphRevisionOrder.same,
    );
  });
}

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    subscription = container.listen(
      dailyChoiceCatalogViewModelProvider,
      (_, _) {},
    );
  }

  final _Repository repository = _Repository();
  late final ProviderContainer container;
  late final ProviderSubscription<DailyChoiceCatalogState> subscription;
  DailyChoiceCatalogViewModel get model =>
      container.read(dailyChoiceCatalogViewModelProvider.notifier);
  DailyChoiceCatalogState get state =>
      container.read(dailyChoiceCatalogViewModelProvider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  DailyChoiceCommandAccepted createChoice(int id, {required int revision}) =>
      coordinator.acceptDailyChoiceCreation(
        DailyChoiceCreationFormKey(),
        CreateDailyChoice(
          sourceIntentionId: _intentionId(1),
          selectedIntentionId: _intentionId(2),
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: _relationId(1),
              sourceIntentionId: _intentionId(1),
              type: LongTermRelationType.need,
              relatedIntentionId: _intentionId(2),
            ),
          ]),
          date: CalendarDate.fromParts(2026, 9, 24),
          description: null,
          isCompleted: false,
        ),
      ) as DailyChoiceCommandAccepted;
  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final queries = <DailyChoiceCatalogQuery>[];
  final _pages = <Completer<DailyChoiceCatalogPageResult>>[];
  final _commands = <Completer<DailyChoiceCommandResult>>[];
  final _intentionCommands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) {
    queries.add(query);
    final request = Completer<DailyChoiceCatalogPageResult>();
    _pages.add(request);
    return request.future;
  }

  void first(
    int index,
    List<DailyChoiceCatalogItem> items, {
    required int total,
    DailyChoiceCatalogCursor? cursor,
    int revision = 1,
    int epoch = 0,
  }) => _pages[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogFirstPage(
        items: items,
        totalCount: total,
        nextCursor: cursor,
        revision: _Revision(revision, epoch: epoch),
      ),
    ),
  );
  void more(
    int index,
    List<DailyChoiceCatalogItem> items, {
    DailyChoiceCatalogCursor? cursor,
    int revision = 1,
  }) => _pages[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );
  void fail(int index, DailyChoiceCatalogReadFailure failure) =>
      _pages[index].complete(DailyChoiceCatalogPageError(failure));

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is UpdateIntention) {
      final request =
          Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
      _intentionCommands.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    final request = Completer<DailyChoiceCommandResult>();
    _commands.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void succeedCreation(
    int index,
    int id, {
    required int revision,
    bool isCompleted = false,
    int epoch = 0,
  }) {
    final choice = DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: CalendarDate.fromParts(2026, 9, 24),
      description: null,
      isCompleted: isCompleted,
    );
    final change = DailyChoiceChange(
      revision: _Revision(revision, epoch: epoch),
      before: null,
      after: choice,
      releasedRelationIds: const [],
      occupiedRelationIds: [_relationId(1)],
      intentionCounts: {_intentionId(1): _counts(), _intentionId(2): _counts()},
      relationPermissions: {
        _relationId(1):
            const LongTermRelationPermissions.referencedByDailyPath(),
      },
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision, epoch: epoch),
          value: DailyChoiceCreated(
            choice: choice,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(id),
                dailyChoiceId: choice.id,
                relationId: _relationId(1),
                previousStepId: null,
              ),
            ]),
            changes: [change],
          ),
        ),
      ),
    );
  }

  void succeedDeletion(int index, int id, {required int revision}) {
    final choice = DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: CalendarDate.fromParts(2026, 9, 24),
      description: null,
      isCompleted: false,
    );
    final change = DailyChoiceChange(
      revision: _Revision(revision),
      before: choice,
      after: null,
      releasedRelationIds: [_relationId(1)],
      occupiedRelationIds: const [],
      intentionCounts: {_intentionId(1): _counts(), _intentionId(2): _counts()},
      relationPermissions: {
        _relationId(1): const LongTermRelationPermissions.unrestricted(),
      },
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: DailyChoiceDeleted(choice: choice, changes: [change]),
        ),
      ),
    );
  }

  void succeedDateUpdate(
    int index,
    int id,
    CalendarDate beforeDate,
    CalendarDate afterDate, {
    required int revision,
  }) {
    DailyChoice choice(CalendarDate date) => DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: date,
      description: null,
      isCompleted: false,
    );
    final before = choice(beforeDate);
    final after = choice(afterDate);
    final change = DailyChoiceChange(
      revision: _Revision(revision),
      before: before,
      after: after,
      releasedRelationIds: const [],
      occupiedRelationIds: const [],
      intentionCounts: {_intentionId(1): _counts(), _intentionId(2): _counts()},
      relationPermissions: const {},
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: DailyChoiceFieldsUpdated(
            before: before,
            choice: after,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(id),
                dailyChoiceId: after.id,
                relationId: _relationId(1),
                previousStepId: null,
              ),
            ]),
            changes: [change],
          ),
        ),
      ),
    );
  }

  void succeedRename(int id, {required int revision}) {
    final before = _IntentionEntry(_summary(id, 'Основание'));
    final after = _IntentionEntry(_summary(id, 'Новое основание'));
    final mutation = IntentionCatalogUpdated(
      revision: _Revision(revision),
      before: before,
      after: after,
    );
    final intention = Intention(
      id: _intentionId(id),
      title: 'Новое основание',
      description: null,
      readiness: IntentionReadiness.notReady,
      archiveState: IntentionArchiveState.active,
      createdAt: IntentionTimestamp(DateTime.utc(2026)),
      updatedAt: IntentionTimestamp(DateTime.utc(2026)),
    );
    _intentionCommands[0].complete(
      ResultSuccess(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: IntentionSaved(intention, catalogMutation: mutation),
        ),
      ),
    );
  }

  void succeedUnrelatedCreation(int index, int id, {required int revision}) {
    final choice = DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: CalendarDate.fromParts(2026, 9, 24),
      description: null,
      isCompleted: false,
    );
    _commands[index].complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: DailyChoiceCreated(
            choice: choice,
            path: StoredChoicePath([
              ChoicePathStep(
                id: _stepId(id),
                dailyChoiceId: choice.id,
                relationId: _relationId(1),
                previousStepId: null,
              ),
            ]),
            changes: [_UnrelatedChange(_Revision(revision))],
          ),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Cursor implements DailyChoiceCatalogCursor {}

final class _UnrelatedChange implements GraphChange {
  const _UnrelatedChange(this.revision);
  @override
  final GraphRevision revision;
}

final class _IntentionEntry implements IntentionCatalogEntrySnapshot {
  const _IntentionEntry(this.summary);
  @override
  final IntentionSummary summary;
  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}

IntentionSummary _summary(int id, String title) => IntentionSummary(
  id: _intentionId(id),
  title: title,
  hasDescription: false,
  readiness: IntentionReadiness.notReady,
  archiveState: IntentionArchiveState.active,
  activeRelationCount: 0,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

final class _Revision implements GraphRevision {
  const _Revision(this.value, {this.epoch = 0});
  final int value;
  final int epoch;
  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is! _Revision || epoch != other.epoch
      ? GraphRevisionOrder.differentEpoch
      : value < other.value
      ? GraphRevisionOrder.older
      : value > other.value
      ? GraphRevisionOrder.newer
      : GraphRevisionOrder.same;
}

DailyChoiceCatalogItem _item(int id, {CalendarDate? date}) =>
    DailyChoiceCatalogItem(
      id: _choiceId(id),
      source: DailyChoiceCatalogParticipant(
        id: _intentionId(1),
        title: 'Основание',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.notReady,
      ),
      selected: DailyChoiceCatalogParticipant(
        id: _intentionId(2),
        title: 'Действие',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.ready,
      ),
      date: date ?? CalendarDate.fromParts(2026, 9, 24),
      isCompleted: false,
    );

RelationCounts _counts() => RelationCounts(
  activeNeedIncoming: 0,
  activeNeedOutgoing: 0,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: 0,
  archivedCanOutgoing: 0,
);

IntentionId _intentionId(int value) => switch (IntentionId.decode(
  '018f1200-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
LongTermRelationId _relationId(int value) => switch (LongTermRelationId.decode(
  '018f1300-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  LongTermRelationIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
DailyChoiceId _choiceId(int value) => switch (DailyChoiceId.decode(
  '018f1400-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
ChoicePathStepId _stepId(int value) => switch (ChoicePathStepId.decode(
  '018f1500-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  ChoicePathStepIdDecodingSuccess(:final id) => id,
  _ => throw StateError('ID'),
};
