import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_instance.dart';
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
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/daily_choice_local_date.dart';
import '../../../support/tag_read_contract_test_fallback.dart';

part 'daily_choice_catalog_completion_scenarios.dart';

final _today = CalendarDate.fromParts(2026, 9, 24);

void main() {
  _completionScenarios();
  test('первые порции публикуются только согласованной парой; раскрытие не читает граф', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.first(0, [_item(1)], total: 2, cursor: _Cursor());
    await pumpEventQueue();
    expect(h.state, isA<DailyChoiceCatalogInitialLoad>());
    h.repository.first(1, [_item(2, completed: true)], total: 1);
    await pumpEventQueue();
    expect(_loaded(h).incomplete.items.single.id, _choiceId(1));
    expect(_loaded(h).completed.items.single.id, _choiceId(2));
    expect(_loaded(h).totalCount, 3);
    expect(h.state.selection.incompleteExpanded, isTrue);
    expect(h.state.selection.completedExpanded, isFalse);
    h.model.toggleSection(false);
    h.model.toggleSection(true);
    expect(h.state.selection.incompleteExpanded, isFalse);
    expect(h.state.selection.completedExpanded, isTrue);
    expect(h.repository.queries, hasLength(2));
    expect(h.repository.queries.map((q) => q.isCompleted), [false, true]);
  });

  test(
    'подгрузки секций независимы и ответы сохраняют обе загруженные части',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await _pair(
        h,
        incomplete: [_item(1)],
        completed: [_item(3, completed: true)],
        more: true,
      );
      final incomplete = h.model.loadMore(isCompleted: false);
      final completed = h.model.loadMore(isCompleted: true);
      expect(
        _loaded(h).incomplete.pageStatus,
        isA<DailyChoiceCatalogPageLoading>(),
      );
      expect(
        _loaded(h).completed.pageStatus,
        isA<DailyChoiceCatalogPageLoading>(),
      );
      h.repository.more(3, [_item(4, completed: true)]);
      await completed;
      h.repository.more(2, [_item(2)]);
      await incomplete;
      expect(_loaded(h).incomplete.items.map((i) => i.id), [
        _choiceId(1),
        _choiceId(2),
      ]);
      expect(_loaded(h).completed.items.map((i) => i.id), [
        _choiceId(3),
        _choiceId(4),
      ]);
    },
  );

  test('подтверждение между чтениями не публикует смешанную пару', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final published = <List<DailyChoiceId>>[];
    final sub = h.container.listen(h.provider, (_, value) {
      if (value is DailyChoiceCatalogLoaded) {
        published.add(value.items.map((i) => i.id).toList());
      }
    });
    addTearDown(sub.close);
    h.repository.first(0, [_item(1)], total: 1);
    await pumpEventQueue();
    final command = h.createChoice(2, revision: 2);
    h.repository.succeedCreation(0, 2, revision: 2, isCompleted: true);
    await command.future;
    await pumpEventQueue();
    h.repository.first(1, [_item(2, completed: true)], total: 1, revision: 2);
    await pumpEventQueue();
    expect(published, isEmpty);
    await _pair(
      h,
      index: 2,
      incomplete: [_item(1)],
      completed: [_item(2, completed: true)],
      revision: 2,
    );
    expect(published, [
      [_choiceId(1), _choiceId(2)],
    ]);
  });

  test(
    'перенос выполнения сохраняет старую пару до полной пересборки',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await _pair(
        h,
        incomplete: [_item(1)],
        completed: [_item(2, completed: true)],
      );
      final update = h.coordinator.acceptDailyChoiceUpdate(
        UpdateDailyChoiceFields(
          choiceId: _choiceId(1),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      ) as DailyChoiceCommandAccepted;
      h.repository.succeedCompletionUpdate(0, 1, revision: 2);
      await update.future;
      await pumpEventQueue();
      expect(_loaded(h).freshness, DailyChoiceCatalogFreshness.refreshing);
      h.repository.first(2, [], total: 0, revision: 2);
      await pumpEventQueue();
      expect(_loaded(h).incomplete.items.single.id, _choiceId(1));
      expect(_loaded(h).completed.items.single.id, _choiceId(2));
      h.repository.first(
        3,
        [_item(1, completed: true), _item(2, completed: true)],
        total: 2,
        revision: 2,
      );
      await pumpEventQueue();
      expect(_loaded(h).incomplete.items, isEmpty);
      expect(_loaded(h).completed.items.map((i) => i.id), [
        _choiceId(1),
        _choiceId(2),
      ]);
    },
  );

  test('пересборка восстанавливает прежний объём каждой секции', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(
      h,
      incomplete: [_item(1)],
      completed: [_item(3, completed: true)],
      more: true,
    );
    final load = h.model.loadMore(isCompleted: false);
    h.repository.more(2, [_item(2)]);
    await load;
    final command = h.createChoice(5, revision: 2);
    h.repository.succeedCreation(0, 5, revision: 2);
    await command.future;
    await pumpEventQueue();
    await _pair(
      h,
      index: 3,
      incomplete: [_item(5)],
      completed: [_item(3, completed: true)],
      more: true,
      revision: 2,
    );
    expect(_loaded(h).incomplete.items, hasLength(2));
    h.repository.more(5, [_item(1)], cursor: _Cursor(), revision: 2);
    await pumpEventQueue();
    expect(_loaded(h).incomplete.items.map((i) => i.id), [
      _choiceId(5),
      _choiceId(1),
    ]);
    expect(_loaded(h).completed.items, hasLength(1));
    expect(h.repository.queries, hasLength(6));
  });

  for (final failure in const [
    DailyChoiceCatalogUnavailableFailure(),
    DailyChoiceCatalogCorruptionFailure(),
    DailyChoiceCatalogUnexpectedFailure(),
  ]) {
    test(
      'отказ ${failure.runtimeType}: повтор только временного отказа и сохранение пары',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.repository.fail(0, failure);
        await pumpEventQueue();
        expect(
          (h.state as DailyChoiceCatalogInitialFailure).canRetry,
          failure is DailyChoiceCatalogUnavailableFailure,
        );
        if (failure is! DailyChoiceCatalogUnavailableFailure) {
          await h.model.retryFirstPage();
          expect(h.repository.queries, hasLength(1));
          return;
        }
        final retry = h.model.retryFirstPage();
        await _pair(
          h,
          index: 1,
          incomplete: [_item(1)],
          completed: [_item(3, completed: true)],
          more: true,
        );
        await retry;
        final load = h.model.loadMore(isCompleted: true);
        h.repository.fail(3, failure);
        await load;
        expect(
          _loaded(h).completed.pageStatus,
          isA<DailyChoiceCatalogPageFailure>(),
        );
        expect(_loaded(h).incomplete.items.single.id, _choiceId(1));
        final more = h.model.retryLoadMore(isCompleted: true);
        h.repository.more(4, [_item(4, completed: true)]);
        await more;
        final command = h.createChoice(2, revision: 2);
        h.repository.succeedCreation(0, 2, revision: 2);
        await command.future;
        await pumpEventQueue();
        h.repository.fail(5, failure);
        await pumpEventQueue();
        expect(_loaded(h).freshness, DailyChoiceCatalogFreshness.stale);
        expect(_loaded(h).totalCount, 4);
        final refresh = h.model.retryRefresh();
        await _pair(
          h,
          index: 6,
          incomplete: [_item(1), _item(2)],
          completed: [_item(3, completed: true), _item(4, completed: true)],
          revision: 2,
        );
        await refresh;
        expect(_loaded(h).freshness, DailyChoiceCatalogFreshness.current);
      },
    );
  }

  test('посторонняя ревизия и устаревшее продолжение пересобирают пару до расширенного объёма', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(h, incomplete: [_item(1)], more: true);
    final command = h.createChoice(9, revision: 2);
    h.repository.succeedUnrelatedCreation(0, 9, revision: 2);
    await command.future;
    await pumpEventQueue();
    expect(h.repository.queries, hasLength(2));
    final load = h.model.loadMore(isCompleted: false);
    expect(h.repository.queries.last.cursor, isNull);
    await _pair(h, index: 2, incomplete: [_item(1)], more: true, revision: 2);
    h.repository.more(4, [_item(2)], revision: 2);
    await load;
    expect(_loaded(h).incomplete.items, hasLength(2));
  });

  for (final lateFailure in [false, true]) {
    test(
      'смена дня сохраняет раскрытие и отбрасывает позднее продолжение: отказ $lateFailure',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await _pair(h, incomplete: [_item(1)], more: true);
        final load = h.model.loadMore(isCompleted: false);
        h.model.toggleSection(false);
        h.model.toggleSection(true);
        final next = CalendarDate.fromParts(2026, 9, 25);
        h.model.selectDate(next);
        expect(h.state, isA<DailyChoiceCatalogInitialLoad>());
        expect(h.state.selection.incompleteExpanded, isFalse);
        expect(h.state.selection.completedExpanded, isTrue);
        h.repository.first(3, [], total: 0);
        await pumpEventQueue();
        h.repository.first(4, [
          _item(5, date: next, completed: true),
        ], total: 1);
        await pumpEventQueue();
        if (lateFailure) {
          h.repository.fail(2, const DailyChoiceCatalogSnapshotExpired());
        } else {
          h.repository.more(2, [_item(2)]);
        }
        await load;
        expect(h.state.selection.date, next);
        expect(_loaded(h).items.single.id, _choiceId(5));
        expect(h.repository.queries, hasLength(5));
      },
    );
  }

  test(
    'переименование участника обновляет пару, перестроение сохраняет раскрытие',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      await _pair(h, incomplete: [_item(1)]);
      h.model.toggleSection(false);
      h.model.toggleSection(true);
      final command = h.coordinator.acceptExisting(
        UpdateIntention(
          id: _intentionId(1),
          title: 'Новое основание',
          description: null,
        ),
        presentationTitle: 'Основание',
      ) as IntentionCommandAccepted;
      h.repository.succeedRename(1, revision: 2);
      await command.future;
      await pumpEventQueue();
      await _pair(
        h,
        index: 2,
        incomplete: [_item(1, title: 'Новое основание')],
        revision: 2,
      );
      expect(_loaded(h).items.single.source.title, 'Новое основание');
      h.container.invalidate(h.provider);
      expect(h.state.selection.incompleteExpanded, isFalse);
      expect(h.state.selection.completedExpanded, isTrue);
    },
  );
}

