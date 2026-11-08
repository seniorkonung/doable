import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/intention_cascade_execution.dart';

void main() {
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late DateTime clock;
  late IntentionId sourceId;
  late IntentionId relatedId;
  late IntentionId thirdId;
  late IntentionId fourthId;
  late LongTermRelationId relationId;
  late LongTermRelationId secondRelationId;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    clock = DateTime.utc(2026, 9, 22, 10);
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
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => clock,
      InMemoryDiagnosticsSink(),
      relationIdGenerator: _DeterministicRelationIdGenerator([
        relationId,
        secondRelationId,
        _relationId(_uuid(103)),
      ]),
    );
  });

  tearDown(() => database.close());

  test('создание пишет в оба столбца одно показание часов команды', () async {
    clock = DateTime.utc(2026, 9, 23, 8, 30, 15, 123, 456);

    await _create(repository, sourceId, relatedId);

    final stored = await _timestamps(database, relationId);
    expect(stored.createdAt, clock.microsecondsSinceEpoch);
    expect(stored.updatedAt, clock.microsecondsSinceEpoch);
  });

  test(
    'изменение типа, приоритета и описания обновляет только updated_at',
    () async {
      final createdAt = clock;
      await _create(repository, sourceId, relatedId);
      final patches = <LongTermRelationPatch>[
        const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
        ),
        const LongTermRelationPatch(
          priority: LongTermRelationFieldSet(RelationPriority.p1),
        ),
        LongTermRelationPatch(
          description: LongTermRelationDescriptionReplaced(
            LongTermRelationDescription.fromInput('Новое описание')!,
          ),
        ),
      ];

      for (final (index, patch) in patches.indexed) {
        clock = DateTime.utc(2026, 9, 24, index + 1);
        await _expectSucceeded(
          repository.execute(
            UpdateLongTermRelation(relationId: relationId, patch: patch),
          ),
        );

        final stored = await _timestamps(database, relationId);
        expect(stored.createdAt, createdAt.microsecondsSinceEpoch);
        expect(stored.updatedAt, clock.microsecondsSinceEpoch);
      }
    },
  );

  test('архивирование и восстановление обновляют только updated_at', () async {
    final createdAt = clock;
    await _create(repository, sourceId, relatedId);

    clock = DateTime.utc(2026, 9, 24);
    await _expectSucceeded(
      repository.execute(
        await previewedArchiveRelation(repository, relationId),
      ),
    );
    var stored = await _timestamps(database, relationId);
    expect(stored.createdAt, createdAt.microsecondsSinceEpoch);
    expect(stored.updatedAt, clock.microsecondsSinceEpoch);

    clock = DateTime.utc(2026, 9, 25);
    await _expectSucceeded(
      repository.execute(
        await previewedRestoreRelation(repository, relationId),
      ),
    );
    stored = await _timestamps(database, relationId);
    expect(stored.createdAt, createdAt.microsecondsSinceEpoch);
    expect(stored.updatedAt, clock.microsecondsSinceEpoch);
  });

  test('повтор прежнего значения показаний не меняет', () async {
    await _create(repository, sourceId, relatedId, description: 'Описание');
    final before = await _timestamps(database, relationId);
    clock = DateTime.utc(2026, 9, 24);

    await _expectSucceeded(
      repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: LongTermRelationPatch(
            type: const LongTermRelationFieldSet(LongTermRelationType.need),
            priority: const LongTermRelationFieldSet(RelationPriority.p4),
            description: LongTermRelationDescriptionReplaced(
              LongTermRelationDescription.fromInput('Описание')!,
            ),
          ),
        ),
      ),
    );
    await _expectSucceeded(
      repository.execute(givenRestoreRelation(relationId)),
    );
    await _expectSucceeded(
      repository.execute(
        await previewedArchiveRelation(repository, relationId),
      ),
    );
    final archived = await _timestamps(database, relationId);
    clock = DateTime.utc(2026, 9, 25);
    await _expectSucceeded(
      repository.execute(givenArchiveRelation(relationId)),
    );

    expect(archived.createdAt, before.createdAt);
    expect(
      archived.updatedAt,
      DateTime.utc(2026, 9, 24).microsecondsSinceEpoch,
    );
    expect(await _timestamps(database, relationId), archived);
  });

  test('результаты команд несут записанные показания времени', () async {
    final createdAt = DateTime.utc(2026, 9, 23, 8, 30, 15, 123, 456);
    clock = createdAt;
    final created = _relationOf(await _create(repository, sourceId, relatedId));
    expect(created.createdAt, RelationTimestamp(createdAt));
    expect(created.updatedAt, RelationTimestamp(createdAt));

    clock = DateTime.utc(2026, 9, 24, 9, 1, 2, 3, 4);
    final updated = _updatedOf(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            priority: LongTermRelationFieldSet(RelationPriority.p1),
          ),
        ),
      ),
    );
    expect(updated.before.updatedAt, RelationTimestamp(createdAt));
    expect(updated.relation.createdAt, RelationTimestamp(createdAt));
    expect(updated.relation.updatedAt, RelationTimestamp(clock));

    final archivedAt = clock = DateTime.utc(2026, 9, 25, 10);
    final archived = _updatedOf(
      await repository.execute(
        await previewedArchiveRelation(repository, relationId),
      ),
    );
    expect(archived.relation.createdAt, RelationTimestamp(createdAt));
    expect(archived.relation.updatedAt, RelationTimestamp(archivedAt));

    clock = DateTime.utc(2026, 9, 26, 11);
    final restored = _updatedOf(
      await repository.execute(
        await previewedRestoreRelation(repository, relationId),
      ),
    );
    expect(restored.before.updatedAt, RelationTimestamp(archivedAt));
    expect(restored.relation.createdAt, RelationTimestamp(createdAt));
    expect(restored.relation.updatedAt, RelationTimestamp(clock));
  });

  test('повтор значений возвращает показания без изменения', () async {
    clock = DateTime.utc(2026, 9, 23);
    await _create(repository, sourceId, relatedId);
    clock = DateTime.utc(2026, 9, 24);

    final repeated = _updatedOf(
      await repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            type: LongTermRelationFieldSet(LongTermRelationType.need),
            priority: LongTermRelationFieldSet(RelationPriority.p4),
          ),
        ),
      ),
    );
    final repeatedArchive = _updatedOf(
      await repository.execute(givenRestoreRelation(relationId)),
    );

    for (final result in [repeated, repeatedArchive]) {
      expect(
        result.relation.createdAt,
        RelationTimestamp(DateTime.utc(2026, 9, 23)),
      );
      expect(
        result.relation.updatedAt,
        RelationTimestamp(DateTime.utc(2026, 9, 23)),
      );
      expect(result.changes.single, isA<LongTermRelationUnchangedChange>());
    }
  });

  test('отклонённая операция показаний не меняет', () async {
    await _create(repository, sourceId, relatedId);
    await repository.execute(
      await previewedArchiveRelation(repository, relationId),
    );
    final before = await _timestamps(database, relationId);
    clock = DateTime.utc(2026, 9, 24);

    final archivedTypeChange = await repository.execute(
      UpdateLongTermRelation(
        relationId: relationId,
        patch: const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
          priority: LongTermRelationFieldSet(RelationPriority.p1),
        ),
      ),
    );
    final occupiedPair = await repository.execute(
      AddLongTermRelations(
        pageIntentionId: sourceId,
        group: IntentionRelationGroup.canUse,
        candidateIds: [relatedId],
      ),
    );
    // Восстановление связи теперь вернуло бы и архивированного участника.
    final staleRestore = await previewedRestoreRelation(repository, relationId);
    await repository.execute(
      await previewedArchiveIntention(repository, sourceId),
    );
    final compositionConflict = await repository.execute(staleRestore);

    expect(archivedTypeChange, isA<GraphCommandFailed>());
    expect(occupiedPair, isA<GraphCommandFailed>());
    expect(compositionConflict, isA<GraphCommandFailed>());
    expect(await _timestamps(database, relationId), before);
  });

  test('каскад обновляет updated_at только у архивируемых связей тем же показанием, что у намерения', () async {
    final createdAt = clock;
    await _create(repository, sourceId, relatedId);
    clock = DateTime.utc(2026, 9, 22, 11);
    await _create(repository, thirdId, fourthId);
    clock = DateTime.utc(2026, 9, 22, 12);
    await _create(repository, sourceId, thirdId);
    clock = DateTime.utc(2026, 9, 22, 13);
    await repository.execute(
      await previewedArchiveRelation(repository, _relationId(_uuid(103))),
    );
    final alreadyArchived = await _timestamps(
      database,
      _relationId(_uuid(103)),
    );
    final otherRelation = await _timestamps(database, secondRelationId);

    clock = DateTime.utc(2026, 9, 25, 7, 45, 12, 345, 678);
    await _expectSucceeded(
      repository.execute(await previewedArchiveIntention(repository, sourceId)),
    );

    final cascaded = await _timestamps(database, relationId);
    expect(cascaded.createdAt, createdAt.microsecondsSinceEpoch);
    expect(cascaded.updatedAt, clock.microsecondsSinceEpoch);
    expect(await _intentionUpdatedAt(database, sourceId), cascaded.updatedAt);
    expect(
      await _timestamps(database, _relationId(_uuid(103))),
      alreadyArchived,
    );
    expect(await _timestamps(database, secondRelationId), otherRelation);
  });

  for (final choice in CascadeChoice.values) {
    test('каскадное архивирование варианта ${choice.name} пишет одно показание '
        'часов в каждую изменённую строку и не меняет остальные', () async {
      // 1 главное → 2 вспомогательное → 3 вспомогательное, которое удерживает
      // и главное 4. Связь 4 → 2 архивирована раньше.
      await seedGraph(database, () async {
        await database.customStatement(
          '''UPDATE intentions SET kind = 'supporting' WHERE id IN (?, ?)''',
          [relatedId.toCanonicalString(), thirdId.toCanonicalString()],
        );
        for (final (number, source, related, archived) in [
          (201, sourceId, relatedId, 0),
          (202, relatedId, thirdId, 0),
          (203, fourthId, thirdId, 0),
          (204, fourthId, relatedId, 1),
        ]) {
          await database.customStatement(
            '''INSERT INTO long_term_relations
               (id, source_intention_id, related_intention_id,
                type, priority, is_archived, created_at, updated_at)
               VALUES (?, ?, ?, 'need', 2, ?, 5, 5)''',
            [
              _uuid(number),
              source.toCanonicalString(),
              related.toCanonicalString(),
              archived,
            ],
          );
        }
      });
      final intentionsBefore = {
        for (final id in [sourceId, relatedId, thirdId, fourthId])
          id: await _intentionUpdatedAt(database, id),
      };
      final preview = await repository.previewCurrentCascade(
        IntentionCascadeSubject(sourceId),
        CascadeOperation.archive,
      ) as ArchiveCascadePreview;
      clock = DateTime.utc(2026, 9, 26, 6, 5, 4, 3, 2);

      await _expectSucceeded(
        repository.execute(
          ArchiveIntention(
            sourceId,
            execution: CascadeExecution.of(preview.plan, choice),
          ),
        ),
      );

      final stamped = clock.microsecondsSinceEpoch;
      // При «только это» 2 остаётся активным, но становится главным.
      final changedIntentions = {sourceId, relatedId};
      final changedRelations = switch (choice) {
        CascadeChoice.withSupporting => {201, 202},
        CascadeChoice.onlyThis => {201},
      };
      for (final MapEntry(key: id, value: before) in intentionsBefore.entries) {
        expect(
          await _intentionUpdatedAt(database, id),
          changedIntentions.contains(id) ? stamped : before,
        );
      }
      for (final number in [201, 202, 203, 204]) {
        expect(await _timestamps(database, _relationId(_uuid(number))), (
          createdAt: 5,
          updatedAt: changedRelations.contains(number) ? stamped : 5,
        ), reason: 'Связь $number');
      }
    });
  }

  test('изменение каскада несёт показание часов команды намерения', () async {
    final createdAt = clock;
    await _create(repository, sourceId, relatedId);

    clock = DateTime.utc(2026, 9, 25, 7, 45, 12, 345, 678);
    final result = await repository.execute(
      await previewedArchiveIntention(repository, sourceId),
    );

    final change = _changesOf(result)
        .whereType<LongTermRelationUpdatedChange>()
        .single;
    expect(change.before.updatedAt, RelationTimestamp(createdAt));
    expect(change.after.scope, RelationScope.archived);
    expect(change.after.createdAt, RelationTimestamp(createdAt));
    expect(change.after.updatedAt, RelationTimestamp(clock));
  });

  test('порядок связей в группе не зависит от показаний времени', () async {
    clock = DateTime.utc(2026, 9, 22, 12);
    await _create(repository, sourceId, relatedId);
    clock = DateTime.utc(2026, 9, 22, 8);
    await _create(repository, sourceId, thirdId);
    clock = DateTime.utc(2026, 9, 22, 18);
    await _expectSucceeded(
      repository.execute(
        UpdateLongTermRelation(
          relationId: secondRelationId,
          patch: const LongTermRelationPatch(
            description: LongTermRelationDescriptionCleared(),
          ),
        ),
      ),
    );
    await _expectSucceeded(
      repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            type: LongTermRelationFieldSet(LongTermRelationType.can),
          ),
        ),
      ),
    );
    await _expectSucceeded(
      repository.execute(
        UpdateLongTermRelation(
          relationId: relationId,
          patch: const LongTermRelationPatch(
            type: LongTermRelationFieldSet(LongTermRelationType.need),
          ),
        ),
      ),
    );

    final result = await repository.getRelationGroupPage(
      RelationGroupQuery(
        intentionId: sourceId,
        type: LongTermRelationType.need,
        direction: RelationDirection.outgoing,
        scope: RelationScope.active,
        pageSize: 10,
      ),
    );

    final page =
        (result as RelationGroupPageSuccess).value as RelationGroupFirstPage;
    expect(page.items.map((item) => item.relation.id), [
      relationId,
      secondRelationId,
    ]);
  });
}

