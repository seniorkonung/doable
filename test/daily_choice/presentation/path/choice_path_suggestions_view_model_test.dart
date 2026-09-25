import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_state.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart'
    as intention_result;
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('пустая выдача, ошибка и временный повтор различимы', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    expect(fixture.model.state, isA<ChoicePathSuggestionsLoading>());
    fixture.complete(0, []);
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsEmpty>());
    fixture.model.refresh();
    fixture.fail(1, const ChoicePathSuggestionsCorruptionFailure());
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsRefreshFailure>());
    fixture.model.retry();
    expect(fixture.repository.queries, hasLength(2));
    fixture.model.select(ChoicePathSuggestionsForAction(_id(2)));
    fixture.fail(2, const ChoicePathSuggestionsUnavailableFailure());
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsLoadFailure>());
    fixture.model.retry();
    expect(fixture.repository.queries, hasLength(4));
  });

  test('смена участника и направления отвергает поздний ответ', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.model.select(ChoicePathSuggestionsForAction(_id(2)));
    fixture.complete(1, [_suggestion(1)], revision: 2);
    await pumpEventQueue();
    fixture.complete(0, [_suggestion(1)], revision: 1);
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsReady>());
    expect(fixture.model.state.query, isA<ChoicePathSuggestionsForAction>());
    expect(fixture.model.confirmable(_choiceId(1)), isNotNull);
    expect(fixture.repository.cancelledWatches, 1);
  });

  test(
    'смена участника при прежнем направлении не принимает старую выдачу',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.model.select(ChoicePathSuggestionsForSource(_id(3)));
      fixture.complete(1, [], revision: 2);
      await pumpEventQueue();
      fixture.complete(0, [_suggestion(1)], revision: 1);
      await pumpEventQueue();
      expect(fixture.model.state, isA<ChoicePathSuggestionsEmpty>());
      expect(fixture.model.state.query.participantId, _id(3));
      expect(fixture.model.confirmable(_choiceId(1)), isNull);
    },
  );

  test('отсутствие участника не становится пустой историей', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.fail(0, const ChoicePathSuggestionsIntentionNotFoundFailure());
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsNotFound>());
  });

  test('изменение графа убирает подтверждение до актуального снимка', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();
    expect(fixture.model.confirmable(_choiceId(1)), isNotNull);

    fixture.revision(2);
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsUpdating>());
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
    fixture.complete(1, [_suggestion(1, archived: true)], revision: 2);
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsReady>());
    expect(
      fixture.model.state.items.single,
      isA<UnavailableChoicePathSuggestion>(),
    );
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
  });

  test(
    'устаревшее чтение и удаление кандидата не возвращают подтверждение',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      fixture.complete(0, [_suggestion(1)]);
      await pumpEventQueue();
      fixture.revision(2);
      fixture.revision(3);
      await pumpEventQueue();
      expect(fixture.repository.queries, hasLength(2));
      fixture.complete(1, [_suggestion(1)], revision: 2);
      await pumpEventQueue();
      expect(fixture.repository.queries, hasLength(3));
      expect(fixture.model.confirmable(_choiceId(1)), isNull);
      fixture.complete(2, [], revision: 3);
      await pumpEventQueue();
      expect(fixture.model.state, isA<ChoicePathSuggestionsEmpty>());
      expect(fixture.model.confirmable(_choiceId(1)), isNull);
    },
  );

  test('частые актуализации оставляют одно ожидающее чтение и отбрасывают старый ответ', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();

    fixture.model.refresh();
    for (var revision = 2; revision <= 100; revision++) {
      fixture.revision(revision);
    }
    expect(fixture.repository.queries, hasLength(2));
    expect(fixture.model.confirmable(_choiceId(1)), isNull);

    fixture.complete(1, [_suggestion(1)], revision: 2);
    await pumpEventQueue();
    expect(fixture.repository.queries, hasLength(3));
    expect(fixture.model.confirmable(_choiceId(1)), isNull);

    fixture.complete(2, [], revision: 100);
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsEmpty>());
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
  });

  test('освобождение модели отменяет наблюдение и игнорирует ответ', () async {
    final fixture = _Fixture();
    final model = fixture.model;
    model.dispose();
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();
    expect(fixture.repository.cancelledWatches, 1);
    expect(fixture.changes.hasListener, isFalse);
    fixture.repository.dispose();
    await fixture.changes.close();
  });

  test('создание, замена и удаление кандидатов актуализируют выдачу', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();

    fixture.change(2, before: null, after: _choice(2));
    expect(fixture.model.state, isA<ChoicePathSuggestionsUpdating>());
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
    fixture.complete(1, [_suggestion(2), _suggestion(1)], revision: 2);
    await pumpEventQueue();

    fixture.change(3, before: _choice(2), after: _choice(2, source: 3));
    expect(fixture.model.state, isA<ChoicePathSuggestionsUpdating>());
    fixture.complete(2, [_suggestion(1)], revision: 3);
    await pumpEventQueue();

    fixture.change(4, before: _choice(1), after: null);
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
    fixture.complete(3, [], revision: 4);
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsEmpty>());
  });

  test('замена пути источника показывает текущую цепочку подсказки', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();
    expect(
      fixture.model.confirmable(_choiceId(1))!.path.single.relation.id,
      _relationId(1),
    );

    fixture.change(2, before: _choice(1), after: _choice(1));
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
    fixture.complete(1, [_suggestion(1, relationNumber: 2)], revision: 2);
    await pumpEventQueue();
    expect(
      fixture.model.confirmable(_choiceId(1))!.path.single.relation.id,
      _relationId(2),
    );
  });

  test('связь маршрута и готовность действия меняют доступность', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();

    fixture.relationChanged(2);
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
    fixture.complete(1, [_suggestion(1, archived: true)], revision: 2);
    await pumpEventQueue();
    expect(
      fixture.model.state.items.single,
      isA<UnavailableChoicePathSuggestion>(),
    );

    fixture.relationChanged(3);
    fixture.complete(2, [_suggestion(1)], revision: 3);
    await pumpEventQueue();
    expect(fixture.model.confirmable(_choiceId(1)), isNotNull);

    fixture.repository.candidateRevision(1, 4);
    expect(fixture.model.confirmable(_choiceId(1)), isNull);
    fixture.complete(3, [_suggestion(1, ready: false)], revision: 4);
    await pumpEventQueue();
    expect(
      (fixture.model.state.items.single as UnavailableChoicePathSuggestion)
          .reason,
      ChoicePathSuggestionUnavailableReason.actionNotReady,
    );
  });

  test('постороннее изменение не перечитывает подсказки', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();
    fixture.change(2, before: null, after: _choice(2, source: 3));
    expect(fixture.repository.queries, hasLength(1));
    expect(fixture.model.confirmable(_choiceId(1)), isNotNull);
  });

  test('смена эпохи исключает прежнюю выдачу', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.complete(0, [_suggestion(1)]);
    await pumpEventQueue();
    fixture.repository.revision(1, epoch: 2);
    expect(fixture.model.state, isA<ChoicePathSuggestionsUpdating>());
    fixture.repository.complete(1, [_suggestion(1)], epoch: 2);
    await pumpEventQueue();
    expect(fixture.model.state, isA<ChoicePathSuggestionsReady>());
    expect(fixture.model.confirmable(_choiceId(1)), isNotNull);
  });
}

