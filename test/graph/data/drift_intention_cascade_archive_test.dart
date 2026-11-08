import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/graph_durability_fixture.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Граф проверок: главные «Быть здоровым» (1), «Высыпаться» (4) и «Сходить в
/// поход» (5), вспомогательные «Много ходить» (2) и «Хорошая обувь» (3), а
/// вспомогательные «Разминка» (6) и «Растяжка» (7) нужны только друг другу.
/// Связи «нужно»: 101 (1 → 2), 102 (2 → 3), 103 (2 → 4), 104 (5 → 3),
/// 105 (6 → 7), 106 (7 → 6). Все строки созданы показанием 1.
void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late DateTime now;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
    await seedGraph(database, () async {
      for (final (number, kind) in [
        (1, 'main'),
        (2, 'supporting'),
        (3, 'supporting'),
        (4, 'main'),
        (5, 'main'),
        (6, 'supporting'),
        (7, 'supporting'),
      ]) {
        await database.customStatement(
          '''INSERT INTO intentions
             (id, title, kind, is_archived, created_at, updated_at)
             VALUES (?, ?, ?, 0, 1, 1)''',
          [durabilityUuid(number), 'Намерение $number', kind],
        );
      }
      for (final (number, source, related) in [
        (101, 1, 2),
        (102, 2, 3),
        (103, 2, 4),
        (104, 5, 3),
        (105, 6, 7),
        (106, 7, 6),
      ]) {
        await database.customStatement(
          '''INSERT INTO long_term_relations
             (id, source_intention_id, related_intention_id,
              type, priority, description, is_archived,
              created_at, updated_at)
             VALUES (?, ?, ?, 'need', 2, ?, 0, 1, 1)''',
          [
            durabilityUuid(number),
            durabilityUuid(source),
            durabilityUuid(related),
            'Описание $number',
          ],
        );
      }
    });
    diagnostics = InMemoryDiagnosticsSink();
    now = DateTime.utc(2026, 11, 8, 9);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      diagnostics,
    );
  });
  tearDown(() => harness.dispose());

  Future<CascadePlan<ArchiveCascadeComposition>> archivePlan(
    CascadeSubject subject,
  ) async {
    final preview = await repository.previewCurrentCascade(
      subject,
      CascadeOperation.archive,
    );
    expect(preview, isA<ArchiveCascadePreview>());
    return (preview as ArchiveCascadePreview).plan;
  }

  Future<ArchiveIntention> archiveIntention(
    int number, {
    CascadeChoice choice = CascadeChoice.withSupporting,
  }) async {
    final plan = await archivePlan(
      IntentionCascadeSubject(durabilityIntention(number)),
    );
    return ArchiveIntention(
      durabilityIntention(number),
      execution: _execution(plan, choice),
    );
  }

  Future<ArchiveLongTermRelation> archiveRelation(
    int number, {
    CascadeChoice choice = CascadeChoice.withSupporting,
  }) async {
    final plan = await archivePlan(
      RelationCascadeSubject(durabilityRelation(number)),
    );
    return ArchiveLongTermRelation(
      durabilityRelation(number),
      execution: _execution(plan, choice),
    );
  }

  Future<ConfirmedGraphResult<GraphCommandOutcome>> confirm(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    expect(result, isA<GraphCommandSucceeded>());
    return (result as GraphCommandSucceeded).value;
  }

  Future<GraphRevision> currentRevision() async =>
      ((await repository.watchIntention(durabilityIntention(1)).first)
              as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
          .value
          .revision;

  test('каскад уносит только то, что больше не удерживается, и не трогает '
      'неудерживаемые вне каскада', () async {
    final before = await _graphState(database);

    await confirm(await archiveIntention(1));

    final after = await _graphState(database);
    expect(after.archivedIntentions, {1, 2});
    expect(after.archivedRelations, {101, 102, 103});
    expect(after.kinds, before.kinds);
    for (final unchanged in [3, 4, 5, 6, 7]) {
      expect(after.intentions[unchanged], before.intentions[unchanged]);
    }
    for (final unchanged in [104, 105, 106]) {
      expect(after.relations[unchanged], before.relations[unchanged]);
    }
  });

  test('архивирование не учитывает архивное главное намерение', () async {
    await confirm(await archiveIntention(5));
    expect((await _graphState(database)).archivedRelations, {104});

    await confirm(await archiveIntention(1));

    final after = await _graphState(database);
    expect(after.archivedIntentions, {1, 2, 3, 5});
    expect(after.archivedRelations, {101, 102, 103, 104});
  });

  test('выбор «только это» архивирует намерение с его связями и делает '
      'непосредственно нижнее вспомогательное главным', () async {
    await confirm(await archiveIntention(1, choice: CascadeChoice.onlyThis));

    final after = await _graphState(database);
    expect(after.archivedIntentions, {1});
    expect(after.archivedRelations, {101});
    expect(after.kinds[2], 'main');
    expect(after.kinds[3], 'supporting');
  });

  test('вопрос не задаётся, когда другие намерения не затронуты', () async {
    final plan = await archivePlan(
      IntentionCascadeSubject(durabilityIntention(2)),
    );
    expect(plan.asksQuestion, isFalse);

    final confirmed = await confirm(
      ArchiveIntention(
        durabilityIntention(2),
        execution: CascadeExecution.withSupporting(plan),
      ),
    );

    final after = await _graphState(database);
    expect(after.archivedIntentions, {2});
    expect(after.archivedRelations, {101, 102, 103});
    expect(after.kinds[3], 'supporting');
    final outcome = confirmed.changes.whereType<CascadeOutcome>().single;
    expect((outcome.executed as ArchiveCascadeComposition).departing, isEmpty);
    expect(
      (await repository.getIntentionHolding({
        durabilityIntention(3),
      }) as IntentionHoldingRead).holdings.values.single,
      IntentionHolding.held,
    );
  });

  test('пакет несёт изменения связей, мутации каталога, абсолютные '
      'количества, изменение удержания и исполненный состав', () async {
    now = DateTime.utc(2026, 11, 8, 10, 30);
    final command = await archiveIntention(1);

    final confirmed = await confirm(command);

    expect(
      confirmed.changes.map(
        (change) => change.revision.compareTo(confirmed.revision),
      ),
      everyElement(GraphRevisionOrder.same),
    );
    final saved = confirmed.value as IntentionSaved;
    expect(saved.intention.id, durabilityIntention(1));
    expect(saved.intention.archiveState, IntentionArchiveState.archived);
    expect(saved.catalogMutation.after!.summary.id, durabilityIntention(1));
    expect(
      {
        for (final mutation in saved.catalogMutations)
          _intentionNumber(mutation.after!.summary.id): (
            mutation.before!.summary.archiveState,
            mutation.after!.summary.archiveState,
            mutation.after!.summary.kind,
          ),
      },
      {
        1: (
          IntentionArchiveState.active,
          IntentionArchiveState.archived,
          IntentionKind.main,
        ),
        2: (
          IntentionArchiveState.active,
          IntentionArchiveState.archived,
          IntentionKind.supporting,
        ),
      },
    );
    final relationChanges = confirmed.changes
        .whereType<LongTermRelationUpdatedChange>()
        .toList();
    expect(
      relationChanges.map((change) => _relationNumber(change.id)),
      unorderedEquals([101, 102, 103]),
    );
    for (final change in relationChanges) {
      expect(change.before.scope, RelationScope.active);
      expect(change.after.scope, RelationScope.archived);
      expect(change.after.updatedAt, RelationTimestamp(now));
      expect(change.after.type, change.before.type);
      expect(change.after.priority, change.before.priority);
      expect(change.after.creationSequence, change.before.creationSequence);
      expect(change.after.createdAt, change.before.createdAt);
    }
    final counts = {
      for (final change
          in confirmed.changes.whereType<IntentionRelationCountsChanged>())
        _intentionNumber(change.intentionId): change.counts,
    };
    expect(counts.keys, unorderedEquals([1, 2, 3, 4]));
    for (final MapEntry(key: number, value: packaged) in counts.entries) {
      expect(
        _countsKey(packaged),
        _countsKey(await _readCounts(repository, number)),
        reason: 'Абсолютные количества намерения $number',
      );
    }
    expect(_countsKey(counts[3]!), (active: 1, archived: 1));
    expect(_countsKey(counts[4]!), (active: 0, archived: 1));
    expect(
      confirmed.changes.whereType<IntentionHoldingChanged>(),
      hasLength(1),
    );
    final outcome =
        confirmed.changes.whereType<CascadeOutcome>().single.executed
            as ArchiveCascadeComposition;
    expect(outcome.departing, [durabilityIntention(2)]);
    expect(outcome.promoted, isEmpty);
  });

  test('каскад сохраняет разные назначения тегов', () async {
    final home = await _createTag(repository, 'Дом');
    final weekend = await _createTag(repository, 'Выходные');
    await confirm(AssignTag(tagId: home, intentionId: durabilityIntention(1)));
    await confirm(
      AssignTag(tagId: weekend, intentionId: durabilityIntention(2)),
    );

    await confirm(await archiveIntention(1));

    Future<List<int>> archivedWith(TagId tag) async {
      final page = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.archived,
          titleFilter: null,
          tagFilter: IntentionTagFilter(requiredTagIds: [tag]),
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 10,
        ),
      );
      return [
        for (final item
            in (page as ResultSuccess<IntentionCatalogPage>).value.items)
          _intentionNumber(item.id),
      ];
    }

    expect(await archivedWith(home), [1]);
    expect(await archivedWith(weekend), [2]);
  });

  test('самостоятельное архивирование связи между главными сохраняет '
      'намерения и другие связи', () async {
    final addition = await confirm(
      AddLongTermRelations(
        pageIntentionId: durabilityIntention(4),
        group: IntentionRelationGroup.canUse,
        candidateIds: [durabilityIntention(5)],
      ),
    );
    final relationId =
        (addition.value as LongTermRelationsAdded).relations.single.id;
    final added = _relationNumber(relationId);
    final before = await _graphState(database);
    final plan = await archivePlan(RelationCascadeSubject(relationId));
    expect(plan.asksQuestion, isFalse);

    final confirmed = await confirm(
      ArchiveLongTermRelation(
        relationId,
        execution: CascadeExecution.withSupporting(plan),
      ),
    );

    final after = await _graphState(database);
    expect(after.archivedIntentions, isEmpty);
    expect(after.archivedRelations, {added});
    expect(after.intentions, before.intentions);
    final updated = confirmed.value as LongTermRelationUpdated;
    expect(updated.relation.scope, RelationScope.archived);
    expect(updated.relation.type, LongTermRelationType.can);
    expect(updated.relation.creationSequence, updated.before.creationSequence);
  });

  test('архивирование связи «со вспомогательными» уносит связанное '
      'намерение со всеми его связями', () async {
    final confirmed = await confirm(await archiveRelation(101));

    final after = await _graphState(database);
    expect(after.archivedIntentions, {2});
    expect(after.archivedRelations, {101, 102, 103});
    expect(after.relations[101]!.description, 'Описание 101');
    final updated = confirmed.value as LongTermRelationUpdated;
    expect(updated.relation.id, durabilityRelation(101));
    expect(updated.relation.scope, RelationScope.archived);
    expect(
      confirmed.changes.whereType<IntentionCatalogUpdated>().map(
        (mutation) => _intentionNumber(mutation.after.summary.id),
      ),
      [2],
    );
    expect(
      (confirmed.changes.whereType<CascadeOutcome>().single.executed
              as ArchiveCascadeComposition)
          .departing,
      [durabilityIntention(2)],
    );
  });

  test('архивирование связи с выбором «только это» делает связанное '
      'намерение главным', () async {
    await confirm(await archiveRelation(101, choice: CascadeChoice.onlyThis));

    final after = await _graphState(database);
    expect(after.archivedIntentions, isEmpty);
    expect(after.archivedRelations, {101});
    expect(after.kinds[2], 'main');
  });

  test('изменившийся состав даёт конфликт без записи, отличимый в '
      'результате и диагностике', () async {
    final archival = await archiveIntention(1);
    final relationArchival = await archiveRelation(101);
    // Теперь «Хорошую обувь» удерживает только «Много ходить», и каскад
    // унёс бы и её.
    await confirm(await archiveRelation(104));
    final before = await _graphState(database);
    final revision = await currentRevision();

    final result = await repository.execute(archival);
    final relationResult = await repository.execute(relationArchival);

    expect(
      result,
      isA<ResultFailure>().having(
        (failure) => failure.failure,
        'отказ',
        isA<IntentionCascadeConflictFailure>(),
      ),
    );
    expect(
      relationResult,
      isA<GraphCommandFailed>().having(
        (failure) => failure.failure,
        'отказ',
        isA<LongTermRelationCascadeConflictFailure>(),
      ),
    );
    expect(await _graphState(database), before);
    expect(
      (await currentRevision()).compareTo(revision),
      GraphRevisionOrder.same,
    );
    final failures = [
      for (final event in diagnostics.events)
        if (event.status case DiagnosticsFailed(:final code))
          (event.runtimeType, code),
    ];
    expect(failures, [
      (
        IntentionCommandDiagnosticsEvent,
        DiagnosticsFailureCode.cascadeConflict,
      ),
      (
        LongTermRelationCommandDiagnosticsEvent,
        DiagnosticsFailureCode.cascadeConflict,
      ),
    ]);

    await confirm(await archiveIntention(1));
    expect((await _graphState(database)).archivedIntentions, {1, 2, 3});
  });

  test('изменение, не затрагивающее выбранный вариант, не вызывает '
      'конфликта', () async {
    final archival = await archiveIntention(1, choice: CascadeChoice.onlyThis);
    await confirm(await archiveRelation(104));

    await confirm(archival);

    final after = await _graphState(database);
    expect(after.archivedIntentions, {1});
    expect(after.kinds[2], 'main');
    expect(after.kinds[3], 'supporting');
  });

  test('создание связи, не меняющее состав, архивируется вместе с '
      'участником', () async {
    final archival = await archiveIntention(4);
    await confirm(
      AddLongTermRelations(
        pageIntentionId: durabilityIntention(4),
        group: IntentionRelationGroup.needs,
        candidateIds: [durabilityIntention(5)],
      ),
    );

    await confirm(archival);

    expect(
      await database.customSelect(
        '''SELECT 1 FROM long_term_relations AS relation
               JOIN intentions AS intention
                 ON intention.id IN (relation.source_intention_id,
                                     relation.related_intention_id)
               WHERE relation.is_archived = 0 AND intention.is_archived = 1''',
      ).get(),
      isEmpty,
    );
    expect((await _graphState(database)).archivedIntentions, {4});
  });

  test('создание связи, изменившее состав, даёт конфликт архивирования '
      'участника', () async {
    final archival = await archiveIntention(1);
    // «Разминка» и «Растяжка» оказываются ниже «Быть здоровым».
    await confirm(
      AddLongTermRelations(
        pageIntentionId: durabilityIntention(1),
        group: IntentionRelationGroup.needs,
        candidateIds: [durabilityIntention(6)],
      ),
    );
    final before = await _graphState(database);

    final result = await repository.execute(archival);

    expect(
      result,
      isA<ResultFailure>().having(
        (failure) => failure.failure,
        'отказ',
        isA<IntentionCascadeConflictFailure>(),
      ),
    );
    expect(await _graphState(database), before);
  });

  test('намерение, созданное после построения индекса, архивируется по '
      'предпросмотру без вопроса и конфликта', () async {
    expect(
      await repository.getIntentionHolding({durabilityIntention(2)}),
      isA<IntentionHoldingRead>(),
    );
    final created = await confirm(
      const CreateIntention(title: 'Новое намерение', description: null),
    );
    final id = (created.value as IntentionSaved).intention.id;
    final plan = await archivePlan(IntentionCascadeSubject(id));
    expect(plan.asksQuestion, isFalse);

    final archived = await confirm(
      ArchiveIntention(id, execution: CascadeExecution.withSupporting(plan)),
    );

    expect(
      (archived.value as IntentionSaved).intention.archiveState,
      IntentionArchiveState.archived,
    );
  });

  test('ошибка записи не оставляет частичного каскада', () async {
    final archival = await archiveIntention(1);
    final before = await _graphState(database);
    // Связи уже архивированы, когда отказывает запись намерений.
    await database.customStatement('''
      CREATE TEMP TRIGGER fail_intention_archive
      AFTER UPDATE OF is_archived ON intentions
      BEGIN
        SELECT RAISE(ABORT, 'сбой записи');
      END''');

    final result = await repository.execute(archival);

    expect(result, isA<ResultFailure>());
    expect(await _graphState(database), before);
  });
}