Future<LongTermRelationCommandResult> _create(
  DriftPersonalGraphRepository repository,
  IntentionId sourceId,
  IntentionId relatedId, {
  String? description,
}) async {
  final result = await repository.execute(
    AddLongTermRelations(
      pageIntentionId: sourceId,
      group: IntentionRelationGroup.needs,
      candidateIds: [relatedId],
    ),
  );
  expect(result, isA<GraphCommandSucceeded>());
  if (description != null) {
    await _expectSucceeded(
      repository.execute(
        UpdateLongTermRelation(
          relationId: _relationOf(result).id,
          patch: LongTermRelationPatch(
            description: LongTermRelationDescriptionPatch.fromInput(
              description,
            ),
          ),
        ),
      ),
    );
  }
  return result;
}

LongTermRelation _relationOf(LongTermRelationCommandResult result) =>
    switch (result) {
      GraphResultSuccess(:final value) =>
        (value.value as LongTermRelationsAdded).relations.single,
      GraphResultFailure() => throw TestFailure('Команда связи отклонена'),
    };

LongTermRelationUpdated _updatedOf(LongTermRelationCommandResult result) =>
    switch (result) {
      GraphResultSuccess(:final value) =>
        value.value as LongTermRelationUpdated,
      GraphResultFailure() => throw TestFailure('Команда связи отклонена'),
    };

