import 'dart:async';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/action/presentation/day/action_day_instance.dart';
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/action/presentation/day/action_day_view_model.dart';
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
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/controlled_local_date.dart';
import '../../../support/intention_title_order_key.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/intention_holding_read_contract_test_fallback.dart';

part 'action_day_completion_scenarios.dart';

final _today = CalendarDate.fromParts(2026, 9, 24);
final _otherDay = CalendarDate.fromParts(2026, 9, 20);
final _anotherDay = CalendarDate.fromParts(2026, 9, 21);

void main() {
  _completionScenarios();

  test('создание действия обновляет список выбранного дня', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(h);
    final action = _action(1, _today, false);
    final start = h.coordinator.acceptActionCreation(
      ActionCreationFormKey(),
      CreateAction(
        title: action.title,
        description: action.description,
        path: action.path,
        date: action.date,
        schedule: action.schedule,
        priority: action.priority,
      ),
    ) as ActionCommandAccepted;
    final revision = _Revision(2);
    h.repository._commands.single.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: revision,
          value: ActionCreated(
            action: action,
            changes: [ActionCreatedChange(revision: revision, action: action)],
          ),
        ),
      ),
    );
    await start.future;
    await pumpEventQueue();
    await _pair(h, index: 2, incomplete: [_item(1)], revision: 2);
    expect(_loaded(h).incomplete.items.single.id, action.id);
  });
  test('первые порции публикуются только согласованной парой; раскрытие не читает граф', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.repository.first(
      0,
      [_item(1)],
      incompleteCount: 2,
      completedCount: 1,
      cursor: _Cursor(),
    );
    await pumpEventQueue();
    expect(h.state, isA<ActionDayInitialLoad>());
    h.repository.first(
      1,
      [_item(2, completed: true)],
      incompleteCount: 2,
      completedCount: 1,
    );
    await pumpEventQueue();
    expect(_loaded(h).incomplete.items.single.id, _actionId(1));
    expect(_loaded(h).completed.items.single.id, _actionId(2));
    expect(_loaded(h).incomplete.totalCount, 2);
    expect(_loaded(h).completed.totalCount, 1);
    expect(_loaded(h).totalCount, 3);
    expect(h.state.selection.isExpanded(ActionDaySection.incomplete), isTrue);
    expect(h.state.selection.isExpanded(ActionDaySection.completed), isTrue);
    h.model.toggleSection(ActionDaySection.incomplete);
    h.model.toggleSection(ActionDaySection.completed);
    expect(h.state.selection.isExpanded(ActionDaySection.incomplete), isFalse);
    expect(h.state.selection.isExpanded(ActionDaySection.completed), isFalse);
    expect(h.repository.queries, hasLength(2));
    expect(h.repository.queries.map((q) => q.section), [
      ActionDaySection.incomplete,
      ActionDaySection.completed,
    ]);
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
      final incomplete = h.model.loadMore(section: ActionDaySection.incomplete);
      final completed = h.model.loadMore(section: ActionDaySection.completed);
      expect(
        _loaded(h).incomplete.pageStatus,
        isA<ActionDayContinuationLoading>(),
      );
      expect(
        _loaded(h).completed.pageStatus,
        isA<ActionDayContinuationLoading>(),
      );
      h.repository.more(3, [_item(4, completed: true)]);
      await completed;
      h.repository.more(2, [_item(2)]);
      await incomplete;
      expect(_loaded(h).incomplete.items.map((i) => i.id), [
        _actionId(1),
        _actionId(2),
      ]);
      expect(_loaded(h).completed.items.map((i) => i.id), [
        _actionId(3),
        _actionId(4),
      ]);
    },
  );

  test('подтверждение между чтениями не публикует смешанную пару', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    final published = <List<ActionId>>[];
    final sub = h.container.listen(h.provider, (_, value) {
      if (value is ActionDayLoaded) {
        published.add(value.items.map((i) => i.id).toList());
      }
    });
    addTearDown(sub.close);
    h.repository.first(0, [_item(1)], incompleteCount: 1, completedCount: 0);
    await pumpEventQueue();
    await h.confirmMove(
      2,
      from: _otherDay,
      to: _today,
      revision: 2,
      completed: true,
    );
    h.repository.first(
      1,
      [_item(2, completed: true)],
      incompleteCount: 1,
      completedCount: 1,
      revision: 2,
    );
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
      [_actionId(1), _actionId(2)],
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
      final update = h.coordinator.acceptActionUpdate(
        UpdateActionFields(
          actionId: _actionId(1),
          patch: ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
        ),
      ) as ActionCommandAccepted;
      h.repository.succeedCompletionUpdate(0, 1, revision: 2);
      await update.future;
      await pumpEventQueue();
      expect(_loaded(h).freshness, ActionDayFreshness.refreshing);
      h.repository.first(
        2,
        [],
        incompleteCount: 0,
        completedCount: 2,
        revision: 2,
      );
      await pumpEventQueue();
      expect(_loaded(h).incomplete.items.single.id, _actionId(1));
      expect(_loaded(h).completed.items.single.id, _actionId(2));
      h.repository.first(
        3,
        [_item(1, completed: true), _item(2, completed: true)],
        incompleteCount: 0,
        completedCount: 2,
        revision: 2,
      );
      await pumpEventQueue();
      expect(_loaded(h).incomplete.items, isEmpty);
      expect(_loaded(h).completed.items.map((i) => i.id), [
        _actionId(1),
        _actionId(2),
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
    final load = h.model.loadMore(section: ActionDaySection.incomplete);
    h.repository.more(2, [_item(2)]);
    await load;
    await h.confirmMove(5, from: _otherDay, to: _today, revision: 2);
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
      _actionId(5),
      _actionId(1),
    ]);
    expect(_loaded(h).completed.items, hasLength(1));
    expect(h.repository.queries, hasLength(6));
  });

  for (final failure in const [
    ActionDayUnavailableFailure(),
    ActionDayCorruptionFailure(),
    ActionDayUnexpectedFailure(),
  ]) {
    test(
      'отказ ${failure.runtimeType}: повтор только временного отказа и сохранение пары',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        h.repository.fail(0, failure);
        await pumpEventQueue();
        expect(
          (h.state as ActionDayInitialFailure).canRetry,
          failure is ActionDayUnavailableFailure,
        );
        if (failure is! ActionDayUnavailableFailure) {
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
        final load = h.model.loadMore(section: ActionDaySection.completed);
        h.repository.fail(3, failure);
        await load;
        expect(
          _loaded(h).completed.pageStatus,
          isA<ActionDayContinuationFailure>(),
        );
        expect(_loaded(h).incomplete.items.single.id, _actionId(1));
        final more = h.model.retryLoadMore(section: ActionDaySection.completed);
        h.repository.more(4, [_item(4, completed: true)]);
        await more;
        await h.confirmMove(2, from: _otherDay, to: _today, revision: 2);
        h.repository.fail(5, failure);
        await pumpEventQueue();
        expect(_loaded(h).freshness, ActionDayFreshness.stale);
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
        expect(_loaded(h).freshness, ActionDayFreshness.current);
      },
    );
  }

  // Изменения, не затрагивающие показанные строки, не перечитывают выдачу, но
  // помечают пару как требующую пересборки перед следующей подгрузкой.
  final foreignChanges = <String, Future<void> Function(_Harness)>{
    'действия другой даты': (h) =>
        h.confirmMove(9, from: _otherDay, to: _anotherDay, revision: 2),
    'чужого корневого намерения': (h) => h.confirmRename(7, revision: 2),
  };
  for (final MapEntry(key: name, value: confirm) in foreignChanges.entries) {
    test(
      'подтверждение изменения $name не перечитывает пару, а продолжение пересобирает её до расширенного объёма',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await _pair(h, incomplete: [_item(1)], more: true);
        await confirm(h);
        expect(h.repository.queries, hasLength(2));
        final load = h.model.loadMore(section: ActionDaySection.incomplete);
        expect(h.repository.queries.last.cursor, isNull);
        await _pair(
          h,
          index: 2,
          incomplete: [_item(1)],
          more: true,
          revision: 2,
        );
        h.repository.more(4, [_item(2)], revision: 2);
        await load;
        expect(_loaded(h).incomplete.items, hasLength(2));
      },
    );
  }

  for (final lateFailure in [false, true]) {
    test(
      'смена дня сохраняет раскрытие и отбрасывает позднее продолжение: отказ $lateFailure',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await _pair(h, incomplete: [_item(1)], more: true);
        final load = h.model.loadMore(section: ActionDaySection.incomplete);
        h.model.toggleSection(ActionDaySection.incomplete);
        h.model.toggleSection(ActionDaySection.completed);
        final next = CalendarDate.fromParts(2026, 9, 25);
        h.model.selectDate(next);
        expect(h.state, isA<ActionDayInitialLoad>());
        expect(
          h.state.selection.isExpanded(ActionDaySection.incomplete),
          isFalse,
        );
        expect(
          h.state.selection.isExpanded(ActionDaySection.completed),
          isFalse,
        );
        h.repository.first(3, [], incompleteCount: 0, completedCount: 1);
        await pumpEventQueue();
        h.repository.first(
          4,
          [_item(5, date: next, completed: true)],
          incompleteCount: 0,
          completedCount: 1,
        );
        await pumpEventQueue();
        if (lateFailure) {
          h.repository.fail(2, const ActionDaySnapshotExpired());
        } else {
          h.repository.more(2, [_item(2)]);
        }
        await load;
        expect(h.state.selection.date, next);
        expect(_loaded(h).items.single.id, _actionId(5));
        expect(h.repository.queries, hasLength(5));
      },
    );
  }

  test('переименование корневого намерения обновляет пару, перестроение сохраняет раскрытие', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    await _pair(h, incomplete: [_item(1)]);
    h.model.toggleSection(ActionDaySection.incomplete);
    h.model.toggleSection(ActionDaySection.completed);
    await h.confirmRename(1, revision: 2);
    await _pair(
      h,
      index: 2,
      incomplete: [_item(1, rootTitle: 'Новое основание')],
      revision: 2,
    );
    expect(_loaded(h).items.single.rootTitle, 'Новое основание');
    h.container.invalidate(h.provider);
    expect(h.state.selection.isExpanded(ActionDaySection.incomplete), isFalse);
    expect(h.state.selection.isExpanded(ActionDaySection.completed), isFalse);
  });
}

