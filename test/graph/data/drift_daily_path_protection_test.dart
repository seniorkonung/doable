import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      InMemoryDiagnosticsSink(),
    );
    for (var number = 1; number <= 5; number++) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, 0, 0, 1, 1)''',
        [_uuid(number), 'Намерение $number'],
      );
    }
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority,
          description, is_archived)
         VALUES (?, ?, ?, 'need', 2, 'Прежнее', 0)''',
      [_uuid(101), _uuid(1), _uuid(2)],
    );
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority,
          description, is_archived)
         VALUES (?, ?, ?, 'can', 2, NULL, 0)''',
      [_uuid(102), _uuid(2), _uuid(3)],
    );
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority,
          description, is_archived)
         VALUES (?, ?, ?, 'need', 2, NULL, 0)''',
      [_uuid(103), _uuid(1), _uuid(4)],
    );
  });

  tearDown(() => database.close());

  void addChoice(int number, {bool completed = false}) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date,
          description, is_completed)
         VALUES (?, ?, ?, '2026-09-23', 'Выбор', ?)''',
      [_uuid(number), _uuid(1), _uuid(3), completed ? 1 : 0],
    );
    raw.execute(
      '''INSERT INTO daily_choice_path_steps
         (id, daily_choice_id, long_term_relation_id, previous_step_id)
         VALUES (?, ?, ?, NULL)''',
      [_uuid(number + 100), _uuid(number), _uuid(101)],
    );
    raw.execute(
      '''INSERT INTO daily_choice_path_steps
         (id, daily_choice_id, long_term_relation_id, previous_step_id)
         VALUES (?, ?, ?, ?)''',
      [_uuid(number + 200), _uuid(number), _uuid(102), _uuid(number + 100)],
    );
  }

  int count(String table) =>
      raw.select('SELECT COUNT(*) AS count FROM $table').single['count'] as int;

  Map<String, Object?> storedRelation(int number) => Map.of(
    raw.select('SELECT * FROM long_term_relations WHERE id = ?', [
      _uuid(number),
    ]).single,
  );

  test(
    'удаление используемой связи возвращает конфликт и сохраняет путь',
    () async {
      addChoice(201, completed: true);

      final result = await repository.execute(
        DeleteLongTermRelation(_relation(101)),
      );

      expect(result, isA<GraphCommandFailed>());
      expect(
        (result as GraphCommandFailed).failure,
        isA<LongTermRelationReferencedByDailyPathFailure>(),
      );
      expect(count('long_term_relations'), 3);
      expect(count('daily_choice_path_steps'), 2);
    },
  );

  test('массовое удаление отклоняет весь набор до первой записи', () async {
    addChoice(201);
    final command = DeleteBlockingRelations(
      intentionId: _intention(1),
      relationIds: [_relation(103), _relation(101)],
    );

    final result = await repository.execute(command);

    expect(result, isA<GraphCommandFailed>());
    final failure = (result as GraphCommandFailed).failure;
    expect(failure, isA<DeleteBlockingRelationsSelectionConflictFailure>());
    expect(
      (failure as DeleteBlockingRelationsSelectionConflictFailure).reason,
      BlockingRelationConflictReason.deletionProhibited,
    );
    expect(count('long_term_relations'), 3);
    expect(count('daily_choice_path_steps'), 2);
  });

  test('составная смена типа или участника отклоняет все поля', () async {
    addChoice(201);
    final before = storedRelation(101);
    final patches = [
      LongTermRelationPatch(
        type: const LongTermRelationFieldSet(LongTermRelationType.can),
        priority: const LongTermRelationFieldSet(RelationPriority.p4),
        description: LongTermRelationDescriptionPatch.fromInput('Новое'),
      ),
      LongTermRelationPatch(
        relatedIntentionId: LongTermRelationFieldSet(_intention(5)),
        priority: const LongTermRelationFieldSet(RelationPriority.p4),
      ),
      LongTermRelationPatch(
        sourceIntentionId: LongTermRelationFieldSet(_intention(5)),
        priority: const LongTermRelationFieldSet(RelationPriority.p4),
      ),
    ];

    for (final patch in patches) {
      final result = await repository.execute(
        UpdateLongTermRelation(relationId: _relation(101), patch: patch),
      );
      expect(result, isA<GraphCommandFailed>());
      expect(
        (result as GraphCommandFailed).failure,
        isA<LongTermRelationReferencedByDailyPathFailure>(),
      );
      expect(storedRelation(101), before);
    }
  });

  test('прежние значения смысла допускают описание и приоритет', () async {
    addChoice(201);

    final result = await repository.execute(
      UpdateLongTermRelation(
        relationId: _relation(101),
        patch: LongTermRelationPatch(
          type: const LongTermRelationFieldSet(LongTermRelationType.need),
          sourceIntentionId: LongTermRelationFieldSet(_intention(1)),
          relatedIntentionId: LongTermRelationFieldSet(_intention(2)),
          priority: const LongTermRelationFieldSet(RelationPriority.p4),
          description: LongTermRelationDescriptionPatch.fromInput('Новое'),
        ),
      ),
    );

    expect(result, isA<GraphCommandSucceeded>());
    expect(storedRelation(101)['priority'], 4);
    expect(storedRelation(101)['description'], 'Новое');
    expect(count('daily_choice_path_steps'), 2);
  });

  test(
    'архивирование промежуточного намерения и готовность сохраняют путь',
    () async {
      addChoice(201);

      expect(
        await repository.execute(ArchiveLongTermRelation(_relation(101))),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(ArchiveIntention(_intention(2))),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(DisableIntentionReadiness(_intention(3))),
        isA<GraphCommandSucceeded>(),
      );

      expect(count('daily_choices'), 1);
      expect(count('daily_choice_path_steps'), 2);
      expect(storedRelation(101)['is_archived'], 1);
      expect(storedRelation(102)['is_archived'], 1);
      expect(
        await repository.execute(RestoreLongTermRelation(_relation(101))),
        isA<GraphCommandFailed>(),
      );
      expect(
        await repository.execute(RestoreIntention(_intention(2))),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(RestoreLongTermRelation(_relation(101))),
        isA<GraphCommandSucceeded>(),
      );
      expect(count('daily_choice_path_steps'), 2);
    },
  );

  test('защита исчезает только после последней ссылки', () async {
    addChoice(201);
    addChoice(202);
    raw.execute('DELETE FROM daily_choices WHERE id = ?', [_uuid(201)]);

    final blocked = await repository.execute(
      DeleteLongTermRelation(_relation(101)),
    );
    expect(
      (blocked as GraphCommandFailed).failure.category,
      GraphFailureCategory.conflict,
    );
    raw.execute('DELETE FROM daily_choices WHERE id = ?', [_uuid(202)]);

    expect(
      await repository.execute(DeleteLongTermRelation(_relation(101))),
      isA<GraphCommandSucceeded>(),
    );
    expect(count('daily_choice_path_steps'), 0);
  });

  test('удаление намерения повторно учитывает прямую дневную ссылку', () async {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date, is_completed)
         VALUES (?, ?, ?, '2026-09-23', 0)''',
      [_uuid(201), _uuid(1), _uuid(3)],
    );
    raw.execute('DELETE FROM long_term_relations');

    final result = await repository.execute(DeleteIntention(_intention(1)));

    expect(result, isA<GraphCommandFailed>());
    expect(
      (result as GraphCommandFailed).failure,
      isA<IntentionHasBlockingRelationsFailure>(),
    );
    expect(count('intentions'), 5);
    expect(count('daily_choices'), 1);
  });
}
