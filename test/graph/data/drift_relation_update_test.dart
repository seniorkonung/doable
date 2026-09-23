import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
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
      _relationId(_uuid(104)),
    ]);
  });

  tearDown(() => database.close());

  test(
    'частичное изменение сохраняет идентичность, порядок и незапрошенные поля',
    () async {
      await _create(
        repository,
        sourceId,
        relatedId,
        description: '  Прежнее описание\n',
      );
      final intentionsBefore = await _storedIntentions(database);

      final updated = _updated(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: relationId,
            patch: const LongTermRelationPatch(
              priority: LongTermRelationFieldSet(RelationPriority.p4),
            ),
          ),
        ),
      );

      expect(updated.before.id, relationId);
      expect(updated.relation.id, relationId);
      expect(updated.relation.creationSequence.value, 1);
      expect(updated.relation.scope, RelationScope.active);
      expect(updated.relation.type, LongTermRelationType.need);
      expect(updated.relation.sourceIntentionId, sourceId);
      expect(updated.relation.relatedIntentionId, relatedId);
      expect(updated.relation.priority, RelationPriority.p4);
      expect(updated.description?.value, '  Прежнее описание\n');

      final stored = await _storedRelation(database, relationId);
      expect(stored['id'], relationId.toCanonicalString());
      expect(stored['creation_sequence'], 1);
      expect(stored['is_archived'], 0);
      expect(stored['type'], 'need');
      expect(stored['priority'], 4);
      expect(stored['description'], '  Прежнее описание\n');
      expect(await _storedIntentions(database), intentionsBefore);
    },
  );

  test('явная очистка удаляет описание и сохраняет остальные поля', () async {
    await _create(repository, sourceId, relatedId, description: 'Описание');

    final updated = _updated(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            description: LongTermRelationDescriptionCleared(),
          ),
        ),
      ),
    );

    expect(updated.description, isNull);
    expect(updated.relation.type, LongTermRelationType.need);
    expect(updated.relation.priority, RelationPriority.p2);
    expect(updated.relation.sourceIntentionId, sourceId);
    expect(updated.relation.relatedIntentionId, relatedId);
    expect(
      (await _storedRelation(database, relationId))['description'],
      isNull,
    );
  });

  test('одна транзакция заменяет поля и публикует абсолютные количества участников', () async {
    await _create(repository, sourceId, relatedId, description: 'Прежнее');
    final intentionsBefore = await _storedIntentions(database);
    final revisionBefore = await _revision(repository, sourceId);

    final result = _updated(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            type: const LongTermRelationFieldSet(LongTermRelationType.can),
            priority: const LongTermRelationFieldSet(RelationPriority.p1),
            relatedIntentionId: LongTermRelationFieldSet(thirdId),
            description: LongTermRelationDescriptionPatch.fromInput(
              '  Новое описание\n',
            ),
          ),
        ),
      ),
    );

    expect(
      revisionBefore.compareTo(result.changes.first.revision),
      GraphRevisionOrder.older,
    );
    expect(result.before.relatedIntentionId, relatedId);
    expect(result.relation.relatedIntentionId, thirdId);
    expect(result.relation.type, LongTermRelationType.can);
    expect(result.relation.priority, RelationPriority.p1);
    expect(result.description?.value, '  Новое описание\n');
    final relationChange = result.changes
        .whereType<LongTermRelationUpdatedChange>()
        .single;
    expect(relationChange.before.relatedIntentionId, relatedId);
    expect(relationChange.after.relatedIntentionId, thirdId);

    final countChanges = result.changes
        .whereType<IntentionRelationCountsChanged>()
        .toList(growable: false);
    expect(countChanges.map((change) => change.intentionId), {
      sourceId,
      relatedId,
      thirdId,
    });
    expect(
      countChanges
          .singleWhere((change) => change.intentionId == sourceId)
          .counts
          .activeCanOutgoing,
      1,
    );
    expect(
      countChanges
          .singleWhere((change) => change.intentionId == relatedId)
          .counts
          .total,
      0,
    );
    expect(
      countChanges
          .singleWhere((change) => change.intentionId == thirdId)
          .counts
          .activeCanIncoming,
      1,
    );
    expect(await _storedIntentions(database), intentionsBefore);
  });

  test(
    'пустая правка не продвигает ревизию и не инвалидирует чтения',
    () async {
      await _create(repository, sourceId, relatedId);
      final sourceEvents = <Result<GraphSnapshot<IntentionDetails?>>>[];
      final relationEvents = <Object>[];
      final subscriptions = <StreamSubscription<Object>>[
        repository.watchIntention(sourceId).listen(sourceEvents.add),
        repository.watchRelation(relationId).listen(relationEvents.add),
      ];
      await pumpEventQueue(times: 20);
      final revisionBefore = await _revision(repository, sourceId);

      final result = await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(),
        ),
      );
      expect(
        result,
        isA<GraphCommandSucceeded>(),
        reason: switch (result) {
          GraphCommandFailed(:final failure) => failure.runtimeType.toString(),
          GraphCommandSucceeded() => null,
        },
      );
      final updated = _updated(result);
      await pumpEventQueue(times: 20);

      expect(updated.changes, [isA<LongTermRelationUnchangedChange>()]);
      expect(
        revisionBefore.compareTo(await _revision(repository, sourceId)),
        GraphRevisionOrder.same,
      );
      expect(sourceEvents, hasLength(1));
      expect(relationEvents, hasLength(1));
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    },
  );

  test(
    'изменение отсутствующей связи возвращает типизированное отсутствие',
    () async {
      final missingId = _relationId(_uuid(999));
      final revisionBefore = await _revision(repository, sourceId);

      final failure = _failure(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: missingId,
            patch: const LongTermRelationPatch(
              priority: LongTermRelationFieldSet(RelationPriority.p1),
            ),
          ),
        ),
      );

      expect(
        failure,
        isA<LongTermRelationNotFoundFailure>().having(
          (value) => value.relationId,
          'relationId',
          missingId,
        ),
      );
      expect(
        revisionBefore.compareTo(await _revision(repository, sourceId)),
        GraphRevisionOrder.same,
      );
    },
  );

  test('совпавшие итоговые участники отклоняют весь набор правок', () async {
    await _create(repository, sourceId, relatedId, description: 'Прежнее');
    final storedBefore = await _storedRelation(database, relationId);

    final failure = _failure(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(sourceId),
            description: LongTermRelationDescriptionPatch.fromInput('Новое'),
          ),
        ),
      ),
    );

    expect(
      failure,
      isA<LongTermRelationCommandValidationFailure>().having(
        (value) => value.reason,
        'reason',
        CreateLongTermRelationValidationFailure.sameIntention,
      ),
    );
    expect(await _storedRelation(database, relationId), storedBefore);
  });

  test(
    'занятая новая пара возвращает прежнюю связь и откатывает все поля',
    () async {
      await _create(repository, sourceId, relatedId, description: 'Прежнее');
      await _create(repository, sourceId, thirdId);
      final storedBefore = await _storedRelation(database, relationId);

      final failure = _failure(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: relationId,
            patch: LongTermRelationPatch(
              relatedIntentionId: LongTermRelationFieldSet(thirdId),
              type: const LongTermRelationFieldSet(LongTermRelationType.can),
              description: LongTermRelationDescriptionPatch.fromInput('Новое'),
            ),
          ),
        ),
      );

      expect(
        failure,
        isA<LongTermRelationPairOccupiedFailure>().having(
          (value) => value.existingRelationId,
          'existingRelationId',
          secondRelationId,
        ),
      );
      expect(await _storedRelation(database, relationId), storedBefore);
    },
  );

  test('собственная пара исключается из проверки уникальности', () async {
    await _create(repository, sourceId, relatedId);

    final updated = _updated(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            type: LongTermRelationFieldSet(LongTermRelationType.can),
          ),
        ),
      ),
    );

    expect(updated.relation.type, LongTermRelationType.can);
  });

  test(
    'активная связь проверяет существование и архив участников по роли',
    () async {
      await _create(repository, sourceId, relatedId);
      final missingId = _intentionId(_uuid(999));
      await repository.execute(ArchiveIntention(thirdId));

      final missing = _failure(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: relationId,
            patch: LongTermRelationPatch(
              sourceIntentionId: LongTermRelationFieldSet(missingId),
            ),
          ),
        ),
      );
      final archived = _failure(
        await repository.execute(
          UpdateLongTermRelation(
            relationId: relationId,
            patch: LongTermRelationPatch(
              relatedIntentionId: LongTermRelationFieldSet(thirdId),
            ),
          ),
        ),
      );

      expect(
        missing,
        isA<LongTermRelationParticipantNotFoundFailure>()
            .having(
              (value) => value.role,
              'role',
              RelationParticipantRole.source,
            )
            .having((value) => value.intentionId, 'intentionId', missingId),
      );
      expect(
        archived,
        isA<LongTermRelationParticipantArchivedFailure>()
            .having(
              (value) => value.role,
              'role',
              RelationParticipantRole.related,
            )
            .having((value) => value.intentionId, 'intentionId', thirdId),
      );
    },
  );

  test('архивная связь допускает архивированного участника', () async {
    await _create(repository, sourceId, relatedId);
    await (database.update(database.longTermRelations)
          ..where((row) => row.id.equals(relationId.toCanonicalString())))
        .write(const LongTermRelationsCompanion(isArchived: Value(true)));
    await repository.execute(ArchiveIntention(thirdId));

    final updated = _updated(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            sourceIntentionId: LongTermRelationFieldSet(thirdId),
          ),
        ),
      ),
    );

    expect(updated.relation.sourceIntentionId, thirdId);
    expect(updated.relation.scope, RelationScope.archived);
    expect((await _storedIntention(database, thirdId))['is_archived'], 1);
  });

  test('встречная связь и цикл остаются допустимыми после изменения', () async {
    await _create(repository, sourceId, relatedId);
    await _create(repository, relatedId, sourceId);
    final cycleRelationId = _relationId(_uuid(103));
    await _create(repository, relatedId, thirdId);

    final updated = _updated(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: cycleRelationId,
          patch: LongTermRelationPatch(
            sourceIntentionId: LongTermRelationFieldSet(thirdId),
            relatedIntentionId: LongTermRelationFieldSet(sourceId),
          ),
        ),
      ),
    );

    expect(updated.relation.sourceIntentionId, thirdId);
    expect(updated.relation.relatedIntentionId, sourceId);
    expect(
      await database.select(database.longTermRelations).get(),
      hasLength(3),
    );
  });

  test(
    'изменение перед архивированием участника попадает в его каскад',
    () async {
      await _create(repository, sourceId, relatedId);

      final update = repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(thirdId),
          ),
        ),
      );
      final archive = repository.execute(ArchiveIntention(thirdId));

      expect(await update, isA<GraphCommandSucceeded>());
      expect(await archive, isA<ResultSuccess>());
      final stored = await _storedRelation(database, relationId);
      expect(stored['related_intention_id'], thirdId.toCanonicalString());
      expect(stored['is_archived'], 1);
    },
  );

  test(
    'архивирование участника перед изменением отклоняет активную связь',
    () async {
      await _create(repository, sourceId, relatedId);

      final archive = repository.execute(ArchiveIntention(thirdId));
      final update = repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(thirdId),
          ),
        ),
      );

      expect(await archive, isA<ResultSuccess>());
      expect(
        _failure(await update),
        isA<LongTermRelationParticipantArchivedFailure>(),
      );
    },
  );

  test(
    'изменение перед удалением нового участника блокирует удаление',
    () async {
      await _create(repository, sourceId, relatedId);

      final update = repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(thirdId),
          ),
        ),
      );
      final deletion = repository.execute(DeleteIntention(thirdId));

      expect(await update, isA<GraphCommandSucceeded>());
      expect(
        await deletion,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (value) => value.failure,
              'failure',
              isA<IntentionHasBlockingRelationsFailure>(),
            ),
      );
    },
  );

  test(
    'удаление нового участника перед изменением возвращает отсутствие',
    () async {
      await _create(repository, sourceId, relatedId);

      final deletion = repository.execute(DeleteIntention(thirdId));
      final update = repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(thirdId),
          ),
        ),
      );

      expect(await deletion, isA<ResultSuccess>());
      expect(
        _failure(await update),
        isA<LongTermRelationParticipantNotFoundFailure>(),
      );
    },
  );

  test(
    'последовательное занятие пары оставляет ровно один подтверждённый исход',
    () async {
      await _create(repository, sourceId, relatedId);

      final update = repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            relatedIntentionId: LongTermRelationFieldSet(thirdId),
          ),
        ),
      );
      final creation = repository.execute(_createCommand(sourceId, thirdId));

      expect(await update, isA<GraphCommandSucceeded>());
      expect(
        _failure(await creation),
        isA<LongTermRelationPairOccupiedFailure>().having(
          (value) => value.existingRelationId,
          'existingRelationId',
          relationId,
        ),
      );
      expect(
        await database.select(database.longTermRelations).get(),
        hasLength(1),
      );
    },
  );

  test('занятие пары перед изменением отклоняет весь набор правок', () async {
    await _create(repository, sourceId, relatedId);

    final creation = repository.execute(_createCommand(sourceId, thirdId));
    final update = repository.execute(
      UpdateLongTermRelation(
        relationId: relationId,
        patch: LongTermRelationPatch(
          relatedIntentionId: LongTermRelationFieldSet(thirdId),
        ),
      ),
    );

    expect(await creation, isA<GraphCommandSucceeded>());
    expect(
      _failure(await update),
      isA<LongTermRelationPairOccupiedFailure>().having(
        (value) => value.existingRelationId,
        'existingRelationId',
        secondRelationId,
      ),
    );
  });

  test('ошибка записи откатывает изменение и не продвигает ревизию', () async {
    await _create(repository, sourceId, relatedId, description: 'Прежнее');
    final storedBefore = await _storedRelation(database, relationId);
    final revisionBefore = await _revision(repository, sourceId);
    await database.customStatement('''
      CREATE TEMP TRIGGER canary_relation_update_failure
      BEFORE UPDATE ON long_term_relations
      BEGIN
        SELECT RAISE(ABORT, 'canary relation update failure');
      END
    ''');

    final failure = _failure(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            priority: const LongTermRelationFieldSet(RelationPriority.p1),
            description: LongTermRelationDescriptionPatch.fromInput('Новое'),
          ),
        ),
      ),
    );

    expect(failure, isA<LongTermRelationUnexpectedFailure>());
    expect(await _storedRelation(database, relationId), storedBefore);
    expect(
      revisionBefore.compareTo(await _revision(repository, sourceId)),
      GraphRevisionOrder.same,
    );
  });

  test(
    'сбой диагностики после commit не меняет подтверждённый успех',
    () async {
      await _create(repository, sourceId, relatedId);
      final throwingDiagnostics = _ThrowingDiagnosticsSink();
      repository = _repository(database, throwingDiagnostics, const []);

      final result = await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
      );

      expect(result, isA<GraphCommandSucceeded>());
      expect((await _storedRelation(database, relationId))['priority'], 1);
      expect(
        throwingDiagnostics.attemptedEvents,
        everyElement(
          isA<LongTermRelationCommandDiagnosticsEvent>().having(
            (event) => event.commandType,
            'commandType',
            LongTermRelationCommandDiagnosticsType.update,
          ),
        ),
      );
    },
  );

  test('диагностика различает безопасный исход изменения', () async {
    await _create(repository, sourceId, relatedId);

    await repository.execute(
      UpdateLongTermRelation(
        relationId: relationId,
        patch: const LongTermRelationPatch(
          priority: LongTermRelationFieldSet(RelationPriority.p3),
        ),
      ),
    );

    expect(
      diagnostics.events.whereType<LongTermRelationCommandDiagnosticsEvent>(),
      contains(
        isA<LongTermRelationCommandDiagnosticsEvent>()
            .having(
              (event) => event.commandType,
              'commandType',
              LongTermRelationCommandDiagnosticsType.update,
            )
            .having(
              (event) => event.status,
              'status',
              isA<DiagnosticsSucceeded>(),
            ),
      ),
    );
  });
}