Iterable<GraphChange> _changesOf<
  T extends GraphCommandOutcome,
  F extends GraphCommandFailure
>(GraphCommandResult<T, F> result) => switch (result) {
  GraphResultSuccess(:final value) => value.value.changes,
  GraphResultFailure() => throw TestFailure('Команда отклонена'),
};

Future<void> _expectSucceeded(Future<GraphCommandResult> result) async {
  expect(await result, isA<GraphCommandSucceeded>());
}

typedef _Timestamps = ({int createdAt, int updatedAt});

Future<_Timestamps> _timestamps(
  AppDatabase database,
  LongTermRelationId id,
) async {
  final row = await database
      .customSelect(
        'SELECT created_at, updated_at FROM long_term_relations WHERE id = ?',
        variables: [Variable<String>(id.toCanonicalString())],
        readsFrom: {database.longTermRelations},
      )
      .getSingle();
  return (
    createdAt: row.data['created_at']! as int,
    updatedAt: row.data['updated_at']! as int,
  );
}

Future<int> _intentionUpdatedAt(AppDatabase database, IntentionId id) async {
  final row = await database
      .customSelect(
        'SELECT updated_at FROM intentions WHERE id = ?',
        variables: [Variable<String>(id.toCanonicalString())],
        readsFrom: {database.intentions},
      )
      .getSingle();
  return row.data['updated_at']! as int;
}

Future<void> _insertIntention(
  AppDatabase database,
  IntentionId id, {
  required String title,
}) => seedGraph(
  database,
  () => database
      .into(database.intentions)
      .insert(
        IntentionsCompanion.insert(
          id: id.toCanonicalString(),
          title: title,
          createdAt: DateTime.utc(2026, 9, 22).microsecondsSinceEpoch,
          updatedAt: DateTime.utc(2026, 9, 22).microsecondsSinceEpoch,
        ),
      ),
);

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