CascadeExecution<ArchiveCascadeComposition> _execution(
  CascadePlan<ArchiveCascadeComposition> plan,
  CascadeChoice choice,
) => CascadeExecution(
  choice: choice,
  expected: switch (choice) {
    CascadeChoice.withSupporting => plan.withSupporting,
    CascadeChoice.onlyThis => plan.onlyThis,
  },
);

int _intentionNumber(IntentionId id) => _numberOf(id.toCanonicalString());

int _relationNumber(LongTermRelationId id) => _numberOf(id.toCanonicalString());

int _numberOf(String canonicalId) =>
    int.parse(canonicalId.split('-').last, radix: 16);

typedef _IntentionRow = ({String kind, int archived, int updatedAt});
typedef _RelationRow = ({
  String? description,
  int archived,
  int updatedAt,
  int creationSequence,
});

/// Сохранённые строки намерений и связей с номерами из идентификаторов.
final class _GraphState {
  _GraphState(this.intentions, this.relations);

  final Map<int, _IntentionRow> intentions;
  final Map<int, _RelationRow> relations;

  Map<int, String> get kinds => {
    for (final MapEntry(:key, :value) in intentions.entries) key: value.kind,
  };

  Set<int> get archivedIntentions => {
    for (final MapEntry(:key, :value) in intentions.entries)
      if (value.archived == 1) key,
  };

