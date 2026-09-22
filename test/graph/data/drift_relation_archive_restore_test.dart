import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
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
  late IntentionId thirdId;
  late IntentionId fourthId;
  late LongTermRelationId relationId;
  late LongTermRelationId secondRelationId;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    sourceId = _intentionId(_uuid(1));
    relatedId = _intentionId(_uuid(2));
    thirdId = _intentionId(_uuid(3));
    fourthId = _intentionId(_uuid(4));
    relationId = _relationId(_uuid(101));
    secondRelationId = _relationId(_uuid(102));
    for (final entry in <(IntentionId, String)>[
      (sourceId, 'Исходное намерение'),
      (relatedId, 'Связанное намерение'),
      (thirdId, 'Третье намерение'),
      (fourthId, 'Четвёртое намерение'),
    ]) {
      await _insertIntention(database, entry.$1, title: entry.$2);
    }
    repository = _repository(database, diagnostics, [
      relationId,
      secondRelationId,
      _relationId(_uuid(103)),
    ]);
  });

  tearDown(() => database.close());

  test(
    'архивирование меняет только состояние связи и публикует цельный результат',
    () async {
      await _create(repository, sourceId, relatedId);
      await _create(repository, thirdId, fourthId);
      final intentionsBefore = await _storedIntentions(database);
      final otherRelationBefore = await _storedRelation(
        database,
        secondRelationId,
      );
      final events = StreamIterator(repository.watchRelation(relationId));
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);

      final confirmed = _confirmedUpdated(
        await repository.execute(ArchiveLongTermRelation(relationId)),
      );

      expect(confirmed.value.before.scope, RelationScope.active);
      expect(confirmed.value.relation.scope, RelationScope.archived);
      expect(confirmed.value.description?.value, '  Описание\n');
      _expectStableStoredFields(
        await _storedRelation(database, relationId),
        relationId: relationId,
        sourceId: sourceId,
        relatedId: relatedId,
        isArchived: 1,
      );
      expect(
        await _storedRelation(database, secondRelationId),
        otherRelationBefore,
      );
      expect(await _storedIntentions(database), intentionsBefore);

      final changes = confirmed.value.changes;
      expect(changes.map((change) => change.revision).toSet(), {
        confirmed.revision,
      });
      final relationChange = changes
          .whereType<LongTermRelationUpdatedChange>()
          .single;
      expect(relationChange.before.scope, RelationScope.active);
      expect(relationChange.after.scope, RelationScope.archived);
      final countChanges = changes
          .whereType<IntentionRelationCountsChanged>()
          .toList(growable: false);
      expect(countChanges.map((change) => change.intentionId), {
        sourceId,
        relatedId,
      });
      expect(
        countChanges
            .singleWhere((change) => change.intentionId == sourceId)
            .counts,
        isA<RelationCounts>()
            .having((counts) => counts.activeNeedOutgoing, 'активные', 0)
            .having((counts) => counts.archivedNeedOutgoing, 'архивные', 1),
      );
      expect(
        countChanges
            .singleWhere((change) => change.intentionId == relatedId)
            .counts,
        isA<RelationCounts>()
            .having((counts) => counts.activeNeedIncoming, 'активные', 0)
            .having((counts) => counts.archivedNeedIncoming, 'архивные', 1),
      );

      expect(await events.moveNext(), isTrue);
      final details = _relationSnapshot(events.current).value!;
      expect(details.relation.scope, RelationScope.archived);
      expect(details.source.activeRelationCount, 0);
      expect(details.related.activeRelationCount, 0);
    },
  );

  test(
    'восстановление возвращает ту же связь при активных участниках',
    () async {
      await _create(repository, sourceId, relatedId);
      final archived = _confirmedUpdated(
        await repository.execute(ArchiveLongTermRelation(relationId)),
      );

      final restored = _confirmedUpdated(
        await repository.execute(RestoreLongTermRelation(relationId)),
      );

      expect(
        restored.revision.compareTo(archived.revision),
        GraphRevisionOrder.newer,
      );
      expect(restored.value.before.scope, RelationScope.archived);
      expect(restored.value.relation.scope, RelationScope.active);
      expect(restored.value.relation.id, relationId);
      expect(restored.value.relation.creationSequence.value, 1);
      expect(restored.value.relation.type, LongTermRelationType.need);
      expect(restored.value.relation.priority, RelationPriority.p2);
      expect(restored.value.relation.sourceIntentionId, sourceId);
      expect(restored.value.relation.relatedIntentionId, relatedId);
      expect(restored.value.description?.value, '  Описание\n');
      final counts = restored.value.changes
          .whereType<IntentionRelationCountsChanged>()
          .toList(growable: false);
      expect(
        counts
            .singleWhere((change) => change.intentionId == sourceId)
            .counts
            .activeNeedOutgoing,
        1,
      );
      expect(
        counts
            .singleWhere((change) => change.intentionId == relatedId)
            .counts
            .archivedNeedIncoming,
        0,
      );
    },
  );

  test('уже достигнутое состояние не пишет и не продвигает ревизию', () async {
    await _create(repository, sourceId, relatedId);
    await database.customStatement('''
      CREATE TEMP TRIGGER canary_relation_state_write
      BEFORE UPDATE ON long_term_relations
      BEGIN
        SELECT RAISE(ABORT, 'canary relation state write');
      END
    ''');
    final activeRevision = await _revision(repository, sourceId);

    final alreadyActive = _confirmedUpdated(
      await repository.execute(RestoreLongTermRelation(relationId)),
    );

    expect(alreadyActive.value.changes, [
      isA<LongTermRelationUnchangedChange>(),
    ]);
    expect(
      alreadyActive.revision.compareTo(activeRevision),
      GraphRevisionOrder.same,
    );

    await database.customStatement('DROP TRIGGER canary_relation_state_write');
    await repository.execute(ArchiveLongTermRelation(relationId));
    await database.customStatement('''
      CREATE TEMP TRIGGER canary_relation_state_write
      BEFORE UPDATE ON long_term_relations
      BEGIN
        SELECT RAISE(ABORT, 'canary relation state write');
      END
    ''');
    final archivedRevision = await _revision(repository, sourceId);

    final alreadyArchived = _confirmedUpdated(
      await repository.execute(ArchiveLongTermRelation(relationId)),
    );

    expect(alreadyArchived.value.changes, [
      isA<LongTermRelationUnchangedChange>(),
    ]);
    expect(
      alreadyArchived.revision.compareTo(archivedRevision),
      GraphRevisionOrder.same,
    );
  });

  test('отсутствие связи отличается от конфликта участника', () async {
    final missingId = _relationId(_uuid(999));
    final archiveFailure = _failure(
      await repository.execute(ArchiveLongTermRelation(missingId)),
    );
    final restoreFailure = _failure(
      await repository.execute(RestoreLongTermRelation(missingId)),
    );

    expect(
      archiveFailure,
      isA<LongTermRelationNotFoundFailure>().having(
        (failure) => failure.relationId,
        'relationId',
        missingId,
      ),
    );
    expect(restoreFailure, isA<LongTermRelationNotFoundFailure>());

    await _create(repository, sourceId, relatedId);
    await repository.execute(ArchiveIntention(sourceId));
    final participantFailure = _failure(
      await repository.execute(RestoreLongTermRelation(relationId)),
    );
    expect(
      participantFailure,
      isA<LongTermRelationParticipantArchivedFailure>()
          .having(
            (failure) => failure.role,
            'роль',
            RelationParticipantRole.source,
          )
          .having((failure) => failure.intentionId, 'участник', sourceId),
    );
  });

  test(
    'каскад требует восстановить участника раньше связи для обеих ролей',
    () async {
      await _create(repository, sourceId, relatedId);
      await repository.execute(ArchiveIntention(sourceId));

      expect(
        _failure(await repository.execute(RestoreLongTermRelation(relationId))),
        isA<LongTermRelationParticipantArchivedFailure>().having(
          (failure) => failure.role,
          'роль',
          RelationParticipantRole.source,
        ),
      );
      await repository.execute(RestoreIntention(sourceId));
      expect(
        _confirmedUpdated(
          await repository.execute(RestoreLongTermRelation(relationId)),
        ).value.relation.scope,
        RelationScope.active,
      );

      await repository.execute(ArchiveIntention(relatedId));
      await repository.execute(RestoreIntention(relatedId));
      expect(
        _confirmedUpdated(
          await repository.execute(RestoreLongTermRelation(relationId)),
        ).value.relation.scope,
        RelationScope.active,
      );

      await repository.execute(ArchiveLongTermRelation(relationId));
      await repository.execute(ArchiveIntention(relatedId));
      expect(
        _failure(await repository.execute(RestoreLongTermRelation(relationId))),
        isA<LongTermRelationParticipantArchivedFailure>().having(
          (failure) => failure.role,
          'роль',
          RelationParticipantRole.related,
        ),
      );
    },
  );

  test('архивная связь продолжает занимать направленную пару', () async {
    await _create(repository, sourceId, relatedId);
    await repository.execute(ArchiveLongTermRelation(relationId));

    final failure = _failure(
      await repository.execute(_createCommand(sourceId, relatedId)),
    );

    expect(
      failure,
      isA<LongTermRelationPairOccupiedFailure>().having(
        (failure) => failure.existingRelationId,
        'существующая связь',
        relationId,
      ),
    );
    expect((await _storedRelation(database, relationId))['is_archived'], 1);
  });

  test('ошибка записи откатывает состояние и не публикует изменение', () async {
    await _create(repository, sourceId, relatedId);
    final storedBefore = await _storedRelation(database, relationId);
    final revisionBefore = await _revision(repository, sourceId);
    final events = <LongTermRelationReadResult>[];
    final subscription = repository
        .watchRelation(relationId)
        .listen(events.add);
    addTearDown(() {
      unawaited(subscription.cancel());
    });
    await _waitFor(() => events.length == 1);
    await database.customStatement('''
      CREATE TEMP TRIGGER canary_relation_archive_failure
      BEFORE UPDATE ON long_term_relations
      BEGIN
        SELECT RAISE(ABORT, 'canary relation archive failure');
      END
    ''');

    final failure = _failure(
      await repository.execute(ArchiveLongTermRelation(relationId)),
    );
    await pumpEventQueue(times: 10);

    expect(failure, isA<LongTermRelationUnexpectedFailure>());
    expect(await _storedRelation(database, relationId), storedBefore);
    expect(
      (await _revision(repository, sourceId)).compareTo(revisionBefore),
      GraphRevisionOrder.same,
    );
    expect(events, hasLength(1));
  });

  test('диагностика различает архивирование и восстановление', () async {
    await _create(repository, sourceId, relatedId);

    await repository.execute(ArchiveLongTermRelation(relationId));
    await repository.execute(RestoreLongTermRelation(relationId));

    final commandEvents = diagnostics.events
        .whereType<LongTermRelationCommandDiagnosticsEvent>()
        .toList(growable: false);
    expect(
      commandEvents.map((event) => event.commandType),
      containsAllInOrder([
        LongTermRelationCommandDiagnosticsType.create,
        LongTermRelationCommandDiagnosticsType.archive,
        LongTermRelationCommandDiagnosticsType.restore,
      ]),
    );
    expect(
      commandEvents.where(
        (event) =>
            event.commandType ==
                LongTermRelationCommandDiagnosticsType.archive ||
            event.commandType == LongTermRelationCommandDiagnosticsType.restore,
      ),
      everyElement(
        isA<LongTermRelationCommandDiagnosticsEvent>().having(
          (event) => event.status,
          'статус',
          isA<DiagnosticsSucceeded>(),
        ),
      ),
    );
  });

  test('отказ диагностики после commit не меняет архивирование', () async {
    await _create(repository, sourceId, relatedId);
    final throwingDiagnostics = _ThrowingDiagnosticsSink();
    repository = _repository(database, throwingDiagnostics, const []);

    final result = await repository.execute(
      ArchiveLongTermRelation(relationId),
    );

    expect(result, isA<GraphCommandSucceeded>());
    expect((await _storedRelation(database, relationId))['is_archived'], 1);
    expect(
      throwingDiagnostics.attemptedEvents,
      everyElement(
        isA<LongTermRelationCommandDiagnosticsEvent>().having(
          (event) => event.commandType,
          'тип команды',
          LongTermRelationCommandDiagnosticsType.archive,
        ),
      ),
    );
  });
}

