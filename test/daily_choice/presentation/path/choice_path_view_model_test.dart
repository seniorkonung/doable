import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_state.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_view_model.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  test(
    'нижний обход сохраняет действие и направляет видимый путь к нему',
    () async {
      final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
      addTearDown(harness.dispose);
      expect(harness.state.draft, isA<ChoicePathDraftBottomStart>());
      harness.repository.completePage(0, [_edge(2, 3, 1)]);
      await pumpEventQueue();
      expect(harness.state.confirmedPath, isNull);
      expect(harness.model.selectContinuation(_relation(1)), isTrue);
      harness.repository.completePage(1, [_edge(1, 2, 2)], ready: false);
      await pumpEventQueue();

      final first = harness.state as ChoicePathData;
      expect(first.canConfirm, isTrue);
      expect(first.confirmedPath!.steps.first.sourceIntentionId, _intention(2));
      expect(first.confirmedPath!.steps.last.relatedIntentionId, _intention(3));
      expect(harness.model.selectContinuation(_relation(2)), isTrue);
      harness.repository.completePage(2, [], ready: false);
      await pumpEventQueue();

      final complete = harness.state as ChoicePathEmpty;
      expect(complete.canConfirm, isTrue);
      expect(complete.draft.startingIntentionId, _intention(3));
      expect(complete.visibleSteps.map((step) => step.relation.id), [
        _relation(2),
        _relation(1),
      ]);
      expect(complete.confirmedPath!.steps.map((step) => step.relationId), [
        _relation(2),
        _relation(1),
      ]);
      expect(harness.repository.commandCount, 0);
    },
  );

  test(
    'нижний возврат меняет основание и отбрасывает позднюю порцию',
    () async {
      final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
      addTearDown(harness.dispose);
      harness.repository.completePage(0, [_edge(2, 3, 1)]);
      await pumpEventQueue();
      harness.model.selectContinuation(_relation(1));
      harness.repository.completePage(1, [_edge(1, 2, 2)], cursor: _Cursor());
      await pumpEventQueue();
      final latePage = harness.model.loadMore();
      harness.model.selectContinuation(_relation(2));
      harness.repository.completePage(3, [], ready: false);
      await pumpEventQueue();
      expect(harness.model.backToStep(1), isTrue);
      harness.repository.completePage(4, [_edge(4, 2, 3)]);
      await pumpEventQueue();
      harness.repository.completePage(2, [_edge(5, 1, 4)]);
      await latePage;
      expect(harness.model.selectContinuation(_relation(4)), isFalse);
      expect(harness.model.selectContinuation(_relation(3)), isTrue);
      harness.repository.completePage(5, [], ready: false);
      await pumpEventQueue();

      final choice = harness.state as ChoicePathEmpty;
      expect(choice.visibleSteps.map((step) => step.relation.id), [
        _relation(3),
        _relation(1),
      ]);
      expect(
        choice.confirmedPath!.steps.first.sourceIntentionId,
        _intention(4),
      );
      expect(
        choice.confirmedPath!.steps.last.relatedIntentionId,
        _intention(3),
      );
      expect(harness.model.backToStep(0), isTrue);
      expect(harness.state.draft, isA<ChoicePathDraftBottomStart>());
      expect(harness.state.confirmedPath, isNull);
      expect(harness.state.visibleSteps, isEmpty);
    },
  );

  test(
    'нижний обход отклоняет повтор действия и неверное направление',
    () async {
      final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
      addTearDown(harness.dispose);
      harness.repository.completePage(0, [_edge(3, 2, 1)]);
      await pumpEventQueue();
      expect(harness.state, isA<ChoicePathFailure>());
      expect(harness.model.selectContinuation(_relation(1)), isFalse);

      final refreshed = harness.model.refresh();
      expect(harness.repository.queries, hasLength(1));
      await refreshed;
    },
  );

  test('нижний обход не возвращается к уже посещённому действию', () async {
    final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
    addTearDown(harness.dispose);
    harness.repository.completePage(0, [_edge(2, 3, 1)]);
    await pumpEventQueue();
    harness.model.selectContinuation(_relation(1));
    harness.repository.completePage(1, [_edge(3, 2, 2)]);
    await pumpEventQueue();
    expect(harness.state, isA<ChoicePathFailure>());
    expect(harness.model.selectContinuation(_relation(2)), isFalse);
  });

  test('нижний возврат к началу отбрасывает ожидаемый ответ', () async {
    final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
    addTearDown(harness.dispose);
    harness.repository.completePage(0, [_edge(2, 3, 1)]);
    await pumpEventQueue();
    harness.model.selectContinuation(_relation(1));
    expect(harness.model.backToStep(0), isTrue);
    harness.repository.completePage(2, [_edge(4, 3, 3)]);
    await pumpEventQueue();
    harness.repository.completePage(1, [_edge(1, 2, 2)]);
    await pumpEventQueue();
    expect(harness.state.confirmedPath, isNull);
    expect(harness.model.selectContinuation(_relation(2)), isFalse);
    expect(harness.model.selectContinuation(_relation(3)), isTrue);
  });

  test('нижний обход требует новой основы после изменения графа', () async {
    final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
    addTearDown(harness.dispose);
    harness.repository.completePage(0, [_edge(2, 3, 1)], revision: 1);
    await pumpEventQueue();
    harness.model.selectContinuation(_relation(1));
    harness.repository.completePage(1, [], revision: 1);
    await pumpEventQueue();
    expect(harness.state.confirmedPath, isNotNull);

    harness.repository.emitRevision(2, ready: true);
    await pumpEventQueue();
    expect(harness.state, isA<ChoicePathConflict>());
    expect(harness.state.confirmedPath, isNull);
    final refresh = harness.model.refresh();
    harness.repository.completeFailure(
      2,
      const ChoicePathContinuationSnapshotExpired(),
    );
    await refresh;
    expect(harness.state, isA<ChoicePathConflict>());

    expect(harness.model.backToStep(0), isTrue);
    harness.repository.completePage(3, [
      _edge(4, 3, 2, type: LongTermRelationType.can),
    ], revision: 2);
    await pumpEventQueue();
    expect(harness.model.selectContinuation(_relation(1)), isFalse);
    expect(harness.model.selectContinuation(_relation(2)), isTrue);
    harness.repository.completePage(4, [], revision: 2);
    await pumpEventQueue();
    expect(
      harness.state.confirmedPath!.steps.single.type,
      LongTermRelationType.can,
    );
  });

  test(
    'утрата готовности фиксированного действия запрещает подтверждение',
    () async {
      final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
      addTearDown(harness.dispose);
      harness.repository.completePage(0, [_edge(2, 3, 1)]);
      await pumpEventQueue();
      harness.model.selectContinuation(_relation(1));
      harness.repository.completePage(1, []);
      await pumpEventQueue();
      expect(harness.state.confirmedPath, isNotNull);

      harness.repository.emitRevision(1, ready: false);
      await pumpEventQueue();
      expect(harness.state, isA<ChoicePathConflict>());
      expect(harness.state.confirmedPath, isNull);
    },
  );

  test(
    'нижний обход различает пустое начало, отсутствие и ошибку чтения',
    () async {
      final empty = _Harness(direction: ChoicePathDraftDirection.bottomUp);
      addTearDown(empty.dispose);
      expect(empty.state, isA<ChoicePathLoading>());
      empty.repository.completePage(0, []);
      await pumpEventQueue();
      expect(empty.state, isA<ChoicePathEmpty>());
      expect(empty.state.confirmedPath, isNull);

      final missing = _Harness(direction: ChoicePathDraftDirection.bottomUp);
      addTearDown(missing.dispose);
      missing.repository.completeFailure(
        0,
        const ChoicePathContinuationIntentionNotFoundFailure(),
      );
      await pumpEventQueue();
      expect(missing.state, isA<ChoicePathNotFound>());

      final unavailable = _Harness(
        direction: ChoicePathDraftDirection.bottomUp,
      );
      addTearDown(unavailable.dispose);
      unavailable.repository.completeFailure(
        0,
        const ChoicePathContinuationUnavailableFailure(),
      );
      await pumpEventQueue();
      expect(unavailable.state, isA<ChoicePathFailure>());
      expect((unavailable.state as ChoicePathFailure).canRetry, isTrue);
    },
  );

  test('закрытая нижняя сессия не принимает поздний ответ', () async {
    final harness = _Harness(direction: ChoicePathDraftDirection.bottomUp);
    final repository = harness.repository;
    harness.dispose();
    repository.completePage(0, [_edge(2, 3, 1)]);
    await pumpEventQueue();
    expect(repository.commandCount, 0);
  });

  test(
    'возврат сохраняет префикс и поздний ответ старой ветви не применяется',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      expect(harness.state, isA<ChoicePathLoading>());
      harness.repository.completePage(0, [_edge(1, 2, 1)]);
      await pumpEventQueue();

      expect(harness.model.selectContinuation(_relation(1)), isTrue);
      expect(harness.state.draft.currentIntentionId, _intention(2));
      harness.repository.completePage(1, [_edge(2, 3, 2)]);
      await pumpEventQueue();
      expect(harness.model.selectContinuation(_relation(2)), isTrue);
      expect(harness.state.draft.steps, hasLength(2));

      expect(harness.model.backToStep(1), isTrue);
      expect(harness.state.draft.steps, hasLength(1));
      expect(harness.state.visibleSteps.map((step) => step.relation.id), [
        _relation(1),
      ]);
      harness.repository.completePage(3, [_edge(2, 4, 3)]);
      await pumpEventQueue();
      expect(harness.model.selectContinuation(_relation(3)), isTrue);
      harness.repository.completePage(2, [_edge(3, 5, 4)]);
      await pumpEventQueue();
      expect(harness.state.draft.currentIntentionId, _intention(4));
      harness.repository.completePage(4, [], ready: true);
      await pumpEventQueue();

      final ready = harness.state as ChoicePathEmpty;
      expect(ready.canConfirm, isTrue);
      expect(ready.visibleSteps.map((step) => step.relation.id), [
        _relation(1),
        _relation(3),
      ]);
      expect(ready.confirmedPath!.steps.map((step) => step.relationId), [
        _relation(1),
        _relation(3),
      ]);
      expect(harness.repository.commandCount, 0);
    },
  );

  test(
    'поздняя порция не добавляется после возврата и смены страницы',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final cursor = _Cursor();
      harness.repository.completePage(0, [_edge(1, 2, 1)], cursor: cursor);
      await pumpEventQueue();
      final loading = harness.model.loadMore();
      expect(harness.repository.queries[1].cursor, same(cursor));
      expect(harness.state, isA<ChoicePathData>());

      expect(harness.model.selectContinuation(_relation(1)), isTrue);
      harness.repository.completePage(2, [], ready: true);
      await pumpEventQueue();
      expect(harness.model.backToStep(0), isTrue);
      harness.repository.completePage(3, [_edge(1, 3, 3)]);
      await pumpEventQueue();
      harness.repository.completePage(1, [_edge(1, 4, 2)]);
      await loading;
      expect(harness.model.selectContinuation(_relation(2)), isFalse);
      expect(harness.model.selectContinuation(_relation(3)), isTrue);
    },
  );

  test('новая ревизия запрещает подтверждение и поздний снимок', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.completePage(0, [_edge(1, 2, 1)], revision: 1);
    await pumpEventQueue();
    harness.model.selectContinuation(_relation(1));
    harness.repository.completePage(1, [], ready: true, revision: 1);
    await pumpEventQueue();
    expect((harness.state as ChoicePathEmpty).canConfirm, isTrue);

    harness.repository.emitRevision(2);
    await pumpEventQueue();
    expect(harness.state, isA<ChoicePathConflict>());
    expect(harness.state.confirmedPath, isNull);
    expect(harness.model.selectContinuation(_relation(1)), isFalse);
    final refresh = harness.model.refresh();
    harness.repository.completeFailure(
      2,
      const ChoicePathContinuationSnapshotExpired(),
    );
    await refresh;
    expect(harness.state, isA<ChoicePathConflict>());

    harness.model.backToStep(0);
    harness.repository.completePage(3, [
      _edge(1, 2, 1, type: LongTermRelationType.can),
    ], revision: 2);
    await pumpEventQueue();
    harness.model.selectContinuation(_relation(1));
    harness.repository.completePage(4, [], ready: true, revision: 2);
    await pumpEventQueue();
    expect(
      harness.state.confirmedPath!.steps.single.type,
      LongTermRelationType.can,
    );
  });

  test('ответ старой ревизии не публикуется после изменения графа', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.emitRevision(2);
    await pumpEventQueue();
    harness.repository.completePage(0, [_edge(1, 2, 1)], revision: 1);
    await pumpEventQueue();
    expect(harness.state, isA<ChoicePathConflict>());
    expect(harness.model.selectContinuation(_relation(1)), isFalse);

    final refresh = harness.model.refresh();
    harness.repository.completePage(1, [_edge(1, 3, 2)], revision: 2);
    await refresh;
    expect(harness.model.selectContinuation(_relation(1)), isFalse);
    expect(harness.model.selectContinuation(_relation(2)), isTrue);
  });

  test('достигнутое действие допускает выбор и дальнейший проход', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.completePage(0, [_edge(1, 2, 1)]);
    await pumpEventQueue();
    harness.model.selectContinuation(_relation(1));
    harness.repository.completePage(1, [_edge(2, 3, 2)], ready: true);
    await pumpEventQueue();
    final current = harness.state as ChoicePathData;
    expect(current.canConfirm, isTrue);
    expect(current.confirmedPath!.steps.single.relationId, _relation(1));
    expect(harness.model.selectContinuation(_relation(2)), isTrue);
    expect(harness.state.draft.steps, hasLength(2));
  });

  test(
    'ошибка порции без временной причины не запускает новый запрос',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.completePage(0, [_edge(1, 2, 1)], cursor: _Cursor());
      await pumpEventQueue();
      final load = harness.model.loadMore();
      harness.repository.completeFailure(
        1,
        const ChoicePathContinuationCorruptionFailure(),
      );
      await load;
      expect(
        (harness.state as ChoicePathData).progress,
        isA<ChoicePathPageFailure>(),
      );
      await harness.model.retry();
      await harness.model.refresh();
      expect(harness.repository.queries, hasLength(2));
    },
  );

  test(
    'архивирование префикса и выключение готовности не дают выбрать его',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.completePage(0, [_edge(1, 2, 1)], revision: 1);
      await pumpEventQueue();
      harness.model.selectContinuation(_relation(1));
      harness.repository.completePage(1, [], ready: true, revision: 1);
      await pumpEventQueue();
      harness.repository.emitRevision(2);
      await pumpEventQueue();
      expect(harness.state, isA<ChoicePathConflict>());
      final archived = harness.model.refresh();
      harness.repository.completeFailure(
        2,
        const ChoicePathContinuationSnapshotExpired(),
      );
      await archived;
      expect(harness.state.confirmedPath, isNull);

      harness.model.backToStep(0);
      harness.repository.completePage(3, [_edge(1, 2, 1)], revision: 2);
      await pumpEventQueue();
      harness.model.selectContinuation(_relation(1));
      harness.repository.completePage(4, [], ready: false, revision: 2);
      await pumpEventQueue();
      expect(harness.state, isA<ChoicePathEmpty>());
      expect((harness.state as ChoicePathEmpty).canConfirm, isFalse);
      expect(harness.state.confirmedPath, isNull);
    },
  );

  test(
    'пустое начало, ошибка и обычный повтор имеют разные состояния',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.completePage(0, []);
      await pumpEventQueue();
      expect(harness.state, isA<ChoicePathEmpty>());
      expect(harness.state.confirmedPath, isNull);

      final refresh = harness.model.refresh();
      harness.repository.completeFailure(
        1,
        const ChoicePathContinuationCorruptionFailure(),
      );
      await refresh;
      expect(harness.state, isA<ChoicePathFailure>());
      expect((harness.state as ChoicePathFailure).canRetry, isFalse);
      await harness.model.retry();
      await harness.model.refresh();
      expect(harness.repository.queries, hasLength(2));

      final temporary = _Harness();
      addTearDown(temporary.dispose);
      temporary.repository.completeFailure(
        0,
        const ChoicePathContinuationUnavailableFailure(),
      );
      await pumpEventQueue();
      expect((temporary.state as ChoicePathFailure).canRetry, isTrue);
      final retry = temporary.model.retry();
      temporary.repository.completePage(1, [_edge(1, 2, 1)]);
      await retry;
      expect(temporary.state, isA<ChoicePathData>());
    },
  );
}