DailyChoiceCatalogLoaded _loaded(_Harness h) =>
    h.state as DailyChoiceCatalogLoaded;

Future<void> _pair(
  _Harness h, {
  int index = 0,
  List<DailyChoiceCatalogItem> incomplete = const [],
  List<DailyChoiceCatalogItem> completed = const [],
  bool more = false,
  int revision = 1,
}) async {
  h.repository.first(
    index,
    incomplete,
    total: incomplete.length + (more ? 1 : 0),
    cursor: more ? _Cursor() : null,
    revision: revision,
  );
  await pumpEventQueue();
  h.repository.first(
    index + 1,
    completed,
    total: completed.length + (more && completed.isNotEmpty ? 1 : 0),
    cursor: more && completed.isNotEmpty ? _Cursor() : null,
    revision: revision,
  );
  await pumpEventQueue();
}

final class _Harness {
  _Harness({CalendarDate? initialDate})
    : instance = DailyChoiceCatalogInstance(
        initialDate: initialDate ?? _today,
      ) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        localDate.override,
      ],
    );
    subscription = container.listen(provider, (_, _) {});
  }

  final _Repository repository = _Repository();
  final DailyChoiceCatalogInstance instance;
  DailyChoiceCatalogViewModelProvider get provider =>
      dailyChoiceCatalogViewModelProvider(instance);
  final localDate = ControlledDailyChoiceLocalDate(_today);
  late final ProviderContainer container;
  late final ProviderSubscription<DailyChoiceCatalogState> subscription;
  DailyChoiceCatalogViewModel get model => container.read(provider.notifier);
  DailyChoiceCatalogState get state => container.read(provider);
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
          date: _today,
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
  final commands = <DailyChoiceCommand>[];
  final _intentionCommands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];
  final _tagCommands = <Completer<TagCommandResult>>[];

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
  }) => _pages[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogFirstPage(
        items: items,
        totalCount: total,
        hasTimedChoices: false,
        nextCursor: cursor,
        revision: _Revision(revision),
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

  void failCommand(int index, DailyChoiceCommandFailure failure) =>
      _commands[index].complete(GraphCommandFailed(failure));

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is TagCommand) {
      final request = Completer<TagCommandResult>();
      _tagCommands.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    if (command is UpdateIntention) {
      final request =
          Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>();
      _intentionCommands.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    final request = Completer<DailyChoiceCommandResult>();
    commands.add(command as DailyChoiceCommand);
    _commands.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  void completeTag(int index, TagCommandResult result) =>
      _tagCommands[index].complete(result);

  void succeedCreation(
    int index,
    int id, {
    required int revision,
    bool isCompleted = false,
    CalendarDate? date,
  }) {
    final choice = DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: date ?? _today,
      description: null,
      isCompleted: isCompleted,
    );
    final change = DailyChoiceChange(
      revision: _Revision(revision),
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
      date: _today,
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

  void succeedCompletionUpdate(
    int index,
    int id, {
    required int revision,
    bool completed = true,
  }) => succeedDateUpdate(
    index,
    id,
    _today,
    _today,
    revision: revision,
    completed: completed,
    beforeCompleted: !completed,
  );

  void succeedDateUpdate(
    int index,
    int id,
    CalendarDate beforeDate,
    CalendarDate afterDate, {
    required int revision,
    bool completed = false,
    bool beforeCompleted = false,
  }) {
    DailyChoice choice(CalendarDate date, bool isCompleted) => DailyChoice(
      id: _choiceId(id),
      sourceIntentionId: _intentionId(1),
      selectedIntentionId: _intentionId(2),
      date: date,
      description: null,
      isCompleted: isCompleted,
    );
    final before = choice(beforeDate, beforeCompleted);
    final after = choice(afterDate, completed);
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
      date: _today,
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
  descriptionPreview: null,
  readiness: IntentionReadiness.notReady,
  archiveState: IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

final class _Revision implements GraphRevision {
  const _Revision(this.value);
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

DailyChoiceCatalogItem _item(
  int id, {
  CalendarDate? date,
  bool completed = false,
  String title = 'Основание',
}) => DailyChoiceCatalogItem(
  id: _choiceId(id),
  source: DailyChoiceCatalogParticipant(
    id: _intentionId(1),
    title: title,
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.notReady,
  ),
  selected: DailyChoiceCatalogParticipant(
    id: _intentionId(2),
    title: 'Действие',
    archiveState: IntentionArchiveState.active,
    readiness: IntentionReadiness.ready,
  ),
  date: date ?? _today,
  isCompleted: completed,
  schedule: const DailyChoiceAllDay(),
  priority: DailyChoicePriority.p4,
  description: null,
  pathIntentionCount: 2,
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