Future<LongTermRelationCreated> _create(
  DriftPersonalGraphRepository repository,
  IntentionId sourceId,
  IntentionId relatedId,
) async =>
    _created(await repository.execute(_createCommand(sourceId, relatedId)));

CreateLongTermRelation _createCommand(
  IntentionId sourceId,
  IntentionId relatedId,
) => CreateLongTermRelation(
  sourceIntentionId: sourceId,
  relatedIntentionId: relatedId,
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  description: LongTermRelationDescription.fromInput('  Описание\n'),
);

LongTermRelationCreated _created(LongTermRelationCommandResult result) {
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

ConfirmedGraphResult<LongTermRelationUpdated> _confirmedUpdated(
  LongTermRelationCommandResult result,
) {
  expect(result, isA<GraphCommandSucceeded>());
  final confirmed =
      (result
              as GraphCommandSucceeded<
                LongTermRelationCommandSuccess,
                LongTermRelationCommandFailure
              >)
          .value;
  return ConfirmedGraphResult(
    revision: confirmed.revision,
    value: confirmed.value as LongTermRelationUpdated,
  );
}

LongTermRelationCommandFailure _failure(LongTermRelationCommandResult result) {
  expect(result, isA<GraphCommandFailed>());
  return (result
          as GraphCommandFailed<
            LongTermRelationCommandSuccess,
            LongTermRelationCommandFailure
          >)
      .failure;
}

GraphSnapshot<LongTermRelationDetails?> _relationSnapshot(
  LongTermRelationReadResult result,
) {
  expect(result, isA<LongTermRelationReadSuccess>());
  return (result as LongTermRelationReadSuccess).value;
}

Future<GraphRevision> _revision(
  DriftPersonalGraphRepository repository,
  IntentionId intentionId,
) async => (await repository.getRelationCounts(
  intentionId,
) as ResultSuccess<GraphSnapshot<RelationCounts>>).value.revision;

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink diagnostics,
  List<LongTermRelationId> ids,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 22),
  diagnostics,
  relationIdGenerator: _DeterministicRelationIdGenerator(ids),
);

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  required String title,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id.toCanonicalString(),
        title: title,
        createdAt: DateTime.utc(2026, 9, 22).microsecondsSinceEpoch,
        updatedAt: DateTime.utc(2026, 9, 22).microsecondsSinceEpoch,
      ),
    );