ActionDayLoaded _loaded(_Harness h) => h.state as ActionDayLoaded;

/// Отвечает на первые порции обеих секций одной ревизии. Секция с признаком
/// [more] имеет ещё одно действие и продолжение; пустая секция его не имеет.
Future<void> _pair(
  _Harness h, {
  int index = 0,
  List<ActionListItem> incomplete = const [],
  List<ActionListItem> completed = const [],
  bool more = false,
  int revision = 1,
}) async {
  final incompleteCount = incomplete.length + (more ? 1 : 0);
  final completedCount =
      completed.length + (more && completed.isNotEmpty ? 1 : 0);
  h.repository.first(
    index,
    incomplete,
    incompleteCount: incompleteCount,
    completedCount: completedCount,
    cursor: more ? _Cursor() : null,
    revision: revision,
  );
  await pumpEventQueue();
  h.repository.first(
    index + 1,
    completed,
    incompleteCount: incompleteCount,
    completedCount: completedCount,
    cursor: more && completed.isNotEmpty ? _Cursor() : null,
    revision: revision,
  );
  await pumpEventQueue();
}

final class _Harness {
  _Harness({CalendarDate? initialDate})
    : instance = ActionDayInstance(initialDate: initialDate ?? _today) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
        localDate.override,
      ],
    );
    subscription = container.listen(provider, (_, _) {});
  }

  final _Repository repository = _Repository();
  final ActionDayInstance instance;
  ActionDayViewModelProvider get provider =>
      actionDayViewModelProvider(instance);
  final localDate = ControlledLocalDate(_today);
  late final ProviderContainer container;
  late final ProviderSubscription<ActionDayState> subscription;
  ActionDayViewModel get model => container.read(provider.notifier);
  ActionDayState get state => container.read(provider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Подтверждает перенос действия [id] с даты [from] на [to] ревизией
  /// [revision]; [completed] задаёт выполнение после переноса.
  Future<void> confirmMove(
    int id, {
    required CalendarDate from,
    required CalendarDate to,
    required int revision,
    bool completed = false,
  }) async {
    final command = coordinator.acceptActionUpdate(
      UpdateActionFields(
        actionId: _actionId(id),
        patch: ActionFieldsPatch(
          date: ActionFieldSet(to),
          isCompleted: ActionFieldSet(completed),
        ),
      ),
    ) as ActionCommandAccepted;
    repository.succeedUpdate(
      repository.commands.length - 1,
      id,
      revision: revision,
      beforeDate: from,
      afterDate: to,
      afterCompleted: completed,
    );
    await command.future;
    await pumpEventQueue();
  }

  /// Подтверждает переименование намерения [id] ревизией [revision].
  Future<void> confirmRename(int id, {required int revision}) async {
    final command = coordinator.acceptExisting(
      UpdateIntention(
        id: _intentionId(id),
        title: 'Новое основание',
        description: null,
      ),
      presentationTitle: 'Основание',
    ) as IntentionCommandAccepted;
    repository.succeedRename(id, revision: revision);
    await command.future;
    await pumpEventQueue();
  }

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Repository
    with IntentionHoldingReadContractTestFallback, TagReadContractTestFallback
    implements PersonalGraphRepository {
  final queries = <ActionDayQuery>[];
  final _pages = <Completer<ActionDayPageResult>>[];
  final _commands = <Completer<ActionCommandResult>>[];
  final commands = <UpdateActionFields>[];
  final _intentionCommands =
      <Completer<Result<ConfirmedGraphResult<IntentionCommandSuccess>>>>[];

  @override
  Future<ActionDayPageResult> getActionDayPage(ActionDayQuery query) {
    queries.add(query);
    final request = Completer<ActionDayPageResult>();
    _pages.add(request);
    return request.future;
  }

  /// Первая порция любой секции несёт числа обеих секций дня.
  void first(
    int index,
    List<ActionListItem> items, {
    required int incompleteCount,
    required int completedCount,
    ActionDayCursor? cursor,
    int revision = 1,
  }) => _pages[index].complete(
    ActionDayPageSuccess(
      ActionDayFirstPage(
        items: items,
        incompleteCount: incompleteCount,
        completedCount: completedCount,
        hasTimedActions: false,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );
  void more(
    int index,
    List<ActionListItem> items, {
    ActionDayCursor? cursor,
    int revision = 1,
  }) => _pages[index].complete(
    ActionDayPageSuccess(
      ActionDayContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );
  void fail(int index, ActionDayReadFailure failure) =>
      _pages[index].complete(ActionDayPageError(failure));

  void failCommand(int index, ActionCommandFailure failure) =>
      _commands[index].complete(GraphCommandFailed(failure));

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
    if (command is CreateAction) {
      final request = Completer<ActionCommandResult>();
      _commands.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    if (command is UpdateActionFields) {
      final request = Completer<ActionCommandResult>();
      commands.add(command as UpdateActionFields);
      _commands.add(request);
      return await request.future as GraphCommandResult<TSuccess, TFailure>;
    }
    throw UnsupportedError('Команда не предусмотрена сценарием.');
  }

  /// Подтверждает выполнение действия [id]; у него остаётся дата дня.
  void succeedCompletionUpdate(
    int index,
    int id, {
    required int revision,
    bool completed = true,
  }) => succeedUpdate(
    index,
    id,
    revision: revision,
    beforeDate: _today,
    afterDate: _today,
    beforeCompleted: !completed,
    afterCompleted: completed,
  );

  /// Подтверждает изменение действия [id] ревизией [revision] с состоянием
  /// до и после, по которому экран дня находит затронутые строки.
  void succeedUpdate(
    int index,
    int id, {
    required int revision,
    required CalendarDate beforeDate,
    required CalendarDate afterDate,
    bool beforeCompleted = false,
    bool afterCompleted = false,
  }) {
    final before = _action(id, beforeDate, beforeCompleted);
    final after = _action(id, afterDate, afterCompleted);
    final graphRevision = _Revision(revision);
    _commands[index].complete(
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

  /// Подтверждает переименование намерения [id]; новое название — «Новое
  /// основание».
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
    _intentionCommands.last.complete(
      ResultSuccess(
        ConfirmedGraphResult(
          revision: _Revision(revision),
          value: IntentionSaved(intention, catalogMutation: mutation),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Cursor implements ActionDayCursor {}

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
  titleOrderKey: testTitleOrderKey(title),
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

/// Строка действия на [date] с корневым намерением 1 и путём из двух
/// намерений; название корня задаёт [rootTitle].
ActionListItem _item(
  int id, {
  CalendarDate? date,
  bool completed = false,
  String rootTitle = 'Основание',
}) => ActionListItem(
  id: _actionId(id),
  title: ActionTitle('Действие'),
  description: null,
  date: date ?? _today,
  schedule: const ActionAllDay(),
  priority: ActionPriority.p4,
  isCompleted: completed,
  rootIntentionId: _intentionId(1),
  rootTitle: rootTitle,
  pathIntentionCount: 2,
);

/// Полное действие с тем же путём, что у строки [_item].
Action _action(int id, CalendarDate date, bool isCompleted) => Action(
  id: _actionId(id),
  title: ActionTitle('Действие'),
  description: null,
  path: ActionPath([_intentionId(1), _intentionId(2)]),
  date: date,
  schedule: const ActionAllDay(),
  priority: ActionPriority.p4,
  isCompleted: isCompleted,
  creationSequence: ActionCreationSequence(id),
  createdAt: ActionTimestamp(DateTime.utc(2026)),
  updatedAt: ActionTimestamp(DateTime.utc(2026)),
);

IntentionId _intentionId(int value) => switch (IntentionId.decode(
  '018f1200-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Неверный идентификатор фикстуры',
  ),
};

ActionId _actionId(int value) => switch (ActionId.decode(
  '018f1400-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  ActionIdDecodingSuccess(:final id) => id,
  InvalidActionIdDecoding() => throw StateError(
    'Неверный идентификатор фикстуры',
  ),
};