final class _Fixture {
  _Fixture() {
    model = ChoicePathSuggestionsViewModel(
      repository,
      changes.stream,
      ChoicePathSuggestionsForSource(_id(1)),
    );
  }

  final _Repository repository = _Repository();
  final StreamController<ConfirmedGraphChangePackage> changes =
      StreamController<ConfirmedGraphChangePackage>.broadcast(sync: true);
  late final ChoicePathSuggestionsViewModel model;

  void complete(
    int index,
    List<ChoicePathSuggestion> items, {
    int revision = 1,
  }) {
    repository.complete(index, items, revision: revision);
  }

  void fail(int index, ChoicePathSuggestionsFailure failure) =>
      repository.fail(index, failure);

  void revision(int value) => repository.revision(value);

  void change(int revision, {DailyChoice? before, DailyChoice? after}) {
    final released = before == null ? <LongTermRelationId>[] : [_relationId(1)];
    final occupied = after == null ? <LongTermRelationId>[] : [_relationId(2)];
    changes.add(
      _Package(_Revision(revision), [
        DailyChoiceChange(
          revision: _Revision(revision),
          before: before,
          after: after,
          releasedRelationIds: released,
          occupiedRelationIds: occupied,
          intentionCounts: {
            for (final id in [_id(1), _id(2), _id(3)]) id: _counts(),
          },
          relationPermissions: {
            for (final id in [...released, ...occupied])
              id: const LongTermRelationPermissions.referencedByDailyPath(),
          },
        ),
      ]),
    );
  }

  void relationChanged(int revision) {
    final before = _details(1).path.single.relation;
    final after = LongTermRelation(
      id: before.id,
      sourceIntentionId: before.sourceIntentionId,
      relatedIntentionId: before.relatedIntentionId,
      type: before.type,
      priority: before.priority,
      scope: RelationScope.archived,
      creationSequence: before.creationSequence,
    );
    changes.add(
      _Package(_Revision(revision), [
        LongTermRelationUpdatedChange(
          revision: _Revision(revision),
          before: before,
          after: after,
        ),
      ]),
    );
  }

  Future<void> dispose() async {
    model.dispose();
    repository.dispose();
    await changes.close();
  }
}