Future<Map<String, Object?>> _storedRelation(
  AppDatabase database,
  LongTermRelationId id,
) async => Map.unmodifiable(
  (await database
          .customSelect(
            'SELECT * FROM long_term_relations WHERE id = ?',
            variables: [Variable<String>(id.toCanonicalString())],
            readsFrom: {database.longTermRelations},
          )
          .getSingle())
      .data,
);

Future<List<Map<String, Object?>>> _storedIntentions(
  AppDatabase database,
) async => [
  for (final row
      in await database.customSelect('SELECT * FROM intentions').get())
    Map<String, Object?>.unmodifiable(row.data),
];

void _expectStableStoredFields(
  Map<String, Object?> stored, {
  required LongTermRelationId relationId,
  required IntentionId sourceId,
  required IntentionId relatedId,
  required int isArchived,
}) {
  expect(stored['creation_sequence'], 1);
  expect(stored['id'], relationId.toCanonicalString());
  expect(stored['source_intention_id'], sourceId.toCanonicalString());
  expect(stored['related_intention_id'], relatedId.toCanonicalString());
  expect(stored['type'], 'need');
  expect(stored['priority'], 2);
  expect(stored['description'], '  Описание\n');
  expect(stored['is_archived'], isArchived);
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw ArgumentError.value(value),
    };

String _uuid(int suffix) =>
    '018f0000-0000-7000-8000-${suffix.toString().padLeft(12, '0')}';

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
    throw StateError('Управляемый отказ диагностики.');
  }
}
