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
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_seed.dart';
import '../../support/graph_durability_fixture.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

/// Основной граф проверок: главные «Быть здоровым» (1), «Высыпаться» (4) и
/// «Сходить в поход» (5), вспомогательные «Много ходить» (2) и «Хорошая
/// обувь» (3). Связи «нужно»: 101 (1 → 2), 102 (2 → 3), 103 (2 → 4),
/// 104 (5 → 3). Все строки созданы и изменены показанием 1.
const _baseIntentions = [
  (1, 'main', 0),
  (2, 'supporting', 0),
  (3, 'supporting', 0),
  (4, 'main', 0),
  (5, 'main', 0),
];
const _baseRelations = [
  (101, 1, 2, 0),
  (102, 2, 3, 0),
  (103, 2, 4, 0),
  (104, 5, 3, 0),
];

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late DateTime now;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    database = await harness.openReadyDatabase();
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

  /// Записывает намерения (номер, вид, архив) и связи «нужно» (номер,
  /// источник, связанное, архив) и действие с путём [path], если он задан.
  Future<void> seed({
    List<(int, String, int)> intentions = _baseIntentions,
    List<(int, int, int, int)> relations = _baseRelations,
    List<int>? path,
  }) => seedGraph(database, () async {
    for (final (number, kind, archived) in intentions) {
      await database.customStatement(
        '''INSERT INTO intentions
           (id, title, kind, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, ?, 1, 1)''',
        [durabilityUuid(number), 'Намерение $number', kind, archived],
      );
    }
    for (final (number, source, related, archived) in relations) {
      await database.customStatement(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id,
            type, priority, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 'need', 2, ?, 1, 1)''',
        [
          durabilityUuid(number),
          durabilityUuid(source),
          durabilityUuid(related),
          archived,
        ],
      );
    }
    if (path != null) {
      await insertAction(
        database,
        id: durabilityUuid(201),
        path: [for (final number in path) durabilityUuid(number)],
      );
      await database.customStatement('UPDATE actions SET is_completed = 1');
    }
  });

  Future<CascadePlan<DeleteCascadeComposition>> deletePlan(
    CascadeSubject subject,
  ) async {
    final preview = await repository.previewCurrentCascade(
      subject,
      CascadeOperation.delete,
    );
    expect(preview, isA<CascadePreview<DeleteCascadeComposition>>());
    return (preview as CascadePreview<DeleteCascadeComposition>).plan;
  }

  Future<DeleteIntention> deleteIntention(
    int number, {
    CascadeChoice choice = CascadeChoice.withSupporting,
  }) async => DeleteIntention(
    durabilityIntention(number),
    execution: _execution(
      await deletePlan(IntentionCascadeSubject(durabilityIntention(number))),
      choice,
    ),
  );

  Future<DeleteLongTermRelation> deleteRelation(
    int number, {
    CascadeChoice choice = CascadeChoice.withSupporting,
  }) async => DeleteLongTermRelation(
    durabilityRelation(number),
    execution: _execution(
      await deletePlan(RelationCascadeSubject(durabilityRelation(number))),
      choice,
    ),
  );

  Future<ConfirmedGraphResult<GraphCommandOutcome>> confirm(
    GraphCommand<GraphCommandOutcome, GraphCommandFailure> command,
  ) async {
    final result = await repository.execute(command);
    expect(result, isA<GraphCommandSucceeded>());
    return (result as GraphCommandSucceeded).value;
  }

  test('каскад удаляет предмет и неудерживаемые вспомогательные со всеми '
      'связями, а удерживаемое и главное остаются без изменений', () async {
    await seed();
    final before = await _graphState(database);

    await confirm(await deleteIntention(1));

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([3, 4, 5]));
    expect(after.relations.keys, [104]);
    for (final unchanged in [3, 4, 5]) {
      expect(after.intentions[unchanged], before.intentions[unchanged]);
    }
    expect(after.relations[104], before.relations[104]);
  });

  test('удаление уносит архивное вспомогательное, до которого ведёт только '
      'архивная связь', () async {
    await seed(
      intentions: [(1, 'main', 0), (2, 'supporting', 0), (3, 'supporting', 1)],
      relations: [(101, 1, 2, 0), (102, 2, 3, 1)],
    );

    await confirm(await deleteIntention(1));

    final after = await _graphState(database);
    expect(after.intentions, isEmpty);
    expect(after.relations, isEmpty);
  });

  test('вспомогательное, удерживаемое только архивным главным, уходит в '
      'архив и остаётся вспомогательным', () async {
    await seed(
      intentions: [
        (1, 'main', 0),
        (2, 'supporting', 0),
        (3, 'supporting', 0),
        (5, 'main', 1),
      ],
      relations: [(101, 1, 2, 0), (102, 2, 3, 0), (104, 5, 3, 1)],
    );

    final confirmed = await confirm(await deleteIntention(1));

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([3, 5]));
    expect(after.archivedIntentions, {3, 5});
    expect(after.intentions[3]!.kind, 'supporting');
    expect(after.relations.keys, [104]);
    final executed =
        confirmed.changes.whereType<CascadeOutcome>().single.executed
            as DeleteCascadeComposition;
    expect(executed.departing, [durabilityIntention(2)]);
    expect(executed.archivedByInvariant, [durabilityIntention(3)]);
  });

  test('выбор «только это» делает нижнее вспомогательное главным, не отменяет '
      'архивирование по инварианту и пишет одно показание часов только '
      'затронутым', () async {
    // «Растяжку» (6) кроме «Хорошей обуви» (3) удерживает главное (7).
    await seed(
      intentions: [
        (1, 'main', 0),
        (2, 'supporting', 0),
        (3, 'supporting', 0),
        (5, 'main', 1),
        (6, 'supporting', 0),
        (7, 'main', 0),
      ],
      relations: [
        (101, 1, 2, 0),
        (102, 1, 3, 0),
        (104, 5, 3, 1),
        (105, 3, 6, 0),
        (106, 7, 6, 0),
      ],
    );
    final before = await _graphState(database);
    now = DateTime.utc(2026, 11, 8, 10, 30);
    final changedAt = now.microsecondsSinceEpoch;

    await confirm(await deleteIntention(1, choice: CascadeChoice.onlyThis));

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([2, 3, 5, 6, 7]));
    expect(after.intentions[2], (
      kind: 'main',
      archived: 0,
      updatedAt: changedAt,
    ));
    expect(after.intentions[3], (
      kind: 'supporting',
      archived: 1,
      updatedAt: changedAt,
    ));
    expect(after.relations.keys, unorderedEquals([104, 105, 106]));
    expect(after.relations[105]!.archived, 1);
    expect(after.relations[105]!.updatedAt, changedAt);
    for (final unchanged in [5, 6, 7]) {
      expect(after.intentions[unchanged], before.intentions[unchanged]);
    }
    for (final unchanged in [104, 106]) {
      expect(after.relations[unchanged], before.relations[unchanged]);
    }
  });

  test('связи, действия и теги не блокируют удаление: уходят связи и '
      'назначения, а теги, действие и путь остаются, и путь получает '
      'надгробия', () async {
    // У «Высыпаться» (4) есть активная исходящая связь 107 и архивная
    // входящая 106, и оно входит в путь 1 → 2 → 4.
    await seed(
      relations: [..._baseRelations, (106, 1, 4, 1), (107, 4, 5, 0)],
      path: [1, 2, 4],
    );
    final home = await _createTag(repository, 'Дом');
    final weekend = await _createTag(repository, 'Выходные');
    for (final (tag, number) in [(home, 4), (home, 1), (weekend, 4)]) {
      await confirm(
        AssignTag(tagId: tag, intentionId: durabilityIntention(number)),
      );
    }
    final pathBefore = await _rows(database, 'action_path_items');
    final actionsBefore = await _rows(database, 'actions');
    final plan = await deletePlan(
      IntentionCascadeSubject(durabilityIntention(4)),
    );
    expect(plan.asksQuestion, isFalse);

    await confirm(
      DeleteIntention(
        durabilityIntention(4),
        execution: CascadeExecution.withSupporting(plan),
      ),
    );

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([1, 2, 3, 5]));
    expect(after.relations.keys, unorderedEquals([101, 102, 104]));
    expect(after.archivedIntentions, isEmpty);
    expect(await _rows(database, 'tags'), hasLength(2));
    expect(
      await database
          .customSelect('SELECT tag_id, intention_id FROM tag_assignments')
          .map(
            (row) =>
                (row.read<String>('tag_id'), row.read<String>('intention_id')),
          )
          .get(),
      [(home.toCanonicalString(), durabilityUuid(1))],
    );
    expect(await _rows(database, 'actions'), actionsBefore);
    expect(await _rows(database, 'action_path_items'), pathBefore);
    expect(await _rows(database, 'deleted_intentions'), [
      [durabilityUuid(4), 'Намерение 4'],
    ]);
    expect(await _rows(database, 'deleted_relation_pairs'), [
      [durabilityUuid(2), durabilityUuid(4), 'need'],
    ]);
  });

  test('основная мутация удаления описывает предмет, даже если '
      'вспомогательное создано раньше', () async {
    await seed(
      intentions: [(1, 'supporting', 0), (2, 'main', 0)],
      relations: [(101, 2, 1, 0)],
    );

    final confirmed = await confirm(await deleteIntention(2));
    final deleted = confirmed.value as IntentionDeleted;

    expect(deleted.catalogMutation, isA<IntentionCatalogDeleted>());
    expect(deleted.catalogMutation.before!.summary.id, durabilityIntention(2));
    expect(deleted.catalogMutations, hasLength(2));
    final supportingMutation = deleted.catalogMutations.skip(1).single;
    expect(supportingMutation, isA<IntentionCatalogDeleted>());
    expect(supportingMutation.before!.summary.id, durabilityIntention(1));
  });

  test('пакет несёт удаления каталога и связей, абсолютные количества, '
      'изменение удержания и исполненный состав', () async {
    await seed();

    final confirmed = await confirm(await deleteIntention(1));

    expect(
      confirmed.changes.map(
        (change) => change.revision.compareTo(confirmed.revision),
      ),
      everyElement(GraphRevisionOrder.same),
    );
    final deleted = confirmed.value as IntentionDeleted;
    expect(deleted.id, durabilityIntention(1));
    expect(deleted.catalogMutation, isA<IntentionCatalogDeleted>());
    expect(
      deleted.catalogMutations.map(
        (mutation) => _intentionNumber(mutation.before!.summary.id),
      ),
      [1, 2],
    );
    expect(
      deleted.catalogMutations.map((mutation) => mutation.after),
      everyElement(isNull),
    );
    expect(
      confirmed.changes.whereType<LongTermRelationDeletedChange>().map(
        (change) => _relationNumber(change.id),
      ),
      unorderedEquals([101, 102, 103]),
    );
    final counts = {
      for (final change
          in confirmed.changes.whereType<IntentionRelationCountsChanged>())
        _intentionNumber(change.intentionId): change.counts,
    };
    expect(counts.keys, unorderedEquals([3, 4]));
    for (final MapEntry(key: number, value: packaged) in counts.entries) {
      expect(
        _countsKey(packaged),
        _countsKey(await _readCounts(repository, number)),
        reason: 'Абсолютные количества намерения $number',
      );
    }
    expect(_countsKey(counts[3]!), (active: 1, archived: 0));
    expect(_countsKey(counts[4]!), (active: 0, archived: 0));
    expect(
      confirmed.changes.whereType<IntentionHoldingChanged>(),
      hasLength(1),
    );
    final executed =
        confirmed.changes.whereType<CascadeOutcome>().single.executed
            as DeleteCascadeComposition;
    expect(executed.departing, [durabilityIntention(2)]);
    expect(executed.promoted, isEmpty);
    expect(executed.archivedByInvariant, isEmpty);
  });

  test('изменившийся состав даёт конфликт без записи, а повтор по новому '
      'предпросмотру удаляет обновлённый состав', () async {
    await seed();
    final deletion = await deleteIntention(1);
    final relationDeletion = await deleteRelation(101);
    // Теперь «Хорошую обувь» удерживает только «Много ходить», и каскад
    // унёс бы и её.
    await confirm(await deleteRelation(104));
    final before = await _graphState(database);

    final result = await repository.execute(deletion);
    final relationResult = await repository.execute(relationDeletion);

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
      [
        for (final event in diagnostics.events)
          if (event.status case DiagnosticsFailed(:final code)) code,
      ],
      [
        DiagnosticsFailureCode.cascadeConflict,
        DiagnosticsFailureCode.cascadeConflict,
      ],
    );

    await confirm(await deleteIntention(1));
    expect(
      (await _graphState(database)).intentions.keys,
      unorderedEquals([4, 5]),
    );
  });

  test('изменение, не затрагивающее выбранный вариант, не вызывает '
      'конфликта', () async {
    await seed();
    final deletion = await deleteIntention(1, choice: CascadeChoice.onlyThis);
    await confirm(await deleteRelation(104));

    await confirm(deletion);

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([2, 3, 4, 5]));
    expect(after.intentions[2]!.kind, 'main');
    expect(after.intentions[3]!.kind, 'supporting');
    expect(after.archivedIntentions, isEmpty);
  });

  test('удаление связи «со вспомогательными» удаляет связанное намерение со '
      'всеми его связями', () async {
    await seed();

    final confirmed = await confirm(await deleteRelation(101));

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([1, 3, 4, 5]));
    expect(after.relations.keys, [104]);
    final deleted = confirmed.value as LongTermRelationDeleted;
    expect(deleted.relation.id, durabilityRelation(101));
    expect(
      confirmed.changes.whereType<IntentionCatalogDeleted>().map(
        (mutation) => _intentionNumber(mutation.entry.summary.id),
      ),
      [2],
    );
    expect(
      confirmed.changes.whereType<LongTermRelationDeletedChange>().map(
        (change) => _relationNumber(change.id),
      ),
      unorderedEquals([101, 102, 103]),
    );
  });

  test('«Оставить главным» удаляет только связь, а связанное намерение '
      'становится главным со своими связями', () async {
    await seed();

    await confirm(await deleteRelation(101, choice: CascadeChoice.onlyThis));

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([1, 2, 3, 4, 5]));
    expect(after.intentions[2]!.kind, 'main');
    expect(after.relations.keys, unorderedEquals([102, 103, 104]));
  });

  test('удаление связи архивирует связанное намерение, которое удерживает '
      'только архивное главное', () async {
    await seed(
      intentions: [
        (1, 'main', 0),
        (2, 'supporting', 0),
        (3, 'supporting', 0),
        (5, 'main', 1),
      ],
      relations: [(101, 1, 2, 0), (102, 2, 3, 0), (104, 5, 3, 1)],
    );

    await confirm(await deleteRelation(102));

    final after = await _graphState(database);
    expect(after.intentions.keys, unorderedEquals([1, 2, 3, 5]));
    expect(after.archivedIntentions, {3, 5});
    expect(after.intentions[3]!.kind, 'supporting');
    expect(after.relations.keys, unorderedEquals([101, 104]));
  });

  test('архивная связь с архивным участником из пути выполненного действия '
      'удаляется без блокировок, а участники и путь остаются', () async {
    await seed(
      intentions: [(4, 'main', 0), (5, 'main', 1)],
      relations: [(107, 4, 5, 1)],
      path: [4, 5],
    );
    final before = await _graphState(database);
    final pathBefore = await _rows(database, 'action_path_items');

    await confirm(await deleteRelation(107));

    final after = await _graphState(database);
    expect(after.intentions, before.intentions);
    expect(after.relations, isEmpty);
    expect(await _rows(database, 'action_path_items'), pathBefore);
    expect(await _rows(database, 'deleted_relation_pairs'), [
      [durabilityUuid(4), durabilityUuid(5), 'need'],
    ]);
  });

  test('намерение, созданное после построения индекса, удаляется по '
      'предпросмотру без вопроса и конфликта', () async {
    await seed();
    expect(
      await repository.getIntentionHolding({durabilityIntention(2)}),
      isA<IntentionHoldingRead>(),
    );
    final created = await confirm(
      const CreateIntention(title: 'Новое намерение', description: null),
    );
    final id = (created.value as IntentionSaved).intention.id;
    final plan = await deletePlan(IntentionCascadeSubject(id));
    expect(plan.asksQuestion, isFalse);

    final deleted = await confirm(
      DeleteIntention(id, execution: CascadeExecution.withSupporting(plan)),
    );

    expect((deleted.value as IntentionDeleted).id, id);
  });

  test('ошибка записи не оставляет частичного каскада', () async {
    await seed();
    final deletion = await deleteIntention(1);
    final before = await _graphState(database);
    // Связи уже удалены, когда отказывает удаление намерений.
    await database.customStatement('''
      CREATE TEMP TRIGGER fail_intention_delete
      BEFORE DELETE ON intentions
      BEGIN
        SELECT RAISE(ABORT, 'сбой записи');
      END''');

    final result = await repository.execute(deletion);

    expect(result, isA<ResultFailure>());
    expect(await _graphState(database), before);
  });
}

CascadeExecution<DeleteCascadeComposition> _execution(
  CascadePlan<DeleteCascadeComposition> plan,
  CascadeChoice choice,
) => CascadeExecution.of(plan, choice);

int _intentionNumber(IntentionId id) => _numberOf(id.toCanonicalString());

int _relationNumber(LongTermRelationId id) => _numberOf(id.toCanonicalString());

int _numberOf(String canonicalId) =>
    int.parse(canonicalId.split('-').last, radix: 16);

typedef _IntentionRow = ({String kind, int archived, int updatedAt});
typedef _RelationRow = ({int archived, int updatedAt});

/// Сохранённые строки намерений и связей с номерами из идентификаторов.
final class _GraphState {
  _GraphState(this.intentions, this.relations);

  final Map<int, _IntentionRow> intentions;
  final Map<int, _RelationRow> relations;

  Set<int> get archivedIntentions => {
    for (final MapEntry(:key, :value) in intentions.entries)
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
  for (final row
      in await database
          .customSelect(
            'SELECT id, is_archived, updated_at FROM long_term_relations',
          )
          .get()) {
    relations[_numberOf(row.read<String>('id'))] = (
      archived: row.read<int>('is_archived'),
      updatedAt: row.read<int>('updated_at'),
    );
  }
  return _GraphState(intentions, relations);
}

Future<List<List<Object?>>> _rows(AppDatabase database, String table) async => [
  for (final row
      in await database
          .customSelect('SELECT * FROM $table ORDER BY rowid')
          .get())
    row.data.values.toList(),
];

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
