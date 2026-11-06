import 'dart:async';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/action/domain/action.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/action/presentation/intention_actions/intention_actions_state.dart';
import 'package:doable/src/action/presentation/intention_actions/intention_actions_view_model.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

final _today = CalendarDate.fromParts(2026, 10, 8);

void main() {
  test(
    'до показа вкладки читаются только числа, а строк и курсора нет',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setVisible(false);
      expect(h.state.counts, isNull);

      h.repository.first(0, [_item(1)], counts: _counts(root: 2, total: 2));

      await pumpEventQueue();
      expect(h.state, isA<IntentionActionsHidden>());
      expect(h.state.counts?.root, 2);
      expect(h.repository.queries.single.pageSize, 1);
      expect(h.repository.queries.single.role, IntentionActionRole.root);
    },
  );

  test(
    'первый показ выбирает плитку с наибольшим числом и запоминает её',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setVisible(true);
      expect(h.state, isA<IntentionActionsInitialLoad>());

      h.repository.first(0, [
        _item(1),
      ], counts: _counts(root: 1, intermediate: 3, terminal: 2, total: 6));
      await pumpEventQueue();
      expect(h.repository.queries.last.role, IntentionActionRole.intermediate);
      h.repository.first(1, [
        _item(2),
        _item(3),
        _item(4),
      ], counts: _counts(root: 1, intermediate: 3, terminal: 2, total: 6));
      await pumpEventQueue();

      final loaded = h.state as IntentionActionsLoaded;
      expect(loaded.role, IntentionActionRole.intermediate);
      expect(loaded.items, hasLength(3));
      expect(h.instance.actionsRole, IntentionActionRole.intermediate);
    },
  );

  test('при равенстве чисел открывается первая плитка по порядку', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.setVisible(true);
    h.repository.first(0, [
      _item(1),
    ], counts: _counts(root: 2, intermediate: 2, terminal: 2, total: 4));
    await pumpEventQueue();

    expect((h.state as IntentionActionsLoaded).role, IntentionActionRole.root);
    expect(h.repository.queries, hasLength(1));
  });

  test('выбранная плитка сохраняется при сокрытии и новом показе', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.setVisible(true);
    h.repository.first(0, [_item(1)], counts: _counts(root: 1, total: 1));
    await pumpEventQueue();
    h.model.selectRole(IntentionActionRole.terminal);
    expect(h.state, isA<IntentionActionsInitialLoad>());
    h.repository.first(1, [
      _item(2),
    ], counts: _counts(root: 1, terminal: 1, total: 2));
    await pumpEventQueue();

    h.model.setVisible(false);
    expect(h.state, isA<IntentionActionsHidden>());
    expect(h.state.counts?.terminal, 1);
    h.repository.first(2, [
      _item(2),
    ], counts: _counts(root: 1, terminal: 1, total: 2));
    await pumpEventQueue();
    h.model.setVisible(true);
    h.repository.first(3, [
      _item(2),
    ], counts: _counts(root: 1, terminal: 1, total: 2));
    await pumpEventQueue();

    expect(h.repository.queries[3].role, IntentionActionRole.terminal);
    expect(h.repository.queries[3].cursor, isNull);
    expect(
      h.repository.queries[3].pageSize,
      IntentionActionsQuery.defaultPageSize,
    );
    final loaded = h.state as IntentionActionsLoaded;
    expect(loaded.role, IntentionActionRole.terminal);
  });

  test(
    'подгрузка добавляет порцию, а смена ревизии пересобирает загруженное',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.instance.actionsRole = IntentionActionRole.root;
      h.model.setVisible(true);
      h.repository.first(
        0,
        [_item(1)],
        counts: _counts(root: 3, total: 3),
        cursor: _Cursor(),
      );
      await pumpEventQueue();

      final more = h.model.loadMore();
      expect(
        (h.state as IntentionActionsLoaded).page,
        isA<IntentionActionsPageLoading>(),
      );
      h.repository.more(1, [_item(2)], cursor: _Cursor());
      await more;
      expect((h.state as IntentionActionsLoaded).items.map((i) => i.id), [
        _actionId(1),
        _actionId(2),
      ]);

      final expired = h.model.loadMore();
      h.repository.fail(2, const IntentionActionsSnapshotExpired());
      await pumpEventQueue();
      expect(h.repository.queries[3].cursor, isNull);
      h.repository.first(
        3,
        [_item(1), _item(5)],
        counts: _counts(root: 4, total: 4),
        cursor: _Cursor(),
        revision: 2,
      );
      await pumpEventQueue();
      h.repository.more(4, [_item(2), _item(6)], revision: 2);
      await expired;
      await pumpEventQueue();

      final loaded = h.state as IntentionActionsLoaded;
      expect(loaded.items.map((i) => i.id), [
        _actionId(1),
        _actionId(5),
        _actionId(2),
        _actionId(6),
      ]);
      expect(loaded.counts.root, 4);
    },
  );

  test('отказ подгрузки сохраняет строки и продолжение, повтор читает ту же порцию', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.instance.actionsRole = IntentionActionRole.root;
    h.model.setVisible(true);
    h.repository.first(
      0,
      [_item(1)],
      counts: _counts(root: 2, total: 2),
      cursor: _Cursor(),
    );
    await pumpEventQueue();

    unawaited(h.model.loadMore());
    h.repository.fail(1, const IntentionActionsUnavailableFailure());
    await pumpEventQueue();
    var loaded = h.state as IntentionActionsLoaded;
    expect(loaded.items, hasLength(1));
    expect(loaded.nextCursor, isNotNull);
    expect(
      loaded.page,
      isA<IntentionActionsPageFailure>().having(
        (f) => f.canRetry,
        'canRetry',
        isTrue,
      ),
    );

    unawaited(h.model.retryLoadMore());
    h.repository.more(2, [_item(2)]);
    await pumpEventQueue();
    loaded = h.state as IntentionActionsLoaded;
    expect(loaded.items, hasLength(2));
    expect(loaded.nextCursor, isNull);
  });

  test(
    'отказ первого чтения не выдаётся за пустой список и повторяется',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.instance.actionsRole = IntentionActionRole.root;
      h.model.setVisible(true);
      h.repository.fail(0, const IntentionActionsUnavailableFailure());
      await pumpEventQueue();

      expect(h.state, isA<IntentionActionsInitialFailure>());
      unawaited(h.model.retryFirstPage());
      expect(h.state, isA<IntentionActionsInitialLoad>());
      h.repository.first(1, const [], counts: _counts(total: 0));
      await pumpEventQueue();
      expect((h.state as IntentionActionsLoaded).items, isEmpty);

      final corrupt = _Harness();
      addTearDown(corrupt.dispose);
      corrupt.instance.actionsRole = IntentionActionRole.root;
      corrupt.model.setVisible(true);
      corrupt.repository.fail(0, const IntentionActionsCorruptionFailure());
      await pumpEventQueue();
      final failure = corrupt.state as IntentionActionsInitialFailure;
      expect(failure.canRetry, isFalse);
      expect(corrupt.model.retryFirstPage(), completes);
      expect(corrupt.repository.queries, hasLength(1));
    },
  );

  test(
    'подтверждённое изменение действия пути пересобирает числа и строки',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.instance.actionsRole = IntentionActionRole.root;
      h.model.setVisible(true);
      h.repository.first(0, [
        _item(1),
        _item(2),
      ], counts: _counts(root: 2, total: 2));
      await pumpEventQueue();

      await h.confirmCompletion(1, revision: 2, path: [1, 2]);
      expect(h.repository.queries, hasLength(2));
      final refreshing = h.state as IntentionActionsLoaded;
      expect(refreshing.freshness, isA<IntentionActionsRefreshing>());
      expect(refreshing.items, hasLength(2));

      h.repository.first(
        1,
        [_item(1, completed: true), _item(2)],
        counts: _counts(root: 2, total: 2),
        revision: 2,
      );
      await pumpEventQueue();
      final loaded = h.state as IntentionActionsLoaded;
      expect(loaded.freshness, isA<IntentionActionsCurrent>());
      expect(loaded.items.first.isCompleted, isTrue);
      expect(loaded.role, IntentionActionRole.root);
    },
  );

  test(
    'изменение действия вне путей намерения числа не перечитывает',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.instance.actionsRole = IntentionActionRole.root;
      h.model.setVisible(true);
      h.repository.first(0, [_item(1)], counts: _counts(root: 1, total: 1));
      await pumpEventQueue();

      await h.confirmCompletion(9, revision: 2, path: [5, 6]);

      expect(h.repository.queries, hasLength(1));
      expect(h.state, isA<IntentionActionsLoaded>());
    },
  );

  test(
    'удаление последнего действия оставляет плитку выбранной и пустой',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.instance.actionsRole = IntentionActionRole.terminal;
      h.model.setVisible(true);
      h.repository.first(0, [
        _item(1),
      ], counts: _counts(root: 1, terminal: 1, total: 1));
      await pumpEventQueue();

      await h.confirmDelete(1, revision: 2, path: [1, 2]);
      h.repository.first(1, const [], counts: _counts(total: 0), revision: 2);
      await pumpEventQueue();

      final loaded = h.state as IntentionActionsLoaded;
      expect(loaded.role, IntentionActionRole.terminal);
      expect(loaded.items, isEmpty);
      expect(loaded.counts.total, 0);
    },
  );

  test(
    'без показа подтверждённое изменение пути перечитывает только числа',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.setVisible(false);
      h.repository.first(0, [_item(1)], counts: _counts(root: 1, total: 1));
      await pumpEventQueue();

      await h.confirmCompletion(1, revision: 2, path: [1, 2]);
      expect(h.repository.queries, hasLength(2));
      expect(h.repository.queries.last.pageSize, 1);
      h.repository.first(
        1,
        [_item(1)],
        counts: _counts(root: 1, total: 1),
        revision: 2,
      );
      await pumpEventQueue();

      expect(h.state, isA<IntentionActionsHidden>());
    },
  );

  test('отказ обновления оставляет прежние строки и даёт повтор', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.instance.actionsRole = IntentionActionRole.root;
    h.model.setVisible(true);
    h.repository.first(0, [_item(1)], counts: _counts(root: 1, total: 1));
    await pumpEventQueue();

    await h.confirmCompletion(1, revision: 2, path: [1, 2]);
    h.repository.fail(1, const IntentionActionsUnavailableFailure());
    await pumpEventQueue();
    final stale = h.state as IntentionActionsLoaded;
    expect(stale.items, hasLength(1));
    expect(stale.canRetryRefresh, isTrue);
    expect(stale.freshness, isA<IntentionActionsStale>());

    unawaited(h.model.retryRefresh());
    h.repository.first(
      2,
      [_item(1)],
      counts: _counts(root: 1, total: 1),
      revision: 2,
    );
    await pumpEventQueue();
    expect(
      (h.state as IntentionActionsLoaded).freshness,
      isA<IntentionActionsCurrent>(),
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
    subscription = container.listen(provider, (_, _) {});
  }

  final repository = _Repository();
  final instance = IntentionPageInstance(target: const ActionsTarget());
  late final ProviderContainer container;
  late final ProviderSubscription<IntentionActionsState> subscription;

  IntentionActionsViewModelProvider get provider =>
      intentionActionsViewModelProvider(_intentionId(1), instance);
  IntentionActionsViewModel get model => container.read(provider.notifier);
  IntentionActionsState get state => container.read(provider);
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

  /// Подтверждает выполнение действия [id] с путём из намерений [path].
  Future<void> confirmCompletion(
    int id, {
    required int revision,
    required List<int> path,
  }) async {
    final start = coordinator.acceptActionUpdate(
      UpdateActionFields(
        actionId: _actionId(id),
        patch: ActionFieldsPatch(isCompleted: ActionFieldSet(true)),
      ),
    ) as ActionCommandAccepted;
    final graphRevision = _Revision(revision);
    final before = _action(id, path, false);
    final after = _action(id, path, true);
    repository.completeCommand(
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
    await start.future;
    await pumpEventQueue();
  }

  /// Подтверждает удаление действия [id] с путём из намерений [path].
  Future<void> confirmDelete(
    int id, {
    required int revision,
    required List<int> path,
  }) async {
    final start = coordinator.acceptActionDelete(
      DeleteAction(_actionId(id)),
    ) as ActionCommandAccepted;
    final graphRevision = _Revision(revision);
    final deleted = _action(id, path, false);
    repository.completeCommand(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: graphRevision,
          value: ActionDeleted(
            action: deleted,
            changes: [
              ActionDeletedChange(revision: graphRevision, action: deleted),
            ],
          ),
        ),
      ),
    );
    await start.future;
    await pumpEventQueue();
  }

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final queries = <IntentionActionsQuery>[];
  final _pages = <Completer<IntentionActionsPageResult>>[];
  Completer<ActionCommandResult>? _command;

  @override
  Future<IntentionActionsPageResult> getIntentionActionsPage(
    IntentionActionsQuery query,
  ) {
    queries.add(query);
    final request = Completer<IntentionActionsPageResult>();
    _pages.add(request);
    return request.future;
  }

  void first(
    int index,
    List<ActionListItem> items, {
    required IntentionActionCounts counts,
    IntentionActionsCursor? cursor,
    int revision = 1,
  }) => _pages[index].complete(
    IntentionActionsPageSuccess(
      IntentionActionsFirstPage(
        items: items,
        counts: counts,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );

  void more(
    int index,
    List<ActionListItem> items, {
    IntentionActionsCursor? cursor,
    int revision = 1,
  }) => _pages[index].complete(
    IntentionActionsPageSuccess(
      IntentionActionsContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );

  void fail(int index, IntentionActionsReadFailure failure) =>
      _pages[index].complete(IntentionActionsPageError(failure));

  void completeCommand(ActionCommandResult result) =>
      _command!.complete(result);

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is ActionCommand) {
      _command = Completer<ActionCommandResult>();
      return await _command!.future as GraphCommandResult<TSuccess, TFailure>;
    }
    throw UnsupportedError('Команда не предусмотрена сценарием.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Cursor implements IntentionActionsCursor {}

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

IntentionActionCounts _counts({
  int root = 0,
  int intermediate = 0,
  int terminal = 0,
  int? total,
}) => IntentionActionCounts(
  root: root,
  intermediate: intermediate,
  terminal: terminal,
  total: total ?? root + intermediate + terminal,
);

ActionListItem _item(int id, {bool completed = false}) => ActionListItem(
  id: _actionId(id),
  title: ActionTitle('Действие'),
  description: null,
  date: _today,
  schedule: const ActionAllDay(),
  priority: ActionPriority.p4,
  isCompleted: completed,
  rootIntentionId: _intentionId(1),
  rootTitle: 'Основание',
  pathIntentionCount: 2,
);

Action _action(int id, List<int> path, bool isCompleted) => Action(
  id: _actionId(id),
  title: ActionTitle('Действие'),
  description: null,
  path: ActionPath([for (final number in path) _intentionId(number)]),
  date: _today,
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
