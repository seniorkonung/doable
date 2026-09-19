import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late IntentionId sourceId;
  late IntentionId relatedId;
  late LongTermRelationId relationId;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    sourceId = _intentionId(_uuid(1));
    relatedId = _intentionId(_uuid(2));
    relationId = _relationId(_uuid(101));
    await _insertIntention(database, sourceId, title: 'Учиться');
    await _insertIntention(database, relatedId, title: 'Учиться');
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 19),
      diagnostics,
      relationIdGenerator: _DeterministicRelationIdGenerator([relationId]),
    );
  });

  tearDown(() => database.close());

  test(
    'создаёт активную связь и публикует абсолютные количества участников',
    () async {
      final sourceBefore = await _storedIntention(database, sourceId);
      final relatedBefore = await _storedIntention(database, relatedId);
      final revisionBefore = (await repository.getRelationCounts(
        sourceId,
      ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.revision;

      final result = await repository.execute(
        CreateLongTermRelation(
          sourceIntentionId: sourceId,
          relatedIntentionId: relatedId,
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: LongTermRelationDescription.fromInput(
            '  Практиковаться ежедневно\n',
          ),
        ),
      );

      expect(result, isA<GraphCommandSucceeded>());
      final confirmed =
          (result
                  as GraphCommandSucceeded<
                    LongTermRelationCommandSuccess,
                    LongTermRelationCommandFailure
                  >)
              .value;
      final created = confirmed.value as LongTermRelationCreated;
      expect(created.relation.id, relationId);
      expect(created.relation.sourceIntentionId, sourceId);
      expect(created.relation.relatedIntentionId, relatedId);
      expect(created.relation.type, LongTermRelationType.need);
      expect(created.relation.priority, RelationPriority.p2);
      expect(created.relation.scope, RelationScope.active);
      expect(created.relation.creationSequence.value, 1);
      expect(created.description?.value, '  Практиковаться ежедневно\n');
      expect(
        revisionBefore.compareTo(confirmed.revision),
        GraphRevisionOrder.older,
      );

      final countChanges = created.changes
          .whereType<IntentionRelationCountsChanged>()
          .toList(growable: false);
      expect(countChanges, hasLength(2));
      expect(
        countChanges
            .singleWhere((change) => change.intentionId == sourceId)
            .counts
            .activeNeedOutgoing,
        1,
      );
      expect(
        countChanges
            .singleWhere((change) => change.intentionId == relatedId)
            .counts
            .activeNeedIncoming,
        1,
      );
      expect(
        created.changes.singleWhereType<LongTermRelationCreatedChange>().id,
        relationId,
      );

      final stored = await database
          .select(database.longTermRelations)
          .getSingle();
      expect(stored.id, relationId.toCanonicalString());
      expect(stored.creationSequence, 1);
      expect(stored.isArchived, isFalse);
      expect(await _storedIntention(database, sourceId), sourceBefore);
      expect(await _storedIntention(database, relatedId), relatedBefore);
      expect(
        diagnostics.events.whereType<LongTermRelationCommandDiagnosticsEvent>(),
        [
          isA<LongTermRelationCommandDiagnosticsEvent>()
              .having(
                (event) => event.commandType,
                'commandType',
                LongTermRelationCommandDiagnosticsType.create,
              )
              .having(
                (event) => event.status,
                'status',
                isA<DiagnosticsSucceeded>(),
              ),
        ],
      );
    },
  );

  test(
    'сохраняет занятой архивную пару и возвращает её идентификатор',
    () async {
      await repository.execute(_createCommand(sourceId, relatedId));
      await (database.update(database.longTermRelations)
            ..where((row) => row.id.equals(relationId.toCanonicalString())))
          .write(const LongTermRelationsCompanion(isArchived: Value(true)));

      final result = await repository.execute(
        _createCommand(sourceId, relatedId, type: LongTermRelationType.can),
      );

      final failure = _relationFailure(result);
      expect(failure, isA<LongTermRelationPairOccupiedFailure>());
      expect(
        (failure as LongTermRelationPairOccupiedFailure).existingRelationId,
        relationId,
      );
      expect(
        await database.select(database.longTermRelations).get(),
        hasLength(1),
      );
      expect(
        diagnostics.events.last,
        isA<LongTermRelationCommandDiagnosticsEvent>().having(
          (event) => (event.status as DiagnosticsFailed).code,
          'failureCode',
          DiagnosticsFailureCode.conflict,
        ),
      );
    },
  );

  test('разрешает встречные связи и цикл через разные намерения', () async {
    final thirdId = _intentionId(_uuid(3));
    await _insertIntention(database, thirdId, title: 'Учиться');
    repository = _repository(database, diagnostics, [
      _relationId(_uuid(101)),
      _relationId(_uuid(102)),
      _relationId(_uuid(103)),
    ]);

    final results = [
      await repository.execute(_createCommand(sourceId, relatedId)),
      await repository.execute(_createCommand(relatedId, sourceId)),
      await repository.execute(_createCommand(relatedId, thirdId)),
    ];

    expect(results, everyElement(isA<GraphCommandSucceeded>()));
    expect(
      await database.select(database.longTermRelations).get(),
      hasLength(3),
    );
    expect(
      (await repository.getRelationCounts(
        relatedId,
      ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.value.active,
      3,
    );
  });

  test('различает отсутствующего и архивного участника по роли', () async {
    final missingId = _intentionId(_uuid(3));
    final archivedId = _intentionId(_uuid(4));
    await _insertIntention(
      database,
      archivedId,
      title: 'Архивное намерение',
      isArchived: true,
    );

    final missing = _relationFailure(
      await repository.execute(_createCommand(missingId, relatedId)),
    );
    final archived = _relationFailure(
      await repository.execute(_createCommand(sourceId, archivedId)),
    );

    expect(
      missing,
      isA<LongTermRelationParticipantNotFoundFailure>()
          .having(
            (failure) => failure.role,
            'role',
            RelationParticipantRole.source,
          )
          .having((failure) => failure.intentionId, 'intentionId', missingId),
    );
    expect(
      archived,
      isA<LongTermRelationParticipantArchivedFailure>()
          .having(
            (failure) => failure.role,
            'role',
            RelationParticipantRole.related,
          )
          .having((failure) => failure.intentionId, 'intentionId', archivedId),
    );
    expect(await database.select(database.longTermRelations).get(), isEmpty);
  });

  test(
    'перечитывает наблюдения участников и не трогает постороннее намерение',
    () async {
      final otherId = _intentionId(_uuid(3));
      await _insertIntention(database, otherId, title: 'Постороннее намерение');
      final sourceEvents = <Result<GraphSnapshot<IntentionDetails?>>>[];
      final relatedEvents = <Result<GraphSnapshot<IntentionDetails?>>>[];
      final otherEvents = <Result<GraphSnapshot<IntentionDetails?>>>[];
      final subscriptions = [
        repository.watchIntention(sourceId).listen(sourceEvents.add),
        repository.watchIntention(relatedId).listen(relatedEvents.add),
        repository.watchIntention(otherId).listen(otherEvents.add),
      ];
      await pumpEventQueue(times: 20);
      expect(
        [sourceEvents.length, relatedEvents.length, otherEvents.length],
        [1, 1, 1],
      );

      final created = _relationCreated(
        await repository.execute(_createCommand(sourceId, relatedId)),
      );
      await pumpEventQueue(times: 20);

      expect(
        [sourceEvents.length, relatedEvents.length, otherEvents.length],
        [2, 2, 1],
      );
      final sourceSnapshot = _detailsSnapshot(sourceEvents.last);
      final relatedSnapshot = _detailsSnapshot(relatedEvents.last);
      expect(sourceSnapshot.value!.relationCounts.activeNeedOutgoing, 1);
      expect(relatedSnapshot.value!.relationCounts.activeNeedIncoming, 1);
      expect(
        sourceSnapshot.revision.compareTo(created.changes.first.revision),
        GraphRevisionOrder.same,
      );
      expect(
        relatedSnapshot.revision.compareTo(created.changes.first.revision),
        GraphRevisionOrder.same,
      );

      await repository.execute(_createCommand(sourceId, relatedId));
      await pumpEventQueue(times: 20);
      expect(
        [sourceEvents.length, relatedEvents.length, otherEvents.length],
        [2, 2, 1],
      );
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    },
  );

  test(
    'конкурентное создание одной пары подтверждает ровно одну связь',
    () async {
      final results = await Future.wait([
        repository.execute(_createCommand(sourceId, relatedId)),
        repository.execute(
          _createCommand(sourceId, relatedId, type: LongTermRelationType.can),
        ),
      ]);

      expect(results.whereType<GraphCommandSucceeded>(), hasLength(1));
      expect(
        results.whereType<GraphCommandFailed>().single.failure,
        isA<LongTermRelationPairOccupiedFailure>(),
      );
      expect(
        await database.select(database.longTermRelations).get(),
        hasLength(1),
      );
    },
  );

  test('создание перед архивированием попадает в атомарный каскад', () async {
    final creation = repository.execute(_createCommand(sourceId, relatedId));
    final archival = repository.execute(ArchiveIntention(sourceId));

    expect(await creation, isA<GraphCommandSucceeded>());
    expect(await archival, isA<ResultSuccess>());
    final stored = await database
        .select(database.longTermRelations)
        .getSingle();
    expect(stored.isArchived, isTrue);
  });

  test('архивирование перед созданием отклоняет архивного участника', () async {
    final archival = repository.execute(ArchiveIntention(sourceId));
    final creation = repository.execute(_createCommand(sourceId, relatedId));

    expect(await archival, isA<ResultSuccess>());
    expect(
      _relationFailure(await creation),
      isA<LongTermRelationParticipantArchivedFailure>(),
    );
    expect(await database.select(database.longTermRelations).get(), isEmpty);
  });

  test(
    'создание перед удалением сохраняет обе сущности и возвращает конфликт',
    () async {
      final creation = repository.execute(_createCommand(sourceId, relatedId));
      final deletion = repository.execute(DeleteIntention(sourceId));

      expect(await creation, isA<GraphCommandSucceeded>());
      expect(
        await deletion,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (result) => result.failure,
              'failure',
              isA<IntentionHasBlockingRelationsFailure>(),
            ),
      );
      expect(await database.select(database.intentions).get(), hasLength(2));
      expect(
        await database.select(database.longTermRelations).get(),
        hasLength(1),
      );
    },
  );

  test(
    'удаление перед созданием возвращает отсутствующего участника',
    () async {
      final deletion = repository.execute(DeleteIntention(sourceId));
      final creation = repository.execute(_createCommand(sourceId, relatedId));

      expect(await deletion, isA<ResultSuccess>());
      expect(
        _relationFailure(await creation),
        isA<LongTermRelationParticipantNotFoundFailure>(),
      );
      expect(await database.select(database.longTermRelations).get(), isEmpty);
    },
  );

  test('ошибка вставки откатывает создание и не продвигает ревизию', () async {
    await repository.execute(_createCommand(sourceId, relatedId));
    final thirdId = _intentionId(_uuid(3));
    final fourthId = _intentionId(_uuid(4));
    await _insertIntention(database, thirdId, title: 'Третье намерение');
    await _insertIntention(database, fourthId, title: 'Четвёртое намерение');
    repository = _repository(database, diagnostics, [relationId]);
    final revisionBefore = (await repository.getRelationCounts(
      thirdId,
    ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.revision;

    final result = await repository.execute(_createCommand(thirdId, fourthId));

    expect(_relationFailure(result), isA<LongTermRelationUnexpectedFailure>());
    expect(
      await database.select(database.longTermRelations).get(),
      hasLength(1),
    );
    final snapshotAfter = (await repository.getRelationCounts(
      thirdId,
    ) as ResultSuccess<GraphSnapshot<RelationCounts>>).value;
    expect(snapshotAfter.value.total, 0);
    expect(
      revisionBefore.compareTo(snapshotAfter.revision),
      GraphRevisionOrder.same,
    );
  });

  test(
    'сбой диагностики после commit не меняет подтверждённый успех',
    () async {
      final throwingDiagnostics = _ThrowingDiagnosticsSink();
      repository = _repository(database, throwingDiagnostics, [relationId]);

      final result = await repository.execute(
        _createCommand(sourceId, relatedId),
      );

      expect(result, isA<GraphCommandSucceeded>());
      expect(
        await database.select(database.longTermRelations).get(),
        hasLength(1),
      );
      expect(
        throwingDiagnostics.attemptedEvents,
        everyElement(isA<LongTermRelationCommandDiagnosticsEvent>()),
      );
    },
  );
}

CreateLongTermRelation _createCommand(
  IntentionId sourceId,
  IntentionId relatedId, {
  LongTermRelationType type = LongTermRelationType.need,
}) => CreateLongTermRelation(
  sourceIntentionId: sourceId,
  relatedIntentionId: relatedId,
  type: type,
  priority: RelationPriority.p2,
  description: null,
);

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
  List<LongTermRelationId> ids,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 19),
  diagnostics,
  relationIdGenerator: _DeterministicRelationIdGenerator(ids),
);

LongTermRelationCreated _relationCreated(LongTermRelationCommandResult result) {
  expect(result, isA<GraphCommandSucceeded>());
  return (result
              as GraphCommandSucceeded<
                LongTermRelationCommandSuccess,
                LongTermRelationCommandFailure
              >)
          .value
          .value
      as LongTermRelationCreated;
}

LongTermRelationCommandFailure _relationFailure(
  LongTermRelationCommandResult result,
) {
  expect(result, isA<GraphCommandFailed>());
  return (result
          as GraphCommandFailed<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >)
      .failure;
}

GraphSnapshot<IntentionDetails?> _detailsSnapshot(
  Result<GraphSnapshot<IntentionDetails?>> result,
) => (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>).value;

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  required String title,
  bool isArchived = false,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id.toCanonicalString(),
        title: title,
        isArchived: Value(isArchived),
        createdAt: DateTime.utc(2026, 9, 19).microsecondsSinceEpoch,
        updatedAt: DateTime.utc(2026, 9, 19).microsecondsSinceEpoch,
      ),
    );

Future<Map<String, Object?>> _storedIntention(
  AppDatabase database,
  IntentionId id,
) async => Map.unmodifiable(
  (await database
          .customSelect(
            'SELECT * FROM intentions WHERE id = ?',
            variables: [Variable<String>(id.toCanonicalString())],
            readsFrom: {database.intentions},
          )
          .getSingle())
      .data,
);

final class _DeterministicRelationIdGenerator
    implements LongTermRelationIdGenerator {
  _DeterministicRelationIdGenerator(this._ids);

  final List<LongTermRelationId> _ids;
  var _index = 0;

  @override
  LongTermRelationId generate() => _ids[_index++];
}

final class _ThrowingDiagnosticsSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> attemptedEvents = [];

  @override
  void record(DiagnosticsEvent event) {
    attemptedEvents.add(event);
    throw StateError('CANARY-диагностика');
  }
}

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw ArgumentError.value(
        value,
        'value',
      ),
    };

String _uuid(int value) =>
    '018f0b5d-6b2e-7c80-8000-${value.toString().padLeft(12, '0')}';

extension _SingleWhereType on Iterable<GraphChange> {
  T singleWhereType<T extends GraphChange>() => whereType<T>().single;
}
