import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';
import '../../support/schema_v1_fixture.dart';

const _sourceIdValue = '018f0b5d-6b2e-7c80-8000-000000000901';
const _firstNeighborIdValue = '018f0b5d-6b2e-7c80-8000-000000000902';
const _secondNeighborIdValue = '018f0b5d-6b2e-7c80-8000-000000000903';
const _unrelatedIdValue = '018f0b5d-6b2e-7c80-8000-000000000904';
const _firstRelationIdValue = '018f0b5d-6b2e-7c80-8000-000000000951';
const _secondRelationIdValue = '018f0b5d-6b2e-7c80-8000-000000000952';
const _unrelatedRelationIdValue = '018f0b5d-6b2e-7c80-8000-000000000953';
const _workerRelationIdValue = '018f0b5d-6b2e-7c80-8000-000000000954';

const _workerOperationEnvironment = 'DOABLE_GRAPH_OPERATION';
const _workerStopPointEnvironment = 'DOABLE_GRAPH_STOP_POINT';
const _workerDatabasePathEnvironment = 'DOABLE_GRAPH_DATABASE_PATH';
const _workerStartedMarker = 'DOABLE_GRAPH_WORKER_STARTED';
const _workerReadyMarker = 'DOABLE_GRAPH_WORKER_READY';

final _sourceId = _intentionId(_sourceIdValue);
final _firstNeighborId = _intentionId(_firstNeighborIdValue);
final _secondNeighborId = _intentionId(_secondNeighborIdValue);
final _unrelatedId = _intentionId(_unrelatedIdValue);
final _firstRelationId = _relationId(_firstRelationIdValue);
final _secondRelationId = _relationId(_secondRelationIdValue);
final _unrelatedRelationId = _relationId(_unrelatedRelationIdValue);
final _workerRelationId = _relationId(_workerRelationIdValue);