  Set<int> get archivedRelations => {
    for (final MapEntry(:key, :value) in relations.entries)
      if (value.archived == 1) key,
  };

  @override
  bool operator ==(Object other) =>
      other is _GraphState &&
      _sameMap(intentions, other.intentions) &&
      _sameMap(relations, other.relations);

  @override
  int get hashCode => Object.hash(intentions.length, relations.length);

  @override
  String toString() => '$intentions $relations';
}

bool _sameMap<K, V>(Map<K, V> a, Map<K, V> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

Future<_GraphState> _graphState(AppDatabase database) async {
  final intentions = <int, _IntentionRow>{};
  for (final row
      in await database
          .customSelect(
            'SELECT id, kind, is_archived, updated_at FROM intentions',
          )
          .get()) {
    intentions[_numberOf(row.read<String>('id'))] = (
      kind: row.read<String>('kind'),
      archived: row.read<int>('is_archived'),
      updatedAt: row.read<int>('updated_at'),
    );
  }
  final relations = <int, _RelationRow>{};
  for (final row in await database.customSelect(
    '''SELECT id, description, is_archived, updated_at, creation_sequence
           FROM long_term_relations''',
  ).get()) {
    relations[_numberOf(row.read<String>('id'))] = (
      description: row.readNullable<String>('description'),
      archived: row.read<int>('is_archived'),
      updatedAt: row.read<int>('updated_at'),
      creationSequence: row.read<int>('creation_sequence'),
    );
  }
  return _GraphState(intentions, relations);
}

Future<RelationCounts> _readCounts(
  DriftPersonalGraphRepository repository,
  int number,
) async =>
    ((await repository.watchIntention(durabilityIntention(number)).first)
            as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
        .value
        .value!
        .relationCounts;

({int active, int archived}) _countsKey(RelationCounts counts) =>
    (active: counts.active, archived: counts.archived);

Future<TagId> _createTag(
  DriftPersonalGraphRepository repository,
  String name,
) async {
  final result = await repository.execute(
    CreateTag(
      name: TagName.fromInput(name),
      color: null,
      placement: TagPlacement.first,
    ),
  );
  return ((result as GraphCommandSucceeded).value.value as TagCreated).tag.id;
}