final class _Repository implements PersonalGraphRepository {
  final queries = <ChoicePathSuggestionsQuery>[];
  final requests = <Completer<ChoicePathSuggestionsResult>>[];
  final observations =
      StreamController<
        intention_result.Result<GraphSnapshot<IntentionDetails?>>
      >.broadcast(sync: true);
  final candidates = <DailyChoiceId, StreamController<DailyChoiceReadResult>>{};
  int cancelledWatches = 0;

  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) {
    queries.add(query);
    final request = Completer<ChoicePathSuggestionsResult>();
    requests.add(request);
    return request.future;
  }

  void complete(
    int index,
    List<ChoicePathSuggestion> items, {
    int revision = 1,
    int epoch = 1,
  }) {
    requests[index].complete(
      ChoicePathSuggestionsSuccess(
        ChoicePathSuggestionsSnapshot(
          query: queries[index],
          items: items,
          revision: _Revision(revision, epoch: epoch),
        ),
      ),
    );
  }

  void fail(int index, ChoicePathSuggestionsFailure failure) =>
      requests[index].complete(ChoicePathSuggestionsError(failure));

  void revision(int value, {int epoch = 1}) => observations.add(
    intention_result.ResultSuccess(
      GraphSnapshot(
        value: IntentionDetails(
          intention: _intention(1),
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
        revision: _Revision(value, epoch: epoch),
      ),
    ),
  );

  @override
  Stream<intention_result.Result<GraphSnapshot<IntentionDetails?>>>
  watchIntention(IntentionId id) => observations.stream.asBroadcastStream(
    onCancel: (_) => cancelledWatches++,
  );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) => candidates
      .putIfAbsent(
        id,
        () => StreamController<DailyChoiceReadResult>.broadcast(sync: true),
      )
      .stream;

  void candidateRevision(int choice, int revision) =>
      candidates[_choiceId(choice)]!.add(
        DailyChoiceReadSuccess(
          GraphSnapshot(value: _details(choice), revision: _Revision(revision)),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  void dispose() {
    observations.close();
    for (final controller in candidates.values) {
      controller.close();
    }
  }
}

final class _Package implements ConfirmedGraphChangePackage {
  const _Package(this.revision, this.changes);
  @override
  final GraphRevision revision;
  @override
  final List<GraphChange> changes;
}

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

final class _Revision implements GraphRevision {
  const _Revision(this.value, {this.epoch = 1});
  final int value;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) =>
      other is! _Revision || other.epoch != epoch
      ? GraphRevisionOrder.differentEpoch
      : switch (value.compareTo(other.value)) {
          < 0 => GraphRevisionOrder.older,
          > 0 => GraphRevisionOrder.newer,
          _ => GraphRevisionOrder.same,
        };
}

IntentionId _id(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

DailyChoiceId _choiceId(int value) => (DailyChoiceId.decode(
  '00000000-0000-4000-8002-${value.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

LongTermRelationId _relationId(int value) => (LongTermRelationId.decode(
  '00000000-0000-4000-8001-${value.toString().padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

ChoicePathStepId _stepId(int value) => (ChoicePathStepId.decode(
  '00000000-0000-4000-8003-${value.toString().padLeft(12, '0')}',
) as ChoicePathStepIdDecodingSuccess).id;

Intention _intention(int value, {bool archived = false, bool ready = true}) =>
    Intention(
      id: _id(value),
      title: 'Намерение $value',
      description: null,
      readiness: ready ? IntentionReadiness.ready : IntentionReadiness.notReady,
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
      createdAt: IntentionTimestamp(DateTime.utc(2026)),
      updatedAt: IntentionTimestamp(DateTime.utc(2026)),
    );

DailyChoice _choice(int value, {int source = 1}) => DailyChoice(
  id: _choiceId(value),
  sourceIntentionId: _id(source),
  selectedIntentionId: _id(2),
  date: CalendarDate.fromParts(2026, 9, 25),
  description: null,
  isCompleted: false,
);

ChoicePathSuggestion _suggestion(
  int value, {
  bool archived = false,
  bool ready = true,
  int? relationNumber,
}) => ChoicePathSuggestion.fromDetails(
  _details(
    value,
    archived: archived,
    ready: ready,
    relationNumber: relationNumber,
  ),
);

DailyChoiceDetails _details(
  int value, {
  bool archived = false,
  bool ready = true,
  int? relationNumber,
}) {
  final source = _intention(1);
  final selected = _intention(2, ready: ready);
  final relation = LongTermRelation(
    id: _relationId(relationNumber ?? value),
    sourceIntentionId: source.id,
    relatedIntentionId: selected.id,
    type: LongTermRelationType.need,
    priority: RelationPriority.p1,
    scope: archived ? RelationScope.archived : RelationScope.active,
    creationSequence: RelationCreationSequence(value),
  );
  final choice = _choice(value);
  return DailyChoiceDetails(
    choice: choice,
    source: source,
    selected: selected,
    path: [
      DailyChoicePathStepDetails(
        step: ChoicePathStep(
          id: _stepId(value),
          dailyChoiceId: choice.id,
          relationId: relation.id,
          previousStepId: null,
        ),
        relation: relation,
        description: null,
        source: source,
        related: selected,
      ),
    ],
  );
}