void main() {
  test('сохраняет создание и порядок после повторного открытия при переводе часов назад', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);

    var database = await harness.openReadyDatabase();
    await _insertIntention(database, _sourceId, title: 'Изучать язык');
    await _insertIntention(database, _firstNeighborId, title: 'Читать');
    await _insertIntention(database, _secondNeighborId, title: 'Говорить');
    final firstClock = _RecordingClock(DateTime.utc(2026, 9, 20, 12));
    final firstRepository = _repository(database, [
      _firstRelationId,
    ], now: firstClock.call);

    expect(
      await firstRepository.execute(
        _createCommand(
          relatedId: _firstNeighborId,
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: '  Читать каждый день\n',
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(firstClock.readCount, 0);
    await harness.closePersistenceObjectGraph();

    database = await harness.openReadyDatabase();
    final earlierClock = _RecordingClock(DateTime.utc(2026, 9, 19, 12));
    final secondRepository = _repository(database, [
      _secondRelationId,
    ], now: earlierClock.call);
    expect(
      await secondRepository.execute(
        _createCommand(
          relatedId: _secondNeighborId,
          type: LongTermRelationType.can,
          priority: RelationPriority.p2,
          description: null,
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(earlierClock.readCount, 0);
    await harness.closePersistenceObjectGraph();

    database = await harness.openReadyDatabase();
    expect(await _relationRows(database), [
      {
        'creation_sequence': 1,
        'id': _firstRelationIdValue,
        'source_intention_id': _sourceIdValue,
        'related_intention_id': _firstNeighborIdValue,
        'type': 'need',
        'priority': 2,
        'description': '  Читать каждый день\n',
        'is_archived': 0,
      },
      {
        'creation_sequence': 2,
        'id': _secondRelationIdValue,
        'source_intention_id': _sourceIdValue,
        'related_intention_id': _secondNeighborIdValue,
        'type': 'can',
        'priority': 2,
        'description': null,
        'is_archived': 0,
      },
    ]);
    final reopenedRepository = _repository(database, const []);
    final sourceCounts = await _counts(reopenedRepository, _sourceId);
    final firstCounts = await _counts(reopenedRepository, _firstNeighborId);
    final secondCounts = await _counts(reopenedRepository, _secondNeighborId);
    expect(sourceCounts.activeNeedOutgoing, 1);
    expect(sourceCounts.activeCanOutgoing, 1);
    expect(firstCounts.activeNeedIncoming, 1);
    expect(secondCounts.activeCanIncoming, 1);
    await _expectCanonicalConnectionIntegrity(database);
  });

  test(
    'миграция схемы 1 сохраняет намерения и поддерживает долговечный каскад',
    () async {
      final harness = await LocalDatabaseHarness.fileBacked();
      addTearDown(harness.dispose);
      await createSchemaV1Fixture(harness.databaseFile, seed: _seedSchemaV1);

      var database = await harness.openReadyDatabase();
      expect(
        (await _intentionRows(database))
            .singleWhere((row) => row['id'] == _unrelatedIdValue),
        <String, Object?>{
          'id': _unrelatedIdValue,
          'title': 'Архивное намерение',
          'description': '  Сохранённый текст  ',
          'is_action_ready': 1,
          'is_archived': 1,
          'created_at': 1704067200000000,
          'updated_at': 1704153600000000,
        },
      );
      final repository = _repository(database, [
        _firstRelationId,
        _secondRelationId,
      ]);
      expect(
        await repository.execute(
          _createCommand(
            relatedId: _firstNeighborId,
            type: LongTermRelationType.need,
            priority: RelationPriority.p1,
            description: 'Нужная связь',
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(
          _createCommand(
            relatedId: _secondNeighborId,
            type: LongTermRelationType.can,
            priority: RelationPriority.p4,
            description: 'Возможная связь',
          ),
        ),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(ArchiveIntention(_sourceId)),
        isA<ResultSuccess>(),
      );
      await harness.closePersistenceObjectGraph();

      database = await harness.openReadyDatabase();
      expect(await _relationRows(database), [
        {
          'creation_sequence': 1,
          'id': _firstRelationIdValue,
          'source_intention_id': _sourceIdValue,
          'related_intention_id': _firstNeighborIdValue,
          'type': 'need',
          'priority': 1,
          'description': 'Нужная связь',
          'is_archived': 1,
        },
        {
          'creation_sequence': 2,
          'id': _secondRelationIdValue,
          'source_intention_id': _sourceIdValue,
          'related_intention_id': _secondNeighborIdValue,
          'type': 'can',
          'priority': 4,
          'description': 'Возможная связь',
          'is_archived': 1,
        },
      ]);
      final intentions = await _intentionRows(database);
      expect(
        intentions.singleWhere((row) => row['id'] == _sourceIdValue),
        containsPair('is_archived', 1),
      );
      expect(
        intentions.singleWhere((row) => row['id'] == _firstNeighborIdValue),
        containsPair('is_archived', 0),
      );
      expect(
        intentions.singleWhere((row) => row['id'] == _secondNeighborIdValue),
        containsPair('is_archived', 0),
      );
      expect(
        intentions.singleWhere((row) => row['id'] == _unrelatedIdValue),
        <String, Object?>{
          'id': _unrelatedIdValue,
          'title': 'Архивное намерение',
          'description': '  Сохранённый текст  ',
          'is_action_ready': 1,
          'is_archived': 1,
          'created_at': 1704067200000000,
          'updated_at': 1704153600000000,
        },
      );
      final reopenedRepository = _repository(database, const []);
      final sourceCounts = await _counts(reopenedRepository, _sourceId);
      expect(sourceCounts.active, 0);
      expect(sourceCounts.archivedNeedOutgoing, 1);
      expect(sourceCounts.archivedCanOutgoing, 1);
      await _expectCanonicalConnectionIntegrity(database);
    },
  );

  test('исключение внутри транзакции откатывает файловое создание', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final observer = _FailAfterSqlObserver(
      operation: LocalDatabaseSqlOperation.insert,
      sqlFragment: 'long_term_relations',
    );
    var database = await harness.openReadyDatabase(observer: observer);
    await _insertIntention(database, _sourceId, title: 'Изучать язык');
    await _insertIntention(database, _firstNeighborId, title: 'Читать');
    final repository = _repository(database, [_firstRelationId]);
    observer.arm();

    expect(
      await repository.execute(
        _createCommand(
          relatedId: _firstNeighborId,
          type: LongTermRelationType.need,
          priority: RelationPriority.p2,
          description: 'Не должно сохраниться',
        ),
      ),
      isA<GraphCommandFailed>(),
    );
    expect(observer.didFail, isTrue);
    await harness.closePersistenceObjectGraph();

    database = await harness.openReadyDatabase();
    expect(await _relationRows(database), isEmpty);
    expect(
      (await _counts(_repository(database, const []), _sourceId)).total,
      0,
    );
    await _expectCanonicalConnectionIntegrity(database);
  });

  test('исключение внутри транзакции откатывает файловый каскад', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    final observer = _FailAfterSqlObserver(
      operation: LocalDatabaseSqlOperation.update,
      sqlFragment: 'UPDATE long_term_relations',
    );
    var database = await harness.openReadyDatabase(observer: observer);
    await _seedCascade(database);
    final repository = _repository(database, const []);
    observer.arm();

    expect(
      await repository.execute(ArchiveIntention(_sourceId)),
      isA<ResultFailure>(),
    );
    expect(observer.didFail, isTrue);
    await harness.closePersistenceObjectGraph();

    database = await harness.openReadyDatabase();
    await _expectCascadeState(database, committed: false);
    await _expectCanonicalConnectionIntegrity(database);
  });

  for (final installation in _LifecycleInstallation.values) {
    test(
      'полный жизненный цикл сохраняется ${installation.testDescription}',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        if (installation == _LifecycleInstallation.migrated) {
          await createSchemaV1Fixture(
            harness.databaseFile,
            seed: _seedSchemaV1,
          );
        }

        var database = await harness.openReadyDatabase();
        if (installation == _LifecycleInstallation.fresh) {
          await _insertIntention(database, _sourceId, title: 'Изучать язык');
          await _insertIntention(database, _firstNeighborId, title: 'Читать');
          await _insertIntention(
            database,
            _secondNeighborId,
            title: 'Говорить',
          );
          await _insertIntention(database, _unrelatedId, title: 'Отдыхать');
        }
        final intentionsBefore = await _intentionRows(database);
        var repository = _repository(database, [
          _unrelatedRelationId,
          _firstRelationId,
          _secondRelationId,
        ]);
        expect(
          await repository.execute(
            _createRelationCommand(
              sourceId: _firstNeighborId,
              relatedId: _secondNeighborId,
              type: LongTermRelationType.can,
              priority: RelationPriority.p3,
              description: 'Независимая связь',
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        expect(
          await repository.execute(
            _createCommand(
              relatedId: _firstNeighborId,
              type: LongTermRelationType.need,
              priority: RelationPriority.p2,
              description: 'Исходное описание',
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        expect(
          await repository.execute(
            _createCommand(
              relatedId: _secondNeighborId,
              type: LongTermRelationType.need,
              priority: RelationPriority.p2,
              description: null,
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        repository = _repository(database, const []);
        expect(
          await repository.execute(
            UpdateLongTermRelation(
              relationId: _firstRelationId,
              patch: LongTermRelationPatch(
                sourceIntentionId: LongTermRelationFieldSet(_firstNeighborId),
                relatedIntentionId: LongTermRelationFieldSet(_sourceId),
                type: const LongTermRelationFieldSet(LongTermRelationType.can),
                priority: const LongTermRelationFieldSet(RelationPriority.p4),
                description: LongTermRelationDescriptionReplaced(
                  LongTermRelationDescription.fromInput(
                    '  Изменённое описание\n',
                  )!,
                ),
              ),
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        expect(
          (await _relationRows(database))
              .singleWhere((row) => row['id'] == _firstRelationIdValue),
          <String, Object?>{
            'creation_sequence': 2,
            'id': _firstRelationIdValue,
            'source_intention_id': _firstNeighborIdValue,
            'related_intention_id': _sourceIdValue,
            'type': 'can',
            'priority': 4,
            'description': '  Изменённое описание\n',
            'is_archived': 0,
          },
        );
        repository = _repository(database, const []);
        expect(
          await repository.execute(
            UpdateLongTermRelation(
              relationId: _firstRelationId,
              patch: LongTermRelationPatch(
                sourceIntentionId: LongTermRelationFieldSet(_sourceId),
                relatedIntentionId: LongTermRelationFieldSet(_firstNeighborId),
                type: const LongTermRelationFieldSet(LongTermRelationType.need),
                priority: const LongTermRelationFieldSet(RelationPriority.p2),
              ),
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        repository = _repository(database, const []);
        final orderedGroup = await repository.getRelationGroupPage(
          RelationGroupQuery(
            intentionId: _sourceId,
            type: LongTermRelationType.need,
            direction: RelationDirection.outgoing,
            scope: RelationScope.active,
            pageSize: 10,
          ),
        );
        expect(orderedGroup, isA<RelationGroupPageSuccess>());
        expect(
          (orderedGroup as RelationGroupPageSuccess).value.items.map(
            (item) => item.relation.id,
          ),
          [_firstRelationId, _secondRelationId],
        );
        expect(
          await repository.execute(ArchiveLongTermRelation(_firstRelationId)),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        expect(
          (await _relationRows(database))
              .singleWhere((row) => row['id'] == _firstRelationIdValue),
          containsPair('is_archived', 1),
        );
        repository = _repository(database, const []);
        expect(
          await repository.execute(RestoreLongTermRelation(_firstRelationId)),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        expect(
          (await _relationRows(database))
              .singleWhere((row) => row['id'] == _firstRelationIdValue),
          containsPair('is_archived', 0),
        );
        repository = _repository(database, const []);
        expect(
          await repository.execute(DeleteLongTermRelation(_firstRelationId)),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        expect(
          (await _relationRows(database))
              .where((row) => row['id'] == _firstRelationIdValue),
          isEmpty,
        );
        repository = _repository(database, const []);
        expect(
          await repository.execute(DeleteLongTermRelation(_secondRelationId)),
          isA<GraphCommandSucceeded>(),
        );
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        final decreasingClock = _RecordingClock(DateTime.utc(2025, 1, 1));
        repository = _repository(database, [
          _workerRelationId,
        ], now: decreasingClock.call);
        expect(
          await repository.execute(
            _createCommand(
              relatedId: _secondNeighborId,
              type: LongTermRelationType.need,
              priority: RelationPriority.p2,
              description: 'Создано заново',
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );
        expect(decreasingClock.readCount, 0);
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        expect(await _relationRows(database), [
          {
            'creation_sequence': 1,
            'id': _unrelatedRelationIdValue,
            'source_intention_id': _firstNeighborIdValue,
            'related_intention_id': _secondNeighborIdValue,
            'type': 'can',
            'priority': 3,
            'description': 'Независимая связь',
            'is_archived': 0,
          },
          {
            'creation_sequence': 4,
            'id': _workerRelationIdValue,
            'source_intention_id': _sourceIdValue,
            'related_intention_id': _secondNeighborIdValue,
            'type': 'need',
            'priority': 2,
            'description': 'Создано заново',
            'is_archived': 0,
          },
        ]);
        expect(_workerRelationId, isNot(_secondRelationId));
        expect(await _intentionRows(database), intentionsBefore);
        await _expectCanonicalConnectionIntegrity(database);
      },
    );
  }

  for (final operation in const [
    _GraphProcessOperation.update,
    _GraphProcessOperation.archive,
    _GraphProcessOperation.restore,
    _GraphProcessOperation.delete,
  ]) {
    test(
      'отказ внутри транзакции ${operation.testDescription} откатывает запись',
      () async {
        final harness = await LocalDatabaseHarness.fileBacked();
        addTearDown(harness.dispose);
        final observer = _FailAfterSqlObserver(
          operation: operation == _GraphProcessOperation.delete
              ? LocalDatabaseSqlOperation.delete
              : LocalDatabaseSqlOperation.update,
          sqlFragment: 'long_term_relations',
        );
        var database = await harness.openReadyDatabase(observer: observer);
        await _seedRelationOperation(
          database,
          archived: operation == _GraphProcessOperation.restore,
        );
        final repository = _repository(database, const []);
        observer.arm();

        expect(
          await repository.execute(_relationOperationCommand(operation)),
          isA<GraphCommandFailed>(),
        );
        expect(observer.didFail, isTrue);
        await harness.closePersistenceObjectGraph();

        database = await harness.openReadyDatabase();
        await _expectRelationOperationState(
          database,
          operation,
          committed: false,
        );
        await _expectCanonicalConnectionIntegrity(database);
      },
    );
  }

  for (final operation in _GraphProcessOperation.values) {
    for (final stopPoint in _GraphProcessStopPoint.values) {
      test(
        'прерывание ${operation.testDescription} ${stopPoint.testDescription} '
        'оставляет целое состояние',
        () async {
          final harness = await LocalDatabaseHarness.fileBacked();
          addTearDown(harness.dispose);
          final database = await harness.openReadyDatabase();
          switch (operation) {
            case _GraphProcessOperation.create:
              await _insertIntention(
                database,
                _sourceId,
                title: 'Изучать язык',
              );
              await _insertIntention(
                database,
                _firstNeighborId,
                title: 'Читать',
              );
            case _GraphProcessOperation.cascade:
              await _seedCascade(database);
            case _GraphProcessOperation.update:
            case _GraphProcessOperation.archive:
            case _GraphProcessOperation.restore:
            case _GraphProcessOperation.delete:
              await _seedRelationOperation(
                database,
                archived: operation == _GraphProcessOperation.restore,
              );
          }
          await harness.closePersistenceObjectGraph();

          await _runGraphWorkerUntilStopPoint(harness, operation, stopPoint);

          final reopenedDatabase = await harness.openReadyDatabase();
          switch (operation) {
            case _GraphProcessOperation.create:
              await _expectCreateState(
                reopenedDatabase,
                committed: stopPoint.isAfterCommit,
              );
            case _GraphProcessOperation.cascade:
              await _expectCascadeState(
                reopenedDatabase,
                committed: stopPoint.isAfterCommit,
              );
            case _GraphProcessOperation.update:
            case _GraphProcessOperation.archive:
            case _GraphProcessOperation.restore:
            case _GraphProcessOperation.delete:
              await _expectRelationOperationState(
                reopenedDatabase,
                operation,
                committed: stopPoint.isAfterCommit,
              );
          }
          await _expectCanonicalConnectionIntegrity(reopenedDatabase);
        },
        timeout: Timeout.none,
      );
    }
  }
}

CreateLongTermRelation _createCommand({
  required IntentionId relatedId,
  required LongTermRelationType type,
  required RelationPriority priority,
  required String? description,
}) => _createRelationCommand(
  sourceId: _sourceId,
  relatedId: relatedId,
  type: type,
  priority: priority,
  description: description,
);

CreateLongTermRelation _createRelationCommand({
  required IntentionId sourceId,
  required IntentionId relatedId,
  required LongTermRelationType type,
  required RelationPriority priority,
  required String? description,
}) => CreateLongTermRelation(
  sourceIntentionId: sourceId,
  relatedIntentionId: relatedId,
  type: type,
  priority: priority,
  description: switch (description) {
    null => null,
    final value => LongTermRelationDescription.fromInput(value),
  },
);

PersonalGraphRepository _repository(
  AppDatabase database,
  List<LongTermRelationId> relationIds, {
  DateTime Function()? now,
}) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  now ?? () => DateTime.utc(2026, 9, 20, 12),
  InMemoryDiagnosticsSink(),
  relationIdGenerator: _DeterministicRelationIdGenerator(relationIds),
);

Future<RelationCounts> _counts(
  PersonalGraphRepository repository,
  IntentionId id,
) async {
  final result = await repository.getRelationCounts(id);
  expect(result, isA<ResultSuccess<GraphSnapshot<RelationCounts>>>());
  return (result as ResultSuccess<GraphSnapshot<RelationCounts>>).value.value;
}

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

Future<void> _insertRelation(
  AppDatabase database, {
  required LongTermRelationId id,
  required IntentionId sourceId,
  required IntentionId relatedId,
  LongTermRelationType type = LongTermRelationType.need,
  RelationPriority priority = RelationPriority.p2,
  String? description,
  bool isArchived = false,
}) => database
    .into(database.longTermRelations)
    .insert(
      LongTermRelationsCompanion.insert(
        id: id.toCanonicalString(),
        sourceIntentionId: sourceId.toCanonicalString(),
        relatedIntentionId: relatedId.toCanonicalString(),
        type: type == LongTermRelationType.need ? 'need' : 'can',
        priority: priority.index + 1,
        description: Value(description),
        isArchived: Value(isArchived),
      ),
    );

Future<void> _seedRelationOperation(
  AppDatabase database, {
  required bool archived,
}) async {
  await _insertIntention(database, _sourceId, title: 'Изучать язык');
  await _insertIntention(database, _firstNeighborId, title: 'Читать');
  await _insertIntention(database, _secondNeighborId, title: 'Говорить');
  await _insertIntention(database, _unrelatedId, title: 'Отдыхать');
  await _insertRelation(
    database,
    id: _workerRelationId,
    sourceId: _sourceId,
    relatedId: _firstNeighborId,
    description: 'Исходное описание',
    isArchived: archived,
  );
  await _insertRelation(
    database,
    id: _unrelatedRelationId,
    sourceId: _firstNeighborId,
    relatedId: _secondNeighborId,
    type: LongTermRelationType.can,
  );
}

Future<void> _seedCascade(AppDatabase database) async {
  await _insertIntention(database, _sourceId, title: 'Изучать язык');
  await _insertIntention(database, _firstNeighborId, title: 'Читать');
  await _insertIntention(database, _secondNeighborId, title: 'Говорить');
  await _insertIntention(database, _unrelatedId, title: 'Отдыхать');
  await _insertRelation(
    database,
    id: _firstRelationId,
    sourceId: _sourceId,
    relatedId: _firstNeighborId,
  );
  await _insertRelation(
    database,
    id: _secondRelationId,
    sourceId: _secondNeighborId,
    relatedId: _sourceId,
    type: LongTermRelationType.can,
  );
  await _insertRelation(
    database,
    id: _unrelatedRelationId,
    sourceId: _firstNeighborId,
    relatedId: _unrelatedId,
  );
}

Future<List<Map<String, Object?>>> _relationRows(AppDatabase database) async =>
    [
      for (final row in await database.customSelect('''
        SELECT
          creation_sequence,
          id,
          source_intention_id,
          related_intention_id,
          type,
          priority,
          description,
          is_archived
        FROM long_term_relations
        ORDER BY creation_sequence
      ''').get())
        Map<String, Object?>.from(row.data),
    ];

Future<List<Map<String, Object?>>> _intentionRows(AppDatabase database) async =>
    [
      for (final row in await database.customSelect('''
        SELECT
          id,
          title,
          description,
          is_action_ready,
          is_archived,
          created_at,
          updated_at
        FROM intentions
        ORDER BY id
      ''').get())
        Map<String, Object?>.from(row.data),
    ];

Future<void> _expectCanonicalConnectionIntegrity(AppDatabase database) async {
  final foreignKeys = await database
      .customSelect('PRAGMA foreign_keys')
      .getSingle();
  expect(foreignKeys.read<int>('foreign_keys'), 1);
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
}

Future<void> _expectCreateState(
  AppDatabase database, {
  required bool committed,
}) async {
  final rows = await _relationRows(database);
  if (!committed) {
    expect(rows, isEmpty);
    expect(
      (await _counts(_repository(database, const []), _sourceId)).total,
      0,
    );
    return;
  }

  expect(rows, [
    {
      'creation_sequence': 1,
      'id': _workerRelationIdValue,
      'source_intention_id': _sourceIdValue,
      'related_intention_id': _firstNeighborIdValue,
      'type': 'need',
      'priority': 2,
      'description': 'Создано дочерним процессом',
      'is_archived': 0,
    },
  ]);
  final repository = _repository(database, const []);
  expect((await _counts(repository, _sourceId)).activeNeedOutgoing, 1);
  expect((await _counts(repository, _firstNeighborId)).activeNeedIncoming, 1);
}

Future<void> _expectCascadeState(
  AppDatabase database, {
  required bool committed,
}) async {
  final intentions = await _intentionRows(database);
  expect(
    intentions.singleWhere((row) => row['id'] == _sourceIdValue)['is_archived'],
    committed ? 1 : 0,
  );
  expect(
    intentions
        .where((row) => row['id'] != _sourceIdValue)
        .map((row) => row['is_archived']),
    everyElement(0),
  );
  final relations = await _relationRows(database);
  expect(relations.map((row) => row['id']), [
    _firstRelationIdValue,
    _secondRelationIdValue,
    _unrelatedRelationIdValue,
  ]);
  expect(
    relations.map((row) => row['is_archived']),
    committed ? [1, 1, 0] : [0, 0, 0],
  );

  final sourceCounts = await _counts(
    _repository(database, const []),
    _sourceId,
  );
  expect(sourceCounts.active, committed ? 0 : 2);
  expect(sourceCounts.archived, committed ? 2 : 0);
}

LongTermRelationCommand _relationOperationCommand(
  _GraphProcessOperation operation,
) => switch (operation) {
  _GraphProcessOperation.update => UpdateLongTermRelation(
    relationId: _workerRelationId,
    patch: LongTermRelationPatch(
      sourceIntentionId: LongTermRelationFieldSet(_secondNeighborId),
      relatedIntentionId: LongTermRelationFieldSet(_unrelatedId),
      type: const LongTermRelationFieldSet(LongTermRelationType.can),
      priority: const LongTermRelationFieldSet(RelationPriority.p4),
      description: LongTermRelationDescriptionReplaced(
        LongTermRelationDescription.fromInput('Изменено дочерним процессом')!,
      ),
    ),
  ),
  _GraphProcessOperation.archive => ArchiveLongTermRelation(_workerRelationId),
  _GraphProcessOperation.restore => RestoreLongTermRelation(_workerRelationId),
  _GraphProcessOperation.delete => DeleteLongTermRelation(_workerRelationId),
  _ => throw ArgumentError.value(operation, 'operation'),
};

Future<void> _expectRelationOperationState(
  AppDatabase database,
  _GraphProcessOperation operation, {
  required bool committed,
}) async {
  final relationRows = await _relationRows(database);
  final workerRows = relationRows
      .where((row) => row['id'] == _workerRelationIdValue)
      .toList(growable: false);
  if (operation == _GraphProcessOperation.delete && committed) {
    expect(workerRows, isEmpty);
  } else {
    final row = workerRows.single;
    expect(row['creation_sequence'], 1);
    expect(row['id'], _workerRelationIdValue);
    expect(
      row['source_intention_id'],
      operation == _GraphProcessOperation.update && committed
          ? _secondNeighborIdValue
          : _sourceIdValue,
    );
    expect(
      row['related_intention_id'],
      operation == _GraphProcessOperation.update && committed
          ? _unrelatedIdValue
          : _firstNeighborIdValue,
    );
    expect(
      row['type'],
      operation == _GraphProcessOperation.update && committed ? 'can' : 'need',
    );
    expect(
      row['priority'],
      operation == _GraphProcessOperation.update && committed ? 4 : 2,
    );
    expect(
      row['description'],
      operation == _GraphProcessOperation.update && committed
          ? 'Изменено дочерним процессом'
          : 'Исходное описание',
    );
    final initiallyArchived = operation == _GraphProcessOperation.restore;
    final expectedArchived = switch (operation) {
      _GraphProcessOperation.archive when committed => true,
      _GraphProcessOperation.restore when committed => false,
      _ => initiallyArchived,
    };
    expect(row['is_archived'], expectedArchived ? 1 : 0);
  }

  expect(
    relationRows.singleWhere((row) => row['id'] == _unrelatedRelationIdValue),
    <String, Object?>{
      'creation_sequence': 2,
      'id': _unrelatedRelationIdValue,
      'source_intention_id': _firstNeighborIdValue,
      'related_intention_id': _secondNeighborIdValue,
      'type': 'can',
      'priority': 2,
      'description': null,
      'is_archived': 0,
    },
  );
  expect(
    (await _intentionRows(database)).map((row) => row['is_archived']),
    everyElement(0),
  );

  final repository = _repository(database, const []);
  final workerExists = operation != _GraphProcessOperation.delete || !committed;
  final workerMoved = operation == _GraphProcessOperation.update && committed;
  expect(
    (await _counts(repository, _sourceId)).total,
    workerExists && !workerMoved ? 1 : 0,
  );
  expect(
    (await _counts(repository, _firstNeighborId)).total,
    1 + (workerExists && !workerMoved ? 1 : 0),
  );
  expect(
    (await _counts(repository, _secondNeighborId)).total,
    1 + (workerExists && workerMoved ? 1 : 0),
  );
  expect(
    (await _counts(repository, _unrelatedId)).total,
    workerExists && workerMoved ? 1 : 0,
  );
}

void _seedSchemaV1(sqlite.Database database) {
  database.execute('''
    INSERT INTO intentions (
      id,
      title,
      description,
      is_action_ready,
      is_archived,
      created_at,
      updated_at
    ) VALUES
      (
        '$_sourceIdValue',
        'Изучать язык',
        NULL,
        0,
        0,
        1704067200000000,
        1704067200000000
      ),
      (
        '$_firstNeighborIdValue',
        'Читать',
        NULL,
        0,
        0,
        1704067200000000,
        1704067200000000
      ),
      (
        '$_secondNeighborIdValue',
        'Говорить',
        NULL,
        0,
        0,
        1704067200000000,
        1704067200000000
      ),
      (
        '$_unrelatedIdValue',
        'Архивное намерение',
        '  Сохранённый текст  ',
        1,
        1,
        1704067200000000,
        1704153600000000
      )
  ''');
}

Future<void> _runGraphWorkerUntilStopPoint(
  LocalDatabaseHarness harness,
  _GraphProcessOperation operation,
  _GraphProcessStopPoint stopPoint,
) async {
  final flutterExecutable = _findFlutterExecutable();
  final workerPath = File.fromUri(
    Directory.current.uri.resolve(
      'test/support/graph_operation_process_worker.dart',
    ),
  ).path;
  final process = await Process.start(
    flutterExecutable,
    ['test', '--no-pub', '--reporter', 'compact', workerPath],
    workingDirectory: Directory.current.path,
    environment: {
      _workerOperationEnvironment: operation.environmentValue,
      _workerStopPointEnvironment: stopPoint.environmentValue,
      _workerDatabasePathEnvironment: harness.databaseFile.path,
    },
  );
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  final ready = Completer<int>();
  final startedPidPattern = RegExp('$_workerStartedMarker:(\\d+)');
  final readyPidPattern = RegExp('$_workerReadyMarker:(\\d+)');
  final stdoutDone = Completer<void>();
  final stderrDone = Completer<void>();
  int? startedWorkerPid;

  process.stdout.transform(utf8.decoder).listen((chunk) {
    stdoutBuffer.write(chunk);
    final output = stdoutBuffer.toString();
    final startedMatch = startedPidPattern.firstMatch(output);
    if (startedMatch != null) {
      startedWorkerPid = int.parse(startedMatch.group(1)!);
    }
    final readyMatch = readyPidPattern.firstMatch(output);
    if (readyMatch != null && !ready.isCompleted) {
      ready.complete(int.parse(readyMatch.group(1)!));
    }
  }, onDone: stdoutDone.complete);
  process.stderr
      .transform(utf8.decoder)
      .listen(stderrBuffer.write, onDone: stderrDone.complete);
  unawaited(
    process.exitCode.then((exitCode) {
      if (!ready.isCompleted) {
        ready.completeError(
          StateError(
            'Процесс операции графа завершился с кодом $exitCode до точки '
            '${stopPoint.environmentValue}.\nstdout:\n$stdoutBuffer\n'
            'stderr:\n$stderrBuffer',
          ),
        );
      }
    }),
  );

  var workerWasKilled = false;
  try {
    final workerPid = await ready.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw TimeoutException(
        'Процесс операции графа не достиг точки '
        '${stopPoint.environmentValue}.\nstdout:\n$stdoutBuffer\n'
        'stderr:\n$stderrBuffer',
      ),
    );
    workerWasKilled = Process.killPid(workerPid, ProcessSignal.sigkill);
    expect(
      workerWasKilled,
      isTrue,
      reason: 'Не удалось принудительно завершить процесс операции графа.',
    );
  } finally {
    if (!workerWasKilled) {
      final workerPid = startedWorkerPid;
      if (workerPid != null) {
        Process.killPid(workerPid, ProcessSignal.sigkill);
      }
      process.kill(ProcessSignal.sigkill);
    }
  }

  final exitCode = await process.exitCode.timeout(const Duration(seconds: 15));
  await Future.wait([stdoutDone.future, stderrDone.future]);
  expect(exitCode, isNot(0));
}

String _findFlutterExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      '${directory.path}/bin/${Platform.isWindows ? 'flutter.bat' : 'flutter'}',
    );
    if (candidate.existsSync()) return candidate.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'Не удалось найти Flutter SDK от Platform.resolvedExecutable.',
      );
    }
    directory = parent;
  }
}

enum _GraphProcessOperation {
  create(environmentValue: 'create', testDescription: 'создания связи'),
  cascade(
    environmentValue: 'cascade',
    testDescription: 'каскадного архивирования',
  ),
  update(environmentValue: 'update', testDescription: 'изменения связи'),
  archive(environmentValue: 'archive', testDescription: 'архивирования связи'),
  restore(environmentValue: 'restore', testDescription: 'восстановления связи'),
  delete(environmentValue: 'delete', testDescription: 'удаления связи');

  const _GraphProcessOperation({
    required this.environmentValue,
    required this.testDescription,
  });

  final String environmentValue;
  final String testDescription;
}

enum _LifecycleInstallation {
  fresh('после создания схемы 2'),
  migrated('после обновления со схемы 1');

  const _LifecycleInstallation(this.testDescription);

  final String testDescription;
}

enum _GraphProcessStopPoint {
  beforeCommit(environmentValue: 'before_commit', testDescription: 'до commit'),
  afterCommit(
    environmentValue: 'after_commit',
    testDescription: 'после commit',
  );

  const _GraphProcessStopPoint({
    required this.environmentValue,
    required this.testDescription,
  });

  final String environmentValue;
  final String testDescription;

  bool get isAfterCommit => this == afterCommit;
}

final class _RecordingClock {
  _RecordingClock(this.value);

  final DateTime value;
  var readCount = 0;

  DateTime call() {
    readCount++;
    return value;
  }
}

final class _DeterministicRelationIdGenerator
    implements LongTermRelationIdGenerator {
  _DeterministicRelationIdGenerator(this._ids);

  final List<LongTermRelationId> _ids;
  var _index = 0;

  @override
  LongTermRelationId generate() => _ids[_index++];
}

final class _FailAfterSqlObserver extends LocalDatabaseConnectionObserver {
  _FailAfterSqlObserver({required this.operation, required this.sqlFragment});

  final LocalDatabaseSqlOperation operation;
  final String sqlFragment;
  var _isArmed = false;
  var didFail = false;

  void arm() => _isArmed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_isArmed || didFail || statement.operation != operation) return;
    if (!statement.statements.any((sql) => sql.contains(sqlFragment))) return;
    didFail = true;
    throw StateError('CANARY-file-backed-transaction-failure');
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