final class _Harness {
  _Harness({this.direction = ChoicePathDraftDirection.topDown}) {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (_, _) => null,
    );
    subscription = container.listen(
      choicePathViewModelProvider(
        _intention(direction == ChoicePathDraftDirection.bottomUp ? 3 : 1),
        direction: direction,
      ),
      (_, _) {},
      fireImmediately: true,
    );
  }

  final repository = _Repository();
  final ChoicePathDraftDirection direction;
  late final ProviderContainer container;
  late final ProviderSubscription<ChoicePathState> subscription;

  ChoicePathViewModel get model => container.read(
    choicePathViewModelProvider(
      _intention(direction == ChoicePathDraftDirection.bottomUp ? 3 : 1),
      direction: direction,
    ).notifier,
  );
  ChoicePathState get state => container.read(
    choicePathViewModelProvider(
      _intention(direction == ChoicePathDraftDirection.bottomUp ? 3 : 1),
      direction: direction,
    ),
  );

  void dispose() {
    subscription.close();
    container.dispose();
    repository.dispose();
  }
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final queries = <ChoicePathContinuationQuery>[];
  final _requests = <Completer<ChoicePathContinuationResult>>[];
  final _observations =
      StreamController<Result<GraphSnapshot<IntentionDetails?>>>.broadcast(
        sync: true,
      );
  var commandCount = 0;

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) {
    queries.add(query);
    final request = Completer<ChoicePathContinuationResult>();
    _requests.add(request);
    return request.future;
  }

  void completePage(
    int index,
    List<LongTermRelationSummary> items, {
    int revision = 1,
    bool ready = false,
    ChoicePathContinuationCursor? cursor,
  }) {
    final draft = queries[index].draft;
    _requests[index].complete(
      ChoicePathContinuationSuccess(
        ChoicePathContinuationsPage(
          draft: draft,
          current: _current(draft.currentIntentionId, ready: ready),
          items: items,
          nextCursor: cursor,
          revision: _Revision(revision),
        ),
      ),
    );
  }

  void completeFailure(int index, ChoicePathContinuationFailure failure) {
    _requests[index].complete(ChoicePathContinuationError(failure));
  }

  void emitRevision(int revision, {bool ready = false}) {
    _observations.add(
      ResultSuccess(
        GraphSnapshot(
          value: IntentionDetails(
            intention: _current(observedId, ready: ready),
            relationCounts: RelationCounts(
              activeNeedIncoming: 0,
              activeNeedOutgoing: 0,
              activeCanIncoming: 0,
              activeCanOutgoing: 0,
              archivedNeedIncoming: 0,
              archivedNeedOutgoing: 0,
              archivedCanIncoming: 0,
              archivedCanOutgoing: 0,
            ),
          ),
          revision: _Revision(revision),
        ),
      ),
    );
  }

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) {
    observedId = id;
    return _observations.stream;
  }

  late IntentionId observedId;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) {
    commandCount++;
    throw UnimplementedError();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void dispose() => _observations.close();
}

