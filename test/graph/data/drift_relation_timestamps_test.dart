import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
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
          priority: LongTermRelationFieldSet(RelationPriority.p4),
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
      repository.execute(ArchiveLongTermRelation(relationId)),
    );
    var stored = await _timestamps(database, relationId);
    expect(stored.createdAt, createdAt.microsecondsSinceEpoch);
    expect(stored.updatedAt, clock.microsecondsSinceEpoch);

    clock = DateTime.utc(2026, 9, 25);
    await _expectSucceeded(
      repository.execute(RestoreLongTermRelation(relationId)),
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
            priority: const LongTermRelationFieldSet(RelationPriority.p2),
            description: LongTermRelationDescriptionReplaced(
              LongTermRelationDescription.fromInput('Описание')!,
            ),
          ),
        ),
      ),
    );
    await _expectSucceeded(
      repository.execute(RestoreLongTermRelation(relationId)),
    );
    await _expectSucceeded(
      repository.execute(ArchiveLongTermRelation(relationId)),
    );
    final archived = await _timestamps(database, relationId);
    clock = DateTime.utc(2026, 9, 25);
    await _expectSucceeded(
      repository.execute(ArchiveLongTermRelation(relationId)),
    );

    expect(archived.createdAt, before.createdAt);
    expect(
      archived.updatedAt,
      DateTime.utc(2026, 9, 24).microsecondsSinceEpoch,
    );
    expect(await _timestamps(database, relationId), archived);
  });

  test('отклонённая операция показаний не меняет', () async {
    await _create(repository, sourceId, relatedId);
    await repository.execute(ArchiveLongTermRelation(relationId));
    final before = await _timestamps(database, relationId);
    clock = DateTime.utc(2026, 9, 24);

    final archivedTypeChange = await repository.execute(
      UpdateLongTermRelation(
        relationId: relationId,
        patch: const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
          priority: LongTermRelationFieldSet(RelationPriority.p4),
        ),
      ),
    );
    final occupiedPair = await repository.execute(
      CreateLongTermRelation(
        sourceIntentionId: sourceId,
        relatedIntentionId: relatedId,
        type: LongTermRelationType.can,
        priority: RelationPriority.p1,
        description: null,
      ),
    );
    await repository.execute(ArchiveIntention(sourceId));
    final archivedParticipant = await repository.execute(
      RestoreLongTermRelation(relationId),
    );

    expect(archivedTypeChange, isA<GraphCommandFailed>());
    expect(occupiedPair, isA<GraphCommandFailed>());
    expect(archivedParticipant, isA<GraphCommandFailed>());
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
    await repository.execute(ArchiveLongTermRelation(_relationId(_uuid(103))));
    final alreadyArchived = await _timestamps(
      database,
      _relationId(_uuid(103)),
    );
    final otherRelation = await _timestamps(database, secondRelationId);

    clock = DateTime.utc(2026, 9, 25, 7, 45, 12, 345, 678);
    await _expectSucceeded(repository.execute(ArchiveIntention(sourceId)));

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

Future<void> _create(
  DriftPersonalGraphRepository repository,
  IntentionId sourceId,
  IntentionId relatedId, {
  String? description,
}) => _expectSucceeded(
  repository.execute(
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