Future<LongTermRelationCreated> _create(
  DriftPersonalGraphRepository repository,
  IntentionId sourceId,
  IntentionId relatedId, {
  String? description,
}) async => _created(
  await repository.execute(
    CreateLongTermRelation(
      sourceIntentionId: sourceId,
      relatedIntentionId: relatedId,
      type: LongTermRelationType.need,
      priority: RelationPriority.p2,
      description: description == null
          ? null
          : LongTermRelationDescription.fromInput(description),
    ),
  ),
);

CreateLongTermRelation _createCommand(
  IntentionId sourceId,
  IntentionId relatedId,
) => CreateLongTermRelation(
  sourceIntentionId: sourceId,
  relatedIntentionId: relatedId,
  type: LongTermRelationType.need,
  priority: RelationPriority.p2,
  description: null,
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

LongTermRelationUpdated _updated(LongTermRelationCommandResult result) {
  expect(result, isA<GraphCommandSucceeded>());
  return (result
              as GraphCommandSucceeded<
                LongTermRelationCommandSuccess,
                LongTermRelationCommandFailure
              >)
          .value
          .value
      as LongTermRelationUpdated;
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

Future<List<Map<String, Object?>>> _storedIntentions(
  AppDatabase database,
) async => [
  for (final row
      in await database.customSelect('SELECT * FROM intentions').get())
    Map<String, Object?>.unmodifiable(row.data),
];

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
    throw StateError('CANARY-диагностика');
  }
}