final class _Cursor implements ChoicePathContinuationCursor {}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is! _Revision
      ? GraphRevisionOrder.differentEpoch
      : switch (value.compareTo(other.value)) {
          < 0 => GraphRevisionOrder.older,
          > 0 => GraphRevisionOrder.newer,
          _ => GraphRevisionOrder.same,
        };
}

IntentionId _intention(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

Intention _current(IntentionId id, {bool ready = false}) => Intention(
  id: id,
  title: 'Намерение',
  description: null,
  readiness: ready ? IntentionReadiness.ready : IntentionReadiness.notReady,
  archiveState: IntentionArchiveState.active,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
);

LongTermRelationSummary _edge(
  int source,
  int related,
  int number, {
  LongTermRelationType type = LongTermRelationType.need,
}) => LongTermRelationSummary(
  relation: LongTermRelation(
    id: _relation(number),
    sourceIntentionId: _intention(source),
    relatedIntentionId: _intention(related),
    type: type,
    priority: RelationPriority.p1,
    scope: RelationScope.active,
    creationSequence: RelationCreationSequence(number),
  ),
  source: RelationParticipantSummary(
    id: _intention(source),
    title: 'Исходное',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 1,
  ),
  related: RelationParticipantSummary(
    id: _intention(related),
    title: 'Связанное',
    archiveState: IntentionArchiveState.active,
    activeRelationCount: 0,
  ),
  hasDescription: false,
);
